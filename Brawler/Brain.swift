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

/// Test brain: walks in a fixed direction (stands in for an enemy closing in).
final class WalkBrain: Brain {
    let direction: CGVector, intensity: CGFloat
    init(direction: CGVector, intensity: CGFloat) { self.direction = direction; self.intensity = intensity }
    func think(me: Fighter, foes: [Fighter], now: TimeInterval, dt: TimeInterval) -> MoveIntent {
        MoveIntent(direction: direction, intensity: intensity)
    }
}

/// Test brain: paces left and right at full tilt (to measure how fast a chilled hero really moves).
final class PaceBrain: Brain {
    private var t: TimeInterval = 0
    func think(me: Fighter, foes: [Fighter], now: TimeInterval, dt: TimeInterval) -> MoveIntent {
        t += dt
        return MoveIntent(direction: CGVector(dx: Int(t / 1.3) % 2 == 0 ? 1 : -1, dy: 0), intensity: 1)
    }
}

// MARK: - Crowd

/// Stops a group of enemies from all piling onto the player at once: only a few hold an "attack token" at a time and
/// close in; the rest wait in a ring at a distance, then take over as tokens free up.
final class CrowdDirector {
    var maxAttackers = 2
    var stagger: TimeInterval = 0.6          // minimum gap between two enemies starting their approach
    var members: [Fighter] = []              // all enemies; the scene refreshes this each frame

    private var holders: [(fighter: Fighter, since: TimeInterval)] = []
    private var lastGrant: TimeInterval = -10

    func holds(_ f: Fighter) -> Bool { holders.contains { $0.fighter === f } }
    func release(_ f: Fighter) { holders.removeAll { $0.fighter === f } }
    func slot(of f: Fighter) -> Int { members.firstIndex { $0 === f } ?? 0 }

    /// Grants a token to the waiting enemy nearest the target, one at a time.
    func request(_ me: Fighter, target: Fighter, now: TimeInterval) -> Bool {
        if holds(me) { return true }
        holders.removeAll { $0.fighter.dead || now - $0.since > 8 }          // never let a stuck holder block the rest
        guard holders.count < maxAttackers, now - lastGrant >= stagger else { return false }
        let tx = target.rig.position.x
        let waiting = members.filter { !$0.dead && !$0.incapacitated && !holds($0) && !$0.canShoot }   // archers never queue for melee
        guard let nearest = waiting.min(by: { abs($0.rig.position.x - tx) < abs($1.rig.position.x - tx) }), nearest === me
        else { return false }
        holders.append((me, now)); lastGrant = now
        return true
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
    var holdDistance: CGFloat = 230                   // where it waits while another enemy has the attack token
    var chargeChance: Double = 0.25                   // per second, while far away: sprint in for a dash attack
    var retreatChance: Double = 0.25                  // after attacking: back off instead of pressing
    var comboChance: Double = 0.35                    // chance an attack is a multi-hit chain
    var rangedMin: CGFloat = 270                      // archers back away when you get closer than this
    var rangedMax: CGFloat = 470                      // ... and close in when you're farther than this
    var rangedReaction: ClosedRange<Double> = 0.35...0.7   // pause before drawing
    var shotCooldown: ClosedRange<Double> = 1.4...2.6      // rest between shots
}

/// Wait in the ring -> get a token -> close in -> pause -> attack -> recover (-> back off) -> repeat.
/// Randomness and a reaction delay keep it from feeling scripted. It only sends gestures, so it can do whatever the
/// move table allows: jabs, hooks, combos, dash attacks.
final class EnemyBrain: Brain {
    var traits: EnemyTraits
    let director: CrowdDirector

    private typealias Step = (gesture: GestureKind, wait: TimeInterval)
    private enum GestureKind { case tap, forward, back, up, down }
    private enum State {
        case approach                                   // no token yet: hold position in the ring
        case engage                                     // has a token: walk to striking distance
        case charge
        case ready(until: TimeInterval)
        case attacking(steps: [Step], nextAt: TimeInterval)
        case recover(until: TimeInterval)
        case backOff(until: TimeInterval)
    }
    private var state = State.approach
    private var nextRaise: TimeInterval = 0           // shield: don't re-raise before this (after a stagger)

    init(traits: EnemyTraits = EnemyTraits(), director: CrowdDirector) {
        self.traits = traits
        self.director = director
    }

