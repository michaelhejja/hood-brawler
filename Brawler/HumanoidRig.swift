import SpriteKit

enum CharacterAnimation: String, CaseIterable, Identifiable {
    case idle, run, attack, leap, hit
    case roll                  // backward tumble (dodge)
    case haymaker              // third punch of a string: big overhand finisher
    case jab, hook             // boxing pair: jab = tap (off hand), hook = forward swipe (weapon hand)
    case jump, fall, land      // driven by the scene's height physics, not shown in the lab
    case bite                  // bat: wings snap back, lunge and bite
    case bullRush              // special release: head down, shoulders forward
    case whirlwind             // special release: arms out, two full spins
    case hammerSlam            // hammer: long overhead wind-up, then a ground slam (impact at 0.55s)
    case guardUp, shieldBurst  // shield: raised guard (held until another animation) and the release
    case airStrike             // quick mid-air punch-kick; holds its pose until the fall
    case slam, slamLand        // air-to-ground attack: the dive, then the impact
    case smash                 // running ground slam: two-handed overhead swing
    case uppercut              // launcher: cock low, swing up, head thrown back
    case knockdown             // blasted flat: topples backwards and stays down
    case pickup                // crouch and reach for the ground
    case headRock              // heavy hit on something too big to launch: head snaps back
    case powerUp               // looping rage charge (special)
    case rageSlam              // the special's release: arms up, then a ground pound
    case throwRock             // overhand throw (the rock)
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

    var flies = false                       // wings (the arms) flap together; set by the fighter before it first plays idle

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
        sword.zPosition = -1                      // behind the arm, so the hand wraps the grip
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

        legBack.position = CGPoint(x: layout.legBackX, y: 0);   legBack.zPosition = -2     // weapon side: nearest the camera
        legFront.position = CGPoint(x: layout.legFrontX, y: 0); legFront.zPosition = -3  // off-hand side: further away
        armOff.position = layout.offShoulder;                   armOff.zPosition = -1
        armWeapon.position = layout.weaponShoulder;             armWeapon.zPosition = 3
        head.position = layout.headPivot;                       head.zPosition = 2
        head.addChild(skin.makeHead())

        sword.position = CGPoint(x: 0, y: -armLength)
        sword.zPosition = -1
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
        case .throwRock: throwRock()
        case .powerUp: powerUp()
        case .airStrike: airStrike()
        case .bite: bite()
        case .guardUp: guardUp()
        case .shieldBurst: shieldBurst()
        case .hammerSlam: hammerSlam()
        case .whirlwind: whirlwind()
        case .bullRush: bullRush()
        case .haymaker: haymaker()
        case .roll: roll()
        case .rageSlam: rageSlam()
        case .headRock: headRock()
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

    private func bullRush() {
        track(armWeapon, [(1.5, 0.08), (nil, 0.8), (armRest, 0.15)])
        track(armOff,    [(1.5, 0.08), (nil, 0.8), (0, 0.15)])
        track(legFront,  [(0.6, 0.08), (nil, 0.8), (0, 0.15)])
        track(legBack,   [(-0.6, 0.08), (nil, 0.8), (0, 0.15)])
        track(body,      [(-0.5, 0.08), (nil, 0.8), (0, 0.15)])
        body.run(.sequence([pose(y: restY * 0.9, x: 20, d: 0.08), .wait(forDuration: 0.8), pose(y: restY, d: 0.15), returnToIdle]))
        for t in [0.1, 0.3, 0.5, 0.7] { run(.sequence([.wait(forDuration: t), .run { [weak self] in self?.puff() }])) }       // dust all the way along
    }

