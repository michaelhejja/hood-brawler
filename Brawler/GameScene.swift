import SwiftUI
import SpriteKit
import GameController

/// Per-level horizontal bounds. The world spans minX...maxX.
/// The camera stops at the ends, so the hero walks toward the edge instead of staying centered.
struct LevelConfig {
    var minX: CGFloat = 0
    var maxX: CGFloat = 4000
    var heroInset: CGFloat = 40     // how close the hero's origin may get to either world edge
}

final class GameScene: SKScene {
    var level = LevelConfig()

    let hero = Fighter(name: "hero", skin: HeroSkin())
    private var enemies: [Fighter] = []

    private let cam = SKCameraNode()
    private let groundHeight: CGFloat = 250
    private let laneMinY: CGFloat = -100      // can walk below the original ground line
    private let laneStartY: CGFloat = 120
    private let verticalFollow: CGFloat = 0.7 // how much of the hero's vertical travel the camera follows
    private var baseCamY: CGFloat { size.height / 2 }
    private var layers: [(node: SKNode, fx: CGFloat, fy: CGFloat, tileW: CGFloat)] = []

    let input = InputController()
    private var lastTime: TimeInterval = 0
    private let debugLayer = SKNode()
    private let debugLabel = SKLabelNode(fontNamed: "Menlo-Bold")

