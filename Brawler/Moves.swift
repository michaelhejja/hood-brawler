import Foundation
import CoreGraphics

/// Combo timing. Start generous, tighten after playtesting.
enum ComboTuning {
    static let cancelAt: TimeInterval = 0.12   // a chained move may cut in this long after the previous one starts
    static let window: TimeInterval = 0.4      // chain stays open this long after the previous move's lock ends
    static let buffer: TimeInterval = 0.25     // early/unchainable input is held this long, then fires when free
}

/// Jumps follow a strong ease-in-out curve (not a parabola): slow, tense start and apex, fast in between.
enum JumpTuning {
    static let rise: CGFloat = 0.2      // seconds, launch to apex
    static let hang: CGFloat = 0.18     // seconds floating at the apex: the decision window (swipe down to slam, or land)
    static let fall: CGFloat = 0.3      // seconds, apex to ground
    static let ease: CGFloat = 2.5      // 1 = linear, higher = more tension at the bottom and top
}

/// Context + gesture. Weapons use these to override single entries of the default move table.
struct MoveKey: Hashable { let context: MoveContext; let trigger: Trigger }

/// A gesture normalised to the hero's facing: swipes become forward / back.
enum Trigger: String, Hashable {
    case tap, up, down, forward, back

    init(_ g: Gesture, facingRight: Bool) {
        switch g {
        case .tap: self = .tap
        case .swipe(.up): self = .up
        case .swipe(.down): self = .down
        case .swipe(.right): self = facingRight ? .forward : .back
        case .swipe(.left): self = facingRight ? .back : .forward
        }
    }
}

enum MoveContext: String {
    case grounded   // standing or slow walk
    case running
    case airborne
}

/// A strike's active window and effect. The region is relative to the attacker's facing, in world points.
struct Hit {
    var start: TimeInterval              // seconds after the move begins
    var duration: TimeInterval = 0.1
    var reach: ClosedRange<CGFloat>      // forward range from the attacker (negative = behind)
    var depth: CGFloat = 36              // lane tolerance (+/-)
    var heightTolerance: CGFloat = 70    // max height difference between attacker and target
    var damage: CGFloat
    var knockback: CGFloat = 0           // pt/s away from the attacker
    var launch: CGFloat = 0              // > 0 pops the target into the air (juggle); < 0 spikes it down
    var stun: TimeInterval = 0.3
    var disarm = false                   // knocks the weapon out of the victim's hand regardless of knockback
    var vsHeavy: CGFloat = 1             // damage multiplier against things too big to launch (giants, crates)
    var shatters = false                 // breaks a raised shield outright and knocks it loose
    var environmental = false            // comes from the level, not a fighter: no shield can block it
    var chills: TimeInterval = 0         // slows the target's run speed for this long (ice)
}

extension Hit {
    static let arrow = Hit(start: 0, duration: 0, reach: 0...0, depth: 30, heightTolerance: 60, damage: 7, knockback: 160, stun: 0.3)
    static let rock = Hit(start: 0, duration: 0, reach: 0...0, depth: 30, heightTolerance: 70, damage: 12, knockback: 260, stun: 0.4)
    /// A thrown bomb does nothing in flight; it explodes on the ground after its fuse (see `explode` in the scene).
    static let bombThrow = Hit(start: 0, duration: 0, reach: 0...0, damage: 0)
    /// The blast: heavy, pops you into the air, and no shield blocks it. Hits everyone in range, thrower included.
    static let bombBlast = Hit(start: 0, duration: 0, reach: 0...0, depth: 80, heightTolerance: 100, damage: 34, knockback: 650, launch: 380, stun: 0.8, environmental: true)
    /// Strong hits (launchers, spikes, heavy knockback) knock the weapon out of the victim's hand.
    var isStrong: Bool { disarm || launch != 0 || knockback >= 500 }

