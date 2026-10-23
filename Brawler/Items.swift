import SpriteKit

// MARK: - Data

/// A weapon is data: a name, how hard it hits, and how to draw it (grip at the origin, blade along +y).
struct Weapon {
    let name: String
    var power: CGFloat = 1          // multiplies the damage of weapon moves (hook family, uppercut, slams)
    var ammo: Int? = nil            // nil = no ammo system; otherwise shots left (travels with the weapon when dropped)
    var capacity = 12               // most ammo it can hold
    var consumable = false          // vanishes from the hand once its ammo is spent (a thrown rock)
    var moves: [MoveKey: Move] = [:]   // overrides of the default move table while this weapon is held
    var lightBonus: CGFloat = 0     // widens the holder's light in dark levels (0.22 = 22% wider)
    let make: () -> SKNode

    var isRanged: Bool { !consumable && moves.values.contains { $0.projectile != nil } }   // archers kite and refill; one-shot throwables don't
}

/// A consumable. `apply` returns true when it was used up; false leaves it on the ground (e.g. food at full health).
struct Item {
    let name: String
    let make: () -> SKNode
    let apply: (Fighter) -> Bool
    var permanent = false           // never fades or gets evicted (survival buffs)
}

enum PickupKind { case weapon(Weapon), item(Item) }

