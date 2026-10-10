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

    /// Slower and lighter than the hero.
    static var skeleton: FighterStats {
        var s = FighterStats()
        s.runSpeed = 300; s.baseAccel = 900; s.maxHealth = 40; s.damageScale = 0.6
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
    var brain: Brain?                      // who is driving this fighter (player or AI)
    weak var projectiles: ProjectileField?
    private(set) var ammo: Int?
    weak var world: PickupField?           // the ground: where weapons drop and pickups are found
    var collectsItems = false              // only the player picks up items (weapons can be picked up by anyone)
    var lootDropped = false
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
    private var now: TimeInterval = 0
    private var grabAt: TimeInterval?
    private var fireAt: TimeInterval?
    private var pendingShot: Hit?
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
        rig.returnsToIdle = false          // the fighter drives locomotion animation itself
    }

    var dead: Bool { health <= 0 }
    var healthFraction: CGFloat { health / stats.maxHealth }
    var isHurt: Bool { now < hurtUntil || launched }
    var isDown: Bool { !airborne && now < downUntil }          // lying on the ground
    var incapacitated: Bool { dead || isHurt || isDown }
    var hittable: Bool { !dead && !isDown }
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
    func claim(_ index: Int, _ target: Fighter) -> Bool {
        let id = ObjectIdentifier(target)
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
        weapon = w
        ammo = w?.ammo
        rig.setWeapon(w)
    }

    /// Restores health. Returns false (and does nothing) when already full, so food isn't wasted.
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
        guard let world, let p = world.nearest(to: rig.position, items: collectsItems) else { return }
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
    private func launchProjectile(_ hit: Hit) {
        guard let projectiles else { return }
        if let a = ammo { guard a > 0 else { return }; ammo = a - 1 }
        let dir: CGFloat = rig.facingRight ? 1 : -1
        projectiles.launch(from: CGPoint(x: rig.position.x + dir * 46, y: rig.position.y), height: rig.height, dir: dir, owner: self, hit: hit)
        NSLog("ITEM %@ shot arrow, %d left", name, ammo ?? -1)
    }

    /// Test hook: run a move directly, skipping the gesture / context / chain rules.
    func debugPerform(_ m: Move) { perform(m) }

    var debugState: String { airborne ? "air" : (loco.map { "\($0)" } ?? "action") }

    /// What the fighter can do right now. Running = grounded and fast.
    private var context: MoveContext {
        airborne ? .airborne : (velocity > stats.runSpeed * 0.7 ? .running : .grounded)
    }

    // MARK: Gestures -> moves

    func handle(_ g: Gesture, bufferedAt: TimeInterval? = nil) {
        guard !incapacitated else { return }
        let trigger = Trigger(g, facingRight: rig.facingRight)
        let ctx = context

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
            buffered = (g, bufferedAt ?? now)
            return
        }
        // 3. Normal context lookup: the held weapon may override this gesture (e.g. a bow's back swipe shoots)
        guard let move = weapon?.moves[MoveKey(context: ctx, trigger: trigger)] ?? MoveTable.move(ctx, trigger) else {
            lastGesture = "\(trigger.rawValue) [\(ctx.rawValue)] -> (nothing)"
            return
        }
        if move.projectile != nil, let a = ammo, a <= 0 {
            lastGesture = "\(trigger.rawValue) [\(ctx.rawValue)] -> \(move.name) (out of arrows)"
            world?.floatText("no arrows", at: CGPoint(x: rig.position.x, y: rig.position.y + rig.height + 150), color: .white)
            return
        }
        lastGesture = "\(trigger.rawValue) [\(ctx.rawValue)] -> \(move.name)"
        perform(move)
    }

    private func perform(_ move: Move) {
        onMoveStart?(move)
        current = (move, now)
        claims = [:]
        buffered = nil
        advance = move.advance > 0
            ? (now + move.advanceStart, move.advanceDuration, move.advance, rig.facingRight ? 1 : -1, 0) : nil
        grabAt = move.grab >= 0 ? now + move.grab : nil
        fireAt = (move.fire >= 0 && move.projectile != nil) ? now + move.fire : nil
        pendingShot = move.projectile
        if move.lunge > 0 {
            moveDir = CGVector(dx: rig.facingRight ? 1 : -1, dy: 0)
            velocity = max(velocity, move.lunge)
        }
        if move.plant { velocity = 0 }
        brakeUntil = move.brake > 0 ? now + move.brake : 0   // any new move cancels a skid / plant
        if move.slam { jump = nil; vz = -stats.slamVZ; falling = true }

        if move.jumpHeight > 0 {
            startJump(move)
        } else if let anim = move.animation {
            rig.speed = 1
            rig.play(anim)
            if !airborne { actionUntil = now + move.lock; loco = nil }
        } else if !airborne {
            actionUntil = now + move.lock     // animation-less move (e.g. pick up) still holds the fighter
        }
    }

    // MARK: Height axis

    private func startJump(_ m: Move) {
        airborne = true; falling = false; vz = 0
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
            let m = MoveTable.slamLanding
            rig.play(.slamLand)
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

    func receive(_ hit: Hit, power: CGFloat, scale: CGFloat, from attacker: Fighter, away direction: CGFloat? = nil) {
        health = max(0, health - hit.damage * power * scale)
        let away: CGFloat = direction ?? (attacker.rig.position.x <= rig.position.x ? 1 : -1)
        current = nil; claims = [:]; buffered = nil; advance = nil
        brakeUntil = 0; velocity = 0; loco = nil
        knock = away * hit.knockback * power
        rig.speed = 1
        grabAt = nil; fireAt = nil; pendingShot = nil       // a hit interrupts the draw: no arrow, no ammo spent
        if hit.isStrong || dead { disarm(away: away) }       // before the reaction animation, which resets the weapon pose

        if airborne || hit.launch > 0 {
            // Juggle: any hit keeps a launched fighter up; launchers send them higher, spikes drive them down
            if hit.launch > 0 { vz = hit.launch * (0.6 + 0.4 * power) }
            else if hit.launch < 0 { vz = hit.launch }
            else { vz = max(vz, 260) }
            jump = nil; airborne = true; falling = true; launched = true
            rig.play(.knockdown)
        } else if hit.knockback * power >= 500 || dead {
            lieDown(for: hit.stun + 0.4)                    // blasted flat
        } else {
            hurtUntil = now + hit.stun                      // ordinary flinch
            actionUntil = hurtUntil
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

        // Momentum locomotion
        let braking = currentTime < brakeUntil
        let intensity = (braking || incapacitated) ? 0 : intent.intensity
        let hasInput = intensity > 0
        if hasInput { moveDir = intent.direction }
        let targetSpeed = intensity * stats.runSpeed
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
        if let f = intent.facing { if !attacking { rig.facingRight = f } }
        else if hasInput, abs(intent.direction.dx) > 0.25 { rig.facingRight = intent.direction.dx > 0 }

        stepHeight(d, now: currentTime)
        if let g = grabAt, currentTime >= g { grabAt = nil; performGrab() }
        if let f = fireAt, currentTime >= f, let h = pendingShot { fireAt = nil; pendingShot = nil; launchProjectile(h) }
        if let b = buffered {
            if currentTime - b.time > ComboTuning.buffer { buffered = nil }
            else { buffered = nil; handle(b.gesture, bufferedAt: b.time) }
        }

        // Locomotion animation (paused while an action plays)
        if !airborne, currentTime >= actionUntil {
            let desired: Loco = velocity < 20 ? .idle : (velocity < stats.runSpeed * 0.7 ? .walk : .run)
            if desired != loco {
                loco = desired
                rig.speed = desired == .walk ? 0.6 : 1
                rig.play(desired == .idle ? .idle : .run)
            }
        }
    }
}
