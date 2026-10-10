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