    static let jab        = Hit(start: 0.035, duration: 0.08, reach: 0...115, damage: 6, knockback: 140, stun: 0.25)
    // Finisher: slow to land, knocks down (500+ knockback = a strong hit) but doesn't launch
    static let haymaker   = Hit(start: 0.17, duration: 0.12, reach: 0...150, damage: 16, knockback: 540, stun: 0.6)
    static let hook       = Hit(start: 0.10, duration: 0.10, reach: 0...135, damage: 12, knockback: 300, stun: 0.4)
    // Spear: long and narrow. Outreaches every other melee hit, but misses anything off its lane.
    static let spearPoke   = Hit(start: 0.06, duration: 0.09, reach: 20...185, depth: 20, damage: 7, knockback: 160, stun: 0.25)
    static let spearThrust = Hit(start: 0.12, duration: 0.12, reach: 40...235, depth: 22, damage: 14, knockback: 380, stun: 0.4)
    // Special: hits everything within ~one screen either side, every lane. Giants only rock back, so it hits them 4x harder instead.
    static let rageShockwave = Hit(start: 0.19, duration: 0.12, reach: -650...650, depth: 170, heightTolerance: 400, damage: 28, knockback: 800, launch: 650, stun: 0.9, vsHeavy: 4)
    static let dashJab    = Hit(start: 0.04, duration: 0.14, reach: 0...150, damage: 8, knockback: 320, stun: 0.3)
    static let dashHook   = Hit(start: 0.08, duration: 0.18, reach: 0...160, damage: 16, knockback: 420, stun: 0.45, disarm: true)   // <500: staggers, doesn't floor
    static let uppercut   = Hit(start: 0.07, duration: 0.14, reach: -10...150, heightTolerance: 300, damage: 14, knockback: 80, launch: 1202, stun: 0.4)   // 850 x sqrt(2): apex doubles
    // Finisher versions (long combos): about double the damage, wider and stronger launches. Same timing as the originals.
    static let uppercutFinisher = Hit(start: 0.07, duration: 0.18, reach: -30...200, depth: 70, heightTolerance: 320, damage: 32, knockback: 120, launch: 1500, stun: 0.6)
    static let smashFinisher    = Hit(start: 0.25, duration: 0.14, reach: -140...260, depth: 90, heightTolerance: 140, damage: 38, knockback: 900, launch: 600, stun: 0.8, vsHeavy: 2)
    static let knockoutFinisher = Hit(start: 0.10, duration: 0.12, reach: 0...190, damage: 30, knockback: 950, stun: 0.8, vsHeavy: 2)       // flattens them: knockback, no launch
    static let knockoutDash     = Hit(start: 0.08, duration: 0.18, reach: 0...200, damage: 30, knockback: 950, stun: 0.8, disarm: true, vsHeavy: 2)
    static let shockwaveFinisher = Hit(start: 0, duration: 0.14, reach: -280...280, depth: 100, heightTolerance: 100, damage: 28, knockback: 800, launch: 650, stun: 0.8, vsHeavy: 2)
    // Air strike: quick, short-range, forgiving about height so it connects with things above or below you
    static let airStrike  = Hit(start: 0.03, duration: 0.14, reach: -10...125, depth: 38, heightTolerance: 220, damage: 8, knockback: 180, stun: 0.3)
    static let diveSlam   = Hit(start: 0, duration: 1.0, reach: 0...150, depth: 40, heightTolerance: 140, damage: 10, knockback: 250, launch: -900, stun: 0.4)
    static let shockwave  = Hit(start: 0, duration: 0.12, reach: -170...170, depth: 60, heightTolerance: 80, damage: 14, knockback: 650, launch: 450, stun: 0.5)
    // Hammer: slow to land (the wind-up is the warning), wide, but only low: a jump clears it, a roll's invulnerability beats it.
    static let hammer     = Hit(start: 0.42, duration: 0.12, reach: 20...245, depth: 80, heightTolerance: 45, damage: 18, knockback: 560, stun: 0.6, shatters: true)
    static let forgeSmash = Hit(start: 0, duration: 0, reach: 0...0, damage: 18, knockback: 620, launch: 320, stun: 0.8)
    static let lava       = Hit(start: 0, duration: 0, reach: 0...0, damage: 9, stun: 0.45, environmental: true)
    static let giantSlam  = Hit(start: 0, duration: 0, reach: 0...0, damage: 20, knockback: 820, launch: 380, stun: 0.8)
    static let smash      = Hit(start: 0.25, duration: 0.12, reach: 0...175, depth: 50, heightTolerance: 120, damage: 18, knockback: 700, launch: 350, stun: 0.5)
}

