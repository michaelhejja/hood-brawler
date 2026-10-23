import SpriteKit

// MARK: - Shared shape helpers (swap for sprites later)

let ink = SKColor(red: 0.08, green: 0.06, blue: 0.12, alpha: 1)

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
func limbShape(width: CGFloat, height: CGFloat, fill: SKColor, line: CGFloat = 4) -> SKShapeNode {
    styled(SKShapeNode(rect: CGRect(x: -width / 2, y: -height, width: width, height: height),
                       cornerRadius: width / 2), fill, line: line)
}

// MARK: - Skin contract

enum LegSide { case back, front }
enum ArmRole { case weapon, off }

/// Where the joints sit. The rig animates joints; a skin only has to fit this layout.
/// Rig space: origin at the feet, +y up, character faces +x. Weapon arm is on the BACK shoulder.
struct RigLayout {
    var restY: CGFloat = 30                                   // hip height above the feet
    var legBackX: CGFloat = -9
    var legFrontX: CGFloat = 9
    var weaponShoulder = CGPoint(x: -16, y: 44)
    var offShoulder = CGPoint(x: 17, y: 44)
    var headPivot = CGPoint(x: 2, y: 64)
    var wingJoint = CGPoint(x: -12, y: 40)                    // where drawn wings join the back (only used by skins that have wings)
    var armLength: CGFloat = 28                               // weapon attaches this far down the weapon arm
    var armRest: CGFloat = 0.5
    var weaponRest: CGFloat = .pi + 2.0
    var shadowSize = CGSize(width: 64, height: 14)
    /// Where the off hand goes for two-handed moves.
    var gripPoint: CGPoint { CGPoint(x: weaponShoulder.x + 8, y: weaponShoulder.y + 1) }
}

/// Art for one character look. Every part hangs from its joint (origin = joint), so any skin plays every animation.
/// Mix and match: a skin can build its parts from other skins' parts.
protocol Skin {
    var layout: RigLayout { get }
    func makeHead() -> SKNode
    func makeTorso() -> SKNode
    func makeLeg(_ side: LegSide) -> SKNode
    func makeArm(_ role: ArmRole) -> SKNode       // includes the hand
    var defaultWeapon: Weapon? { get }            // what this character starts with; nil = unarmed
    func makeWing(front: Bool) -> SKNode?         // optional: hangs from layout.wingJoint, drawn behind the body
}

extension Skin {
    func makeWing(front: Bool) -> SKNode? { nil }
}

// MARK: - Hero

struct HeroSkin: Skin {
    var defaultWeapon: Weapon? { Weapons.sword }
    private let cloak = SKColor(red: 0.36, green: 0.28, blue: 0.50, alpha: 1)
    private let cloakDark = SKColor(red: 0.24, green: 0.18, blue: 0.36, alpha: 1)
    var layout = RigLayout()

    func makeHead() -> SKNode {
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
        return hood
    }

    func makeTorso() -> SKNode {
        styled(SKShapeNode(rect: CGRect(x: -20, y: 0, width: 40, height: 48), cornerRadius: 14), cloak)
    }

    func makeLeg(_ side: LegSide) -> SKNode {
        limbShape(width: 14, height: 30, fill: side == .back ? cloakDark : cloak)
    }

    func makeArm(_ role: ArmRole) -> SKNode {
        switch role {
        case .weapon:
            return limbShape(width: 12, height: 28, fill: cloak)
        case .off:
            let arm = limbShape(width: 12, height: 28, fill: cloakDark)
            let fist = styled(SKShapeNode(circleOfRadius: 8), cloakDark)
            fist.position = CGPoint(x: 0, y: -28)
            arm.addChild(fist)
            return arm
        }
    }

}

// MARK: - Ember (second hero)

/// A fast, light fighter: crimson hood, a pale mask with gold eyes and a long scarf.
struct EmberSkin: Skin {
    var defaultWeapon: Weapon? { Weapons.axe }
    private let hood = SKColor(red: 0.74, green: 0.20, blue: 0.16, alpha: 1)
    private let hoodDark = SKColor(red: 0.50, green: 0.12, blue: 0.11, alpha: 1)
    private let gold = SKColor(red: 1, green: 0.80, blue: 0.25, alpha: 1)
    var layout = RigLayout()

    func makeHead() -> SKNode {
        let head = styled(SKShapeNode(circleOfRadius: 20), hood)
        let mask = styled(SKShapeNode(ellipseOf: CGSize(width: 24, height: 22)), SKColor(red: 0.93, green: 0.90, blue: 0.84, alpha: 1), line: 3)
        mask.position = CGPoint(x: 6, y: -1)
        for x: CGFloat in [-3, 5] {
            let eye = styled(SKShapeNode(ellipseOf: CGSize(width: 7, height: 5)), gold, line: 2)
            eye.position = CGPoint(x: x, y: 2); eye.glowWidth = 2
            mask.addChild(eye)
        }
        head.addChild(mask)
        let tail = CGMutablePath()                                                 // hood point trailing behind
        tail.move(to: CGPoint(x: -14, y: 10)); tail.addLine(to: CGPoint(x: -34, y: 2)); tail.addLine(to: CGPoint(x: -16, y: -6)); tail.closeSubpath()
        let point = styled(SKShapeNode(path: tail), hood, line: 3)
        point.zPosition = -1
        head.addChild(point)
        return head
    }

