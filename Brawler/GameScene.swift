import SwiftUI
import SpriteKit

final class GameScene: SKScene {
    let hero = CharacterNode()

    private let cam = SKCameraNode()
    private let groundHeight: CGFloat = 250
    private let laneMinY: CGFloat = 30
    private let moveSpeed: CGFloat = 320
    private var layers: [(node: SKNode, factor: CGFloat, tileW: CGFloat)] = []
    private var target: CGPoint?
    private var isMoving = false
    private var lastTime: TimeInterval = 0

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
                tree.position = CGPoint(x: x, y: self.groundHeight - 10)
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
                let r = SKShapeNode(rect: CGRect(x: CGFloat(i) * 200, y: 0, width: 200, height: self.groundHeight))
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
    private func addLayer(factor: CGFloat, tileW: CGFloat, z: CGFloat, tile: () -> SKNode) {
        let layer = SKNode()
        layer.zPosition = z
        for i in 0..<(Int(ceil(size.width / tileW)) + 2) {
            let t = tile()
            t.position.x = CGFloat(i) * tileW
            layer.addChild(t)
        }
        addChild(layer)
        layers.append((layer, factor, tileW))
    }

    // MARK: Placeholder input (TEMP: drag to walk; real touch controls come next)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { setTarget(touches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { setTarget(touches) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { target = nil }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { target = nil }

    private func setTarget(_ touches: Set<UITouch>) {
        guard let p = touches.first?.location(in: self) else { return }
        target = CGPoint(x: p.x, y: min(max(p.y, laneMinY), groundHeight - 30))
    }

    // MARK: Loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(currentTime - lastTime, 1.0 / 20)
        lastTime = currentTime

        var moving = false
        if let t = target {
            let dx = t.x - hero.position.x, dy = t.y - hero.position.y
            let dist = hypot(dx, dy)
            if dist > 10 {
                let step = min(dist, moveSpeed * CGFloat(dt))
                hero.position.x += dx / dist * step
                hero.position.y += dy / dist * step
                hero.zPosition = 300 - hero.position.y
                if abs(dx) > 8, hero.facingRight != (dx > 0) { hero.facingRight = dx > 0 }
                moving = true
            }
        }
        if moving != isMoving {
            isMoving = moving
            hero.play(moving ? .run : .idle)
        }

        // Camera follows the hero horizontally
        let follow = min(1, CGFloat(dt) * 6)
        cam.position.x += (hero.position.x - cam.position.x) * follow

        // Parallax
        for l in layers {
            var m = (cam.position.x * l.factor).truncatingRemainder(dividingBy: l.tileW)
            if m < 0 { m += l.tileW }
            l.node.position.x = cam.position.x - size.width / 2 - m
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
