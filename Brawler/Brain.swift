import SpriteKit

/// Decides what a Fighter does. The player's thumbs and an AI are both just brains: they read the world,
/// return a movement intent, and send gestures through the same `Fighter.handle` the player uses.
protocol Brain: AnyObject {
    /// Called once per frame before the fighter updates.
    func think(me: Fighter, foes: [Fighter], now: TimeInterval, dt: TimeInterval) -> MoveIntent
}

// MARK: - Player

/// Touch and keyboard (both feed `InputController`) -> a Fighter.
final class PlayerBrain: Brain {
    let input: InputController

    init(input: InputController, fighter: Fighter) {
        self.input = input
        input.onGesture = { [weak fighter] in fighter?.handle($0) }
    }

    func think(me: Fighter, foes: [Fighter], now: TimeInterval, dt: TimeInterval) -> MoveIntent {
        input.update(dt: dt)
        return MoveIntent(direction: input.direction, intensity: input.intensity, dragSpeed: input.dragSpeed)
    }
}

// MARK: - Enemy

/// Personality knobs. Different enemy types are different numbers here (plus a skin and stats).
struct EnemyTraits {
    var reaction: ClosedRange<Double> = 0.3...0.6     // pause between reaching you and acting
    var cooldown: ClosedRange<Double> = 1.0...2.4     // rest after an attack sequence
    var attackRange: CGFloat = 120                    // horizontal reach before it starts attacking
    var laneTolerance: CGFloat = 26                   // how closely it lines up with you in depth
    var approachIntensity: CGFloat = 0.5              // walk (stays below the running threshold)
    var chargeChance: Double = 0.25                   // per second, while far away: sprint in for a dash attack
    var retreatChance: Double = 0.25                  // after attacking: back off instead of pressing
    var comboChance: Double = 0.35                    // chance an attack is a multi-hit chain
}

/// Approach -> pause -> attack -> recover (-> back off) -> repeat. Randomness and a reaction delay keep it from feeling scripted.
/// It only ever sends gestures, so it can do whatever the move table allows: jabs, hooks, combos, dash attacks.
final class EnemyBrain: Brain {
    var traits: EnemyTraits

    private typealias Step = (gesture: GestureKind, wait: TimeInterval)
    private enum GestureKind { case tap, forward, up, down }
    private enum State {
        case approach
        case charge
        case ready(until: TimeInterval)
        case attacking(steps: [Step], nextAt: TimeInterval)
        case recover(until: TimeInterval)
        case backOff(until: TimeInterval)
    }
    private var state = State.approach

    init(traits: EnemyTraits = EnemyTraits()) { self.traits = traits }

    func think(me: Fighter, foes: [Fighter], now: TimeInterval, dt: TimeInterval) -> MoveIntent {
        guard let target = foes.first else { return MoveIntent() }
        let dx = target.rig.position.x - me.rig.position.x
        let dy = target.rig.position.y - me.rig.position.y
        let dist = max(hypot(dx, dy), 1)
        let toward = CGVector(dx: dx / dist, dy: dy / dist)
        let inReach = abs(dx) < traits.attackRange * 0.85 && abs(dy) < traits.laneTolerance

        switch state {
        case .approach:
            if inReach {
                me.face(towardX: target.rig.position.x)
                state = .ready(until: now + .random(in: traits.reaction))
                return MoveIntent()
            }
            if abs(dx) > 380, Double.random(in: 0...1) < traits.chargeChance * dt { state = .charge }
            return MoveIntent(direction: toward, intensity: traits.approachIntensity)

        case .charge:
            if abs(dx) < 170 {
                me.face(towardX: target.rig.position.x)
                send(.forward, me)                                  // running forward swipe = power dash
                state = .recover(until: now + .random(in: traits.cooldown))
                return MoveIntent()
            }
            return MoveIntent(direction: toward, intensity: 1)

        case .ready(let until):
            if now >= until { state = .attacking(steps: pickAttack(), nextAt: now) }
            return MoveIntent()

        case .attacking(var steps, let nextAt):
            guard now >= nextAt else { return MoveIntent() }
            guard !steps.isEmpty else {
                state = .recover(until: now + .random(in: traits.cooldown))
                return MoveIntent()
            }
            let step = steps.removeFirst()
            me.face(towardX: target.rig.position.x)
            send(step.gesture, me)
            state = .attacking(steps: steps, nextAt: now + step.wait)
            return MoveIntent()

        case .recover(let until):
            if now >= until {
                state = Double.random(in: 0...1) < traits.retreatChance ? .backOff(until: now + 0.6) : .approach
            }
            return MoveIntent()

        case .backOff(let until):
            if now >= until { state = .approach }
            return MoveIntent(direction: CGVector(dx: -toward.dx, dy: 0), intensity: traits.approachIntensity)
        }
    }

    private func pickAttack() -> [Step] {
        if Double.random(in: 0...1) < traits.comboChance {
            return [[(.tap, 0.22), (.tap, 0.5)],                                  // jab, jab
                    [(.forward, 0.3), (.up, 0.9)],                                // hook, uppercut
                    [(.tap, 0.22), (.tap, 0.22), (.up, 0.9)]].randomElement()!    // jab, jab, uppercut
        }
        return [[(.tap, 0.5)], [(.forward, 0.6)]].randomElement()!
    }

    private func send(_ kind: GestureKind, _ me: Fighter) {
        switch kind {
        case .tap:     me.handle(.tap)
        case .up:      me.handle(.swipe(.up))
        case .down:    me.handle(.swipe(.down))
        case .forward: me.handle(.swipe(me.rig.facingRight ? .right : .left))
        }
    }
}