enum Weapons {
    static let sword = Weapon(name: "sword") {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -4, y: 0)); p.addLine(to: CGPoint(x: 4, y: 0))
        p.addLine(to: CGPoint(x: 3, y: 46)); p.addLine(to: CGPoint(x: 0, y: 56))
        p.addLine(to: CGPoint(x: -3, y: 46)); p.closeSubpath()
        let sword = SKShapeNode(path: p)
        styled(sword, SKColor(white: 0.9, alpha: 1), line: 3)
        let guardBar = styled(SKShapeNode(rect: CGRect(x: -9, y: -3, width: 18, height: 6), cornerRadius: 3),
                              SKColor(red: 0.5, green: 0.3, blue: 0.15, alpha: 1), line: 3)
        let blood = styled(SKShapeNode(ellipseOf: CGSize(width: 6, height: 14)),
                           SKColor(red: 0.75, green: 0.05, blue: 0.1, alpha: 1), line: 0)
        blood.position = CGPoint(x: 0, y: 38)
        sword.addChild(blood)
        sword.addChild(guardBar)
        return sword
    }

    /// Sleeps in the Blackout's altar. Hits like a slightly better sword, and its glow widens the light around its holder.
    static let lightblade = Weapon(name: "light blade", power: 1.15, lightBonus: 0.22) {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -4, y: 0)); p.addLine(to: CGPoint(x: 4, y: 0))
        p.addLine(to: CGPoint(x: 3, y: 48)); p.addLine(to: CGPoint(x: 0, y: 60))
        p.addLine(to: CGPoint(x: -3, y: 48)); p.closeSubpath()
        let blade = SKShapeNode(path: p)
        styled(blade, SKColor(red: 1, green: 0.95, blue: 0.62, alpha: 1), line: 3)
        blade.glowWidth = 9
        let guardBar = styled(SKShapeNode(rect: CGRect(x: -10, y: -3, width: 20, height: 6), cornerRadius: 3), SKColor(red: 0.95, green: 0.74, blue: 0.2, alpha: 1), line: 3)
        let gem = styled(SKShapeNode(circleOfRadius: 3.5), SKColor(red: 1, green: 0.4, blue: 0.2, alpha: 1), line: 1)
        gem.position = CGPoint(x: 0, y: 0); gem.zPosition = 1; gem.glowWidth = 4
        blade.addChild(guardBar); blade.addChild(gem)
        return blade
    }

    static let rustyBlade = Weapon(name: "rusty blade") {
        styled(SKShapeNode(rect: CGRect(x: -3, y: 0, width: 6, height: 42), cornerRadius: 2),
               SKColor(red: 0.6, green: 0.55, blue: 0.5, alpha: 1), line: 3)
    }

    static let axe = Weapon(name: "axe", power: 1.3) {
        let handle = styled(SKShapeNode(rect: CGRect(x: -3, y: -8, width: 6, height: 62), cornerRadius: 2),
                            SKColor(red: 0.5, green: 0.33, blue: 0.18, alpha: 1), line: 3)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 3, y: 30)); p.addLine(to: CGPoint(x: 26, y: 22))
        p.addLine(to: CGPoint(x: 26, y: 58)); p.addLine(to: CGPoint(x: 3, y: 50)); p.closeSubpath()
        handle.addChild(styled(SKShapeNode(path: p), SKColor(white: 0.72, alpha: 1), line: 3))
        return handle
    }

    /// Reach over speed. Tap pokes from a distance; a forward swipe lunges into a long thrust. Narrow, so it needs lane alignment.
    static let spear = Weapon(name: "spear", moves: [
        MoveKey(context: .grounded, trigger: .tap):
            Move(name: "spear poke", animation: .jab, lock: 0.3, lunge: 80).hitting(.spearPoke).armed,
        MoveKey(context: .grounded, trigger: .forward):
            Move(name: "spear thrust", animation: .hook, lock: 0.55, lunge: 260).hitting(.spearThrust).armed.emphasized(.light),
    ]) {
        let shaft = styled(SKShapeNode(rect: CGRect(x: -2.5, y: -22, width: 5, height: 104), cornerRadius: 2),
                           SKColor(red: 0.55, green: 0.38, blue: 0.2, alpha: 1), line: 3)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -7, y: 80)); p.addLine(to: CGPoint(x: 0, y: 110)); p.addLine(to: CGPoint(x: 7, y: 80)); p.closeSubpath()
        shaft.addChild(styled(SKShapeNode(path: p), SKColor(white: 0.88, alpha: 1), line: 3))
        return shaft
    }

    /// Slow and heavy. Tap or forward swipe: a long overhead wind-up, then a ground slam in front that shatters shields.
    /// Only hits what is on the ground (jump it) and can be rolled through. Everything else stays as normal.
    static let hammer = Weapon(name: "hammer", power: 1.2, moves: [
        MoveKey(context: .grounded, trigger: .tap):
            Move(name: "hammer slam", animation: .hammerSlam, lock: 0.8, plant: true).hitting(.hammer).armed.emphasized(.heavy),
        MoveKey(context: .grounded, trigger: .forward):
            Move(name: "hammer slam", animation: .hammerSlam, lock: 0.8, plant: true).hitting(.hammer).armed.emphasized(.heavy),
    ]) {
        let shaft = styled(SKShapeNode(rect: CGRect(x: -3, y: -10, width: 6, height: 74), cornerRadius: 2),
                           SKColor(red: 0.5, green: 0.33, blue: 0.18, alpha: 1), line: 3)
        let head = styled(SKShapeNode(rect: CGRect(x: -19, y: 56, width: 38, height: 26), cornerRadius: 4),
                          SKColor(red: 0.45, green: 0.47, blue: 0.54, alpha: 1), line: 3)
        let band = styled(SKShapeNode(rect: CGRect(x: -19, y: 64, width: 38, height: 6)), SKColor(red: 0.95, green: 0.78, blue: 0.3, alpha: 1), line: 2)
        shaft.addChild(head); shaft.addChild(band)
        return shaft
    }

    /// No roll: a back swipe raises the guard (see Fighter.enterGuard). Held, it absorbs frontal hits; a forward swipe releases them.
    static let shield = Weapon(name: "shield", power: 0.8, moves: [
        MoveKey(context: .grounded, trigger: .back): Move(name: "guard", animation: .guardUp, lock: 0.1),
        MoveKey(context: .running, trigger: .back): Move(name: "guard", animation: .guardUp, lock: 0.1),
    ]) {
        let n = SKNode()
        let glow = styled(SKShapeNode(ellipseOf: CGSize(width: 39, height: 110)), SKColor(red: 1, green: 0.85, blue: 0.4, alpha: 1), line: 0)
        glow.name = "glow"; glow.alpha = 0; glow.position = CGPoint(x: 0, y: 20); glow.zPosition = -1
        let face = styled(SKShapeNode(ellipseOf: CGSize(width: 25, height: 90)), SKColor(red: 0.50, green: 0.55, blue: 0.66, alpha: 1), line: 4)
        face.position = CGPoint(x: 0, y: 20)
        let boss = styled(SKShapeNode(ellipseOf: CGSize(width: 9, height: 62)), SKColor(red: 0.95, green: 0.78, blue: 0.3, alpha: 1), line: 2)
        boss.position = CGPoint(x: 0, y: 20)
        [glow, face, boss].forEach(n.addChild)
        return n
    }

    /// Weak in melee (0.6x). A back swipe draws and looses an arrow straight ahead; every other gesture is unchanged.
    static let bow = Weapon(name: "bow", power: 0.6, ammo: 8, capacity: 12, moves: [
        MoveKey(context: .grounded, trigger: .back):
            Move(name: "shoot", animation: .shoot, lock: 0.45, fire: 0.18, projectile: .arrow)
    ]) {
        let bow = SKNode()
        let limb = CGMutablePath()
        limb.move(to: CGPoint(x: -3, y: -32)); limb.addQuadCurve(to: CGPoint(x: -3, y: 32), control: CGPoint(x: 26, y: 0))
        let outline = SKShapeNode(path: limb)
        outline.strokeColor = ink; outline.lineWidth = 11; outline.lineCap = .round
        let wood = SKShapeNode(path: limb)
        wood.strokeColor = SKColor(red: 0.62, green: 0.40, blue: 0.22, alpha: 1); wood.lineWidth = 5; wood.lineCap = .round
        let str = CGMutablePath()
        str.move(to: CGPoint(x: -3, y: -32)); str.addLine(to: CGPoint(x: -3, y: 32))
        let string = SKShapeNode(path: str)
        string.strokeColor = SKColor(white: 0.95, alpha: 1); string.lineWidth = 2
        [outline, wood, string].forEach(bow.addChild)

        // Shown during the draw: string pulled back with an arrow nocked
        let nocked = SKNode(); nocked.name = "nocked"; nocked.isHidden = true; nocked.zPosition = 1
        let pull = CGMutablePath()
        pull.move(to: CGPoint(x: -3, y: -32)); pull.addLine(to: CGPoint(x: -20, y: 0)); pull.addLine(to: CGPoint(x: -3, y: 32))
        let pulled = SKShapeNode(path: pull)
        pulled.strokeColor = SKColor(white: 0.95, alpha: 1); pulled.lineWidth = 2
        nocked.addChild(pulled)
        nocked.addChild(Weapons.arrowArt(scale: 0.8, at: CGPoint(x: 4, y: 0)))
        bow.addChild(nocked)
        return bow
    }

    /// The Necromancer's staff. A back swipe fires a slow bone bolt (the same gesture archers use).
    static let staff = Weapon(name: "staff", moves: staffMoves) { staffArt() }

    private static let staffMoves: [MoveKey: Move] = {
        let bolt = Move(name: "bone bolt", animation: .shoot, lock: 0.55, fire: 0.3, projectile: .necroBolt, shot: Shot(kind: .bolt, speed: 520))
        var m: [MoveKey: Move] = [:]
        m[MoveKey(context: .grounded, trigger: .back)] = bolt
        m[MoveKey(context: .running, trigger: .back)] = bolt
        return m
    }()

    static func staffArt() -> SKNode {
        let pole = styled(SKShapeNode(rect: CGRect(x: -2.5, y: -30, width: 5, height: 110), cornerRadius: 2),
                          SKColor(red: 0.3, green: 0.2, blue: 0.14, alpha: 1), line: 3)
        let orb = styled(SKShapeNode(circleOfRadius: 10), SKColor(red: 0.6, green: 1, blue: 0.7, alpha: 1), line: 3)
        orb.position = CGPoint(x: 0, y: 88); orb.glowWidth = 6
        orb.run(.repeatForever(.sequence([.scale(to: 1.18, duration: 0.5), .scale(to: 0.9, duration: 0.5)])))
        pole.addChild(orb)
        return pole
    }

    /// The frost wizards' staff. A back swipe throws an ice bolt that slows whoever it hits.
    static let iceStaff = Weapon(name: "ice staff", moves: iceStaffMoves) { iceStaffArt() }

    private static let iceStaffMoves: [MoveKey: Move] = {
        let bolt = Move(name: "ice bolt", animation: .shoot, lock: 0.55, fire: 0.3, projectile: .iceBolt, shot: Shot(kind: .ice, speed: 560))
        var m: [MoveKey: Move] = [:]
        m[MoveKey(context: .grounded, trigger: .back)] = bolt
        m[MoveKey(context: .running, trigger: .back)] = bolt
        return m
    }()

    /// A demon's innate fire bolt: the ice bolt's timing, plain damage, no weapon needed.
    static let fireBreathMoves: [MoveKey: Move] = {
        let bolt = Move(name: "fire bolt", animation: .shoot, lock: 0.55, fire: 0.3, projectile: .fireBolt, shot: Shot(kind: .fire, speed: 520))
        return [MoveKey(context: .grounded, trigger: .back): bolt, MoveKey(context: .running, trigger: .back): bolt]
    }()

    static func iceStaffArt() -> SKNode {
        let pole = styled(SKShapeNode(rect: CGRect(x: -2.5, y: -30, width: 5, height: 110), cornerRadius: 2), SKColor(red: 0.55, green: 0.62, blue: 0.72, alpha: 1), line: 3)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: 14)); p.addLine(to: CGPoint(x: 9, y: 0)); p.addLine(to: CGPoint(x: 0, y: -12)); p.addLine(to: CGPoint(x: -9, y: 0)); p.closeSubpath()
        let crystal = styled(SKShapeNode(path: p), SKColor(red: 0.72, green: 0.95, blue: 1, alpha: 1), line: 3)
        crystal.position = CGPoint(x: 0, y: 90); crystal.glowWidth = 7
        crystal.run(.repeatForever(.sequence([.scale(to: 1.18, duration: 0.5), .scale(to: 0.9, duration: 0.5)])))
        pole.addChild(crystal)
        return pole
    }

    static func iceBoltArt() -> SKNode {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 22, y: 0)); p.addLine(to: CGPoint(x: 0, y: 10)); p.addLine(to: CGPoint(x: -16, y: 0)); p.addLine(to: CGPoint(x: 0, y: -10)); p.closeSubpath()
        let core = styled(SKShapeNode(path: p), SKColor(red: 0.72, green: 0.95, blue: 1, alpha: 1), line: 3)
        core.glowWidth = 9
        let shine = styled(SKShapeNode(ellipseOf: CGSize(width: 14, height: 4)), .white, line: 0)
        shine.position = CGPoint(x: 3, y: 2); core.addChild(shine)
        for (i, r) in [CGFloat(7), 5, 3].enumerated() {
            let t = SKShapeNode(circleOfRadius: r)
            t.fillColor = SKColor(red: 0.8, green: 0.95, blue: 1, alpha: 0.55 - CGFloat(i) * 0.14); t.strokeColor = .clear
            t.position = CGPoint(x: -CGFloat(i + 1) * 15 - 8, y: 0); t.zPosition = -1
            core.addChild(t)
        }
        core.run(.repeatForever(.sequence([.scale(to: 1.12, duration: 0.12), .scale(to: 0.92, duration: 0.12)])))
        return core
    }

    static func fireBoltArt() -> SKNode {
        let core = styled(SKShapeNode(circleOfRadius: 11), SKColor(red: 1, green: 0.62, blue: 0.15, alpha: 1), line: 3)
        core.glowWidth = 10
        let hot = styled(SKShapeNode(circleOfRadius: 5), SKColor(red: 1, green: 0.95, blue: 0.6, alpha: 1), line: 0)
        core.addChild(hot)
        for (i, r) in [CGFloat(9), 7, 4].enumerated() {
            let t = SKShapeNode(circleOfRadius: r)
            t.fillColor = SKColor(red: 1, green: 0.35, blue: 0.1, alpha: 0.55 - CGFloat(i) * 0.14); t.strokeColor = .clear
            t.position = CGPoint(x: -CGFloat(i + 1) * 15 - 6, y: 0); t.zPosition = -1
            core.addChild(t)
        }
        core.run(.repeatForever(.sequence([.scale(to: 1.15, duration: 0.1), .scale(to: 0.88, duration: 0.1)])))
        return core
    }

    static func boltArt() -> SKNode {
        let core = styled(SKShapeNode(circleOfRadius: 11), SKColor(red: 0.7, green: 1, blue: 0.75, alpha: 1), line: 3)
        core.glowWidth = 9
        for (i, r) in [CGFloat(8), 6, 4].enumerated() {
            let t = SKShapeNode(circleOfRadius: r)
            t.fillColor = SKColor(red: 0.5, green: 0.9, blue: 0.6, alpha: 0.5 - CGFloat(i) * 0.12); t.strokeColor = .clear
            t.position = CGPoint(x: -CGFloat(i + 1) * 14, y: 0); t.zPosition = -1
            core.addChild(t)
        }
        core.run(.repeatForever(.sequence([.scale(to: 1.15, duration: 0.12), .scale(to: 0.9, duration: 0.12)])))
        return core
    }

    /// One-shot. Tap, forward and back swipes all throw it (up still jumps); in the air it's thrown down at an angle.
    static let rock = Weapon(name: "rock", ammo: 1, capacity: 1, consumable: true, moves: rockMoves) { rockArt() }

    private static let rockMoves: [MoveKey: Move] = {
        let ground = Move(name: "throw", animation: .throwRock, lock: 0.4, fire: 0.15, projectile: .rock,
                          shot: Shot(kind: .rock, speed: 900, vz: 260, gravity: 1800))
        let air = Move(name: "air throw", animation: .throwRock, fire: 0.15, projectile: .rock,
                       shot: Shot(kind: .rock, speed: 760, vz: -620, gravity: 1200))
        var m: [MoveKey: Move] = [:]
        for t in [Trigger.tap, .back, .forward] {
            m[MoveKey(context: .grounded, trigger: t)] = ground
            m[MoveKey(context: .running, trigger: t)] = ground
            m[MoveKey(context: .airborne, trigger: t)] = air
        }
        return m
    }()

    /// One-shot. Lobbed in a high arc; after it lands the fuse blinks faster and faster, then it explodes.
    static let bomb = Weapon(name: "bomb", ammo: 1, capacity: 1, consumable: true, moves: bombMoves) { bombArt() }

    private static let bombMoves: [MoveKey: Move] = {
        let ground = Move(name: "lob", animation: .throwRock, lock: 0.5, fire: 0.18, projectile: .bombThrow,
                          shot: Shot(kind: .bomb, speed: 560, vz: 520, gravity: 1500))
        let air = Move(name: "air lob", animation: .throwRock, fire: 0.18, projectile: .bombThrow,
                       shot: Shot(kind: .bomb, speed: 480, vz: -380, gravity: 1200))
        var m: [MoveKey: Move] = [:]
        for t in [Trigger.tap, .back, .forward] {
            m[MoveKey(context: .grounded, trigger: t)] = ground
            m[MoveKey(context: .running, trigger: t)] = ground
            m[MoveKey(context: .airborne, trigger: t)] = air
        }
        return m
    }()

    static func bombArt() -> SKNode {
        let body = styled(SKShapeNode(circleOfRadius: 13), SKColor(white: 0.13, alpha: 1), line: 3)
        body.name = "body"
        let shine = styled(SKShapeNode(ellipseOf: CGSize(width: 6, height: 4)), SKColor(white: 0.7, alpha: 1), line: 0)
        shine.position = CGPoint(x: -5, y: 5); body.addChild(shine)
        let cap = styled(SKShapeNode(rect: CGRect(x: -5, y: 11, width: 10, height: 6), cornerRadius: 1), SKColor(white: 0.45, alpha: 1), line: 2)
        body.addChild(cap)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: 16)); p.addQuadCurve(to: CGPoint(x: 8, y: 27), control: CGPoint(x: -4, y: 24))
        let fuse = SKShapeNode(path: p); fuse.strokeColor = SKColor(red: 0.75, green: 0.6, blue: 0.35, alpha: 1); fuse.lineWidth = 3; fuse.lineCap = .round
        body.addChild(fuse)
        let spark = styled(SKShapeNode(circleOfRadius: 4), SKColor(red: 1, green: 0.75, blue: 0.2, alpha: 1), line: 0)
        spark.name = "light"; spark.position = CGPoint(x: 8, y: 28); spark.glowWidth = 5
        spark.run(.repeatForever(.sequence([.scale(to: 1.5, duration: 0.07), .scale(to: 0.8, duration: 0.07)])))
        body.addChild(spark)
        return body
    }

    static func rockArt() -> SKNode {
        let p = CGMutablePath()
        let pts: [(CGFloat, CGFloat)] = [(-11, -3), (-6, -9), (5, -9), (11, -2), (8, 8), (-3, 10), (-10, 5)]
        p.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
        pts.dropFirst().forEach { p.addLine(to: CGPoint(x: $0.0, y: $0.1)) }
        p.closeSubpath()
        let rock = styled(SKShapeNode(path: p), SKColor(white: 0.55, alpha: 1), line: 3)
        let shade = styled(SKShapeNode(ellipseOf: CGSize(width: 8, height: 5)), SKColor(white: 0.4, alpha: 1), line: 0)
        shade.position = CGPoint(x: 2, y: -3)
        rock.addChild(shade)
        return rock
    }

    /// A horizontal arrow pointing +x, centered on the origin.
    static func arrowArt(scale: CGFloat = 1, at p: CGPoint = .zero) -> SKNode {
        let arrow = SKNode()
        let shaft = styled(SKShapeNode(rect: CGRect(x: -24, y: -2.5, width: 44, height: 5), cornerRadius: 2),
                           SKColor(red: 0.72, green: 0.56, blue: 0.34, alpha: 1), line: 3)
        let head = CGMutablePath()
        head.move(to: CGPoint(x: 18, y: -8)); head.addLine(to: CGPoint(x: 36, y: 0)); head.addLine(to: CGPoint(x: 18, y: 8)); head.closeSubpath()
        let tip = styled(SKShapeNode(path: head), SKColor(white: 0.85, alpha: 1), line: 3)
        for sy: CGFloat in [-1, 1] {
            let f = CGMutablePath()
            f.move(to: CGPoint(x: -20, y: 0)); f.addLine(to: CGPoint(x: -34, y: 9 * sy))
            f.addLine(to: CGPoint(x: -26, y: 9 * sy)); f.addLine(to: CGPoint(x: -12, y: 0)); f.closeSubpath()
            arrow.addChild(styled(SKShapeNode(path: f), SKColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1), line: 2))
        }
        [shaft, tip].forEach(arrow.addChild)
        arrow.setScale(scale); arrow.position = p
        return arrow
    }
}