    private func whirlwind() {
        track(armWeapon, [(1.45, 0.08), (nil, 0.5), (armRest, 0.15)])
        track(armOff,    [(1.45, 0.08), (nil, 0.5), (0, 0.15)])
        track(legFront,  [(0.5, 0.08), (nil, 0.5), (0, 0.15)])
        track(legBack,   [(-0.5, 0.08), (nil, 0.5), (0, 0.15)])
        body.run(.sequence([.rotate(byAngle: 4 * .pi, duration: 0.6), .run { [weak self] in self?.body.zRotation = 0 }]))
        body.run(.sequence([pose(y: restY + 12, d: 0.1, .easeOut), .wait(forDuration: 0.5), pose(y: restY, d: 0.15), returnToIdle]))
        run(.sequence([.wait(forDuration: 0.08), .run { [weak self] in self?.spawnSlash(start: 0, end: .pi * 1.9, radius: 120, lift: 50, clockwise: false) }]))
        run(.sequence([.wait(forDuration: 0.3), .run { [weak self] in self?.spawnSlash(start: 0, end: .pi * 1.9, radius: 140, lift: 50, clockwise: false) }]))
    }

    private func hammerSlam() {
        armOff.run(.move(to: layout.gripPoint, duration: 0.15))
        armOff.zPosition = 4
        let wind: CGFloat = 3.5, strike: CGFloat = 0.8
        track(armWeapon, [(wind, 0.3), (nil, 0.05), (strike, 0.07), (nil, 0.25), (armRest, 0.18)])
        track(armOff,    [(wind, 0.3), (nil, 0.05), (strike, 0.07), (nil, 0.25), (0, 0.18)])
        track(sword,     [(.pi, 0.2), (nil, 0.25), (swordRest, 0.25)])
        track(body,      [(0.35, 0.3), (nil, 0.05), (-0.4, 0.07), (nil, 0.25), (0, 0.18)])
        track(legFront,  [(0.3, 0.3), (nil, 0.05), (-0.2, 0.07), (nil, 0.35)])
        track(legBack,   [(-0.3, 0.3), (nil, 0.05), (0.3, 0.07), (nil, 0.35)])
        body.run(.sequence([
            pose(y: restY * 0.95, x: -14, d: 0.3, .easeOut),                       // rears back, hammer high
            .wait(forDuration: 0.05),
            pose(y: restY * 0.78, x: 26, sx: 1.15, sy: 0.82, d: 0.07, .easeIn),    // crash down
            pose(y: restY * 0.88, d: 0.25),
            pose(y: restY, d: 0.18),
            returnToIdle
        ]))
        run(.sequence([.wait(forDuration: 0.42), .run { [weak self] in self?.puff(); self?.shockwave(scale: 2.6, at: 130) }]))
    }

    /// Shield held out in front, braced.
    private func guardUp() {
        track(armWeapon, [(1.5, 0.12)])
        track(armOff, [(1.3, 0.12)])
        track(sword, [(-1.5, 0.12)])                    // cancels the arm's turn, so the shield stands upright in front of you
        track(legFront, [(0.35, 0.12)])
        track(legBack, [(-0.35, 0.12)])
        track(body, [(0.1, 0.12)])
        body.run(pose(y: restY * 0.93, x: 8, d: 0.12))
    }

    private func shieldBurst() {
        track(armWeapon, [(0.9, 0.08), (1.75, 0.07), (nil, 0.15), (armRest, 0.2)])
        track(armOff, [(0.9, 0.08), (1.6, 0.07), (nil, 0.15), (0, 0.2)])
        track(sword, [(-0.9, 0.08), (-1.75, 0.07), (nil, 0.15), (swordRest, 0.2)])
        body.run(.sequence([pose(y: restY, x: -10, d: 0.08), pose(y: restY, x: 28, d: 0.07, .easeIn), .wait(forDuration: 0.15), pose(y: restY, d: 0.2), returnToIdle]))
        run(.sequence([.wait(forDuration: 0.08), .run { [weak self] in self?.spawnSlash(start: 1.4, end: -0.2, radius: 140, lift: 50) }]))
    }

    /// 0...1: how much energy the shield is holding (it glows).
    func setGuardCharge(_ k: CGFloat) { sword.childNode(withName: "glow")?.alpha = min(1, max(0, k)) * 0.85 }