    override init() {
        super.init(size: CGSize(width: 1334, height: 750))
        scaleMode = .aspectFill
        backgroundColor = SKColor(red: 0.55, green: 0.78, blue: 0.85, alpha: 1)
        camera = cam
        cam.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(cam)
        buildWorld()

        hero.rig.scaleFactor = 1.3
        hero.rig.position = CGPoint(x: size.width / 2, y: 120)
        hero.logPrefix = ""
        addChild(hero.rig)
        addChild(pickups)
        addChild(arrows)
        hero.world = pickups
        hero.onMoveStart = { [weak self] in self?.windup($0) }
        if args.contains("-fxhold") { fx.holdScale = 6 }
        hero.projectiles = arrows
        hero.collectsItems = true

        for (x, y) in [(900, 90), (1150, 170), (1450, 120)] as [(CGFloat, CGFloat)] { spawnEnemy(x: x, y: y) }
        if !testMode {
            pickups.place(.weapon(Weapons.axe), at: CGPoint(x: 480, y: 100))
            pickups.place(.item(Items.food), at: CGPoint(x: 800, y: 70))
            pickups.place(.weapon(Weapons.bow), at: CGPoint(x: 620, y: 150))
            pickups.place(.item(Items.quiver), at: CGPoint(x: 720, y: 160))
        }
        hero.rig.zPosition = 300 - hero.rig.position.y

        // Debug overlay lives on the camera so it stays on screen
        debugLayer.zPosition = 10_000
        cam.addChild(debugLayer)
        let divider = SKShapeNode(rect: CGRect(x: -1, y: -size.height / 2, width: 2, height: size.height))
        divider.fillColor = .white; divider.strokeColor = .clear; divider.alpha = 0.15
        divider.zPosition = 10_000
        cam.addChild(divider)
        debugLabel.fontSize = 22
        debugLabel.fontColor = .white
        debugLabel.zPosition = 10_001
        cam.addChild(debugLabel)
        hero.brain = PlayerBrain(input: input, fighter: hero)
        heroBar.zPosition = 10_000
        cam.addChild(heroBar)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Enemies

    private let args = ProcessInfo.processInfo.arguments
    private var testMode: Bool { args.contains("-hittest") || args.contains("-divetest") || args.contains("-itemtest") || args.contains("-bowtest") || args.contains("-fxtest") }
    private var nextCrowdLog: TimeInterval = 0
    private let crowd = CrowdDirector()
    private let pickups = PickupField()
    private let fx = CameraFX()
    private var fxEnabled: Bool { !args.contains("-nofx") }
    private var gameTime: TimeInterval = 0      // advances at the (possibly slowed) game rate; every gameplay timer runs on it
    private var realNow: TimeInterval = 0
    private var fxPeakZoom: CGFloat = 0, fxMinScale: CGFloat = 1, fxActive: TimeInterval = 0
    private let arrows = ProjectileField()
    private let archerChance = 0.3           // chance a spawned skeleton carries a bow
    private let foodDropChance = 0.3          // chance a KO'd enemy drops food
    private var bars: [ObjectIdentifier: HealthBar] = [:]
    private let heroBar = HealthBar(width: 300, height: 14)
    private var nextSpawn: TimeInterval = 0

    private func spawnEnemy(x: CGFloat, y: CGFloat) {
        let e = Fighter(name: "skeleton", skin: SkeletonSkin(), stats: .skeleton)
        e.team = 1
        e.world = pickups
        e.projectiles = arrows
        if !testMode, Double.random(in: 0...1) < archerChance { e.equip(Weapons.bow) }
        if !args.contains("-passive"), !testMode { e.brain = EnemyBrain(director: crowd) }
        e.rig.scaleFactor = 1.3
        e.rig.facingRight = false
        e.rig.position = CGPoint(x: x, y: y)
        e.rig.zPosition = 300 - y
        enemies.append(e)
        addChild(e.rig)
        let bar = HealthBar(width: 70)
        bar.zPosition = 9000
        bars[ObjectIdentifier(e)] = bar
        addChild(bar)
    }

    /// Impact flash plus a floating damage number.
    private func spawnImpact(at p: CGPoint, damage: CGFloat) {
        let path = CGMutablePath()
        for i in 0..<16 {
            let r: CGFloat = i % 2 == 0 ? 8 + damage * 1.6 : 6 + damage * 0.6
            let a = CGFloat(i) * .pi / 8
            let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        let star = styled(SKShapeNode(path: path), .white, line: 3)
        star.position = p; star.zPosition = 9500
        addChild(star)
        star.run(.sequence([.group([.scale(to: 1.5, duration: 0.14), .fadeOut(withDuration: 0.14)]), .removeFromParent()]))

        let text = "\(Int(damage.rounded()))"
        for (offset, color) in [(CGPoint(x: 2, y: -2), SKColor.black), (CGPoint.zero, SKColor(red: 1, green: 0.9, blue: 0.3, alpha: 1))] {
            let l = SKLabelNode(fontNamed: "Menlo-Bold")
            l.text = text; l.fontSize = 28; l.fontColor = color
            l.position = CGPoint(x: p.x + offset.x, y: p.y + 20 + offset.y); l.zPosition = 9501 + (color == .black ? 0 : 1)
            addChild(l)
            l.run(.sequence([.group([.moveBy(x: 0, y: 55, duration: 0.7), .sequence([.wait(forDuration: 0.35), .fadeOut(withDuration: 0.35)])]),
                             .removeFromParent()]))
        }
    }

    /// `-crowdtest` metrics: closest pair of same-lane enemies, and how many are in melee range of the hero.
    private func logCrowd(now: TimeInterval) {
        guard args.contains("-crowdtest"), now >= nextCrowdLog else { return }
        nextCrowdLog = now + 0.5
        let live = enemies.filter { $0.hittable }
        var gap = CGFloat.infinity
        for i in 0..<live.count { for j in (i + 1)..<live.count {
            let a = live[i].rig.position, b = live[j].rig.position
            if abs(a.y - b.y) < 24 { gap = min(gap, abs(a.x - b.x)) }
        } }
        let engaged = live.filter { abs($0.rig.position.x - hero.rig.position.x) < 140 && abs($0.rig.position.y - hero.rig.position.y) < 30 }.count
        NSLog("CROWD n=%d min_gap=%@ engaged=%d", live.count, gap.isFinite ? String(Int(gap)) : "-", engaged)
    }

    /// Soft push so grounded enemies never stand on top of each other (they ease apart rather than snap).
    private func separateEnemies(dt: CGFloat, bounds: WorldBounds) {
        let live = enemies.filter { $0.hittable && !$0.airborne }
        let spacingX: CGFloat = 70, spacingY: CGFloat = 30
        let k = min(1, dt * 10)
        for i in 0..<live.count {
            for j in (i + 1)..<live.count {
                let a = live[i], b = live[j]
                let dx = a.rig.position.x - b.rig.position.x, dy = a.rig.position.y - b.rig.position.y
                guard abs(dx) < spacingX, abs(dy) < spacingY else { continue }
                let sx: CGFloat = dx == 0 ? (i < j ? 1 : -1) : (dx > 0 ? 1 : -1)
                let sy: CGFloat = dy == 0 ? (i < j ? 1 : -1) : (dy > 0 ? 1 : -1)
                let px = (spacingX - abs(dx)) * 0.5 * k, py = (spacingY - abs(dy)) * 0.5 * k
                a.nudge(dx: sx * px, dy: sy * py, bounds: bounds)
                b.nudge(dx: -sx * px, dy: -sy * py, bounds: bounds)
            }
        }
    }

    // MARK: Camera moments

    /// Anticipation: the camera starts easing in as the hero begins a big move, even if it ends up missing.
    private func windup(_ m: Move) {
        guard fxEnabled, m.emphasis.windup > 0 else { return }
        fx.add(zoom: m.emphasis.windup, attack: 0.1, hold: 0.15, release: m.emphasis.release, at: realNow)
    }

    /// The hero's connecting hits set the size of the moment: the move's own tier, bumped by how many it hit, whether it
    /// finished someone, and whether that was the last enemy standing. Enemy hits never move the camera.
    private func emphasize(_ contacts: [Combat.Contact]) {
        guard fxEnabled else { return }
        let mine = contacts.filter { $0.attacker === hero }
        guard !mine.isEmpty else { return }
        var e = mine.compactMap { $0.move?.emphasis }.max { $0.impact < $1.impact } ?? .none
        let ko = mine.contains { $0.ko }
        if ko {
            let finisher = !enemies.contains { !$0.dead }
            let k = finisher ? Emphasis.massive : Emphasis.kill
            if k.impact > e.impact { e = k }
        }
        guard e.impact > 0 else { return }
        let bonus = min(1.6, 1 + 0.25 * CGFloat(mine.count - 1) + (ko ? 0.2 : 0))
        fx.add(zoom: e.impact * bonus, slow: max(0.2, 1 - (1 - e.slow) * min(1.3, bonus)), attack: 0.05,
               hold: e.hold * Double(bonus), release: e.release, at: realNow)
    }

    private func updateCombat(now: TimeInterval) {
        logCrowd(now: now)
        let contacts = Combat.resolve([hero] + enemies) + Combat.resolveProjectiles(arrows, [hero] + enemies)
        for c in contacts { spawnImpact(at: c.point, damage: c.damage) }
        emphasize(contacts)

        // Health bars float over enemies (hidden at full health); the hero's sits at the bottom of the screen
        for e in enemies {
            guard let bar = bars[ObjectIdentifier(e)] else { continue }
            bar.position = CGPoint(x: e.rig.position.x, y: e.rig.position.y + e.rig.height * 1.3 + 128)
            bar.set(e.healthFraction)
            bar.isHidden = e.dead || e.healthFraction >= 1
        }
        heroBar.set(hero.healthFraction)

        // Loot: some KO'd enemies drop food
        for e in enemies where e.dead && !e.lootDropped {
            e.lootDropped = true
            if !testMode, Double.random(in: 0...1) < foodDropChance {
                pickups.launch(.item(Items.food), from: e.rig.position, height: 40, vx: .random(in: -60...60), vz: 600)
            }
        }

        // Clear out the dead; keep the playground stocked
        enemies.removeAll { e in
            guard e.dead, let since = e.deadSince, now - since > 1.5, !testMode else { return false }
            e.rig.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
            bars.removeValue(forKey: ObjectIdentifier(e))?.removeFromParent()
            return true
        }
        if hero.dead, let since = hero.deadSince, now - since > 2.5 { hero.restore() }
        if !testMode, !args.contains("-passive"), enemies.count < 3, now >= nextSpawn {
            nextSpawn = now + 3
            spawnEnemy(x: min(level.maxX - 100, hero.rig.position.x + size.width * 0.8), y: .random(in: 40...180))
        }
    }

    // MARK: World

    private func buildWorld() {
        // Far hills
        addLayer(factor: 0.2, tileW: 700, z: -3000) {
            let t = SKNode()
            for (x, w, h) in [(180, 620, 240), (520, 520, 180)] as [(CGFloat, CGFloat, CGFloat)] {
                let hill = styled(SKShapeNode(ellipseOf: CGSize(width: w, height: h)),
                                  SKColor(red: 0.45, green: 0.68, blue: 0.62, alpha: 1))
                hill.position = CGPoint(x: x, y: self.groundHeight + 20)
                t.addChild(hill)
            }
            return t
        }
        // Mid pines
        addLayer(factor: 0.5, tileW: 520, z: -2000) {
            let t = SKNode()
            for (x, s) in [(120, 1.0), (390, 1.4)] as [(CGFloat, CGFloat)] {
                let tree = self.pine()
                tree.position = CGPoint(x: x, y: self.groundHeight - 50)   // sunk so vertical parallax never exposes a gap
                tree.setScale(s)
                t.addChild(tree)
            }
            return t
        }
        // Ground
        addLayer(factor: 1.0, tileW: 400, z: -1000) {
            let t = SKNode()
            for (i, c) in [SKColor(red: 0.20, green: 0.50, blue: 0.48, alpha: 1),
                           SKColor(red: 0.23, green: 0.55, blue: 0.52, alpha: 1)].enumerated() {
                // Extends well below the lane so there's no gap when the camera follows the hero down
                let r = SKShapeNode(rect: CGRect(x: CGFloat(i) * 200, y: -600, width: 200, height: self.groundHeight + 600))
                r.fillColor = c
                r.strokeColor = .clear
                t.addChild(r)
            }
            let edge = SKShapeNode(rect: CGRect(x: -4, y: self.groundHeight - 2, width: 408, height: 4))
            edge.fillColor = ink
            edge.strokeColor = .clear
            t.addChild(edge)
            return t
        }
    }

    private func pine() -> SKNode {
        let tree = SKNode()
        let trunk = styled(SKShapeNode(rect: CGRect(x: -12, y: 0, width: 24, height: 60)),
                           SKColor(red: 0.42, green: 0.28, blue: 0.2, alpha: 1))
        tree.addChild(trunk)
        for (i, w) in [(0, 150), (1, 120), (2, 85)] as [(Int, CGFloat)] {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -w / 2, y: 0))
            p.addLine(to: CGPoint(x: w / 2, y: 0))
            p.addLine(to: CGPoint(x: 0, y: 110))
            p.closeSubpath()
            let layer = styled(SKShapeNode(path: p), SKColor(red: 0.16, green: 0.40, blue: 0.34, alpha: 1))
            layer.position = CGPoint(x: 0, y: 40 + CGFloat(i) * 55)
            tree.addChild(layer)
        }
        return tree
    }

