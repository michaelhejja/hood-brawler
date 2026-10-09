import SpriteKit

/// What a brain wants the body to do this frame. The player's thumb and an AI both produce one of these.
struct MoveIntent {
    var direction = CGVector.zero    // unit vector, +y up
    var intensity: CGFloat = 0       // 0...1, how hard they push (walk -> run)
    var dragSpeed: CGFloat = 0       // pt/s of the thumb; faster flicks accelerate quicker
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
}

/// All of a character's state and rules: locomotion, height axis, move execution, combo chain, input buffer, health.
/// Brain-agnostic: feed it `MoveIntent` every frame and `Gesture`s as they happen. Works for the hero, enemies, or a second player.
/// Owns a `HumanoidRig` (the body) but knows nothing about the scene, camera or touch.
final class Fighter {
    let name: String
    let rig: HumanoidRig
    var stats: FighterStats
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

    init(name: String, skin: Skin, stats: FighterStats = FighterStats()) {
        self.name = name
        self.stats = stats
        health = stats.maxHealth
        rig = HumanoidRig(skin: skin)
        rig.returnsToIdle = false          // the fighter drives locomotion animation itself
    }

    var debugState: String { airborne ? "air" : (loco.map { "\($0)" } ?? "action") }

    /// What the fighter can do right now. Running = grounded and fast.
    private var context: MoveContext {
        airborne ? .airborne : (velocity > stats.runSpeed * 0.7 ? .running : .grounded)
    }

    // MARK: Gestures -> moves

    func handle(_ g: Gesture, bufferedAt: TimeInterval? = nil) {
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
        // 3. Normal context lookup
        guard let move = MoveTable.move(ctx, trigger) else {
            lastGesture = "\(trigger.rawValue) [\(ctx.rawValue)] -> (nothing)"
            return
        }
        lastGesture = "\(trigger.rawValue) [\(ctx.rawValue)] -> \(move.name)"
        perform(move)
    }

    private func perform(_ move: Move) {
        current = (move, now)
        buffered = nil
        if move.lunge > 0 {
            moveDir = CGVector(dx: rig.facingRight ? 1 : -1, dy: 0)
            velocity = max(velocity, move.lunge)
        }
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
        let slammed = (jump == nil)
        rig.height = 0
        airborne = false; falling = false; vz = 0; jump = nil
        if slammed {
            // Cooldown with the combo chain open immediately (see MoveTable.slamLanding)
            let m = MoveTable.slamLanding
            rig.play(.slamLand)
            current = (m, now)
            actionUntil = now + m.lock
            brakeUntil = now + m.lock - 0.05          // feet planted
        } else {
            rig.play(.land)
            actionUntil = now + 0.15
        }
        loco = nil
    }

    // MARK: Per-frame

    func update(now currentTime: TimeInterval, dt: TimeInterval, intent: MoveIntent, bounds: WorldBounds) {
        now = currentTime
        let d = CGFloat(dt)

        // Momentum locomotion
        let braking = currentTime < brakeUntil
        let intensity = braking ? 0 : intent.intensity
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
            rig.position.x = min(max(rig.position.x + moveDir.dx * velocity * d, bounds.minX), bounds.maxX)
            rig.position.y = min(max(rig.position.y + moveDir.dy * velocity * d, bounds.minY), bounds.maxY)
            rig.zPosition = 300 - rig.position.y
        }
        if hasInput, abs(intent.direction.dx) > 0.25 { rig.facingRight = intent.direction.dx > 0 }

        stepHeight(d, now: currentTime)
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
