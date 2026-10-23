import SpriteKit

enum Combat {
    static let bodyHalfWidth: CGFloat = 24     // how far a target's body reaches into a hit region

    struct Contact { let point: CGPoint; let damage: CGFloat; var attacker: Fighter? = nil; var move: Move? = nil; var ko = false; var crit = false }

    /// Chance that one of the hero's hits is a lucky hit: 1.25x damage, a longer hit-stop, a bigger flash and a callout.
    static var critChance = 0.12
    static let critDamage: CGFloat = 1.25

    /// Applies every active hit that overlaps an opposing fighter this frame.
    /// A move hits each target at most once per hit window. Lower array index wins a same-frame trade.
    static func resolve(_ fighters: [Fighter]) -> [Contact] {
        var contacts: [Contact] = []
        for a in fighters where !a.dead {
            for (index, hit, power) in a.activeHits {
                for t in fighters where t.team != a.team && t.vulnerable {
                    guard !a.isHurt, overlaps(hit, from: a, to: t), a.claim(index, t) else { continue }
                    let crit = a.collectsItems && hit.damage > 0 && Double.random(in: 0...1) < critChance
                    let dmg = hit.damage * power * a.damageMultiplier * (crit ? critDamage : 1)
                    let move = a.currentMoveName
                    let moveUsed = a.currentMove
                    t.receive(hit, power: power, scale: a.damageMultiplier * (crit ? critDamage : 1), from: a)
                    let base = hit.launch > 0 ? 0 : min(0.12, 0.03 + Double(dmg) * 0.004); let stop = crit && hit.launch == 0 ? base * 1.8 + 0.05 : base   // hit-stop: heavier hits freeze longer; launchers never freeze, the victim flies at once
                    a.hitStop(stop); t.hitStop(stop)
                    let toward: CGFloat = a.rig.position.x < t.rig.position.x ? -1 : 1
                    contacts.append(Contact(point: CGPoint(x: t.rig.position.x + toward * 10,
                                                           y: t.rig.position.y + t.rig.height + 60), damage: dmg,
                                            attacker: a, move: moveUsed, ko: t.dead, crit: crit))
                    NSLog("HIT %@ -> %@ [%@] dmg %.1f hp %.1f%@", a.name, t.name, move, dmg, t.health,
                          t.dead ? " KO" : (t.launched ? " LAUNCH" : ""))
                }
            }
        }
        return contacts
    }

    /// Arrows hit the first opposing fighter whose body they reach (same lane band, within height tolerance).
    static func resolveProjectiles(_ field: ProjectileField, _ fighters: [Fighter]) -> [Contact] {
        var contacts: [Contact] = []
        for a in field.arrows where !a.spent && a.shot.kind != .bomb {
            for t in fighters where t.team != a.owner.team && t.vulnerable {
                guard abs(a.position.x - t.rig.position.x) <= bodyHalfWidth * t.stats.size + 8,
                      abs(a.lane - t.rig.position.y) <= a.hit.depth,
                      abs(a.height - t.rig.height) <= a.hit.heightTolerance else { continue }
                let crit = a.owner.collectsItems && Double.random(in: 0...1) < critChance
                let scale = a.owner.stats.damageScale * (crit ? critDamage : 1)
                let dmg = a.hit.damage * scale
                t.receive(a.hit, power: 1, scale: scale, from: a.owner, away: a.dir)
                t.hitStop(0.04)
                contacts.append(Contact(point: CGPoint(x: t.rig.position.x - a.dir * 10, y: t.rig.position.y + t.rig.height + 62), damage: dmg,
                                            attacker: a.owner, move: nil, ko: t.dead, crit: crit))
                NSLog("HIT %@ -> %@ [arrow] dmg %.1f hp %.1f%@ at x%.0f y%.0f", a.owner.name, t.name, dmg, t.health, t.dead ? " KO" : "", t.rig.position.x, t.rig.position.y)
                field.remove(a, hit: true)
                break
            }
        }
        return contacts
    }

    static func overlaps(_ hit: Hit, from a: Fighter, to t: Fighter) -> Bool {
        let f: CGFloat = a.rig.facingRight ? 1 : -1
        let dx = (t.rig.position.x - a.rig.position.x) * f
        let body = bodyHalfWidth * t.stats.size, s = a.stats.size
        return dx >= hit.reach.lowerBound * s - body && dx <= hit.reach.upperBound * s + body
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


/// Debug view of hit regions. Draws each live `Hit` as the exact ground footprint `Combat.overlaps` tests
/// (reach widened by the target's body half-width, lane +/- depth), then fades it so 0.1s windows stay readable.
/// Toggle with H or launch with `-hitboxes`.
final class HitOverlay: SKNode {
    private struct Key: Hashable { let fighter: ObjectIdentifier; let index: Int }
    private var shapes: [Key: SKShapeNode] = [:]
    private let fadeRate: CGFloat = 3.5          // alpha per second after a window closes

    var enabled = false {
        didSet {
            isHidden = !enabled
            if !enabled { removeAllChildren(); shapes.removeAll() }
        }
    }

    override init() {
        super.init()
        zPosition = 8000
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(_ fighters: [Fighter], heroTeam: Int, dt: CGFloat) {
        guard enabled else { return }
        var live = Set<Key>()
        for f in fighters {
            let dir: CGFloat = f.rig.facingRight ? 1 : -1
            for (index, hit, _) in f.activeHits {
                let key = Key(fighter: ObjectIdentifier(f), index: index)
                live.insert(key)
                let a = f.rig.position.x + dir * (hit.reach.lowerBound * f.stats.size - Combat.bodyHalfWidth)
                let b = f.rig.position.x + dir * (hit.reach.upperBound * f.stats.size + Combat.bodyHalfWidth)
                let rect = CGRect(x: min(a, b), y: f.rig.position.y - hit.depth, width: abs(b - a), height: hit.depth * 2)
                let shape = shapes[key] ?? makeShape(for: key)
                shape.path = CGPath(rect: rect, transform: nil)
                let color: SKColor = f.team == heroTeam ? .cyan : .red
                shape.fillColor = color.withAlphaComponent(0.25)
                shape.strokeColor = color
                shape.alpha = 1
            }
        }
        for (key, shape) in shapes where !live.contains(key) {
            shape.alpha -= fadeRate * dt
            if shape.alpha <= 0 { shape.removeFromParent(); shapes[key] = nil }
        }
    }

    private func makeShape(for key: Key) -> SKShapeNode {
        let s = SKShapeNode()
        s.lineWidth = 2
        addChild(s)
        shapes[key] = s
        return s
    }
}


/// Slim special-move meter under the health bar. Pulses gold when full.
final class MeterBar: SKNode {
    private let fill: SKShapeNode
    private var wasFull = false

    init(width: CGFloat, height: CGFloat = 8) {
        let back = SKShapeNode(rect: CGRect(x: -width / 2, y: 0, width: width, height: height), cornerRadius: 3)
        back.fillColor = SKColor(white: 0.1, alpha: 0.85); back.strokeColor = ink; back.lineWidth = 3
        fill = SKShapeNode(rect: CGRect(x: 0, y: 0, width: width, height: height), cornerRadius: 3)
        fill.position.x = -width / 2; fill.strokeColor = .clear; fill.zPosition = 1
        super.init()
        addChild(back); addChild(fill)
        set(0)
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(_ f: CGFloat) {
        fill.xScale = max(0.001, min(1, f))
        let full = f >= 1
        fill.fillColor = full ? SKColor(red: 1, green: 0.82, blue: 0.2, alpha: 1) : SKColor(red: 0.3, green: 0.6, blue: 1, alpha: 1)
        guard full != wasFull else { return }
        wasFull = full
        removeAction(forKey: "pulse"); alpha = 1
        if full { run(.repeatForever(.sequence([.fadeAlpha(to: 0.5, duration: 0.25), .fadeAlpha(to: 1, duration: 0.25)])), withKey: "pulse") }
    }
}


// MARK: - Bone Wyrm

extension Hit {
    static let batSwoop   = Hit(start: 0, duration: 0, reach: 0...0, damage: 12, knockback: 520, launch: 420, stun: 0.8)
    static let batShock   = Hit(start: 0, duration: 0, reach: 0...0, damage: 13, knockback: 480, launch: 380, stun: 0.7)
    static let batBite    = Hit(start: 0.1, duration: 0.14, reach: 0...85, depth: 34, heightTolerance: 70, damage: 7, knockback: 220, stun: 0.3)
    static let necroBolt  = Hit(start: 0, duration: 0, reach: 0...0, depth: 30, heightTolerance: 70, damage: 11, knockback: 320, stun: 0.45)
    /// The frost wizards' bolt: lighter than the necromancer's, but it chills (half speed for a moment).
    static let fireBolt   = Hit(start: 0, duration: 0, reach: 0...0, depth: 30, heightTolerance: 70, damage: 10, knockback: 200, stun: 0.35)
    static let iceBolt    = Hit(start: 0, duration: 0, reach: 0...0, depth: 30, heightTolerance: 70, damage: 8, knockback: 200, stun: 0.35, chills: 1.7)
    static let eruption   = Hit(start: 0, duration: 0, reach: 0...0, damage: 16, knockback: 520, launch: 420, stun: 0.8)
    static let crumble    = Hit(start: 0, duration: 0, reach: 0...0, damage: 9999, knockback: 0, stun: 0.3)
    static let wyrmBite   = Hit(start: 0, duration: 0, reach: 0...0, damage: 10, knockback: 380, stun: 0.45)
    static let wyrmCharge = Hit(start: 0, duration: 0, reach: 0...0, damage: 22, knockback: 650, launch: 480, stun: 0.9)
}

/// Boss: a huge skeletal serpent that lives in the lanes. It weaves, rears up (a red lane marks where it will charge),
/// charges across the screen, then crashes into the edge and lies stunned. Dodge or jump the charge, then punish the head.
/// Head hits during the stun hurt most; the body takes little. At half health it enrages: faster, and it calls skeletons.
final class BoneWyrm: SKNode {
    enum State { case entering, prowl, telegraph, charge, stunned, recover, dying, gone }
    private(set) var state = State.entering

    let maxHealth: CGFloat = 520
    private(set) var health: CGFloat = 520
    var healthFraction: CGFloat { max(0, health / maxHealth) }
    var isFinished: Bool { state == .gone }
    var isDefeated: Bool { state == .dying || state == .gone }

    /// Impact strength (1 = a crash, 2 = death) so the scene can shake and zoom.
    var onSlam: ((CGFloat) -> Void)?
    var onEnrage: (() -> Void)?
    var onDefeated: (() -> Void)?

    private let count = 17                      // index 0 is the head
    private let spacing: CGFloat = 40
    private var pos: [CGPoint]                  // x and lane of every segment
    private var hgt: [CGFloat]                  // height of every segment's underside
    private var nodes: [SKNode] = []
    private var bodies: [SKShapeNode] = []
    private var shadows: [SKShapeNode] = []
    private let jaw = SKNode()
    private let stars = SKNode()
    private let warn = SKShapeNode()

    private var now: TimeInterval = 0
    private var stateStart: TimeInterval = 0
    private var started = false
    private var dir: CGFloat
    private var headTarget: CGFloat = 16
    private var locked = false
    private var chargeDir: CGFloat = 1
    private var chargeLane: CGFloat = 100
    private var chargeEnd: CGFloat = 0
    private var chargeHit = false
    private var biteReadyAt: TimeInterval = 0
    private var enraged = false
    private var bursts = 0
    private var bone = SKColor(red: 0.93, green: 0.9, blue: 0.8, alpha: 1)

    /// `dir` is the way it is travelling as it enters the arena (-1 = coming in from the right).
    init(x: CGFloat, lane: CGFloat, dir: CGFloat) {
        pos = Array(repeating: CGPoint(x: x, y: lane), count: count)
        hgt = Array(repeating: 0, count: count)
        self.dir = dir
        super.init()
        warn.fillColor = SKColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.22)
        warn.strokeColor = SKColor(red: 1, green: 0.25, blue: 0.2, alpha: 0.9); warn.lineWidth = 4
        warn.zPosition = 40; warn.isHidden = true
        warn.run(.repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 0.12), .fadeAlpha(to: 1, duration: 0.12)])))
        addChild(warn)
        for i in 0..<count {
            let shadow = SKShapeNode(ellipseOf: CGSize(width: radius(i) * 2.2, height: 14))
            shadow.fillColor = SKColor(white: 0, alpha: 0.3); shadow.strokeColor = .clear
            addChild(shadow); shadows.append(shadow)
            let (node, body) = i == 0 ? makeHead() : makeSegment(i)
            addChild(node); nodes.append(node); bodies.append(body)
        }
        stars.position = CGPoint(x: 0, y: 78); stars.isHidden = true
        for k in 0..<3 {
            let a = CGFloat(k) * 2 * .pi / 3
            let s = styled(SKShapeNode(rect: CGRect(x: -6, y: -6, width: 12, height: 12)), SKColor(red: 1, green: 0.9, blue: 0.3, alpha: 1), line: 3)
            s.position = CGPoint(x: cos(a) * 34, y: sin(a) * 12); s.zRotation = .pi / 4
            stars.addChild(s)
        }
        stars.run(.repeatForever(.rotate(byAngle: .pi * 2, duration: 1.4)))
        nodes[0].addChild(stars)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func radius(_ i: Int) -> CGFloat { i == 0 ? 42 : 32 * (1 - 0.55 * CGFloat(i) / CGFloat(count)) }