enum Items {
    /// An apple. Restores a bit of health; stays on the ground if you're already full.
    static let food = Item(name: "apple", make: {
        let apple = styled(SKShapeNode(circleOfRadius: 11), SKColor(red: 0.85, green: 0.2, blue: 0.2, alpha: 1), line: 3)
        let shine = styled(SKShapeNode(ellipseOf: CGSize(width: 5, height: 8)), SKColor(white: 1, alpha: 0.7), line: 0)
        shine.position = CGPoint(x: -4, y: 3)
        let stem = styled(SKShapeNode(rect: CGRect(x: -1.5, y: 9, width: 3, height: 7)), SKColor(red: 0.4, green: 0.25, blue: 0.15, alpha: 1), line: 2)
        let leaf = styled(SKShapeNode(ellipseOf: CGSize(width: 10, height: 6)), SKColor(red: 0.35, green: 0.75, blue: 0.3, alpha: 1), line: 2)
        leaf.position = CGPoint(x: 7, y: 14)
        [shine, stem, leaf].forEach(apple.addChild)
        return apple
    }, apply: { $0.heal(25) })

    /// Six arrows. Only used if you're holding a bow with room in the quiver.
    static let quiver = Item(name: "quiver", make: {
        let q = styled(SKShapeNode(rect: CGRect(x: -9, y: -14, width: 18, height: 28), cornerRadius: 6),
                       SKColor(red: 0.5, green: 0.32, blue: 0.18, alpha: 1), line: 3)
        for dx: CGFloat in [-5, 0, 5] {
            let shaft = styled(SKShapeNode(rect: CGRect(x: dx - 1.2, y: 10, width: 2.4, height: 14)), SKColor(red: 0.72, green: 0.56, blue: 0.34, alpha: 1), line: 1.5)
            let tip = CGMutablePath()
            tip.move(to: CGPoint(x: dx - 3.5, y: 22)); tip.addLine(to: CGPoint(x: dx, y: 29)); tip.addLine(to: CGPoint(x: dx + 3.5, y: 22)); tip.closeSubpath()
            q.addChild(shaft); q.addChild(styled(SKShapeNode(path: tip), SKColor(white: 0.85, alpha: 1), line: 1.5))
        }
        q.zRotation = 0.25
        return q
    }, apply: { $0.addAmmo(6) })
}