    private func flap(_ p: Double, lean: CGFloat) {
        body.zRotation = lean
        body.run(.repeatForever(.sequence([pose(y: restY + 7, d: p), pose(y: restY - 1, d: p)])))
        track(armWeapon, [(2.5, p), (0.3, p)], loop: true)
        track(armOff, [(2.3, p), (0.2, p)], loop: true)
    }

    private func bite() {
        track(armWeapon, [(2.5, 0.07), (nil, 0.08), (0.5, 0.2)])
        track(armOff, [(2.3, 0.07), (nil, 0.08), (0.2, 0.2)])
        track(head, [(0.35, 0.07), (-0.15, 0.08), (0, 0.2)])
        track(body, [(-0.3, 0.07), (-0.12, 0.08), (0, 0.2)])
        body.run(.sequence([pose(y: restY - 4, x: -8, d: 0.07), pose(y: restY, x: 22, d: 0.08, .easeIn), pose(y: restY, d: 0.2), returnToIdle]))
    }

    private func idle() {
        if flies { flap(0.17, lean: 0); return }
        body.run(.repeatForever(.sequence([pose(y: restY + 2, d: 0.7), pose(y: restY, d: 0.7)])))
        track(armWeapon, [(armRest + 0.08, 0.7), (armRest - 0.05, 0.7)], loop: true)
        track(armOff, [(-0.05, 0.7), (0.06, 0.7)], loop: true)
    }

