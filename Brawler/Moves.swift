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

/// Pure data. To add a move, add one row to `MoveTable.rows`.
struct Move {
    let name: String
    var animation: CharacterAnimation? = nil
    var lock: TimeInterval = 0       // grounded: how long the action holds before locomotion resumes
    var lunge: CGFloat = 0           // forward speed burst (pt/s); never reduces current speed
    var jumpHeight: CGFloat = 0      // > 0 launches into the air (peak height in pt)
    var jumpRise = JumpTuning.rise
    var jumpFall = JumpTuning.fall
    var jumpHang = JumpTuning.hang
    var slam = false                 // dive to the ground
    var brake: TimeInterval = 0      // > 0 forces a hard stop for this long (skid)
    var power: CGFloat = 1           // relative damage / knockback (used once hit detection exists)
    var cancelAt = ComboTuning.cancelAt
    var window = ComboTuning.window
}

enum MoveTable {
    private struct Key: Hashable { let context: MoveContext; let trigger: Trigger }

    // Back-swipe while grounded is intentionally absent: an open slot for future specials.
    // Animations marked (placeholder) reuse existing poses until dedicated ones exist.
    private static let rows: [(MoveContext, Trigger, Move)] = [
        // Standing / slow walk
        (.grounded, .tap,     Move(name: "punch",         animation: .jab,  lock: 0.28)),
        (.grounded, .up,      Move(name: "small jump",    jumpHeight: 170)),
        (.grounded, .down,    Move(name: "pick up",       lock: 0.3)),                          // (placeholder) no item system yet
        (.grounded, .forward, Move(name: "heavy attack",  animation: .hook, lock: 0.5, lunge: 140)),

        // Fully running
        (.running,  .tap,     Move(name: "dash attack",   animation: .jab,  lock: 0.3, lunge: 560)),
        (.running,  .up,      Move(name: "big jump",      lunge: 560, jumpHeight: 230, jumpRise: 0.24, jumpFall: 0.34, jumpHang: 0.2)),
        (.running,  .forward, powerDash),
        (.running,  .back,    Move(name: "skid stop",     animation: .land, lock: 0.3, brake: 0.3)), // (placeholder) land pose

        // In the air
        (.airborne, .down,    Move(name: "air slam",      animation: .slam, slam: true, power: 1.0)),
    ]

    // Combo links: after `from` (by move name), `trigger` gives the next move. Input-driven: no hit required.
    private static let powerDash = Move(name: "power dash",    animation: .hook, lock: 0.5, lunge: 760)

    /// Running ground slam. Same shockwave and knockback as the air slam, a bit less powerful.
    private static let groundSmash = Move(name: "ground smash", animation: .smash, lock: 0.62, brake: 0.4, power: 0.7)

    private static let uppercut = Move(name: "uppercut", animation: .uppercut, jumpHeight: 260, jumpRise: 0.22, jumpFall: 0.34, jumpHang: 0.26)

    /// Landing from an air slam: a short recovery during which the combo chain is open from the first frame.
    static let slamLanding = Move(name: "slam landing", animation: .slamLand, lock: 0.3, cancelAt: 0)

    private static let chains: [(from: String, trigger: Trigger, move: Move)] = [
        ("punch",      .tap,  Move(name: "punch 2",      animation: .jab,  lock: 0.28, lunge: 80)),
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