    func makeTorso() -> SKNode {
        let body = styled(SKShapeNode(rect: CGRect(x: -17, y: 0, width: 34, height: 48), cornerRadius: 12), hood)
        let scarf = CGMutablePath()
        scarf.move(to: CGPoint(x: -14, y: 44)); scarf.addLine(to: CGPoint(x: -40, y: 36)); scarf.addLine(to: CGPoint(x: -34, y: 26))
        scarf.addLine(to: CGPoint(x: -52, y: 20)); scarf.addLine(to: CGPoint(x: -14, y: 30)); scarf.closeSubpath()
        let s = styled(SKShapeNode(path: scarf), gold, line: 3)
        s.zPosition = -1
        body.addChild(s)
        let belt = styled(SKShapeNode(rect: CGRect(x: -17, y: 14, width: 34, height: 6)), hoodDark, line: 2)
        body.addChild(belt)
        return body
    }

    func makeLeg(_ side: LegSide) -> SKNode { limbShape(width: 12, height: 30, fill: side == .back ? hoodDark : hood) }

    func makeArm(_ role: ArmRole) -> SKNode {
        switch role {
        case .weapon: return limbShape(width: 10, height: 28, fill: hood)
        case .off:
            let arm = limbShape(width: 10, height: 28, fill: hoodDark)
            let fist = styled(SKShapeNode(circleOfRadius: 7), gold)
            fist.position = CGPoint(x: 0, y: -28)
            arm.addChild(fist)
            return arm
        }
    }
}

// MARK: - Bully (third hero)

/// A slow, heavy bruiser: steel helmet with a visor slit, broad pauldrons and thick limbs.
struct BullySkin: Skin {
    var defaultWeapon: Weapon? { Weapons.hammer }
    private let steel = SKColor(red: 0.50, green: 0.54, blue: 0.62, alpha: 1)
    private let steelDark = SKColor(red: 0.32, green: 0.35, blue: 0.42, alpha: 1)
    private let trim = SKColor(red: 0.92, green: 0.52, blue: 0.16, alpha: 1)
    var layout = RigLayout()

    func makeHead() -> SKNode {
        let head = styled(SKShapeNode(circleOfRadius: 21), steel)
        let visor = styled(SKShapeNode(rect: CGRect(x: -4, y: -3, width: 26, height: 8), cornerRadius: 3), ink, line: 2)
        visor.position = CGPoint(x: 1, y: 3)
        let glint = styled(SKShapeNode(rect: CGRect(x: 8, y: -1, width: 12, height: 3)), trim, line: 0)
        glint.glowWidth = 2
        visor.addChild(glint)
        head.addChild(visor)
        let crest = styled(SKShapeNode(rect: CGRect(x: -3, y: 16, width: 8, height: 14), cornerRadius: 3), trim, line: 3)
        crest.zPosition = -1
        head.addChild(crest)
        return head
    }

    func makeTorso() -> SKNode {
        let body = styled(SKShapeNode(rect: CGRect(x: -21, y: 0, width: 42, height: 50), cornerRadius: 12), steel)
        let plate = styled(SKShapeNode(rect: CGRect(x: -15, y: 10, width: 30, height: 30), cornerRadius: 8), steelDark, line: 2)
        body.addChild(plate)
        let belt = styled(SKShapeNode(rect: CGRect(x: -21, y: 6, width: 42, height: 7)), trim, line: 2)
        body.addChild(belt)
        for sx: CGFloat in [-1, 1] {                                              // pauldrons
            let p = styled(SKShapeNode(ellipseOf: CGSize(width: 22, height: 17)), steelDark, line: 3)
            p.position = CGPoint(x: sx * 19, y: 46)
            body.addChild(p)
        }
        return body
    }

    func makeLeg(_ side: LegSide) -> SKNode { limbShape(width: 15, height: 30, fill: side == .back ? steelDark : steel) }

    func makeArm(_ role: ArmRole) -> SKNode {
        let arm = limbShape(width: 14, height: 28, fill: role == .weapon ? steel : steelDark)
        let gauntlet = styled(SKShapeNode(circleOfRadius: 9), trim)
        gauntlet.position = CGPoint(x: 0, y: -28)
        arm.addChild(gauntlet)
        return arm
    }
}

/// The playable heroes. Everything else (moves, weapons, animations) is shared.
enum HeroKind: Int, CaseIterable {
    case cloak, ember, bully

