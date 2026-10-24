import SpriteKit

/// What a brain wants the body to do this frame. The player's thumb and an AI both produce one of these.
struct MoveIntent {
    var direction = CGVector.zero    // unit vector, +y up
    var intensity: CGFloat = 0       // 0...1, how hard they push (walk -> run)
    var dragSpeed: CGFloat = 0       // pt/s of the thumb; faster flicks accelerate quicker
    var facing: Bool? = nil          // AI only: face this way (true = right) regardless of where it walks (backpedalling)
}

/// Where a fighter may stand (already inset from the world edges by the level).
struct WorldBounds {
    var minX: CGFloat, maxX: CGFloat
    var minY: CGFloat, maxY: CGFloat
}

/// Per-character numbers. A brute is a Fighter with different stats.
struct FighterStats {
    var runSpeed: CGFloat = 520
    var baseAccel: CGFloat = 1500       // slow drag: ~0.35s to full speed
    var dragAccelGain: CGFloat = 1.2    // + thumb speed * gain: a fast flick: ~0.2s
    var steerDecel: CGFloat = 2400      // pushing less than current speed
    var stopDecel: CGFloat = 3600       // input released: quick stop
    var skidDecel: CGFloat = 1800       // input released at full run: small skid
    var brakeDecel: CGFloat = 3600      // forced stop (skid move / planted landing)
    var airDecel: CGFloat = 250         // momentum carries through the air
    var gravity: CGFloat = 2400         // only the air-slam dive uses physics; jumps follow `JumpTuning`
    var slamVZ: CGFloat = 1500
    var maxHealth: CGFloat = 100
    var damageScale: CGFloat = 1        // multiplies the damage this fighter deals
    var attackSpeed: CGFloat = 1        // grounded attacks run this much faster (Frenzy buff); jumps and air moves are unaffected
    var size: CGFloat = 1               // body scale for combat: multiplies hit reach and how far its own body reaches into hits
    var ignoresPickups = false          // never grabs anything, weapons included (too big to use them)
    var innateMoves: [MoveKey: Move] = [:]   // moves it has without a weapon (a demon's fire); a held weapon still overrides
    var flies = false                   // sets its own height (a bat): hovers out of reach of ground attacks, sinks when hurt
    var unlaunchable = false            // never leaves the ground: launchers and big hits only rock it back

    /// Fast, fragile and airborne: hovers out of reach of ground attacks, dives to bite.
    static var bat: FighterStats {
        var s = FighterStats()
        s.runSpeed = 470; s.baseAccel = 1400; s.maxHealth = 18; s.damageScale = 1
        s.flies = true; s.ignoresPickups = true
        return s
    }

    /// Flying boss: hovers well above ground reach, shrugs off hits without dropping, lands only when it chooses to.
    static var batKing: FighterStats {
        var s = FighterStats()
        s.runSpeed = 380; s.baseAccel = 1000; s.maxHealth = 260; s.damageScale = 1
        s.size = 2; s.flies = true; s.unlaunchable = true; s.ignoresPickups = true
        return s
    }

    /// The Demon: a giant's bulk, a bat's wings and a wizard's blink. Hits don't knock it back or drop it from the air.
    static var demon: FighterStats {
        var s = FighterStats()
        s.runSpeed = 250; s.baseAccel = 800; s.maxHealth = 520; s.damageScale = 1.4
        s.size = 1.6; s.flies = true; s.unlaunchable = true; s.ignoresPickups = true
        s.innateMoves = Weapons.fireBreathMoves
        return s
    }

    /// Gravewood's boss: frail on foot, shielded by a ward, and rocks back instead of flying.
    static var necromancer: FighterStats {
        var s = FighterStats()
        s.runSpeed = 240; s.baseAccel = 700; s.maxHealth = 420; s.damageScale = 1
        s.unlaunchable = true; s.ignoresPickups = true
        return s
    }

    /// Huge, slow, hits hard, and can't be launched.
    static var giantSkeleton: FighterStats {
        var s = FighterStats()
        s.runSpeed = 170; s.baseAccel = 500; s.maxHealth = 400; s.damageScale = 1.8
        s.size = 2; s.unlaunchable = true; s.ignoresPickups = true
        return s
    }

    /// A ghost with a lantern: slow, can't be launched, and only hurt while it stands inside the hero's light.
    static var wraith: FighterStats {
        var s = FighterStats()
        s.runSpeed = 240; s.baseAccel = 800; s.maxHealth = 280; s.damageScale = 1
        s.unlaunchable = true; s.ignoresPickups = true
        return s
    }

    /// Gravewood-sized and slow, with a hammer: a boss that makes the floor dangerous. Immune to lava.
    static var forgeKing: FighterStats {
        var s = FighterStats()
        s.runSpeed = 190; s.baseAccel = 600; s.maxHealth = 380; s.damageScale = 1.5
        s.size = 1.4; s.unlaunchable = true; s.ignoresPickups = true
        return s
    }

    /// A frost wizard: frail, quick on its feet, never melees.
    static var wizard: FighterStats {
        var s = FighterStats()
        s.runSpeed = 280; s.baseAccel = 800; s.maxHealth = 70; s.damageScale = 1
        s.ignoresPickups = true
        return s
    }

    /// The Frost Archmage: a giant wizard with a boss's health.
    static var archmage: FighterStats {
        var s = FighterStats()
        s.runSpeed = 210; s.baseAccel = 600; s.maxHealth = 700; s.damageScale = 1.2
        s.size = 2; s.unlaunchable = true; s.ignoresPickups = true
        return s
    }

    /// Slower and lighter than the hero.
    static var skeleton: FighterStats {
        var s = FighterStats()
        s.runSpeed = 300; s.baseAccel = 900; s.maxHealth = 40; s.damageScale = 0.6
        return s
    }

