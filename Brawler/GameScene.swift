import SwiftUI
import SpriteKit
import GameController

/// Per-level horizontal bounds. The world spans minX...maxX.
/// The camera stops at the ends, so the hero walks toward the edge instead of staying centered.
struct LevelConfig {
    var minX: CGFloat = 0
    var maxX: CGFloat = 4000
    var heroInset: CGFloat = 40     // how close the hero's origin may get to either world edge
}

final class GameScene: SKScene {
    var level = LevelConfig()

    let hero = CharacterNode()

    private let cam = SKCameraNode()
    private let groundHeight: CGFloat = 250
    private let laneMinY: CGFloat = -100      // can walk below the original ground line
    private let laneStartY: CGFloat = 120
    private let verticalFollow: CGFloat = 0.7 // how much of the hero's vertical travel the camera follows
    private var baseCamY: CGFloat { size.height / 2 }
    private var layers: [(node: SKNode, fx: CGFloat, fy: CGFloat, tileW: CGFloat)] = []

    // Locomotion tuning (pt/s and pt/s²)
    private let runSpeed: CGFloat = 520
    private let baseAccel: CGFloat = 1500       // slow drag: ~0.35s to full speed
    private let dragAccelGain: CGFloat = 1.2    // + thumb speed * gain: a fast flick: ~0.2s
    private let steerDecel: CGFloat = 2400      // thumb still down but pushing less
    private let stopDecel: CGFloat = 3600       // thumb lifted: quick stop
    private let skidDecel: CGFloat = 1800       // thumb lifted at full run: small skid

    let input = InputController()
    private enum Loco { case idle, walk, run }
    private var loco: Loco?
    private var velocity: CGFloat = 0
    private var moveDir = CGVector(dx: 1, dy: 0)
    private var actionUntil: TimeInterval = 0
    // Height axis (pt, pt/s, pt/s²). Height is separate from the lane position, so jumping never moves him in depth.
    private let gravity: CGFloat = 2400
    private let slamVZ: CGFloat = 1500
    private let airDecel: CGFloat = 250         // momentum carries through the air
    private let brakeDecel: CGFloat = 3600
    private var brakeUntil: TimeInterval = 0
    private var current: (move: Move, start: TimeInterval)?
    private var buffered: (gesture: Gesture, time: TimeInterval)?
    private var vz: CGFloat = 0
    private var jump: (height: CGFloat, rise: CGFloat, hang: CGFloat, fall: CGFloat, t: CGFloat)?   // nil = physics (slam)
    private var airborne = false
    private var falling = false
    private var lastGesture = "-" { didSet { NSLog("MOVE %@", lastGesture) } }
    private var lastTime: TimeInterval = 0
    private let debugLayer = SKNode()
    private let debugLabel = SKLabelNode(fontNamed: "Menlo-Bold")