// MARK: - Survival buffs

/// Permanent power-ups for the rest of a survival run. Dropped by giants and hidden in the arena's altars.
enum Buff: String, CaseIterable {
    case swiftness = "SWIFTNESS", might = "MIGHT", vitality = "VITALITY", frenzy = "FRENZY"

    var color: SKColor {
        switch self {
        case .swiftness: return SKColor(red: 0.35, green: 0.85, blue: 1, alpha: 1)
        case .might:     return SKColor(red: 1, green: 0.5, blue: 0.2, alpha: 1)
        case .vitality:  return SKColor(red: 0.45, green: 1, blue: 0.45, alpha: 1)
        case .frenzy:    return SKColor(red: 1, green: 0.9, blue: 0.25, alpha: 1)
        }
    }
    var cap: Int? { self == .swiftness ? 5 : self == .frenzy ? 4 : nil }  // swings tuned for feel: +32% is the limit
    func isMaxed(_ f: Fighter) -> Bool { cap.map { (f.buffs[rawValue] ?? 0) >= $0 } ?? false }

    /// +8% run speed, +10% damage dealt, +15% max health (and the same healed), or +8% attack speed.
    func apply(to f: Fighter) -> Bool {
        guard !isMaxed(f) else { return false }
        switch self {
        case .swiftness: f.stats.runSpeed *= 1.08
        case .might:     f.stats.damageScale *= 1.10
        case .frenzy:    f.stats.attackSpeed += 0.08
        case .vitality:  f.raiseMaxHealth(by: (f.stats.maxHealth * 0.15).rounded())
        }
        f.buffs[rawValue, default: 0] += 1
        f.world?.floatText(rawValue + " UP", at: CGPoint(x: f.rig.position.x, y: f.rig.position.y + f.rig.height + 170), color: color)
        NSLog("BUFF %@ x%d: runSpeed %.0f damageScale %.2f attackSpeed %.2f maxHealth %.0f health %.0f", rawValue, f.buffs[rawValue] ?? 0, f.stats.runSpeed, f.stats.damageScale, f.stats.attackSpeed, f.stats.maxHealth, f.health)
        return true
    }

    var item: Item {
        let b = self
        return Item(name: rawValue.lowercased(), make: {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: 15)); p.addLine(to: CGPoint(x: 11, y: 0)); p.addLine(to: CGPoint(x: 0, y: -15)); p.addLine(to: CGPoint(x: -11, y: 0)); p.closeSubpath()
            let gem = styled(SKShapeNode(path: p), b.color, line: 3)
            gem.glowWidth = 5
            let shine = styled(SKShapeNode(ellipseOf: CGSize(width: 4, height: 9)), SKColor(white: 1, alpha: 0.8), line: 0)
            shine.position = CGPoint(x: -3, y: 4); gem.addChild(shine)
            gem.run(.repeatForever(.sequence([.scale(to: 1.15, duration: 0.6), .scale(to: 0.95, duration: 0.6)])))
            return gem
        }, apply: { b.apply(to: $0) }, permanent: true)
    }

    /// A random buff the hero can still use.
    static func random(for hero: Fighter) -> Buff { allCases.filter { !$0.isMaxed(hero) }.randomElement() ?? .might }
}

// MARK: - World objects

/// Something lying on the ground (or tumbling through the air after a drop).
final class Pickup: SKNode {
    let kind: PickupKind
    var tag = -1                            // index into the area's props, so a revisit knows what's already been taken
    let lane: CGFloat                       // ground y
    private(set) var height: CGFloat
    private(set) var landed = false
    private var vx: CGFloat, vz: CGFloat, spin: CGFloat
    private let art = SKNode()
    private let shadow = styled(SKShapeNode(ellipseOf: CGSize(width: 44, height: 11)), SKColor(white: 0, alpha: 0.28), line: 0)
    private let marker = SKShapeNode(ellipseOf: CGSize(width: 62, height: 16))
    private let lying: CGFloat = .pi / 2 + 0.2

    var label: String {
        switch kind { case .weapon(let w): return w.name; case .item(let i): return i.name }
    }

    init(kind: PickupKind, x: CGFloat, lane: CGFloat, height: CGFloat, vx: CGFloat, vz: CGFloat, spin: CGFloat) {
        self.kind = kind; self.lane = lane; self.height = height
        self.vx = vx; self.vz = vz; self.spin = spin
        super.init()
        switch kind {
        case .weapon(let w): art.addChild(w.make())
        case .item(let i):   art.addChild(i.make())
        }
        art.setScale(1.3)
        marker.strokeColor = .white; marker.lineWidth = 3; marker.fillColor = .clear; marker.alpha = 0
        addChild(shadow); addChild(marker); addChild(art)
        position = CGPoint(x: x, y: lane + height)
        zPosition = 8000
    }
    required init?(coder: NSCoder) { fatalError() }

    func step(_ dt: CGFloat, minX: CGFloat, maxX: CGFloat) {
        guard !landed else { return }
        vz -= 2400 * dt
        height += vz * dt
        position.x = min(max(position.x + vx * dt, minX), maxX)
        art.zRotation += spin * dt
        if height <= 0 { settle(animated: true) }
        position.y = lane + height
        shadow.position.y = -height; marker.position.y = -height
        shadow.setScale(max(0.4, 1 - height / 300))
    }

    /// Come to rest on the ground: weapons lie flat, food bobs, everything gets a pulsing marker so it reads as pickable.
    func settle(animated: Bool) {
        height = 0; landed = true; vx = 0
        position.y = lane; shadow.position.y = 0; marker.position.y = 0; shadow.setScale(1)
        zPosition = 300 - lane - 1
        if case .weapon = kind {
            if animated { art.run(.rotate(toAngle: lying, duration: 0.1, shortestUnitArc: true)) } else { art.zRotation = lying }
        } else {
            art.run(.repeatForever(.sequence([.moveBy(x: 0, y: 4, duration: 0.7), .moveBy(x: 0, y: -4, duration: 0.7)])))
        }
        if animated { art.run(.sequence([.moveBy(x: 0, y: 10, duration: 0.07), .moveBy(x: 0, y: -10, duration: 0.07)])) }
        marker.run(.repeatForever(.sequence([.fadeAlpha(to: 0.7, duration: 0.6), .fadeAlpha(to: 0.15, duration: 0.6)])))
    }
}

/// Everything on the ground. Fighters ask it what's at their feet.
final class PickupField: SKNode {
    static let reachX: CGFloat = 80, reachY: CGFloat = 40
    var maxPickups = 6                                   // oldest fades out beyond this
    private(set) var pickups: [Pickup] = []

    /// Toss something into the air; it tumbles and lands.
    func launch(_ kind: PickupKind, from p: CGPoint, height: CGFloat, vx: CGFloat, vz: CGFloat) {
        let pk = Pickup(kind: kind, x: p.x, lane: p.y, height: height, vx: vx, vz: vz, spin: vx >= 0 ? 14 : -14)
        if case .weapon = kind { expire(pk) }
        add(pk)
    }

    /// Dropped weapons clean themselves up: they blink for the last 1.5s, then vanish.
    static let weaponLifetime: TimeInterval = 10
    private func expire(_ pk: Pickup) {
        let blink = SKAction.repeat(.sequence([.fadeAlpha(to: 0.15, duration: 0.15), .fadeAlpha(to: 1, duration: 0.15)]), count: 5)
        pk.run(.sequence([.wait(forDuration: Self.weaponLifetime - 1.5), blink,
                          .run { [weak self, weak pk] in if let pk { self?.pickups.removeAll { $0 === pk } } },
                          .removeFromParent()]), withKey: "expire")
    }