    /// A skeleton with twice the health.
    static var goblin: FighterStats {
        var s = skeleton
        s.maxHealth = 80
        return s
    }
}

/// All of a character's state and rules: locomotion, height axis, move execution, combo chain, input buffer, health.
/// Brain-agnostic: feed it `MoveIntent` every frame and `Gesture`s as they happen. Works for the hero, enemies, or a second player.
/// Owns a `HumanoidRig` (the body) but knows nothing about the scene, camera or touch.
final class Fighter {
    let name: String
    let rig: HumanoidRig
    var stats: FighterStats
    var onMoveStart: ((Move) -> Void)?     // the scene listens on the hero for camera windups
    var finisherReady = false              // the scene sets this from the combo counter: uppercut / smash / air slam become finishers
    var onFinisher: ((Move) -> Void)?      // a finisher just went off (the scene spends the charge and plays the effects)
    private var slamFinisher = false       // this air slam will land as the big shockwave
    var brain: Brain?                      // who is driving this fighter (player or AI)
    weak var projectiles: ProjectileField?
    private(set) var ammo: Int?
    weak var world: PickupField?           // the ground: where weapons drop and pickups are found
    var collectsItems = false              // only the player picks up items (weapons can be picked up by anyone)
    var buffs: [String: Int] = [:]         // permanent survival buffs collected this run, by name -> stacks
    var lootDropped = false
    // Shield guard: raised by the shield's back swipe, ended by any other gesture (a forward swipe first = release)
    private(set) var guarding = false
    private(set) var guardEnergy: CGFloat = 0
    var guardCapacity: CGFloat = 60       // energy the shield can hold (the hero's release grows with it)
    var guardWalk: CGFloat = 0.4          // walking speed while guarding, as a fraction of normal
    var guardBreaks = false               // enemies: a full shield breaks and staggers its holder; the hero's just maxes out
    var hasShield: Bool { weapon?.name == "shield" }
    var lanternLight: CGFloat = 0         // carries a lantern: lights this radius around itself in dark levels, until it dies
    var immuneToHazards = false           // lava and the like leave it alone (the thing that makes them)
    var keepsWeapon = false               // bosses: strong hits don't knock the weapon loose
    var slowUntil: TimeInterval = 0       // chilled (ice) until then: runs at `slowFactor` of normal speed
    var slowFactor: CGFloat = 0.5
    private var frost: SKNode?
    var isChilled: Bool { now < slowUntil }
    func dropGuard() { endGuard() }
    var flyHeight: CGFloat = 0               // flyers: the height they are heading for
    var flyRate: CGFloat = 5                 // ... and how quickly (higher = snappier)
    var damageTaken: CGFloat = 1             // multiplies all incoming damage (a boss's ward lowers it, an opening raises it)
    var placedIndex = -1                    // which of the area's placed enemies this is (-1: spawned by an encounter)

    // Special move: fill the meter by fighting, then hold to charge. Invulnerable and rooted while charging and releasing.
    var special: Special?
    private(set) var meter: CGFloat = 0
    func debugFillMeter() { meter = 1 }
    private var chargeStart: TimeInterval?
    private var invulnerableUntil: TimeInterval = 0
    var onSpecial: ((Special) -> Void)?
    var doorCheck: (() -> Bool)?             // grounded swipe up: return true if it was used (entering a door), so it doesn't jump
    var isCharging: Bool { chargeStart != nil }
    /// 0...1 through the hold, for the camera to creep in with.
    var chargeProgress: CGFloat {
        guard let c = chargeStart, let s = special else { return 0 }
        return min(1, CGFloat((now - c) / s.chargeTime))
    }
    var invulnerable: Bool { chargeStart != nil || now < invulnerableUntil }
    private(set) var weapon: Weapon?
    let startWeapon: Weapon?
    var team = 0                           // fighters only hit other teams
    var logPrefix: String?                 // non-nil: log each move as "MOVE <prefix><description>"
    private(set) var health: CGFloat

    private enum Loco { case idle, walk, run }
    private(set) var velocity: CGFloat = 0
    private(set) var airborne = false
    private(set) var lastGesture = "-" {
        didSet { if let p = logPrefix { NSLog("MOVE %@", p + lastGesture) } }
    }
    private var loco: Loco?
    private var moveDir = CGVector(dx: 1, dy: 0)
    private var actionUntil: TimeInterval = 0
    private var brakeUntil: TimeInterval = 0
    private var current: (move: Move, start: TimeInterval)?
    private var buffered: (gesture: Gesture, time: TimeInterval)?
    private var vz: CGFloat = 0
    private var jump: (height: CGFloat, rise: CGFloat, hang: CGFloat, fall: CGFloat, t: CGFloat)?   // nil = physics (slam)
    private var falling = false
    private var airStrikes = 0
    static let maxAirStrikes = 2
    private var now: TimeInterval = 0
    private var grabAt: TimeInterval?
    private var fireAt: TimeInterval?
    private var pendingShot: Move?
    private var foesNow: [Fighter] = []
    static let personalSpace: CGFloat = 46     // root motion stops this far short of an opponent

    // Combat state
    private(set) var launched = false          // knocked into the air (juggle)
    private(set) var deadSince: TimeInterval?
    private var hurtUntil: TimeInterval = 0
    private var downUntil: TimeInterval = 0
    private var advance: (from: TimeInterval, dur: TimeInterval, dist: CGFloat, dir: CGFloat, done: CGFloat)?
    private var knock: CGFloat = 0              // signed x velocity from the last hit
    private var frozenUntil: TimeInterval = 0   // hit-stop
    private var claims: [Int: Set<ObjectIdentifier>] = [:]   // which targets each hit window already struck