    func think(me: Fighter, foes: [Fighter], now: TimeInterval, dt: TimeInterval) -> MoveIntent {
        guard let target = foes.first(where: { !$0.dead }) else { director.release(me); return MoveIntent() }
        if me.incapacitated {                          // knocked about: drop the plan, recover before acting again
            director.release(me)
            nextRaise = now + 1.0
            if case .recover = state {} else { state = .recover(until: now + .random(in: 0.4...0.9)) }
            return MoveIntent()
        }
        if me.canShoot { director.release(me); return kite(me, target, now) }
        ranged = .position; pressedSince = nil
        let dx = target.rig.position.x - me.rig.position.x
        let dy = target.rig.position.y - me.rig.position.y
        let toward = CGVector(dx: dx / max(hypot(dx, dy), 1), dy: dy / max(hypot(dx, dy), 1))
        let inReach = abs(dx) < traits.attackRange * 0.85 && abs(dy) < traits.laneTolerance

        if me.hasShield {                              // shield up while closing in or waiting to strike; down to attack, charge, rest or back off
            var up = false
            switch state { case .approach, .engage, .ready: up = true; default: break }
            if up { if !me.guarding, now >= nextRaise { me.face(towardX: target.rig.position.x); send(.back, me) } }
            else if me.guarding { me.dropGuard() }
        }

        switch state {
        case .approach:
            if director.request(me, target: target, now: now) { state = .engage; return MoveIntent() }
            return hold(me, target)

        case .engage:
            guard director.holds(me) else { state = .approach; return MoveIntent() }
            if inReach {
                me.face(towardX: target.rig.position.x)
                state = .ready(until: now + .random(in: traits.reaction))
                return MoveIntent()
            }
            if abs(dx) > 380, Double.random(in: 0...1) < traits.chargeChance * dt { state = .charge }
            let side: CGFloat = me.rig.position.x >= target.rig.position.x ? 1 : -1
            return go(to: CGPoint(x: target.rig.position.x + side * traits.attackRange * 0.65, y: target.rig.position.y),
                      me, target)

        case .charge:
            if abs(dx) < 170 {
                me.face(towardX: target.rig.position.x)
                send(.forward, me)                                  // running forward swipe = power dash
                state = .recover(until: now + .random(in: traits.cooldown))
                return MoveIntent()
            }
            return MoveIntent(direction: toward, intensity: 1)

        case .ready(let until):
            if now >= until {
                if me.guarding, me.guardEnergy >= 12 {                 // absorbed enough: shield bash instead of a normal attack
                    me.face(towardX: target.rig.position.x)
                    send(.forward, me)
                    state = .recover(until: now + .random(in: traits.cooldown))
                    return MoveIntent()
                }
                me.dropGuard()
                state = .attacking(steps: pickAttack(me), nextAt: now)
            }
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
                director.release(me)                                   // hand the token to the next enemy in line
                state = Double.random(in: 0...1) < traits.retreatChance ? .backOff(until: now + 0.6) : .approach
            }
            return MoveIntent()

        case .backOff(let until):
            if now >= until { state = .approach }
            return MoveIntent(direction: CGVector(dx: -toward.dx, dy: 0), intensity: traits.approachIntensity)
        }
    }

    // MARK: Ranged (bow)

    private enum RangedPhase { case position, aim(until: TimeInterval), rest(until: TimeInterval) }
    private var ranged = RangedPhase.position
    private var nextShot: TimeInterval = 0
    private var nextJab: TimeInterval = 0
    private var pressedSince: TimeInterval?       // when the player first got inside striking range; nil = comfortable

    /// Stay out at range, line up in the target's lane, pause, shoot (a back swipe, same gesture as the player's),
    /// rest. Rushed to point-blank range, it jabs weakly instead.
    private func kite(_ me: Fighter, _ target: Fighter, _ now: TimeInterval) -> MoveIntent {
        let dx = target.rig.position.x - me.rig.position.x
        let dy = target.rig.position.y - me.rig.position.y
        let faceRight = dx >= 0
        let dist = abs(dx)
        switch ranged {
        case .aim(let until):
            if dist < traits.rangedMin * 0.6 { ranged = .position; return MoveIntent(facing: faceRight) }   // rushed mid-draw: abort and back off
            guard now >= until else { return MoveIntent(facing: faceRight) }
            me.face(towardX: target.rig.position.x)
            me.handle(.swipe(faceRight ? .left : .right))             // back swipe = shoot; forward is where the target is
            nextShot = now + .random(in: traits.shotCooldown)
            ranged = .rest(until: now + 0.5)
            return MoveIntent(facing: faceRight)

        case .rest(let until):
            if now >= until { ranged = .position }
            return MoveIntent(facing: faceRight)

        case .position:
            if dist < traits.rangedMin { pressedSince = pressedSince ?? now } else { pressedSince = nil }
            // Only fights back with a weak jab once it has been pressed for a while and the player is still on top of it
            if dist < 120, abs(dy) < traits.laneTolerance + 14, let since = pressedSince, now - since > 0.9 {
                // Planted feet only: jabbing while backpedalling would count as running and become a dash attack toward you
                if me.velocity < 120, now >= nextJab { nextJab = now + 1.1; me.face(towardX: target.rig.position.x); send(.tap, me) }
                return MoveIntent(facing: faceRight)
            }
            var dir = CGVector.zero
            var intensity: CGFloat = 0
            if dist < traits.rangedMin { dir.dx = faceRight ? -1 : 1; intensity = dist < traits.rangedMin * 0.7 ? 0.95 : 0.6 }   // backpedal, still facing you; hurries when close
            else if dist > traits.rangedMax { dir.dx = faceRight ? 1 : -1; intensity = 0.55 }
            let aligned = abs(dy) < traits.laneTolerance
            if !aligned { dir.dy = dy > 0 ? 1 : -1; intensity = max(intensity, 0.45) }              // slide into your lane
            if aligned, dist >= traits.rangedMin * 0.7, dist <= traits.rangedMax + 120, now >= nextShot {
                ranged = .aim(until: now + .random(in: traits.rangedReaction))
                return MoveIntent(facing: faceRight)
            }
            let len = hypot(dir.dx, dir.dy)
            if len > 0 { dir = CGVector(dx: dir.dx / len, dy: dir.dy / len) }
            return MoveIntent(direction: dir, intensity: len > 0 ? intensity : 0, facing: faceRight)
        }
    }