    /// Put something straight on the ground.
    @discardableResult
    func place(_ kind: PickupKind, at p: CGPoint) -> Pickup {
        let pk = Pickup(kind: kind, x: p.x, lane: p.y, height: 0, vx: 0, vz: 0, spin: 0)
        pk.settle(animated: false)
        add(pk)
        return pk
    }

    private func add(_ pk: Pickup) {
        pickups.append(pk); addChild(pk)
        while pickups.count > maxPickups, let old = pickups.first(where: { pk in
            if case .item(let i) = pk.kind, i.permanent { return false }
            return pk.landed
        }) {
            pickups.removeAll { $0 === old }
            old.run(.sequence([.fadeOut(withDuration: 0.25), .removeFromParent()]))
        }
    }

    /// The closest landed pickup within arm's reach. Items are skipped unless the fighter collects them.
    func nearest(to p: CGPoint, items: Bool) -> Pickup? {
        pickups.filter { pk in
            guard pk.landed, abs(pk.position.x - p.x) <= Self.reachX, abs(pk.lane - p.y) <= Self.reachY else { return false }
            if case .item = pk.kind { return items }
            return true
        }.min { abs($0.position.x - p.x) < abs($1.position.x - p.x) }
    }

    func take(_ pk: Pickup) {
        pickups.removeAll { $0 === pk }
        pk.removeAction(forKey: "expire")
        pk.run(.sequence([.group([.scale(to: 1.4, duration: 0.15), .fadeOut(withDuration: 0.15)]), .removeFromParent()]))
    }

    func clear() { pickups.forEach { $0.removeFromParent() }; pickups = [] }

    func step(dt: CGFloat, minX: CGFloat, maxX: CGFloat) { pickups.forEach { $0.step(dt, minX: minX, maxX: maxX) } }

    func floatText(_ text: String, at p: CGPoint, color: SKColor) {
        for (i, c) in [SKColor.black, color].enumerated() {
            let l = SKLabelNode(fontNamed: GameFont.speech)
            l.text = text; l.fontSize = 31; l.fontColor = c
            l.position = CGPoint(x: p.x + (i == 0 ? 2 : 0), y: p.y + (i == 0 ? -2 : 0)); l.zPosition = 9500 + CGFloat(i)
            addChild(l)
            l.run(.sequence([.group([.moveBy(x: 0, y: 55, duration: 0.8),
                                     .sequence([.wait(forDuration: 0.4), .fadeOut(withDuration: 0.4)])]),
                             .removeFromParent()]))
        }
    }
}


// MARK: - Projectiles

/// An arrow or rock in flight. Both stay in their lane, so jumping over them works.
/// Arrows fly level; a rock arcs under gravity and, once it lands, blinks out.
final class Projectile: SKNode {
    let owner: Fighter
    let hit: Hit
    let shot: Shot
    let dir: CGFloat
    let lane: CGFloat
    let lift: CGFloat = 62               // launch point above the feet
    let art: SKNode
    fileprivate(set) var height: CGFloat // feet-level height of the launcher, plus the arc so far
    fileprivate(set) var vz: CGFloat
    fileprivate(set) var travelled: CGFloat = 0
    var spent = false