/// How a launched projectile travels. Arrows fly level; a rock arcs (vz = initial vertical speed, gravity pulls it down and it lands).
enum ProjectileKind { case arrow, rock, bolt, ice, bomb, fire }
struct Shot {
    var kind = ProjectileKind.arrow
    var speed: CGFloat = 1100
    var vz: CGFloat = 0
    var gravity: CGFloat = 0
}

enum FinisherTuning {
    /// Combo hits needed before the uppercut / ground smash / air slam become their finisher versions. Another one is earned
    /// every `threshold` hits after that (10, 20, 30 ...), and a combo that ends starts the count again.
    static var threshold = 10
}

/// How a hero bends the shared finishers: multipliers on every hit of the finisher move. All 1 = the shared version.
struct FinisherStyle {
    var damage: CGFloat = 1
    var reach: CGFloat = 1
    var knockback: CGFloat = 1
    var launch: CGFloat = 1          // launch speed and the uppercut's jump height
    var stun: TimeInterval = 1
}

/// Pure data. To add a move, add one row to `MoveTable.rows`.
struct Move {
    let name: String
    var animation: CharacterAnimation? = nil
    var lock: TimeInterval = 0       // grounded: how long the action holds before locomotion resumes
    var lunge: CGFloat = 0           // forward speed burst (pt/s); never reduces current speed
    var advance: CGFloat = 0         // root motion: distance (pt) travelled forward, eased, independent of run speed
    var advanceStart: TimeInterval = 0
    var advanceDuration: TimeInterval = 0.2
    var jumpHeight: CGFloat = 0      // > 0 launches into the air (peak height in pt)
    var jumpRise = JumpTuning.rise
    var jumpFall = JumpTuning.fall
    var jumpHang = JumpTuning.hang
    var slam = false                 // dive to the ground
    var plant = false                // kills horizontal run momentum when it starts (the move supplies its own travel)
    var brake: TimeInterval = 0      // > 0 forces a hard stop for this long (skid)
    var airHold: CGFloat = 0             // in the air: restart the hang at the current height for this long (an air strike keeps you up)
    var invulnerable: TimeInterval = 0   // can't be hit for this long from the start of the move (dodges)
    var power: CGFloat = 1           // relative damage / knockback (used once hit detection exists)
    var buffersInput = true          // false: a too-early input during this move is dropped, not held (tight-timing chains)
    var cancelAt = ComboTuning.cancelAt
    var window = ComboTuning.window
    var hits: [Hit] = []
    var usesWeapon = false           // damage scales with the equipped weapon (bare-handed is weaker)
    var grab: TimeInterval = -1      // >= 0: picks up whatever is at the fighter's feet this long into the move
    var fire: TimeInterval = -1      // >= 0: launches `projectile` this long into the move (uses one ammo)
    var projectile: Hit? = nil
    var shot = Shot()                // flight path of `projectile`
    var emphasis = Emphasis.none     // camera zoom / slow-mo when the hero performs it (bigger moment, bigger effect)
    var finisher = false             // the powered-up version unlocked by a long combo (gold trails, big callout)

    func hitting(_ h: Hit...) -> Move { var m = self; m.hits = h; return m }