    init(name: String, skin: Skin, stats: FighterStats = FighterStats()) {
        self.name = name
        self.stats = stats
        health = stats.maxHealth
        rig = HumanoidRig(skin: skin)
        startWeapon = skin.defaultWeapon
        weapon = startWeapon
        rig.flies = stats.flies
        rig.returnsToIdle = false          // the fighter drives locomotion animation itself
    }

    var dead: Bool { health <= 0 }
    var healthFraction: CGFloat { health / stats.maxHealth }
    var isHurt: Bool { now < hurtUntil || launched }
    var isDown: Bool { !airborne && now < downUntil }          // lying on the ground
    var incapacitated: Bool { dead || isHurt || isDown }
    var hittable: Bool { !dead && !isDown }
    var vulnerable: Bool { hittable && !invulnerable }        // what attacks are allowed to target
    var currentMoveName: String { current?.move.name ?? "-" }
    var currentMove: Move? { current?.move }

    /// Hit regions of the current move that are live this instant.
    var activeHits: [(index: Int, hit: Hit, power: CGFloat)] {
        guard let c = current, !incapacitated else { return [] }
        let t = now - c.start
        return c.move.hits.enumerated().compactMap { i, h in
            t >= h.start && t < h.start + h.duration ? (i, h, c.move.power) : nil
        }
    }

    /// True the first time this hit window strikes `target`; a window never hits the same target twice.
    func claim(_ index: Int, _ target: Fighter) -> Bool { claim(index, id: ObjectIdentifier(target)) }

    func claim(_ index: Int, id: ObjectIdentifier) -> Bool {
        if claims[index, default: []].contains(id) { return false }
        claims[index, default: []].insert(id)
        return true
    }

    /// Back to full health, standing, in a neutral state (respawn / test reset).
    func restore() {
        health = stats.maxHealth; deadSince = nil; launched = false
        airborne = false; jump = nil; vz = 0; falling = false; knock = 0; velocity = 0
        hurtUntil = 0; downUntil = 0; brakeUntil = 0; actionUntil = 0; frozenUntil = 0
        current = nil; buffered = nil; claims = [:]; loco = nil; advance = nil
        grabAt = nil; fireAt = nil; pendingShot = nil; lootDropped = false; equip(startWeapon)
        rig.isPaused = false; rig.height = 0; rig.alpha = 1; rig.speed = 1
        rig.play(.idle)
    }

    /// Mid-attack with a live move (not just recovering).
    var attacking: Bool {
        guard let c = current, !incapacitated else { return false }
        return !c.move.hits.isEmpty && now <= c.start + c.move.lock
    }

    /// The combo chain is still open after a hitting move (live move plus its chain window).
    private var comboOpen: Bool {
        guard let c = current, !incapacitated else { return false }
        return !c.move.hits.isEmpty && now <= c.start + c.move.lock + c.move.window
    }

    /// While attacking, don't carry through an opponent: stop at arm's length so the next move still connects.
    /// `staggeredOnly`: after the attack ends but the chain is open, only hold back for enemies we just hit,
    /// so a held run can't carry the hero past the target before the follow-up lands.
    private func stopShort(from x0: CGFloat, to x1: CGFloat, dir: CGFloat, staggeredOnly: Bool = false) -> CGFloat {
        var x = x1
        for f in foesNow where f.hittable && (!staggeredOnly || f.isHurt || f.launched) && abs(f.rig.position.y - rig.position.y) < 40 {
            let ahead = (f.rig.position.x - x0) * dir
            guard ahead > -10 else { continue }                     // already past them: not blocked
            x = dir > 0 ? min(x, max(x0, f.rig.position.x - Fighter.personalSpace))
                        : max(x, min(x0, f.rig.position.x + Fighter.personalSpace))
        }
        return x
    }

    /// Gentle positional push from the crowd (separation). Ignored while mid-attack so it never disturbs a strike.
    func nudge(dx: CGFloat, dy: CGFloat, bounds: WorldBounds) {
        guard !attacking else { return }
        rig.position.x = min(max(rig.position.x + dx, bounds.minX), bounds.maxX)
        rig.position.y = min(max(rig.position.y + dy, bounds.minY), bounds.maxY)
        rig.zPosition = 300 - rig.position.y
    }

    // MARK: Weapons and items

    /// Damage multiplier: the fighter's own strength, times the weapon for weapon moves (bare-handed hits softer).
    var damageMultiplier: CGFloat {
        stats.damageScale * (current?.move.usesWeapon == true ? (weapon?.power ?? 0.7) : 1)
    }

    func equip(_ w: Weapon?) {
        if guarding, w?.name != "shield" { endGuard() }
        weapon = w
        ammo = w?.ammo
        rig.setWeapon(w)
    }

    /// Restores health. Returns false (and does nothing) when already full, so food isn't wasted.
    /// Permanently raises max health, and heals by the same amount.
    /// Scales max and current health together (difficulty).
    func scaleMaxHealth(by factor: CGFloat) { stats.maxHealth *= factor; health *= factor }

    func raiseMaxHealth(by extra: CGFloat) { stats.maxHealth += extra; health += extra }

    @discardableResult
    func heal(_ amount: CGFloat) -> Bool {
        guard !dead, health < stats.maxHealth else { return false }
        let gained = min(amount, stats.maxHealth - health)
        health += gained
        world?.floatText("+\(Int(gained.rounded()))", at: CGPoint(x: rig.position.x, y: rig.position.y + rig.height + 150),
                         color: SKColor(red: 0.45, green: 1, blue: 0.5, alpha: 1))
        NSLog("ITEM %@ healed +%.0f hp %.0f", name, gained, health)
        return true
    }