    override init() {
        super.init(size: CGSize(width: 1334, height: 750))
        scaleMode = .aspectFill
        backgroundColor = SKColor(red: 0.55, green: 0.78, blue: 0.85, alpha: 1)
        camera = cam
        cam.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(cam)
        buildWorld()

        hero.scaleFactor = 1.3
        hero.returnsToIdle = false
        hero.position = CGPoint(x: size.width / 2, y: 120)
        addChild(hero)

        for (x, y) in [(900, 90), (1150, 170), (1450, 120)] as [(CGFloat, CGFloat)] {
            let s = SkeletonNode()
            s.setScale(1.3)
            s.face(right: false)
            s.position = CGPoint(x: x, y: y)
            s.zPosition = 300 - y
            addChild(s)
        }
        hero.zPosition = 300 - hero.position.y

        // Debug overlay lives on the camera so it stays on screen
        debugLayer.zPosition = 10_000
        cam.addChild(debugLayer)
        let divider = SKShapeNode(rect: CGRect(x: -1, y: -size.height / 2, width: 2, height: size.height))
        divider.fillColor = .white; divider.strokeColor = .clear; divider.alpha = 0.15
        divider.zPosition = 10_000
        cam.addChild(divider)
        debugLabel.fontSize = 22
        debugLabel.fontColor = .white
        debugLabel.zPosition = 10_001
        cam.addChild(debugLabel)
        input.onGesture = { [weak self] in self?.handle($0) }
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: World

    private func buildWorld() {
        // Far hills
        addLayer(factor: 0.2, tileW: 700, z: -3000) {
            let t = SKNode()
            for (x, w, h) in [(180, 620, 240), (520, 520, 180)] as [(CGFloat, CGFloat, CGFloat)] {
                let hill = styled(SKShapeNode(ellipseOf: CGSize(width: w, height: h)),
                                  SKColor(red: 0.45, green: 0.68, blue: 0.62, alpha: 1))
                hill.position = CGPoint(x: x, y: self.groundHeight + 20)
                t.addChild(hill)
            }
            return t
        }
        // Mid pines
        addLayer(factor: 0.5, tileW: 520, z: -2000) {
            let t = SKNode()
            for (x, s) in [(120, 1.0), (390, 1.4)] as [(CGFloat, CGFloat)] {
                let tree = self.pine()
                tree.position = CGPoint(x: x, y: self.groundHeight - 50)   // sunk so vertical parallax never exposes a gap
                tree.setScale(s)
                t.addChild(tree)
            }
            return t
        }
        // Ground
        addLayer(factor: 1.0, tileW: 400, z: -1000) {
            let t = SKNode()
            for (i, c) in [SKColor(red: 0.20, green: 0.50, blue: 0.48, alpha: 1),
                           SKColor(red: 0.23, green: 0.55, blue: 0.52, alpha: 1)].enumerated() {
                // Extends well below the lane so there's no gap when the camera follows the hero down
                let r = SKShapeNode(rect: CGRect(x: CGFloat(i) * 200, y: -600, width: 200, height: self.groundHeight + 600))
                r.fillColor = c
                r.strokeColor = .clear
                t.addChild(r)
            }
            let edge = SKShapeNode(rect: CGRect(x: -4, y: self.groundHeight - 2, width: 408, height: 4))
            edge.fillColor = ink
            edge.strokeColor = .clear
            t.addChild(edge)
            return t
        }
    }

    private func pine() -> SKNode {
        let tree = SKNode()
        let trunk = styled(SKShapeNode(rect: CGRect(x: -12, y: 0, width: 24, height: 60)),
                           SKColor(red: 0.42, green: 0.28, blue: 0.2, alpha: 1))
        tree.addChild(trunk)
        for (i, w) in [(0, 150), (1, 120), (2, 85)] as [(Int, CGFloat)] {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -w / 2, y: 0))
            p.addLine(to: CGPoint(x: w / 2, y: 0))
            p.addLine(to: CGPoint(x: 0, y: 110))
            p.closeSubpath()
            let layer = styled(SKShapeNode(path: p), SKColor(red: 0.16, green: 0.40, blue: 0.34, alpha: 1))
            layer.position = CGPoint(x: 0, y: 40 + CGFloat(i) * 55)
            tree.addChild(layer)
        }
        return tree
    }

    /// Tiles must be identical (period = tileW) so they loop seamlessly.
    /// fx / fy: 1 = moves with the world (foreground), 0 = pinned to the screen (infinitely far).
    /// fy defaults to fx; set it separately for levels that scroll mostly vertically (e.g. a mountain climb).
    private func addLayer(factor fx: CGFloat, factorY fy: CGFloat? = nil, tileW: CGFloat, z: CGFloat,
                          tile: () -> SKNode) {
        let layer = SKNode()
        layer.zPosition = z
        for i in 0..<(Int(ceil(size.width / tileW)) + 2) {
            let t = tile()
            t.position.x = CGFloat(i) * tileW
            layer.addChild(t)
        }
        addChild(layer)
        layers.append((layer, fx, fy ?? fx, tileW))
    }

    // MARK: Input

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        setupKeyboard()
        if ProcessInfo.processInfo.arguments.contains("-demo") { runDemo() }
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-pose"), i + 1 < args.count, let a = CharacterAnimation(rawValue: args[i + 1]) {
            run(.sequence([.wait(forDuration: 1), .run { [weak self] in if a == .slam || a == .uppercut { self?.hero.height = 150 }; self?.hero.speed = 0.08; self?.hero.play(a) }]))   // slow-mo
        }
    }

    /// Hardware keyboard (Mac keyboard in the simulator). No view focus needed.
    /// WASD = move (Shift = run), arrow keys = swipes, Space = tap.
    private func setupKeyboard() {
        func attach(_ kb: GCKeyboard) {
            kb.keyboardInput?.keyChangedHandler = { [weak self] pad, _, code, down in
                guard let self else { return }
                let shift = (pad.button(forKeyCode: .leftShift)?.isPressed ?? false)
                    || (pad.button(forKeyCode: .rightShift)?.isPressed ?? false)
                let letters: [GCKeyCode: Character] = [.keyW: "w", .keyA: "a", .keyS: "s", .keyD: "d"]
                if let ch = letters[code] {
                    if down { self.input.keyDown(ch, run: shift) } else { self.input.keyUp(ch) }
                    return
                }
                guard down else { return }
                switch code {
                case .upArrow:    self.input.fire(.swipe(.up))
                case .downArrow:  self.input.fire(.swipe(.down))
                case .leftArrow:  self.input.fire(.swipe(.left))
                case .rightArrow: self.input.fire(.swipe(.right))
                case .spacebar:   self.input.fire(.tap)
                default: break
                }
            }
        }
        if let kb = GCKeyboard.coalesced { attach(kb) }
        NotificationCenter.default.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { n in
            if let kb = n.object as? GCKeyboard { attach(kb) }
        }
    }

    /// Launch with `-demo` to play a scripted input sequence (no touch needed). Exercises every move-table context.
    private func runDemo() {
        func fire(_ g: Gesture) -> SKAction { .run { [weak self] in self?.input.fire(g) } }
        func hold(run: Bool) -> SKAction { .run { [weak self] in self?.input.keyDown("d", run: run) } }
        let release = SKAction.run { [weak self] in self?.input.keyUp("d") }
        run(.sequence([
            .wait(forDuration: 1),
            fire(.tap), .wait(forDuration: 0.8),                       // grounded tap
            fire(.swipe(.right)), .wait(forDuration: 0.8),             // grounded forward
            fire(.swipe(.left)), .wait(forDuration: 0.5),              // grounded back (open: nothing)
            fire(.swipe(.down)), .wait(forDuration: 0.5),              // grounded down
            fire(.swipe(.up)), .wait(forDuration: 1.0),                // small jump
            hold(run: true), .wait(forDuration: 1.8),                  // build up to a full run
            fire(.tap), .wait(forDuration: 0.7),                       // running tap
            fire(.swipe(.right)), .wait(forDuration: 0.7),             // running forward
            fire(.swipe(.up)), .wait(forDuration: 0.25),               // big jump
            fire(.swipe(.down)), .wait(forDuration: 1.0),              // air slam
            hold(run: true), .wait(forDuration: 1.8),
            fire(.swipe(.left)), .wait(forDuration: 0.6),              // running back: skid
            release, .wait(forDuration: 1.2),                          // stand still before the combo tests
            fire(.tap), .wait(forDuration: 0.2),                       // COMBO: punch ...
            fire(.tap), .wait(forDuration: 0.2),                       // ... punch 2 ...
            fire(.swipe(.up)), .wait(forDuration: 0.3),                // ... uppercut ...
            fire(.swipe(.down)), .wait(forDuration: 1.2),              // ... air slam (airborne)
            fire(.tap), .wait(forDuration: 0.05),                      // EARLY: arrives before the cancel point ...
            fire(.tap), .wait(forDuration: 1.0),                       // ... buffered, fires as punch 2
            fire(.tap), .wait(forDuration: 0.9),                       // EXPIRED: window closes before the next tap ...
            fire(.tap), .wait(forDuration: 1.0),                       // ... so this is a fresh punch, not punch 2
            hold(run: true), .wait(forDuration: 1.8),
            fire(.swipe(.right)), .wait(forDuration: 0.2),             // COMBO: power dash ...
            fire(.swipe(.down)), .wait(forDuration: 1.2),              // ... ground smash
            fire(.swipe(.right)), .wait(forDuration: 0.2),             // running power dash ...
            fire(.swipe(.up)), .wait(forDuration: 1.2),                // ... uppercut (new)
            release, .wait(forDuration: 1.2),
            fire(.swipe(.right)), .wait(forDuration: 0.2),             // standing heavy attack ...
            fire(.swipe(.up)), .wait(forDuration: 1.2),                // ... uppercut (new)
            release, .wait(forDuration: 1.2),
            fire(.swipe(.up)), .wait(forDuration: 0.3),                // jump, into the hang
            fire(.swipe(.down)), .wait(forDuration: 0.3),              // air slam; lands during this wait
            fire(.swipe(.right)), .wait(forDuration: 1.2),             // forward in the cooldown -> power dash
            fire(.swipe(.up)), .wait(forDuration: 0.3),
            fire(.swipe(.down)), .wait(forDuration: 0.03),             // slam ...
            fire(.swipe(.right)), .wait(forDuration: 1.2),             // ... forward mashed mid-dive: buffered, chains on landing
            release, .wait(forDuration: 1)
        ]))
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { if let v = view { input.began(touches, in: v) } }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { if let v = view { input.moved(touches, in: v) } }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { if let v = view { input.ended(touches, in: v) } }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { input.cancelled(touches) }

    /// What the hero can do right now. Running = grounded and fast.
    private var context: MoveContext {
        airborne ? .airborne : (velocity > runSpeed * 0.7 ? .running : .grounded)
    }

    private func handle(_ g: Gesture, bufferedAt: TimeInterval? = nil) {
        let trigger = Trigger(g, facingRight: hero.facingRight)
        let ctx = context
        let now = lastTime

        // 1. Combo chain: cuts in early (early cancel), stays open a while after the move ends
        if let cur = current,
           now >= cur.start + cur.move.cancelAt,
           now <= cur.start + cur.move.lock + cur.move.window,
           let next = MoveTable.chain(from: cur.move.name, trigger) {
            lastGesture = "\(trigger.rawValue) [\(ctx.rawValue)] -> \(next.name)  (combo from \(cur.move.name))"
            perform(next)
            return
        }
        // 2. Busy with a move that can't chain: hold the input briefly instead of dropping it
        if airborne, jump == nil {                       // mid-dive: hold the next input for the landing
            if trigger != .down { buffered = (g, bufferedAt ?? now) }
            return
        }
        if !airborne, now < actionUntil {
            buffered = (g, bufferedAt ?? now)
            return
        }
        // 3. Normal context lookup
        guard let move = MoveTable.move(ctx, trigger) else {
            lastGesture = "\(trigger.rawValue) [\(ctx.rawValue)] -> (nothing)"
            return
        }
        lastGesture = "\(trigger.rawValue) [\(ctx.rawValue)] -> \(move.name)"
        perform(move)
    }

    private func perform(_ move: Move) {
        current = (move, lastTime)
        buffered = nil
        if move.lunge > 0 {
            moveDir = CGVector(dx: hero.facingRight ? 1 : -1, dy: 0)
            velocity = max(velocity, move.lunge)
        }
        brakeUntil = move.brake > 0 ? lastTime + move.brake : 0   // any new move cancels a skid / plant
        if move.slam { jump = nil; vz = -slamVZ; falling = true }

        if move.jumpHeight > 0 {
            startJump(move)
        } else if let anim = move.animation {
            hero.speed = 1
            hero.play(anim)
            if !airborne { actionUntil = lastTime + move.lock; loco = nil }
        } else if !airborne {
            actionUntil = lastTime + move.lock     // animation-less move (e.g. pick up) still holds the hero
        }
    }

    private func startJump(_ m: Move) {
        airborne = true; falling = false; vz = 0
        jump = (m.jumpHeight, m.jumpRise, m.jumpHang, m.jumpFall, 0)
        hero.speed = 1
        hero.play(m.animation ?? .jump)
        loco = nil
    }

    /// Strong ease-in-out: ~0 at both ends, steep in the middle.
    private func ease(_ t: CGFloat) -> CGFloat {
        let p = JumpTuning.ease
        let a = pow(t, p), b = pow(1 - t, p)
        return a / (a + b)
    }

    private func stepHeight(_ dt: CGFloat, now: TimeInterval) {
        guard airborne else { return }
        if var j = jump {
            j.t += dt
            if j.t < j.rise {
                hero.height = j.height * ease(j.t / j.rise)
            } else if j.t < j.rise + j.hang {
                // Hang: drifts a touch higher, then settles. The air-slam decision window.
                let h = (j.t - j.rise) / j.hang
                hero.height = j.height + 10 * sin(h * .pi)
            } else {
                if !falling { falling = true; hero.play(.fall) }
                hero.height = j.height * (1 - ease(min(1, (j.t - j.rise - j.hang) / j.fall)))
            }
            jump = j
            if j.t < j.rise + j.hang + j.fall { return }
        } else {
            vz -= gravity * dt
            hero.height += vz * dt
            if hero.height > 0 { return }
        }
        // Landed
        let slammed = (jump == nil)
        hero.height = 0
        airborne = false; falling = false; vz = 0; jump = nil
        if slammed {
            // Cooldown with the combo chain open immediately (see MoveTable.slamLanding)
            let m = MoveTable.slamLanding
            hero.play(.slamLand)
            current = (m, now)
            actionUntil = now + m.lock
            brakeUntil = now + m.lock - 0.05          // feet planted
        } else {
            hero.play(.land)
            actionUntil = now + 0.15
        }
        loco = nil
    }

    // MARK: Debug overlay

    /// Half the visible height in scene units. aspectFill crops the scene on wider screens, so size.height overshoots.
    private var visibleHalfHeight: CGFloat {
        guard let v = view, v.bounds.width > 0, v.bounds.height > 0 else { return size.height / 2 }
        let scale = max(v.bounds.width / size.width, v.bounds.height / size.height)
        return v.bounds.height / scale / 2
    }

    private func updateDebug() {
        debugLayer.removeAllChildren()
        debugLabel.position = CGPoint(x: 0, y: visibleHalfHeight - 56)
        for t in input.debugTouches {
            let o = cam.convert(convertPoint(fromView: t.origin), from: self)
            let c = cam.convert(convertPoint(fromView: t.current), from: self)
            let color: SKColor = t.isLeft ? .cyan : .orange
            let ring = SKShapeNode(circleOfRadius: 40)
            ring.strokeColor = color; ring.lineWidth = 3; ring.fillColor = .clear; ring.alpha = 0.6
            ring.position = o
            let dot = SKShapeNode(circleOfRadius: 16)
            dot.fillColor = color; dot.strokeColor = .clear; dot.alpha = 0.7
            dot.position = c
            debugLayer.addChild(ring); debugLayer.addChild(dot)
        }
        let state = airborne ? "air" : (loco.map { "\($0)" } ?? "action")
        debugLabel.text = "\(state)  speed \(Int(velocity))  h \(Int(hero.height))  |  last: \(lastGesture)"
    }

    // MARK: Loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(currentTime - lastTime, 1.0 / 20)
        lastTime = currentTime
        let d = CGFloat(dt)

        // Momentum locomotion
        input.update(dt: dt)
        let braking = currentTime < brakeUntil
        let intensity = braking ? 0 : input.intensity
        let hasInput = intensity > 0
        if hasInput { moveDir = input.direction }
        let targetSpeed = intensity * runSpeed
        if targetSpeed > velocity {
            // Bigger / faster thumb drags reach full velocity sooner
            velocity = min(targetSpeed, velocity + (baseAccel + input.dragSpeed * dragAccelGain) * d)
        } else {
            let decel = braking ? brakeDecel : hasInput ? steerDecel : (airborne ? airDecel : (velocity > runSpeed * 0.8 ? skidDecel : stopDecel))
            velocity = max(targetSpeed, velocity - decel * d)
        }
        if velocity > 0 {
            hero.position.x = min(max(hero.position.x + moveDir.dx * velocity * d,
                                      level.minX + level.heroInset), level.maxX - level.heroInset)
            hero.position.y = min(max(hero.position.y + moveDir.dy * velocity * d, laneMinY), groundHeight - 30)
            hero.zPosition = 300 - hero.position.y
        }
        if hasInput, abs(input.direction.dx) > 0.25 { hero.facingRight = input.direction.dx > 0 }

        // Locomotion animation (paused while an action plays)
        stepHeight(d, now: currentTime)
        if let b = buffered {
            if currentTime - b.time > ComboTuning.buffer { buffered = nil }
            else { buffered = nil; handle(b.gesture, bufferedAt: b.time) }
        }
        if !airborne, currentTime >= actionUntil {
            let desired: Loco = velocity < 20 ? .idle : (velocity < runSpeed * 0.7 ? .walk : .run)
            if desired != loco {
                loco = desired
                hero.speed = desired == .walk ? 0.6 : 1
                hero.play(desired == .idle ? .idle : .run)
            }
        }
        updateDebug()

        // Camera follows the hero in both axes (vertical is damped so the horizon shifts, not snaps)
        let follow = min(1, CGFloat(dt) * 6)
        let camTargetY = baseCamY + (hero.position.y - laneStartY) * verticalFollow
        let camMinX = level.minX + size.width / 2, camMaxX = max(camMinX, level.maxX - size.width / 2)
        let camTargetX = min(max(hero.position.x, camMinX), camMaxX)
        cam.position.x += (camTargetX - cam.position.x) * follow
        cam.position.y += (camTargetY - cam.position.y) * follow

        // Parallax: horizontal layers tile and wrap; vertical offset is a simple scaled shift
        for l in layers {
            var m = (cam.position.x * l.fx).truncatingRemainder(dividingBy: l.tileW)
            if m < 0 { m += l.tileW }
            l.node.position.x = cam.position.x - size.width / 2 - m
            l.node.position.y = (cam.position.y - baseCamY) * (1 - l.fy)
        }
    }
}

struct GameView: View {
    let onBack: () -> Void
    @State private var scene = GameScene()

    var body: some View {
        SpriteView(scene: scene, debugOptions: [.showsFPS, .showsNodeCount])
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) {
                Button(action: onBack) { Label("Menu", systemImage: "chevron.left") }
                    .buttonStyle(.borderedProminent)
                    .padding()
            }
    }
}