    var title: String { ["CLOAK", "EMBER", "BULLY"][rawValue] }
    var skin: Skin {
        if self == .cloak, ProcessInfo.processInfo.arguments.contains("-templateskin") { return TemplateSkin() }      // the custom-proportion rig
        if self == .bully { return SpriteSkin.wrap("bully", BullySkin()) }
        if self == .ember { return SpriteSkin.wrap("ember", EmberSkin()) }
        return [TemplateSkin(), EmberSkin(), BullySkin()][rawValue]
    }
    var special: Special { [Specials.rageSlam, Specials.whirlwind, Specials.bullRush][rawValue] }
    var bulk: CGFloat { self == .bully ? 1.12 : 1 }
    var stats: FighterStats {
        var s = FighterStats()
        switch self {
        case .cloak: break
        case .ember:   s.runSpeed = 600; s.baseAccel = 1800; s.maxHealth = 75;  s.damageScale = 1.15     // quick and hits harder, but fragile
        case .bully: s.runSpeed = 400; s.baseAccel = 800;  s.maxHealth = 170; s.damageScale = 1.35     // slow, tough and heavy-handed
        }
        return s
    }

    /// The hero chosen on the menu (`-hero N` on the command line overrides it).
    static var selected: HeroKind {
        get {
            let a = ProcessInfo.processInfo.arguments
            if let i = a.firstIndex(of: "-hero"), i + 1 < a.count, let n = Int(a[i + 1]), let k = HeroKind(rawValue: n) { return k }
            return HeroKind(rawValue: UserDefaults.standard.integer(forKey: "hero")) ?? .cloak
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "hero") }
    }

    func makeFighter() -> Fighter {
        let f = Fighter(name: "hero", skin: skin, stats: stats)
        f.rig.scaleFactor = bulk
        return f
    }
}

// MARK: - Skeleton

struct SkeletonSkin: Skin {
    var defaultWeapon: Weapon? { Weapons.rustyBlade }
    private let bone = SKColor(white: 0.93, alpha: 1)
    var layout = RigLayout(restY: 28, legBackX: -7, legFrontX: 7,
                           weaponShoulder: CGPoint(x: -14, y: 44), offShoulder: CGPoint(x: 15, y: 44),
                           armLength: 26, shadowSize: CGSize(width: 56, height: 12))

    func makeHead() -> SKNode {
        let skull = styled(SKShapeNode(circleOfRadius: 16), bone)
        for x: CGFloat in [-5, 7] {
            let eye = styled(SKShapeNode(ellipseOf: CGSize(width: 8, height: 10)), ink, line: 0)
            eye.position = CGPoint(x: x, y: 3)
            skull.addChild(eye)
        }
        skull.addChild(styled(SKShapeNode(rect: CGRect(x: -8, y: -14, width: 20, height: 7), cornerRadius: 3),
                              bone, line: 3))
        return skull
    }

    func makeTorso() -> SKNode {
        let ribs = styled(SKShapeNode(rect: CGRect(x: -16, y: 0, width: 32, height: 46), cornerRadius: 10),
                          bone, line: 3)
        let lines = CGMutablePath()
        for y: CGFloat in [14, 25, 36] {
            lines.move(to: CGPoint(x: -10, y: y))
            lines.addLine(to: CGPoint(x: 10, y: y))
        }
        let ribLines = SKShapeNode(path: lines)
        ribLines.strokeColor = ink
        ribLines.lineWidth = 3
        ribLines.lineCap = .round
        ribs.addChild(ribLines)
        return ribs
    }

    func makeLeg(_ side: LegSide) -> SKNode { limbShape(width: 9, height: 28, fill: bone, line: 3) }
    func makeArm(_ role: ArmRole) -> SKNode { limbShape(width: 8, height: 26, fill: bone, line: 3) }

}


// MARK: - Goblin

/// A green goblin: pointed ears, yellow eyes, a crooked grin and a ragged vest.
struct GoblinSkin: Skin {
    var defaultWeapon: Weapon? { Weapons.rustyBlade }
    private let skin = SKColor(red: 0.38, green: 0.64, blue: 0.26, alpha: 1)
    private let skinDark = SKColor(red: 0.27, green: 0.48, blue: 0.19, alpha: 1)
    private let vest = SKColor(red: 0.45, green: 0.30, blue: 0.18, alpha: 1)
    var layout = RigLayout(restY: 28, legBackX: -7, legFrontX: 7,
                           weaponShoulder: CGPoint(x: -14, y: 44), offShoulder: CGPoint(x: 15, y: 44),
                           armLength: 26, shadowSize: CGSize(width: 56, height: 12))