    /// The grab moment of a pick-up move: take what's at the feet. A weapon replaces (and drops) the one in hand.
    private func performGrab() {
        guard !stats.ignoresPickups, let world, let p = world.nearest(to: rig.position, items: collectsItems) else { return }
        switch p.kind {
        case .weapon(let new):
            world.take(p)
            if var old = weapon {
                old.ammo = ammo
                world.launch(.weapon(old), from: rig.position, height: 30, vx: (rig.facingRight ? -1 : 1) * 90, vz: 520)
                NSLog("ITEM %@ swapped %@ -> %@", name, old.name, new.name)
            } else {
                NSLog("ITEM %@ equipped %@", name, new.name)
            }
            equip(new)
        case .item(let item):
            if item.apply(self) { world.take(p); NSLog("ITEM %@ used %@", name, item.name) }
        }
    }

    /// Knocked out of the hand: the weapon flips away from the attacker and lands on the ground.
    private func disarm(away: CGFloat) {
        guard var w = weapon else { return }
        w.ammo = ammo                                         // the weapon keeps its remaining ammo
        endGuard()
        equip(nil)
        world?.launch(.weapon(w), from: rig.position, height: rig.height + 70, vx: away * 190, vz: 700)
        NSLog("ITEM %@ dropped %@", name, w.name)
    }

    func debugSetHealth(_ h: CGFloat) { health = h }
    func debugSetAmmo(_ n: Int) { ammo = n }

    /// Holding a ranged weapon with arrows left: the AI keeps its distance and shoots instead of closing in.
    var canShoot: Bool {
        guard let w = weapon, w.isRanged else { return false }
        return ammo.map { $0 > 0 } ?? true
    }

    /// Refills the quiver. False (and nothing happens) without a ranged weapon or when already full.
    @discardableResult
    func addAmmo(_ n: Int) -> Bool {
        guard let w = weapon, w.isRanged, let a = ammo, a < w.capacity else { return false }
        ammo = min(w.capacity, a + n)
        world?.floatText("+\(ammo! - a) arrows", at: CGPoint(x: rig.position.x, y: rig.position.y + rig.height + 150),
                         color: SKColor(red: 1, green: 0.85, blue: 0.4, alpha: 1))
        NSLog("ITEM %@ refilled to %d arrows", name, ammo!)
        return true
    }

    /// The arrow leaves the bow, straight ahead along the lane.
    private func launchProjectile(_ move: Move) {
        guard let projectiles, let hit = move.projectile else { return }
        if let a = ammo { guard a > 0 else { return }; ammo = a - 1 }
        let dir: CGFloat = rig.facingRight ? 1 : -1
        projectiles.launch(from: CGPoint(x: rig.position.x + dir * 46, y: rig.position.y), height: rig.height, dir: dir,
                           owner: self, hit: hit, shot: move.shot)
        NSLog("ITEM %@ shot %@, %d left", name, "\(move.shot.kind)", ammo ?? -1)
        if weapon?.consumable == true, (ammo ?? 0) <= 0 { equip(nil) }      // the rock has left your hand
    }

    /// Test hook: run a move directly, skipping the gesture / context / chain rules.
    func debugPerform(_ m: Move) { perform(m) }

    var debugState: String { airborne ? "air" : (loco.map { "\($0)" } ?? "action") }

    static let sprintThreshold: CGFloat = 0.9      // fraction of top speed above which a back swipe skids instead of rolling

    /// What the fighter can do right now. Running = grounded and fast.
    private var context: MoveContext {
        airborne ? .airborne : (velocity > stats.runSpeed * 0.7 ? .running : .grounded)
    }

    // MARK: Gestures -> moves

    func handle(_ g: Gesture, bufferedAt: TimeInterval? = nil) {
        guard !incapacitated, chargeStart == nil else { return }
        let trigger = Trigger(g, facingRight: rig.facingRight)
        if guarding {
            if trigger == .forward { lastGesture = "forward -> shield release"; releaseGuard(); return }
            endGuard()
            if trigger == .back { lastGesture = "back -> guard down"; return }
        }
        var ctx = context
        // Back swipe: dodge roll unless you're at (near) full sprint, where it's the skid stop. Walking, even briskly, can roll.
        if ctx == .running, trigger == .back, velocity < stats.runSpeed * Fighter.sprintThreshold { ctx = .grounded }

        // 1. Combo chain: cuts in early (early cancel), stays open a while after the move ends
        if let cur = current,
           now >= cur.start + cur.move.cancelAt,
           now <= cur.start + cur.move.lock + cur.move.window,
           let next = MoveTable.chain(from: cur.move.name, trigger) {
            lastGesture = "\(trigger.rawValue) [\(ctx.rawValue)] -> \(next.name)  (combo from \(cur.move.name))"
            perform(next)
            return
        }
        // 2. Busy with a move that can't chain: hold the input briefly instead of dropping it
        if airborne, jump == nil {                       // mid-dive: hold the next input for the landing
            if trigger != .down { buffered = (g, bufferedAt ?? now) }
            return
        }
        if !airborne, now < actionUntil {
            if current?.move.buffersInput ?? true { buffered = (g, bufferedAt ?? now) }
            return
        }
        if trigger == .up, !airborne, doorCheck?() == true { lastGesture = "up -> enter door"; return }
        // 3. Normal context lookup: the held weapon may override this gesture (e.g. a bow's back swipe shoots)
        var override = weapon?.moves[MoveKey(context: ctx, trigger: trigger)] ?? stats.innateMoves[MoveKey(context: ctx, trigger: trigger)] ?? (stats.flies ? Fighter.flierMoves[MoveKey(context: ctx, trigger: trigger)] : nil)
        if let o = override, o.projectile != nil, let a = ammo, a <= 0, MoveTable.move(ctx, trigger) != nil { override = nil }   // empty bow: the gesture goes back to its default (the roll)
        guard let move = override ?? MoveTable.move(ctx, trigger) else {
            lastGesture = "\(trigger.rawValue) [\(ctx.rawValue)] -> (nothing)"
            return
        }
        if move.airHold > 0 {
            guard jump != nil, airStrikes < Fighter.maxAirStrikes else { lastGesture = "\(trigger.rawValue) [\(ctx.rawValue)] -> (no more air strikes)"; return }
            airStrikes += 1
        }
        if move.projectile != nil, let a = ammo, a <= 0 {
            lastGesture = "\(trigger.rawValue) [\(ctx.rawValue)] -> \(move.name) (out of arrows)"
            world?.floatText("no arrows", at: CGPoint(x: rig.position.x, y: rig.position.y + rig.height + 150), color: .white)
            return
        }
        lastGesture = "\(trigger.rawValue) [\(ctx.rawValue)] -> \(move.name)"
        if move.name == "guard" { enterGuard(); return }
        perform(move)
    }

