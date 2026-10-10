import SpriteKit

enum CharacterAnimation: String, CaseIterable, Identifiable {
    case idle, run, attack, leap, hit
    case jab, hook             // boxing pair: jab = tap (off hand), hook = forward swipe (weapon hand)
    case jump, fall, land      // driven by the scene's height physics, not shown in the lab
    case slam, slamLand        // air-to-ground attack: the dive, then the impact
    case smash                 // running ground slam: two-handed overhead swing
    case uppercut              // launcher: cock low, swing up, head thrown back
    case knockdown             // blasted flat: topples backwards and stays down
    case pickup                // crouch and reach for the ground
    case shoot                 // draw a bow and loose an arrow forward
    var id: String { rawValue }
    static let showcase: [CharacterAnimation] = [.idle, .run, .jab, .hook, .uppercut, .smash, .pickup, .shoot, .hit, .slam]
    var title: String { rawValue.capitalized }
}

// MARK: - Rig

/// Owns the joints and every animation. Art comes from a `Skin`, so any skin plays every animation.
/// Origin is at the feet. Faces right; use `facingRight` to flip.
/// Rotations: positive = counter-clockwise, so a hanging arm swings *forward* with positive angles.
final class HumanoidRig: SKNode {
    let skin: Skin
    private let layout: RigLayout
    private let restY: CGFloat
    private let armRest: CGFloat
    private let swordRest: CGFloat
    private let armLength: CGFloat

    private let rig = SKNode()      // lifts the body off the ground; the shadow stays put
    private let body = SKNode()
    private let shadow: SKShapeNode
    private let legBack: SKNode
    private let legFront: SKNode
    private let armOff: SKNode
    private let armWeapon: SKNode
    private let torso: SKNode
    private let head = SKNode()     // pivot; the skin's head art hangs inside it
    private var sword: SKNode

    /// Distance above the ground (pt, unscaled). The scene's physics drives this.
    var height: CGFloat = 0 { didSet { rig.position.y = height; updateShadow() } }

    var scaleFactor: CGFloat = 1 { didSet { applyScale() } }
    var facingRight = true { didSet { applyScale() } }