    init(owner: Fighter, hit: Hit, shot: Shot, dir: CGFloat, x: CGFloat, lane: CGFloat, height: CGFloat) {
        self.owner = owner; self.hit = hit; self.shot = shot; self.dir = dir; self.lane = lane
        self.height = height; self.vz = shot.vz
        switch shot.kind {
        case .rock:  art = Weapons.rockArt()
        case .bomb:  art = Weapons.bombArt()
        case .bolt:  art = Weapons.boltArt()
        case .ice:   art = Weapons.iceBoltArt()
        case .fire:  art = Weapons.fireBoltArt()
        case .arrow: art = Weapons.arrowArt()
        }
        super.init()
        addChild(art)
        if shot.kind == .arrow || shot.kind == .ice || shot.kind == .fire { xScale = dir }
        position = CGPoint(x: x, y: lane + height + lift)
        zPosition = 305 - lane
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class ProjectileField: SKNode {
    static let maxRange: CGFloat = 1100
    private(set) var arrows: [Projectile] = []
    private var fusing: [Projectile] = []
    var onExplode: ((CGPoint, Fighter) -> Void)?       // a bomb's fuse ran out: where, and who threw it

    func launch(from p: CGPoint, height: CGFloat, dir: CGFloat, owner: Fighter, hit: Hit, shot: Shot = Shot()) {
        let a = Projectile(owner: owner, hit: hit, shot: shot, dir: dir, x: p.x, lane: p.y, height: height)
        arrows.append(a); addChild(a)
    }

    func step(dt: CGFloat, minX: CGFloat, maxX: CGFloat) {
        for a in arrows {
            let d = a.shot.speed * dt
            a.position.x += a.dir * d; a.travelled += d
            if a.shot.kind == .rock || a.shot.kind == .bomb {
                a.vz -= a.shot.gravity * dt
                a.height += a.vz * dt
                a.position.y = a.lane + a.height + a.lift
                a.art.zRotation -= a.dir * 14 * dt
                if a.height + a.lift <= 0 { if a.shot.kind == .bomb { fuse(a) } else { land(a) }; continue }
            }
            if a.travelled > Self.maxRange || a.position.x < minX - 100 || a.position.x > maxX + 100 { remove(a, hit: false) }
        }
    }

    /// A bomb reaches the ground and sits there: the light blinks faster and faster, then it goes off.
    private func fuse(_ a: Projectile) {
        guard let i = arrows.firstIndex(where: { $0 === a }) else { return }
        arrows.remove(at: i); a.spent = true; fusing.append(a)
        a.position.y = a.lane + 14
        a.zPosition = 300 - a.lane - 1
        a.art.zRotation = 0
        NSLog("BOMB landed x%.0f lane%.0f", a.position.x, a.lane)
        let body = a.art as? SKShapeNode
        let light = a.art.childNode(withName: "light")
        var steps: [SKAction] = []
        var on = false
        for d in [0.22, 0.22, 0.17, 0.17, 0.12, 0.12, 0.08, 0.08, 0.05, 0.05] as [TimeInterval] {
            on.toggle()
            let lit = on
            steps.append(.run { body?.fillColor = lit ? SKColor(red: 0.9, green: 0.15, blue: 0.1, alpha: 1) : SKColor(white: 0.13, alpha: 1); light?.alpha = lit ? 1 : 0.3; a.art.setScale(lit ? 1.18 : 1) })
            steps.append(.wait(forDuration: d))
        }
        steps.append(.run { [weak self, weak a] in
            guard let self, let a else { return }
            self.fusing.removeAll { $0 === a }
            self.onExplode?(CGPoint(x: a.position.x, y: a.lane), a.owner)
            a.removeFromParent()
        })
        a.run(.sequence(steps), withKey: "fuse")
    }

    /// A rock reaches the ground: it can no longer hit anyone, sits there briefly, then blinks out. No reuse.
    private func land(_ a: Projectile) {
        guard let i = arrows.firstIndex(where: { $0 === a }) else { return }
        arrows.remove(at: i); a.spent = true
        a.position.y = a.lane
        a.zPosition = 300 - a.lane - 1
        a.run(.sequence([.wait(forDuration: 0.35),
                         .repeat(.sequence([.fadeAlpha(to: 0.1, duration: 0.06), .fadeAlpha(to: 1, duration: 0.06)]), count: 5),
                         .removeFromParent()]))
    }

    func remove(_ a: Projectile, hit: Bool) {
        guard let i = arrows.firstIndex(where: { $0 === a }) else { return }
        arrows.remove(at: i); a.spent = true
        a.run(.sequence([hit ? .group([.scale(to: 0.6, duration: 0.08), .fadeOut(withDuration: 0.08)]) : .fadeOut(withDuration: 0.25),
                         .removeFromParent()]))
    }

    func clear() { arrows.forEach { $0.removeFromParent() }; arrows = []; fusing.forEach { $0.removeAllActions(); $0.removeFromParent() }; fusing = [] }
}


// MARK: - Crates

/// A big wooden crate. Blocks fighters, takes only the hero's melee hits (enemies and projectiles pass through it
/// harmlessly), and when it breaks it drops whatever was inside. No health bar: it just cracks, then goes.
final class Crate: SKNode {
    static let halfWidth: CGFloat = 58, halfDepth: CGFloat = 24, height: CGFloat = 92
    let contents: PickupKind?
    enum Style { case crate, altar, bush, witheredBush }
    let style: Style
    var isAltar: Bool { style == .altar }         // a stack of stones with an idol on top (tougher, breaks into rubble)
    var isBush: Bool { style == .bush || style == .witheredBush }
    var blocks: Bool { !isBush }                  // bushes can be walked through
    private(set) var halfWidth = Crate.halfWidth, halfDepth = Crate.halfDepth, height = Crate.height
    var tag = -1                           // index into the area's props
    private(set) var health: CGFloat = 40
    private var maxHealth: CGFloat = 40
    private let art = SKNode()
    private var cracks = 0

    init(x: CGFloat, lane: CGFloat, contents: PickupKind?, altar: Bool = false, style: Style? = nil, scale: CGFloat = 1) {
        self.contents = contents
        self.style = style ?? (altar ? .altar : .crate)
        if self.style == .altar { health = 70; maxHealth = 70 }
        if self.style == .bush || self.style == .witheredBush { health = 1; maxHealth = 1 }
        super.init()
        position = CGPoint(x: x, y: lane)
        zPosition = 300 - lane
        if self.style == .altar { buildAltar(); return }
        if isBush { buildBush(scale: scale); return }
        let wood = SKColor(red: 0.62, green: 0.43, blue: 0.22, alpha: 1)
        let dark = SKColor(red: 0.42, green: 0.27, blue: 0.13, alpha: 1)
        let w = Self.halfWidth * 2, h = Self.height
        art.addChild(styled(SKShapeNode(rect: CGRect(x: -w / 2, y: 0, width: w, height: h), cornerRadius: 4), wood, line: 4))
        for y in [h * 0.33, h * 0.66] {                                    // plank seams
            art.addChild(styled(SKShapeNode(rect: CGRect(x: -w / 2 + 3, y: y - 1.5, width: w - 6, height: 3)), dark, line: 0))
        }
        for sx: CGFloat in [-1, 1] {                                         // corner braces
            art.addChild(styled(SKShapeNode(rect: CGRect(x: sx * (w / 2 - 12) - 6, y: 4, width: 12, height: h - 8)), dark, line: 0))
        }
        let p = CGMutablePath()                                              // diagonal brace
        p.move(to: CGPoint(x: -w / 2 + 10, y: 10)); p.addLine(to: CGPoint(x: w / 2 - 10, y: h - 10))
        let brace = SKShapeNode(path: p); brace.strokeColor = dark; brace.lineWidth = 7; art.addChild(brace)
        addChild(art)
        let shadow = SKShapeNode(ellipseOf: CGSize(width: w * 1.1, height: 26))
        shadow.fillColor = SKColor(white: 0, alpha: 0.3); shadow.strokeColor = .clear; shadow.zPosition = -1
        addChild(shadow)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildAltar() {
        let stone = SKColor(red: 0.50, green: 0.51, blue: 0.56, alpha: 1), dark = SKColor(red: 0.36, green: 0.37, blue: 0.42, alpha: 1)
        let moss = SKColor(red: 0.28, green: 0.46, blue: 0.30, alpha: 1)
        var y: CGFloat = 0
        for (w, h, c) in [(116, 24, dark), (94, 20, stone), (72, 16, dark)] as [(CGFloat, CGFloat, SKColor)] {
            art.addChild(styled(SKShapeNode(rect: CGRect(x: -w / 2, y: y, width: w, height: h), cornerRadius: 5), c, line: 4))
            y += h - 2
        }
        for (mx, my) in [(-44, 10), (30, 30), (-20, 44)] as [(CGFloat, CGFloat)] {
            let patch = styled(SKShapeNode(ellipseOf: CGSize(width: 22, height: 8)), moss, line: 0)
            patch.position = CGPoint(x: mx, y: my); patch.zPosition = 1
            art.addChild(patch)
        }
        let idol = SKNode(); idol.position = CGPoint(x: 0, y: y)
        idol.addChild(styled(SKShapeNode(rect: CGRect(x: -13, y: 0, width: 26, height: 18), cornerRadius: 6), moss, line: 3))
        let head = styled(SKShapeNode(circleOfRadius: 12), moss, line: 3)
        head.position = CGPoint(x: 0, y: 28)
        for ex: CGFloat in [-5, 5] {
            let eye = styled(SKShapeNode(ellipseOf: CGSize(width: 5, height: 6)), SKColor(red: 1, green: 0.82, blue: 0.3, alpha: 1), line: 0)
            eye.position = CGPoint(x: ex, y: 2); eye.glowWidth = 5
            head.addChild(eye)
        }
        idol.addChild(head)
        art.addChild(idol)
        addChild(art)
        let shadow = SKShapeNode(ellipseOf: CGSize(width: Self.halfWidth * 2.2, height: 26))
        shadow.fillColor = SKColor(white: 0, alpha: 0.3); shadow.strokeColor = .clear; shadow.zPosition = -1
        addChild(shadow)
    }

    /// A leafy shrub: overlapping blobs, a few berries (or bare twigs when withered), swaying very slightly.
    private func buildBush(scale: CGFloat) {
        let withered = style == .witheredBush
        let dark  = withered ? SKColor(red: 0.24, green: 0.24, blue: 0.16, alpha: 1) : SKColor(red: 0.16, green: 0.40, blue: 0.21, alpha: 1)
        let mid   = withered ? SKColor(red: 0.36, green: 0.36, blue: 0.22, alpha: 1) : SKColor(red: 0.27, green: 0.58, blue: 0.27, alpha: 1)
        let light = withered ? SKColor(red: 0.50, green: 0.46, blue: 0.27, alpha: 1) : SKColor(red: 0.43, green: 0.73, blue: 0.34, alpha: 1)
        halfWidth = 34 * scale; halfDepth = 16 * scale; height = 56 * scale
        for (x, y, r, c) in [(-22, 18, 20, dark), (23, 16, 22, dark), (0, 27, 28, mid), (-13, 38, 17, light), (14, 40, 15, light)] as [(CGFloat, CGFloat, CGFloat, SKColor)] {
            let blob = styled(SKShapeNode(circleOfRadius: r), c, line: 3)
            blob.position = CGPoint(x: x, y: y)
            art.addChild(blob)
        }
        if withered {
            for (x, a) in [(-14, 0.5), (4, -0.1), (18, -0.6)] as [(CGFloat, CGFloat)] {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: x, y: 30)); p.addLine(to: CGPoint(x: x + sin(a) * 34, y: 30 + cos(a) * 34))
                let twig = SKShapeNode(path: p); twig.strokeColor = SKColor(red: 0.22, green: 0.17, blue: 0.12, alpha: 1); twig.lineWidth = 3; twig.lineCap = .round
                twig.zPosition = 3
                art.addChild(twig)
            }
        } else if Bool.random() {
            for (x, y) in [(-8, 30), (12, 22), (22, 38)] as [(CGFloat, CGFloat)] {
                let berry = styled(SKShapeNode(circleOfRadius: 3.5), SKColor(red: 0.85, green: 0.15, blue: 0.2, alpha: 1), line: 1)
                berry.position = CGPoint(x: x, y: y); berry.zPosition = 3
                art.addChild(berry)
            }
        }
        art.setScale(scale)
        art.run(.sequence([.wait(forDuration: .random(in: 0...2)),
                           .repeatForever(.sequence([.rotate(toAngle: 0.03, duration: .random(in: 1.1...1.9)), .rotate(toAngle: -0.03, duration: .random(in: 1.1...1.9))]))]))
        addChild(art)
        let shadow = SKShapeNode(ellipseOf: CGSize(width: halfWidth * 2.1, height: 14 * scale))
        shadow.fillColor = SKColor(white: 0, alpha: 0.25); shadow.strokeColor = .clear; shadow.zPosition = -1
        addChild(shadow)
    }

    /// Returns true if this blow broke it.
    func damage(_ amount: CGFloat, fromRight: Bool) -> Bool {
        health -= amount
        art.removeAction(forKey: "wobble")
        let s: CGFloat = fromRight ? -1 : 1
        art.run(.sequence([.moveBy(x: s * 7, y: 0, duration: 0.03), .moveBy(x: -s * 11, y: 0, duration: 0.05), .moveBy(x: s * 4, y: 0, duration: 0.04)]),
                withKey: "wobble")
        let want = health <= maxHealth * 0.34 ? 2 : health <= maxHealth * 0.67 ? 1 : 0
        while cracks < want { cracks += 1; addCrack() }
        return health <= 0
    }

    private func addCrack() {
        guard !isBush else { return }
        let p = CGMutablePath(), x = CGFloat.random(in: -34...34), y = height * CGFloat.random(in: 0.35...0.8)
        p.move(to: CGPoint(x: x, y: y))
        p.addLine(to: CGPoint(x: x + 9, y: y - 16)); p.addLine(to: CGPoint(x: x - 4, y: y - 26)); p.addLine(to: CGPoint(x: x + 8, y: y - 42))
        let c = SKShapeNode(path: p); c.strokeColor = SKColor(white: 0.1, alpha: 0.85); c.lineWidth = 3; c.zPosition = 2
        art.addChild(c)
    }
}

final class CrateField: SKNode {
    private(set) var crates: [Crate] = []