    /// The same move run `k` times faster: every time value shrinks, distances and damage stay the same.
    func styled(_ s: FinisherStyle) -> Move {
        var m = self
        m.jumpHeight *= s.launch
        m.hits = hits.map { var h = $0
            h.damage *= s.damage; h.knockback *= s.knockback; h.launch *= s.launch; h.stun *= s.stun
            h.reach = (h.reach.lowerBound * s.reach)...(h.reach.upperBound * s.reach)
            return h }
        return m
    }

    func sped(by k: CGFloat) -> Move {
        var m = self
        let t = TimeInterval(1 / k)
        m.lock *= t; m.advanceStart *= t; m.advanceDuration *= t; m.brake *= t; m.cancelAt *= t
        if m.grab >= 0 { m.grab *= t }
        if m.fire >= 0 { m.fire *= t }
        m.hits = m.hits.map { var h = $0; h.start *= t; h.duration *= t; return h }
        return m
    }
    var armed: Move { var m = self; m.usesWeapon = true; return m }
    func emphasized(_ e: Emphasis) -> Move { var m = self; m.emphasis = e; return m }
}

enum MoveTable {
    // (see MoveKey below)

    // Back-swipe while grounded is intentionally absent: an open slot for future specials.
    // Animations marked (placeholder) reuse existing poses until dedicated ones exist.
    private static let rows: [(MoveContext, Trigger, Move)] = [
        // Standing / slow walk
        (.grounded, .tap,     Move(name: "punch",         animation: .jab,  lock: 0.2).hitting(.jab)),
        (.grounded, .up,      Move(name: "small jump",    jumpHeight: 170)),
        (.grounded, .down,    Move(name: "pick up",       animation: .pickup, lock: 0.28, grab: 0.1)),
        (.grounded, .back,    Move(name: "dodge roll",   animation: .roll, lock: 0.38, advance: -250, advanceDuration: 0.3, plant: true, invulnerable: 0.26, buffersInput: false, cancelAt: 0.26, window: 0.08)),
        (.grounded, .forward, heavyAttack),

        // Fully running
        (.running,  .tap,     Move(name: "dash attack",   animation: .jab,  lock: 0.3, lunge: 560).hitting(.dashJab)),
        (.running,  .up,      Move(name: "big jump",      lunge: 560, jumpHeight: 230, jumpRise: 0.24, jumpFall: 0.34, jumpHang: 0.2)),
        (.running,  .forward, powerDash),
        (.running,  .back,    Move(name: "skid stop",     animation: .land, lock: 0.3, brake: 0.3)), // (placeholder) land pose

        // In the air
        (.airborne, .tap,     Move(name: "air strike",    animation: .airStrike, airHold: 0.3).hitting(.airStrike).armed),
        (.airborne, .down,    Move(name: "air slam",      animation: .slam, slam: true, power: 1.0).hitting(.diveSlam).armed.emphasized(.medium)),
    ]

    // Combo links: after `from` (by move name), `trigger` gives the next move. Input-driven: no hit required.
    private static let heavyAttack = Move(name: "heavy attack", animation: .hook, lock: 0.5, lunge: 140).hitting(.hook).armed.emphasized(.light)
    private static let powerDash = Move(name: "power dash",    animation: .hook, lock: 0.5, lunge: 760).hitting(.dashHook).armed.emphasized(.medium)
    /// The roll counter: same hit, but it covers about the 250 the roll gave up (lunge speed 950 coasts ~245), so you re-engage where you were.
    private static let counterDash = Move(name: "counter dash",  animation: .hook, lock: 0.5, lunge: 950).hitting(.dashHook).armed.emphasized(.medium)

    /// Running ground slam. Same shockwave and knockback as the air slam, a bit less powerful.
    static let groundSmash = Move(name: "ground smash", animation: .smash, lock: 0.62, advance: 150, advanceStart: 0, advanceDuration: 0.27, brake: 0.4, power: 0.7).hitting(.smash).armed.emphasized(.heavy)

