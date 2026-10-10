import SpriteKit

enum Combat {
    static let bodyHalfWidth: CGFloat = 24     // how far a target's body reaches into a hit region

    struct Contact { let point: CGPoint; let damage: CGFloat }

    /// Applies every active hit that overlaps an opposing fighter this frame.
    /// A move hits each target at most once per hit window. Lower array index wins a same-frame trade.
    static func resolve(_ fighters: [Fighter]) -> [Contact] {
        var contacts: [Contact] = []
        for a in fighters where !a.dead {
            for (index, hit, power) in a.activeHits {
                for t in fighters where t.team != a.team && t.hittable {
                    guard !a.isHurt, overlaps(hit, from: a, to: t), a.claim(index, t) else { continue }
                    let dmg = hit.damage * power * a.damageMultiplier
                    let move = a.currentMoveName
                    t.receive(hit, power: power, scale: a.damageMultiplier, from: a)
                    let stop = min(0.12, 0.03 + Double(dmg) * 0.004)      // hit-stop: heavier hits freeze longer
                    a.hitStop(stop); t.hitStop(stop)
                    let toward: CGFloat = a.rig.position.x < t.rig.position.x ? -1 : 1
                    contacts.append(Contact(point: CGPoint(x: t.rig.position.x + toward * 10,
                                                           y: t.rig.position.y + t.rig.height + 60), damage: dmg))
                    NSLog("HIT %@ -> %@ [%@] dmg %.1f hp %.1f%@", a.name, t.name, move, dmg, t.health,
                          t.dead ? " KO" : (t.launched ? " LAUNCH" : ""))
                }
            }
        }
        return contacts
    }

    static func overlaps(_ hit: Hit, from a: Fighter, to t: Fighter) -> Bool {
        let f: CGFloat = a.rig.facingRight ? 1 : -1
        let dx = (t.rig.position.x - a.rig.position.x) * f
        return dx >= hit.reach.lowerBound - bodyHalfWidth && dx <= hit.reach.upperBound + bodyHalfWidth
            && abs(t.rig.position.y - a.rig.position.y) <= hit.depth
            && abs(t.rig.height - a.rig.height) <= hit.heightTolerance
    }
}

/// Floating bar over enemies (hidden at full health) and the hero's HUD bar.
final class HealthBar: SKNode {
    let width: CGFloat
    private let fill: SKShapeNode

    init(width: CGFloat, height: CGFloat = 10) {
        self.width = width
        let back = SKShapeNode(rect: CGRect(x: -width / 2, y: 0, width: width, height: height), cornerRadius: 3)
        back.fillColor = SKColor(white: 0.1, alpha: 0.85); back.strokeColor = ink; back.lineWidth = 3
        fill = SKShapeNode(rect: CGRect(x: 0, y: 0, width: width, height: height), cornerRadius: 3)
        fill.position.x = -width / 2; fill.strokeColor = .clear; fill.zPosition = 1
        super.init()
        addChild(back); addChild(fill)
        set(1)
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(_ f: CGFloat) {
        fill.xScale = max(0.001, min(1, f))
        fill.fillColor = f > 0.5 ? SKColor(red: 0.35, green: 0.8, blue: 0.4, alpha: 1)
            : f > 0.25 ? SKColor(red: 0.95, green: 0.8, blue: 0.25, alpha: 1)
            : SKColor(red: 0.9, green: 0.25, blue: 0.25, alpha: 1)
    }
}