    @discardableResult
    func place(x: CGFloat, lane: CGFloat, contents: PickupKind? = nil, altar: Bool = false, style: Crate.Style? = nil, scale: CGFloat = 1) -> Crate {
        let c = Crate(x: x, lane: lane, contents: contents, altar: altar, style: style, scale: scale)
        crates.append(c); addChild(c)
        return c
    }

    func clear() { crates.forEach { $0.removeFromParent() }; crates = [] }

    /// Hero melee hits only. Each hit window strikes a given crate once.
    func resolve(hero a: Fighter, pickups: PickupField) -> [Combat.Contact] {
        guard !a.dead else { return [] }
        var contacts: [Combat.Contact] = []
        let dir: CGFloat = a.rig.facingRight ? 1 : -1
        for (index, hit, power) in a.activeHits {
            for c in crates where !a.isHurt {
                let dx = (c.position.x - a.rig.position.x) * dir, s = a.stats.size
                guard dx >= hit.reach.lowerBound * s - c.halfWidth, dx <= hit.reach.upperBound * s + c.halfWidth,
                      abs(c.position.y - a.rig.position.y) <= hit.depth + c.halfDepth,
                      a.claim(index, id: ObjectIdentifier(c)) else { continue }
                let dmg = hit.damage * power * a.damageMultiplier
                a.hitStop(c.isBush ? 0.015 : 0.04)
                contacts.append(Combat.Contact(point: CGPoint(x: c.position.x - dir * c.halfWidth, y: c.position.y + c.height * 0.55),
                                               damage: dmg, attacker: a, move: a.currentMove))
                if c.damage(dmg * hit.vsHeavy, fromRight: dir < 0) { smash(c, pickups: pickups) }
            }
        }
        return contacts
    }

    /// An explosion smashes every breakable inside its ellipse.
    func blast(at p: CGPoint, radiusX: CGFloat, radiusY: CGFloat, pickups: PickupField) {
        for c in crates {
            let d = hypot(max(0, abs(c.position.x - p.x) - c.halfWidth) / radiusX, max(0, abs(c.position.y - p.y) - c.halfDepth) / radiusY)
            if d <= 1, c.damage(120, fromRight: c.position.x < p.x) { smash(c, pickups: pickups) }
        }
    }

    private func burstLeaves(_ c: Crate) {
        let withered = c.style == .witheredBush
        let greens: [SKColor] = withered
            ? [SKColor(red: 0.36, green: 0.36, blue: 0.22, alpha: 1), SKColor(red: 0.50, green: 0.46, blue: 0.27, alpha: 1)]
            : [SKColor(red: 0.27, green: 0.58, blue: 0.27, alpha: 1), SKColor(red: 0.43, green: 0.73, blue: 0.34, alpha: 1), SKColor(red: 0.16, green: 0.40, blue: 0.21, alpha: 1)]
        for _ in 0..<16 {
            let leaf = styled(SKShapeNode(ellipseOf: CGSize(width: 14, height: 7)), greens.randomElement() ?? greens[0], line: 2)
            leaf.position = CGPoint(x: c.position.x + .random(in: -c.halfWidth...c.halfWidth), y: c.position.y + .random(in: 10...c.height))
            leaf.zPosition = c.zPosition + 1
            leaf.zRotation = .random(in: 0...(.pi))
            addChild(leaf)
            let dx = CGFloat.random(in: -150...150), up = CGFloat.random(in: 50...140), sway = CGFloat.random(in: 20...55) * (Bool.random() ? 1 : -1)
            leaf.run(.sequence([
                .group([.moveBy(x: dx, y: up, duration: 0.3).with(.easeOut), .rotate(byAngle: .random(in: -6...6), duration: 1.1)]),
                .group([.moveBy(x: sway, y: -up - 50, duration: 0.8).with(.easeIn), .rotate(byAngle: .random(in: -3...3), duration: 0.8)]),
                .fadeOut(withDuration: 0.3), .removeFromParent()]))
        }
        for _ in 0..<3 {
            let twig = styled(SKShapeNode(rect: CGRect(x: -11, y: -1.5, width: 22, height: 3)), SKColor(red: 0.40, green: 0.28, blue: 0.16, alpha: 1), line: 1)
            twig.position = CGPoint(x: c.position.x + .random(in: -20...20), y: c.position.y + .random(in: 14...40))
            twig.zPosition = c.zPosition + 1; twig.zRotation = .random(in: 0...(.pi))
            addChild(twig)
            let dx = CGFloat.random(in: -120...120), up = CGFloat.random(in: 30...90)
            twig.run(.sequence([.group([.moveBy(x: dx, y: up, duration: 0.25).with(.easeOut), .rotate(byAngle: .random(in: -5...5), duration: 0.6)]),
                                .moveBy(x: dx * 0.2, y: -up - 45, duration: 0.3).with(.easeIn), .fadeOut(withDuration: 0.2), .removeFromParent()]))
        }
    }

    private func smash(_ c: Crate, pickups: PickupField) {
        crates.removeAll { $0 === c }
        if c.isBush { burstLeaves(c); c.removeFromParent(); return }
        let wood = c.isAltar ? SKColor(red: 0.48, green: 0.49, blue: 0.54, alpha: 1) : SKColor(red: 0.62, green: 0.43, blue: 0.22, alpha: 1)
        for _ in 0..<10 {
            let plank = styled(SKShapeNode(rect: CGRect(x: -14, y: -4, width: 28, height: 8)), wood, line: 2)
            plank.position = CGPoint(x: c.position.x + .random(in: -Crate.halfWidth...Crate.halfWidth),
                                     y: c.position.y + .random(in: 10...Crate.height))
            plank.zPosition = c.zPosition + 1
            plank.zRotation = .random(in: 0...(.pi))
            addChild(plank)
            let dx = CGFloat.random(in: -170...170), up = CGFloat.random(in: 40...130)
            plank.run(.sequence([
                .group([.moveBy(x: dx, y: up, duration: 0.25).with(.easeOut),
                        .rotate(byAngle: .random(in: -5...5), duration: 0.6)]),
                .moveBy(x: dx * 0.2, y: -up - 70, duration: 0.3).with(.easeIn),
                .fadeOut(withDuration: 0.25), .removeFromParent()]))
        }
        if let kind = c.contents {
            pickups.launch(kind, from: c.position, height: 50, vx: .random(in: -70...70), vz: 520)
        }
        c.removeFromParent()
    }