    func makeHead() -> SKNode {
        let head = styled(SKShapeNode(circleOfRadius: 16), skin)
        for sx: CGFloat in [-1, 1] {                                              // big pointed ears
            let p = CGMutablePath()
            p.move(to: CGPoint(x: sx * 12, y: 4)); p.addLine(to: CGPoint(x: sx * 32, y: 14)); p.addLine(to: CGPoint(x: sx * 13, y: -5)); p.closeSubpath()
            let ear = styled(SKShapeNode(path: p), skin, line: 3)
            ear.zPosition = -1
            head.addChild(ear)
        }
        for x: CGFloat in [-5, 7] {
            let eye = styled(SKShapeNode(ellipseOf: CGSize(width: 8, height: 9)), SKColor(red: 1, green: 0.88, blue: 0.2, alpha: 1), line: 2)
            eye.position = CGPoint(x: x, y: 4)
            let pupil = styled(SKShapeNode(ellipseOf: CGSize(width: 3, height: 6)), ink, line: 0)
            pupil.position = CGPoint(x: 1, y: 0)
            eye.addChild(pupil)
            head.addChild(eye)
        }
        let grin = CGMutablePath()
        grin.move(to: CGPoint(x: -8, y: -6)); grin.addQuadCurve(to: CGPoint(x: 11, y: -5), control: CGPoint(x: 2, y: -15))
        let mouth = SKShapeNode(path: grin)
        mouth.strokeColor = ink; mouth.lineWidth = 3; mouth.lineCap = .round
        head.addChild(mouth)
        for x: CGFloat in [-3, 6] {                                               // fangs
            let f = CGMutablePath()
            f.move(to: CGPoint(x: x - 2, y: -8)); f.addLine(to: CGPoint(x: x, y: -13)); f.addLine(to: CGPoint(x: x + 2, y: -8)); f.closeSubpath()
            head.addChild(styled(SKShapeNode(path: f), .white, line: 1))
        }
        return head
    }

    func makeTorso() -> SKNode {
        let body = styled(SKShapeNode(rect: CGRect(x: -16, y: 0, width: 32, height: 46), cornerRadius: 10), skin, line: 3)
        let v = CGMutablePath()
        v.move(to: CGPoint(x: -16, y: 2)); v.addLine(to: CGPoint(x: -16, y: 30)); v.addLine(to: CGPoint(x: -2, y: 18)); v.addLine(to: CGPoint(x: 5, y: 32))
        v.addLine(to: CGPoint(x: 16, y: 28)); v.addLine(to: CGPoint(x: 16, y: 2)); v.closeSubpath()
        let rag = styled(SKShapeNode(path: v), vest, line: 3)
        body.addChild(rag)
        return body
    }

    func makeLeg(_ side: LegSide) -> SKNode { limbShape(width: 9, height: 28, fill: skinDark, line: 3) }
    func makeArm(_ role: ArmRole) -> SKNode { limbShape(width: 8, height: 26, fill: skin, line: 3) }
}

// MARK: - Necromancer

/// A hooded, robed skeleton with glowing eyes. The boss of Gravewood.
struct NecromancerSkin: Skin {
    var defaultWeapon: Weapon? { Weapons.staff }
    private let robe = SKColor(red: 0.26, green: 0.14, blue: 0.40, alpha: 1)
    private let robeDark = SKColor(red: 0.16, green: 0.08, blue: 0.27, alpha: 1)
    private let trim = SKColor(red: 0.78, green: 0.62, blue: 0.95, alpha: 1)
    private let bone = SKColor(white: 0.93, alpha: 1)
    var layout = RigLayout(restY: 28, legBackX: -7, legFrontX: 7,
                           weaponShoulder: CGPoint(x: -14, y: 44), offShoulder: CGPoint(x: 15, y: 44),
                           armLength: 26, shadowSize: CGSize(width: 64, height: 14))

    func makeHead() -> SKNode {
        let hood = styled(SKShapeNode(circleOfRadius: 19), robe)
        let tip = CGMutablePath()
        tip.move(to: CGPoint(x: -14, y: 12)); tip.addLine(to: CGPoint(x: -6, y: 36)); tip.addLine(to: CGPoint(x: 12, y: 14)); tip.closeSubpath()
        let point = styled(SKShapeNode(path: tip), robe)
        point.zPosition = -1
        hood.addChild(point)
        let face = styled(SKShapeNode(ellipseOf: CGSize(width: 26, height: 24)), bone, line: 3)
        face.position = CGPoint(x: 4, y: -1); face.zPosition = 1
        hood.addChild(face)
        for x: CGFloat in [-2, 10] {
            let eye = styled(SKShapeNode(ellipseOf: CGSize(width: 6, height: 8)), SKColor(red: 0.5, green: 1, blue: 0.6, alpha: 1), line: 0)
            eye.position = CGPoint(x: x, y: 2); eye.glowWidth = 4; eye.zPosition = 2
            face.addChild(eye)
        }
        return hood
    }

    func makeTorso() -> SKNode {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -17, y: 48)); p.addLine(to: CGPoint(x: 17, y: 48))
        p.addLine(to: CGPoint(x: 25, y: -20)); p.addLine(to: CGPoint(x: -25, y: -20)); p.closeSubpath()
        let body = styled(SKShapeNode(path: p), robe, line: 3)
        let hem = styled(SKShapeNode(rect: CGRect(x: -25, y: -20, width: 50, height: 7)), trim, line: 0)
        body.addChild(hem)
        let sash = styled(SKShapeNode(rect: CGRect(x: -19, y: 20, width: 38, height: 6)), robeDark, line: 0)
        body.addChild(sash)
        return body
    }

    func makeLeg(_ side: LegSide) -> SKNode { limbShape(width: 10, height: 28, fill: robeDark, line: 3) }
    func makeArm(_ role: ArmRole) -> SKNode { limbShape(width: 11, height: 26, fill: robe, line: 3) }
}


