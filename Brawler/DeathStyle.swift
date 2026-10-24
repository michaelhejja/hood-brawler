import Foundation

/// How an enemy dies. Rolled once, on the killing blow. Everything that isn't an alternate is the standard death (knocked flat).
/// To rebalance, change the numbers below: `everyone` applies to every enemy, `extra` adds to it by name. Keep each enemy's total under 1.
enum DeathStyle {
    case standard
    case kneel          // drops to its knees, sways, then falls forward on its face (ground kills only)
    case breakApart     // every part flies off on its own (skeletons)

    private static let everyone: [(DeathStyle, Double)] = [(.kneel, 0.15)]
    private static let extra: [String: [(DeathStyle, Double)]] = [
        "skeleton": [(.breakApart, 0.3)],
        "giant skeleton": [(.breakApart, 0.5)],
    ]

    /// `canKneel` is false when the killing blow launches the enemy or it is in the air: a kneel needs a grounded body.
    /// Launch flags: `-bonebreak` forces the break-apart on skeletons, `-kneel` forces the kneel.
    static func roll(name: String, canKneel: Bool) -> DeathStyle {
        let flags = ProcessInfo.processInfo.arguments
        let table = (everyone + (extra[name] ?? [])).filter { canKneel || $0.0 != .kneel }
        if flags.contains("-bonebreak"), table.contains(where: { $0.0 == .breakApart }) { return .breakApart }
        if flags.contains("-kneel"), canKneel { return .kneel }
        var r = Double.random(in: 0..<1)
        for (style, chance) in table {
            if r < chance { return style }
            r -= chance
        }
        return .standard
    }
}