    // MARK: Drawing

    private func makeHead() -> (SKNode, SKShapeNode) {
        let head = SKNode()
        let dark = SKColor(red: 0.3, green: 0.25, blue: 0.22, alpha: 1)
        let lower = jaw; lower.position = CGPoint(x: -4, y: -20); lower.zPosition = -1       // the jaw node itself, so step() can swing it open
        lower.addChild(styled(SKShapeNode(rect: CGRect(x: 0, y: -18, width: 78, height: 18), cornerRadius: 8), bone, line: 5))
        for k in 0..<5 { lower.addChild(tooth(x: 14 + CGFloat(k) * 12, y: 0, up: true)) }
        head.addChild(lower)
        let skull = styled(SKShapeNode(ellipseOf: CGSize(width: 104, height: 78)), bone, line: 5)
        head.addChild(skull)
        let snout = styled(SKShapeNode(rect: CGRect(x: 14, y: -16, width: 62, height: 34), cornerRadius: 13), bone, line: 5)
        snout.zPosition = 1
        head.addChild(snout)
        for k in 0..<5 { let t = tooth(x: 26 + CGFloat(k) * 11, y: -15, up: false); t.zPosition = 2; head.addChild(t) }
        for (x, h) in [(CGFloat(-26), CGFloat(52)), (CGFloat(-6), CGFloat(40))] {                 // crest horns
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x - 12, y: 24)); p.addLine(to: CGPoint(x: x - 24, y: 24 + h)); p.addLine(to: CGPoint(x: x + 8, y: 30)); p.closeSubpath()
            head.addChild(styled(SKShapeNode(path: p), dark, line: 4))
        }
        let socket = styled(SKShapeNode(ellipseOf: CGSize(width: 26, height: 30)), ink, line: 0)
        socket.position = CGPoint(x: 6, y: 12); socket.zPosition = 3
        let eye = styled(SKShapeNode(ellipseOf: CGSize(width: 11, height: 13)), SKColor(red: 1, green: 0.15, blue: 0.1, alpha: 1), line: 0)
        eye.position = CGPoint(x: 8, y: 12); eye.zPosition = 4; eye.glowWidth = 6
        eye.run(.repeatForever(.sequence([.fadeAlpha(to: 0.55, duration: 0.5), .fadeAlpha(to: 1, duration: 0.5)])))
        head.addChild(socket); head.addChild(eye)
        for x in [CGFloat(52), CGFloat(62)] {                                                    // nostrils
            let n = styled(SKShapeNode(ellipseOf: CGSize(width: 5, height: 7)), ink, line: 0)
            n.position = CGPoint(x: x, y: 8); n.zPosition = 3; head.addChild(n)
        }
        return (head, skull)
    }
    private func tooth(x: CGFloat, y: CGFloat, up: Bool) -> SKShapeNode {
        let p = CGMutablePath(); let s: CGFloat = up ? 1 : -1
        p.move(to: CGPoint(x: x - 4, y: y)); p.addLine(to: CGPoint(x: x, y: y + s * 10)); p.addLine(to: CGPoint(x: x + 4, y: y)); p.closeSubpath()
        return styled(SKShapeNode(path: p), SKColor(white: 0.97, alpha: 1), line: 2)
    }

    private func makeSegment(_ i: Int) -> (SKNode, SKShapeNode) {
        let r = radius(i), n = SKNode()
        let body = styled(SKShapeNode(ellipseOf: CGSize(width: r * 2.1, height: r * 1.6)), bone, line: 5)
        body.position = CGPoint(x: 0, y: r * 0.8)
        n.addChild(body)
        for dx in [-r * 0.35, r * 0.35] {                                                         // ribs
            let p = CGMutablePath()
            p.move(to: CGPoint(x: dx, y: r * 1.4)); p.addQuadCurve(to: CGPoint(x: dx, y: r * 0.2), control: CGPoint(x: dx + r * 0.45, y: r * 0.8))
            let rib = SKShapeNode(path: p); rib.strokeColor = SKColor(red: 0.3, green: 0.25, blue: 0.22, alpha: 0.75); rib.lineWidth = 3
            n.addChild(rib)
        }
        let p = CGMutablePath()                                                                   // spine spike
        p.move(to: CGPoint(x: -r * 0.28, y: r * 1.55)); p.addLine(to: CGPoint(x: 0, y: r * 1.55 + r * 0.55)); p.addLine(to: CGPoint(x: r * 0.28, y: r * 1.55)); p.closeSubpath()
        let spike = styled(SKShapeNode(path: p), bone, line: 4); spike.zPosition = -1
        n.addChild(spike)
        return (n, body)
    }

    // MARK: Per frame

    func step(now: TimeInterval, dt: CGFloat, hero: Fighter, center: CGFloat, half: CGFloat) {
        guard state != .gone else { return }
        if !started { started = true; stateStart = now }
        self.now = now
        let t = CGFloat(now - stateStart)
        let edgeL = center - half + 150, edgeR = center + half - 150
        var undulate: CGFloat = 8, jawOpen: CGFloat = 0, shake: CGFloat = 0
        let hx = hero.rig.position.x, hy = hero.rig.position.y
        if state != .charge, state != .dying, state != .entering { dir = hx >= pos[0].x ? 1 : -1 }

        switch state {
        case .entering:
            pos[0].x += dir * 560 * dt
            pos[0].y += (110 - pos[0].y) * min(1, dt * 2)
            headTarget = 16
            if abs(pos[0].x - center) < half * 0.4 || t > 3 { go(.prowl) }

        case .prowl:
            let side: CGFloat = pos[0].x >= hx ? 1 : -1
            let tx = min(max(hx + side * 400, edgeL), edgeR)
            pos[0].x += max(-240, min(240, (tx - pos[0].x) * 2)) * dt
            pos[0].y += max(-110, min(110, (hy - pos[0].y) * 2)) * dt + sin(CGFloat(now) * 2.4) * 30 * dt
            headTarget = 16
            jawOpen = 0.12
            if !enraged, healthFraction < 0.5 { enrage() }
            if t > (enraged ? 1.5 : 2.4) { go(.telegraph) }

        case .telegraph:
            let tele: CGFloat = enraged ? 0.7 : 1.0
            if t < tele * 0.65 { pos[0].y += max(-300, min(300, (hy - pos[0].y) * 6)) * dt }
            else if !locked { lockCharge(hx: hx, edgeL: edgeL, edgeR: edgeR) }
            headTarget = 120 * min(1, t / 0.4)
            jawOpen = 0.6; shake = 3
            if t >= tele { go(.charge) }

        case .charge:
            dir = chargeDir
            pos[0].x += chargeDir * (enraged ? 1900 : 1500) * dt
            pos[0].y = chargeLane
            headTarget = 24; undulate = 0; jawOpen = 0.7
            if chargeDir * (pos[0].x - chargeEnd) >= 0 { pos[0].x = chargeEnd; crash() }

        case .stunned:
            headTarget = 0; undulate = 0; jawOpen = 0.35
            stars.isHidden = false
            if t > (enraged ? 1.7 : 2.3) { stars.isHidden = true; go(.recover) }

        case .recover:
            headTarget = 18; jawOpen = 0.1
            if t > 0.6 { go(.prowl) }

        case .dying:
            let n = min(count, Int(t / 0.07) + 1)
            while bursts < n { burst(bursts); bursts += 1 }
            if bursts >= count, t > CGFloat(count) * 0.07 + 0.9 { go(.gone) }
            return

        case .gone:
            return
        }
        pos[0].y = min(max(pos[0].y, -90), 210)

        for i in 1..<count {                                   // each segment trails the one ahead at a fixed distance
            let dx = pos[i - 1].x - pos[i].x, dy = pos[i - 1].y - pos[i].y, d = hypot(dx, dy)
            if d > spacing { pos[i].x += dx / d * (d - spacing); pos[i].y += dy / d * (d - spacing) }
        }
        for i in 0..<count {
            let wave = undulate * (0.5 + 0.5 * sin(CGFloat(now) * 5 - CGFloat(i) * 0.7))
            let target = i == 0 ? headTarget + wave * 0.5 : hgt[i - 1] * 0.82 + wave
            hgt[i] += (target - hgt[i]) * min(1, dt * (i == 0 ? 10 : 14))
            let j: CGFloat = i < 4 ? .random(in: -shake...shake) : 0
            nodes[i].position = CGPoint(x: pos[i].x + j, y: pos[i].y + hgt[i] + (i == 0 ? 40 : 0))
            nodes[i].zPosition = 300 - pos[i].y - CGFloat(i) * 0.02
            shadows[i].position = CGPoint(x: pos[i].x, y: pos[i].y - 4)
            shadows[i].zPosition = 299 - pos[i].y
        }
        nodes[0].xScale = dir
        jaw.zRotation += (-jawOpen - jaw.zRotation) * min(1, dt * 14)
    }

    private func go(_ s: State) {
        state = s; stateStart = now
        if s == .telegraph { locked = false }
        if s == .charge { chargeHit = false }
    }

    /// Fix the charge lane and direction, and mark the path on the ground.
    private func lockCharge(hx: CGFloat, edgeL: CGFloat, edgeR: CGFloat) {
        locked = true
        chargeLane = pos[0].y
        var d: CGFloat = hx >= pos[0].x ? 1 : -1
        chargeEnd = d > 0 ? edgeR : edgeL
        if d * (chargeEnd - pos[0].x) < 300 { d = -d; chargeEnd = d > 0 ? edgeR : edgeL }     // too close to that wall: go the long way
        chargeDir = d
        dir = d
        let x0 = pos[0].x
        warn.path = CGPath(rect: CGRect(x: min(x0, chargeEnd), y: chargeLane - 38, width: abs(chargeEnd - x0), height: 76), transform: nil)
        warn.isHidden = false
    }

    private func crash() {
        warn.isHidden = true
        go(.stunned)
        puff(at: CGPoint(x: pos[0].x, y: pos[0].y))
        onSlam?(1)
    }

    private func enrage() {
        enraged = true
        bone = SKColor(red: 1, green: 0.72, blue: 0.62, alpha: 1)
        bodies.forEach { $0.fillColor = bone }
        onSlam?(1)
        onEnrage?()
    }

    private func die() {
        guard state != .dying, state != .gone else { return }
        state = .dying; stateStart = now
        warn.isHidden = true; stars.isHidden = true
        onSlam?(2)
        onDefeated?()
    }

    // MARK: Effects

    private func puff(at p: CGPoint) {
        for _ in 0..<7 {
            let c = SKShapeNode(circleOfRadius: .random(in: 14...28))
            c.fillColor = SKColor(white: 0.8, alpha: 0.7); c.strokeColor = .clear
            c.position = CGPoint(x: p.x + .random(in: -40...40), y: p.y + .random(in: 0...30)); c.zPosition = 9000
            addChild(c)
            c.run(.sequence([.group([.moveBy(x: .random(in: -90...90), y: .random(in: 20...70), duration: 0.5),
                                     .scale(to: 2, duration: 0.5), .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
        }
    }

    private func burst(_ i: Int) {
        let p = nodes[i].position, r = radius(i)
        nodes[i].isHidden = true; shadows[i].isHidden = true
        for _ in 0..<5 {
            let c = styled(SKShapeNode(rect: CGRect(x: -r * 0.3, y: -r * 0.18, width: r * 0.6, height: r * 0.36), cornerRadius: 3), bone, line: 3)
            c.position = p; c.zPosition = 9000; c.zRotation = .random(in: 0...(.pi))
            addChild(c)
            let dx = CGFloat.random(in: -140...140), up = CGFloat.random(in: 60...220)
            let rise = SKAction.moveBy(x: dx, y: up, duration: 0.3); rise.timingMode = .easeOut
            let fall = SKAction.moveBy(x: dx * 0.3, y: -up - 120, duration: 0.5); fall.timingMode = .easeIn
            c.run(.sequence([.group([rise, .rotate(byAngle: .random(in: -6...6), duration: 0.8)]),
                             .group([fall, .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
        }
        if i % 3 == 0 { puff(at: CGPoint(x: p.x, y: pos[i].y)) }
    }

    private func flash(_ i: Int) {
        bodies[i].fillColor = .white
        bodies[i].removeAction(forKey: "flash")
        bodies[i].run(.sequence([.wait(forDuration: 0.07), .run { [weak self] in
            guard let self else { return }
            self.bodies[i].fillColor = self.bone
        }]), withKey: "flash")
    }

    // MARK: Combat

    private func multiplier(_ i: Int) -> CGFloat {
        let stunned = state == .stunned
        return i == 0 ? (stunned ? 3 : 1) : (stunned ? 1 : 0.35)
    }

    private func hurt(_ dmg: CGFloat, segment i: Int) {
        health -= dmg
        flash(i)
        if health <= 0 { health = 0; die() }
    }

    /// Both directions of damage for this frame: the hero's melee, arrows and rocks against the Wyrm,
    /// and the Wyrm's charge and bite against the hero.
    func resolve(hero a: Fighter, arrows: ProjectileField) -> [Combat.Contact] {
        var out: [Combat.Contact] = []
        guard state != .entering, state != .dying, state != .gone else { return out }

        let dir: CGFloat = a.rig.facingRight ? 1 : -1
        if !a.dead, !a.isHurt {
            for (index, hit, power) in a.activeHits {
                var best: (i: Int, dx: CGFloat)?
                for i in 0..<count where !nodes[i].isHidden {
                    let r = radius(i), dx = (pos[i].x - a.rig.position.x) * dir
                    guard dx >= hit.reach.lowerBound * a.stats.size - r, dx <= hit.reach.upperBound * a.stats.size + r,
                          abs(pos[i].y - a.rig.position.y) <= hit.depth + 12,
                          abs(hgt[i] + r - (a.rig.height + 30)) <= hit.heightTolerance + 40 else { continue }
                    if best == nil || i == 0 || (best!.i != 0 && dx < best!.dx) { best = (i, dx) }
                }
                guard let b = best, a.claim(index, id: ObjectIdentifier(self)) else { continue }
                let dmg = hit.damage * power * a.damageMultiplier * multiplier(b.i) * hit.vsHeavy
                let r = radius(b.i)
                a.hitStop(0.05)
                out.append(Combat.Contact(point: CGPoint(x: pos[b.i].x - dir * r, y: pos[b.i].y + hgt[b.i] + r + 10),
                                          damage: dmg, attacker: a, move: a.currentMove, ko: health - dmg <= 0))
                hurt(dmg, segment: b.i)
                if isDefeated { return out }
            }
        }
        for p in arrows.arrows where !p.spent && p.owner.team == a.team {
            let h = p.position.y - p.lane
            for i in 0..<count where !nodes[i].isHidden {
                let r = radius(i)
                guard abs(p.position.x - pos[i].x) <= r + 8, abs(p.lane - pos[i].y) <= p.hit.depth + 10,
                      abs(h - (hgt[i] + r)) <= r + 24 else { continue }
                let dmg = p.hit.damage * p.owner.stats.damageScale * multiplier(i)
                out.append(Combat.Contact(point: CGPoint(x: p.position.x, y: p.position.y), damage: dmg, attacker: p.owner, ko: health - dmg <= 0))
                arrows.remove(p, hit: true)
                hurt(dmg, segment: i)
                if isDefeated { return out }
                break
            }
        }

        // The Wyrm hurts the hero: the whole body while charging (jump it or roll it), the head if you hug it.
        guard !a.dead, a.vulnerable else { return out }
        let hx = a.rig.position.x, hy = a.rig.position.y
        if state == .charge, !chargeHit {
            for i in 0..<count where !nodes[i].isHidden {
                let r = radius(i)
                guard abs(pos[i].x - hx) <= r + 22, abs(pos[i].y - hy) <= 38, a.rig.height < hgt[i] + r * 1.4 else { continue }
                chargeHit = true
                a.receive(.wyrmCharge, power: 1, scale: 1, from: nil, away: chargeDir)
                out.append(Combat.Contact(point: CGPoint(x: hx, y: hy + a.rig.height + 60), damage: Hit.wyrmCharge.damage))
                break
            }
        } else if state == .prowl || state == .recover, now >= biteReadyAt,
                  abs(pos[0].x - hx) <= 85, abs(pos[0].y - hy) <= 36, a.rig.height < hgt[0] + 70 {
            biteReadyAt = now + 1.4
            a.receive(.wyrmBite, power: 1, scale: 1, from: nil, away: hx >= pos[0].x ? 1 : -1)
            out.append(Combat.Contact(point: CGPoint(x: hx, y: hy + a.rig.height + 60), damage: Hit.wyrmBite.damage))
        }
        return out
    }
}


// MARK: - Necromancer brain

/// Gravewood's boss. It stays back like an archer, shielded by a ward that soaks most damage. It opens the ward when it
/// has to commit: channelling a summon (hit him to break it), casting a floor eruption, or just after teleporting away.
/// Pressing close makes it vanish to the far side. At half health it summons faster, in bigger groups, and calls giants.
final class NecromancerBrain: Brain {
    private enum Act { case enter, kite, aim(TimeInterval), channel(TimeInterval, Bool), cast(TimeInterval), vanish(TimeInterval, Bool) }
    private var act = Act.enter
    private var holding = false
    private var enraged = false
    private var summons = 0
    private var nextAction: TimeInterval = 0
    private var nextSummon: TimeInterval = 0
    private var nextTeleport: TimeInterval = 0
    private var exposedUntil: TimeInterval = 0
    private var pressedSince: TimeInterval?
    private var wantBolt = false
    private var boltDeadline: TimeInterval = 0
    private let ward = SKShapeNode(ellipseOf: CGSize(width: 120, height: 160))

    var arena: ClosedRange<CGFloat> = 0...1334          // where it may stand; the scene keeps this inside the locked screen
    var minions: () -> Int = { 0 }
    var onSummon: ((Int, Bool) -> Void)?                // count, include a giant
    var onEruption: ((CGFloat, CGFloat) -> Void)?       // x, lane
    var onPoof: ((CGPoint) -> Void)?
    var onEnrage: (() -> Void)?

    init() {
        ward.fillColor = SKColor(red: 0.6, green: 0.3, blue: 1, alpha: 0.14)
        ward.strokeColor = SKColor(red: 0.75, green: 0.5, blue: 1, alpha: 0.8); ward.lineWidth = 4; ward.glowWidth = 6
        ward.position = CGPoint(x: 0, y: 78); ward.zPosition = 5
        ward.run(.repeatForever(.sequence([.fadeAlpha(to: 0.55, duration: 0.6), .fadeAlpha(to: 1, duration: 0.6)])))
    }

    func think(me: Fighter, foes: [Fighter], now: TimeInterval, dt: TimeInterval) -> MoveIntent {
        if ward.parent == nil { me.rig.addChild(ward) }
        if me.dead {
            if holding { me.releasePose(); holding = false }
            ward.isHidden = true
            return MoveIntent()
        }
        guard let hero = foes.first(where: { !$0.dead }) ?? foes.first else { return MoveIntent() }
        let dx = hero.rig.position.x - me.rig.position.x, dy = hero.rig.position.y - me.rig.position.y
        let faceRight = dx >= 0, dist = abs(dx)

        let exposed = now < exposedUntil
        me.damageTaken = exposed ? 1.4 : 0.35
        ward.isHidden = exposed
        if !enraged, me.healthFraction < 0.5 {
            enraged = true
            ward.strokeColor = SKColor(red: 1, green: 0.35, blue: 0.4, alpha: 0.9)
            ward.fillColor = SKColor(red: 1, green: 0.2, blue: 0.3, alpha: 0.14)
            onEnrage?()
        }

        if me.isHurt {                                       // knocked out of whatever it was doing
            if holding { me.releasePose(); holding = false }
            switch act {
            case .enter, .vanish: break
            default: act = .kite; nextAction = max(nextAction, now + 1.2)
            }
            return MoveIntent(facing: faceRight)
        }

        switch act {
        case .enter:
            if arena.contains(me.rig.position.x) { act = .kite; nextAction = now + 1.2; return MoveIntent(facing: faceRight) }
            let toward: CGFloat = me.rig.position.x < arena.lowerBound ? 1 : -1
            return MoveIntent(direction: CGVector(dx: toward, dy: 0), intensity: 0.6, facing: toward > 0)

        case .aim(let until):
            guard now >= until else { return MoveIntent(facing: faceRight) }
            me.face(towardX: hero.rig.position.x)
            me.handle(.swipe(faceRight ? .left : .right))      // back swipe = bolt, as with archers
            act = .kite
            nextAction = now + .random(in: enraged ? 1.4...2.2 : 2.2...3.2)
            return MoveIntent(facing: faceRight)

        case .channel(let start, let summoned):
            let t = now - start
            if !summoned, t >= 1.2 {
                act = .channel(start, true); summons += 1
                onSummon?(enraged ? 4 : 3, enraged && summons % 2 == 0)
            }
            if t >= 2.0 {
                me.releasePose(); holding = false
                act = .kite
                nextAction = now + .random(in: 2.0...3.0)
                nextSummon = now + (enraged ? 7 : 10)
            }
            return MoveIntent(facing: faceRight)

        case .cast(let until):
            if now >= until {
                me.releasePose(); holding = false
                act = .kite
                nextAction = now + .random(in: 1.6...2.6)
            }
            return MoveIntent(facing: faceRight)

        case .vanish(let until, let moved):
            if now < until { return MoveIntent() }
            if !moved {
                let mid = (arena.lowerBound + arena.upperBound) / 2
                onPoof?(me.rig.position)
                me.rig.position.x = hero.rig.position.x > mid ? arena.lowerBound + 40 : arena.upperBound - 40
                me.rig.position.y = .random(in: 50...170)
                onPoof?(me.rig.position)
                me.rig.run(.fadeIn(withDuration: 0.2))
                act = .vanish(now + 0.3, true)
            } else {
                act = .kite
                exposedUntil = now + 1.6                   // just landed: the ward is down
                nextAction = now + 1.2
            }
            return MoveIntent()

        case .kite:
            if dist < 230 { pressedSince = pressedSince ?? now } else { pressedSince = nil }
            if let p = pressedSince, now - p > 0.5, now >= nextTeleport {
                pressedSince = nil
                nextTeleport = now + (enraged ? 3.5 : 5)
                me.setInvulnerable(for: 0.6)
                me.rig.run(.fadeOut(withDuration: 0.18))
                onPoof?(me.rig.position)
                act = .vanish(now + 0.25, false)
                return MoveIntent()
            }
            if now >= nextAction {
                let r = Double.random(in: 0...1)
                let free = now >= nextSummon && minions() < 6
                if free, r < 0.45 || minions() == 0 {
                    me.holdPose(.powerUp, aura: true); holding = true
                    exposedUntil = now + 2.3
                    act = .channel(now, false)
                    return MoveIntent(facing: faceRight)
                } else if r < 0.75 {
                    me.holdPose(.powerUp, aura: false); holding = true
                    exposedUntil = now + 1.1
                    let offsets: [CGFloat] = enraged ? [-150, 0, 150] : [0]
                    for o in offsets { onEruption?(hero.rig.position.x + o, hero.rig.position.y) }
                    act = .cast(now + 0.7)
                    return MoveIntent(facing: faceRight)
                } else {
                    wantBolt = true; boltDeadline = now + 3
                    nextAction = now + 4
                }
            }
            let aligned = abs(dy) < 28
            if wantBolt {
                if now > boltDeadline { wantBolt = false }
                else if aligned, dist >= 260 { wantBolt = false; act = .aim(now + 0.55); return MoveIntent(facing: faceRight) }
            }
            var dir = CGVector.zero
            var intensity: CGFloat = 0
            if dist < 380 { dir.dx = faceRight ? -1 : 1; intensity = dist < 260 ? 0.9 : 0.55 }
            else if dist > 560 { dir.dx = faceRight ? 1 : -1; intensity = 0.5 }
            let x = me.rig.position.x
            if (dir.dx < 0 && x <= arena.lowerBound) || (dir.dx > 0 && x >= arena.upperBound) { dir.dx = 0 }     // don't back out of the screen
            if !aligned { dir.dy = dy > 0 ? 1 : -1; intensity = max(intensity, 0.4) }
            let len = hypot(dir.dx, dir.dy)
            if len > 0 { dir = CGVector(dx: dir.dx / len, dy: dir.dy / len) }
            return MoveIntent(direction: dir, intensity: len > 0 ? intensity : 0, facing: faceRight)
        }
    }
}


// MARK: - Bat

extension Fighter {
    /// Flyers have no weapon: their tap is a bite. It misses a hero who has jumped over the dive.
    static let flierMoves: [MoveKey: Move] = {
        let bite = Move(name: "bite", animation: .bite, lock: 0.4, lunge: 380).hitting(.batBite)
        return [MoveKey(context: .grounded, trigger: .tap): bite, MoveKey(context: .running, trigger: .tap): bite]
    }()
}

/// Bats hover out of ground reach (so jump to hit them), then rise and screech ("!"), and dive at where you were.
/// Sidestep, roll or jump the dive; a bat that misses climbs away. Hit one and it drops to the ground, stunned.
final class BatBrain: Brain {
    private enum Phase { case hover, telegraph(TimeInterval), dive(TimeInterval), bite(TimeInterval), retreat(TimeInterval) }
    private var phase = Phase.hover
    private var nextDive: TimeInterval = -1
    private var target = CGPoint.zero
    private let hoverY = CGFloat.random(in: 115...165)
    private let seed = Double.random(in: 0...6.28)
    private var marker: SKLabelNode?

    func think(me: Fighter, foes: [Fighter], now: TimeInterval, dt: TimeInterval) -> MoveIntent {
        guard let hero = foes.first(where: { !$0.dead }) else { return MoveIntent() }
        if nextDive < 0 { nextDive = now + .random(in: 1.4...3.0) }
        if me.isHurt || me.isDown {                         // knocked out of it: start over once it recovers
            phase = .hover; clearMarker()
            nextDive = max(nextDive, now + 1.5)
            me.flyRate = 5
            return MoveIntent()
        }
        let hx = hero.rig.position.x, hy = hero.rig.position.y
        let mx = me.rig.position.x, my = me.rig.position.y
        let dx = hx - mx, dy = hy - my
        let faceRight = dx >= 0

        switch phase {
        case .hover:
            me.flyRate = 5
            me.flyHeight = hoverY + CGFloat(sin(now * 3 + seed)) * 14
            var dirx: CGFloat = 0
            if abs(dx) > 310 { dirx = faceRight ? 1 : -1 } else if abs(dx) < 190 { dirx = faceRight ? -1 : 1 }
            let diry = max(-1, min(1, dy / 90)) * 0.5 + CGFloat(sin(now * 1.7 + seed)) * 0.4
            if now >= nextDive {
                phase = .telegraph(now + 0.55)
                let m = SKLabelNode(fontNamed: GameFont.banner)
                m.text = "!"; m.fontSize = 46; m.fontColor = SKColor(red: 1, green: 0.2, blue: 0.2, alpha: 1)
                m.position = CGPoint(x: 0, y: 110); m.zPosition = 50
                me.rig.addChild(m); marker = m
                m.run(.sequence([.scale(to: 1.4, duration: 0.1), .scale(to: 1, duration: 0.1)]))
            }
            let len = hypot(dirx, diry)
            return MoveIntent(direction: len > 0 ? CGVector(dx: dirx / len, dy: diry / len) : .zero, intensity: len > 0 ? 0.6 : 0, facing: faceRight)

        case .telegraph(let until):
            me.flyHeight = hoverY + 35                       // rears up
            if now >= until {
                clearMarker()
                target = CGPoint(x: hx, y: hy)               // dives at where you were: step aside
                phase = .dive(now + 1.2)
            }
            return MoveIntent(facing: faceRight)

        case .dive(let deadline):
            me.flyHeight = 16; me.flyRate = 11
            let tx = target.x - mx, ty = target.y - my
            let near = abs(hx - mx) <= 80 && abs(hy - my) <= 30 && me.rig.height < 90
            if near {
                me.handle(.tap)
                phase = .bite(now + 0.45)                    // stay low and facing you until the bite has landed
            } else if (abs(tx) < 30 && abs(ty) < 30) || now > deadline {
                phase = .retreat(now + 0.9)                  // missed it: climb away
            }
            let len = max(1, hypot(tx, ty))
            return MoveIntent(direction: CGVector(dx: tx / len, dy: ty / len), intensity: 1, facing: tx >= 0)

        case .bite(let until):
            me.flyHeight = 16; me.flyRate = 11
            if now >= until { phase = .retreat(now + 0.9) }
            return MoveIntent(facing: faceRight)

        case .retreat(let until):
            me.flyHeight = hoverY; me.flyRate = 6
            if now >= until { phase = .hover; nextDive = now + .random(in: 2.0...3.6) }
            return MoveIntent(direction: CGVector(dx: faceRight ? -1 : 1, dy: 0), intensity: 0.8)
        }
    }

    private func clearMarker() { marker?.removeFromParent(); marker = nil }
}


// MARK: - Bat King

/// Boss. Hovers at about 185, out of reach of ground attacks, so you have to jump and air-strike him. Three attacks:
///  - Swoop: a red lane lights up, then he dives along it. Leave the lane, or jump it. He crashes at the far side and lies there.
///  - Slam: he rises, drops, and sends a shockwave along the ground both ways. Jump it. He lies there afterwards.
///  - Screech: calls bats.
/// While he is low (landed or diving) he takes extra damage and ground attacks reach him. At half health he's faster and doubles up.
final class BatKingBrain: Brain {
    private enum Phase {
        case enter, hover(TimeInterval), warn(TimeInterval), dive(TimeInterval), land(TimeInterval)
        case screech(TimeInterval, Bool), slamUp(TimeInterval), slamDown(TimeInterval)
    }
    private var phase = Phase.enter
    private var enraged = false
    private var swoopDir: CGFloat = 1
    private var swoopLane: CGFloat = 100
    private var swoopEndX: CGFloat = 0
    private var swoopHit = false
    private var lastAttack = -1
    private var marker: SKLabelNode?
    private let hoverY: CGFloat = 185
    private(set) var debugPhase = "enter"

    var arena: ClosedRange<CGFloat> = 0...1334
    var minions: () -> Int = { 0 }
    var onSummon: ((Int) -> Void)?
    var onShockwave: ((CGFloat, CGFloat, Bool) -> Void)?
    var onTelegraph: ((CGFloat) -> Void)?
    var onThud: ((CGPoint) -> Void)?
    var onHeroHit: ((Fighter) -> Void)?
    var onEnrage: (() -> Void)?

    private func clamp(_ v: CGFloat) -> CGFloat { max(-1, min(1, v)) }

    private func showMarker(_ me: Fighter) {
        clearMarker()
        let m = SKLabelNode(fontNamed: GameFont.banner)
        m.text = "!"; m.fontSize = 34; m.fontColor = SKColor(red: 1, green: 0.2, blue: 0.2, alpha: 1)
        m.position = CGPoint(x: 0, y: 150); m.zPosition = 50
        me.rig.addChild(m); marker = m
        m.run(.sequence([.scale(to: 1.4, duration: 0.1), .scale(to: 1, duration: 0.1)]))
    }
    private func clearMarker() { marker?.removeFromParent(); marker = nil }

    func think(me: Fighter, foes: [Fighter], now: TimeInterval, dt: TimeInterval) -> MoveIntent {
        if me.dead { clearMarker(); debugPhase = "dead"; return MoveIntent() }
        guard let hero = foes.first(where: { !$0.dead }) else { return MoveIntent() }
        let mx = me.rig.position.x, my = me.rig.position.y, hx = hero.rig.position.x, hy = hero.rig.position.y
        let dx = hx - mx, dy = hy - my, faceRight = dx >= 0
        let d = CGFloat(dt)

        if !enraged, me.healthFraction < 0.5 { enraged = true; onEnrage?() }
        me.damageTaken = me.rig.height < 60 ? 1.7 : 1       // low: landed or diving, so he's open

        switch phase {
        case .enter:
            debugPhase = "enter"
            me.flyHeight = hoverY; me.flyRate = 4
            if arena.contains(mx) { phase = .hover(now + 1.4); return MoveIntent(facing: faceRight) }
            let toward: CGFloat = mx < arena.lowerBound ? 1 : -1
            return MoveIntent(direction: CGVector(dx: toward, dy: 0), intensity: 1, facing: toward > 0)

        case .hover(let until):
            debugPhase = "hover"
            me.flyRate = 4; me.flyHeight = hoverY + CGFloat(sin(now * 2.5)) * 14
            var dirx: CGFloat = 0
            if abs(dx) > 250 { dirx = faceRight ? 1 : -1 } else if abs(dx) < 110 { dirx = faceRight ? -1 : 1 }
            if (dirx < 0 && mx <= arena.lowerBound) || (dirx > 0 && mx >= arena.upperBound) { dirx = 0 }
            let diry = clamp(dy / 60)
            if now >= until {
                var options = [0, 1]
                if minions() < 3 { options.append(2) }
                options.removeAll { $0 == lastAttack }
                let pick = options.randomElement() ?? 0
                lastAttack = pick
                switch pick {
                case 0:  swoopLane = hy; onTelegraph?(swoopLane); showMarker(me); phase = .warn(now + (enraged ? 0.75 : 0.95))
                case 1:  showMarker(me); phase = .slamUp(now + (enraged ? 0.8 : 1.0))
                default: phase = .screech(now + 1.7, false)
                }
            }
            let len = hypot(dirx, diry)
            return MoveIntent(direction: len > 0 ? CGVector(dx: dirx / len, dy: diry / len) : .zero, intensity: len > 0 ? 0.8 : 0, facing: faceRight)

        case .warn(let until):
            debugPhase = "warn"
            me.flyHeight = hoverY + 45; me.flyRate = 6
            me.rig.position.y += (swoopLane - my) * min(1, d * 8)          // slide into the marked lane
            if now >= until {
                clearMarker()
                swoopDir = faceRight ? 1 : -1
                swoopEndX = swoopDir > 0 ? arena.upperBound : arena.lowerBound
                swoopHit = false
                phase = .dive(now + 2)
            }
            return MoveIntent(facing: faceRight)

        case .dive(let deadline):
            debugPhase = "dive"
            me.flyHeight = 20; me.flyRate = 12
            let speed: CGFloat = enraged ? 1150 : 950
            me.rig.position.x += swoopDir * speed * d
            me.rig.position.y += (swoopLane - my) * min(1, d * 10)
            if !swoopHit, abs(hx - me.rig.position.x) <= 110, abs(hy - me.rig.position.y) <= 42, hero.rig.height < 75, hero.vulnerable {
                swoopHit = true
                hero.receive(.batSwoop, power: 1, scale: 1, from: me, away: swoopDir)
                onHeroHit?(hero)
            }
            if swoopDir * (me.rig.position.x - swoopEndX) >= 0 || now > deadline {
                phase = .land(now + (enraged ? 1.6 : 2.1))
                onThud?(me.rig.position)
            }
            return MoveIntent(facing: swoopDir > 0)

        case .land(let until):
            debugPhase = "land"
            me.flyHeight = 0; me.flyRate = 14
            if now >= until { phase = .hover(now + 0.9) }
            return MoveIntent(facing: faceRight)

        case .screech(let until, let did):
            debugPhase = "screech"
            me.flyHeight = hoverY + 60; me.flyRate = 6
            if !did, now >= until - 1.0 { phase = .screech(until, true); onSummon?(enraged ? 3 : 2) }
            else if did, now >= until { phase = .hover(now + 1.0) }
            return MoveIntent(facing: faceRight)

        case .slamUp(let until):
            debugPhase = "slamUp"
            me.flyHeight = hoverY + 80; me.flyRate = 6
            if now >= until { clearMarker(); phase = .slamDown(now + 0.8) }
            return MoveIntent(direction: CGVector(dx: clamp(dx / 80), dy: clamp(dy / 50)), intensity: 0.9, facing: faceRight)

        case .slamDown(let deadline):
            debugPhase = "slamDown"
            me.flyHeight = 0; me.flyRate = 16
            if me.rig.height < 14 || now > deadline {
                onShockwave?(mx, my, enraged)
                onThud?(me.rig.position)
                phase = .land(now + (enraged ? 1.8 : 2.3))
            }
            return MoveIntent(facing: faceRight)
        }
    }
}


// MARK: - Demon

/// Mini-boss. On the ground it trades blows like a giant and throws fire without a weapon. Pressed, it blinks away like a wizard.
/// Every so often it rises like the Bat King, rains fire on marked spots, then crashes down and is stunned: that's the opening.
final class DemonBrain: Brain {
    let inner: EnemyBrain
    private enum Phase { case ground, fire(TimeInterval), fadeOut(TimeInterval), fadeIn(TimeInterval), rise(TimeInterval), rain(TimeInterval, Int), slam(TimeInterval), stunned(TimeInterval) }
    private var phase = Phase.ground
    private var started = false
    private var enraged = false
    private var nextFire: TimeInterval = 0
    private var nextBlink: TimeInterval = 0
    private var nextAir: TimeInterval = 0
    private var pressedSince: TimeInterval?
    private let hoverY: CGFloat = 110
    private(set) var debugPhase = "ground"

    var arena: ClosedRange<CGFloat> = 0...1334
    var onPoof: ((CGPoint) -> Void)?
    var onRain: (([CGPoint]) -> Void)?
    var onSlam: ((CGPoint) -> Void)?
    var onHeroHit: ((Fighter) -> Void)?
    var onEnrage: (() -> Void)?

    init(inner: EnemyBrain) { self.inner = inner }

    func think(me: Fighter, foes: [Fighter], now: TimeInterval, dt: TimeInterval) -> MoveIntent {
        if me.dead { debugPhase = "dead"; return MoveIntent() }
        guard let hero = foes.first(where: { !$0.dead }) else { return inner.think(me: me, foes: foes, now: now, dt: dt) }
        if !started { started = true; nextFire = now + 2; nextBlink = now + 4; nextAir = now + 9 }
        let mx = me.rig.position.x, hx = hero.rig.position.x, hy = hero.rig.position.y
        let dx = hx - mx, dy = hy - me.rig.position.y, dist = abs(dx), faceRight = dx >= 0
        if !enraged, me.healthFraction < 0.5 { enraged = true; onEnrage?() }

        switch phase {
        case .ground:
            debugPhase = "ground"
            me.damageTaken = 1; me.flyHeight = 0; me.flyRate = 14
            guard !me.isHurt else { return inner.think(me: me, foes: foes, now: now, dt: dt) }
            if now >= nextAir {
                inner.director.release(me)
                nextAir = now + (enraged ? 8 : 12)
                phase = .rise(now + 0.9)
                return MoveIntent(facing: faceRight)
            }
            if dist < 230 { pressedSince = pressedSince ?? now } else { pressedSince = nil }
            if now >= nextBlink, let p = pressedSince, now - p > 0.5 {
                inner.director.release(me)
                pressedSince = nil
                nextBlink = now + (enraged ? 4 : 6)
                me.setInvulnerable(for: 0.6)
                me.rig.run(.fadeOut(withDuration: 0.15))
                onPoof?(me.rig.position)
                phase = .fadeOut(now + 0.22)
                return MoveIntent()
            }
            if now >= nextFire, dist > 260, dist < 620 {
                if abs(dy) < 26 {
                    inner.director.release(me)
                    me.face(towardX: hx)
                    me.handle(.swipe(faceRight ? .left : .right))             // back swipe = fire bolt, from its innate moves
                    nextFire = now + .random(in: enraged ? 1.8...3 : 2.8...4.2)
                    phase = .fire(now + 0.7)
                    return MoveIntent(facing: faceRight)
                }
                return MoveIntent(direction: CGVector(dx: 0, dy: dy > 0 ? 1 : -1), intensity: 0.6, facing: faceRight)       // line up the shot
            }
            return inner.think(me: me, foes: foes, now: now, dt: dt)

        case .fire(let until):
            debugPhase = "fire"
            if now >= until { phase = .ground }
            return MoveIntent(facing: faceRight)

        case .fadeOut(let until):
            debugPhase = "blink"
            guard now >= until else { return MoveIntent() }
            func target(_ s: CGFloat) -> CGFloat { min(max(hx + s * .random(in: 320...440), arena.lowerBound), arena.upperBound) }
            var side: CGFloat = Bool.random() ? 1 : -1
            var x = target(side)
            if abs(x - hx) < 240 { side = -side; x = target(side) }
            me.rig.position = CGPoint(x: x, y: .random(in: 60...170))
            onPoof?(me.rig.position)
            me.rig.run(.fadeIn(withDuration: 0.2))
            me.face(towardX: hx)
            phase = .fadeIn(now + 0.3)
            return MoveIntent()

        case .fadeIn(let until):
            debugPhase = "blink"
            if now >= until { nextFire = min(nextFire, now + 0.4); phase = .ground }      // lands and throws fire almost at once
            return MoveIntent()

        case .rise(let until):
            debugPhase = "rise"
            me.flyHeight = hoverY; me.flyRate = 6
            if now >= until { phase = .rain(now + 0.4, enraged ? 4 : 3) }
            return MoveIntent(facing: faceRight)

        case .rain(let next, let left):
            debugPhase = "rain"
            me.flyHeight = hoverY + CGFloat(sin(now * 2.5)) * 14; me.flyRate = 6
            if now >= next {
                if left == 0 { phase = .slam(now + 1.0); return MoveIntent(facing: faceRight) }
                func clampX(_ x: CGFloat) -> CGFloat { min(max(x, arena.lowerBound), arena.upperBound) }
                var spots = [CGPoint(x: clampX(hx), y: hy)]                        // one on you, the rest around you
                for _ in 0..<(enraged ? 2 : 1) { spots.append(CGPoint(x: clampX(hx + .random(in: -260...260)), y: .random(in: 60...170))) }
                onRain?(spots)
                phase = .rain(now + (enraged ? 1.2 : 1.5), left - 1)
            }
            return MoveIntent(direction: CGVector(dx: max(-1, min(1, dx / 200)), dy: 0), intensity: 0.4, facing: faceRight)

        case .slam(let deadline):
            debugPhase = "slam"
            me.flyHeight = 0; me.flyRate = 16
            if me.rig.height < 14 || now > deadline {
                me.rig.height = 0
                onSlam?(me.rig.position)
                if abs(hx - me.rig.position.x) <= 150, abs(dy) <= 55, hero.rig.height < 80, hero.vulnerable {
                    hero.receive(.giantSlam, power: 1, scale: 1, from: me, away: faceRight ? 1 : -1)
                    onHeroHit?(hero)
                }
                phase = .stunned(now + (enraged ? 1.5 : 2.0))
            }
            return MoveIntent(facing: faceRight)

        case .stunned(let until):
            debugPhase = "stunned"
            me.damageTaken = 1.7; me.flyHeight = 0; me.flyRate = 14
            if now >= until { me.damageTaken = 1; nextFire = now + 1.5; phase = .ground }
            return MoveIntent(facing: faceRight)
        }
    }
}


// MARK: - Giant ambush

/// Wraps the giant's melee brain. Stand and trade blows and it gets angry: it vanishes, a red mark appears under you,
/// and it slams down on that spot. Move off the mark (or jump) and the slam whiffs, leaving it open for a moment.
final class GiantBrain: Brain {
    let inner: EnemyBrain
    private enum Phase { case normal, fade(TimeInterval), stalk(TimeInterval), mark(TimeInterval), recover(TimeInterval) }
    private var phase = Phase.normal
    private var lastHealth: CGFloat = -1
    private var anger: CGFloat = 0                    // damage taken lately; decays
    private var nextAllowed: TimeInterval = 0
    private var spot = CGPoint.zero
    private(set) var debugPhase = "normal"

    var angerLimit: CGFloat = 45
    var onMark: ((CGPoint, TimeInterval) -> Void)?
    var onPoof: ((CGPoint) -> Void)?
    var onSlam: ((CGPoint) -> Void)?
    var onHeroHit: ((Fighter) -> Void)?

    init(inner: EnemyBrain) { self.inner = inner }

    func think(me: Fighter, foes: [Fighter], now: TimeInterval, dt: TimeInterval) -> MoveIntent {
        if me.dead { debugPhase = "dead"; return MoveIntent() }
        if lastHealth < 0 { lastHealth = me.health; nextAllowed = now + 4 }
        if me.health < lastHealth { anger += lastHealth - me.health }
        lastHealth = me.health
        anger = max(0, anger - 12 * CGFloat(dt))
        guard let hero = foes.first(where: { !$0.dead }) else { return inner.think(me: me, foes: foes, now: now, dt: dt) }

        switch phase {
        case .normal:
            debugPhase = "normal"
            me.damageTaken = 1
            if anger >= angerLimit, now >= nextAllowed, !me.isHurt, !me.airborne {
                inner.director.release(me)
                me.setInvulnerable(for: 2.0)
                me.rig.run(.fadeOut(withDuration: 0.25))
                onPoof?(me.rig.position)
                phase = .fade(now + 0.3)
                return MoveIntent()
            }
            return inner.think(me: me, foes: foes, now: now, dt: dt)

        case .fade(let until):
            debugPhase = "fade"
            if now >= until { phase = .stalk(now + 0.7) }
            return MoveIntent()

        case .stalk(let until):                       // invisible and untouchable; the mark lands where you are when this ends
            debugPhase = "stalk"
            me.setInvulnerable(for: 0.2)
            me.rig.alpha = 0
            if now >= until {
                spot = hero.rig.position
                onMark?(spot, 0.65)
                phase = .mark(now + 0.65)
            }
            return MoveIntent()

        case .mark(let until):
            debugPhase = "mark"
            me.setInvulnerable(for: 0.2)
            me.rig.alpha = 0
            if now >= until {
                me.rig.position = CGPoint(x: spot.x + (hero.rig.position.x >= spot.x ? -90 : 90), y: spot.y)
                me.rig.height = 0
                me.rig.facingRight = hero.rig.position.x >= me.rig.position.x
                me.rig.alpha = 1
                me.rig.play(.slamLand)
                onPoof?(me.rig.position); onSlam?(me.rig.position)
                if abs(hero.rig.position.x - spot.x) <= 150, abs(hero.rig.position.y - spot.y) <= 55, hero.rig.height < 80, hero.vulnerable {
                    hero.receive(.giantSlam, power: 1, scale: 1, from: me, away: hero.rig.position.x >= me.rig.position.x ? 1 : -1)
                    onHeroHit?(hero)
                }
                anger = 0
                nextAllowed = now + 7
                phase = .recover(now + 1.3)
            }
            return MoveIntent()

        case .recover(let until):                     // landed: open to damage
            debugPhase = "recover"
            me.damageTaken = 1.5
            if now >= until { phase = .normal; me.damageTaken = 1 }
            return MoveIntent()
        }
    }
}


// MARK: - Doppelgänger

/// Boss. A shadow copy of whichever hero you chose: same special, and your weapon if it's a melee one.
/// It fights like a quick duelist, charges your hero's own special when its meter fills (the glow gives it away),
/// and watches you: do the same move three times in six seconds and it raises a shield and bashes back.
final class DoppelBrain: Brain {
    private enum Act { case tap, forward, up }
    private enum Phase {
        case approach
        case strike([(Act, TimeInterval)], TimeInterval)
        case recover(TimeInterval)
        case guardUp(TimeInterval)
    }
    private var phase = Phase.approach
    private var seen: [(name: String, at: TimeInterval)] = []
    private var lastName = "-"
    private var base: Weapon?                          // its own weapon, which it goes back to after a shield counter
    private var shielded = false
    private var nextCounterAt: TimeInterval = 4
    private var nextAttackAt: TimeInterval = 0
    private var lastRaise: TimeInterval = 0
    private var enraged = false
    private(set) var debugPhase = "approach"
    private(set) var counters = 0

    var onRead: ((String) -> Void)?
    var onEnrage: (() -> Void)?

    private func act(_ a: Act, _ me: Fighter) {
        switch a {
        case .tap:     me.handle(.tap)
        case .forward: me.handle(.swipe(me.rig.facingRight ? .right : .left))
        case .up:      me.handle(.swipe(.up))
        }
    }

    private func restoreWeapon(_ me: Fighter) {
        guard let w = base else { return }
        if shielded { me.dropGuard(); shielded = false }
        if me.weapon?.name != w.name { me.equip(w) }                 // also re-arms it if the shield was broken out of its hands
    }

    func think(me: Fighter, foes: [Fighter], now: TimeInterval, dt: TimeInterval) -> MoveIntent {
        if me.dead { debugPhase = "dead"; return MoveIntent() }
        guard let hero = foes.first(where: { !$0.dead }) else { return MoveIntent() }
        if base == nil { base = me.weapon }
        let dx = hero.rig.position.x - me.rig.position.x, dy = hero.rig.position.y - me.rig.position.y
        let faceRight = dx >= 0

        me.addMeter(dealt: CGFloat(dt) * (enraged ? 8 : 5))            // the special charges on its own, too
        if !enraged, me.healthFraction < 0.5 { enraged = true; onEnrage?() }

        // Watch the hero's habits.
        let name = hero.currentMoveName
        if name != lastName { lastName = name; if name != "-", !["roll", "jump", "guard", "run"].contains(where: { name.contains($0) }) { seen.append((name, now)) } }
        seen.removeAll { now - $0.at > 6 }
        let repeated = Dictionary(grouping: seen, by: { $0.name }).values.contains { $0.count >= 3 }

        if me.isCharging { debugPhase = "charging"; return MoveIntent(facing: faceRight) }
        if me.isHurt || me.isDown || me.incapacitated {
            restoreWeapon(me)
            phase = .recover(now + 0.3)
            debugPhase = "hurt"
            return MoveIntent()
        }

        switch phase {
        case .approach:
            debugPhase = "approach"
            if me.meter >= 1, abs(dx) < 400, abs(dy) < 90, !me.airborne {            // fire the hero's own special
                me.face(towardX: hero.rig.position.x)
                if me.beginSpecial() {
                    phase = .recover(now + (me.special?.chargeTime ?? 1) + 1.3)
                    return MoveIntent(facing: faceRight)
                }
            }
            if repeated, now >= nextCounterAt, abs(dx) < 450 {                       // "I've seen that one before"
                shielded = true
                me.equip(Weapons.shield)
                me.guardCapacity = 40; me.guardWalk = 0.8; me.guardBreaks = true
                nextCounterAt = now + 9; counters += 1
                seen.removeAll()
                phase = .guardUp(now + 3.2)
                onRead?("I SEE YOU")
                return MoveIntent(facing: faceRight)
            }
            let hammer = me.weapon?.name == "hammer"
            let range: CGFloat = hammer ? 190 : 120
            let tx = hero.rig.position.x - (faceRight ? 1 : -1) * range * 0.8, ty = hero.rig.position.y
            let vx = tx - me.rig.position.x, vy = ty - me.rig.position.y, d = max(1, hypot(vx, vy))
            if abs(dx) <= range, abs(dy) <= 28, now >= nextAttackAt {
                let steps: [[(Act, TimeInterval)]] = hammer
                    ? [[(.tap, 0.9)]]
                    : [[(.tap, 0.3), (.tap, 0.3), (.tap, 0.5)], [(.tap, 0.3), (.tap, 0.5)], [(.forward, 0.7)], [(.up, 0.28), (.tap, 0.34), (.tap, 0.4)]]
                phase = .strike(steps.randomElement() ?? [(.tap, 0.5)], now)
                return MoveIntent(facing: faceRight)
            }
            return MoveIntent(direction: CGVector(dx: vx / d, dy: vy / d), intensity: d > 70 ? 0.95 : 0.4, facing: faceRight)

        case .strike(var steps, let nextAt):
            debugPhase = "strike"
            if now >= nextAt, let step = steps.first {
                steps.removeFirst()
                me.face(towardX: hero.rig.position.x)
                act(step.0, me)
                if steps.isEmpty {
                    nextAttackAt = now + step.1 + Double.random(in: enraged ? 0.4...0.9 : 0.8...1.5)
                    phase = .recover(now + step.1)
                } else { phase = .strike(steps, now + step.1) }
            }
            return MoveIntent(facing: faceRight)

        case .recover(let until):
            debugPhase = "recover"
            if now >= until { restoreWeapon(me); phase = .approach }
            return MoveIntent(facing: faceRight)

        case .guardUp(let until):
            debugPhase = "guard"
            if me.weapon == nil || now >= until {                                    // the shield broke, or the window closed
                restoreWeapon(me)
                nextAttackAt = now + 0.5
                phase = .recover(now + 0.4)
                return MoveIntent(facing: faceRight)
            }
            if !me.guarding {
                if now - lastRaise > 0.25 { lastRaise = now; me.handle(.swipe(faceRight ? .left : .right)) }
            } else if me.guardEnergy >= 14, abs(dx) < 220 {                          // enough absorbed: bash it back
                me.face(towardX: hero.rig.position.x)
                act(.forward, me)
                phase = .recover(now + 0.8)
                return MoveIntent(facing: faceRight)
            }
            let advance: CGFloat = abs(dx) > 160 ? 0.5 : 0                           // a wall that walks at you
            let d = max(1, hypot(dx, dy))
            return MoveIntent(direction: CGVector(dx: dx / d, dy: dy / d), intensity: advance, facing: faceRight)
        }
    }
}


// MARK: - Level hazards

/// A strip of floor across a level (every lane between minY and maxY) that cycles: dormant (cooling crust),
/// warning (it glows and pulses), active (it burns anything standing on it). Reusable: lava now; ice, spikes or fire later.
struct LavaBand {
    var minY: CGFloat
    var maxY: CGFloat
    var period: TimeInterval = 7        // length of the whole cycle
    var warn: TimeInterval = 1.2        // how long it glows before it burns
    var active: TimeInterval = 1.8      // how long it burns
    var offset: TimeInterval = 0        // shifts the cycle, so neighbouring bands take turns
}

final class HazardField: SKNode {
    enum State { case dormant, warning, active }

    private struct Live {
        var band: LavaBand
        let node: SKShapeNode
        var start: TimeInterval?        // one-shot bands (erupt) run once from here and vanish
    }

    private var live: [Live] = []
    private var clock: TimeInterval = 0
    private var burnedAt: [ObjectIdentifier: TimeInterval] = [:]
    private var width: CGFloat = 0

    /// Called when something is burned (for the impact effect).
    var onBurn: ((Fighter) -> Void)?
    var burnCooldown: TimeInterval = 0.9

    override init() { super.init(); zPosition = -500 }
    required init?(coder: NSCoder) { fatalError() }

    /// Replaces every band with a level's own.
    func load(_ bands: [LavaBand], width: CGFloat) {
        live.forEach { $0.node.removeFromParent() }
        live = []; burnedAt = [:]; self.width = width
        for b in bands { live.append(Live(band: b, node: makeNode(b), start: nil)) }
    }

    /// A one-off band (a boss attack): warns, burns, then vanishes.
    func erupt(minY: CGFloat, maxY: CGFloat, warn: TimeInterval, active: TimeInterval) {
        let b = LavaBand(minY: minY, maxY: maxY, period: 1, warn: warn, active: active)
        live.append(Live(band: b, node: makeNode(b), start: clock))
    }

    var debugStates: String {
        live.compactMap { l in phase(l).map { p in "\(p.0)".prefix(1) + String(format: "%.0f", p.1 * 100) } }.joined(separator: "/")
    }

    private func makeNode(_ b: LavaBand) -> SKShapeNode {
        let n = SKShapeNode(rect: CGRect(x: -200, y: b.minY, width: max(width, 1600) + 400, height: b.maxY - b.minY))
        n.lineWidth = 4
        addChild(n)
        return n
    }

    private func phase(_ l: Live) -> (State, CGFloat)? {
        let b = l.band
        if let s = l.start {
            let t = clock - s
            if t < b.warn { return (.warning, CGFloat(t / b.warn)) }
            if t < b.warn + b.active { return (.active, CGFloat((t - b.warn) / b.active)) }
            return nil
        }
        let t = (clock + b.offset).truncatingRemainder(dividingBy: b.period)
        let rest = b.period - b.warn - b.active
        if t < rest { return (.dormant, CGFloat(t / rest)) }
        if t < rest + b.warn { return (.warning, CGFloat((t - rest) / b.warn)) }
        return (.active, CGFloat((t - rest - b.warn) / b.active))
    }

    func update(dt: TimeInterval, fighters: [Fighter], lanes: ClosedRange<CGFloat>) {
        clock += dt
        live.removeAll { l in
            if phase(l) == nil { l.node.removeFromParent(); return true }
            return false
        }
        for l in live {
            guard let (state, _) = phase(l) else { continue }
            switch state {
            case .dormant:
                l.node.fillColor = SKColor(red: 0.30, green: 0.07, blue: 0.05, alpha: 0.55)
                l.node.strokeColor = SKColor(red: 0.85, green: 0.30, blue: 0.08, alpha: 0.35)
                l.node.glowWidth = 0
            case .warning:
                let k = CGFloat(0.5 + 0.5 * sin(clock * 16))
                l.node.fillColor = SKColor(red: 0.55 + 0.4 * k, green: 0.10 + 0.25 * k, blue: 0.05, alpha: 0.75)
                l.node.strokeColor = SKColor(red: 1, green: 0.55, blue: 0.15, alpha: 0.9)
                l.node.glowWidth = 3 + 4 * k
            case .active:
                let f = CGFloat(0.5 + 0.5 * sin(clock * 22))
                l.node.fillColor = SKColor(red: 1, green: 0.40 + 0.2 * f, blue: 0.08, alpha: 0.92)
                l.node.strokeColor = SKColor(red: 1, green: 0.88, blue: 0.35, alpha: 1)
                l.node.glowWidth = 10
                for fighter in fighters where eligible(fighter) {
                    let y = fighter.rig.position.y
                    guard y >= l.band.minY, y <= l.band.maxY else { continue }
                    let id = ObjectIdentifier(fighter)
                    if let t = burnedAt[id], clock - t < burnCooldown { continue }
                    burnedAt[id] = clock
                    fighter.receive(.lava, power: 1, scale: 1, from: nil, away: 1)
                    shove(fighter, out: l.band, lanes: lanes)
                    onBurn?(fighter)
                }
            }
        }
    }

    private func eligible(_ f: Fighter) -> Bool {
        f.vulnerable && !f.stats.flies && !f.immuneToHazards && !f.airborne && f.rig.height < 25
    }

    /// The burn throws you clear of the band, to whichever edge is nearer (if both fit).
    private func shove(_ f: Fighter, out b: LavaBand, lanes: ClosedRange<CGFloat>) {
        let down = b.minY - 22, up = b.maxY + 22
        var target = (f.rig.position.y - b.minY) < (b.maxY - f.rig.position.y) ? down : up
        if !lanes.contains(target) { target = target == down ? up : down }
        f.rig.position.y = min(max(target, lanes.lowerBound), lanes.upperBound)
        f.rig.zPosition = 300 - f.rig.position.y
    }
}


// MARK: - Forge King

/// Boss. Slow and huge, he makes the floor dangerous:
///  - Smash: a slow hammer wind-up with a "!", then a slam in front of him that launches you and leaves a strip of lava in his lane.
///  - Flood: a "!" and a lava strip rises under your lane. Move.
///  - Brace: he lifts an anvil shield and stomps toward you. A hammer shatters it outright, and any heavy blow cracks it. Broken, he is staggered and takes extra damage.
/// At half health everything is quicker and floods come in pairs.
final class ForgeKingBrain: Brain {
    private enum Phase {
        case walk(TimeInterval), smash(TimeInterval), flood(TimeInterval), brace(TimeInterval), recover(TimeInterval)
    }
    private var phase = Phase.walk(0)
    private var enraged = false
    private var lastAttack = -1
    private var nextAttackAt: TimeInterval = 0
    private var base: Weapon?
    private var shielded = false
    private var marker: SKLabelNode?
    private var smashDirection: CGFloat = 1
    private var smashHit = false
    private var smashStart: TimeInterval = 0
    private(set) var debugPhase = "walk"
    private(set) var smashes = 0, floods = 0, braces = 0, breaks = 0

    var onErupt: ((CGFloat, CGFloat, TimeInterval, TimeInterval) -> Void)?
    var onThud: ((CGPoint) -> Void)?
    var onHeroHit: ((Fighter) -> Void)?
    var onEnrage: (() -> Void)?
    var onSay: ((String) -> Void)?

    private func mark(_ me: Fighter) {
        marker?.removeFromParent()
        let m = SKLabelNode(fontNamed: GameFont.banner)
        m.text = "!"; m.fontSize = 36; m.fontColor = SKColor(red: 1, green: 0.5, blue: 0.1, alpha: 1)
        m.position = CGPoint(x: 0, y: 190); m.zPosition = 50
        me.rig.addChild(m); marker = m
        m.run(.sequence([.scale(to: 1.4, duration: 0.1), .scale(to: 1, duration: 0.1)]))
    }
    private func clearMark() { marker?.removeFromParent(); marker = nil }

    private func restoreWeapon(_ me: Fighter) {
        guard let w = base else { return }
        if shielded { me.dropGuard(); shielded = false }
        if me.weapon?.name != w.name { me.equip(w) }
    }

    func think(me: Fighter, foes: [Fighter], now: TimeInterval, dt: TimeInterval) -> MoveIntent {
        if me.dead { clearMark(); debugPhase = "dead"; return MoveIntent() }
        guard let hero = foes.first(where: { !$0.dead }) else { return MoveIntent() }
        if base == nil { base = me.weapon }
        let dx = hero.rig.position.x - me.rig.position.x, dy = hero.rig.position.y - me.rig.position.y
        let faceRight = dx >= 0
        if !enraged, me.healthFraction < 0.5 { enraged = true; onEnrage?() }

        switch phase {
        case .walk:
            debugPhase = "walk"
            me.damageTaken = 1
            let hold: CGFloat = 230
            let tx = hero.rig.position.x - (faceRight ? 1 : -1) * hold * 0.8, ty = hero.rig.position.y
            let vx = tx - me.rig.position.x, vy = ty - me.rig.position.y, d = max(1, hypot(vx, vy))
            if now >= nextAttackAt, abs(dx) < 330 {
                var options = [0, 1, 2]
                options.removeAll { $0 == lastAttack }
                let pick = options.randomElement() ?? 0
                lastAttack = pick
                me.face(towardX: hero.rig.position.x)
                switch pick {
                case 0:
                    smashes += 1; smashHit = false; smashDirection = faceRight ? 1 : -1; smashStart = now
                    me.rig.speed = 0.6
                    me.rig.play(.hammerSlam)
                    mark(me)
                    phase = .smash(now + 0.42 / 0.6)
                case 1:
                    floods += 1
                    mark(me)
                    phase = .flood(now + (enraged ? 0.7 : 0.95))
                default:
                    braces += 1
                    shielded = true
                    me.equip(Weapons.shield)
                    me.guardCapacity = 90; me.guardWalk = 0.9; me.guardBreaks = true
                    onSay?("Come get it!")
                    phase = .brace(now + 4.5)
                }
                return MoveIntent(facing: faceRight)
            }
            return MoveIntent(direction: CGVector(dx: vx / d, dy: vy / d), intensity: d > 60 ? 0.9 : 0.3, facing: faceRight)

        case .smash(let impact):
            debugPhase = "smash"
            if now >= impact {
                clearMark(); me.rig.speed = 1
                let f = smashDirection
                let rx = (hero.rig.position.x - me.rig.position.x) * f
                if rx >= 20, rx <= 330, abs(hero.rig.position.y - me.rig.position.y) <= 85, hero.rig.height < 45, hero.vulnerable {
                    hero.receive(.forgeSmash, power: 1, scale: 1, from: me, away: f)
                    onHeroHit?(hero)
                }
                onThud?(me.rig.position)
                let y = me.rig.position.y
                onErupt?(y - 38, y + 38, enraged ? 0.7 : 0.9, 1.5)           // the slam leaves his lane burning
                phase = .recover(now + (enraged ? 1.0 : 1.5))
            }
            return MoveIntent()

        case .flood(let until):
            debugPhase = "flood"
            if now >= until {
                clearMark()
                let y = hero.rig.position.y
                onErupt?(y - 34, y + 34, enraged ? 0.9 : 1.1, 1.7)
                if enraged { onErupt?(y + 100, y + 160, 1.2, 1.7); onErupt?(y - 160, y - 100, 1.2, 1.7) }
                phase = .recover(now + (enraged ? 1.0 : 1.4))
            }
            return MoveIntent(facing: faceRight)

        case .brace(let until):
            debugPhase = "brace"
            if me.weapon == nil || now >= until {                            // the anvil cracked, or he gave up waiting
                let broke = me.weapon == nil
                if broke { breaks += 1; onSay?("My anvil!") }
                restoreWeapon(me)
                me.damageTaken = broke ? 1.7 : 1
                phase = .recover(now + (broke ? 2.2 : 0.5))
                return MoveIntent(facing: faceRight)
            }
            if !me.guarding { me.handle(.swipe(faceRight ? .left : .right)) }
            else if me.guardEnergy >= 45, abs(dx) < 220 {
                me.handle(.swipe(faceRight ? .right : .left))                // enough absorbed: bash it back
                restoreWeapon(me)
                phase = .recover(now + 1.0)
                return MoveIntent(facing: faceRight)
            }
            let d = max(1, hypot(dx, dy))
            return MoveIntent(direction: CGVector(dx: dx / d, dy: dy / d), intensity: abs(dx) > 170 ? 0.8 : 0, facing: faceRight)

        case .recover(let until):
            debugPhase = "recover"
            if now >= until { restoreWeapon(me); me.damageTaken = 1; nextAttackAt = now + (enraged ? 0.3 : 0.8); phase = .walk(0) }
            return MoveIntent(facing: faceRight)
        }
    }
}


// MARK: - Darkness

/// A dim veil over the screen with soft holes of light. Lives on the camera. Drawn into a quarter-resolution bitmap each frame
/// (black fill, then a radial gradient punched out for each light) and stretched over the view.
final class DarknessLayer: SKNode {
    struct Light { var x: CGFloat; var y: CGFloat; var radius: CGFloat }
    var enabled = false { didSet { isHidden = !enabled } }

    private let sprite = SKSpriteNode()
    private var ctx: CGContext?
    private var viewSize = CGSize.zero
    private let cell: CGFloat = 4
    private let gradient: CGGradient = {
        let c: [CGFloat] = [1, 1, 1, 1,  1, 1, 1, 0.92,  1, 1, 1, 0.55,  1, 1, 1, 0.18,  1, 1, 1, 0]
        return CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(), colorComponents: c, locations: [0, 0.4, 0.65, 0.85, 1], count: 5)!
    }()

    func configure(size: CGSize) {
        viewSize = size
        let w = max(8, Int(size.width / cell)), h = max(8, Int(size.height / cell))
        ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        sprite.size = size
        if sprite.parent == nil { addChild(sprite) }
        isHidden = !enabled
    }

    /// `darkness` is how opaque the veil is away from every light (0.85 = dim, silhouettes still show).
    func render(lights: [Light], camPos: CGPoint, camScale: CGFloat, darkness: CGFloat) {
        guard let ctx else { return }
        let w = CGFloat(ctx.width), h = CGFloat(ctx.height)
        ctx.setBlendMode(.copy)
        ctx.setFillColor(red: 0.02, green: 0.02, blue: 0.07, alpha: darkness)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setBlendMode(.destinationOut)
        for l in lights {
            let cx = ((l.x - camPos.x) / camScale + viewSize.width / 2) / cell
            let cy = ((l.y - camPos.y) / camScale + viewSize.height / 2) / cell
            let r = l.radius / camScale / cell
            guard cx + r > 0, cx - r < w, cy + r > 0, cy - r < h else { continue }
            ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: cx, y: cy), startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: r, options: [])
        }
        guard let img = ctx.makeImage() else { return }
        let tex = SKTexture(cgImage: img)
        tex.filteringMode = .linear
        sprite.texture = tex
    }
}


// MARK: - Lantern Wraith

/// Boss, for dark levels. He can only be hurt while he is inside the hero's light (a pale body outside it, solid inside), so he stays
/// at the edge of the dark and fights from there:
///  - Bolt: he teleports to the edge of your light, lines up with your lane, and shoots after a "!".
///  - Curse: spikes erupt under you (three at once when angry).
///  - Gloom: he channels, and your light shrinks for a few seconds, which makes him harder to catch.
/// Walk into him and he backs away; stay on him and he teleports out again.
final class WraithBrain: Brain {
    private enum Act { case enter, kite, aim(TimeInterval), cast(TimeInterval), gloom(TimeInterval, Bool), vanish(TimeInterval, Bool) }
    private var act = Act.enter
    private var holding = false
    private var enraged = false
    private var nextAction: TimeInterval = 0
    private var nextGloom: TimeInterval = 9
    private var nextTeleport: TimeInterval = 0
    private var pressedSince: TimeInterval?
    private var wantBolt = false
    private var boltDeadline: TimeInterval = 0
    private var marker: SKLabelNode?
    private(set) var debugPhase = "enter"
    private(set) var lit = false
    private(set) var bolts = 0, curses = 0, glooms = 0, teleports = 0

    var arena: ClosedRange<CGFloat> = 0...1334
    var heroLight: () -> CGFloat = { 465 }
    var onEruption: ((CGFloat, CGFloat) -> Void)?
    var onGloom: ((TimeInterval) -> Void)?
    var onPoof: ((CGPoint) -> Void)?
    var onEnrage: (() -> Void)?

    private func mark(_ me: Fighter) {
        marker?.removeFromParent()
        let m = SKLabelNode(fontNamed: GameFont.banner)
        m.text = "!"; m.fontSize = 34; m.fontColor = SKColor(red: 0.6, green: 0.95, blue: 1, alpha: 1)
        m.position = CGPoint(x: 0, y: 125); m.zPosition = 50
        me.rig.addChild(m); marker = m
        m.run(.sequence([.scale(to: 1.4, duration: 0.1), .scale(to: 1, duration: 0.1)]))
    }
    private func clearMark() { marker?.removeFromParent(); marker = nil }

    func think(me: Fighter, foes: [Fighter], now: TimeInterval, dt: TimeInterval) -> MoveIntent {
        if me.dead {
            clearMark(); me.rig.alpha = 1
            if holding { me.releasePose(); holding = false }
            debugPhase = "dead"
            return MoveIntent()
        }
        guard let hero = foes.first(where: { !$0.dead }) ?? foes.first else { return MoveIntent() }
        let dx = hero.rig.position.x - me.rig.position.x, dy = hero.rig.position.y - me.rig.position.y
        let dist = hypot(dx, dy), faceRight = dx >= 0
        let radius = heroLight()
        lit = dist < radius * 0.8
        me.damageTaken = 1
        if !enraged, me.healthFraction < 0.5 { enraged = true; onEnrage?() }

        var vanishing = false
        if case .vanish = act { vanishing = true }
        if !lit && !vanishing { me.setInvulnerable(for: 0.15) }        // outside your light nothing touches him
        if !vanishing { me.rig.alpha = lit ? 1 : 0.5 }                 // pale outside the light, solid inside

        if me.isHurt {
            if holding { me.releasePose(); holding = false }
            clearMark()
            switch act {
            case .enter, .vanish: break
            default: act = .kite; nextAction = max(nextAction, now + 1.2)
            }
            return MoveIntent(facing: faceRight)
        }

        switch act {
        case .enter:
            debugPhase = "enter"
            if arena.contains(me.rig.position.x) { act = .kite; nextAction = now + 1.2; return MoveIntent(facing: faceRight) }
            let toward: CGFloat = me.rig.position.x < arena.lowerBound ? 1 : -1
            return MoveIntent(direction: CGVector(dx: toward, dy: 0), intensity: 0.6, facing: toward > 0)

        case .aim(let until):
            debugPhase = "aim"
            guard now >= until else { return MoveIntent(facing: faceRight) }
            clearMark()
            me.face(towardX: hero.rig.position.x)
            me.handle(.swipe(faceRight ? .left : .right))              // back swipe = bolt, as with the Necromancer
            bolts += 1
            act = .kite
            nextAction = now + .random(in: enraged ? 1.2...2.0 : 2.0...3.0)
            return MoveIntent(facing: faceRight)

        case .cast(let until):
            debugPhase = "curse"
            if now >= until {
                me.releasePose(); holding = false
                act = .kite
                nextAction = now + .random(in: 1.6...2.6)
            }
            return MoveIntent(facing: faceRight)

        case .gloom(let start, let done):
            debugPhase = "gloom"
            let t = now - start
            if !done, t >= 1.0 { act = .gloom(start, true); onGloom?(enraged ? 8 : 6) }
            if t >= 1.8 {
                me.releasePose(); holding = false
                act = .kite
                nextAction = now + .random(in: 1.6...2.6)
                nextGloom = now + (enraged ? 10 : 14)
            }
            return MoveIntent(facing: faceRight)

        case .vanish(let until, let moved):
            debugPhase = "vanish"
            if now < until { return MoveIntent() }
            if !moved {
                onPoof?(me.rig.position)
                let side: CGFloat = Bool.random() ? 1 : -1
                var x = hero.rig.position.x + side * (radius * 1.05 + .random(in: 0...50))
                if !arena.contains(x) { x = hero.rig.position.x - side * (radius * 1.05) }
                x = min(max(x, arena.lowerBound), arena.upperBound)
                me.rig.position = CGPoint(x: x, y: min(max(hero.rig.position.y + .random(in: -10...10), 40), 170))
                onPoof?(me.rig.position)
                me.rig.run(.fadeIn(withDuration: 0.2))
                act = .vanish(now + 0.3, true)
            } else {
                act = .kite
                wantBolt = true; boltDeadline = now + 3             // lands at the edge of your light, and lines up a shot straight away
                nextAction = now + 3.5
            }
            return MoveIntent()

        case .kite:
            debugPhase = "kite"
            if dist < 230 { pressedSince = pressedSince ?? now } else { pressedSince = nil }
            if let p = pressedSince, now - p > 1.1, now >= nextTeleport {
                pressedSince = nil
                nextTeleport = now + (enraged ? 2.6 : 3.8)
                teleports += 1
                me.setInvulnerable(for: 0.6)
                me.rig.run(.fadeOut(withDuration: 0.18))
                onPoof?(me.rig.position)
                act = .vanish(now + 0.25, false)
                return MoveIntent()
            }
            if now >= nextAction {
                let r = Double.random(in: 0...1)
                if now >= nextGloom, r < 0.4 {
                    glooms += 1
                    me.holdPose(.powerUp, aura: true); holding = true
                    act = .gloom(now, false)
                    return MoveIntent(facing: faceRight)
                } else if r < 0.65 {
                    curses += 1
                    me.holdPose(.powerUp, aura: false); holding = true
                    let offsets: [CGFloat] = enraged ? [-150, 0, 150] : [0]
                    for o in offsets { onEruption?(hero.rig.position.x + o, hero.rig.position.y) }
                    act = .cast(now + 0.7)
                    return MoveIntent(facing: faceRight)
                } else {
                    wantBolt = true; boltDeadline = now + 3
                    nextAction = now + 3.5
                }
            }
            let aligned = abs(dy) < 28
            if wantBolt {
                if now > boltDeadline { wantBolt = false }
                else if aligned, dist >= 200 { wantBolt = false; act = .aim(now + 0.6); mark(me); return MoveIntent(facing: faceRight) }
            }
            var dir = CGVector.zero
            var intensity: CGFloat = 0
            let hold = max(300, radius)
            if dist < hold * 0.8 { dir.dx = faceRight ? -1 : 1; intensity = dist < hold * 0.55 ? 0.9 : 0.55 }      // back away from the light
            else if dist > hold * 1.3 { dir.dx = faceRight ? 1 : -1; intensity = 0.5 }
            let x = me.rig.position.x
            if (dir.dx < 0 && x <= arena.lowerBound) || (dir.dx > 0 && x >= arena.upperBound) { dir.dx = 0 }
            if !aligned { dir.dy = dy > 0 ? 1 : -1; intensity = max(intensity, 0.4) }
            let len = hypot(dir.dx, dir.dy)
            if len > 0 { dir = CGVector(dx: dir.dx / len, dy: dir.dy / len) }
            return MoveIntent(direction: dir, intensity: len > 0 ? intensity : 0, facing: faceRight)
        }
    }
}


// MARK: - Frost wizard

/// Keeps its distance and lines up shots like an archer, but is more cunning: every ice bolt is telegraphed with a flash,
/// it teleports away when you get close (sometimes to the far side of you), and now and then blinks in to ambush.
/// The Archmage fires volleys of three and calls two wizards when he drops below half health.
final class WizardBrain: Brain {
    private enum Act { case position, aim(TimeInterval), rest(TimeInterval), blink(TimeInterval, Bool) }
    private var act = Act.position
    private var started = false
    private var nextShot: TimeInterval = 0
    private var nextBlink: TimeInterval = 0
    private var nextAmbush: TimeInterval = 0
    private var pressedSince: TimeInterval?
    private var volleyLeft = 0
    private var farSide = false
    private var enraged = false
    let boss: Bool

    var arena: ClosedRange<CGFloat> = 0...1334          // where it may teleport to; the scene keeps this inside the locked screen
    var onPoof: ((CGPoint) -> Void)?
    var onEnrage: (() -> Void)?
    var onSummon: (() -> Void)?

    init(boss: Bool = false) { self.boss = boss }

    private var minRange: CGFloat { boss ? 340 : 280 }
    private var maxRange: CGFloat { boss ? 560 : 470 }

    /// The tell: a cyan ring swells over its head until the bolt leaves.
    private func beginAim(_ me: Fighter, _ now: TimeInterval, delay: TimeInterval) {
        act = .aim(now + delay)
        let ring = SKShapeNode(circleOfRadius: 14)
        ring.strokeColor = SKColor(red: 0.6, green: 0.95, blue: 1, alpha: 1); ring.lineWidth = 4; ring.glowWidth = 6
        ring.fillColor = SKColor(red: 0.75, green: 0.95, blue: 1, alpha: 0.35)
        ring.position = CGPoint(x: 0, y: 104); ring.zPosition = 20
        me.rig.addChild(ring)
        ring.run(.sequence([.group([.scale(to: 2.4, duration: delay), .fadeOut(withDuration: delay)]), .removeFromParent()]))
    }

    private func startBlink(_ me: Fighter, _ now: TimeInterval, far: Bool) -> MoveIntent {
        farSide = far; pressedSince = nil
        nextBlink = now + (boss ? 3.5 : 5)
        me.setInvulnerable(for: 0.6)
        me.rig.run(.fadeOut(withDuration: 0.15))
        onPoof?(me.rig.position)
        act = .blink(now + 0.22, false)
        return MoveIntent()
    }

    func think(me: Fighter, foes: [Fighter], now: TimeInterval, dt: TimeInterval) -> MoveIntent {
        guard !me.dead, let hero = foes.first(where: { !$0.dead }) else { return MoveIntent() }
        if !started { started = true; nextShot = now + .random(in: 0.9...1.6); nextBlink = now + 1.5; nextAmbush = now + .random(in: 7...11) }
        let dx = hero.rig.position.x - me.rig.position.x, dy = hero.rig.position.y - me.rig.position.y
        let faceRight = dx >= 0, dist = abs(dx)
        if boss, !enraged, me.healthFraction < 0.5 { enraged = true; onEnrage?(); onSummon?() }

        if me.isHurt {                                       // knocked out of whatever it was doing
            if case .blink = act {} else { act = .rest(now + 0.5); volleyLeft = 0 }
            return MoveIntent(facing: faceRight)
        }

        switch act {
        case .aim(let until):
            if dist < minRange * 0.5 { act = .position; volleyLeft = 0; return MoveIntent(facing: faceRight) }     // rushed mid-cast: abort
            guard now >= until else { return MoveIntent(facing: faceRight) }
            me.face(towardX: hero.rig.position.x)
            me.handle(.swipe(faceRight ? .left : .right))                  // back swipe = bolt, as with archers
            volleyLeft = max(0, volleyLeft - 1)
            NSLog("WIZ shot boss=%d dist=%.0f dy=%.0f left=%d", boss ? 1 : 0, dist, dy, volleyLeft)
            act = .rest(now + (volleyLeft > 0 ? 0.62 : 0.45))
            return MoveIntent(facing: faceRight)

        case .rest(let until):
            if now >= until {
                if volleyLeft > 0 { beginAim(me, now, delay: 0.25) }
                else {
                    act = .position
                    nextShot = now + .random(in: boss ? (enraged ? 0.9...1.5 : 1.3...2.1) : 1.7...2.9)
                }
            }
            return MoveIntent(facing: faceRight)

        case .blink(let until, let moved):
            if now < until { return MoveIntent() }
            if !moved {
                let hx = hero.rig.position.x
                let current: CGFloat = me.rig.position.x >= hx ? 1 : -1
                var side = farSide ? -current : current
                func target(_ s: CGFloat) -> CGFloat { min(max(hx + s * .random(in: 340...470), arena.lowerBound), arena.upperBound) }
                var x = target(side)
                if abs(x - hx) < 260 { side = -side; x = target(side) }          // squashed against a wall: go the other way
                me.rig.position = CGPoint(x: x, y: .random(in: 60...170))
                onPoof?(me.rig.position)
                me.rig.run(.fadeIn(withDuration: 0.2))
                me.face(towardX: hx)
                NSLog("WIZ blink boss=%d far=%d from=%.0f to=%.0f hero=%.0f", boss ? 1 : 0, farSide ? 1 : 0, hx - current * 0, x, hx)
                act = .blink(now + 0.3, true)
            } else {
                act = .position
                nextShot = min(nextShot, now + 0.5)                              // lands and casts almost at once
            }
            return MoveIntent()

        case .position:
            if dist < (boss ? 240 : 200) { pressedSince = pressedSince ?? now } else { pressedSince = nil }
            if let p = pressedSince, now - p > 0.35, now >= nextBlink {
                return startBlink(me, now, far: Double.random(in: 0...1) < 0.35)        // pressed: blink away, sometimes behind you
            }
            if now >= nextAmbush, now >= nextBlink {
                nextAmbush = now + .random(in: 8...12)
                return startBlink(me, now, far: true)                                    // an ambush from the far side
            }
            var dir = CGVector.zero
            var intensity: CGFloat = 0
            if dist < minRange { dir.dx = faceRight ? -1 : 1; intensity = dist < minRange * 0.7 ? 0.95 : 0.6 }
            else if dist > maxRange { dir.dx = faceRight ? 1 : -1; intensity = 0.55 }
            let aligned = abs(dy) < 24
            if !aligned { dir.dy = dy > 0 ? 1 : -1; intensity = max(intensity, 0.45) }
            if aligned, dist >= minRange * 0.7, dist <= maxRange + 120, now >= nextShot {
                volleyLeft = boss ? (enraged ? 4 : 3) : 1
                beginAim(me, now, delay: boss ? 0.45 : .random(in: 0.5...0.7))
                return MoveIntent(facing: faceRight)
            }
            let len = hypot(dir.dx, dir.dy)
            if len > 0 { dir = CGVector(dx: dir.dx / len, dy: dir.dy / len) }
            return MoveIntent(direction: dir, intensity: len > 0 ? intensity : 0, facing: faceRight)
        }
    }
}