    /// Fighters can't walk through crates (jump over to pass). Pushes them out along the shallowest side;
    /// when blocked head-on they slide toward the nearer lane edge so they walk around instead of getting stuck.
    func block(_ fighters: [Fighter], dt: CGFloat) {
        let fx: CGFloat = 22, fy: CGFloat = 8                    // a fighter's footprint half-extents
        for f in fighters where !f.dead && f.rig.height < Crate.height {
            for c in crates where c.blocks {
                let dx = f.rig.position.x - c.position.x, dy = f.rig.position.y - c.position.y
                let ox = c.halfWidth + fx - abs(dx), oy = c.halfDepth + fy - abs(dy)
                guard ox > 0, oy > 0 else { continue }
                if ox < oy * 2.2 {                                // side hit: push out sideways, slide around
                    f.rig.position.x += (dx >= 0 ? 1 : -1) * ox
                    f.rig.position.y += (dy >= 0 ? 1 : -1) * min(oy, 260 * dt)
                } else {
                    f.rig.position.y += (dy >= 0 ? 1 : -1) * oy
                }
                f.rig.zPosition = 300 - f.rig.position.y
            }
        }
    }
}

private extension SKAction {
    func with(_ mode: SKActionTimingMode) -> SKAction { timingMode = mode; return self }
}


// MARK: - Doors

/// A portal to a level. Swipe up in front of it to go in. Glows and spins faster when you're close enough to enter.
final class Door: SKNode {
    static let reachX: CGFloat = 90, reachY: CGFloat = 60
    let level: Int
    var area = -1                       // >= 0: leads to another area of the same level, not to a level
    var arrival = ""                   // which entry point of that area to appear at
    private let glow = SKShapeNode(ellipseOf: CGSize(width: 150, height: 236))
    private let swirl = SKNode()
    private let art = SKNode()
    private var near = false
    private var arcs: [SKShapeNode] = []
    private var arcColors: [SKColor] = []
    private let frameFill = SKColor(red: 0.1, green: 0.04, blue: 0.22, alpha: 1)
    private let hint = SKNode()
    private var frameNode: SKShapeNode?
    private let nearColors = [SKColor(red: 1, green: 0.95, blue: 0.5, alpha: 1), SKColor(red: 1, green: 0.6, blue: 0.2, alpha: 1), SKColor.white]

    init(x: CGFloat, lane: CGFloat, level: Int, name: String) {
        self.level = level
        super.init()
        position = CGPoint(x: x, y: lane)
        zPosition = 299.5 - lane
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 150, height: 24))
        shadow.fillColor = SKColor(white: 0, alpha: 0.3); shadow.strokeColor = .clear; shadow.zPosition = -1
        addChild(shadow)

        glow.position = CGPoint(x: 0, y: 100)
        glow.fillColor = SKColor(red: 0.6, green: 0.4, blue: 1, alpha: 0.25)
        glow.strokeColor = SKColor(red: 0.8, green: 0.7, blue: 1, alpha: 1); glow.lineWidth = 6; glow.glowWidth = 14
        glow.alpha = 0; glow.zPosition = -0.5
        addChild(glow)

        let frame = styled(SKShapeNode(ellipseOf: CGSize(width: 132, height: 208)), SKColor(red: 0.1, green: 0.04, blue: 0.22, alpha: 1), line: 6)
        frame.position = CGPoint(x: 0, y: 100)
        frameNode = frame
        art.addChild(frame)

        swirl.position = CGPoint(x: 0, y: 100); swirl.yScale = 1.5
        let colors = [SKColor(red: 0.45, green: 0.9, blue: 1, alpha: 1), SKColor(red: 0.85, green: 0.4, blue: 1, alpha: 1), SKColor(red: 1, green: 1, blue: 1, alpha: 0.9)]
        for (k, r) in [CGFloat(56), 40, 24].enumerated() {
            let p = CGMutablePath()
            p.addArc(center: .zero, radius: r, startAngle: 0, endAngle: .pi * 1.4, clockwise: false)
            let arc = SKShapeNode(path: p)
            arc.strokeColor = colors[k]; arc.lineWidth = 6; arc.lineCap = .round; arc.glowWidth = 3
            arc.run(.repeatForever(.rotate(byAngle: k % 2 == 0 ? .pi * 2 : -.pi * 2, duration: 1.6 + Double(k) * 0.5)))
            swirl.addChild(arc); arcs.append(arc)
        }
        arcColors = colors
        art.addChild(swirl)
        addChild(art)

        let title = SKLabelNode(fontNamed: GameFont.banner)
        title.text = name.uppercased(); title.fontSize = 20; title.fontColor = .white
        title.verticalAlignmentMode = .center; title.position = CGPoint(x: 0, y: 232); title.zPosition = 2
        let shade = SKLabelNode(fontNamed: GameFont.banner)
        shade.text = title.text; shade.fontSize = 20; shade.fontColor = .black; shade.verticalAlignmentMode = .center
        shade.position = CGPoint(x: 2, y: -2); shade.zPosition = -1
        title.addChild(shade)
        addChild(title)
        let arrow = CGMutablePath()
        arrow.move(to: CGPoint(x: -16, y: 0)); arrow.addLine(to: CGPoint(x: 0, y: 22)); arrow.addLine(to: CGPoint(x: 16, y: 0))
        arrow.addLine(to: CGPoint(x: 6, y: 0)); arrow.addLine(to: CGPoint(x: 6, y: -18)); arrow.addLine(to: CGPoint(x: -6, y: -18))
        arrow.addLine(to: CGPoint(x: -6, y: 0)); arrow.closeSubpath()
        hint.addChild(styled(SKShapeNode(path: arrow), SKColor(red: 1, green: 0.95, blue: 0.5, alpha: 1), line: 4))
        hint.position = CGPoint(x: 0, y: 270); hint.zPosition = 3; hint.alpha = 0
        addChild(hint)
        swirl.run(.repeatForever(.sequence([.scaleX(to: 1.06, duration: 0.8), .scaleX(to: 0.96, duration: 0.8)])))
    }
    required init?(coder: NSCoder) { fatalError() }

    func setNear(_ on: Bool) {
        guard on != near else { return }
        near = on
        glow.removeAllActions(); hint.removeAllActions(); swirl.speed = on ? 3 : 1
        // Near: the portal turns from cool cyan/violet to hot gold and a bobbing arrow says "swipe up"
        for (k, arc) in arcs.enumerated() { arc.strokeColor = on ? nearColors[k] : arcColors[k] }
        glow.strokeColor = on ? SKColor(red: 1, green: 0.85, blue: 0.3, alpha: 1) : SKColor(red: 0.8, green: 0.7, blue: 1, alpha: 1)
        glow.fillColor = on ? SKColor(red: 1, green: 0.75, blue: 0.2, alpha: 0.3) : SKColor(red: 0.6, green: 0.4, blue: 1, alpha: 0.25)
        frameNode?.fillColor = on ? SKColor(red: 0.3, green: 0.16, blue: 0.04, alpha: 1) : frameFill
        if on {
            glow.run(.repeatForever(.sequence([.fadeAlpha(to: 1, duration: 0.3), .fadeAlpha(to: 0.5, duration: 0.3)])))
            hint.run(.group([.fadeIn(withDuration: 0.12), .repeatForever(.sequence([.moveBy(x: 0, y: 12, duration: 0.3), .moveBy(x: 0, y: -12, duration: 0.3)]))]))
        } else {
            glow.run(.fadeOut(withDuration: 0.2))
            hint.run(.fadeOut(withDuration: 0.12)); hint.position.y = 270
        }
        art.run(.scale(to: on ? 1.05 : 1, duration: 0.15))
    }
}

final class DoorField: SKNode {
    private(set) var doors: [Door] = []

    func clear() { doors.forEach { $0.removeFromParent() }; doors = [] }

    func place(x: CGFloat, lane: CGFloat, level: Int, name: String, popIn: Bool = false, area: Int = -1, arrival: String = "") {
        let d = Door(x: x, lane: lane, level: level, name: name)
        d.area = area; d.arrival = arrival
        doors.append(d); addChild(d)
        if popIn {
            d.setScale(0.02); d.alpha = 0
            let grow = SKAction.scale(to: 1, duration: 0.5); grow.timingMode = .easeOut
            d.run(.group([grow, .fadeIn(withDuration: 0.3)]))
        }
    }

    func nearest(to p: CGPoint) -> Door? {
        doors.filter { abs($0.position.x - p.x) <= Door.reachX && abs($0.position.y - p.y) <= Door.reachY }
             .min { abs($0.position.x - p.x) < abs($1.position.x - p.x) }
    }

    func update(near p: CGPoint) {
        let n = nearest(to: p)
        for d in doors { d.setNear(d === n) }
    }
}
