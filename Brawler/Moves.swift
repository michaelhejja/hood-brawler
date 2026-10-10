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
}

extension Hit {
    /// Strong hits (launchers, spikes, heavy knockback) knock the weapon out of the victim's hand.
    var isStrong: Bool { launch != 0 || knockback >= 500 }

    static let jab        = Hit(start: 0.05, duration: 0.09, reach: 0...115, damage: 6, knockback: 140, stun: 0.25)
    static let hook       = Hit(start: 0.10, duration: 0.10, reach: 0...135, damage: 12, knockback: 380, stun: 0.4)
    static let dashJab    = Hit(start: 0.04, duration: 0.14, reach: 0...150, damage: 8, knockback: 320, stun: 0.3)
    static let dashHook   = Hit(start: 0.08, duration: 0.18, reach: 0...160, damage: 16, knockback: 520, stun: 0.45)
    static let uppercut   = Hit(start: 0.07, duration: 0.14, reach: -10...110, heightTolerance: 300, damage: 14, knockback: 80, launch: 850, stun: 0.4)
    static let diveSlam   = Hit(start: 0, duration: 1.0, reach: 0...90, depth: 40, heightTolerance: 140, damage: 10, knockback: 250, launch: -900, stun: 0.4)
    static let shockwave  = Hit(start: 0, duration: 0.12, reach: -170...170, depth: 60, heightTolerance: 80, damage: 14, knockback: 650, launch: 450, stun: 0.5)
    static let smash      = Hit(start: 0.25, duration: 0.12, reach: 0...175, depth: 50, heightTolerance: 120, damage: 18, knockback: 700, launch: 350, stun: 0.5)
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
    var brake: TimeInterval = 0      // > 0 forces a hard stop for this long (skid)
    var power: CGFloat = 1           // relative damage / knockback (used once hit detection exists)
    var cancelAt = ComboTuning.cancelAt
    var window = ComboTuning.window
    var hits: [Hit] = []
    var usesWeapon = false           // damage scales with the equipped weapon (bare-handed is weaker)
    var grab: TimeInterval = -1      // >= 0: picks up whatever is at the fighter's feet this long into the move

    func hitting(_ h: Hit...) -> Move { var m = self; m.hits = h; return m }
    var armed: Move { var m = self; m.usesWeapon = true; return m }
}

enum MoveTable {
    private struct Key: Hashable { let context: MoveContext; let trigger: Trigger }

    // Back-swipe while grounded is intentionally absent: an open slot for future specials.
    // Animations marked (placeholder) reuse existing poses until dedicated ones exist.
    private static let rows: [(MoveContext, Trigger, Move)] = [
        // Standing / slow walk
        (.grounded, .tap,     Move(name: "punch",         animation: .jab,  lock: 0.28).hitting(.jab)),
        (.grounded, .up,      Move(name: "small jump",    jumpHeight: 170)),
        (.grounded, .down,    Move(name: "pick up",       animation: .pickup, lock: 0.45, grab: 0.2)),
        (.grounded, .forward, Move(name: "heavy attack",  animation: .hook, lock: 0.5, lunge: 140).hitting(.hook).armed),

        // Fully running
        (.running,  .tap,     Move(name: "dash attack",   animation: .jab,  lock: 0.3, lunge: 560).hitting(.dashJab)),
        (.running,  .up,      Move(name: "big jump",      lunge: 560, jumpHeight: 230, jumpRise: 0.24, jumpFall: 0.34, jumpHang: 0.2)),
        (.running,  .forward, powerDash),
        (.running,  .back,    Move(name: "skid stop",     animation: .land, lock: 0.3, brake: 0.3)), // (placeholder) land pose

        // In the air
        (.airborne, .down,    Move(name: "air slam",      animation: .slam, slam: true, power: 1.0).hitting(.diveSlam).armed),
    ]

    // Combo links: after `from` (by move name), `trigger` gives the next move. Input-driven: no hit required.
    private static let powerDash = Move(name: "power dash",    animation: .hook, lock: 0.5, lunge: 760).hitting(.dashHook).armed

    /// Running ground slam. Same shockwave and knockback as the air slam, a bit less powerful.
    static let groundSmash = Move(name: "ground smash", animation: .smash, lock: 0.62, advance: 150, advanceStart: 0, advanceDuration: 0.27, brake: 0.4, power: 0.7).hitting(.smash).armed

    private static let uppercut = Move(name: "uppercut", animation: .uppercut, jumpHeight: 260, jumpRise: 0.22, jumpFall: 0.34, jumpHang: 0.26).hitting(.uppercut).armed

    /// Landing from an air slam: a short recovery during which the combo chain is open from the first frame.
    static let slamLanding = Move(name: "slam landing", animation: .slamLand, lock: 0.3, cancelAt: 0).hitting(.shockwave).armed

    private static let chains: [(from: String, trigger: Trigger, move: Move)] = [
        ("punch",      .tap,  Move(name: "punch 2",      animation: .jab,  lock: 0.28, lunge: 80).hitting(.jab)),
        ("punch 2",      .up,   uppercut),                       // standing-combo entry
        ("heavy attack", .up,   uppercut),                       // any strong attack ...
        ("power dash",   .up,   uppercut),                       // ... including after a full run
        ("slam landing", .forward, powerDash),                   // juggle: slam, then straight back into a dash
        ("slam landing", .up,   uppercut),                       // ... or launch them
        ("power dash",  .down, groundSmash),
        ("dash attack", .down, groundSmash),
    ]
    private static let chainTable: [String: Move] = Dictionary(
        uniqueKeysWithValues: chains.map { ("\($0.from)|\($0.trigger.rawValue)", $0.move) })

    static func chain(from name: String, _ trigger: Trigger) -> Move? {
        chainTable["\(name)|\(trigger.rawValue)"]
    }

    private static let table: [Key: Move] = Dictionary(
        uniqueKeysWithValues: rows.map { (Key(context: $0.0, trigger: $0.1), $0.2) })

    static func move(_ context: MoveContext, _ trigger: Trigger) -> Move? {
        table[Key(context: context, trigger: trigger)]
    }
}
