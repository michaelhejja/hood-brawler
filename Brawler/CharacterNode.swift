import SpriteKit

enum CharacterAnimation: String, CaseIterable, Identifiable {
    case idle, run, attack, leap, hit
    case jab, hook             // boxing pair: jab = tap (off hand), hook = forward swipe (weapon hand)
    case jump, fall, land      // driven by the scene's height physics, not shown in the lab
    var id: String { rawValue }
    static let showcase: [CharacterAnimation] = [.idle, .run, .jab, .hook, .attack, .leap, .hit]
    var title: String { rawValue.capitalized }
}

// MARK: - Shape helpers (swap for sprites later)

let ink = SKColor(red: 0.08, green: 0.06, blue: 0.12, alpha: 1)
private let cloak = SKColor(red: 0.36, green: 0.28, blue: 0.50, alpha: 1)
private let cloakDark = SKColor(red: 0.24, green: 0.18, blue: 0.36, alpha: 1)

@discardableResult
func styled(_ s: SKShapeNode, _ fill: SKColor, line: CGFloat = 4) -> SKShapeNode {
    s.fillColor = fill
    s.strokeColor = line > 0 ? ink : .clear
    s.lineWidth = line
    s.lineJoin = .round
    s.lineCap = .round
    return s
}

/// A limb hanging down from its joint (node origin = joint).
private func limb(width: CGFloat, height: CGFloat, fill: SKColor) -> SKShapeNode {
    styled(SKShapeNode(rect: CGRect(x: -width / 2, y: -height, width: width, height: height),
                       cornerRadius: width / 2), fill)
}

// MARK: - Character

/// Origin is at the feet. Faces right; use `facingRight` to flip.
/// Rotations: positive = counter-clockwise, so a hanging arm swings *forward* with positive angles.
final class CharacterNode: SKNode {
    private let restY: CGFloat = 30
    private let armRest: CGFloat = 0.5
    private let swordRest: CGFloat = .pi + 2.0
    private let armLength: CGFloat = 28
    private let weaponBack: CGFloat = -1     // weapon arm sits behind the torso ...
    private let weaponFront: CGFloat = 4     // ... and only swings in front while attacking

    private let rig = SKNode()      // lifts the body off the ground; the shadow stays put
    private let body = SKNode()
    private let shadow = styled(SKShapeNode(ellipseOf: CGSize(width: 64, height: 14)),
                                SKColor(white: 0, alpha: 0.25), line: 0)
    private let legBack = limb(width: 14, height: 30, fill: cloakDark)
    private let legFront = limb(width: 14, height: 30, fill: cloak)
    private let armOff = limb(width: 12, height: 28, fill: cloakDark)
    private let armWeapon = limb(width: 12, height: 28, fill: cloak)
    private let torso = styled(SKShapeNode(rect: CGRect(x: -20, y: 0, width: 40, height: 48), cornerRadius: 14), cloak)
    private let head = SKNode()
    private let sword = SKShapeNode()

    /// Distance above the ground (pt, unscaled). The scene's physics drives this.
    var height: CGFloat = 0 { didSet { rig.position.y = height; updateShadow() } }

    var scaleFactor: CGFloat = 1 { didSet { applyScale() } }
    var facingRight = true { didSet { applyScale() } }

