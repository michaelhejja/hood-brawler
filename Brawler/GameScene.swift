import SwiftUI
import SpriteKit

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
    private let baseAccel: CGFloat = 500        // slow drag: ~1s to full velocity
    private let dragAccelGain: CGFloat = 0.6    // + thumb velocity * gain: a fast flick: ~0.25s
    private let steerDecel: CGFloat = 1200      // thumb still down but pushing less
    private let stopDecel: CGFloat = 2600       // thumb lifted: quick stop
    private let skidDecel: CGFloat = 1100       // thumb lifted at full run: small skid

    let input = InputController()
    private enum Loco { case idle, walk, run }
    private var loco: Loco?
    private var velocity: CGFloat = 0
    private var moveDir = CGVector(dx: 1, dy: 0)
    private var actionUntil: TimeInterval = 0
    // Height axis (pt, pt/s, pt/s²). Height is separate from the lane position, so jumping never moves him in depth.
    private let gravity: CGFloat = 2400
    private let smallJumpVZ: CGFloat = 800      // apex ~133pt, ~0.67s in the air
    private let slamVZ: CGFloat = 1500
    private let airDecel: CGFloat = 250         // momentum carries through the air
    private var vz: CGFloat = 0
    private var airborne = false
    private var falling = false
    private var lastGesture = "-"
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
        debugLabel.position = CGPoint(x: 0, y: size.height / 2 - 40)
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

    override func didMove(to view: SKView) { view.isMultipleTouchEnabled = true }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { if let v = view { input.began(touches, in: v) } }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { if let v = view { input.moved(touches, in: v) } }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { if let v = view { input.ended(touches, in: v) } }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { input.cancelled(touches) }

    /// Placeholder mapping until the move table exists.
    private func handle(_ g: Gesture) {
        let forward: SwipeDirection = hero.facingRight ? .right : .left
        switch g {
        case .swipe(.up):
            lastGesture = "swipe up"
            if !airborne { startJump(vz: smallJumpVZ) }
        case .swipe(.down):
            lastGesture = "swipe down"
            if airborne { vz = -slamVZ; falling = true; hero.play(.fall) }
        case .tap:
            lastGesture = "tap"
            if !airborne { attack() }
        case .swipe(let d) where d == forward:
            lastGesture = "swipe forward"
            if !airborne { attack() }
        case .swipe:
            lastGesture = "swipe back (open)"
        }
    }

    private func attack() {
        hero.speed = 1
        hero.play(.attack)
        actionUntil = lastTime + 0.5
        loco = nil
    }

    private func startJump(vz v: CGFloat) {
        airborne = true; falling = false; vz = v
        hero.speed = 1
        hero.play(.jump)
        loco = nil
    }

    private func stepHeight(_ dt: CGFloat, now: TimeInterval) {
        guard airborne else { return }
        vz -= gravity * dt
        hero.height += vz * dt
        if vz < 0, !falling { falling = true; hero.play(.fall) }
        if hero.height <= 0 {
            hero.height = 0
            airborne = false; falling = false; vz = 0
            hero.play(.land)
            actionUntil = now + 0.15
            loco = nil
        }
    }

    // MARK: Debug overlay

    private func updateDebug() {
        debugLayer.removeAllChildren()
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
        let intensity = input.intensity
        let hasInput = intensity > 0
        if hasInput { moveDir = input.direction }
        let targetSpeed = intensity * runSpeed
        if targetSpeed > velocity {
            // Bigger / faster thumb drags reach full velocity sooner
            velocity = min(targetSpeed, velocity + (baseAccel + input.dragSpeed * dragAccelGain) * d)
        } else {
            let decel = hasInput ? steerDecel : (airborne ? airDecel : (velocity > runSpeed * 0.8 ? skidDecel : stopDecel))
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
            // Simulator keyboard backend: WASD move (Shift = run), arrows = swipes, Space = tap
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(phases: [.down, .up]) { press in
                let input = scene.input
                let ch = press.characters.lowercased().first
                switch (press.key, press.phase) {
                case (.upArrow, .down):    input.fire(.swipe(.up))
                case (.downArrow, .down):  input.fire(.swipe(.down))
                case (.leftArrow, .down):  input.fire(.swipe(.left))
                case (.rightArrow, .down): input.fire(.swipe(.right))
                case (.space, .down):      input.fire(.tap)
                default:
                    guard let ch, "wasd".contains(ch) else { return .ignored }
                    if press.phase == .down { input.keyDown(ch, run: press.modifiers.contains(.shift)) }
                    else { input.keyUp(ch) }
                }
                return .handled
            }
            .overlay(alignment: .topLeading) {
                Button(action: onBack) { Label("Menu", systemImage: "chevron.left") }
                    .buttonStyle(.borderedProminent)
                    .padding()
            }
    }
}
