import SwiftUI
import SpriteKit

final class CharacterVisualizerScene: SKScene {
    let character = HumanoidRig(skin: HeroSkin())
    private let ground = SKShapeNode()

    override init() {
        super.init(size: CGSize(width: 1334, height: 750))
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.55, green: 0.78, blue: 0.85, alpha: 1)
        ground.fillColor = SKColor(red: 0.20, green: 0.50, blue: 0.48, alpha: 1)
        ground.strokeColor = SKColor(red: 0.08, green: 0.06, blue: 0.12, alpha: 1)
        ground.lineWidth = 5
        character.scaleFactor = 1.6
        addChild(ground)
        addChild(character)
        layout()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// The slam needs height: float up, hold the dive, drop, land.
    func play(_ animation: CharacterAnimation) {
        removeAction(forKey: "slam")
        character.height = 0
        if animation == .uppercut {
            let rise = 0.22, hang = 0.26, fall = 0.34, peak: CGFloat = 200
            func ease(_ t: CGFloat) -> CGFloat {
                let a = pow(t, JumpTuning.ease), b = pow(1 - t, JumpTuning.ease)
                return a / (a + b)
            }
            character.play(.uppercut)
            let arc = SKAction.customAction(withDuration: rise + hang + fall) { [weak self] _, elapsed in
                let t = Double(elapsed)
                let h: CGFloat
                if t < rise { h = peak * ease(CGFloat(t / rise)) }
                else if t < rise + hang { h = peak }
                else { h = peak * (1 - ease(CGFloat((t - rise - hang) / fall))) }
                self?.character.height = h
            }
            run(.sequence([
                .group([arc, .sequence([.wait(forDuration: rise + hang), .run { [weak self] in self?.character.play(.fall) }])]),
                .run { [weak self] in self?.character.height = 0; self?.character.play(.land) },
                .wait(forDuration: 0.5),
                .run { [weak self] in self?.character.play(.idle) }]), withKey: "slam")
            return
        }
        guard animation == .slam else { character.play(animation); return }
        character.height = 180
        character.play(.slam)
        let drop = SKAction.customAction(withDuration: 0.25) { [weak self] _, t in
            self?.character.height = 180 * (1 - (t / 0.25) * (t / 0.25))
        }
        run(.sequence([.wait(forDuration: 0.7), drop,
                       .run { [weak self] in self?.character.height = 0; self?.character.play(.slamLand) },
                       .wait(forDuration: 0.9),
                       .run { [weak self] in self?.character.play(.idle) }]), withKey: "slam")
    }

    override func didChangeSize(_ oldSize: CGSize) { layout() }

    private func layout() {
        let groundHeight = size.height * 0.32
        ground.path = CGPath(rect: CGRect(x: -10, y: -10, width: size.width + 20, height: groundHeight + 10),
                             transform: nil)
        character.position = CGPoint(x: size.width / 2, y: groundHeight - 20)
    }
}

struct CharacterVisualizerView: View {
    let onBack: () -> Void

    @State private var scene = CharacterVisualizerScene()
    @State private var selected: CharacterAnimation = .idle
    @State private var speed = 1.0

    var body: some View {
        ZStack(alignment: .bottom) {
            SpriteView(scene: scene, debugOptions: [.showsFPS, .showsNodeCount])
                .ignoresSafeArea()
            controls
        }
        .overlay(alignment: .topLeading) {
            Button(action: onBack) { Label("Menu", systemImage: "chevron.left") }
                .buttonStyle(.borderedProminent)
                .padding()
        }
        .onChange(of: speed) { _, value in scene.speed = value }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            ForEach(CharacterAnimation.showcase) { animation in
                Button(animation.title) {
                    selected = animation
                    scene.play(animation)
                }
                .buttonStyle(.borderedProminent)
                .tint(selected == animation ? .orange : .gray)
            }
            Divider().frame(height: 28)
            Button("Flip") { scene.character.facingRight.toggle() }
                .buttonStyle(.bordered)
            Image(systemName: "tortoise")
            Slider(value: $speed, in: 0.1...2).frame(width: 100)
            Image(systemName: "hare")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.bottom, 12)
    }
}