    override init() {
        super.init()
        build()
        play(.idle)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func updateShadow() {
        let k = max(0.35, 1 - height / 350)
        shadow.setScale(k)
        shadow.alpha = max(0.4, k)
    }

    private func applyScale() {
        xScale = (facingRight ? 1 : -1) * scaleFactor
        yScale = scaleFactor
    }

    private func build() {
        addChild(shadow)
        addChild(rig)
        rig.addChild(body)
        body.position = CGPoint(x: 0, y: restY)

        legBack.position = CGPoint(x: -9, y: 0);  legBack.zPosition = -3
        legFront.position = CGPoint(x: 9, y: 0);  legFront.zPosition = -2
        armOff.position = CGPoint(x: 17, y: 44);  armOff.zPosition = 3
        armWeapon.position = CGPoint(x: -16, y: 44); armWeapon.zPosition = weaponBack
        head.position = CGPoint(x: 2, y: 64);      head.zPosition = 2

        // Head: hood + dark face + glowing eyes
        let hood = styled(SKShapeNode(circleOfRadius: 20), cloak)
        let face = styled(SKShapeNode(ellipseOf: CGSize(width: 24, height: 22)),
                          SKColor(red: 0.04, green: 0.03, blue: 0.07, alpha: 1), line: 3)
        face.position = CGPoint(x: 6, y: -1)
        for x: CGFloat in [-3, 5] {
            let eye = styled(SKShapeNode(ellipseOf: CGSize(width: 6, height: 8)),
                             SKColor(red: 0.4, green: 1, blue: 0.5, alpha: 1), line: 0)
            eye.glowWidth = 3
            eye.position = CGPoint(x: x, y: 1)
            face.addChild(eye)
        }
        hood.addChild(face)
        head.addChild(hood)

        // Sword: blade points along local +y, held at the hand
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -4, y: 0)); p.addLine(to: CGPoint(x: 4, y: 0))
        p.addLine(to: CGPoint(x: 3, y: 46)); p.addLine(to: CGPoint(x: 0, y: 56))
        p.addLine(to: CGPoint(x: -3, y: 46)); p.closeSubpath()
        sword.path = p
        styled(sword, SKColor(white: 0.9, alpha: 1), line: 3)
        let guardBar = styled(SKShapeNode(rect: CGRect(x: -9, y: -3, width: 18, height: 6), cornerRadius: 3),
                              SKColor(red: 0.5, green: 0.3, blue: 0.15, alpha: 1), line: 3)
        let blood = styled(SKShapeNode(ellipseOf: CGSize(width: 6, height: 14)),
                           SKColor(red: 0.75, green: 0.05, blue: 0.1, alpha: 1), line: 0)
        blood.position = CGPoint(x: 0, y: 38)
        sword.addChild(blood)
        sword.addChild(guardBar)
        sword.position = CGPoint(x: 0, y: -armLength)
        armWeapon.addChild(sword)

        let fist = styled(SKShapeNode(circleOfRadius: 8), cloakDark)
        fist.position = CGPoint(x: 0, y: -28)
        armOff.addChild(fist)