    init(skin: Skin) {
        self.skin = skin
        layout = skin.layout
        restY = layout.restY
        armRest = layout.armRest
        swordRest = layout.weaponRest
        armLength = layout.armLength
        shadow = styled(SKShapeNode(ellipseOf: layout.shadowSize), SKColor(white: 0, alpha: 0.25), line: 0)
        legBack = skin.makeLeg(.back)
        legFront = skin.makeLeg(.front)
        armOff = skin.makeArm(.off)
        armWeapon = skin.makeArm(.weapon)
        torso = skin.makeTorso()
        sword = skin.defaultWeapon?.make() ?? SKNode()
        super.init()
        build()
        play(.idle)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Swap what's in the weapon hand (nil = empty hand).
    func setWeapon(_ w: Weapon?) {
        sword.removeFromParent()
        sword = w?.make() ?? SKNode()
        sword.position = CGPoint(x: 0, y: -armLength)
        sword.zRotation = swordRest
        armWeapon.addChild(sword)
    }

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

        legBack.position = CGPoint(x: layout.legBackX, y: 0);   legBack.zPosition = -3
        legFront.position = CGPoint(x: layout.legFrontX, y: 0); legFront.zPosition = -2
        armOff.position = layout.offShoulder;                   armOff.zPosition = -1
        armWeapon.position = layout.weaponShoulder;             armWeapon.zPosition = 3
        head.position = layout.headPivot;                       head.zPosition = 2
        head.addChild(skin.makeHead())

        sword.position = CGPoint(x: 0, y: -armLength)
        armWeapon.addChild(sword)

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
        case .slam:   slam()
        case .smash:  smash()
        case .uppercut: uppercut()
        case .knockdown: knockdown()
        case .pickup: pickup()
        case .shoot: shoot()
        case .slamLand: slamLand()
        }
    }

    private func stopActions() {
        [self, body, head, legBack, legFront, armOff, armWeapon, sword].forEach { $0.removeAllActions() }
    }

    private func resetPose() {
        stopActions()
        shadow.removeAllActions()
        body.position = CGPoint(x: 0, y: restY)
        body.zRotation = 0
        head.zRotation = 0
        body.xScale = 1; body.yScale = 1
        legBack.zRotation = 0; legFront.zRotation = 0
        armOff.position = layout.offShoulder
        armOff.zPosition = -1
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
        track(head, [(0, 0.2)])
        track(body, [(0, 0.2)])
        body.run(pose(y: restY, sx: 0.94, sy: 1.08, d: 0.12))
        track(armWeapon, [(0.15, 0.15)])
        track(armOff, [(0.1, 0.15)])
        track(legFront, [(0, 0.15)])
        track(legBack, [(0, 0.15)])
        track(sword, [(.pi, 0.1)])
    }

    /// Air-to-ground dive: whole body pitched hard forward, both hands thrust out ahead,
    /// weapon leading (blade extends straight along the arms). Rotation is clockwise-negative.
    private func slam() {
        track(body, [(-1.9, 0.1)])
        track(armWeapon, [(2.9, 0.1)])
        track(armOff, [(2.9, 0.1)])
        track(sword, [(.pi, 0.08)])
        track(legFront, [(0.5, 0.1)])
        track(legBack, [(-0.3, 0.1)])
        body.run(pose(y: restY, sx: 0.92, sy: 1.1, d: 0.1))
        streaks()
    }

    /// Bow shot (0.45s): the weapon arm points straight ahead with the bow upright, the off hand draws the string back,
    /// release at 0.18s (the scene launches the arrow then), then everything settles.
    private func shoot() {
        track(armWeapon, [(1.5, 0.12), (nil, 0.06), (nil, 0.12), (armRest, 0.15)])
        track(sword,     [(4.712, 0.1), (nil, 0.2), (swordRest, 0.15)])              // bow upright: -90 degrees
        track(armOff,    [(-1.45, 0.14), (nil, 0.04), (0.2, 0.05), (nil, 0.08), (0, 0.14)])
        track(body,      [(0.08, 0.14), (nil, 0.04), (-0.05, 0.05), (nil, 0.08), (0, 0.14)])
        track(legFront,  [(0.25, 0.12), (nil, 0.2), (0, 0.13)])
        track(legBack,   [(-0.25, 0.12), (nil, 0.2), (0, 0.13)])
        body.run(.sequence([.wait(forDuration: 0.45), returnToIdle]))
        sword.childNode(withName: "nocked")?.run(.sequence([.wait(forDuration: 0.06), .unhide(), .wait(forDuration: 0.12), .hide()]))
    }

    /// Crouch with the torso pitched forward and the front arm hanging straight down (world-vertical) to scoop something up.
    private func pickup() {
        track(body, [(-0.6, 0.14), (nil, 0.1), (0, 0.18)])
        body.run(.sequence([
            pose(y: restY * 0.6, sx: 1.06, sy: 0.9, d: 0.14),
            .wait(forDuration: 0.1),
            pose(y: restY, d: 0.18),
            returnToIdle
        ]))
        track(armOff,   [(0.6, 0.14), (nil, 0.1), (0, 0.18)])        // cancels the lean: the arm points straight down
        track(head,     [(0.35, 0.14), (nil, 0.1), (0, 0.18)])       // eyes stay forward
        track(legFront, [(0.6, 0.14), (nil, 0.1), (0, 0.18)])
        track(legBack,  [(-0.5, 0.14), (nil, 0.1), (0, 0.18)])
    }

    /// Blasted flat: topples backwards, limbs flung out, and stays down until the fighter gets up.
    private func knockdown() {
        track(body, [(1.5, 0.14)])
        body.run(pose(y: restY * 0.7, d: 0.14, .easeOut))
        track(head, [(0.25, 0.14)])
        track(armWeapon, [(2.3, 0.14)])
        track(armOff, [(1.9, 0.14)])
        track(legFront, [(0.8, 0.14)])
        track(legBack, [(0.3, 0.14)])
    }

    /// Ground-impact dust (landings, knockdowns).
    func dust() { puff() }

    /// Uppercut: sink low with the weapon hauled down and back, then uncoil upward in one big arc.
    /// Front leg drives up, back leg stays pointed down, head is thrown back to follow the blade.
    /// The scene lifts the hero (ease-in-out jump); the pose then holds through the hang.
    private func uppercut() {
        // Cock (0.07s) -> swing (0.12s) -> hold
        track(armWeapon, [(-1.0, 0.07), (2.95, 0.12)])
        track(armOff,    [(1.0, 0.07), (-0.5, 0.12)])           // guard hand drops back as a counterweight
        track(sword,     [(.pi, 0.05)])                          // blade continues the line of the arm
        track(head,      [(-0.2, 0.07), (0.6, 0.12)])            // eyes on the target, then chin up
        track(body,      [(-0.2, 0.07), (0.2, 0.12)])            // coil forward, then arch back
        track(legFront,  [(0.5, 0.07), (1.35, 0.12)])            // knee drives up with the swing
        track(legBack,   [(-0.7, 0.07), (-0.1, 0.12)])           // trailing leg extends, toe pointed down
        body.run(.sequence([
            pose(y: restY * 0.72, sx: 1.18, sy: 0.75, d: 0.07),            // deep crouch
            pose(y: restY * 1.12, sx: 0.9, sy: 1.15, d: 0.12, .easeOut)    // stretch tall
        ]))
        run(.sequence([.wait(forDuration: 0.07), .run { [weak self] in
            self?.spawnSlash(start: -0.9, end: 1.7, radius: 100, lift: 26, clockwise: false, parent: self?.rig)
        }]))
    }

    /// Running ground slam: both hands on the weapon, hauled back behind the head, then driven down into the
    /// ground ahead. Feet leave the ground on the windup. A smaller cousin of the air slam's impact.
    private func smash() {
        // Off hand slides over to the grip and draws in front of the body: two hands on the weapon
        armOff.run(.move(to: layout.gripPoint, duration: 0.1))
        armOff.zPosition = 4

        // Arms: back behind the head, brief hold, then crash down ahead
        let wind: CGFloat = 3.7, strike: CGFloat = 0.8
        track(armWeapon, [(wind, 0.14), (nil, 0.06), (strike, 0.07), (nil, 0.2), (armRest, 0.15)])
        track(armOff,    [(wind, 0.14), (nil, 0.06), (strike, 0.07), (nil, 0.2), (0, 0.15)])
        track(sword,     [(.pi, 0.1), (nil, 0.56), (swordRest, 0.15)])

        // Body: leaps up and leans back, then slams down and forward
        track(body, [(0.3, 0.14), (nil, 0.06), (-0.4, 0.07), (nil, 0.2), (0, 0.15)])
        body.run(.sequence([
            pose(y: restY + 34, sx: 0.95, sy: 1.06, d: 0.14, .easeOut),    // feet lift off
            .wait(forDuration: 0.06),
            pose(y: restY * 0.78, sx: 1.18, sy: 0.8, d: 0.07, .easeIn),     // crash down
            pose(y: restY * 0.85, sx: 1.08, sy: 0.9, d: 0.2, .easeOut),
            pose(y: restY, d: 0.15),
            returnToIdle
        ]))
        track(legFront, [(0.7, 0.14), (nil, 0.06), (-0.2, 0.07), (nil, 0.35)])   // legs tuck up, then plant
        track(legBack,  [(-0.6, 0.14), (nil, 0.06), (0.3, 0.07), (nil, 0.35)])

        run(.sequence([.wait(forDuration: 0.27), .run { [weak self] in
            self?.puff(); self?.shockwave(scale: 2.6, at: 70)
        }]))
    }

    /// Impact: deep crouch, weapon planted in the ground ahead, shockwave. Held through the landing cooldown.
    private func slamLand() {
        puff()
        shockwave()
        body.run(.sequence([
            pose(y: restY * 0.7, sx: 1.25, sy: 0.7, d: 0.05),
            pose(y: restY * 0.8, sx: 1.1, sy: 0.85, d: 0.2, .easeOut)
        ]))
        track(body, [(-0.45, 0.06)])
        track(armWeapon, [(1.2, 0.06)])
        track(armOff, [(1.0, 0.06)])
        track(sword, [(.pi, 0.05)])
        track(legFront, [(0.5, 0.06)])
        track(legBack, [(-0.4, 0.06)])
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

    private func spawnSlash(start: CGFloat = 2.0, end: CGFloat = -0.4, radius: CGFloat = 70, lift: CGFloat = 44,
                            clockwise: Bool = true, parent: SKNode? = nil) {
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: radius, startAngle: start, endAngle: end, clockwise: clockwise)
        let fx = SKShapeNode(path: path)
        fx.strokeColor = .white; fx.lineWidth = 8; fx.lineCap = .round; fx.glowWidth = 3
        fx.position = CGPoint(x: layout.offShoulder.x, y: restY + lift)
        fx.zPosition = 10
        (parent ?? self).addChild(fx)
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

    /// Speed lines above the diver.
    private func streaks() {
        for (x, y, len) in [(-34, 120, 70), (-8, 150, 90), (22, 125, 60)] as [(CGFloat, CGFloat, CGFloat)] {
            let p = CGMutablePath()
            p.move(to: .zero); p.addLine(to: CGPoint(x: 0, y: len))
            let line = SKShapeNode(path: p)
            line.strokeColor = .white; line.lineWidth = 5; line.lineCap = .round
            line.position = CGPoint(x: x, y: y)
            line.zPosition = -5
            rig.addChild(line)
            line.run(.sequence([.group([.moveBy(x: 0, y: 40, duration: 0.18), .fadeOut(withDuration: 0.18)]),
                                .removeFromParent()]))
        }
    }

    private func shockwave(scale: CGFloat = 3.6, at x: CGFloat = 0) {
        let ring = styled(SKShapeNode(ellipseOf: CGSize(width: 60, height: 16)), .clear, line: 5)
        ring.strokeColor = .white
        ring.position = CGPoint(x: x, y: 4)
        ring.zPosition = -5
        addChild(ring)
        ring.run(.sequence([.group([.scale(to: scale, duration: 0.3), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
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