    private static let uppercut = Move(name: "uppercut", animation: .uppercut, advance: 45, advanceStart: 0, advanceDuration: 0.12, jumpHeight: 400, jumpRise: 0.22, jumpFall: 0.34, jumpHang: 0.26, plant: true, brake: 0.3).hitting(.uppercut).armed.emphasized(.heavy)

    /// Landing from an air slam: a short recovery during which the combo chain is open from the first frame.
    static let slamLanding = Move(name: "slam landing", animation: .slamLand, lock: 0.3, cancelAt: 0).hitting(.shockwave).armed.emphasized(.massive)

    /// Third punch in a string: a big, committed overhand right.
    private static let haymaker = Move(name: "haymaker", animation: .haymaker, lock: 0.55, lunge: 120, plant: true, brake: 0.2).hitting(.haymaker).emphasized(.medium)

    /// Powered-up copies keep the original's name, so every chain that follows them still works.
    static let uppercutFinisher: Move = { var m = uppercut; m.hits = [.uppercutFinisher]; m.jumpHeight = 520; m.emphasis = .massive; m.finisher = true; return m }()
    static let smashFinisher: Move = { var m = groundSmash; m.hits = [.smashFinisher]; m.power = 1.0; m.emphasis = .massive; m.finisher = true; return m }()
    static let knockoutHeavy: Move = { var m = heavyAttack; m.hits = [.knockoutFinisher]; m.emphasis = .massive; m.finisher = true; return m }()
    static let knockoutPowerDash: Move = { var m = powerDash; m.hits = [.knockoutDash]; m.emphasis = .massive; m.finisher = true; return m }()
    static let slamLandingFinisher: Move = { var m = slamLanding; m.hits = [.shockwaveFinisher]; m.finisher = true; return m }()

    static func finisherVersion(of name: String, style: FinisherStyle) -> Move? { finisherVersion(of: name)?.styled(style) }

    static func finisherVersion(of name: String) -> Move? {
        switch name {
        case "uppercut": return uppercutFinisher
        case "ground smash": return smashFinisher
        case "heavy attack": return knockoutHeavy              // forward swipe, standing
        case "power dash": return knockoutPowerDash            // forward swipe, running
        default: return nil
        }
    }

    private static let chains: [(from: String, trigger: Trigger, move: Move)] = [
        ("punch",      .tap,  Move(name: "punch 2",      animation: .jab,  lock: 0.2, lunge: 80).hitting(.jab)),
        ("punch 2",      .tap,  haymaker),                       // mash tap: jab, jab, big finisher
        ("punch 2",      .up,   uppercut),                       // standing-combo entry
        ("heavy attack", .up,   uppercut),                       // any strong attack ...
        ("power dash",   .up,   uppercut),                       // ... including after a full run
        ("counter dash", .up,   uppercut),                       // the roll counter keeps the same follow-ups as the power dash
        ("dodge roll",   .forward, counterDash),                   // counter: forward swipe late in the roll, ~0.2s window
        ("slam landing", .forward, powerDash),                   // juggle: slam, then straight back into a dash
        ("slam landing", .up,   uppercut),                       // ... or launch them
        ("power dash",  .down, groundSmash),
        ("counter dash", .down, groundSmash),
        ("dash attack", .down, groundSmash),
    ]
    private static let chainTable: [String: Move] = Dictionary(
        uniqueKeysWithValues: chains.map { ("\($0.from)|\($0.trigger.rawValue)", $0.move) })

    static func chain(from name: String, _ trigger: Trigger) -> Move? {
        chainTable["\(name)|\(trigger.rawValue)"]
    }

    private static let table: [MoveKey: Move] = Dictionary(
        uniqueKeysWithValues: rows.map { (MoveKey(context: $0.0, trigger: $0.1), $0.2) })