        [legBack, legFront, armOff, torso, head, armWeapon].forEach(body.addChild)
        resetPose()
    }

    // MARK: Playback

    func play(_ animation: CharacterAnimation) {
        if animation == .fall { stopActions() } else { resetPose() }
        switch animation {
        case .idle:   idle()
        case .run:    run()
        case .attack: attack()
        case .jab:    jab()
        case .hook:   hook()
        case .leap:   leap()
        case .hit:    hit()
        case .jump:   jump()
        case .fall:   fall()
        case .land:   land()
        }
    }

    private func stopActions() {
        [self, body, legBack, legFront, armOff, armWeapon, sword].forEach { $0.removeAllActions() }
    }

    private func resetPose() {
        stopActions()
        shadow.removeAllActions()
        body.position = CGPoint(x: 0, y: restY)
        body.zRotation = 0
        body.xScale = 1; body.yScale = 1
        legBack.zRotation = 0; legFront.zRotation = 0
        armOff.position = CGPoint(x: 17, y: 44)
        armWeapon.zPosition = weaponBack
        armOff.zRotation = 0; armWeapon.zRotation = armRest
        sword.zRotation = swordRest
        updateShadow()
        alpha = 1
    }

    // MARK: Animations

    private func idle() {
        body.run(.repeatForever(.sequence([pose(y: restY + 2, d: 0.7), pose(y: restY, d: 0.7)])))
        track(armWeapon, [(armRest + 0.08, 0.7), (armRest - 0.05, 0.7)], loop: true)
        track(armOff, [(-0.05, 0.7), (0.06, 0.7)], loop: true)
    }

    private func run() {
        let c = 0.16
        body.zRotation = -0.18
        body.run(.repeatForever(.sequence([pose(y: restY + 5, d: c), pose(y: restY, d: c)])))
        track(legFront, [(0.9, c), (-0.9, c)], loop: true)
        track(legBack, [(-0.9, c), (0.9, c)], loop: true)
        track(armWeapon, [(-0.7, c), (1.1, c)], loop: true)
        track(armOff, [(0.7, c), (-0.7, c)], loop: true)
    }

    private func attack() {
        weaponForward(after: 0.08, for: 0.28)
        track(armWeapon, [(2.8, 0.12), (0.9, 0.07), (nil, 0.1), (armRest, 0.2)])
        track(armOff, [(-0.8, 0.12), (0.4, 0.07), (nil, 0.1), (0, 0.2)])
        track(sword, [(.pi, 0.12), (nil, 0.17), (swordRest, 0.2)])
        body.run(.sequence([
            pose(y: restY, x: -8, d: 0.12),
            pose(y: restY, x: 18, d: 0.07, .easeIn),
            .wait(forDuration: 0.1),
            pose(y: restY, d: 0.2),
            returnToIdle
        ]))
        run(.sequence([.wait(forDuration: 0.12), .run { [weak self] in self?.spawnSlash() }]))
    }

    /// Weapon arm swings in front of the body for the strike, then goes back behind it.
    private func weaponForward(after delay: TimeInterval, for duration: TimeInterval) {
        armWeapon.run(.sequence([.wait(forDuration: delay),
                                 .run { [weak self] in self?.armWeapon.zPosition = self?.weaponFront ?? 4 },
                                 .wait(forDuration: duration),
                                 .run { [weak self] in self?.armWeapon.zPosition = self?.weaponBack ?? -1 }]))
    }

    /// Tap: quick straight punch with the off hand (the one without the sword).
    private func jab() {
        track(armOff, [(1.55, 0.06), (nil, 0.05), (0, 0.13)])
        track(armWeapon, [(armRest - 0.2, 0.06), (nil, 0.05), (armRest, 0.13)])
        body.run(.sequence([
            pose(y: restY, x: 10, d: 0.06, .easeIn),
            .wait(forDuration: 0.05),
            pose(y: restY, d: 0.13),
            returnToIdle
        ]))
        run(.sequence([.wait(forDuration: 0.06), .run { [weak self] in self?.pop(at: CGPoint(x: 50, y: 0)) }]))
    }

    /// Forward swipe: wide hooking swing with the weapon hand, committing the whole body.
    private func hook() {
        weaponForward(after: 0.06, for: 0.3)
        track(armWeapon, [(-0.9, 0.1), (1.7, 0.07), (nil, 0.1), (armRest, 0.2)])
        track(armOff, [(0.5, 0.1), (-0.6, 0.07), (nil, 0.1), (0, 0.2)])
        track(sword, [(2.5, 0.1), (3.0, 0.07), (nil, 0.1), (swordRest, 0.2)])
        body.run(.sequence([
            pose(y: restY, x: -12, d: 0.1),
            pose(y: restY, x: 24, d: 0.07, .easeIn),
            .wait(forDuration: 0.1),
            pose(y: restY, d: 0.2),
            returnToIdle
        ]))
        track(body, [(0.2, 0.1), (-0.25, 0.07), (nil, 0.1), (0, 0.2)])   // lean back, then throw the shoulder through
        run(.sequence([.wait(forDuration: 0.1), .run { [weak self] in self?.spawnSlash(start: 1.0, end: -0.6, radius: 80, lift: 40) }]))
    }

    private func leap() {
        weaponForward(after: 0.35, for: 0.35)
        let h: CGFloat = 150
        // timeline: crouch .12 | rise .25 | hang .08 | dive .18 | land .06 | recover .2
        body.run(.sequence([
            pose(y: restY * 0.8, sx: 1.12, sy: 0.8, d: 0.12),
            pose(y: restY * 1.08 + h, sx: 0.94, sy: 1.08, d: 0.25, .easeOut),
            .wait(forDuration: 0.08),
            pose(y: restY, d: 0.18, .easeIn),
            pose(y: restY * 0.75, sx: 1.2, sy: 0.75, d: 0.06),
            pose(y: restY, d: 0.2, .easeOut),
            returnToIdle
        ]))
        track(armWeapon, [(-0.8, 0.12), (2.9, 0.25), (nil, 0.08), (0.15, 0.18), (nil, 0.06), (armRest, 0.2)])
        track(armOff, [(-0.8, 0.12), (2.6, 0.25), (nil, 0.08), (0.1, 0.18), (nil, 0.06), (0, 0.2)])
        track(legFront, [(0.6, 0.12), (1.0, 0.25), (nil, 0.08), (0, 0.18), (nil, 0.26)])
        track(legBack, [(-0.4, 0.12), (-0.5, 0.25), (nil, 0.08), (0, 0.18), (nil, 0.26)])
        track(sword, [(nil, 0.4), (.pi, 0.1), (nil, 0.19), (swordRest, 0.2)])   // blade points down on the dive
        shadow.run(.sequence([
            .wait(forDuration: 0.12),
            .group([.scale(to: 0.55, duration: 0.25), .fadeAlpha(to: 0.5, duration: 0.25)]),
            .wait(forDuration: 0.08),
            .group([.scale(to: 1, duration: 0.18), .fadeAlpha(to: 1, duration: 0.18)])
        ]))
        run(.sequence([.wait(forDuration: 0.63), .run { [weak self] in self?.puff() }]))
    }

    // Air poses: the scene owns the vertical motion (see `height`)

    private func jump() {
        body.run(.sequence([
            pose(y: restY * 0.85, sx: 1.1, sy: 0.85, d: 0.06),
            pose(y: restY, sx: 0.94, sy: 1.08, d: 0.12, .easeOut)
        ]))
        track(armWeapon, [(-0.6, 0.06), (2.9, 0.16)])
        track(armOff, [(-0.6, 0.06), (2.6, 0.16)])
        track(legFront, [(0.6, 0.12)])
        track(legBack, [(-0.5, 0.12)])
    }

    private func fall() {
        body.run(pose(y: restY, sx: 0.94, sy: 1.08, d: 0.12))
        track(armWeapon, [(0.15, 0.15)])
        track(armOff, [(0.1, 0.15)])
        track(legFront, [(0, 0.15)])
        track(legBack, [(0, 0.15)])
        track(sword, [(.pi, 0.1)])
    }

    private func land() {
        puff()
        body.run(.sequence([
            pose(y: restY * 0.75, sx: 1.2, sy: 0.75, d: 0.05),
            pose(y: restY, d: 0.1, .easeOut)
        ]))
    }

    private func hit() {
        body.run(.sequence([
            pose(y: restY, x: -26, d: 0.08, .easeOut),
            pose(y: restY, d: 0.25),
            returnToIdle
        ]))
        track(body, [(0.35, 0.08), (0, 0.3)])
        track(armWeapon, [(1.6, 0.08), (armRest, 0.3)])
        track(armOff, [(1.2, 0.08), (0, 0.3)])
        run(.repeat(.sequence([.fadeAlpha(to: 0.3, duration: 0.05), .fadeAlpha(to: 1, duration: 0.05)]), count: 4))
    }

    // MARK: Action helpers

    /// The game scene drives locomotion itself, so it turns this off.
    var returnsToIdle = true
    private var returnToIdle: SKAction { .run { [weak self] in if let self, self.returnsToIdle { self.play(.idle) } } }

    private func pose(y: CGFloat, x: CGFloat = 0, sx: CGFloat = 1, sy: CGFloat = 1,
                      d: TimeInterval, _ mode: SKActionTimingMode = .easeInEaseOut) -> SKAction {
        let move = SKAction.move(to: CGPoint(x: x, y: y), duration: d)
        let scale = SKAction.scaleX(to: sx, y: sy, duration: d)
        move.timingMode = mode; scale.timingMode = mode
        return .group([move, scale])
    }

    /// Rotate `node` through (angle, duration) steps; a nil angle just waits.
    private func track(_ node: SKNode, _ steps: [(CGFloat?, TimeInterval)], loop: Bool = false) {
        let seq = SKAction.sequence(steps.map { (angle, d) -> SKAction in
            guard let angle else { return .wait(forDuration: d) }
            let r = SKAction.rotate(toAngle: angle, duration: d)
            r.timingMode = .easeInEaseOut
            return r
        })
        node.run(loop ? .repeatForever(seq) : seq)
    }

    // MARK: Effects

    private func spawnSlash(start: CGFloat = 2.0, end: CGFloat = -0.4, radius: CGFloat = 70, lift: CGFloat = 44) {
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: radius, startAngle: start, endAngle: end, clockwise: true)
        let fx = SKShapeNode(path: path)
        fx.strokeColor = .white; fx.lineWidth = 8; fx.lineCap = .round; fx.glowWidth = 3
        fx.position = CGPoint(x: 17, y: restY + lift)
        fx.zPosition = 10
        addChild(fx)
        fx.run(.sequence([.group([.fadeOut(withDuration: 0.18), .scale(to: 1.15, duration: 0.18)]),
                          .removeFromParent()]))
    }

    /// Small impact flash at the fist.
    private func pop(at p: CGPoint) {
        let star = styled(SKShapeNode(circleOfRadius: 9), .white, line: 3)
        star.position = CGPoint(x: p.x, y: restY + 44)
        star.zPosition = 10
        addChild(star)
        star.run(.sequence([.group([.scale(to: 1.8, duration: 0.12), .fadeOut(withDuration: 0.12)]), .removeFromParent()]))
    }

    private func puff() {
        for dir: CGFloat in [-1, 1] {
            let p = styled(SKShapeNode(circleOfRadius: 9), SKColor(white: 0.92, alpha: 1), line: 3)
            p.position = CGPoint(x: dir * 20, y: 8)
            p.zPosition = 5
            addChild(p)
            p.run(.sequence([
                .group([.moveBy(x: dir * 36, y: 14, duration: 0.3),
                        .scale(to: 1.8, duration: 0.3),
                        .fadeOut(withDuration: 0.3)]),
                .removeFromParent()
            ]))
        }
    }
}