// MARK: - Bat

/// A small bat: fanged head, round body, and wings where the arms go (they flap when the rig is flying).
struct BatSkin: Skin {
    var defaultWeapon: Weapon? { nil }
    var royal = false                       // the Bat King: darker fur, crimson wings, a crown
    private var fur: SKColor { royal ? SKColor(red: 0.17, green: 0.11, blue: 0.21, alpha: 1) : SKColor(red: 0.30, green: 0.22, blue: 0.38, alpha: 1) }
    private var furLight: SKColor { royal ? SKColor(red: 0.30, green: 0.20, blue: 0.34, alpha: 1) : SKColor(red: 0.42, green: 0.32, blue: 0.50, alpha: 1) }
    private var membrane: SKColor { royal ? SKColor(red: 0.55, green: 0.12, blue: 0.22, alpha: 1) : SKColor(red: 0.46, green: 0.30, blue: 0.60, alpha: 1) }
    var layout = RigLayout(restY: 20, legBackX: -4, legFrontX: 4,
                           weaponShoulder: CGPoint(x: -6, y: 30), offShoulder: CGPoint(x: 7, y: 30),
                           headPivot: CGPoint(x: 3, y: 44),
                           armLength: 20, shadowSize: CGSize(width: 44, height: 10))

    func makeHead() -> SKNode {
        let head = styled(SKShapeNode(circleOfRadius: 13), fur)
        for x: CGFloat in [-8, 6] {                                              // ears
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x - 5, y: 8)); p.addLine(to: CGPoint(x: x + 1, y: 27)); p.addLine(to: CGPoint(x: x + 7, y: 8)); p.closeSubpath()
            let ear = styled(SKShapeNode(path: p), fur, line: 3)
            ear.zPosition = -1
            head.addChild(ear)
        }
        if royal {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -12, y: 9)); p.addLine(to: CGPoint(x: -12, y: 22)); p.addLine(to: CGPoint(x: -6, y: 15)); p.addLine(to: CGPoint(x: 0, y: 25))
            p.addLine(to: CGPoint(x: 6, y: 15)); p.addLine(to: CGPoint(x: 12, y: 22)); p.addLine(to: CGPoint(x: 12, y: 9)); p.closeSubpath()
            let crown = styled(SKShapeNode(path: p), SKColor(red: 1, green: 0.82, blue: 0.25, alpha: 1), line: 3)
            crown.position = CGPoint(x: 1, y: 6); crown.zPosition = 3
            head.addChild(crown)
        }
        for x: CGFloat in [-3, 7] {
            let eye = styled(SKShapeNode(ellipseOf: CGSize(width: 5, height: 6)), SKColor(red: 1, green: 0.2, blue: 0.2, alpha: 1), line: 0)
            eye.position = CGPoint(x: x, y: 3); eye.glowWidth = 2
            head.addChild(eye)
        }
        for x: CGFloat in [-1, 7] {                                              // fangs
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x - 2.5, y: -8)); p.addLine(to: CGPoint(x: x, y: -16)); p.addLine(to: CGPoint(x: x + 2.5, y: -8)); p.closeSubpath()
            head.addChild(styled(SKShapeNode(path: p), SKColor.white, line: 2))
        }
        return head
    }

    func makeTorso() -> SKNode {
        let n = SKNode()
        let body = styled(SKShapeNode(ellipseOf: CGSize(width: 28, height: 40)), fur, line: 3)
        body.position = CGPoint(x: 0, y: 18)
        let chest = styled(SKShapeNode(ellipseOf: CGSize(width: 14, height: 22)), furLight, line: 0)
        chest.position = CGPoint(x: 3, y: -2)
        body.addChild(chest)
        n.addChild(body)
        return n
    }

    func makeLeg(_ side: LegSide) -> SKNode { limbShape(width: 5, height: 14, fill: fur, line: 3) }

    func makeArm(_ role: ArmRole) -> SKNode {
        let p = CGMutablePath()
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: -15, y: -12)); p.addLine(to: CGPoint(x: -11, y: -20))
        p.addLine(to: CGPoint(x: -15, y: -34)); p.addLine(to: CGPoint(x: -6, y: -27))
        p.addLine(to: CGPoint(x: -2, y: -44)); p.addLine(to: CGPoint(x: 5, y: -26))
        p.addLine(to: CGPoint(x: 9, y: -10)); p.closeSubpath()
        return styled(SKShapeNode(path: p), membrane, line: 3)
    }
}


// MARK: - Shadow (Mirror Hall)

private func mixColor(_ c: SKColor, _ t: SKColor, _ k: CGFloat) -> SKColor {
    var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
    var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
    c.getRed(&r1, green: &g1, blue: &b1, alpha: &a1); t.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
    return SKColor(red: r1 + (r2 - r1) * k, green: g1 + (g2 - g1) * k, blue: b1 + (b2 - b1) * k, alpha: a1)
}