    // MARK: Movement helpers

    private func clampLane(_ y: CGFloat) -> CGFloat { min(max(y, -90), 210) }

    /// Stand in the ring around the player, spread out by slot so waiting enemies don't overlap.
    private func hold(_ me: Fighter, _ target: Fighter) -> MoveIntent {
        let slot = director.slot(of: me)
        let side: CGFloat = me.rig.position.x >= target.rig.position.x ? 1 : -1
        let lanes: [CGFloat] = [0, 55, -55]
        let point = CGPoint(x: target.rig.position.x + side * (traits.holdDistance + CGFloat(slot / 3) * 45),
                            y: clampLane(target.rig.position.y + lanes[slot % 3]))
        return go(to: point, me, target)
    }

    private func go(to p: CGPoint, _ me: Fighter, _ target: Fighter) -> MoveIntent {
        let dx = p.x - me.rig.position.x, dy = p.y - me.rig.position.y
        let d = hypot(dx, dy)
        if d < 16 { me.face(towardX: target.rig.position.x); return MoveIntent() }
        return MoveIntent(direction: CGVector(dx: dx / d, dy: dy / d), intensity: traits.approachIntensity,
                          facing: me.guarding ? target.rig.position.x >= me.rig.position.x : nil)     // a raised shield keeps facing you
    }

    private func pickAttack(_ me: Fighter) -> [Step] {
        if me.weapon?.name == "hammer" { return [(.tap, 0.9)] }          // one slow slam
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
        case .back:    me.handle(.swipe(me.rig.facingRight ? .left : .right))
        }
    }
}


/// A goblin carrying a bomb: lines up in your lane at lobbing distance and throws it. After that it fights with its blade as usual.
/// (Kill it before it throws and it drops the bomb for you.)
final class BomberBrain: Brain {
    private let inner: Brain
    private let fallback: Weapon?
    private var throwAt: TimeInterval = 0
    private var threw = false

    init(inner: Brain, fallback: Weapon?) { self.inner = inner; self.fallback = fallback }

    func think(me: Fighter, foes: [Fighter], now: TimeInterval, dt: TimeInterval) -> MoveIntent {
        if me.weapon == nil, threw { threw = false; me.equip(fallback) }              // the bomb has gone: back to the blade
        guard !me.dead, !me.isHurt, me.weapon?.name == "bomb", let hero = foes.first(where: { !$0.dead }) else {
            return inner.think(me: me, foes: foes, now: now, dt: dt)
        }
        if throwAt == 0 { throwAt = now + .random(in: 1.4...2.6) }
        let dx = hero.rig.position.x - me.rig.position.x, dy = hero.rig.position.y - me.rig.position.y
        let faceRight = dx >= 0, dist = abs(dx)
        if now >= throwAt, dist >= 230, dist <= 430, abs(dy) < 40 {
            me.face(towardX: hero.rig.position.x)
            me.handle(.tap)
            threw = true
            NSLog("BOMB goblin throws at dist %.0f dy %.0f", dist, dy)
            return MoveIntent(facing: faceRight)
        }
        var dir = CGVector.zero
        var intensity: CGFloat = 0
        if dist < 230 { dir.dx = faceRight ? -1 : 1; intensity = 0.75 }              // back off to lobbing distance
        else if dist > 430 { dir.dx = faceRight ? 1 : -1; intensity = 0.6 }
        if abs(dy) >= 40 { dir.dy = dy > 0 ? 1 : -1; intensity = max(intensity, 0.5) }   // the bomb lands in the thrower's lane
        let len = hypot(dir.dx, dir.dy)
        if len > 0 { dir = CGVector(dx: dir.dx / len, dy: dir.dy / len) }
        return MoveIntent(direction: dir, intensity: len > 0 ? intensity : 0, facing: faceRight)
    }
}