    private func run() {
        if flies { flap(0.1, lean: -0.3); return }
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

    /// Which alternate version of the next jab / hook / haymaker to play (0 = the standard one). Visual only: every
    /// variant keeps the original's step durations, so the hit windows (which are timed separately) still line up.
    var variant = 0
    /// A finisher swing: its slash trails are bigger and gold.
    var finisher = false

    /// 1: a cross, the whole body turning through the punch. 2: a hammer fist, snapped down from overhead.
    private func jabVariant(_ v: Int) {
        if v == 1 {
            track(armOff, [(1.6, 0.04), (nil, 0.03), (0, 0.1)])
            track(armWeapon, [(armRest - 0.8, 0.04), (nil, 0.03), (armRest, 0.1)])
            track(legFront, [(0.7, 0.04), (nil, 0.03), (0, 0.1)])
            track(legBack, [(-0.7, 0.04), (nil, 0.03), (0, 0.1)])
            track(body, [(-0.3, 0.04), (nil, 0.03), (0, 0.1)])
            track(head, [(0.2, 0.04), (nil, 0.03), (0, 0.1)])
            body.run(.sequence([pose(y: restY * 0.88, x: 18, d: 0.04, .easeIn), .wait(forDuration: 0.03), pose(y: restY, d: 0.1), returnToIdle]))
            run(.sequence([.wait(forDuration: 0.04), .run { [weak self] in self?.pop(at: CGPoint(x: 56, y: 0)) }]))
        } else {
            track(armOff, [(3.1, 0.015), (1.0, 0.025), (nil, 0.03), (0, 0.1)])
            track(armWeapon, [(armRest - 0.4, 0.04), (nil, 0.03), (armRest, 0.1)])
            track(legFront, [(0.8, 0.04), (nil, 0.03), (0, 0.1)])
            track(legBack, [(-0.6, 0.04), (nil, 0.03), (0, 0.1)])
            track(body, [(-0.5, 0.04), (nil, 0.03), (0, 0.1)])
            track(head, [(0.3, 0.04), (nil, 0.03), (0, 0.1)])
            body.run(.sequence([pose(y: restY * 0.76, x: 16, d: 0.04, .easeIn), .wait(forDuration: 0.03), pose(y: restY, d: 0.1), returnToIdle]))
            run(.sequence([.wait(forDuration: 0.04), .run { [weak self] in self?.pop(at: CGPoint(x: 56, y: 0), height: 30) }]))
        }
    }

    /// 1: an overhead chop. 2: a low sweep.
    private func hookVariant(_ v: Int) {
        if v == 1 {
            track(armWeapon, [(3.0, 0.1), (1.1, 0.07), (nil, 0.1), (armRest, 0.2)])
            track(armOff, [(2.2, 0.1), (0.2, 0.07), (nil, 0.1), (0, 0.2)])
            track(sword, [(1.6, 0.1), (3.0, 0.07), (nil, 0.1), (swordRest, 0.2)])
            body.run(.sequence([pose(y: restY * 1.03, x: -10, d: 0.1), pose(y: restY * 0.9, x: 22, d: 0.07, .easeIn), .wait(forDuration: 0.1), pose(y: restY, d: 0.2), returnToIdle]))
            track(body, [(0.32, 0.1), (-0.4, 0.07), (nil, 0.1), (0, 0.2)])
            run(.sequence([.wait(forDuration: 0.1), .run { [weak self] in self?.spawnSlash(start: 2.2, end: -0.5, radius: 74, lift: 34) }]))
        } else {
            track(armWeapon, [(-1.4, 0.1), (1.3, 0.07), (nil, 0.1), (armRest, 0.2)])
            track(armOff, [(0.9, 0.1), (-0.4, 0.07), (nil, 0.1), (0, 0.2)])
            track(sword, [(2.2, 0.1), (2.9, 0.07), (nil, 0.1), (swordRest, 0.2)])
            track(legFront, [(-0.3, 0.1), (0.8, 0.07), (nil, 0.1), (0, 0.2)])
            track(legBack, [(0.5, 0.1), (-0.5, 0.07), (nil, 0.1), (0, 0.2)])
            body.run(.sequence([pose(y: restY * 0.8, x: -14, d: 0.1), pose(y: restY * 0.84, x: 26, d: 0.07, .easeIn), .wait(forDuration: 0.1), pose(y: restY, d: 0.2), returnToIdle]))
            track(body, [(0.1, 0.1), (-0.45, 0.07), (nil, 0.1), (0, 0.2)])
            run(.sequence([.wait(forDuration: 0.1), .run { [weak self] in self?.spawnSlash(start: 0.4, end: -1.1, radius: 92, lift: 14) }]))
        }
    }

    /// 1: a spinning backhand. 2: an overhand smash.
    private func haymakerVariant(_ v: Int) {
        if v == 1 {
            track(armWeapon, [(-2.0, 0.17), (1.2, 0.08), (nil, 0.12), (armRest, 0.25)])
            track(armOff, [(1.0, 0.17), (0.8, 0.08), (nil, 0.12), (0, 0.25)])
            track(legFront, [(-0.4, 0.17), (0.8, 0.08), (nil, 0.12), (0, 0.25)])
            track(legBack, [(0.6, 0.17), (-0.9, 0.08), (nil, 0.12), (0, 0.25)])
            track(body, [(0.55, 0.17), (-0.6, 0.08), (nil, 0.12), (0, 0.25)])
            track(head, [(-0.2, 0.17), (0.25, 0.08), (nil, 0.12), (0, 0.25)])
            body.run(.sequence([pose(y: restY * 0.82, x: -26, d: 0.17, .easeOut), pose(y: restY * 0.92, x: 40, d: 0.08, .easeIn), .wait(forDuration: 0.12), pose(y: restY, d: 0.25), returnToIdle]))
            run(.sequence([.wait(forDuration: 0.17), .run { [weak self] in self?.pop(at: CGPoint(x: 72, y: 40)) }]))
        } else {
            track(armWeapon, [(3.1, 0.17), (0.8, 0.08), (nil, 0.12), (armRest, 0.25)])
            track(armOff, [(2.0, 0.17), (0.3, 0.08), (nil, 0.12), (0, 0.25)])
            track(legFront, [(0.2, 0.17), (0.6, 0.08), (nil, 0.12), (0, 0.25)])
            track(legBack, [(0.2, 0.17), (-0.6, 0.08), (nil, 0.12), (0, 0.25)])
            track(body, [(-0.2, 0.17), (-0.35, 0.08), (nil, 0.12), (0, 0.25)])
            track(head, [(-0.1, 0.17), (0.2, 0.08), (nil, 0.12), (0, 0.25)])
            body.run(.sequence([pose(y: restY * 1.05, x: -12, d: 0.17, .easeOut), pose(y: restY * 0.82, x: 30, d: 0.08, .easeIn), .wait(forDuration: 0.12), pose(y: restY, d: 0.25), returnToIdle]))
            run(.sequence([.wait(forDuration: 0.17), .run { [weak self] in self?.pop(at: CGPoint(x: 66, y: 20)) }]))
        }
    }

    /// Tap: quick straight punch with the off hand (the one without the sword).
    private func jab() {
        if variant != 0 { jabVariant(variant); return }
        track(armOff, [(1.55, 0.04), (nil, 0.03), (0, 0.1)])
        track(armWeapon, [(armRest - 0.35, 0.04), (nil, 0.03), (armRest, 0.1)])   // guard hand tucks up
        // Whole-body punch: step into a lunge, drop the weight, twist the shoulders through, then recover.
        track(legFront, [(0.55, 0.04), (nil, 0.03), (0, 0.1)])       // lead foot steps out and plants
        track(legBack,  [(-0.45, 0.04), (nil, 0.03), (0, 0.1)])      // rear leg drives off the ground
        track(body,     [(-0.14, 0.04), (nil, 0.03), (0, 0.1)])      // shoulders lean into the punch
        track(head,     [(0.1, 0.04), (nil, 0.03), (0, 0.1)])        // chin stays level against the lean
        body.run(.sequence([
            pose(y: restY * 0.94, x: 12, d: 0.04, .easeIn),
            .wait(forDuration: 0.03),
            pose(y: restY, d: 0.1),
            returnToIdle
        ]))
        run(.sequence([.wait(forDuration: 0.04), .run { [weak self] in self?.pop(at: CGPoint(x: 50, y: 0)) }]))
    }

    /// Forward swipe: wide hooking swing with the weapon hand, committing the whole body.
    private func hook() {
        if variant != 0 { hookVariant(variant); return }
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

    /// Coil back with the whole body, then unwind into a huge overhand: hips and shoulders rotate, the rear leg drives.
    private func haymaker() {
        if variant != 0 { haymakerVariant(variant); return }
        track(armWeapon, [(-1.5, 0.17), (1.55, 0.08), (nil, 0.12), (armRest, 0.25)])      // cocked far back, then thrown
        track(armOff,    [(1.7, 0.17), (0.4, 0.08), (nil, 0.12), (0, 0.25)])              // guard hand up by the chin
        track(legFront,  [(-0.2, 0.17), (0.7, 0.08), (nil, 0.12), (0, 0.25)])             // lead foot steps through
        track(legBack,   [(0.4, 0.17), (-0.7, 0.08), (nil, 0.12), (0, 0.25)])             // rear leg drives off
        track(body,      [(0.32, 0.17), (-0.3, 0.08), (nil, 0.12), (0, 0.25)])            // wind up away, then throw the shoulder
        track(head,      [(-0.12, 0.17), (0.14, 0.08), (nil, 0.12), (0, 0.25)])
        body.run(.sequence([
            pose(y: restY * 0.85, x: -20, d: 0.17, .easeOut),                              // sink and load the back foot
            pose(y: restY * 0.92, x: 34, d: 0.08, .easeIn),                                // explode forward
            .wait(forDuration: 0.12),
            pose(y: restY, d: 0.25),
            returnToIdle
        ]))
        run(.sequence([.wait(forDuration: 0.17), .run { [weak self] in self?.pop(at: CGPoint(x: 70, y: 40)) }]))
    }

    /// Tuck and tumble backward in 0.3s: arms and legs pull in, the body does one full backflip-style rotation, then lands low.
    private func roll() {
        track(armWeapon, [(1.2, 0.06), (nil, 0.2), (armRest, 0.12)])
        track(armOff,    [(1.2, 0.06), (nil, 0.2), (0, 0.12)])
        track(legFront,  [(1.3, 0.06), (nil, 0.2), (0, 0.12)])
        track(legBack,   [(1.1, 0.06), (nil, 0.2), (0, 0.12)])
        track(head,      [(0.5, 0.06), (nil, 0.2), (0, 0.12)])
        body.run(.sequence([
            .group([pose(y: restY * 0.8, sx: 0.9, sy: 0.85, d: 0.06, .easeOut), .rotate(byAngle: 0.4, duration: 0.06)]),
            .rotate(byAngle: .pi * 2 - 0.4, duration: 0.24),
            .group([pose(y: restY, d: 0.1), .run { [weak self] in self?.body.zRotation = 0 }]),
            returnToIdle
        ]))
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

    /// Mid-air strike: lead arm snaps out, rear knee tucks up, body leans in. No return to idle: the jump's fall takes over.
    private func airStrike() {
        track(armWeapon, [(1.55, 0.05), (nil, 0.12), (0.9, 0.12)])
        track(armOff, [(-0.5, 0.05), (nil, 0.12), (0.2, 0.12)])
        track(legFront, [(1.2, 0.06), (nil, 0.1), (0.5, 0.12)])
        track(legBack, [(-0.4, 0.06), (nil, 0.1), (0, 0.12)])
        track(body, [(-0.28, 0.05), (nil, 0.12), (-0.08, 0.14)])
        track(head, [(0.1, 0.05), (nil, 0.12), (0, 0.14)])
        body.run(pose(y: restY, x: 12, sx: 0.97, sy: 1.03, d: 0.06))
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
    /// Wind the arm back, then whip it forward. The rock leaves the hand 0.15s in.
    private func throwRock() {
        track(armWeapon, [(2.7, 0.12), (nil, 0.03), (0.8, 0.07), (nil, 0.1), (armRest, 0.14)])
        track(armOff,    [(-0.6, 0.12), (nil, 0.03), (0.3, 0.07), (nil, 0.1), (0, 0.14)])
        track(body,      [(0.1, 0.12), (nil, 0.03), (-0.12, 0.07), (nil, 0.1), (0, 0.14)])
        body.run(.sequence([.wait(forDuration: 0.46), returnToIdle]))
    }

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
        track(body, [(-0.6, 0.09), (nil, 0.05), (0, 0.12)])
        body.run(.sequence([
            pose(y: restY * 0.6, sx: 1.06, sy: 0.9, d: 0.09),
            .wait(forDuration: 0.05),
            pose(y: restY, d: 0.12),
            returnToIdle
        ]))
        track(armOff,   [(0.6, 0.09), (nil, 0.05), (0, 0.12)])        // cancels the lean: the arm points straight down
        track(head,     [(0.35, 0.09), (nil, 0.05), (0, 0.12)])       // eyes stay forward
        track(legFront, [(0.6, 0.09), (nil, 0.05), (0, 0.12)])
        track(legBack,  [(-0.5, 0.09), (nil, 0.05), (0, 0.12)])
    }

    /// Blasted flat: topples backwards, limbs flung out, and stays down until the fighter gets up.
    private func knockdown() {
        if reaction != 0 { knockdownVariant(reaction); return }
        track(body, [(1.5, 0.14)])
        body.run(pose(y: restY * 0.7, d: 0.14, .easeOut))
        track(head, [(0.25, 0.14)])
        // Arms fly up with the impact, then drop and lie flat along the ground (the body is tipped ~86 deg, so ~0 is flat)
        track(armWeapon, [(2.3, 0.14), (0.12, 0.38)])
        track(armOff, [(1.9, 0.14), (nil, 0.05), (0.26, 0.36)])
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

    // MARK: Special

    private func powerUp() {
        track(armWeapon, [(2.5, 0.25), (2.1, 0.12), (2.5, 0.12)], loop: true)      // fists up, flexing
        track(armOff,    [(2.5, 0.25), (2.1, 0.12), (2.5, 0.12)], loop: true)
        track(legFront,  [(0.45, 0.25)])                                            // wide, planted stance
        track(legBack,   [(-0.45, 0.25)])
        track(head,      [(0.3, 0.25)])                                             // chin up, roaring
        track(body,      [(-0.12, 0.25), (-0.2, 0.1), (-0.12, 0.1)], loop: true)
        body.run(.repeatForever(.sequence([pose(y: restY * 0.88, x: 2, d: 0.05), pose(y: restY * 0.9, x: -2, d: 0.05)])))   // trembling
    }

    /// Arms overhead, then a crushing ground pound. The shockwave lands ~0.19s in (Hit.rageShockwave.start).
    private func rageSlam() {
        track(armWeapon, [(3.0, 0.14), (0.5, 0.05), (nil, 0.25), (armRest, 0.3)])
        track(armOff,    [(3.0, 0.14), (0.5, 0.05), (nil, 0.25), (0, 0.3)])
        track(legFront,  [(0.8, 0.14), (0.9, 0.05), (nil, 0.25), (0, 0.3)])
        track(legBack,   [(-0.8, 0.14), (-0.9, 0.05), (nil, 0.25), (0, 0.3)])
        track(body,      [(-0.15, 0.14), (0.3, 0.05), (nil, 0.25), (0, 0.3)])
        track(head,      [(0.2, 0.14), (-0.1, 0.05), (nil, 0.25), (0, 0.3)])
        body.run(.sequence([pose(y: restY + 16, d: 0.14, .easeOut), pose(y: restY * 0.74, d: 0.05, .easeIn),
                            .wait(forDuration: 0.25), pose(y: restY, d: 0.3), returnToIdle]))
    }

    /// Red glow and rising embers behind the body while powering up.
    private lazy var aura: SKNode = {
        let n = SKNode(); n.position = CGPoint(x: 0, y: 90); n.zPosition = -0.5; n.isHidden = true
        let glow = SKShapeNode(ellipseOf: CGSize(width: 130, height: 200))
        glow.name = "glow"
        glow.fillColor = SKColor(red: 1, green: 0.15, blue: 0.1, alpha: 0.3)
        glow.strokeColor = SKColor(red: 1, green: 0.5, blue: 0.2, alpha: 0.8); glow.lineWidth = 4; glow.glowWidth = 10
        n.addChild(glow); addChild(n)
        return n
    }()

    func setAura(_ on: Bool) {
        aura.removeAllActions()
        aura.childNode(withName: "glow")?.removeAllActions()
        aura.children.filter { $0.name != "glow" }.forEach { $0.removeFromParent() }
        aura.isHidden = !on
        guard on else { return }
        aura.childNode(withName: "glow")?.run(.repeatForever(.sequence([
            .group([.scale(to: 1.18, duration: 0.18), .fadeAlpha(to: 1, duration: 0.18)]),
            .group([.scale(to: 0.95, duration: 0.18), .fadeAlpha(to: 0.5, duration: 0.18)])])))
        aura.run(.repeatForever(.sequence([.wait(forDuration: 0.06), .run { [weak self] in self?.emitEmber() }])))
    }

    private func emitEmber() {
        let e = styled(SKShapeNode(rect: CGRect(x: -3, y: -3, width: 6, height: 6)),
                       SKColor(red: 1, green: .random(in: 0.3...0.7), blue: 0.1, alpha: 1), line: 0)
        e.position = CGPoint(x: .random(in: -45...45), y: -85)
        aura.addChild(e)
        e.run(.sequence([.group([.moveBy(x: .random(in: -15...15), y: .random(in: 120...190), duration: 0.5), .fadeOut(withDuration: 0.5)]),
                         .removeFromParent()]))
    }

    private func headRock() {
        track(head, [(0.8, 0.09), (nil, 0.14), (0, 0.3)])
        track(body, [(-0.18, 0.09), (nil, 0.14), (0, 0.3)])
        track(armWeapon, [(1.1, 0.09), (armRest, 0.4)])
        track(armOff, [(0.9, 0.09), (0, 0.4)])
        body.run(.sequence([pose(y: restY, x: -10, d: 0.09, .easeOut), pose(y: restY, d: 0.4), returnToIdle]))
    }

    private func hit() {
        if reaction != 0 { hitVariant(reaction); return }
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

    /// Which alternate flinch / knockdown to play (0 = the standard one). Visual only: durations match the standard poses.
    var reaction = 0

    /// 1: spun half-around, head whipped to the side, arms flung out. 2: folds forward over the hit, knees buckling.
    private func hitVariant(_ v: Int) {
        if v == 1 {
            body.run(.sequence([pose(y: restY, x: -18, d: 0.08, .easeOut), pose(y: restY, d: 0.25), returnToIdle]))
            track(body, [(-0.28, 0.08), (0, 0.3)])
            track(head, [(-0.75, 0.08), (0, 0.3)])
            track(armWeapon, [(2.5, 0.08), (armRest, 0.3)])
            track(armOff, [(2.1, 0.08), (0, 0.3)])
            track(legFront, [(0.5, 0.08), (0, 0.3)])
            track(legBack, [(-0.4, 0.08), (0, 0.3)])
        } else {
            body.run(.sequence([pose(y: restY * 0.86, x: -8, sx: 1.08, sy: 0.88, d: 0.08, .easeOut), pose(y: restY, d: 0.25), returnToIdle]))
            track(body, [(-0.5, 0.08), (0, 0.3)])
            track(head, [(-0.35, 0.08), (0, 0.3)])
            track(armWeapon, [(0.7, 0.08), (armRest, 0.3)])
            track(armOff, [(0.6, 0.08), (0, 0.3)])
            track(legFront, [(0.7, 0.08), (0, 0.3)])
            track(legBack, [(-0.4, 0.08), (0, 0.3)])
        }
        run(.repeat(.sequence([.fadeAlpha(to: 0.3, duration: 0.05), .fadeAlpha(to: 1, duration: 0.05)]), count: 4))
    }

    /// 1: a face-plant, arms stretched out ahead. 2: slumps into a sit, legs out in front, head down.
    private func knockdownVariant(_ v: Int) {
        if v == 1 {
            track(body, [(-1.5, 0.14)])
            body.run(pose(y: restY * 0.7, d: 0.14, .easeOut))
            track(head, [(-0.25, 0.14)])
            track(armWeapon, [(3.0, 0.14), (2.7, 0.3)])
            track(armOff, [(2.8, 0.14), (2.5, 0.3)])
            track(legFront, [(-0.4, 0.14)])
            track(legBack, [(-0.2, 0.14)])
        } else {
            track(body, [(0.9, 0.16)])
            body.run(pose(y: restY * 0.58, d: 0.16, .easeOut))
            track(head, [(-0.5, 0.16)])
            track(armWeapon, [(0.5, 0.16)])
            track(armOff, [(0.3, 0.16)])
            track(legFront, [(1.45, 0.16)])
            track(legBack, [(1.1, 0.16)])
        }
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
        path.addArc(center: .zero, radius: radius * (finisher ? 1.5 : 1), startAngle: start, endAngle: end, clockwise: clockwise)
        let fx = SKShapeNode(path: path)
        fx.strokeColor = finisher ? SKColor(red: 1, green: 0.82, blue: 0.2, alpha: 1) : .white; fx.lineWidth = finisher ? 15 : 8; fx.lineCap = .round; fx.glowWidth = finisher ? 9 : 3
        fx.position = CGPoint(x: layout.offShoulder.x, y: restY + lift)
        fx.zPosition = 10
        (parent ?? self).addChild(fx)
        fx.run(.sequence([.group([.fadeOut(withDuration: 0.18), .scale(to: 1.15, duration: 0.18)]),
                          .removeFromParent()]))
    }

    /// Small impact flash at the fist.
    private func pop(at p: CGPoint, height: CGFloat? = nil) {
        let star = styled(SKShapeNode(circleOfRadius: 9), .white, line: 3)
        star.position = CGPoint(x: p.x, y: height ?? restY + 44)
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