/// Any skin, drained to violet with a cold glassy outline: a reflection of whoever it wraps.
struct ShadowSkin: Skin {
    let base: Skin
    let strength: CGFloat
    var layout: RigLayout { base.layout }
    var defaultWeapon: Weapon? { base.defaultWeapon }

    private func shade(_ n: SKNode) -> SKNode {
        if let s = n as? SKShapeNode {
            if s.fillColor.cgColor.alpha > 0.01 { s.fillColor = mixColor(s.fillColor, SKColor(red: 0.22, green: 0.10, blue: 0.40, alpha: 1), strength) }
            if s.lineWidth > 0 { s.strokeColor = mixColor(s.strokeColor, SKColor(red: 0.45, green: 0.85, blue: 1, alpha: 1), 0.45) }
        }
        n.children.forEach { _ = shade($0) }
        return n
    }

    func makeHead() -> SKNode { shade(base.makeHead()) }
    func makeTorso() -> SKNode { shade(base.makeTorso()) }
    func makeLeg(_ side: LegSide) -> SKNode { shade(base.makeLeg(side)) }
    func makeArm(_ role: ArmRole) -> SKNode { shade(base.makeArm(role)) }
}


// MARK: - Forge King

/// A huge, sooty goblin: iron crown, ember eyes, a scorched apron over a glowing furnace-plate chest.
struct ForgeKingSkin: Skin {
    private let base = GoblinSkin()
    var layout: RigLayout { base.layout }
    var defaultWeapon: Weapon? { Weapons.hammer }

    func makeHead() -> SKNode {
        let head = base.makeHead()
        let crown = CGMutablePath()
        crown.move(to: CGPoint(x: -14, y: 12)); crown.addLine(to: CGPoint(x: -14, y: 28)); crown.addLine(to: CGPoint(x: -7, y: 20)); crown.addLine(to: CGPoint(x: 0, y: 32))
        crown.addLine(to: CGPoint(x: 7, y: 20)); crown.addLine(to: CGPoint(x: 14, y: 28)); crown.addLine(to: CGPoint(x: 14, y: 12)); crown.closeSubpath()
        let c = styled(SKShapeNode(path: crown), SKColor(red: 0.33, green: 0.31, blue: 0.36, alpha: 1), line: 3)
        c.position = CGPoint(x: 1, y: 6); c.zPosition = 3
        let gem = styled(SKShapeNode(circleOfRadius: 3.5), SKColor(red: 1, green: 0.5, blue: 0.12, alpha: 1), line: 1)
        gem.position = CGPoint(x: 0, y: 15); gem.glowWidth = 4
        c.addChild(gem)
        head.addChild(c)
        return head
    }

    func makeTorso() -> SKNode {
        let body = base.makeTorso()
        let plate = styled(SKShapeNode(rect: CGRect(x: -11, y: 12, width: 22, height: 22), cornerRadius: 5), SKColor(red: 1, green: 0.45, blue: 0.1, alpha: 1), line: 3)
        plate.glowWidth = 5; plate.zPosition = 2
        let apron = styled(SKShapeNode(rect: CGRect(x: -15, y: -10, width: 30, height: 20), cornerRadius: 3), SKColor(red: 0.22, green: 0.16, blue: 0.14, alpha: 1), line: 3)
        apron.zPosition = 2
        body.addChild(plate); body.addChild(apron)
        return body
    }

    func makeLeg(_ side: LegSide) -> SKNode { base.makeLeg(side) }
    func makeArm(_ role: ArmRole) -> SKNode { base.makeArm(role) }
}


// MARK: - Lantern Wraith

/// The Necromancer's robes, drained to pale cyan: a hooded ghost.
struct WraithSkin: Skin {
    private let base = NecromancerSkin()
    var layout: RigLayout { base.layout }
    var defaultWeapon: Weapon? { Weapons.staff }

    private func ghost(_ n: SKNode) -> SKNode {
        if let s = n as? SKShapeNode {
            if s.fillColor.cgColor.alpha > 0.01 { s.fillColor = mixColor(s.fillColor, SKColor(red: 0.55, green: 0.80, blue: 0.92, alpha: 1), 0.6) }
            if s.lineWidth > 0 { s.strokeColor = mixColor(s.strokeColor, SKColor(red: 0.85, green: 0.97, blue: 1, alpha: 1), 0.6) }
        }
        n.children.forEach { _ = ghost($0) }
        return n
    }
    func makeHead() -> SKNode { ghost(base.makeHead()) }
    func makeTorso() -> SKNode { ghost(base.makeTorso()) }
    func makeLeg(_ side: LegSide) -> SKNode { ghost(base.makeLeg(side)) }
    func makeArm(_ role: ArmRole) -> SKNode { ghost(base.makeArm(role)) }
}


// MARK: - Template (custom proportions)

