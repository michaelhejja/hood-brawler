import SpriteKit

// MARK: - Data

/// A weapon is data: a name, how hard it hits, and how to draw it (grip at the origin, blade along +y).
struct Weapon {
    let name: String
    var power: CGFloat = 1          // multiplies the damage of weapon moves (hook family, uppercut, slams)
    let make: () -> SKNode
}

/// A consumable. `apply` returns true when it was used up; false leaves it on the ground (e.g. food at full health).
struct Item {
    let name: String
    let make: () -> SKNode
    let apply: (Fighter) -> Bool
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
}

// MARK: - World objects

/// Something lying on the ground (or tumbling through the air after a drop).
final class Pickup: SKNode {
    let kind: PickupKind
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
        add(Pickup(kind: kind, x: p.x, lane: p.y, height: height, vx: vx, vz: vz, spin: vx >= 0 ? 14 : -14))
    }

    /// Put something straight on the ground.
    func place(_ kind: PickupKind, at p: CGPoint) {
        let pk = Pickup(kind: kind, x: p.x, lane: p.y, height: 0, vx: 0, vz: 0, spin: 0)
        pk.settle(animated: false)
        add(pk)
    }

    private func add(_ pk: Pickup) {
        pickups.append(pk); addChild(pk)
        while pickups.count > maxPickups, let old = pickups.first(where: { $0.landed }) {
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
        pk.run(.sequence([.group([.scale(to: 1.4, duration: 0.15), .fadeOut(withDuration: 0.15)]), .removeFromParent()]))
    }

    func clear() { pickups.forEach { $0.removeFromParent() }; pickups = [] }

    func step(dt: CGFloat, minX: CGFloat, maxX: CGFloat) { pickups.forEach { $0.step(dt, minX: minX, maxX: maxX) } }

    func floatText(_ text: String, at p: CGPoint, color: SKColor) {
        for (i, c) in [SKColor.black, color].enumerated() {
            let l = SKLabelNode(fontNamed: "Menlo-Bold")
            l.text = text; l.fontSize = 28; l.fontColor = c
            l.position = CGPoint(x: p.x + (i == 0 ? 2 : 0), y: p.y + (i == 0 ? -2 : 0)); l.zPosition = 9500 + CGFloat(i)
            addChild(l)
            l.run(.sequence([.group([.moveBy(x: 0, y: 55, duration: 0.8),
                                     .sequence([.wait(forDuration: 0.4), .fadeOut(withDuration: 0.4)])]),
                             .removeFromParent()]))
        }
    }
}
