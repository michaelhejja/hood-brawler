import Foundation
import CoreGraphics

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
    var jumpVZ: CGFloat = 0          // > 0 launches into the air
    var slam = false                 // dive to the ground
    var brake: TimeInterval = 0      // > 0 forces a hard stop for this long (skid)
}

enum MoveTable {
    private struct Key: Hashable { let context: MoveContext; let trigger: Trigger }

    // Back-swipe while grounded is intentionally absent: an open slot for future specials.
    // Animations marked (placeholder) reuse existing poses until dedicated ones exist.
    private static let rows: [(MoveContext, Trigger, Move)] = [
        // Standing / slow walk
        (.grounded, .tap,     Move(name: "punch",         animation: .attack, lock: 0.35)),
        (.grounded, .up,      Move(name: "small jump",    jumpVZ: 800)),
        (.grounded, .down,    Move(name: "pick up",       lock: 0.3)),                          // (placeholder) no item system yet
        (.grounded, .forward, Move(name: "heavy attack",  animation: .attack, lock: 0.5, lunge: 140)),

        // Fully running
        (.running,  .tap,     Move(name: "dash attack",   animation: .attack, lock: 0.4, lunge: 560)),
        (.running,  .up,      Move(name: "big jump",      lunge: 560, jumpVZ: 950)),
        (.running,  .forward, Move(name: "power dash",    animation: .attack, lock: 0.5, lunge: 760)),
        (.running,  .back,    Move(name: "skid stop",     animation: .land, lock: 0.3, brake: 0.3)), // (placeholder) land pose

        // In the air
        (.airborne, .down,    Move(name: "air slam",      animation: .fall, slam: true)),
    ]

    private static let table: [Key: Move] = Dictionary(
        uniqueKeysWithValues: rows.map { (Key(context: $0.0, trigger: $0.1), $0.2) })

    static func move(_ context: MoveContext, _ trigger: Trigger) -> Move? {
        table[Key(context: context, trigger: trigger)]
    }
}