    static func move(_ context: MoveContext, _ trigger: Trigger) -> Move? {
        table[MoveKey(context: context, trigger: trigger)]
    }
}


// MARK: - Specials

/// A hero's signature move. Data only: hold to charge (invulnerable, rooted), then `release` plays.
/// Another hero gets a different special by setting `Fighter.special`; nothing else changes.
struct Special {
    var name: String
    var chargeTime: TimeInterval = 1.0               // hold this long to unleash it; letting go earlier cancels (meter kept)
    var chargeAnimation: CharacterAnimation          // looping power-up pose while holding
    var release: Move                                // the move that plays when the charge completes
    var recoveryInvulnerability: TimeInterval = 0.2  // extra invulnerable time after the move ends
    var gainPerDamageDealt: CGFloat = 0.0065         // meter (0...1) gained per point of damage you deal
    var gainPerDamageTaken: CGFloat = 0.0032         // ... and per point you take (comeback)

    var impactDelay: TimeInterval { release.hits.first?.start ?? 0 }
    var radius: CGFloat { release.hits.map { max(abs($0.reach.lowerBound), abs($0.reach.upperBound)) }.max() ?? 0 }
}

enum Specials {
    /// Roar, leap-less ground pound, screen-wide shockwave that launches everyone it hits.
    static let rageSlam = Special(
        name: "rage slam", chargeAnimation: .powerUp,
        release: Move(name: "rage slam", animation: .rageSlam, lock: 0.75, plant: true).hitting(.rageShockwave).emphasized(.special))

    /// Slow to charge: a lunging shoulder-charge that plows through everything in front and launches it.
    static let bullRush = Special(
        name: "bull rush", chargeTime: 1.2, chargeAnimation: .powerUp,
        release: Move(name: "bull rush", animation: .bullRush, lock: 1.0, lunge: 1650)
            .hitting(Hit(start: 0.05, duration: 0.85, reach: -20...240, depth: 100, heightTolerance: 140, damage: 110, knockback: 520, launch: 300, stun: 1.0, vsHeavy: 1.5))
            .emphasized(.special),
        gainPerDamageDealt: 0.0056)

    /// Quick to charge: a spin that hits everything around you three times, pinning them in place, the last blow launching.
    static let whirlwind = Special(
        name: "whirlwind", chargeTime: 0.6, chargeAnimation: .powerUp,
        release: Move(name: "whirlwind", animation: .whirlwind, lock: 0.75, plant: true)
            .hitting(Hit(start: 0.08, duration: 0.1, reach: -190...190, depth: 120, heightTolerance: 220, damage: 9, knockback: 40, stun: 0.5, vsHeavy: 2),
                     Hit(start: 0.26, duration: 0.1, reach: -190...190, depth: 120, heightTolerance: 220, damage: 9, knockback: 40, stun: 0.5, vsHeavy: 2),
                     Hit(start: 0.44, duration: 0.12, reach: -200...200, depth: 120, heightTolerance: 220, damage: 13, knockback: 600, launch: 520, stun: 0.8, vsHeavy: 3))
            .emphasized(.special),
        gainPerDamageDealt: 0.0088)

    /// Enzo's: a quick-charging ground pound that fills fastest from damage he takes. Reuses Cloak's rage slam pose for now.
    static let vendetta = Special(
        name: "vendetta", chargeTime: 0.8, chargeAnimation: .powerUp,
        release: Move(name: "vendetta", animation: .rageSlam, lock: 0.75, plant: true)
            .hitting(Hit(start: 0.19, duration: 0.12, reach: -330...330, depth: 170, heightTolerance: 400, damage: 40, knockback: 700, launch: 600, stun: 0.9, vsHeavy: 3))
            .emphasized(.special),
        gainPerDamageDealt: 0.005, gainPerDamageTaken: 0.0055)
}