/// Proportions measured from the artist's template (2048x1536 canvas, 0.128 pt per pixel): a gigantic head sitting straight on a
/// medium egg-shaped body (no neck), arms that hang almost to the ground, and legs that are mostly just feet.
/// Code-drawn stand-in for the real art: the joint positions below are the ones the drawn parts will hang from.
struct TemplateSkin: Skin {
    var defaultWeapon: Weapon? { Weapons.sword }
    private let hood = SKColor(red: 0.80, green: 0.62, blue: 0.30, alpha: 1)
    private let cloth = SKColor(red: 0.67, green: 0.49, blue: 0.24, alpha: 1)
    private let boot = SKColor(red: 0.17, green: 0.23, blue: 0.18, alpha: 1)
    private let line: CGFloat = 2.5

    // Origin: between the feet, on the ground. Template pixels -> points: x = (px - 940) * 0.128, y = (1275 - py) * 0.128.
    var layout = RigLayout(restY: 30, legBackX: -10, legFrontX: 11.5,
                           weaponShoulder: CGPoint(x: -19, y: 17), offShoulder: CGPoint(x: 14, y: 16),
                           headPivot: CGPoint(x: 3, y: 43),
                           armLength: 35, shadowSize: CGSize(width: 63, height: 11))

    /// Which hand-drawn parts to use (Brawler/Sprites/<prefix>_<part>.png); `-spriteprefix name` overrides it for testing.
    private var prefix: String {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-spriteprefix"), i + 1 < a.count { return a[i + 1] }
        return "cloak"
    }

    func makeHead() -> SKNode {
        if let art = SpriteParts.node(prefix, .head) { return art }
        let head = styled(SKShapeNode(circleOfRadius: 41.5), hood, line: line)         // 649 px across
        let face = styled(SKShapeNode(ellipseOf: CGSize(width: 44, height: 50)), SKColor(red: 0.06, green: 0.08, blue: 0.05, alpha: 1), line: line)
        face.position = CGPoint(x: 9, y: -6)
        for (x, y, w, h, r) in [(-6, 2, 13, 17, 0.35), (12, 1, 11, 12, -0.5)] as [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] {
            let eye = styled(SKShapeNode(ellipseOf: CGSize(width: w, height: h)), SKColor(red: 0.95, green: 0.88, blue: 0.2, alpha: 1), line: 1.5)
            eye.position = CGPoint(x: x, y: y); eye.zRotation = r; eye.glowWidth = 2
            face.addChild(eye)
        }
        head.addChild(face)
        return head
    }

    func makeTorso() -> SKNode {
        if let art = SpriteParts.node(prefix, .torso) { return art }
        let n = SKNode()
        let body = styled(SKShapeNode(ellipseOf: CGSize(width: 45, height: 50)), cloth, line: line)
        body.position = CGPoint(x: 0, y: 2)
        n.addChild(body)
        let belt = styled(SKShapeNode(rect: CGRect(x: -20, y: -14, width: 40, height: 9), cornerRadius: 3), hood, line: 1.5)
        belt.zPosition = 1
        n.addChild(belt)
        return n
    }

    /// Mostly just a foot: the joint is the hip, 30 pt above the ground, and the foot hangs at the bottom of it.
    func makeLeg(_ side: LegSide) -> SKNode {
        if let art = SpriteParts.node(prefix, side == .back ? .legBack : .legFront) { return art }
        let n = SKNode()
        n.addChild(styled(SKShapeNode(rect: CGRect(x: -10, y: -30, width: 20, height: 12), cornerRadius: 6), boot, line: line))
        return n
    }

    /// Long: hangs from the shoulder almost to the ground.
    /// The off-hand arm is further back, so it is drawn 12% smaller.
    func makeArm(_ role: ArmRole) -> SKNode {
        let k: CGFloat = role == .weapon ? 1 : 0.88
        if let art = SpriteParts.node(prefix, role == .weapon ? .armWeapon : .armOff) { art.setScale(k); return art }
        return limbShape(width: 21 * k, height: 43 * k, fill: role == .weapon ? hood : cloth, line: line)
    }
}

// MARK: - SpriteSkin (generic drawn humanoid)

/// Any humanoid built from hand-drawn parts (Brawler/Sprites/<prefix>_<part>.png, cut from the shared template).
/// A part with no art falls back to `base`'s code-drawn shape, so characters can be drawn one part at a time and mixed freely.
/// With no art at all it is exactly `base`; with any art it uses the shared template joints.
struct SpriteSkin: Skin {
    let prefix: String
    let base: Skin
    private let drawn: Bool
    private let template = TemplateSkin()

    /// `base` if nothing has been drawn for `prefix`, else a SpriteSkin. This is what spawn code should call.
    static func wrap(_ prefix: String, _ base: Skin) -> Skin {
        SpriteParts.has(prefix).isEmpty ? base : SpriteSkin(prefix: prefix, base: base)
    }

    init(prefix: String, base: Skin) {
        self.prefix = prefix; self.base = base
        drawn = !SpriteParts.has(prefix).isEmpty
    }