    private func enterGuard() {
        guarding = true; guardEnergy = 0
        current = nil; claims = [:]; buffered = nil; advance = nil; brakeUntil = 0
        actionUntil = now; loco = nil
        rig.speed = 1
        rig.play(.guardUp)
        rig.setGuardCharge(0)
    }

    private func endGuard() {
        guard guarding else { return }
        guarding = false; guardEnergy = 0
        rig.setGuardCharge(0)
        loco = nil; actionUntil = min(actionUntil, now)
    }

    /// Forward swipe out of guard: the stored energy goes back out. Nothing stored is a weak shove.
    private func releaseGuard() {
        let e = guardEnergy
        endGuard()
        let hit = Hit(start: 0.08, duration: 0.14, reach: 0...(e > 0 ? 150 + e * 1.5 : 110), depth: 60, heightTolerance: 80,
                      damage: e > 0 ? 8 + e * 0.9 : 4, knockback: e >= 20 ? 560 : 300, launch: e >= 35 ? 380 : 0, stun: 0.6)
        perform(Move(name: "shield burst", animation: .shieldBurst, lock: 0.5).hitting(hit))
        NSLog("SHIELD release energy %.0f -> dmg %.0f", e, hit.damage)
    }

    private func absorb(_ hit: Hit, power: CGFloat, scale: CGFloat, away: CGFloat) {
        guardEnergy = min(guardCapacity, guardEnergy + hit.damage * power * scale)
        knock = away * 90
        rig.setGuardCharge(guardEnergy / guardCapacity)
        let gold = SKColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)
        let above = CGPoint(x: rig.position.x, y: rig.position.y + rig.height + 150)
        if guardBreaks, guardEnergy >= guardCapacity {          // overloaded: the shield gives out and its holder is staggered
            disarm(away: away)                                  // the shield flies out of its hand
            hurtUntil = now + 1.0; actionUntil = hurtUntil
            rig.reaction = 0
            rig.play(.hit)
            world?.floatText("SHIELD BREAK", at: above, color: .white)
            return
        }
        world?.floatText(guardEnergy >= guardCapacity ? "MAX" : "BLOCK", at: above, color: gold)
    }

    private var lastReaction: [String: Int] = [:]

    /// Picks the flinch ("hit") or knockdown ("down") style for the next hit: 0 = standard, never the same one twice running.
    private func rollReaction(_ kind: String) -> Int {
        guard !stats.flies else { return 0 }
        let v = [0, 1, 2].filter { $0 != (lastReaction[kind] ?? 0) }.randomElement() ?? 0
        lastReaction[kind] = v
        NSLog("REACT %@ %d", kind, v)
        return v
    }

    /// Chance that a hero jab / hook / haymaker plays an alternate (visual-only) version.
    static var variantChance = 0.4
    private var lastVariant: [CharacterAnimation: Int] = [:]

    /// 0 = the standard swing. Never the same alternate twice running, so the swings keep looking fresh.
    private func chooseVariant(_ anim: CharacterAnimation) -> Int {
        guard collectsItems, anim == .jab || anim == .hook || anim == .haymaker else { return 0 }
        let last = lastVariant[anim] ?? 0
        let v = Double.random(in: 0...1) < Fighter.variantChance ? ([1, 2].filter { $0 != last }.randomElement() ?? 1) : 0
        lastVariant[anim] = v
        if v != 0 { NSLog("VARIANT %@ %d", "\(anim)", v) }
        return v
    }

    private func perform(_ original: Move) {
        var requested = original
        if original.name != "air slam" { slamFinisher = false }
        if collectsItems, finisherReady, let f = MoveTable.finisherVersion(of: original.name) {
            requested = f
            onFinisher?(f)
        } else if collectsItems, finisherReady, original.name == "air slam" {
            slamFinisher = true                                    // the landing (not the dive) is the finisher
        }
        let tempo = stats.attackSpeed
        let move = (tempo > 1 && !airborne && requested.jumpHeight == 0 && (!requested.hits.isEmpty || requested.projectile != nil)) ? requested.sped(by: tempo) : requested
        onMoveStart?(move)
        current = (move, now)
        claims = [:]
        buffered = nil
        advance = move.advance != 0
            ? (now + move.advanceStart, move.advanceDuration, move.advance, rig.facingRight ? 1 : -1, 0) : nil
        grabAt = move.grab >= 0 ? now + move.grab : nil
        fireAt = (move.fire >= 0 && move.projectile != nil) ? now + move.fire : nil
        pendingShot = move.projectile != nil ? move : nil
        if move.lunge > 0 {
            moveDir = CGVector(dx: rig.facingRight ? 1 : -1, dy: 0)
            velocity = max(velocity, move.lunge)
        }
        if move.plant { velocity = 0 }
        if move.invulnerable > 0 { invulnerableUntil = max(invulnerableUntil, now + move.invulnerable) }
        brakeUntil = move.brake > 0 ? now + move.brake : 0   // any new move cancels a skid / plant
        if move.slam { jump = nil; vz = -stats.slamVZ; falling = true }

        if move.airHold > 0, let j = jump {
            // Hang again from right where you are: the strike holds you up, then you fall from here
            let fall = max(0.1, j.fall * min(1, rig.height / max(1, j.height)))
            jump = (rig.height, 0.0001, move.airHold, fall, 0)
            falling = false
        }
        if move.jumpHeight > 0 {
            startJump(move)
        } else if let anim = move.animation {
            rig.speed = move.hits.isEmpty && move.projectile == nil ? 1 : (airborne ? 1 : max(1, stats.attackSpeed))
            rig.variant = chooseVariant(anim)
            rig.finisher = move.finisher
            rig.play(anim)
            if !airborne { actionUntil = now + move.lock; loco = nil }
        } else if !airborne {
            actionUntil = now + move.lock     // animation-less move (e.g. pick up) still holds the fighter
        }
    }

    // MARK: Height axis

    private func startJump(_ m: Move) {
        airborne = true; falling = false; vz = 0; airStrikes = 0
        jump = (m.jumpHeight, m.jumpRise, m.jumpHang, m.jumpFall, 0)
        rig.speed = 1
        rig.play(m.animation ?? .jump)
        loco = nil
    }

    /// Strong ease-in-out: ~0 at both ends, steep in the middle.
    private func ease(_ t: CGFloat) -> CGFloat {
        let p = JumpTuning.ease
        let a = pow(t, p), b = pow(1 - t, p)
        return a / (a + b)
    }

    private func stepHeight(_ dt: CGFloat, now: TimeInterval) {
        guard airborne else { return }
        if var j = jump {
            j.t += dt
            if j.t < j.rise {
                rig.height = j.height * ease(j.t / j.rise)
            } else if j.t < j.rise + j.hang {
                // Hang: drifts a touch higher, then settles. The air-slam decision window.
                let h = (j.t - j.rise) / j.hang
                rig.height = j.height + 10 * sin(h * .pi)
            } else {
                if !falling { falling = true; rig.play(.fall) }
                rig.height = j.height * (1 - ease(min(1, (j.t - j.rise - j.hang) / j.fall)))
            }
            jump = j
            if j.t < j.rise + j.hang + j.fall { return }
        } else {
            vz -= stats.gravity * dt
            rig.height += vz * dt
            if rig.height > 0 { return }
        }
        // Landed
        airStrikes = 0
        if launched {
            rig.height = 0
            airborne = false; falling = false; vz = 0; jump = nil; launched = false
            lieDown(for: 0.8)
            return
        }
        let slammed = (jump == nil)
        rig.height = 0
        airborne = false; falling = false; vz = 0; jump = nil
        if slammed {
            // Cooldown with the combo chain open immediately (see MoveTable.slamLanding)
            let big = slamFinisher; slamFinisher = false
            let m = big ? MoveTable.slamLandingFinisher : MoveTable.slamLanding
            rig.finisher = big
            rig.play(.slamLand)
            if big { onFinisher?(m) }
            current = (m, now)
            claims = [:]
            actionUntil = now + m.lock
            brakeUntil = now + m.lock - 0.05          // feet planted
        } else {
            rig.play(.land)
            actionUntil = now + 0.15
        }
        loco = nil
    }

    // MARK: Taking hits

    // MARK: Special

    func addMeter(dealt: CGFloat = 0, taken: CGFloat = 0) {
        guard let s = special, chargeStart == nil, now >= invulnerableUntil, !dead else { return }
        let before = meter
        meter = min(1, meter + dealt * s.gainPerDamageDealt + taken * s.gainPerDamageTaken)
        if before < 1, meter >= 1 {
            world?.floatText("SPECIAL READY", at: CGPoint(x: rig.position.x, y: rig.position.y + rig.height + 150), color: SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1))
        }
    }

    /// Hold began: power up if the meter is full and the fighter is free to act.
    @discardableResult
    func beginSpecial() -> Bool {
        guard let s = special, chargeStart == nil, !incapacitated, !airborne, now >= actionUntil else { return false }
        guard meter >= 1 else {
            world?.floatText("special not ready", at: CGPoint(x: rig.position.x, y: rig.position.y + rig.height + 150), color: .white)
            return false
        }
        chargeStart = now
        current = nil; claims = [:]; buffered = nil; advance = nil; brakeUntil = 0
        actionUntil = now + 1000; loco = nil          // holds the fighter (and the locomotion animation) until released
        rig.speed = 1
        rig.play(s.chargeAnimation); rig.setAura(true)
        lastGesture = "hold -> \(s.name) (charging)"
        return true
    }

    /// Hold released before the charge finished: cancel, meter kept.
    func endSpecial() {
        guard chargeStart != nil else { return }
        chargeStart = nil; rig.setAura(false)
        actionUntil = now; loco = nil
    }

    private func releaseSpecial(_ s: Special) {
        chargeStart = nil; meter = 0; rig.setAura(false)
        invulnerableUntil = now + s.release.lock + s.recoveryInvulnerability
        lastGesture = "hold -> \(s.name)"
        perform(s.release)
        onSpecial?(s)
    }

    // MARK: Scripted control (boss brains)

    /// Slows this fighter for `t` seconds; a pale frost ring shows at the feet while it lasts.
    func chill(for t: TimeInterval) {
        slowUntil = max(slowUntil, now + t)
        guard frost == nil, !dead else { return }
        let f = SKShapeNode(ellipseOf: CGSize(width: 78, height: 20))
        f.fillColor = SKColor(red: 0.7, green: 0.9, blue: 1, alpha: 0.55); f.strokeColor = SKColor(red: 0.9, green: 1, blue: 1, alpha: 0.9)
        f.lineWidth = 3; f.glowWidth = 4; f.position = CGPoint(x: 0, y: 2); f.zPosition = -5
        rig.addChild(f); frost = f
        world?.floatText("CHILLED", at: CGPoint(x: rig.position.x, y: rig.position.y + rig.height + 150), color: SKColor(red: 0.6, green: 0.9, blue: 1, alpha: 1))
        NSLog("CHILL %@ for %.1fs", name, t)
    }

    /// Recent light melee hits taken (jabs and the like). Bosses read this to spot button-mashing.
    private var lightHitTimes: [TimeInterval] = []
    func lightHits(within window: TimeInterval) -> Int { lightHitTimes.filter { now - $0 <= window }.count }
    func forgetHits() { lightHitTimes.removeAll() }

    func setInvulnerable(for t: TimeInterval) { invulnerableUntil = max(invulnerableUntil, now + t) }

    /// Freeze in a looping pose (a channel, a cast) until `releasePose` or until something hits the fighter.
    func holdPose(_ animation: CharacterAnimation, aura: Bool) {
        current = nil; claims = [:]; buffered = nil; advance = nil; brakeUntil = 0
        actionUntil = now + 1000; loco = nil
        rig.speed = 1
        rig.play(animation); rig.setAura(aura)
    }

    func releasePose() { rig.setAura(false); actionUntil = now; loco = nil }

    func receive(_ hit: Hit, power: CGFloat, scale baseScale: CGFloat, from attacker: Fighter?, away direction: CGFloat? = nil) {
        var scale = baseScale
        let away: CGFloat = direction ?? ((attacker?.rig.position.x ?? rig.position.x - 1) <= rig.position.x ? 1 : -1)
        if guarding, !dead, attacker?.airborne != true, !hit.environmental {          // a jump-strike comes over the top of any shield
            if away * (rig.facingRight ? 1 : -1) < 0 {              // from the front
                if hit.launch > 0 || hit.knockback >= 500 || hit.shatters {         // heavy blows break the guard and still half-land
                    endGuard(); scale *= 0.5
                    world?.floatText("GUARD BROKEN", at: CGPoint(x: rig.position.x, y: rig.position.y + rig.height + 150), color: .white)
                } else { absorb(hit, power: power, scale: scale, away: away); return }
            } else { endGuard() }                                   // hit from behind
        }
        addMeter(taken: hit.damage * power * scale)
        if let a = attacker, a.team != team, !hit.environmental, !hit.isStrong, abs(a.rig.position.x - rig.position.x) < 240 {
            lightHitTimes.append(now)
            if lightHitTimes.count > 20 { lightHitTimes.removeFirst() }
        }
        health = max(0, health - hit.damage * power * scale * damageTaken * (stats.unlaunchable ? hit.vsHeavy : 1))
        if hit.chills > 0, !dead { chill(for: hit.chills) }
        current = nil; claims = [:]; buffered = nil; advance = nil
        brakeUntil = 0; velocity = 0; loco = nil
        knock = away * hit.knockback * power
        rig.speed = 1
        grabAt = nil; fireAt = nil; pendingShot = nil       // a hit interrupts the draw: no arrow, no ammo spent
        let keepsShield = (guardBreaks && hasShield) || keepsWeapon          // an enemy's shield only comes off when it breaks, or when its holder dies
        if (hit.isStrong && !stats.unlaunchable && !keepsShield) || (hit.shatters && hasShield) || dead { disarm(away: away) }       // before the reaction animation, which resets the weapon pose

        if stats.flies && !stats.unlaunchable && !dead {
            // Light and airborne: a hit knocks it back and drops it to where ground attacks can follow up
            knock = away * min(hit.knockback * power, 260)
            hurtUntil = now + hit.stun
            actionUntil = hurtUntil
            rig.reaction = 0
            rig.play(.hit)
        } else if stats.unlaunchable && !dead {
            // Too big to move: a launcher or heavy blow only shoves it back a little and rocks its head
            knock = away * min(hit.knockback * power, 120)
            hurtUntil = now + hit.stun * 0.7
            actionUntil = hurtUntil
            let heavy = hit.launch != 0 || hit.knockback * power >= 500
            rig.reaction = heavy ? 0 : rollReaction("hit")
            rig.play(heavy ? .headRock : .hit)
        } else if airborne || hit.launch > 0 {
            // Juggle: any hit keeps a launched fighter up; launchers send them higher, spikes drive them down
            let rejuggle = launched
            if hit.launch > 0 { vz = hit.launch * (0.6 + 0.4 * power) }
            else if hit.launch < 0 { vz = hit.launch }
            else { vz = max(vz, 260) }
            jump = nil; airborne = true; falling = true; launched = true
            if !rejuggle { rig.reaction = rollReaction("down") }      // one style per launch: the landing keeps it
            rig.play(.knockdown)
        } else if hit.knockback * power >= 500 || dead {
            rig.reaction = rollReaction("down")
            lieDown(for: hit.stun + 0.4)                    // blasted flat
        } else {
            hurtUntil = now + hit.stun                      // ordinary flinch
            actionUntil = hurtUntil
            rig.reaction = rollReaction("hit")
            rig.play(.hit)
        }
        if dead { deadSince = deadSince ?? now }
    }

    private func lieDown(for duration: TimeInterval) {
        rig.play(.knockdown)
        rig.dust()
        downUntil = now + (dead ? 600 : duration)
        hurtUntil = downUntil
        actionUntil = downUntil
        loco = nil
    }

    /// Freeze this fighter for a few frames on impact. Every timer shifts by the same amount, so nothing desyncs.
    func hitStop(_ duration: TimeInterval) {
        let base = max(frozenUntil, now)
        let until = now + duration
        guard until > base else { return }
        let extra = until - base
        frozenUntil = until
        rig.isPaused = true
        actionUntil += extra
        if brakeUntil > 0 { brakeUntil += extra }
        if hurtUntil > 0 { hurtUntil += extra }
        if downUntil > 0 { downUntil += extra }
        if var c = current { c.start += extra; current = c }
        if var a = advance { a.from += extra; advance = a }
        if let g = grabAt { grabAt = g + extra }
        if let f = fireAt { fireAt = f + extra }
        if var b = buffered { b.time += extra; buffered = b }
    }

    // MARK: Per-frame

    func face(towardX x: CGFloat) { rig.facingRight = x >= rig.position.x }

    /// One frame: the brain decides, then the body acts.
    func step(now currentTime: TimeInterval, dt: TimeInterval, bounds: WorldBounds, foes: [Fighter]) {
        now = currentTime
        foesNow = foes
        let intent = dead ? MoveIntent() : (brain?.think(me: self, foes: foes, now: currentTime, dt: dt) ?? MoveIntent())
        update(now: currentTime, dt: dt, intent: intent, bounds: bounds)
    }

    func update(now currentTime: TimeInterval, dt: TimeInterval, intent: MoveIntent, bounds: WorldBounds) {
        now = currentTime
        if frozenUntil > 0 {
            if currentTime < frozenUntil { return }          // hit-stop
            frozenUntil = 0; rig.isPaused = false
        }
        let d = CGFloat(dt)
        if guarding, incapacitated { endGuard() }

        if let f = frost, currentTime >= slowUntil { f.removeFromParent(); frost = nil }
        // Momentum locomotion
        let braking = currentTime < brakeUntil
        let intensity = (braking || incapacitated || chargeStart != nil) ? 0 : intent.intensity
        let hasInput = intensity > 0
        if hasInput { moveDir = intent.direction }
        let targetSpeed = intensity * stats.runSpeed * (guarding ? guardWalk : 1) * (currentTime < slowUntil ? slowFactor : 1)       // guard: walk, never run; chilled: slowed
        if targetSpeed > velocity {
            // Bigger / faster thumb drags reach full velocity sooner
            velocity = min(targetSpeed, velocity + (stats.baseAccel + intent.dragSpeed * stats.dragAccelGain) * d)
        } else {
            let decel = braking ? stats.brakeDecel
                : hasInput ? stats.steerDecel
                : (airborne ? stats.airDecel : (velocity > stats.runSpeed * 0.8 ? stats.skidDecel : stats.stopDecel))
            velocity = max(targetSpeed, velocity - decel * d)
        }
        if velocity > 0 {
            var nx = rig.position.x + moveDir.dx * velocity * d
            let runDir: CGFloat = moveDir.dx >= 0 ? 1 : -1
            if attacking { nx = stopShort(from: rig.position.x, to: nx, dir: runDir) }                          // dash attacks stop at the target
            else if comboOpen { nx = stopShort(from: rig.position.x, to: nx, dir: runDir, staggeredOnly: true) }  // ... and don't overshoot it afterwards
            rig.position.x = min(max(nx, bounds.minX), bounds.maxX)
            rig.position.y = min(max(rig.position.y + moveDir.dy * velocity * d, bounds.minY), bounds.maxY)
            rig.zPosition = 300 - rig.position.y
        }
        if var a = advance, currentTime >= a.from {
            let f = min(1, CGFloat((currentTime - a.from) / a.dur))
            let eased = f * f * (3 - 2 * f)                       // smoothstep: wind up, surge, settle
            let x = stopShort(from: rig.position.x, to: rig.position.x + a.dist * a.dir * (eased - a.done), dir: a.dir)
            rig.position.x = min(max(x, bounds.minX), bounds.maxX)
            a.done = eased
            advance = f >= 1 ? nil : a
        }
        if knock != 0 {
            rig.position.x = min(max(rig.position.x + knock * d, bounds.minX), bounds.maxX)
            let decel = (airborne ? 500 : 1800) * d
            knock = knock > 0 ? max(0, knock - decel) : min(0, knock + decel)
            rig.zPosition = 300 - rig.position.y
        }
        if let f = intent.facing { if !attacking { rig.facingRight = f } }      // guarding too: turn to meet whoever is coming
        else if hasInput, abs(intent.direction.dx) > 0.25 { rig.facingRight = intent.direction.dx > 0 }

        stepHeight(d, now: currentTime)
        if stats.flies, !airborne {                            // flyers glide to their chosen height; hurt or dead, they drop
            let down = dead || ((isHurt || isDown) && !stats.unlaunchable)
            rig.height += ((down ? 0 : flyHeight) - rig.height) * min(1, d * (down ? 14 : flyRate))
            if down, rig.height < 1 { rig.height = 0 }
        }
        if let c = chargeStart, let s = special, currentTime - c >= s.chargeTime { releaseSpecial(s) }
        if let g = grabAt, currentTime >= g { grabAt = nil; performGrab() }
        if let f = fireAt, currentTime >= f, let m = pendingShot { fireAt = nil; pendingShot = nil; launchProjectile(m) }
        if let b = buffered {
            if currentTime - b.time > ComboTuning.buffer { buffered = nil }
            else { buffered = nil; handle(b.gesture, bufferedAt: b.time) }
        }

        // Locomotion animation (paused while an action plays)
        if !airborne, !guarding, currentTime >= actionUntil {
            let desired: Loco = velocity < 20 ? .idle : (velocity < stats.runSpeed * 0.7 ? .walk : .run)
            if desired != loco {
                loco = desired
                rig.speed = desired == .walk ? 0.6 : 1
                rig.play(desired == .idle ? .idle : .run)
            }
        }
    }
}