    /// Tiles must be identical (period = tileW) so they loop seamlessly.
    /// fx / fy: 1 = moves with the world (foreground), 0 = pinned to the screen (infinitely far).
    /// fy defaults to fx; set it separately for levels that scroll mostly vertically (e.g. a mountain climb).
    private func addLayer(factor fx: CGFloat, factorY fy: CGFloat? = nil, tileW: CGFloat, z: CGFloat,
                          tile: () -> SKNode) {
        let layer = SKNode()
        layer.zPosition = z
        for i in 0..<(Int(ceil(size.width / tileW)) + 2) {
            let t = tile()
            t.position.x = CGFloat(i) * tileW
            layer.addChild(t)
        }
        addChild(layer)
        layers.append((layer, fx, fy ?? fx, tileW))
    }

    // MARK: Input

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        setupKeyboard()
        if ProcessInfo.processInfo.arguments.contains("-demo") { runDemo() }
        if ProcessInfo.processInfo.arguments.contains("-enemylog") {
            for (i, e) in enemies.enumerated() { e.logPrefix = "\(e.name)#\(i): " }
        }
        if ProcessInfo.processInfo.arguments.contains("-hittest") { runHitTest() }
        if ProcessInfo.processInfo.arguments.contains("-divetest") { runDiveTest() }
        if ProcessInfo.processInfo.arguments.contains("-itemtest") { runItemTest() }
        if ProcessInfo.processInfo.arguments.contains("-bowtest") { runBowTest() }
        if ProcessInfo.processInfo.arguments.contains("-fxtest") { runFxTest() }
        if ProcessInfo.processInfo.arguments.contains("-crowdtest") { hero.stats.maxHealth = 1_000_000; hero.restore() }
        if ProcessInfo.processInfo.arguments.contains("-dump") { dumpTree(hero.rig) }
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-pose"), i + 1 < args.count, let a = CharacterAnimation(rawValue: args[i + 1]) {
            run(.sequence([.wait(forDuration: 1), .run { [weak self] in   // slow-mo, hero and skeletons side by side
                guard let self else { return }
                if a == .shoot { ([self.hero] + self.enemies).forEach { $0.equip(Weapons.bow) } }
                for r in ([self.hero] + self.enemies).map(\.rig) {
                    if a == .slam || a == .uppercut { r.height = 150 }
                    r.speed = 0.08; r.play(a)
                }
            }]))
        }
    }

    /// Debug: print every descendant's transform and shape so a refactor can be diffed against a baseline.
    private func dumpTree(_ n: SKNode, depth: Int = 0) {
        for c in n.children {
            var line = String(repeating: " ", count: depth) + "\(type(of: c))"
            line += String(format: " p(%.1f,%.1f) z%.1f r%.3f s(%.2f,%.2f)", c.position.x, c.position.y, c.zPosition, c.zRotation, c.xScale, c.yScale)
            if let sh = c as? SKShapeNode {
                let b = sh.path?.boundingBox ?? .zero
                line += String(format: " box(%.1f,%.1f,%.1f,%.1f) lw%.1f glow%.1f ", b.minX, b.minY, b.width, b.height, sh.lineWidth, sh.glowWidth)
                line += "fill=\(sh.fillColor.cgColor.components ?? []) stroke=\(sh.strokeColor.cgColor.components ?? [])"
            }
            NSLog("DUMP %@", line)
            dumpTree(c, depth: depth + 1)
        }
    }

    /// Hardware keyboard (Mac keyboard in the simulator). No view focus needed.
    /// WASD = move (Shift = run), arrow keys = swipes, Space = tap.
    private func setupKeyboard() {
        func attach(_ kb: GCKeyboard) {
            kb.keyboardInput?.keyChangedHandler = { [weak self] pad, _, code, down in
                guard let self else { return }
                let shift = (pad.button(forKeyCode: .leftShift)?.isPressed ?? false)
                    || (pad.button(forKeyCode: .rightShift)?.isPressed ?? false)
                let letters: [GCKeyCode: Character] = [.keyW: "w", .keyA: "a", .keyS: "s", .keyD: "d"]
                if let ch = letters[code] {
                    if down { self.input.keyDown(ch, run: shift) } else { self.input.keyUp(ch) }
                    return
                }
                guard down else { return }
                switch code {
                case .upArrow:    self.input.fire(.swipe(.up))
                case .downArrow:  self.input.fire(.swipe(.down))
                case .leftArrow:  self.input.fire(.swipe(.left))
                case .rightArrow: self.input.fire(.swipe(.right))
                case .spacebar:   self.input.fire(.tap)
                default: break
                }
            }
        }
        if let kb = GCKeyboard.coalesced { attach(kb) }
        NotificationCenter.default.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { n in
            if let kb = n.object as? GCKeyboard { attach(kb) }
        }
    }

    /// Launch with `-fxtest`: one move per case; reports the peak zoom / slowest time scale / seconds active for each.
    private func runFxTest() {
        guard enemies.count >= 2 else { return }
        let e = enemies[0], e2 = enemies[1]
        func fire(_ g: Gesture) -> SKAction { .run { [weak self] in self?.hero.handle(g) } }
        func w(_ t: Double) -> SKAction { .wait(forDuration: t) }
        func act(_ f: @escaping (Fighter, Fighter) -> Void) -> SKAction { .run { [weak self] in if let self { f(self.hero, e) } } }
        func reset(_ title: String, gap: CGFloat = 90, second: Bool = false, lastOne: Bool = false) -> SKAction { .run { [weak self] in
            guard let self else { return }
            NSLog("FXTEST --- %@", title)
            self.fxPeakZoom = 0; self.fxMinScale = 1; self.fxActive = 0
            self.pickups.clear(); self.arrows.clear()
            self.hero.restore(); self.hero.rig.position = CGPoint(x: 667, y: 120); self.hero.rig.facingRight = true
            for (i, f) in self.enemies.enumerated() { f.restore(); f.rig.position = CGPoint(x: 1900 + CGFloat(i) * 150, y: 120); f.rig.facingRight = false }
            e.rig.position = CGPoint(x: 667 + gap, y: 120)
            if second { e2.rig.position = CGPoint(x: 667 + gap + 30, y: 126) }
            if lastOne { for f in self.enemies where f !== e { f.debugSetHealth(0) } }
        } }
        func report() -> SKAction { .run { [weak self] in
            guard let self else { return }
            NSLog("FXTEST result peak_zoom=%.3f min_timescale=%.2f active=%.2fs", self.fxPeakZoom, self.fxMinScale, self.fxActive)
        } }
        func sprint(_ on: Bool) -> SKAction { .run { [weak self] in if on { self?.input.keyDown("d", run: true) } else { self?.input.keyUp("d") } } }
        run(.sequence([
            w(1),
            reset("A jab (expect none)"), fire(.tap), w(2.2), report(),
            reset("B heavy attack / hook (light)"), fire(.swipe(.right)), w(2.2), report(),
            reset("C power dash (medium)", gap: 330), sprint(true), w(0.7), fire(.swipe(.right)), w(0.5), sprint(false), w(2.2), report(),
            reset("D hook into uppercut (heavy)"), fire(.swipe(.right)), w(0.3), fire(.swipe(.up)), w(3), report(),
            reset("E ground smash alone (heavy)", gap: 150), act { h, _ in h.debugPerform(MoveTable.groundSmash) }, w(2.5), report(),
            reset("F air slam dive + landing shockwave (massive)", gap: 60), fire(.swipe(.up)), w(0.5), fire(.swipe(.down)), w(3), report(),
            reset("G uppercut whiffs (windup only)", gap: 400), fire(.swipe(.right)), w(0.3), fire(.swipe(.up)), w(3), report(),
            reset("H a KO with other enemies left (kill)"), act { _, e in e.debugSetHealth(5) }, fire(.tap), w(2.2), report(),
            reset("I the LAST enemy falls (massive)", lastOne: true), act { _, e in e.debugSetHealth(5) }, fire(.tap), w(2.5), report(),
            reset("D2 uppercut alone, one enemy in range"), act { h, _ in h.debugPerform(MoveTable.chain(from: "heavy attack", .up)!) }, w(3), report(),
            reset("J same uppercut, TWO enemies in range (expect ~25% bigger than D2)", second: true),
            act { h, _ in h.debugPerform(MoveTable.chain(from: "heavy attack", .up)!) }, w(3), report(),
            reset("K ENEMY uppercuts the hero (expect none)"), act { _, e in e.debugPerform(MoveTable.chain(from: "heavy attack", .up)!) }, w(2.5), report()
        ]))
    }

    /// Launch with `-bowtest`: shooting, ammo, arrow hits, dodging, interrupts, quiver and swapping. Prints `BOWTEST` lines.
    private func runBowTest() {
        guard let e = enemies.first else { return }
        func fire(_ g: Gesture) -> SKAction { .run { [weak self] in self?.hero.handle(g) } }
        func w(_ t: Double) -> SKAction { .wait(forDuration: t) }
        func act(_ f: @escaping (Fighter, Fighter) -> Void) -> SKAction { .run { [weak self] in if let self { f(self.hero, e) } } }
        func report(_ label: String) -> SKAction { .run { [weak self] in
            guard let self else { return }
            let ground = self.pickups.pickups.map { "\($0.label)@\(Int($0.position.x))" }.joined(separator: ",")
            NSLog("BOWTEST %@ | hero hp=%ld weapon=%@ ammo=%@ | enemy hp=%ld weapon=%@ ammo=%@ | arrows in flight=%ld | ground=[%@]", label,
                  Int(self.hero.health), self.hero.weapon?.name ?? "none", self.hero.ammo.map(String.init) ?? "-",
                  Int(e.health), e.weapon?.name ?? "none", e.ammo.map(String.init) ?? "-", self.arrows.arrows.count, ground)
        } }
        func reset(_ title: String, gap: CGFloat = 400, dy: CGFloat = 0, bow: Bool = true) -> SKAction { .run { [weak self] in
            guard let self else { return }
            NSLog("BOWTEST --- %@", title)
            self.pickups.clear(); self.arrows.clear()
            self.hero.restore(); self.hero.rig.position = CGPoint(x: 667, y: 120); self.hero.rig.facingRight = true
            if bow { self.hero.equip(Weapons.bow) }
            e.restore(); e.rig.position = CGPoint(x: 667 + gap, y: 120 + dy); e.rig.facingRight = false
        } }
        let back: Gesture = .swipe(.left)       // hero faces right, so left = back
        var steps: [SKAction] = [
            w(1),
            reset("A back swipe shoots, enemy takes an arrow"), fire(back), w(0.3), report("mid-draw"), w(1.2), report("expect ammo 7, enemy hp 35.8"),
            reset("B arrow misses in another lane", dy: 80), fire(back), w(1.5), report("expect ammo 7, enemy hp 40"),
            reset("C jump over the arrow", gap: 300),
            act { _, e in e.equip(Weapons.bow); e.debugSetAmmo(3); e.rig.facingRight = false },
            act { _, e in e.handle(.swipe(.right)) }, fire(.swipe(.up)), w(1.4), report("expect hero hp 100 (arrow passed under)"),
            reset("D out of arrows", bow: true), act { h, _ in h.debugSetAmmo(0) }, fire(back), w(0.8), report("expect no shot, ammo 0"),
            reset("E melee still works with bow", gap: 90), fire(.tap), w(1.0), report("expect jab 6*1.0 = 6 dmg"),
            reset("F weak weapon moves", gap: 90), fire(.swipe(.right)), w(1.2), report("expect hook 12*0.6 = 7.2 dmg"),
            reset("G quiver refills"), act { h, _ in h.debugSetAmmo(2) }, .run { [weak self] in self?.pickups.place(.item(Items.quiver), at: CGPoint(x: 697, y: 120)) },
            fire(.swipe(.down)), w(0.9), report("expect ammo 8, quiver gone"),
            reset("H quiver ignored without a bow", bow: false), .run { [weak self] in self?.pickups.place(.item(Items.quiver), at: CGPoint(x: 697, y: 120)) },
            fire(.swipe(.down)), w(0.9), report("expect quiver stays"),
            reset("I full quiver is not wasted"), act { h, _ in h.debugSetAmmo(12) }, .run { [weak self] in self?.pickups.place(.item(Items.quiver), at: CGPoint(x: 697, y: 120)) },
            fire(.swipe(.down)), w(0.9), report("expect quiver stays, ammo 8"),
            reset("J hit mid-draw cancels the shot", gap: 90), fire(back), w(0.05),
            act { _, e in e.debugPerform(MoveTable.move(.grounded, .tap)!) }, w(1.2), report("expect ammo 8 (no arrow spent)"),
            reset("K swap bow for sword keeps arrows on the bow"), act { h, _ in h.debugSetAmmo(5) },
            .run { [weak self] in self?.pickups.place(.weapon(Weapons.sword), at: CGPoint(x: 697, y: 120)) },
            fire(.swipe(.down)), w(1.0), report("expect sword, bow on ground"),
            .run { [weak self] in
                if let bow = self?.pickups.pickups.first(where: { $0.label == "bow" }) {
                    if case .weapon(let wp) = bow.kind { NSLog("BOWTEST dropped bow carries ammo=%@", wp.ammo.map(String.init) ?? "-") }
                }
            },
            reset("L enemy archer kites a hero who does not move"),
            act { _, e in e.equip(Weapons.bow); e.brain = EnemyBrain(director: CrowdDirector()); e.rig.position.x = 667 + 300 }, w(10),
            report("archer after 10s")
        ]

        /// The hero walks (or runs) straight at an archer without attacking; logs the gap twice a second.
        func approach(_ title: String, tag: String, running: Bool, samples: Int) {
            steps.append(reset(title, gap: 450))
            steps.append(act { _, e in e.equip(Weapons.bow); e.rig.position.x = 667 + 450 })
            steps.append(.run { [weak self] in self?.input.keyDown("d", run: running) })
            for _ in 0..<samples {
                steps.append(w(0.5))
                steps.append(.run { [weak self] in
                    guard let self else { return }
                    NSLog("BOWTEST %@ gap=%.0f archer_hp=%.0f archer_ammo=%@ hero_hp=%.0f", tag, e.rig.position.x - self.hero.rig.position.x,
                          e.health, e.ammo.map(String.init) ?? "-", self.hero.health)
                })
            }
            steps.append(.run { [weak self] in self?.input.keyUp("d") })
        }
        approach("M hero walks at an archer", tag: "M", running: false, samples: 14)
        approach("N hero RUNS at an archer", tag: "N", running: true, samples: 10)
        run(.sequence(steps))
    }

    /// Launch with `-itemtest`: pickups, swaps, disarming and bare-handed damage. Prints `ITEMTEST` state lines.
    private func runItemTest() {
        guard let e = enemies.first else { return }
        func fire(_ g: Gesture) -> SKAction { .run { [weak self] in self?.hero.handle(g) } }
        func w(_ t: Double) -> SKAction { .wait(forDuration: t) }
        func act(_ f: @escaping (Fighter, Fighter) -> Void) -> SKAction { .run { [weak self] in if let self { f(self.hero, e) } } }
        func place(_ k: PickupKind, dx: CGFloat) -> SKAction { .run { [weak self] in self?.pickups.place(k, at: CGPoint(x: 667 + dx, y: 120)) } }
        func report(_ label: String) -> SKAction { .run { [weak self] in
            guard let self else { return }
            let ground = self.pickups.pickups.map { "\($0.label)@\(Int($0.position.x))" + ($0.landed ? "" : "(air)") }.joined(separator: ",")
            NSLog("ITEMTEST %@ | hero hp=%ld weapon=%@ | enemy hp=%ld weapon=%@ | ground=[%@]", label, Int(self.hero.health),
                  self.hero.weapon?.name ?? "none", Int(e.health), e.weapon?.name ?? "none", ground)
        } }
        func reset(_ title: String, gap: CGFloat = 400) -> SKAction { .run { [weak self] in
            guard let self else { return }
            NSLog("ITEMTEST --- %@", title)
            self.pickups.clear()
            self.hero.restore(); self.hero.rig.position = CGPoint(x: 667, y: 120); self.hero.rig.facingRight = true
            e.restore(); e.rig.position = CGPoint(x: 667 + gap, y: 120); e.rig.facingRight = false
        } }
        let uppercut = MoveTable.chain(from: "heavy attack", .up)!
        let jab = MoveTable.move(.grounded, .tap)!
        let pick = MoveTable.move(.grounded, .down)!
        run(.sequence([
            w(1),
            reset("A heal when hurt"), act { h, _ in h.debugSetHealth(50) }, place(.item(Items.food), dx: 30), fire(.swipe(.down)), w(0.9),
            report("expect hp 75, apple gone"),
            reset("B food at full health stays"), place(.item(Items.food), dx: 30), fire(.swipe(.down)), w(0.9),
            report("expect hp 100, apple stays"),
            reset("C swap weapon"), place(.weapon(Weapons.axe), dx: 30), fire(.swipe(.down)), w(0.35),
            report("mid-swap"), w(1.0), report("expect weapon axe, sword on ground"),
            reset("D bare-handed pickup"), act { h, _ in h.equip(nil) }, place(.weapon(Weapons.sword), dx: 30), fire(.swipe(.down)), w(0.9),
            report("expect weapon sword"),
            reset("E strong hit disarms", gap: 70), act { _, e in e.debugPerform(uppercut) }, w(0.5),
            report("mid-flip"), w(1.4), report("expect hero weapon none, sword on ground"),
            reset("F jab keeps weapon", gap: 70), act { _, e in e.debugPerform(jab) }, w(1.0), report("expect weapon sword"),
            reset("G armed heavy attack", gap: 90), fire(.swipe(.right)), w(1.2), report("expect enemy hp 28 (12 dmg)"),
            reset("H bare-handed heavy attack", gap: 90), act { h, _ in h.equip(nil) }, fire(.swipe(.right)), w(1.2),
            report("expect enemy hp 31.6 (8.4 dmg)"),
            reset("I hero with axe", gap: 90), act { h, _ in h.equip(Weapons.axe) }, fire(.swipe(.right)), w(1.2),
            report("expect enemy hp 24.4 (15.6 dmg)"),
            reset("J enemies skip items"), place(.item(Items.food), dx: 400), act { _, e in e.debugPerform(pick) }, w(1.0),
            report("expect apple stays")
        ]))
    }

    /// Launch with `-divetest`: jump, hang, dive onto a standing skeleton at several offsets. Logs every hit with the move that caused it.
    private func runDiveTest() {
        guard let e = enemies.first else { return }
        func fire(_ g: Gesture) -> SKAction { .run { [weak self] in self?.hero.handle(g) } }
        func w(_ t: Double) -> SKAction { .wait(forDuration: t) }
        func reset(_ title: String, gap: CGFloat, dy: CGFloat = 0) -> SKAction { .run { [weak self] in
            guard let self else { return }
            NSLog("HITTEST --- %@", title)
            self.hero.restore(); self.hero.rig.position = CGPoint(x: 667, y: 120); self.hero.rig.facingRight = true
            e.restore(); e.rig.position = CGPoint(x: 667 + gap, y: 120 + dy); e.rig.facingRight = false
        } }
        var steps: [SKAction] = [w(1)]
        for (gap, dy) in [(0, 0), (40, 0), (80, 0), (120, 0), (160, 0), (60, 30), (60, 60), (-60, 0)] as [(CGFloat, CGFloat)] {
            steps += [reset("dive onto skeleton: gap \(Int(gap)) lane \(Int(dy))", gap: gap, dy: dy),
                      fire(.swipe(.up)), w(0.5), fire(.swipe(.down)), w(1.6)]
        }
        run(.sequence(steps))
    }

    /// Launch with `-hittest`: one passive skeleton in front of the hero; each case resets both and fires gestures.
    /// Results appear as `HIT ...` lines (damage, remaining hp, LAUNCH / KO).
    private func runHitTest() {
        guard let e = enemies.first else { return }
        func fire(_ g: Gesture) -> SKAction { .run { [weak self] in self?.hero.handle(g) } }
        func w(_ t: Double) -> SKAction { .wait(forDuration: t) }
        func reset(_ title: String, gap: CGFloat = 90) -> SKAction { .run { [weak self] in
            guard let self else { return }
            NSLog("HITTEST --- %@", title)
            self.hero.restore(); self.hero.rig.position = CGPoint(x: 667, y: 120); self.hero.rig.facingRight = true
            e.restore(); e.rig.position = CGPoint(x: 667 + gap, y: 120); e.rig.facingRight = false
        } }
        run(.sequence([
            w(1),
            reset("jab"), fire(.tap), w(1.5),
            reset("hook"), fire(.swipe(.right)), w(1.5),
            reset("jab jab"), fire(.tap), w(0.2), fire(.tap), w(1.5),
            reset("hook uppercut"), fire(.swipe(.right)), w(0.3), fire(.swipe(.up)), w(2.0),
            reset("juggle: hook uppercut slam"), fire(.swipe(.right)), w(0.3), fire(.swipe(.up)), w(0.5), fire(.swipe(.down)), w(2.2),
            reset("out of reach", gap: 400), fire(.tap), w(1.2),
            reset("power dash", gap: 330), .run { [weak self] in self?.input.keyDown("d", run: true) }, w(0.7),
            fire(.swipe(.right)), w(0.5), .run { [weak self] in self?.input.keyUp("d") }, w(1.5),
            reset("dash attack then smash", gap: 330), .run { [weak self] in self?.input.keyDown("d", run: true) }, w(0.7),
            fire(.tap), w(0.25), fire(.swipe(.down)), w(0.5), .run { [weak self] in self?.input.keyUp("d") }, w(1.5),
            reset("smash alone, standing, gap 70", gap: 70), .run { [weak self] in self?.hero.debugPerform(MoveTable.groundSmash) }, w(1.2),
            reset("smash alone, standing, gap 150", gap: 150), .run { [weak self] in self?.hero.debugPerform(MoveTable.groundSmash) }, w(1.2),
            reset("smash alone, standing, gap 230", gap: 230), .run { [weak self] in self?.hero.debugPerform(MoveTable.groundSmash) }, w(1.2),
            reset("smash alone, standing, gap 300", gap: 300), .run { [weak self] in self?.hero.debugPerform(MoveTable.groundSmash) }, w(1.2),
            reset("smash alone, standing, gap 380", gap: 380), .run { [weak self] in self?.hero.debugPerform(MoveTable.groundSmash) }, w(1.2),
            reset("smash alone, running, gap 330", gap: 330), .run { [weak self] in self?.input.keyDown("d", run: true) }, w(0.7), .run { [weak self] in self?.hero.debugPerform(MoveTable.groundSmash) }, w(0.6), .run { [weak self] in self?.input.keyUp("d") }, w(1.2),
        ]))
    }

    /// Launch with `-demo` to play a scripted input sequence (no touch needed). Exercises every move-table context.
    private func runDemo() {
        func fire(_ g: Gesture) -> SKAction { .run { [weak self] in self?.input.fire(g) } }
        func hold(run: Bool) -> SKAction { .run { [weak self] in self?.input.keyDown("d", run: run) } }
        let release = SKAction.run { [weak self] in self?.input.keyUp("d") }
        run(.sequence([
            .wait(forDuration: 1),
            fire(.tap), .wait(forDuration: 0.8),                       // grounded tap
            fire(.swipe(.right)), .wait(forDuration: 0.8),             // grounded forward
            fire(.swipe(.left)), .wait(forDuration: 0.5),              // grounded back (open: nothing)
            fire(.swipe(.down)), .wait(forDuration: 0.5),              // grounded down
            fire(.swipe(.up)), .wait(forDuration: 1.0),                // small jump
            hold(run: true), .wait(forDuration: 1.8),                  // build up to a full run
            fire(.tap), .wait(forDuration: 0.7),                       // running tap
            fire(.swipe(.right)), .wait(forDuration: 0.7),             // running forward
            fire(.swipe(.up)), .wait(forDuration: 0.25),               // big jump
            fire(.swipe(.down)), .wait(forDuration: 1.0),              // air slam
            hold(run: true), .wait(forDuration: 1.8),
            fire(.swipe(.left)), .wait(forDuration: 0.6),              // running back: skid
            release, .wait(forDuration: 1.2),                          // stand still before the combo tests
            fire(.tap), .wait(forDuration: 0.2),                       // COMBO: punch ...
            fire(.tap), .wait(forDuration: 0.2),                       // ... punch 2 ...
            fire(.swipe(.up)), .wait(forDuration: 0.3),                // ... uppercut ...
            fire(.swipe(.down)), .wait(forDuration: 1.2),              // ... air slam (airborne)
            fire(.tap), .wait(forDuration: 0.05),                      // EARLY: arrives before the cancel point ...
            fire(.tap), .wait(forDuration: 1.0),                       // ... buffered, fires as punch 2
            fire(.tap), .wait(forDuration: 0.9),                       // EXPIRED: window closes before the next tap ...
            fire(.tap), .wait(forDuration: 1.0),                       // ... so this is a fresh punch, not punch 2
            hold(run: true), .wait(forDuration: 1.8),
            fire(.swipe(.right)), .wait(forDuration: 0.2),             // COMBO: power dash ...
            fire(.swipe(.down)), .wait(forDuration: 1.2),              // ... ground smash
            fire(.swipe(.right)), .wait(forDuration: 0.2),             // running power dash ...
            fire(.swipe(.up)), .wait(forDuration: 1.2),                // ... uppercut (new)
            release, .wait(forDuration: 1.2),
            fire(.swipe(.right)), .wait(forDuration: 0.2),             // standing heavy attack ...
            fire(.swipe(.up)), .wait(forDuration: 1.2),                // ... uppercut (new)
            release, .wait(forDuration: 1.2),
            fire(.swipe(.up)), .wait(forDuration: 0.3),                // jump, into the hang
            fire(.swipe(.down)), .wait(forDuration: 0.3),              // air slam; lands during this wait
            fire(.swipe(.right)), .wait(forDuration: 1.2),             // forward in the cooldown -> power dash
            fire(.swipe(.up)), .wait(forDuration: 0.3),
            fire(.swipe(.down)), .wait(forDuration: 0.03),             // slam ...
            fire(.swipe(.right)), .wait(forDuration: 1.2),             // ... forward mashed mid-dive: buffered, chains on landing
            release, .wait(forDuration: 1)
        ]))
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { if let v = view { input.began(touches, in: v) } }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { if let v = view { input.moved(touches, in: v) } }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { if let v = view { input.ended(touches, in: v) } }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { input.cancelled(touches) }

    // MARK: Debug overlay

    /// Half the visible height in scene units. aspectFill crops the scene on wider screens, so size.height overshoots.
    private var visibleHalfHeight: CGFloat {
        guard let v = view, v.bounds.width > 0, v.bounds.height > 0 else { return size.height / 2 }
        let scale = max(v.bounds.width / size.width, v.bounds.height / size.height)
        return v.bounds.height / scale / 2
    }

    private func updateDebug() {
        debugLayer.removeAllChildren()
        debugLabel.position = CGPoint(x: 0, y: visibleHalfHeight - 56)
        heroBar.position = CGPoint(x: 0, y: -visibleHalfHeight + 28)
        for t in input.debugTouches {
            let o = cam.convert(convertPoint(fromView: t.origin), from: self)
            let c = cam.convert(convertPoint(fromView: t.current), from: self)
            let color: SKColor = t.isLeft ? .cyan : .orange
            let ring = SKShapeNode(circleOfRadius: 40)
            ring.strokeColor = color; ring.lineWidth = 3; ring.fillColor = .clear; ring.alpha = 0.6
            ring.position = o
            let dot = SKShapeNode(circleOfRadius: 16)
            dot.fillColor = color; dot.strokeColor = .clear; dot.alpha = 0.7
            dot.position = c
            debugLayer.addChild(ring); debugLayer.addChild(dot)
        }
        debugLabel.text = "\(hero.debugState)  speed \(Int(hero.velocity))  h \(Int(hero.rig.height))  hp \(Int(hero.health))  wpn \(hero.weapon?.name ?? "none")\(hero.ammo.map { " x\($0)" } ?? "")  |  last: \(hero.lastGesture)"
    }

    // MARK: Loop

    override func update(_ currentTime: TimeInterval) {
        let realDT = lastTime == 0 ? 0 : min(currentTime - lastTime, 1.0 / 20)
        lastTime = currentTime
        realNow = currentTime
        let sample: (zoom: CGFloat, slow: CGFloat) = fxEnabled ? fx.sample(at: currentTime) : (0, 1)
        speed = sample.slow                 // SKScene.speed also slows every SKAction: animations, effects, scripted tests
        let dt = realDT * Double(sample.slow)
        gameTime += dt
        let now = gameTime
        if args.contains("-fxtest") {
            fxPeakZoom = max(fxPeakZoom, sample.zoom); fxMinScale = min(fxMinScale, sample.slow)
            if sample.zoom > 0.001 || sample.slow < 0.999 { fxActive += realDT; NSLog("FXSAMPLE zoom=%.3f ts=%.2f", sample.zoom, sample.slow) }
        }

        let bounds = WorldBounds(minX: level.minX + level.heroInset, maxX: level.maxX - level.heroInset,
                                 minY: laneMinY, maxY: groundHeight - 30)
        crowd.members = enemies
        hero.step(now: now, dt: dt, bounds: bounds, foes: enemies)
        for e in enemies { e.step(now: now, dt: dt, bounds: bounds, foes: [hero]) }
        separateEnemies(dt: CGFloat(dt), bounds: bounds)
        pickups.step(dt: CGFloat(dt), minX: level.minX + 20, maxX: level.maxX - 20)
        arrows.step(dt: CGFloat(dt), minX: level.minX, maxX: level.maxX)
        updateCombat(now: now)
        updateDebug()

        // Camera follows the hero in both axes (vertical is damped so the horizon shifts, not snaps).
        // Moments zoom it in; while zoomed it also drifts toward the hero's chest so he stays the focus.
        let follow = min(1, CGFloat(realDT) * 6)
        let camScale = 1 - sample.zoom
        cam.setScale(camScale)
        let focus = min(1, sample.zoom / 0.05)
        var camTargetY = baseCamY + (hero.rig.position.y - laneStartY) * verticalFollow
        let chest = hero.rig.position.y + (hero.rig.height + 60) * hero.rig.scaleFactor
        camTargetY += (chest - camTargetY) * focus * 0.5
        let halfW = size.width / 2 * camScale
        let camMinX = level.minX + halfW, camMaxX = max(camMinX, level.maxX - halfW)
        let camTargetX = min(max(hero.rig.position.x, camMinX), camMaxX)
        cam.position.x += (camTargetX - cam.position.x) * follow
        cam.position.y += (camTargetY - cam.position.y) * follow

        // Parallax: horizontal layers tile and wrap; vertical offset is a simple scaled shift
        for l in layers {
            var m = (cam.position.x * l.fx).truncatingRemainder(dividingBy: l.tileW)
            if m < 0 { m += l.tileW }
            l.node.position.x = cam.position.x - size.width / 2 - m
            l.node.position.y = (cam.position.y - baseCamY) * (1 - l.fy)
        }
    }
}

struct GameView: View {
    let onBack: () -> Void
    @State private var scene = GameScene()

    var body: some View {
        SpriteView(scene: scene, debugOptions: [.showsFPS, .showsNodeCount])
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) {
                Button(action: onBack) { Label("Menu", systemImage: "chevron.left") }
                    .buttonStyle(.borderedProminent)
                    .padding()
            }
    }
}
