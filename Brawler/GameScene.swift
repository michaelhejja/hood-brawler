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

    let hero = Fighter(name: "hero", skin: HeroSkin())
    private var enemies: [Fighter] = []

    private let cam = SKCameraNode()
    private let groundHeight: CGFloat = 250
    private let laneMinY: CGFloat = -100      // can walk below the original ground line
    private let laneStartY: CGFloat = 120
    private let verticalFollow: CGFloat = 0.7 // how much of the hero's vertical travel the camera follows
    private var baseCamY: CGFloat { size.height / 2 }
    private var layers: [(node: SKNode, fx: CGFloat, fy: CGFloat, tileW: CGFloat)] = []

    let input = InputController()
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

        hero.rig.scaleFactor = 1.3
        hero.rig.position = CGPoint(x: size.width / 2, y: 120)
        hero.logPrefix = ""
        addChild(hero.rig)

        for (x, y) in [(900, 90), (1150, 170), (1450, 120)] as [(CGFloat, CGFloat)] {
            let e = Fighter(name: "skeleton", skin: SkeletonSkin(), stats: .skeleton)
            if !ProcessInfo.processInfo.arguments.contains("-passive") { e.brain = EnemyBrain() }
            e.rig.scaleFactor = 1.3
            e.rig.facingRight = false
            e.rig.position = CGPoint(x: x, y: y)
            e.rig.zPosition = 300 - y
            enemies.append(e)
            addChild(e.rig)
        }
        hero.rig.zPosition = 300 - hero.rig.position.y

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
        hero.brain = PlayerBrain(input: input, fighter: hero)
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
        if ProcessInfo.processInfo.arguments.contains("-enemylog") {
            for (i, e) in enemies.enumerated() { e.logPrefix = "\(e.name)#\(i): " }
        }
        if ProcessInfo.processInfo.arguments.contains("-dump") { dumpTree(hero.rig) }
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-pose"), i + 1 < args.count, let a = CharacterAnimation(rawValue: args[i + 1]) {
            run(.sequence([.wait(forDuration: 1), .run { [weak self] in   // slow-mo, hero and skeletons side by side
                guard let self else { return }
                for r in ([self.hero] + self.enemies).map(\.rig) {
                    if a == .slam || a == .uppercut { r.height = 150 }
                    r.speed = 0.08; r.play(a)
                }
            }]))
        }
    }

    /// Debug: print every descendant's transform and shape so a refactor can be diffed against a baseline.
    private func dumpTree(_ n: SKNode, depth: Int = 0) {
        for c in n.children {
            var line = String(repeating: " ", count: depth) + "\(type(of: c))"
            line += String(format: " p(%.1f,%.1f) z%.1f r%.3f s(%.2f,%.2f)", c.position.x, c.position.y, c.zPosition, c.zRotation, c.xScale, c.yScale)
            if let sh = c as? SKShapeNode {
                let b = sh.path?.boundingBox ?? .zero
                line += String(format: " box(%.1f,%.1f,%.1f,%.1f) lw%.1f glow%.1f ", b.minX, b.minY, b.width, b.height, sh.lineWidth, sh.glowWidth)
                line += "fill=\(sh.fillColor.cgColor.components ?? []) stroke=\(sh.strokeColor.cgColor.components ?? [])"
            }
            NSLog("DUMP %@", line)
            dumpTree(c, depth: depth + 1)
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
        debugLabel.text = "\(hero.debugState)  speed \(Int(hero.velocity))  h \(Int(hero.rig.height))  |  last: \(hero.lastGesture)"
    }

    // MARK: Loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(currentTime - lastTime, 1.0 / 20)
        lastTime = currentTime

        let bounds = WorldBounds(minX: level.minX + level.heroInset, maxX: level.maxX - level.heroInset,
                                 minY: laneMinY, maxY: groundHeight - 30)
        hero.step(now: currentTime, dt: dt, bounds: bounds, foes: enemies)
        for e in enemies { e.step(now: currentTime, dt: dt, bounds: bounds, foes: [hero]) }
        updateDebug()

        // Camera follows the hero in both axes (vertical is damped so the horizon shifts, not snaps)
        let follow = min(1, CGFloat(dt) * 6)
        let camTargetY = baseCamY + (hero.rig.position.y - laneStartY) * verticalFollow
        let camMinX = level.minX + size.width / 2, camMaxX = max(camMinX, level.maxX - size.width / 2)
        let camTargetX = min(max(hero.rig.position.x, camMinX), camMaxX)
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