    var layout: RigLayout { drawn ? template.layout : base.layout }
    var defaultWeapon: Weapon? { base.defaultWeapon }

    func makeWing(front: Bool) -> SKNode? { SpriteParts.node(prefix, front ? .wingFront : .wingBack) ?? base.makeWing(front: front) }
    func makeHead() -> SKNode { SpriteParts.node(prefix, .head) ?? base.makeHead() }
    func makeTorso() -> SKNode { SpriteParts.node(prefix, .torso) ?? base.makeTorso() }
    func makeLeg(_ side: LegSide) -> SKNode { SpriteParts.node(prefix, side == .back ? .legBack : .legFront) ?? base.makeLeg(side) }
    func makeArm(_ role: ArmRole) -> SKNode {
        guard let art = SpriteParts.node(prefix, role == .weapon ? .armWeapon : .armOff) else { return base.makeArm(role) }
        if role == .off { art.setScale(0.88) }          // the off-hand arm is further back
        return art
    }
}


// MARK: - Frost wizard

/// An icy robe and a tall pointed hat. The Archmage wears deep blue and gold.
struct WizardSkin: Skin {
    var archmage = false
    var defaultWeapon: Weapon? { Weapons.iceStaff }
    private var robe: SKColor { archmage ? SKColor(red: 0.16, green: 0.26, blue: 0.58, alpha: 1) : SKColor(red: 0.34, green: 0.58, blue: 0.84, alpha: 1) }
    private var robeDark: SKColor { archmage ? SKColor(red: 0.09, green: 0.15, blue: 0.40, alpha: 1) : SKColor(red: 0.22, green: 0.42, blue: 0.68, alpha: 1) }
    private var trim: SKColor { archmage ? SKColor(red: 0.96, green: 0.80, blue: 0.32, alpha: 1) : SKColor(red: 0.93, green: 0.98, blue: 1, alpha: 1) }
    private let skinTone = SKColor(red: 0.90, green: 0.95, blue: 1, alpha: 1)
    var layout = RigLayout(restY: 28, legBackX: -7, legFrontX: 7,
                           weaponShoulder: CGPoint(x: -14, y: 44), offShoulder: CGPoint(x: 15, y: 44),
                           armLength: 26, shadowSize: CGSize(width: 64, height: 14))

    func makeHead() -> SKNode {
        let hood = styled(SKShapeNode(circleOfRadius: 18), robe)
        let hat = CGMutablePath()
        hat.move(to: CGPoint(x: -20, y: 10)); hat.addLine(to: CGPoint(x: 8, y: 60)); hat.addLine(to: CGPoint(x: 21, y: 10)); hat.closeSubpath()
        let cone = styled(SKShapeNode(path: hat), robeDark, line: 3)
        cone.zPosition = 2
        hood.addChild(cone)
        let band = styled(SKShapeNode(rect: CGRect(x: -21, y: 8, width: 43, height: 7), cornerRadius: 2), trim, line: 2)
        band.zPosition = 3
        hood.addChild(band)
        let face = styled(SKShapeNode(ellipseOf: CGSize(width: 24, height: 22)), skinTone, line: 3)
        face.position = CGPoint(x: 4, y: -3); face.zPosition = 1
        hood.addChild(face)
        for x: CGFloat in [-2, 10] {
            let eye = styled(SKShapeNode(ellipseOf: CGSize(width: 5, height: 7)), SKColor(red: 0.3, green: 0.9, blue: 1, alpha: 1), line: 0)
            eye.position = CGPoint(x: x, y: 2); eye.glowWidth = 4; eye.zPosition = 2
            face.addChild(eye)
        }
        let beard = CGMutablePath()
        beard.move(to: CGPoint(x: -7, y: -8)); beard.addLine(to: CGPoint(x: 5, y: -30)); beard.addLine(to: CGPoint(x: 16, y: -8)); beard.closeSubpath()
        let b = styled(SKShapeNode(path: beard), SKColor(white: 0.97, alpha: 1), line: 3)
        b.zPosition = 2
        face.addChild(b)
        return hood
    }

    func makeTorso() -> SKNode {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: -17, y: 48)); p.addLine(to: CGPoint(x: 17, y: 48))
        p.addLine(to: CGPoint(x: 25, y: -20)); p.addLine(to: CGPoint(x: -25, y: -20)); p.closeSubpath()
        let body = styled(SKShapeNode(path: p), robe, line: 3)
        body.addChild(styled(SKShapeNode(rect: CGRect(x: -25, y: -20, width: 50, height: 7)), trim, line: 0))
        body.addChild(styled(SKShapeNode(rect: CGRect(x: -19, y: 20, width: 38, height: 6)), robeDark, line: 0))
        return body
    }

    func makeLeg(_ side: LegSide) -> SKNode { limbShape(width: 10, height: 28, fill: robeDark, line: 3) }
    func makeArm(_ role: ArmRole) -> SKNode { limbShape(width: 11, height: 26, fill: robe, line: 3) }
}
