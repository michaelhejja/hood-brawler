import SwiftUI
import SpriteKit
import GameController

/// Per-level horizontal bounds. The world spans minX...maxX.
/// The camera stops at the ends, so the hero walks toward the edge instead of staying centered.
struct LevelConfig {
    var minX: CGFloat = 0
    var maxX: CGFloat = 4000
    var heroInset: CGFloat = 40     // how close the hero's origin may get to either world edge
}

// MARK: - Level data

enum EnemyKind { case skeleton, archer, giant, wyrm, necromancer, bat, batKing, goblin, doppel, forgeKing, wraith, wizard, archmage, demon }
enum Theme { case forest, cave, mirror, forge, graveyard, snow }
enum Side { case left, right }

/// One enemy in a wave. Enters from just off-screen on `side`, `delay` seconds after the wave starts.
struct Spawn {
    var kind: EnemyKind
    var side: Side
    var lane: CGFloat?
    var delay: TimeInterval
    var tier: CGFloat                 // survival-style toughness boost: 0 = the base enemy
    var shield: Bool                  // carries a shield: blocks frontal hits, drops it when killed
    var hammer: Bool                  // carries a hammer: keeps its distance, then slams
    var lantern: Bool                 // carries a lantern: lights its surroundings in dark levels, until it dies
    init(_ kind: EnemyKind = .skeleton, _ side: Side, lane: CGFloat? = nil, delay: TimeInterval = 0, tier: CGFloat = 0, shield: Bool = false, hammer: Bool = false, lantern: Bool = false) {
        self.kind = kind; self.side = side; self.lane = lane; self.delay = delay; self.tier = tier; self.shield = shield; self.hammer = hammer; self.lantern = lantern
    }
}

/// A group that arrives together. The next wave starts ~1s after the last enemy of this one goes down.
struct Wave {
    var spawns: [Spawn]
    var line: String? = nil           // first enemy to reach the screen says this
}

/// Walk past `triggerX` and the camera locks, the waves play out, then the lock lifts and "GO" shows.
struct Encounter {
    var triggerX: CGFloat
    var waves: [Wave]
    var endsLevel = false             // clearing this one completes the level
    var leadsTo: Int? = nil           // clearing this opens a portal to that area (the way out of a detour)
    var arrival = ""                  // ... arriving at this entry point
}

/// An enemy already standing in the world, ready to chase you when you get near.
struct Placed {
    var kind: EnemyKind = .skeleton
    var x: CGFloat
    var lane: CGFloat
    var tier: CGFloat = 0
    var shield = false
    var hammer = false
    var lantern = false
}

struct Lamp {
    var x: CGFloat
    var lane: CGFloat = 95
    var radius: CGFloat = 270
}

struct Prop {
    enum Kind { case crate(PickupKind?), altar(PickupKind?), scenery(Crate.Style), pickup(PickupKind), door(Int), areaDoor(area: Int, arrival: String, name: String) }
    var kind: Kind
    var x: CGFloat
    var lane: CGFloat
    static func crate(_ x: CGFloat, _ lane: CGFloat, holding: PickupKind? = nil) -> Prop { Prop(kind: .crate(holding), x: x, lane: lane) }
    /// A shrub: breaks in one hit, can be walked through. Withered ones suit the graveyard.
    static func bush(_ x: CGFloat, _ lane: CGFloat, withered: Bool = false) -> Prop { Prop(kind: .scenery(withered ? .witheredBush : .bush), x: x, lane: lane) }
    /// Any smashable scenery: `.bush`, `.witheredBush`, `.frozenBush`, `.crystal` or `.charredBush`.
    static func scenery(_ style: Crate.Style, _ x: CGFloat, _ lane: CGFloat) -> Prop { Prop(kind: .scenery(style), x: x, lane: lane) }
    /// A stack of stones with an idol on top. Breaks like a crate, but tougher.
    static func altar(_ x: CGFloat, _ lane: CGFloat, holding: PickupKind? = nil) -> Prop { Prop(kind: .altar(holding), x: x, lane: lane) }
    static func pickup(_ kind: PickupKind, _ x: CGFloat, _ lane: CGFloat) -> Prop { Prop(kind: .pickup(kind), x: x, lane: lane) }
    static func door(_ level: Int, _ x: CGFloat, _ lane: CGFloat) -> Prop { Prop(kind: .door(level), x: x, lane: lane) }
    /// A door to another area of the same level (a cave, a room). `arrival` names the entry point in that area.
    static func areaDoor(_ area: Int, _ arrival: String, _ x: CGFloat, _ lane: CGFloat, _ name: String) -> Prop {
        Prop(kind: .areaDoor(area: area, arrival: arrival, name: name), x: x, lane: lane)
    }
}

/// A line of dialogue from the world itself: appears ahead of the hero when he passes `x`.
/// A line the hero says when they walk past `x`. The bubble follows the hero (`lane` is no longer used).
struct Say {
    var x: CGFloat
    var text: String
    var lane: CGFloat = 120
}

struct LevelData {
    var name: String
    var width: CGFloat
    var heroStart: CGFloat = 300
    var props: [Prop] = []
    var placed: [Placed] = []
    var says: [Say] = []
    var encounters: [Encounter] = []
    var theme: Theme = .forest
    var hazards: [LavaBand] = []               // floor strips that burn on a timer
    var lamps: [Lamp] = []                     // lamp posts: pools of light in dark levels
    var arrivals: [String: CGFloat] = [:]      // named entry points: where the hero appears when a door leads here
    var areas: [LevelData] = []                // more areas of this level: area 0 is the level itself, then these in order
    func area(_ i: Int) -> LevelData { i == 0 ? self : areas[i - 1] }
}

enum Levels {
    static let all: [LevelData] = [boneRoad, gravewood, boneMountain, mirrorHall, foundry, blackout, chillOut, ashlands]

    /// Scatters bushes along a stretch of a level, in repeatable positions, keeping clear of everything already placed.
    static func withBushes(_ props: [Prop], over range: ClosedRange<CGFloat>, every: CGFloat, seed: Int, withered: Bool = false) -> [Prop] {
        withScenery(props, over: range, every: every, seed: seed, style: withered ? .witheredBush : .bush)
    }

    /// The same scatter for any scenery: pick the style to match the level's theme (forest `.bush`, graveyard `.witheredBush`, snow `.frozenBush`, cave `.crystal`, ashlands `.charredBush`).
    static func withScenery(_ props: [Prop], over range: ClosedRange<CGFloat>, every: CGFloat, seed: Int, style: Crate.Style) -> [Prop] {
        var state = UInt64(truncatingIfNeeded: seed) &* 6364136223846793005 &+ 1442695040888963407
        func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((state >> 33) % 10_000) / 10_000
        }
        var out = props
        var x = range.lowerBound
        while x < range.upperBound {
            let px = x + next() * every * 0.6, lane = 30 + next() * 140
            if !props.contains(where: { abs($0.x - px) < 110 }) { out.append(.scenery(style, px, lane)) }
            x += every * (0.7 + next() * 0.6)
        }
        return out
    }

    /// The walk-around level select: one door per level, in order. Add a level to `all` and its door appears.
    static func doorX(_ level: Int) -> CGFloat { 900 + CGFloat(level) * 480 }
    static var hub: LevelData {
        LevelData(name: "Hub", width: doorX(all.count) + 400, heroStart: 300,
                  props: all.indices.map { Prop.door($0, doorX($0), 110) })
    }

    /// Level 1. No tutorials: each idea is met once, safely, before it matters.
    /// Rocks, then a lone skeleton, a crate, a two-sided brawl, a weapon, archers, a giant, and a finale (stand-in for the Bone Wyrm).
    static let boneRoad = LevelData(
        name: "Bone Road", width: 6200, heroStart: 300,
        props: Levels.withBushes([
            .pickup(.weapon(Weapons.rock), 520, 80), .pickup(.weapon(Weapons.rock), 720, 140),
            .crate(1500, 100, holding: .item(Items.food)),
            .crate(1800, 60), .crate(1800, 160),                                   // empty crates: a wall with a gap
            .pickup(.weapon(Weapons.axe), 2300, 120),
            .crate(2550, 150, holding: .weapon(Weapons.spear)), .crate(2700, 70, holding: .weapon(Weapons.bomb)),
            .crate(3350, 100, holding: .weapon(Weapons.bow)), .crate(3550, 140, holding: .item(Items.quiver)),
            .crate(4000, 90, holding: .item(Items.food)), .pickup(.weapon(Weapons.rock), 4050, 150),
            .crate(5100, 110, holding: .item(Items.food)), .pickup(.weapon(Weapons.spear), 5200, 70),
        ], over: 420...5900, every: 250, seed: 11),
        placed: [Placed(x: 1050, lane: 110)],
        says: [Say(x: 600, text: "...another one wanders in."),
               Say(x: 3900, text: "Turn back. The road ends here.")],
        encounters: [
            Encounter(triggerX: 2000, waves: [
                Wave(spawns: [Spawn(.skeleton, .left), Spawn(.skeleton, .right, delay: 0.8)], line: "Fresh meat!")]),
            Encounter(triggerX: 3000, waves: [
                Wave(spawns: [Spawn(.skeleton, .left), Spawn(.skeleton, .right, delay: 0.6), Spawn(.skeleton, .left, delay: 1.4)]),
                Wave(spawns: [Spawn(.archer, .right), Spawn(.skeleton, .left, delay: 1.0)], line: "Stay back and shoot!")]),
            Encounter(triggerX: 4300, waves: [
                Wave(spawns: [Spawn(.skeleton, .left, tier: 0.2), Spawn(.goblin, .right, delay: 0.5, tier: 0.2), Spawn(.archer, .right, delay: 1.5, tier: 0.2)]),
                Wave(spawns: [Spawn(.giant, .right), Spawn(.skeleton, .left, delay: 2.0, tier: 0.2), Spawn(.skeleton, .left, delay: 3.0, tier: 0.2)],
                     line: "RAAAAGH!")]),
            Encounter(triggerX: 5500, waves: [
                Wave(spawns: [Spawn(.goblin, .left, tier: 0.4), Spawn(.skeleton, .right, tier: 0.4), Spawn(.archer, .left, delay: 1.0, tier: 0.4), Spawn(.archer, .right, delay: 1.0, tier: 0.4)]),
                Wave(spawns: [Spawn(.wyrm, .right)])],
                      endsLevel: true),
        ])

    /// Level 2: the first level with more than one area. The road ends at a cave; the only way on is through it.
    /// Areas: 0 = the road in, 1 = the cave (mini-boss), 2 = the road out (and the Necromancer).
    static let gravewood = LevelData(
        name: "Gravewood", width: 2300, heroStart: 300,
        props: Levels.withBushes([
            .pickup(.weapon(Weapons.rock), 560, 90), .pickup(.weapon(Weapons.spear), 700, 150),
            .crate(1300, 100, holding: .item(Items.food)),
            .crate(1650, 60), .crate(1650, 160),
            .areaDoor(1, "in", 2080, 110, "Cave"),
        ], over: 380...2200, every: 230, seed: 23),
        placed: [Placed(x: 1000, lane: 110, tier: 0.1)],
        says: [Say(x: 1500, text: "The road ends at a cave...")],
        encounters: [
            Encounter(triggerX: 1100, waves: [
                Wave(spawns: [Spawn(.skeleton, .left, tier: 0.1), Spawn(.skeleton, .right, delay: 0.6, tier: 0.1), Spawn(.archer, .right, delay: 1.4, tier: 0.1)])]),
        ],
        areas: [graveCave, graveRoadOut])

    /// Gravewood, past the cave: supplies, a hard fight, then the Necromancer.
    static let graveRoadOut = LevelData(
        name: "Gravewood", width: 3000, heroStart: 300,
        props: [
            .crate(500, 110, holding: .weapon(Weapons.bow)), .pickup(.weapon(Weapons.rock), 620, 60),
            .crate(1300, 90, holding: .item(Items.quiver)), .crate(1300, 170, holding: .item(Items.food)),
        ],
        encounters: [
            Encounter(triggerX: 900, waves: [
                Wave(spawns: [Spawn(.skeleton, .left, tier: 0.3, shield: true), Spawn(.goblin, .right, tier: 0.3), Spawn(.skeleton, .left, delay: 1.0, tier: 0.3), Spawn(.archer, .right, delay: 1.5, tier: 0.3)]),
                Wave(spawns: [Spawn(.giant, .right, tier: 0.3), Spawn(.skeleton, .left, delay: 2.0, tier: 0.3)], line: "RAAAAGH!")]),
            Encounter(triggerX: 2000, waves: [
                Wave(spawns: [Spawn(.necromancer, .right)])], endsLevel: true),
        ],
        arrivals: ["start": 300])

    /// Gravewood's cave: supplies, and a fight that has to be won to feel safe taking them.
    static let graveCave = LevelData(
        name: "Cave", width: 1900, heroStart: 320,
        props: Levels.withScenery([
            .crate(600, 70, holding: .weapon(Weapons.axe)), .crate(600, 160),
            .crate(1150, 100, holding: .item(Items.food)), .crate(1350, 70, holding: .weapon(Weapons.spear)),
            .pickup(.weapon(Weapons.rock), 1500, 120), .pickup(.item(Items.quiver), 1650, 160),
        ], over: 380...1800, every: 260, seed: 61, style: .crystal),
        says: [Say(x: 450, text: "Bones everywhere...")],
        encounters: [
            Encounter(triggerX: 850, waves: [
                Wave(spawns: [Spawn(.skeleton, .left, tier: 0.3, shield: true), Spawn(.goblin, .right, tier: 0.3), Spawn(.goblin, .right, delay: 1.0, tier: 0.3)]),
                Wave(spawns: [Spawn(.archer, .left, tier: 0.3), Spawn(.archer, .right, delay: 0.5, tier: 0.3), Spawn(.skeleton, .left, delay: 1.5, tier: 0.3)], line: "You'll never leave!"),
                Wave(spawns: [Spawn(.giant, .right, tier: 0.4), Spawn(.skeleton, .left, delay: 2.5, tier: 0.3)], line: "GRAAAH!")],
                      leadsTo: 2, arrival: "start"),
        ],
        theme: .cave,
        arrivals: ["in": 320])

    /// Level 3: a climb in beats, ending on the Bat King. Reuses the cave look for now.
    /// Areas: 0 = foothills and switchback, 1 = the cave passage (detour with supplies), 2 = the ridge and the summit.
    static let boneMountain = LevelData(
        name: "Bone Mountain", width: 2900, heroStart: 300,
        props: Levels.withScenery([
            .pickup(.weapon(Weapons.rock), 520, 80), .crate(800, 100, holding: .item(Items.food)),
            .crate(1900, 70, holding: .weapon(Weapons.bow)), .crate(2050, 150, holding: .item(Items.quiver)),
            .crate(1500, 150, holding: .weapon(Weapons.shield)), .crate(1700, 70, holding: .weapon(Weapons.hammer)),
            .crate(2300, 100),
            .areaDoor(1, "in", 2740, 110, "Cave"),
        ], over: 420...2600, every: 300, seed: 71, style: .crystal),
        placed: [Placed(x: 1000, lane: 110, tier: 0.4)],
        says: [Say(x: 420, text: "Something's up there..."), Say(x: 1250, text: "Stay low. Strike high.")],
        encounters: [
            // Foothills: one bat, alone, so the hover and the "!" are easy to read.
            Encounter(triggerX: 1300, waves: [Wave(spawns: [Spawn(.bat, .right, tier: 0.4)])]),
            // Switchback: ground and air together.
            Encounter(triggerX: 2200, waves: [
                Wave(spawns: [Spawn(.goblin, .left, tier: 0.4), Spawn(.skeleton, .right, delay: 0.6, tier: 0.4, shield: true)]),
                Wave(spawns: [Spawn(.bat, .left, tier: 0.4), Spawn(.bat, .right, delay: 0.8, tier: 0.4), Spawn(.skeleton, .right, delay: 1.5, tier: 0.4)])]),
        ],
        theme: .cave,
        areas: [boneCave, boneRidge])

    /// Bone Mountain's cave: a cramped fight with a spear or axe waiting on the other side of it.
    static let boneCave = LevelData(
        name: "Cave", width: 1700, heroStart: 320,
        props: Levels.withScenery([
            .crate(560, 70, holding: .weapon(Weapons.spear)), .crate(700, 160, holding: .item(Items.food)),
            .crate(1150, 100, holding: .weapon(Weapons.axe)), .pickup(.item(Items.food), 1400, 150),
        ], over: 380...1600, every: 260, seed: 67, style: .crystal),
        says: [Say(x: 450, text: "Wings in the dark...")],
        encounters: [
            Encounter(triggerX: 800, waves: [
                Wave(spawns: [Spawn(.goblin, .left, tier: 0.5), Spawn(.skeleton, .right, tier: 0.5, shield: true), Spawn(.bat, .right, delay: 1.0, tier: 0.5)]),
                Wave(spawns: [Spawn(.bat, .left, tier: 0.5), Spawn(.bat, .right, delay: 0.6, tier: 0.5), Spawn(.skeleton, .left, delay: 1.5, tier: 0.5, hammer: true)], line: "Screech!")],
                      leadsTo: 2, arrival: "start"),
        ],
        theme: .cave,
        arrivals: ["in": 320])

    /// Bone Mountain, past the cave: archers and bats, a giant, food, then the Bat King at the summit.
    static let boneRidge = LevelData(
        name: "Bone Mountain", width: 3400, heroStart: 300,
        props: Levels.withScenery([
            .crate(450, 100, holding: .item(Items.food)), .pickup(.weapon(Weapons.rock), 600, 60),
            .crate(1500, 80, holding: .item(Items.quiver)), .crate(1500, 160, holding: .item(Items.food)),
            .crate(2100, 110, holding: .item(Items.food)),
        ], over: 420...3300, every: 300, seed: 73, style: .crystal),
        says: [Say(x: 2000, text: "The summit. Something waits.")],
        encounters: [
            // Ridge: one archer with bats, then a giant with bats behind it.
            Encounter(triggerX: 1000, waves: [
                Wave(spawns: [Spawn(.skeleton, .left, tier: 0.5, shield: true), Spawn(.archer, .right, tier: 0.5), Spawn(.bat, .right, delay: 1.2, tier: 0.5)]),
                Wave(spawns: [Spawn(.giant, .right, tier: 0.5), Spawn(.bat, .left, delay: 2.0, tier: 0.5), Spawn(.goblin, .left, delay: 2.5, tier: 0.5, hammer: true)], line: "RAAAAGH!")]),
            // Summit: nothing ambient, just him.
            Encounter(triggerX: 2500, waves: [Wave(spawns: [Spawn(.batKing, .right)])], endsLevel: true),
        ],
        theme: .cave,
        arrivals: ["start": 300])

    /// One giant. Launch with `-giant`; add `-gianttest` to script a hero who stands and boxes it.
    static let giantArena = LevelData(
        name: "Giant Test", width: 1334, heroStart: 500,
        encounters: [Encounter(triggerX: 400, waves: [Wave(spawns: [Spawn(.giant, .right)])], endsLevel: true)],
        theme: .cave)

    /// Skeletons and an archer, all from the right. Launch with `-shieldtest` to script a hero who guards, then releases.
    static let shieldArena = LevelData(
        name: "Shield Test", width: 1334, heroStart: 500,
        encounters: [Encounter(triggerX: 400, waves: [Wave(spawns: [Spawn(.skeleton, .right), Spawn(.skeleton, .right, delay: 1.5), Spawn(.archer, .right, delay: 1.0)])], endsLevel: true)],
        theme: .cave)

    /// Two goblins and a skeleton, side by side. Launch with `-goblins`.
    static let goblinArena = LevelData(
        name: "Goblin Test", width: 1334, heroStart: 500,
        encounters: [Encounter(triggerX: 400, waves: [Wave(spawns: [Spawn(.goblin, .right), Spawn(.skeleton, .right, delay: 0.3), Spawn(.goblin, .left, delay: 0.6)])], endsLevel: true)],
        theme: .cave)

    /// A shielded skeleton, a shielded goblin and a plain skeleton. Launch with `-shields`; add `-shieldfoe` to script a hero who boxes them, then air-strikes.
    static let shieldFoeArena = LevelData(
        name: "Shield Foes", width: 1334, heroStart: 500,
        encounters: [Encounter(triggerX: 400, waves: [Wave(spawns: [Spawn(.skeleton, .right, shield: true), Spawn(.goblin, .right, delay: 0.5, shield: true), Spawn(.skeleton, .right, delay: 1.0)])], endsLevel: true)],
        theme: .cave)

    /// A hammer skeleton, then a hammer goblin. Launch with `-hammers`; add `-hammer` to start with one yourself.
    static let hammerArena = LevelData(
        name: "Hammer Test", width: 1334, heroStart: 500,
        encounters: [Encounter(triggerX: 400, waves: [Wave(spawns: [Spawn(.skeleton, .right, hammer: true), Spawn(.goblin, .right, delay: 4, hammer: true)])], endsLevel: true)],
        theme: .cave)

    /// Three skeletons around the hero. Launch with `-herotest` (and `-hero 1`) to fire the special on them.
    static let heroArena = LevelData(
        name: "Hero Test", width: 1334, heroStart: 667,
        encounters: [Encounter(triggerX: 600, waves: [Wave(spawns: [Spawn(.skeleton, .left), Spawn(.skeleton, .right, delay: 0.2), Spawn(.skeleton, .left, delay: 0.4), Spawn(.goblin, .right, delay: 0.6)])], endsLevel: true)],
        theme: .cave)

    /// Level 4: shadows step out of the glass, then your own reflection. Three beats, then the Doppelgänger.
    static let mirrorHall = LevelData(
        name: "Mirror Hall", width: 3600, heroStart: 300,
        props: [
            .crate(520, 100, holding: .item(Items.food)),
            .crate(900, 70, holding: .weapon(Weapons.hammer)), .crate(1050, 150, holding: .weapon(Weapons.shield)),
            .crate(1900, 100, holding: .item(Items.food)),
            .crate(2500, 80, holding: .item(Items.food)), .crate(2650, 150, holding: .item(Items.food)),
        ],
        placed: [Placed(x: 800, lane: 110, tier: 0.5)],
        says: [Say(x: 400, text: "Something moves in the glass..."), Say(x: 2850, text: "...is that me?")],
        encounters: [
            Encounter(triggerX: 1300, waves: [
                Wave(spawns: [Spawn(.skeleton, .left, tier: 0.5), Spawn(.goblin, .right, delay: 0.5, tier: 0.5)]),
                Wave(spawns: [Spawn(.skeleton, .left, tier: 0.5, shield: true), Spawn(.goblin, .right, delay: 0.6, tier: 0.5), Spawn(.archer, .right, delay: 1.2, tier: 0.5)])]),
            Encounter(triggerX: 2200, waves: [
                Wave(spawns: [Spawn(.skeleton, .left, tier: 0.6, hammer: true), Spawn(.goblin, .right, delay: 0.6, tier: 0.6), Spawn(.bat, .right, delay: 1.2, tier: 0.6)]),
                Wave(spawns: [Spawn(.giant, .right, tier: 0.5), Spawn(.skeleton, .left, delay: 1.5, tier: 0.6, shield: true)], line: "RAAAAGH!")]),
            Encounter(triggerX: 3000, waves: [Wave(spawns: [Spawn(.doppel, .right)])], endsLevel: true),
        ],
        theme: .mirror)

    /// Just the Doppelgänger, in a one-screen hall. Launch with `-doppel`; add `-doppeltest` to script a hero who spams attacks.
    static let doppelArena = LevelData(
        name: "Doppelganger Test", width: 1334, heroStart: 400,
        encounters: [Encounter(triggerX: 300, waves: [Wave(spawns: [Spawn(.doppel, .right)])], endsLevel: true)],
        theme: .mirror)

    static let foundryLava: [LavaBand] = [
        LavaBand(minY: 15, maxY: 70, period: 7, warn: 1.2, active: 1.8, offset: 0),
        LavaBand(minY: 135, maxY: 190, period: 7, warn: 1.2, active: 1.8, offset: 3.5),     // takes turns with the first; the middle strip stays safe
    ]

    /// Level 5: goblins at the forge, with a lava floor. Hazards come in slowly, then every fight happens on them.
    static let foundry = LevelData(
        name: "The Foundry", width: 3800, heroStart: 300,
        props: [
            .crate(520, 100, holding: .item(Items.food)),
            .crate(1150, 70, holding: .weapon(Weapons.hammer)), .crate(1300, 150, holding: .item(Items.food)),
            .crate(1950, 100, holding: .weapon(Weapons.shield)),
            .crate(2650, 80, holding: .item(Items.food)), .crate(2800, 150, holding: .item(Items.food)),
        ],
        placed: [Placed(kind: .goblin, x: 1000, lane: 105, tier: 0.5)],
        says: [Say(x: 400, text: "The floor is alive..."), Say(x: 800, text: "Wait for the glow to fade.")],
        encounters: [
            Encounter(triggerX: 1500, waves: [
                Wave(spawns: [Spawn(.goblin, .left, tier: 0.6), Spawn(.goblin, .right, delay: 0.5, tier: 0.6)]),
                Wave(spawns: [Spawn(.goblin, .left, tier: 0.6, shield: true), Spawn(.skeleton, .right, delay: 0.6, tier: 0.6), Spawn(.archer, .right, delay: 1.2, tier: 0.6)])]),
            Encounter(triggerX: 2400, waves: [
                Wave(spawns: [Spawn(.goblin, .left, tier: 0.7, hammer: true), Spawn(.goblin, .right, delay: 0.6, tier: 0.7), Spawn(.bat, .right, delay: 1.2, tier: 0.7)]),
                Wave(spawns: [Spawn(.giant, .right, tier: 0.6), Spawn(.goblin, .left, delay: 1.5, tier: 0.7, shield: true)], line: "RAAAAGH!")]),
            Encounter(triggerX: 3100, waves: [Wave(spawns: [Spawn(.forgeKing, .right)])], endsLevel: true),
        ],
        theme: .forge, hazards: foundryLava)

    /// A one-screen forge floor with the lava bands and nothing else. Launch with `-foundry`; add `-lavatest` to stand the hero in one.
    static let foundryArena = LevelData(
        name: "Foundry Test", width: 1334, heroStart: 500, theme: .forge, hazards: foundryLava)

    /// Just the Forge King on the lava floor. Launch with `-forgeking`; add `-forgetest` for a hero who stands and trades blows.
    static let forgeKingArena = LevelData(
        name: "Forge King Test", width: 1334, heroStart: 400,
        encounters: [Encounter(triggerX: 300, waves: [Wave(spawns: [Spawn(.forgeKing, .right)])], endsLevel: true)],
        theme: .forge)

    /// Level 6: a graveyard at night. Lamps thin out as you go; the altar around beat 2 holds the light blade.
    /// Beats: gate (lit) -> graves (altar, lantern goblins, first bat) -> crypt run (archers in the dark) -> chapel (everything, lit).
    /// The last fight is the Lantern Wraith, who can only be hurt inside your light.
    static let blackout = LevelData(
        name: "The Blackout", width: 5900, heroStart: 300,
        props: Levels.withBushes([
            .crate(600, 90, holding: .item(Items.food)), .crate(1000, 150, holding: .weapon(Weapons.shield)),
            .altar(2050, 100, holding: .weapon(Weapons.lightblade)),
            .crate(2650, 80, holding: .item(Items.food)),
            .crate(3350, 70, holding: .item(Items.quiver)), .crate(3500, 150, holding: .item(Items.food)),
            .crate(4300, 100, holding: .item(Items.food)),
            .crate(5000, 100, holding: .item(Items.food)), .crate(5120, 150, holding: .item(Items.food)),
        ], over: 450...5700, every: 330, seed: 37, withered: true),
        placed: [Placed(x: 900, lane: 110, tier: 0.5), Placed(kind: .goblin, x: 1350, lane: 90, tier: 0.5)],
        says: [Say(x: 380, text: "Stay in the light."), Say(x: 1750, text: "Something glows in that old altar..."), Say(x: 3000, text: "They can see you. Can you see them?"), Say(x: 5000, text: "A lantern, drifting in the dark...")],
        encounters: [
            // Graves: the lamps thin out. Lantern goblins carry their own light, and kill it when they die.
            Encounter(triggerX: 1700, waves: [
                Wave(spawns: [Spawn(.skeleton, .left, tier: 0.6), Spawn(.goblin, .right, delay: 0.5, tier: 0.6, lantern: true)]),
                Wave(spawns: [Spawn(.skeleton, .left, tier: 0.6, shield: true), Spawn(.goblin, .right, delay: 0.6, tier: 0.6, lantern: true), Spawn(.bat, .right, delay: 1.4, tier: 0.6)])]),
            // Crypt run: archers fire from outside your light.
            Encounter(triggerX: 3100, waves: [
                Wave(spawns: [Spawn(.archer, .right, tier: 0.7), Spawn(.skeleton, .left, delay: 0.5, tier: 0.7), Spawn(.goblin, .left, delay: 1.0, tier: 0.7, lantern: true)]),
                Wave(spawns: [Spawn(.archer, .left, tier: 0.7), Spawn(.archer, .right, delay: 0.4, tier: 0.7), Spawn(.bat, .right, delay: 1.2, tier: 0.7), Spawn(.goblin, .left, delay: 1.8, tier: 0.7, hammer: true)])]),
            // Chapel: lit, and everything you know.
            Encounter(triggerX: 4350, waves: [
                Wave(spawns: [Spawn(.giant, .right, tier: 0.7), Spawn(.goblin, .left, delay: 1.5, tier: 0.7, shield: true)], line: "RAAAAGH!"),
                Wave(spawns: [Spawn(.goblin, .left, tier: 0.8, hammer: true), Spawn(.goblin, .right, delay: 0.5, tier: 0.8, lantern: true), Spawn(.bat, .right, delay: 1.2, tier: 0.8), Spawn(.skeleton, .left, delay: 1.5, tier: 0.8, shield: true)])]),
            // The Lantern Wraith: a dark arena, with a pool of lamplight at the entrance.
            Encounter(triggerX: 5300, waves: [Wave(spawns: [Spawn(.wraith, .right)])], endsLevel: true),
        ],
        theme: .graveyard,
        lamps: [Lamp(x: 250), Lamp(x: 780), Lamp(x: 1300), Lamp(x: 1900, radius: 230), Lamp(x: 2550, radius: 200),
                Lamp(x: 3500, radius: 190), Lamp(x: 4250, radius: 320), Lamp(x: 4600, radius: 300)])

    /// Level 7. Frost wizards teleport, keep their distance and chill you with ice. Pairs, then the Frost Archmage.
    static let chillOut = LevelData(
        name: "Chill Out", width: 6600, heroStart: 300,
        props: Levels.withScenery([
            .crate(700, 90, holding: .item(Items.food)), .crate(1000, 150, holding: .weapon(Weapons.shield)),
            .crate(1900, 80, holding: .item(Items.food)), .pickup(.weapon(Weapons.spear), 2200, 130),
            .crate(2600, 110, holding: .weapon(Weapons.bow)), .crate(2750, 60, holding: .item(Items.quiver)), .crate(2900, 130, holding: .weapon(Weapons.bomb)),
            .crate(3500, 90, holding: .item(Items.food)), .crate(3650, 150, holding: .item(Items.food)),
            .crate(4400, 100, holding: .item(Items.food)), .pickup(.weapon(Weapons.axe), 4600, 80),
            .crate(5300, 90, holding: .item(Items.food)), .crate(5450, 150, holding: .item(Items.food)),
        ], over: 450...6200, every: 300, seed: 53, style: .frozenBush),
        placed: [Placed(x: 1200, lane: 100, tier: 0.6)],
        says: [Say(x: 400, text: "It's... cold."), Say(x: 2400, text: "Something is watching from the snow."),
               Say(x: 4100, text: "They keep blinking away!"), Say(x: 5700, text: "The air itself freezes.")],
        encounters: [
            // One wizard behind a pair of skeletons: learn the bolt and the blink.
            Encounter(triggerX: 1500, waves: [
                Wave(spawns: [Spawn(.skeleton, .left, tier: 0.6), Spawn(.wizard, .right, delay: 0.8, tier: 0.6)]),
                Wave(spawns: [Spawn(.wizard, .left, tier: 0.7), Spawn(.skeleton, .right, delay: 0.5, tier: 0.7), Spawn(.skeleton, .right, delay: 1.2, tier: 0.7)])]),
            // A pair of wizards pin you from both sides.
            Encounter(triggerX: 3100, waves: [
                Wave(spawns: [Spawn(.wizard, .left, tier: 0.7), Spawn(.wizard, .right, delay: 0.4, tier: 0.7), Spawn(.goblin, .left, delay: 1.0, tier: 0.7, shield: true)]),
                Wave(spawns: [Spawn(.giant, .right, tier: 0.7), Spawn(.wizard, .left, delay: 1.0, tier: 0.8), Spawn(.bat, .right, delay: 1.8, tier: 0.8)], line: "RAAAAGH!")]),
            // The gauntlet: everything at once, with wizards in the back.
            Encounter(triggerX: 4700, waves: [
                Wave(spawns: [Spawn(.goblin, .left, tier: 0.8, hammer: true), Spawn(.wizard, .right, delay: 0.5, tier: 0.8), Spawn(.archer, .left, delay: 1.0, tier: 0.8)]),
                Wave(spawns: [Spawn(.wizard, .left, tier: 0.9), Spawn(.wizard, .right, delay: 0.3, tier: 0.9), Spawn(.wizard, .right, delay: 1.2, tier: 0.9), Spawn(.skeleton, .left, delay: 1.5, tier: 0.9)])]),
            // The Frost Archmage.
            Encounter(triggerX: 5950, waves: [Wave(spawns: [Spawn(.archmage, .right)])], endsLevel: true),
        ],
        theme: .snow)

    /// Two frost wizards and a skeleton in a one-screen snowfield. Launch with `-wizard`; add `-wizardtest` for a hero who paces at full speed and logs its chill.
    static let wizardArena = LevelData(
        name: "Wizard Test", width: 1334, heroStart: 300,
        encounters: [Encounter(triggerX: 250, waves: [Wave(spawns: [Spawn(.wizard, .right), Spawn(.wizard, .right, delay: 0.5), Spawn(.skeleton, .left, delay: 1.0)])], endsLevel: true)],
        theme: .snow)

    /// Level 8: the Demon's introduction. Each of its three tricks shows up alone first: bulk, flight, then the blink.
    /// Borrows the Foundry's look until the Ashlands get their own art (`theme: .forge`), and has no lava bands so the Demon's fire is the only thing to read.
    static let ashlands = LevelData(
        name: "The Ashlands", width: 3400, heroStart: 300,
        props: Levels.withScenery([
            .crate(600, 100, holding: .item(Items.food)),
            .crate(1250, 70, holding: .weapon(Weapons.shield)), .crate(1400, 150, holding: .item(Items.food)),
            .crate(2000, 100, holding: .item(Items.food)), .crate(2150, 60, holding: .weapon(Weapons.bow)),
            .crate(2650, 90, holding: .item(Items.food)), .crate(2800, 150, holding: .item(Items.food)),
        ], over: 400...3300, every: 280, seed: 79, style: .charredBush),
        placed: [Placed(x: 1000, lane: 105, tier: 0.6)],
        says: [Say(x: 400, text: "The air is burning."), Say(x: 1700, text: "Something huge is breathing ahead."), Say(x: 2500, text: "Stay out of the red.")],
        encounters: [
            // Bulk: a giant that won't be pushed around, backed by goblins.
            Encounter(triggerX: 1500, waves: [
                Wave(spawns: [Spawn(.goblin, .left, tier: 0.7), Spawn(.goblin, .right, delay: 0.5, tier: 0.7), Spawn(.skeleton, .right, delay: 1.0, tier: 0.7)]),
                Wave(spawns: [Spawn(.giant, .right, tier: 0.7), Spawn(.goblin, .left, delay: 1.5, tier: 0.8, shield: true)], line: "RAAAAGH!")]),
            // Flight and the blink: bats overhead, a wizard blinking behind them.
            Encounter(triggerX: 2300, waves: [
                Wave(spawns: [Spawn(.bat, .left, tier: 0.8), Spawn(.bat, .right, delay: 0.4, tier: 0.8), Spawn(.skeleton, .right, delay: 1.2, tier: 0.8)]),
                Wave(spawns: [Spawn(.wizard, .right, tier: 0.8), Spawn(.bat, .left, delay: 0.8, tier: 0.9), Spawn(.goblin, .left, delay: 1.5, tier: 0.9, hammer: true)])]),
            // All three at once.
            Encounter(triggerX: 2950, waves: [Wave(spawns: [Spawn(.demon, .right)])], endsLevel: true),
        ],
        theme: .forge)

    /// Just the Demon, in a one-screen graveyard. Launch with `-demon`.
    static let demonArena = LevelData(
        name: "Demon Test", width: 1334, heroStart: 300,
        encounters: [Encounter(triggerX: 250, waves: [Wave(spawns: [Spawn(.demon, .right)])], endsLevel: true)],
        theme: .graveyard)

    /// Just the Frost Archmage, in a one-screen snowfield. Launch with `-archmage`.
    static let archmageArena = LevelData(
        name: "Archmage Test", width: 1334, heroStart: 300,
        encounters: [Encounter(triggerX: 250, waves: [Wave(spawns: [Spawn(.archmage, .right)])], endsLevel: true)],
        theme: .snow)

    /// Just the Lantern Wraith, in a dark one-screen graveyard. Launch with `-wraith`; add `-blade` to carry the light blade, `-wraithtest` for a hero who chases him.
    static let wraithArena = LevelData(
        name: "Wraith Test", width: 1334, heroStart: 400,
        encounters: [Encounter(triggerX: 300, waves: [Wave(spawns: [Spawn(.wraith, .right)])], endsLevel: true)],
        theme: .graveyard)

    /// A dim graveyard with a lamp post, an altar holding the light blade, and lantern goblins. Launch with `-dark`; add `-darktest` for the scripted run.
    static let darkArena = LevelData(
        name: "Dark Test", width: 1334, heroStart: 300,
        props: [.altar(760, 100, holding: .weapon(Weapons.lightblade))],
        encounters: [Encounter(triggerX: 250, waves: [Wave(spawns: [Spawn(.goblin, .right, tier: 0.3, lantern: true), Spawn(.skeleton, .right, delay: 1, tier: 0.3), Spawn(.goblin, .right, delay: 2, tier: 0.3, lantern: true)])], endsLevel: true)],
        theme: .graveyard, lamps: [Lamp(x: 1100)])

    /// Bushes in a row, two withered, and a crate. Launch with `-bushes`; add `-bushtest` for a hero who smashes them.
    static let bushArena = LevelData(
        name: "Bush Test", width: 1334, heroStart: 300,
        props: [.bush(500, 60), .bush(570, 110), .bush(650, 160), .bush(780, 80), .bush(870, 130), .bush(970, 100, withered: true), .bush(1050, 150, withered: true), .crate(1180, 100)],
        theme: .forest)

    /// One of each kind of scenery, side by side: bush, withered, frozen, crystal, charred. Launch with `-scenery`; add `-bushtest` for a hero who smashes them.
    static let sceneryArena = LevelData(
        name: "Scenery Test", width: 1334, heroStart: 300,
        props: [.bush(480, 70), .bush(520, 150), .bush(660, 70, withered: true), .bush(700, 150, withered: true),
                .scenery(.frozenBush, 840, 70), .scenery(.frozenBush, 880, 150), .scenery(.crystal, 1020, 70), .scenery(.crystal, 1060, 150),
                .scenery(.charredBush, 1200, 70), .scenery(.charredBush, 1240, 150)],
        theme: .forest)

    /// Two bats and a skeleton in a one-screen arena. Launch with `-bats`.
    static let batArena = LevelData(
        name: "Bat Arena", width: 1334, heroStart: 667,
        encounters: [Encounter(triggerX: 600, waves: [
            Wave(spawns: [Spawn(.bat, .left), Spawn(.bat, .right, delay: 0.5), Spawn(.skeleton, .left, delay: 1.0)])], endsLevel: true)],
        theme: .cave)

    /// One bat, nothing else. Launch with `-bitetest` to check what its bite does to a hero standing still.
    static let biteArena = LevelData(
        name: "Bite Test", width: 1334, heroStart: 667,
        encounters: [Encounter(triggerX: 600, waves: [Wave(spawns: [Spawn(.bat, .left)])], endsLevel: true)],
        theme: .cave)

    /// Just the Bat King, in a one-screen cave. Launch with `-batboss`.
    static let batBossArena = LevelData(
        name: "Bat King Arena", width: 1334, heroStart: 667,
        encounters: [Encounter(triggerX: 600, waves: [Wave(spawns: [Spawn(.batKing, .right)])], endsLevel: true)],
        theme: .cave)

    /// Just the Necromancer, in a one-screen cave. Launch with `-necro`.
    static let necroArena = LevelData(
        name: "Necromancer Arena", width: 1334, heroStart: 667,
        encounters: [Encounter(triggerX: 600, waves: [Wave(spawns: [Spawn(.necromancer, .right)])], endsLevel: true)],
        theme: .cave)

    /// Just the boss, in a one-screen arena. Launch with `-wyrm`.
    static let wyrmArena = LevelData(
        name: "Wyrm Arena", width: 1334, heroStart: 667,
        encounters: [Encounter(triggerX: 600, waves: [Wave(spawns: [Spawn(.wyrm, .right)])], endsLevel: true)])

    /// The old free-roam playground: used by the test flags and `-sandbox`.
    static let sandbox = LevelData(
        name: "Sandbox", width: 4000, heroStart: 667,
        props: [
            .pickup(.weapon(Weapons.axe), 480, 100), .pickup(.item(Items.food), 800, 70), .pickup(.weapon(Weapons.bow), 620, 150),
            .pickup(.weapon(Weapons.rock), 560, 70), .pickup(.weapon(Weapons.spear), 400, 150), .pickup(.item(Items.quiver), 720, 160),
            .crate(1100, 110, holding: .item(Items.food)), .crate(1750, 70, holding: .weapon(Weapons.spear)),
            .crate(2400, 150, holding: .item(Items.quiver)), .crate(3000, 90, holding: .weapon(Weapons.axe)),
        ] + (0..<8).map { Prop.pickup(.weapon(Weapons.rock), 900 + CGFloat($0) * 400 + .random(in: -120...120), .random(in: 40...180)) },
        placed: [Placed(x: 900, lane: 90), Placed(x: 1150, lane: 170), Placed(x: 1450, lane: 120)])
}

final class GameScene: SKScene {
    var level = LevelConfig()

    let mode: GameMode
    var onTogglePause: (() -> Void)?           // P / Esc on a hardware keyboard
    func resetInput() { input.cancelAll() }
    /// Freezes the game: update() stops advancing anything, and every SKAction (animations, timers, projectiles) stops with it.
    var gamePaused = false { didSet { isPaused = gamePaused; if gamePaused { input.cancelAll() } } }
    var onGameOver: ((GameResult) -> Void)?   // called once: you died, or you cleared the level
    var onEnterLevel: ((Int) -> Void)?        // hub: the hero stepped through a door
    var onExitLevel: (() -> Void)?            // the hero stepped through the exit portal after clearing the level
    private var exitPortalX: CGFloat?
    private(set) var levelData: LevelData?
    private struct ActiveEncounter {
        var index: Int
        var center: CGFloat                   // x the camera is locked to
        var wave = 0
        var queue: [(at: TimeInterval, spawn: Spawn)] = []
        var foes: [Fighter] = []
        var nextWaveAt: TimeInterval?
        var line: String?
        var lineFoe: Fighter?
    }
    private var activeEncounter: ActiveEncounter?
    private var fullLevel: LevelData?
    private var currentArea = 0
    private var clearedAreas: Set<Int> = []        // detours already finished: their doors are gone
    private var theme = Theme.forest
    /// What an area looks like when you come back to it: encounters already won, crates already broken, pickups already taken.
    private struct AreaMemory { var nextEncounter: Int; var nextSay: Int; var props: Set<Int>; var placed: Set<Int> }
    private var memory: [Int: AreaMemory] = [:]
    private var wyrm: BoneWyrm?
    private var necro: Fighter?
    private var archmage: Fighter?
    private var demon: Fighter?
    private var snowFall: SKNode?
    private var finisherAt = FinisherTuning.threshold      // combo count at which the next finisher is armed
    private var finisherAura: SKShapeNode?
    private var batKing: Fighter?
    private var doppel: Fighter?
    private var forgeKing: Fighter?
    private var wraith: Fighter?
    private let bossBar = HealthBar(width: 520, height: 16)
    private let bossName = SKLabelNode(fontNamed: GameFont.banner)
    private var camShake: CGFloat = 0
    private var shakeOffset = CGPoint.zero
    private var nextEncounter = 0
    private var nextSay = 0
    private var levelCompleteAt: TimeInterval?
    private var goUntilX: CGFloat?
    private let goLabel = SKLabelNode(fontNamed: GameFont.banner)
    private struct Bubble { let node: SKNode; weak var target: Fighter?; let until: TimeInterval }
    private var bubbles: [Bubble] = []
    private(set) var kills = 0
    private var gameOver = false
    private var nextGiantAt: TimeInterval = 45
    /// Survival enemies have this share of their health, applied on top of the per-minute tier boost (so every tier is 50% softer).
    private static let survivalHealthScale: CGFloat = 0.5
    private var nextBatAt: TimeInterval = 0
    private var nextWizardAt: TimeInterval = 0
    private var nextDemonAt: TimeInterval = 0
    private let killLabel = SKLabelNode(fontNamed: GameFont.banner)
    private let buffLabel = SKLabelNode(fontNamed: GameFont.banner)      // survival: the buffs collected so far
    private let comboHUD = ComboHUD()                                    // "12 HITS"

    let hero = HeroKind.selected.makeFighter()
    private let heroKind = HeroKind.selected
    private var enemies: [Fighter] = []

    private let cam = SKCameraNode()
    private let groundHeight: CGFloat = 250
    private var laneMinY: CGFloat = -100      // can walk below the original ground line (survival goes deeper: -260)
    private let laneStartY: CGFloat = 120
    private let verticalFollow: CGFloat = 0.7 // how much of the hero's vertical travel the camera follows
    private var baseCamY: CGFloat { size.height / 2 }
    private var layers: [(node: SKNode, fx: CGFloat, fy: CGFloat, tileW: CGFloat)] = []

    let input = InputController()
    private var lastTime: TimeInterval = 0
    private let debugLayer = SKNode()
    private let debugLabel = SKLabelNode(fontNamed: "Menlo-Bold")

    init(mode: GameMode = .campaign, levelIndex requestedLevel: Int = 0, returnDoor: Int? = nil) {
        Difficulty.active = mode == .survival ? .medium : .selected
        self.mode = mode
        let launchArgs = ProcessInfo.processInfo.arguments
        let levelIndex = launchArgs.firstIndex(of: "-level").flatMap { Int(launchArgs[min($0 + 1, launchArgs.count - 1)]) }.map { min(max($0, 0), Levels.all.count - 1) } ?? requestedLevel
        super.init(size: CGSize(width: 1334, height: 750))
        scaleMode = .aspectFill
        backgroundColor = SKColor(red: 0.55, green: 0.78, blue: 0.85, alpha: 1)
        if mode == .survival { level = LevelConfig(minX: 0, maxX: 3600); laneMinY = -260 }      // a closed arena (1.5x wider, 1.5x deeper), hero dead center
        else {
            let d = mode == .hub ? Levels.hub : (args.contains("-demon") ? Levels.demonArena : args.contains("-archmage") ? Levels.archmageArena : args.contains("-wizard") ? Levels.wizardArena : args.contains("-scenery") ? Levels.sceneryArena : args.contains("-bushes") ? Levels.bushArena : args.contains("-wraith") ? Levels.wraithArena : args.contains("-dark") ? Levels.darkArena : args.contains("-forgeking") ? Levels.forgeKingArena : args.contains("-foundry") ? Levels.foundryArena : args.contains("-doppel") ? Levels.doppelArena : args.contains("-herotest") ? Levels.heroArena : args.contains("-hammers") ? Levels.hammerArena : args.contains("-shields") ? Levels.shieldFoeArena : args.contains("-goblins") ? Levels.goblinArena : args.contains("-shieldtest") ? Levels.shieldArena : args.contains("-giant") ? Levels.giantArena : args.contains("-batboss") ? Levels.batBossArena : args.contains("-bitetest") ? Levels.biteArena : args.contains("-bats") ? Levels.batArena : args.contains("-necro") ? Levels.necroArena : args.contains("-wyrm") ? Levels.wyrmArena : ((testMode || args.contains("-sandbox")) ? Levels.sandbox : Levels.all[levelIndex]))
            levelData = d; fullLevel = d
            level = LevelConfig(minX: 0, maxX: d.width)
        }
        let startX = mode == .survival ? (level.minX + level.maxX) / 2 : (returnDoor.map { Levels.doorX($0) } ?? levelData?.heroStart ?? size.width / 2)      // coming back from a level, step out of its door
        camera = cam
        cam.position = CGPoint(x: startX, y: size.height / 2)
        addChild(cam)
        applyTheme(levelData?.theme ?? .forest)

        hero.rig.scaleFactor = 1.3
        hero.rig.position = CGPoint(x: startX, y: returnDoor != nil ? 70 : 120)      // out of a door: stand in front of it (lower lane draws in front)
        hero.rig.zPosition = 300 - hero.rig.position.y
        hero.logPrefix = ""
        addChild(hero.rig)
        addChild(pickups)
        addChild(crates)
        addChild(doors)
        addChild(arrows)
        arrows.onExplode = { [weak self] p, owner in self?.explode(at: p, owner: owner) }
        addChild(hazards)
        addChild(hitOverlay)
        hazards.onBurn = { [weak self] f in
            self?.spawnImpact(at: CGPoint(x: f.rig.position.x, y: f.rig.position.y + 70), damage: Hit.lava.damage)
            self?.pickups.floatText("SCORCHED", at: CGPoint(x: f.rig.position.x, y: f.rig.position.y + f.rig.height + 140), color: SKColor(red: 1, green: 0.55, blue: 0.15, alpha: 1))
        }
        hitOverlay.enabled = args.contains("-hitboxes")
        hero.world = pickups
        hero.onMoveStart = { [weak self] in self?.windup($0) }
        hero.onFinisher = { [weak self] in self?.finisherFired($0) }
        hero.special = HeroKind.selected.special
        if mode != .survival { hero.doorCheck = { [weak self] in self?.tryEnterDoor() ?? false } }
        hero.onSpecial = { [weak self] in self?.specialBurst($0) }
        input.onHold = { [weak self] down in
            guard let self else { return }
            if down { self.hero.beginSpecial() } else { self.hero.endSpecial() }
        }
        if ProcessInfo.processInfo.arguments.contains("-fullmeter") { hero.addMeter(dealt: 1000) }
        if args.contains("-fxhold") { fx.holdScale = 6 }
        hero.projectiles = arrows
        hero.collectsItems = true

        if mode == .survival { setupSurvival() }
        if let d = levelData { loadLevel(d) }
        if args.contains("-pausetest") {          // debug: pause at 5s, resume at 12s; log the game clock and hero health the whole time
            run(.repeatForever(.sequence([.wait(forDuration: 1), .run { [weak self] in
                guard let self else { return }
                NSLog("PAUSETEST wall=%.0f gameTime=%.1f paused=%d hero hp %.0f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000), self.gameTime, self.gamePaused ? 1 : 0, self.hero.health)
            }])), withKey: "pauselog")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.onTogglePause?() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in self?.onTogglePause?() }
        }
        if args.contains("-herotest") {           // debug: at 6s fill the meter and fire the special; log everyone's health before and after
            hero.setInvulnerable(for: 9999)
            func snap(_ tag: String, _ s: GameScene) { NSLog("HEROTEST %@ hero=%@ x%.0f maxhp %.0f speed %.0f | %@", tag, s.hero.special?.name ?? "-", s.hero.rig.position.x, s.hero.stats.maxHealth, s.hero.stats.runSpeed,
                s.enemies.map { String(format: "%@ hp%.0f x%.0f", $0.name, $0.health, $0.rig.position.x - s.hero.rig.position.x) }.joined(separator: ", ")) }
            run(.sequence([.wait(forDuration: 6), .run { [weak self] in
                guard let self else { return }
                snap("before", self)
                self.hero.debugFillMeter()
                NSLog("HEROTEST begin special -> %d", self.hero.beginSpecial() ? 1 : 0)
            }, .wait(forDuration: 1.5), .run { [weak self] in if let self { snap("after", self) } }, .wait(forDuration: 2.5), .run { [weak self] in if let self { snap("final", self) } }]))
        }
        if args.contains("-wraithtest") {         // debug: an invulnerable hero chases the Wraith and swings when close; logs lit/vulnerable and the boss's health
            hero.setInvulnerable(for: 9999)
            run(.repeatForever(.sequence([.wait(forDuration: 0.5), .run { [weak self] in
                guard let self, let w = self.wraith else { return }
                let b = w.brain as? WraithBrain
                NSLog("WRAITHTEST t=%.1f %@ lit=%d vuln=%d alpha=%.1f hp%.0f/%.0f dist%.0f R%.0f bolts=%d curses=%d glooms=%d tele=%d | hero x%.0f y%.0f",
                      self.gameTime, b?.debugPhase ?? "?", (b?.lit ?? false) ? 1 : 0, w.vulnerable ? 1 : 0, w.rig.alpha, w.health, w.stats.maxHealth,
                      hypot(w.rig.position.x - self.hero.rig.position.x, w.rig.position.y - self.hero.rig.position.y), self.heroLightRadius,
                      b?.bolts ?? 0, b?.curses ?? 0, b?.glooms ?? 0, b?.teleports ?? 0, self.hero.rig.position.x, self.hero.rig.position.y)
            }])))
            run(.sequence([.wait(forDuration: 8), .repeatForever(.sequence([.run { [weak self] in
                guard let self, let w = self.wraith, !w.dead, !self.hero.airborne else { return }
                let dx = w.rig.position.x - self.hero.rig.position.x
                if abs(dx) > 110 { self.hero.rig.position.x += (dx > 0 ? 1 : -1) * min(abs(dx) - 90, 150) }
                self.hero.rig.position.y += (w.rig.position.y - self.hero.rig.position.y) * 0.6
                self.hero.rig.facingRight = dx > 0
                if abs(dx) < 160 { self.hero.handle(.tap) }
            }, .wait(forDuration: 0.25)]))]))
        }
        if let i = args.firstIndex(of: "-critchance"), i + 1 < args.count, let p = Double(args[i + 1]) { Combat.critChance = p }          // debug: force lucky hits
        if let i = args.firstIndex(of: "-variantchance"), i + 1 < args.count, let p = Double(args[i + 1]) { Fighter.variantChance = p }   // debug: force alternate swings
        if let i = args.firstIndex(of: "-frenzy"), i + 1 < args.count, let n = Int(args[i + 1]) {      // debug: start with N stacks of Frenzy
            hero.stats.attackSpeed = 1 + 0.08 * CGFloat(n); hero.buffs["FRENZY"] = n
        }
        if args.contains("-deathtest") {           // debug: after 1.5s every enemy is blasted flat and dies; the hero is crumpled 1s later
            run(.sequence([.wait(forDuration: 1.5), .run { [weak self] in
                guard let self else { return }
                for e in self.enemies where !e.dead { e.receive(.crumble, power: 1, scale: 1, from: nil, away: 1) }
            }, .wait(forDuration: 1.0), .run { [weak self] in
                guard let self else { return }
                self.hero.receive(.crumble, power: 1, scale: 1, from: nil, away: 1)
            }]))
        }
        if let i = args.firstIndex(of: "-reactpose"), i + 2 < args.count, let v = Int(args[i + 2]) {      // debug: `-reactpose hit|down N` freezes that flinch / knockdown after it has settled
            let down = args[i + 1] == "down"
            run(.sequence([.wait(forDuration: 1.0), .run { [weak self] in self?.hero.rig.reaction = v; self?.hero.rig.play(down ? .knockdown : .hit) },
                           .wait(forDuration: down ? 0.8 : 0.1), .run { [weak self] in self?.hero.rig.speed = 0 }]))
        }
        if let i = args.firstIndex(of: "-variantpose"), i + 2 < args.count, let v = Int(args[i + 2]) {      // debug: `-variantpose jab|hook|haymaker N` freezes that swing at its hit frame
            let name = args[i + 1]
            let anim: CharacterAnimation = name == "hook" ? .hook : name == "haymaker" ? .haymaker : .jab
            var peak: TimeInterval = anim == .jab ? 0.07 : anim == .hook ? 0.17 : 0.25
            if i + 3 < args.count, let t = Double(args[i + 3]) { peak = t }          // optional 4th arg: freeze at this time instead
            run(.sequence([.wait(forDuration: 1.0), .run { [weak self] in self?.hero.rig.variant = v; self?.hero.rig.play(anim) },
                           .wait(forDuration: peak), .run { [weak self] in self?.hero.rig.speed = 0 }]))
        }
        if args.contains("-finishertest") {        // debug: finishers always armed; scripted tap, tap, uppercut, ground smash, jump, air slam at the nearest enemy
            hero.raiseMaxHealth(by: 900)
            let script: [(String, TimeInterval)] = [("face", 0.05), ("fwd", 1.6), ("face", 0.05), ("tap", 0.26), ("tap", 0.26), ("up", 1.8), ("face", 0.05), ("smash", 1.6), ("face", 0.05), ("up", 0.42), ("down", 2.2)]
            var steps: [SKAction] = [.wait(forDuration: 2.5)]
            for (s, d) in script { steps.append(.run { [weak self] in self?.finisherTest(s) }); steps.append(.wait(forDuration: d)) }
            run(.repeatForever(.sequence(steps)))
        }
        if args.contains("-combotest") {           // debug: a sturdy hero auto-attacks the nearest enemy; logs COMBO lines
            hero.raiseMaxHealth(by: 900)
            run(.sequence([.wait(forDuration: 2), .repeatForever(.sequence([.run { [weak self] in
                guard let self, !self.hero.dead else { return }
                let hx = self.hero.rig.position.x
                guard let e = self.enemies.filter({ !$0.dead }).min(by: { abs($0.rig.position.x - hx) < abs($1.rig.position.x - hx) }) else { return }
                let dx = e.rig.position.x - hx
                if abs(dx) > 100 { self.hero.rig.position = CGPoint(x: e.rig.position.x - (dx > 0 ? 80 : -80), y: e.rig.position.y) }
                self.hero.rig.facingRight = dx > 0
                self.hero.handle(Int(self.gameTime * 3.5) % 4 == 3 ? .swipe(dx > 0 ? .right : .left) : .tap)      // mostly taps, with a forward swipe (the hook) every fourth
            }, .wait(forDuration: 0.28)]))]))
        }
        if args.contains("-bombtest") {            // debug: the hero walks to lobbing distance from the nearest enemy and throws a bomb; -bombself also blasts the hero
            run(.sequence([.wait(forDuration: 1.0), .run { [weak self] in
                guard let self else { return }
                if let e = self.enemies.first(where: { !$0.dead }) { self.hero.rig.position = CGPoint(x: e.rig.position.x - 400, y: e.rig.position.y) }
                self.hero.rig.facingRight = true
                self.hero.equip(Weapons.bomb)
                self.hero.handle(.tap)
                NSLog("BOMB test throw from x%.0f", self.hero.rig.position.x)
            }]))
        }
        if args.contains("-bombself") {
            run(.sequence([.wait(forDuration: 1.0), .run { [weak self] in
                guard let self else { return }
                self.explode(at: CGPoint(x: self.hero.rig.position.x + 60, y: self.hero.rig.position.y), owner: self.hero)
            }]))
        }
        if args.contains("-wizardtest") {          // debug: a sturdy hero paces at full speed; logs his speed and whether he is chilled
            hero.raiseMaxHealth(by: 900)
            run(.sequence([.wait(forDuration: 0.4), .run { [weak self] in self?.hero.brain = PaceBrain() }]))
            run(.repeatForever(.sequence([.wait(forDuration: 0.4), .run { [weak self] in
                guard let self else { return }
                NSLog("WIZTEST t=%.1f vel=%.0f chilled=%d hp=%.0f x=%.0f alive=%d", self.gameTime, self.hero.velocity, self.hero.isChilled ? 1 : 0, self.hero.health, self.hero.rig.position.x, self.enemies.filter { !$0.dead }.count)
            }])))
        }
        if args.contains("-bufftest") {            // debug: the hero smashes altars and grabs what drops; logs the buff state
            hero.setInvulnerable(for: 9999)
            run(.repeatForever(.sequence([.wait(forDuration: 1), .run { [weak self] in
                guard let self else { return }
                NSLog("BUFFTEST t=%.0f altars=%d buffs=%@ runSpeed=%.0f damageScale=%.2f maxHealth=%.0f health=%.0f pickups=%d", self.gameTime, self.crates.crates.filter { $0.isAltar }.count, self.hero.buffs.description, self.hero.stats.runSpeed, self.hero.stats.damageScale, self.hero.stats.maxHealth, self.hero.health, self.pickups.pickups.count)
            }])))
            run(.sequence([.wait(forDuration: 2), .repeatForever(.sequence([.run { [weak self] in
                guard let self else { return }
                if let p = self.pickups.pickups.first(where: { pk in if case .item(let i) = pk.kind, i.permanent { return pk.landed } else { return false } }) {
                    self.hero.rig.position = CGPoint(x: p.position.x, y: p.lane); self.hero.handle(.swipe(.down))
                } else if let a = self.crates.crates.first(where: { $0.isAltar }) {
                    self.hero.rig.position = CGPoint(x: a.position.x - 70, y: a.position.y); self.hero.rig.facingRight = true; self.hero.handle(.tap)
                }
            }, .wait(forDuration: 0.5)]))]))
        }
        if args.contains("-bushtest") {           // debug: the hero smashes each bush in turn; logs bush/crate counts and the special meter (it must not rise)
            hero.setInvulnerable(for: 9999)
            run(.repeatForever(.sequence([.wait(forDuration: 1), .run { [weak self] in
                guard let self else { return }
                NSLog("BUSHTEST t=%.0f bushes=%d crates=%d meter=%.3f hero x%.0f", self.gameTime, self.crates.crates.filter { $0.isScenery }.count, self.crates.crates.filter { !$0.isScenery }.count, self.hero.meter, self.hero.rig.position.x)
            }])))
            run(.sequence([.wait(forDuration: 2.5), .repeatForever(.sequence([.run { [weak self] in
                guard let self, let b = self.crates.crates.first(where: { $0.isScenery }) else { return }
                self.hero.rig.position = CGPoint(x: b.position.x - 70, y: b.position.y); self.hero.rig.facingRight = true
                self.hero.handle(.tap)
            }, .wait(forDuration: 0.6)]))]))
        }
        if args.contains("-darktest") {           // debug: the hero walks to the altar and breaks it; logs light radius, the altar and the hero's weapon
            hero.setInvulnerable(for: 9999)
            run(.repeatForever(.sequence([.wait(forDuration: 1), .run { [weak self] in
                guard let self else { return }
                NSLog("DARKTEST t=%.0f view %.0fx%.0f dark=%d weapon=%@ altar=%d pickups=%d lanterns=%d heroLightR=%.0f", self.gameTime, self.size.width, self.size.height, self.darkness.enabled ? 1 : 0,
                      self.hero.weapon?.name ?? "-", self.crates.crates.filter { $0.isAltar }.count, self.pickups.pickups.count, self.enemies.filter { $0.lanternLight > 0 }.count, self.heroLightRadius)
            }])))
            run(.sequence([.wait(forDuration: 3), .run { [weak self] in
                guard let self, let a = self.crates.crates.first(where: { $0.isAltar }) else { return }
                self.hero.rig.position = CGPoint(x: a.position.x - 100, y: a.position.y); self.hero.rig.facingRight = true
            }, .repeatForever(.sequence([.run { [weak self] in
                guard let self else { return }
                if self.crates.crates.contains(where: { $0.isAltar }) { self.hero.handle(.tap); return }
                if self.hero.weapon?.name != "light blade", let b = self.pickups.pickups.first(where: { if case .weapon(let w) = $0.kind { return w.lightBonus > 0 } else { return false } }), b.landed {
                    self.hero.rig.position = CGPoint(x: b.position.x, y: b.lane)
                    self.hero.handle(.swipe(.down))
                }
            }, .wait(forDuration: 0.4)]))]))
        }
        if args.contains("-forgetest") {          // debug: log the King's phase and every hero health change; the hero swings at him when close
            var lastHP = hero.health
            run(.repeatForever(.sequence([.wait(forDuration: 0.25), .run { [weak self] in
                guard let self, let k = self.forgeKing else { return }
                let b = k.brain as? ForgeKingBrain
                if self.hero.health != lastHP { NSLog("FORGETEST t=%.1f hero hp %.0f -> %.0f (king %@, hero h%.0f y%.0f)", self.gameTime, lastHP, self.hero.health, b?.debugPhase ?? "?", self.hero.rig.height, self.hero.rig.position.y); lastHP = self.hero.health }
                NSLog("FORGETEST t=%.1f %@ hp%.0f/%.0f guard=%d weapon=%@ x%.0f smashes=%d floods=%d braces=%d breaks=%d lava %@ | hero x%.0f hp%.0f", self.gameTime, b?.debugPhase ?? "?", k.health, k.stats.maxHealth, k.guarding ? 1 : 0, k.weapon?.name ?? "-",
                      k.rig.position.x, b?.smashes ?? 0, b?.floods ?? 0, b?.braces ?? 0, b?.breaks ?? 0, self.hazards.debugStates, self.hero.rig.position.x, self.hero.health)
            }])))
            run(.sequence([.wait(forDuration: 4), .repeatForever(.sequence([.run { [weak self] in
                guard let self, let k = self.forgeKing, !k.dead else { return }
                if abs(k.rig.position.x - self.hero.rig.position.x) < 190, !self.hero.airborne {
                    self.hero.rig.facingRight = k.rig.position.x >= self.hero.rig.position.x
                    self.hero.handle(.tap)
                }
            }, .wait(forDuration: 0.4)]))]))
        }
        if args.contains("-lavatest") {           // debug: stand the hero in the first lava band; put them back every 8s; log band states and health
            run(.repeatForever(.sequence([.wait(forDuration: 0.1), .run { [weak self] in
                guard let self else { return }
                self.hero.rig.position.y = 40; self.hero.rig.zPosition = 260
            }, .wait(forDuration: 7.9)])))
            run(.repeatForever(.sequence([.wait(forDuration: 0.25), .run { [weak self] in
                guard let self else { return }
                NSLog("LAVATEST t=%.2f bands %@ hero hp %.0f y %.0f h %.0f", self.gameTime, self.hazards.debugStates, self.hero.health, self.hero.rig.position.y, self.hero.rig.height)
            }])))
        }
        if args.contains("-doppeltest") {         // debug: an invulnerable hero spams attacks beside the Doppelganger; its meter is filled at 14s
            hero.setInvulnerable(for: 9999)
            run(.repeatForever(.sequence([.wait(forDuration: 0.5), .run { [weak self] in
                guard let self, let d = self.doppel else { return }
                let b = d.brain as? DoppelBrain
                NSLog("DOPPELTEST t=%.1f %@ counters=%d hp%.0f/%.0f meter%.2f guard=%d weapon=%@ move=%@ x%.0f | hero x%.0f move=%@", self.gameTime, b?.debugPhase ?? "?", b?.counters ?? 0,
                      d.health, d.stats.maxHealth, d.meter, d.guarding ? 1 : 0, d.weapon?.name ?? "-", d.currentMoveName, d.rig.position.x, self.hero.rig.position.x, self.hero.currentMoveName)
            }])))
            run(.sequence([.wait(forDuration: 3), .repeatForever(.sequence([.run { [weak self] in
                guard let self, let d = self.doppel, !d.dead else { return }
                if abs(d.rig.position.x - self.hero.rig.position.x) > 150 || abs(d.rig.position.y - self.hero.rig.position.y) > 40 {
                    self.hero.rig.position = CGPoint(x: d.rig.position.x - 110, y: d.rig.position.y)
                }
                self.hero.rig.facingRight = d.rig.position.x >= self.hero.rig.position.x
                self.hero.handle(.tap)
            }, .wait(forDuration: 0.4)]))]))
            run(.sequence([.wait(forDuration: 14), .run { [weak self] in self?.doppel?.debugFillMeter(); NSLog("DOPPELTEST meter filled") }]))
        }
        if args.contains("-blade") { hero.equip(Weapons.lightblade) }
        if args.contains("-hammer") { hero.equip(Weapons.hammer) }
        if args.contains("-hammertest") {         // debug: log each hammer slam and every hero health change; -hammerjump jumps 0.25s after a slam starts
            let jumps = args.contains("-hammerjump")
            var lastHP = hero.health
            var lastSlam: [ObjectIdentifier: TimeInterval] = [:]
            run(.repeatForever(.sequence([.wait(forDuration: 0.05), .run { [weak self] in
                guard let self else { return }
                for e in self.enemies where !e.dead {
                    let id = ObjectIdentifier(e)
                    if e.currentMove?.name == "hammer slam" {
                        if self.gameTime - (lastSlam[id] ?? -9) > 1.5 {
                            lastSlam[id] = self.gameTime
                            NSLog("HAMMERTEST t=%.2f %@ starts a slam at dx %.0f dy %.0f", self.gameTime, e.name, e.rig.position.x - self.hero.rig.position.x, e.rig.position.y - self.hero.rig.position.y)
                            if jumps { self.run(.sequence([.wait(forDuration: 0.25), .run { self.hero.handle(.swipe(.up)) }])) }
                        }
                    }
                }
                if self.hero.health != lastHP {
                    NSLog("HAMMERTEST t=%.2f hero hp %.0f -> %.0f (hero height %.0f)", self.gameTime, lastHP, self.hero.health, self.hero.rig.height)
                    lastHP = self.hero.health
                }
            }])))
        }
        if args.contains("-shield") || args.contains("-shieldtest") { hero.equip(Weapons.shield) }
        if args.contains("-shieldtest") {         // debug: guard at 1s, log energy and health; release forward at 9s
            run(.repeatForever(.sequence([.wait(forDuration: 0.5), .run { [weak self] in
                guard let self else { return }
                NSLog("SHIELDTEST t=%.1f guarding=%d energy=%.0f hero hp %.0f | enemies %@", self.gameTime, self.hero.guarding ? 1 : 0, self.hero.guardEnergy, self.hero.health,
                      self.enemies.filter { !$0.dead }.map { String(format: "%@ hp%.0f x%.0f", $0.name, $0.health, $0.rig.position.x) }.joined(separator: ", "))
            }])))
            run(.sequence([.wait(forDuration: 1), .run { [weak self] in
                guard let self else { return }
                self.hero.handle(.swipe(self.hero.rig.facingRight ? .left : .right))
            }, .wait(forDuration: 8), .run { [weak self] in
                guard let self else { return }
                NSLog("SHIELDTEST releasing with energy %.0f", self.hero.guardEnergy)
                self.hero.handle(.swipe(self.hero.rig.facingRight ? .right : .left))
            }]))
        }
        if args.contains("-shieldfoe") {          // debug: an invulnerable hero boxes the nearest shielded enemy; at 9s makes an air strike on it
            hero.setInvulnerable(for: 9999)
            run(.repeatForever(.sequence([.wait(forDuration: 0.5), .run { [weak self] in
                guard let self else { return }
                NSLog("SHIELDFOE t=%.1f hero hp %.0f | %@", self.gameTime, self.hero.health, self.enemies.filter { !$0.dead }.map { String(format: "%@(g%d e%.0f hp%.0f x%.0f)", $0.name, $0.guarding ? 1 : 0, $0.guardEnergy, $0.health, $0.rig.position.x) }.joined(separator: " ")) 
            }])))
            run(.sequence([.wait(forDuration: 2), .repeatForever(.sequence([.run { [weak self] in
                guard let self, !self.hero.airborne,
                      let e = self.enemies.filter({ !$0.dead && $0.hasShield }).min(by: { abs($0.rig.position.x - self.hero.rig.position.x) < abs($1.rig.position.x - self.hero.rig.position.x) }) else { return }
                if abs(e.rig.position.x - self.hero.rig.position.x) > 130 || abs(e.rig.position.y - self.hero.rig.position.y) > 30 {
                    let side: CGFloat = e.rig.position.x >= self.hero.rig.position.x ? -1 : 1
                    self.hero.rig.position = CGPoint(x: e.rig.position.x + side * 100, y: e.rig.position.y)
                }
                self.hero.rig.facingRight = e.rig.position.x >= self.hero.rig.position.x
                self.hero.handle(.tap)
            }, .wait(forDuration: 0.45)]))]), withKey: "foebox")
            run(.sequence([.wait(forDuration: 9), .run { [weak self] in
                guard let self else { return }
                self.removeAction(forKey: "foebox")
                guard let e = self.enemies.filter({ !$0.dead && $0.hasShield }).first else { NSLog("SHIELDFOE no shielded enemy left for the air strike"); return }
                let side: CGFloat = e.rig.position.x >= self.hero.rig.position.x ? -1 : 1
                self.hero.rig.position = CGPoint(x: e.rig.position.x + side * 85, y: e.rig.position.y)
                self.hero.rig.facingRight = side < 0
                NSLog("SHIELDFOE air strike on %@: guarding=%d hp %.0f", e.name, e.guarding ? 1 : 0, e.health)
                self.hero.handle(.swipe(.up))
                self.run(.sequence([.wait(forDuration: 0.28), .run { self.hero.handle(.tap) }, .wait(forDuration: 0.34), .run { self.hero.handle(.tap) },
                                    .wait(forDuration: 0.8), .run { NSLog("SHIELDFOE after air strike: %@ guarding=%d hp %.0f", e.name, e.guarding ? 1 : 0, e.health) }]))
            }]))
        }
        if args.contains("-gianttest") {          // debug: the hero stands next to the giant and boxes; log phases and every hero/giant health change
            var lastH = hero.health
            run(.repeatForever(.sequence([.wait(forDuration: 0.2), .run { [weak self] in
                guard let self, let gnt = self.enemies.first(where: { $0.stats.unlaunchable && !$0.stats.flies }) else { return }
                if self.hero.health != lastH { NSLog("GIANTTEST hero hp %.0f -> %.0f (h%.0f)", lastH, self.hero.health, self.hero.rig.height); lastH = self.hero.health }
                NSLog("GIANTTEST t=%.1f %@ giant hp%.0f alpha%.1f x%.0f | hero x%.0f hp%.0f", self.gameTime, (gnt.brain as? GiantBrain)?.debugPhase ?? "?", gnt.health, gnt.rig.alpha, gnt.rig.position.x, self.hero.rig.position.x, self.hero.health)
            }])))
            run(.sequence([.wait(forDuration: 2), .repeatForever(.sequence([.run { [weak self] in
                guard let self, let gnt = self.enemies.first(where: { $0.stats.unlaunchable && !$0.stats.flies }), !gnt.dead else { return }
                let phase = (gnt.brain as? GiantBrain)?.debugPhase ?? "normal"
                guard phase == "normal" || phase == "recover" else { return }
                if abs(self.hero.rig.position.x - gnt.rig.position.x) > 150 { self.hero.rig.position = CGPoint(x: gnt.rig.position.x - 120, y: gnt.rig.position.y); self.hero.rig.facingRight = true }
                self.hero.handle(.tap)
            }, .wait(forDuration: 0.22)]))]))
        }
        if args.contains("-batboss") {            // debug: log the King's phase, height and health; -bossstrike makes the hero air-strike him
            run(.repeatForever(.sequence([.wait(forDuration: 0.25), .run { [weak self] in
                guard let self, let k = self.batKing else { return }
                NSLog("BOSSTEST t=%.1f %@ boss h%.0f x%.0f hp%.0f/%.0f | hero hp%.0f h%.0f x%.0f", self.gameTime, (k.brain as? BatKingBrain)?.debugPhase ?? "?",
                      k.rig.height, k.rig.position.x, k.health, k.stats.maxHealth, self.hero.health, self.hero.rig.height, self.hero.rig.position.x)
            }])))
        }
        if args.contains("-bossstrike") {
            hero.setInvulnerable(for: 9999)
            run(.sequence([.wait(forDuration: 5), .repeatForever(.sequence([.run { [weak self] in
                guard let self, let k = self.batKing, !k.dead, !self.hero.airborne else { return }
                let dir: CGFloat = k.rig.position.x >= self.hero.rig.position.x ? 1 : -1
                self.hero.rig.position = CGPoint(x: k.rig.position.x - dir * 75, y: k.rig.position.y)
                self.hero.rig.facingRight = dir > 0
                if k.rig.height > 100 {
                    NSLog("BOSSTEST strike: king high h%.0f hp%.0f", k.rig.height, k.health)
                    self.hero.handle(.swipe(.up))
                    self.run(.sequence([.wait(forDuration: 0.28), .run { self.hero.handle(.tap) }, .wait(forDuration: 0.34), .run { self.hero.handle(.tap) }]))
                } else {
                    NSLog("BOSSTEST ground attack: king low h%.0f hp%.0f", k.rig.height, k.health)
                    self.hero.handle(.tap)
                    self.run(.sequence([.wait(forDuration: 0.25), .run { self.hero.handle(.tap) }]))
                }
            }, .wait(forDuration: 2.2)]))]))
        }
        if mode == .survival, args.contains("-survlog") {
            run(.repeatForever(.sequence([.wait(forDuration: 2), .run { [weak self] in
                guard let self else { return }
                let live = self.enemies.filter { !$0.dead }
                NSLog("SURVTEST t=%.0f walkers=%d bats=%d", self.gameTime, live.filter { !$0.stats.flies }.count, live.filter { $0.stats.flies }.count)
            }])))
        }
        if args.contains("-bitetest") {           // debug: while the bat bites, log every check the hit test makes; log every hero health change
            var lastHP = hero.health
            run(.repeatForever(.sequence([.wait(forDuration: 0.03), .run { [weak self] in
                guard let self, let bat = self.enemies.first(where: { $0.stats.flies }) else { return }
                if self.hero.health != lastHP {
                    NSLog("BITETEST hero hp %.0f -> %.0f  (bat h%.0f dx%.0f dy%.0f move=%@)", lastHP, self.hero.health, bat.rig.height,
                          self.hero.rig.position.x - bat.rig.position.x, self.hero.rig.position.y - bat.rig.position.y, bat.currentMove?.name ?? "-")
                    lastHP = self.hero.health
                }
                guard bat.currentMove?.name == "bite" else { return }
                let f: CGFloat = bat.rig.facingRight ? 1 : -1
                let dx = (self.hero.rig.position.x - bat.rig.position.x) * f
                let dy = abs(self.hero.rig.position.y - bat.rig.position.y), dh = abs(self.hero.rig.height - bat.rig.height)
                let h = Hit.batBite
                NSLog("BITETEST bite: active=%d reach=%d(dx %.0f) depth=%d(dy %.0f) height=%d(dh %.0f) overall=%d",
                      bat.activeHits.isEmpty ? 0 : 1, (dx >= h.reach.lowerBound - Combat.bodyHalfWidth && dx <= h.reach.upperBound + Combat.bodyHalfWidth) ? 1 : 0, dx,
                      dy <= h.depth ? 1 : 0, dy, dh <= h.heightTolerance ? 1 : 0, dh, Combat.overlaps(h, from: bat, to: self.hero) ? 1 : 0)
            }])))
        }
        if args.contains("-bats") {               // debug: log the bats every quarter second; at 6s jump-strike the nearest high one
            run(.repeatForever(.sequence([.wait(forDuration: 0.25), .run { [weak self] in
                guard let self else { return }
                let s = self.enemies.filter { $0.stats.flies }.map { String(format: "(h%.0f x%.0f hp%.0f %@)", $0.rig.height, $0.rig.position.x, $0.health, $0.lastGesture) }.joined(separator: " ")
                let bs = self.enemies.filter { $0.stats.flies && !$0.dead }
                let gap = bs.count == 2 ? String(format: "gapX %.0f gapY %.0f", abs(bs[0].rig.position.x - bs[1].rig.position.x), abs(bs[0].rig.position.y - bs[1].rig.position.y)) : "-"
                NSLog("BATTEST t=%.1f %@ hero hp %.0f h%.0f  %@", self.gameTime, gap, self.hero.health, self.hero.rig.height, s)
            }])))
            run(.sequence([.wait(forDuration: 6), .run { [weak self] in
                guard let self, let b = self.enemies.filter({ $0.stats.flies && !$0.dead && $0.rig.height > 90 }).first else { NSLog("BATTEST no high bat to strike"); return }
                self.hero.rig.position = CGPoint(x: b.rig.position.x - 40, y: b.rig.position.y)
                self.hero.rig.facingRight = true
                NSLog("BATTEST strike: bat h%.0f hp%.0f", b.rig.height, b.health)
                self.hero.handle(.swipe(.up))
                self.run(.sequence([.wait(forDuration: 0.28), .run { self.hero.handle(.tap) },
                                    .wait(forDuration: 0.34), .run { self.hero.handle(.tap) },
                                    .wait(forDuration: 0.6), .run { NSLog("BATTEST after strikes: bat hp%.0f dead=%d", b.health, b.dead ? 1 : 0) }]))
            }]))
        }
        if args.contains("-airtest") {            // debug: jump, two air strikes, a third (ignored), then a dive slam, logging height
            let foe = spawnEnemy(x: hero.rig.position.x + 95, y: hero.rig.position.y)
            run(.sequence([.wait(forDuration: 2), .run { [weak self] in self?.hero.handle(.swipe(.up)) },
                           .wait(forDuration: 0.3), .run { [weak self] in self?.hero.handle(.tap) },
                           .wait(forDuration: 0.35), .run { [weak self] in self?.hero.handle(.tap) },
                           .wait(forDuration: 0.3), .run { [weak self] in self?.hero.handle(.tap) },
                           .wait(forDuration: 0.1), .run { [weak self] in self?.hero.handle(.swipe(.down)) },
                           .wait(forDuration: 1.5), .run { NSLog("AIRTEST foe health %.0f of %.0f", foe.health, foe.stats.maxHealth) }]))
            run(.repeatForever(.sequence([.wait(forDuration: 0.1), .run { [weak self] in
                guard let self, self.gameTime > 1.9, self.gameTime < 6 else { return }
                NSLog("AIRTEST t=%.1f h=%.0f  %@", self.gameTime - 2, self.hero.rig.height, self.hero.lastGesture)
            }])))
        }
        if args.contains("-areatest") {          // debug: hop into area 1 and back, unattended
            run(.sequence([.wait(forDuration: 3), .run { [weak self] in self?.changeArea(to: 1, arrival: "in") },
                           .wait(forDuration: 4), .run { [weak self] in self?.changeArea(to: 2, arrival: "start") }]))
        }
        if mode == .campaign, args.contains("-giant") { spawnEnemy(x: 1000, y: 120, giant: true) }
        hero.rig.zPosition = 300 - hero.rig.position.y

        // Debug overlay lives on the camera so it stays on screen
        debugLayer.zPosition = 10_000
        cam.addChild(debugLayer)
        let divider = SKShapeNode(rect: CGRect(x: -1, y: -size.height / 2, width: 2, height: size.height))
        divider.fillColor = .white; divider.strokeColor = .clear; divider.alpha = 0.15
        divider.zPosition = 10_000
        if ProcessInfo.processInfo.arguments.contains("-debug") { cam.addChild(divider) }      // marks the split between the move stick (left) and swipes (right)
        debugLabel.fontSize = 22
        debugLabel.fontColor = .white
        debugLabel.zPosition = 10_001
        if ProcessInfo.processInfo.arguments.contains("-debug") { cam.addChild(debugLabel) }       // the state read-out is for development only
        hero.brain = PlayerBrain(input: input, fighter: hero)
        heroBar.zPosition = 10_000
        cam.addChild(heroBar)
        heroName.text = heroKind.title; heroName.fontSize = 44; heroName.fontColor = .white
        heroName.horizontalAlignmentMode = .left; heroName.verticalAlignmentMode = .center; heroName.zPosition = 10_000
        let heroNameShade = SKLabelNode(fontNamed: GameFont.banner)
        heroNameShade.text = heroName.text; heroNameShade.fontSize = 44; heroNameShade.fontColor = .black
        heroNameShade.horizontalAlignmentMode = .left; heroNameShade.verticalAlignmentMode = .center
        heroNameShade.position = CGPoint(x: 3, y: -3); heroNameShade.zPosition = -1
        heroName.addChild(heroNameShade)
        cam.addChild(heroName)
        bossBar.zPosition = 10_000; bossBar.isHidden = true
        bossName.text = "BONE WYRM"; bossName.fontSize = 40; bossName.fontColor = .white
        bossName.verticalAlignmentMode = .center; bossName.zPosition = 10_000; bossName.isHidden = true
        cam.addChild(bossBar); cam.addChild(bossName)
        meterBar.zPosition = 10_000
        cam.addChild(meterBar)
        darkness.configure(size: size)
        darkness.zPosition = 8000                       // over the world (fighters, lava, warnings), under every bar and label
        cam.addChild(darkness)
        setupKillLabel()
        setupGoLabel()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Enemies

    private let args = ProcessInfo.processInfo.arguments
    private var testMode: Bool { args.contains("-hittest") || args.contains("-divetest") || args.contains("-itemtest") || args.contains("-bowtest") || args.contains("-fxtest") || args.contains("-launchtest") || args.contains("-juggletest") || args.contains("-uppertest") }
    private var nextCrowdLog: TimeInterval = 0
    private let crowd = CrowdDirector()
    private let pickups = PickupField()
    private let fx = CameraFX()
    private var profileHit0: TimeInterval?
    private var fxEnabled: Bool { !args.contains("-nofx") }
    private var gameTime: TimeInterval = 0      // advances at the (possibly slowed) game rate; every gameplay timer runs on it
    private var realNow: TimeInterval = 0
    private var fxPeakZoom: CGFloat = 0, fxMinScale: CGFloat = 1, fxActive: TimeInterval = 0
    private let arrows = ProjectileField()
    private let crates = CrateField()
    private let doors = DoorField()
    private var entering = false
    private var chargeZoom: CGFloat = 0            // last zoom the special's charge reached
    private var chargeZoomUntil: TimeInterval = 0  // after release, keep that zoom until the impact beat has taken over
    private let hitOverlay = HitOverlay()
    private let hazards = HazardField()
    private let darkness = DarknessLayer()
    private var lampNodes: [(node: SKNode, light: Lamp)] = []
    private(set) var heroLightRadius: CGFloat = 0
    private var gloomUntil: TimeInterval = 0        // the Wraith's curse: the hero's light is smaller until then
    var isDark: Bool { darkness.enabled }
    private let archerChance = 0.3           // chance a spawned skeleton carries a bow
    private let foodDropChance = 0.3          // chance a KO'd enemy drops food
    private var bars: [ObjectIdentifier: HealthBar] = [:]
    private let heroBar = HealthBar(width: 300, height: 14)
    private let heroName = SKLabelNode(fontNamed: GameFont.banner)
    private let meterBar = MeterBar(width: 300)
    private var nextSpawn: TimeInterval = 0


    /// `tier` is survival difficulty (0 = the campaign's enemy): more health, harder hits, a bit faster, quicker to act.
    @discardableResult
    private func spawnEnemy(x: CGFloat, y: CGFloat, giant: Bool = false, tier: CGFloat = 0, bow: Bool? = nil, necro: Bool = false, bat: Bool = false, king: Bool = false, goblin: Bool = false, shield: Bool = false, hammer: Bool = false, lantern: Bool = false) -> Fighter {
        var stats: FighterStats = king ? .batKing : bat ? .bat : (necro ? .necromancer : (giant ? .giantSkeleton : (goblin ? .goblin : .skeleton)))
        if tier > 0 {
            stats.maxHealth *= 1 + tier * (giant ? 0.5 : 0.9)
            stats.damageScale *= 1 + tier * 0.35
            stats.runSpeed *= 1 + min(tier, 1) * 0.3
        }
        if mode == .survival { stats.maxHealth *= Self.survivalHealthScale }      // easier early kills, so a run ends in the swarm and not in a slog
        let skin: Skin
        if king { skin = BatSkin(royal: true) } else if bat { skin = BatSkin() } else if necro { skin = NecromancerSkin() } else if goblin { skin = SpriteSkin.wrap("goblin", GoblinSkin()) } else { skin = SpriteSkin.wrap("skeleton", SkeletonSkin()) }
        let shaded: Skin
        if theme == .mirror { shaded = ShadowSkin(base: skin, strength: 0.5) } else { shaded = skin }          // the hall reflects everyone as a shadow
        let e = Fighter(name: king ? "bat king" : bat ? "bat" : (necro ? "necromancer" : (giant ? "giant skeleton" : (goblin ? "goblin" : "skeleton"))), skin: shaded, stats: stats)
        e.team = 1
        e.world = pickups
        e.projectiles = arrows
        let wantsBow = bow ?? (!giant && !testMode && Double.random(in: 0...1) < (tier > 0 ? min(0.4, 0.12 + Double(tier) * 0.06) : archerChance))
        if wantsBow, !giant, !necro, !bat, !king, !goblin { e.equip(Weapons.bow) }
        if shield, !giant, !necro, !bat, !king {
            e.equip(Weapons.shield)
            e.guardCapacity = 40; e.guardWalk = 0.8; e.guardBreaks = true       // enemy shields break when overloaded and walk almost at full speed
        }
        if hammer, !shield, !giant, !necro, !bat, !king { e.equip(Weapons.hammer) }
        let bomber = goblin && !shield && !hammer && (args.contains("-bombgoblin") || (!testMode && Double.random(in: 0...1) < 0.25))      // some goblins carry a bomb
        if bomber { e.equip(Weapons.bomb) }
        if lantern, !giant, !necro, !bat, !king {
            e.lanternLight = 210
            let lamp = SKNode(); lamp.name = "lantern"; lamp.position = CGPoint(x: 30, y: 50); lamp.zPosition = 6
            let flame = styled(SKShapeNode(circleOfRadius: 9), SKColor(red: 1, green: 0.8, blue: 0.35, alpha: 1), line: 2)
            flame.glowWidth = 8
            let cap = styled(SKShapeNode(rect: CGRect(x: -6, y: 9, width: 12, height: 5), cornerRadius: 2), SKColor(red: 0.25, green: 0.2, blue: 0.18, alpha: 1), line: 2)
            lamp.addChild(flame); lamp.addChild(cap)
            e.rig.addChild(lamp)
        }
        if !args.contains("-passive"), !testMode {
            let brain = EnemyBrain(director: crowd)
            if tier > 0 {
                let k = Double(1 / (1 + tier * 0.25))
                let r = brain.traits.reaction, c = brain.traits.cooldown
                brain.traits.reaction = (r.lowerBound * k)...(r.upperBound * k)
                brain.traits.cooldown = (c.lowerBound * k)...(c.upperBound * k)
                brain.traits.comboChance = min(0.6, brain.traits.comboChance + Double(tier) * 0.08)
            }
            if giant {
                brain.traits.attackRange = 230
                brain.traits.reaction = 0.5...0.9
                brain.traits.cooldown = 1.8...3.2
                brain.traits.chargeChance = 0; brain.traits.retreatChance = 0; brain.traits.comboChance = 0.1
                brain.traits.holdDistance = 330
            }
            if hammer, !shield, !giant, !necro, !bat, !king {          // hammer carriers: slightly longer reach, slower and surer
                brain.traits.attackRange = 190; brain.traits.holdDistance = 280
                brain.traits.reaction = 0.45...0.75; brain.traits.cooldown = 2.0...3.4
                brain.traits.chargeChance = 0; brain.traits.comboChance = 0
            }
            if giant, !args.contains("-nosmash") {
                let gb = GiantBrain(inner: brain)
                gb.onMark = { [weak self] p, t in self?.groundMark(at: p, duration: t) }
                gb.onPoof = { [weak self] p in self?.poof(at: p) }
                gb.onSlam = { [weak self] _ in self?.bossSlam(0.6) }
                gb.onHeroHit = { [weak self] h in self?.spawnImpact(at: CGPoint(x: h.rig.position.x, y: h.rig.position.y + h.rig.height + 60), damage: Hit.giantSlam.damage) }
                e.brain = gb
            } else if king { e.brain = BatKingBrain() } else if necro { e.brain = NecromancerBrain() } else if bat { e.brain = BatBrain() } else if bomber { e.brain = BomberBrain(inner: brain, fallback: skin.defaultWeapon) } else { e.brain = brain }
        }
        e.rig.scaleFactor = king ? 3.2 : bat ? 1.25 : (necro ? 1.7 : (giant ? 2.6 : 1.3))
        e.rig.facingRight = false
        e.rig.position = CGPoint(x: x, y: y)
        e.rig.zPosition = 300 - y
        if king { e.rig.height = 200; e.flyHeight = 200 } else if bat { e.rig.height = 130; e.flyHeight = 130 }          // bats arrive already in the air
        enemies.append(e); applyDifficulty(e)
        addChild(e.rig)
        let bar = HealthBar(width: giant ? 150 : (bat ? 46 : 70))
        bar.zPosition = 9000
        bars[ObjectIdentifier(e)] = bar
        addChild(bar)
        return e
    }

    /// Impact flash plus a floating damage number.
    /// Ground ring and white flash timed to the special's impact.
    private func specialBurst(_ s: Special) {
        let origin = hero.rig.position
        if fxEnabled {
            let e = s.release.emphasis
            fx.add(zoom: e.impact, slow: e.slow, attack: 0.05, hold: e.hold, release: e.release, at: realNow + s.impactDelay)
            chargeZoomUntil = realNow + s.impactDelay + 0.05 + e.hold      // the impact beat is above the charge zoom from here on
        }
        run(.sequence([.wait(forDuration: s.impactDelay), .run { [weak self] in
            guard let self else { return }
            let ring = SKShapeNode(ellipseOf: CGSize(width: s.radius * 2, height: s.radius * 0.5))
            ring.strokeColor = .white; ring.lineWidth = 10; ring.glowWidth = 8
            ring.fillColor = SKColor(red: 1, green: 0.3, blue: 0.2, alpha: 0.25)
            ring.position = origin; ring.zPosition = 9000; ring.setScale(0.05)
            self.addChild(ring)
            ring.run(.sequence([.group([.scale(to: 1, duration: 0.35), .fadeOut(withDuration: 0.4)]), .removeFromParent()]))
            let flash = SKSpriteNode(color: .white, size: CGSize(width: self.size.width * 2, height: self.size.height * 2))
            flash.alpha = 0; flash.zPosition = 9900
            self.cam.addChild(flash)
            flash.run(.sequence([.fadeAlpha(to: 0.7, duration: 0.03), .fadeOut(withDuration: 0.25), .removeFromParent()]))
        }]))
    }

    private func spawnImpact(at p: CGPoint, damage: CGFloat) {
        let path = CGMutablePath()
        for i in 0..<16 {
            let r: CGFloat = i % 2 == 0 ? 8 + damage * 1.6 : 6 + damage * 0.6
            let a = CGFloat(i) * .pi / 8
            let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        let star = styled(SKShapeNode(path: path), .white, line: 3)
        star.position = p; star.zPosition = 9500
        addChild(star)
        star.run(.sequence([.group([.scale(to: 1.5, duration: 0.14), .fadeOut(withDuration: 0.14)]), .removeFromParent()]))

        let text = "\(Int(damage.rounded()))"
        for (offset, color) in [(CGPoint(x: 2, y: -2), SKColor.black), (CGPoint.zero, SKColor(red: 1, green: 0.9, blue: 0.3, alpha: 1))] {
            let l = SKLabelNode(fontNamed: GameFont.speech)
            l.text = text; l.fontSize = 31; l.fontColor = color
            l.position = CGPoint(x: p.x + offset.x, y: p.y + 20 + offset.y); l.zPosition = 9501 + (color == .black ? 0 : 1)
            addChild(l)
            l.run(.sequence([.group([.moveBy(x: 0, y: 55, duration: 0.7), .sequence([.wait(forDuration: 0.35), .fadeOut(withDuration: 0.35)])]),
                             .removeFromParent()]))
        }
    }

    /// `-crowdtest` metrics: closest pair of same-lane enemies, and how many are in melee range of the hero.
    private func logCrowd(now: TimeInterval) {
        guard args.contains("-crowdtest"), now >= nextCrowdLog else { return }
        nextCrowdLog = now + 0.5
        let live = enemies.filter { $0.hittable }
        var gap = CGFloat.infinity
        for i in 0..<live.count { for j in (i + 1)..<live.count {
            let a = live[i].rig.position, b = live[j].rig.position
            if abs(a.y - b.y) < 24 { gap = min(gap, abs(a.x - b.x)) }
        } }
        let engaged = live.filter { abs($0.rig.position.x - hero.rig.position.x) < 140 && abs($0.rig.position.y - hero.rig.position.y) < 30 }.count
        NSLog("CROWD n=%d min_gap=%@ engaged=%d", live.count, gap.isFinite ? String(Int(gap)) : "-", engaged)
    }

    /// Soft push so grounded enemies never stand on top of each other (they ease apart rather than snap).
    private func separateEnemies(dt: CGFloat, bounds: WorldBounds) {
        // Walkers keep to themselves; flyers keep to themselves (wider, since they dive across more ground). The two groups pass through each other.
        spread(enemies.filter { $0.hittable && !$0.airborne && !$0.stats.flies }, spacingX: 70, spacingY: 30, dt: dt, bounds: bounds)
        spread(enemies.filter { $0.hittable && $0.stats.flies && !$0.stats.unlaunchable }, spacingX: 130, spacingY: 55, dt: dt, bounds: bounds)
    }

    private func spread(_ live: [Fighter], spacingX: CGFloat, spacingY: CGFloat, dt: CGFloat, bounds: WorldBounds) {
        let k = min(1, dt * 10)
        for i in 0..<live.count {
            for j in (i + 1)..<live.count {
                let a = live[i], b = live[j]
                let dx = a.rig.position.x - b.rig.position.x, dy = a.rig.position.y - b.rig.position.y
                guard abs(dx) < spacingX, abs(dy) < spacingY else { continue }
                let sx: CGFloat = dx == 0 ? (i < j ? 1 : -1) : (dx > 0 ? 1 : -1)
                let sy: CGFloat = dy == 0 ? (i < j ? 1 : -1) : (dy > 0 ? 1 : -1)
                let px = (spacingX - abs(dx)) * 0.5 * k, py = (spacingY - abs(dy)) * 0.5 * k
                a.nudge(dx: sx * px, dy: sy * py, bounds: bounds)
                b.nudge(dx: -sx * px, dy: -sy * py, bounds: bounds)
            }
        }
    }

    // MARK: Survival

    private func setupSurvival() {
        let cx = (level.minX + level.maxX) / 2
        nextSpawn = 1.5
        // A little to work with near the middle; crates are cover and supplies
        pickups.place(.weapon(Weapons.axe), at: CGPoint(x: cx - 360, y: 90))
        pickups.place(.weapon(Weapons.rock), at: CGPoint(x: cx + 360, y: 140))
        crates.place(x: cx - 840, lane: 100, contents: .item(Items.food))
        crates.place(x: cx + 840, lane: 130, contents: .weapon(Weapons.spear))
        crates.place(x: cx - 1425, lane: 80, contents: .weapon(Weapons.bow))
        crates.place(x: cx + 180, lane: 60, contents: .weapon(Weapons.shield))
        crates.place(x: cx + 510, lane: 140, contents: .weapon(Weapons.hammer))
        crates.place(x: cx + 1425, lane: 150, contents: .item(Items.quiver))
        for bx: CGFloat in [-700, 700] { crates.place(x: cx + bx, lane: .random(in: -150...150), contents: .weapon(Weapons.bomb)) }      // bomb crates
        let altarBuffs = Buff.allCases.shuffled()                          // one of each buff, shuffled between the four corners
        for (n, (ax, lane)) in [(level.minX + 170, CGFloat(160)), (level.maxX - 170, 160), (level.minX + 170, -150), (level.maxX - 170, -150)].enumerated() {
            crates.place(x: ax, lane: lane, contents: .item(altarBuffs[n].item), altar: true)
        }
        for _ in 0..<24 {                                                   // shrubs to smash, scattered round the arena
            let bx = CGFloat.random(in: 120...(level.maxX - 120))
            if crates.crates.contains(where: { abs($0.position.x - bx) < 110 }) { continue }
            crates.place(x: bx, lane: .random(in: -220...190), style: .bush, scale: .random(in: 0.85...1.3))
        }
    }

    /// Waves by time survived. Every minute is one "tier": the cap on live enemies, the spawn rate, and each enemy's
    /// health, damage, speed and aggression all climb with it. Giants arrive on a timer, one at a time.
    private func updateSurvival(now: TimeInterval) {
        if hero.dead, !gameOver, let since = hero.deadSince, now - since > 1.8 {
            gameOver = true
            onGameOver?(GameResult(kills: kills, won: false))
        }
        guard !gameOver, !hero.dead, !args.contains("-passive") else { return }

        let tier = CGFloat(now / 60)
        crowd.maxAttackers = min(4, 2 + Int(tier))
        crowd.stagger = max(0.25, 0.6 - Double(tier) * 0.08)

        let alive = enemies.filter { !$0.dead && !$0.stats.flies }.count       // bats have their own cap
        let cap = min(14, 4 + Int(now / 25))
        if alive < cap, now >= nextSpawn {
            nextSpawn = now + max(0.7, 2.6 - now / 50)
            // Goblins join after 30s: one walker in five at first, up to one in three.
            let goblinStart: TimeInterval = args.contains("-earlygoblins") ? 0 : 30
            let goblinChance = now >= goblinStart ? min(0.33, 0.2 + (now - goblinStart) / 900) : 0
            // Shields join at 2:30: about one walker in seven at first, one in three-and-a-bit by about 5 minutes.
            let shieldStart: TimeInterval = args.contains("-earlyshields") ? 0 : 150
            let shieldChance = now >= shieldStart ? min(0.3, 0.15 + (now - shieldStart) / 1000) : 0
            // Hammers join at 3:30: about one walker in twelve, rising to one in five. (A walker never has both.)
            let hammerStart: TimeInterval = args.contains("-earlyhammers") ? 0 : 210
            let hammerChance = now >= hammerStart ? min(0.2, 0.08 + (now - hammerStart) / 1500) : 0
            let wantsShield = Double.random(in: 0...1) < shieldChance
            let wantsHammer = !wantsShield && Double.random(in: 0...1) < hammerChance
            spawnAtEdge(tier: tier, goblin: Double.random(in: 0...1) < goblinChance, shield: wantsShield, hammer: wantsHammer)
        }
        // Bats join late (from batStart), one or two at first, up to four by about five minutes in.
        let batStart: TimeInterval = args.contains("-earlybats") ? 5 : 120
        if now >= batStart, now >= nextBatAt {
            let batCap = min(4, 1 + Int((now - batStart) / 60))
            nextBatAt = now + max(6, 14 - (now - batStart) / 30)
            if enemies.filter({ !$0.dead && $0.stats.flies }).count < batCap { spawnAtEdge(tier: tier, bat: true) }
        }
        // Frost wizards join at 3:00, one at a time at first, up to three by about 6 minutes.
        let wizardStart: TimeInterval = args.contains("-earlywizards") ? 5 : 180
        if now >= wizardStart, now >= nextWizardAt {
            let wizardCap = min(3, 1 + Int((now - wizardStart) / 90))
            nextWizardAt = now + max(12, 25 - (now - wizardStart) / 30)
            if enemies.filter({ !$0.dead && $0.brain is WizardBrain }).count < wizardCap { spawnAtEdge(tier: tier, wizard: true) }
        }
        let bulkAlive = enemies.contains(where: { $0.stats.unlaunchable && !$0.dead })        // one giant or Demon at a time
        if now >= nextGiantAt, !bulkAlive {
            nextGiantAt = now + max(35, 70 - now / 6)
            spawnAtEdge(tier: tier, giant: true)
        }
        // The Demon is a mini-boss like the giant: from 5:00, then every minute and a half or so, never alongside a giant.
        let demonStart: TimeInterval = args.contains("-earlydemon") ? 5 : 300
        if now >= demonStart, now >= nextDemonAt, !bulkAlive {
            nextDemonAt = now + max(75, 100 - (now - demonStart) / 20)
            nextGiantAt = max(nextGiantAt, now + 30)
            spawnAtEdge(tier: tier, demon: true)
        }
    }

    /// Just off-screen to the left or right of the camera (clamped to the arena ends), facing in. Never on screen.
    private func spawnAtEdge(tier: CGFloat, giant: Bool = false, bat: Bool = false, goblin: Bool = false, shield: Bool = false, hammer: Bool = false, wizard: Bool = false, demon: Bool = false) {
        let reach = size.width / 2 + 90
        let sides = [cam.position.x - reach, cam.position.x + reach].map { min(max($0, level.minX + 60), level.maxX - 60) }
            .filter { abs($0 - cam.position.x) > size.width / 2 + 30 }               // a side squashed against the wall would be on screen
        guard let x = sides.randomElement() else { return }
        let facing = x < hero.rig.position.x
        if wizard { _ = makeWizard(x: x, y: .random(in: 50...170), tier: tier, boss: false, facingRight: facing); return }
        if demon { _ = makeDemon(x: x, facingRight: facing, tier: tier, miniBoss: true); return }
        let e = spawnEnemy(x: x, y: .random(in: -220...190), giant: giant, tier: tier, bat: bat, goblin: goblin, shield: shield, hammer: hammer)
        e.rig.facingRight = facing
    }

    private func setupKillLabel() {
        for l in [killLabel] {
            l.fontSize = 40; l.fontColor = .white
            l.horizontalAlignmentMode = .right; l.verticalAlignmentMode = .center
            l.zPosition = 10_000
        }
        let shadow = SKLabelNode(fontNamed: GameFont.banner)
        shadow.fontSize = 40; shadow.fontColor = .black
        shadow.horizontalAlignmentMode = .right; shadow.verticalAlignmentMode = .center
        shadow.position = CGPoint(x: 3, y: -3); shadow.zPosition = -1
        killLabel.addChild(shadow)
        killLabel.isHidden = mode != .survival
        cam.addChild(killLabel)
        buffLabel.fontSize = 22; buffLabel.fontColor = SKColor(red: 1, green: 0.9, blue: 0.5, alpha: 1)
        buffLabel.horizontalAlignmentMode = .right; buffLabel.verticalAlignmentMode = .center; buffLabel.zPosition = 10_000
        let buffShadow = SKLabelNode(fontNamed: GameFont.banner)
        buffShadow.fontSize = 22; buffShadow.fontColor = .black; buffShadow.horizontalAlignmentMode = .right; buffShadow.verticalAlignmentMode = .center
        buffShadow.position = CGPoint(x: 2, y: -2); buffShadow.zPosition = -1
        buffLabel.addChild(buffShadow)
        buffLabel.isHidden = mode != .survival
        cam.addChild(buffLabel)
        comboHUD.zPosition = 10_000
        cam.addChild(comboHUD)
        comboHUD.setReadyColor(heroKind.color)
        updateKills()
    }

    private func updateKills() {
        killLabel.text = "KILLS \(kills)"
        (killLabel.children.first as? SKLabelNode)?.text = killLabel.text
        killLabel.removeAction(forKey: "pop")
        killLabel.run(.sequence([.scale(to: 1.3, duration: 0.06), .scale(to: 1, duration: 0.12)]), withKey: "pop")
    }

    // MARK: Camera moments

    /// Anticipation: the camera starts easing in as the hero begins a big move, even if it ends up missing.
    private func windup(_ m: Move) {
        guard fxEnabled, m.emphasis.windup > 0 else { return }
        fx.add(zoom: m.emphasis.windup, attack: 0.1, hold: 0.15, release: m.emphasis.release, at: realNow)
    }

    /// The hero's connecting hits set the size of the moment: the move's own tier, bumped by how many it hit, whether it
    /// finished someone, and whether that was the last enemy standing. Enemy hits never move the camera.
    private func emphasize(_ contacts: [Combat.Contact]) {
        guard fxEnabled else { return }
        let mine = contacts.filter { $0.attacker === hero }
        guard !mine.isEmpty else { return }
        var e = mine.compactMap { $0.move?.emphasis }.max { $0.impact < $1.impact } ?? .none
        let ko = mine.contains { $0.ko }
        if ko {
            let finisher = !enemies.contains { !$0.dead }
            let k = finisher ? Emphasis.massive : Emphasis.kill
            if k.impact > e.impact { e = k }
        }
        if mine.contains(where: { $0.crit }), Emphasis.medium.impact > e.impact { e = .medium }      // a lucky hit always gets at least a medium zoom
        guard e.impact > 0 else { return }
        let bonus = min(1.6, 1 + 0.25 * CGFloat(mine.count - 1) + (ko ? 0.2 : 0))
        fx.add(zoom: e.impact * bonus, slow: max(0.2, 1 - (1 - e.slow) * min(1.3, bonus)), attack: 0.05,
               hold: e.hold * Double(bonus), release: e.release, at: realNow)
    }

    private func finisherTest(_ step: String) {
        guard !hero.dead else { return }
        let hx = hero.rig.position.x
        if step == "face" {
            guard let e = enemies.filter({ !$0.dead }).min(by: { abs($0.rig.position.x - hx) < abs($1.rig.position.x - hx) }) else { return }
            let dx = e.rig.position.x - hx
            hero.rig.position = CGPoint(x: e.rig.position.x - (dx >= 0 ? 85 : -85), y: e.rig.position.y)
            hero.rig.facingRight = dx >= 0
            return
        }
        switch step {
        case "tap":   hero.handle(.tap)
        case "up":    hero.handle(.swipe(.up))
        case "fwd":   hero.handle(.swipe(hero.rig.facingRight ? .right : .left))
        case "down":  hero.handle(.swipe(.down))
        case "smash": hero.debugPerform(MoveTable.groundSmash)
        default: break
        }
    }

    /// A gold ring under the hero while a finisher is armed.
    private func updateFinisherAura() {
        if hero.finisherReady, !hero.dead {
            guard finisherAura == nil else { return }
            let a = SKShapeNode(ellipseOf: CGSize(width: 96, height: 26))
            a.fillColor = heroKind.color.withAlphaComponent(0.3); a.strokeColor = heroKind.color.withAlphaComponent(0.95)
            a.lineWidth = 4; a.glowWidth = 8; a.position = CGPoint(x: 0, y: 2); a.zPosition = -5
            a.run(.repeatForever(.sequence([.scale(to: 1.15, duration: 0.3), .scale(to: 0.92, duration: 0.3)])))
            hero.rig.addChild(a); finisherAura = a
        } else if let a = finisherAura { a.removeFromParent(); finisherAura = nil }
    }

    /// A finisher went off: spend the charge (the next one is `threshold` hits away), name it, shake the screen and ring the impact.
    private func finisherFired(_ m: Move) {
        finisherAt = comboHUD.count + FinisherTuning.threshold
        let p = hero.rig.position
        let dir: CGFloat = hero.rig.facingRight ? 1 : -1
        let info: (String, CGFloat, TimeInterval, CGFloat)
        switch m.animation {
        case .uppercut?: info = (heroKind.finisherNames.up, 50, 0.07, 240)
        case .smash?:    info = (heroKind.finisherNames.smash, 130, 0.25, 330)
        case .hook?:     info = (heroKind.finisherNames.forward, 110, 0.12, 230)
        default:         info = (heroKind.finisherNames.slam, 0, 0, 380)
        }
        let (title, ringX, delay, size) = info
        NSLog("FINISHER %@ at combo %d, next at %d", title, comboHUD.count, finisherAt)
        camShake = max(camShake, 16)
        for (i, c) in [SKColor.black, heroKind.color].enumerated() {
            let l = SKLabelNode(fontNamed: GameFont.banner)
            l.text = title; l.fontSize = 66; l.fontColor = c
            l.position = CGPoint(x: p.x + (i == 0 ? 4 : 0), y: p.y + hero.rig.height + 200 + (i == 0 ? -4 : 0)); l.zPosition = 9800 + CGFloat(i)
            l.setScale(0.3)
            addChild(l)
            l.run(.sequence([.scale(to: 1.3, duration: 0.08), .scale(to: 1, duration: 0.12), .wait(forDuration: 0.45),
                             .group([.moveBy(x: 0, y: 50, duration: 0.4), .fadeOut(withDuration: 0.4)]), .removeFromParent()]))
        }
        run(.sequence([.wait(forDuration: delay), .run { [weak self] in
            guard let self else { return }
            let ring = SKShapeNode(ellipseOf: CGSize(width: size * 2, height: size * 0.55))
            ring.fillColor = self.heroKind.color.withAlphaComponent(0.3); ring.strokeColor = self.heroKind.color; ring.lineWidth = 7; ring.glowWidth = 8
            ring.position = CGPoint(x: p.x + dir * ringX, y: p.y); ring.zPosition = 8000; ring.setScale(0.15)
            self.addChild(ring)
            ring.run(.sequence([.group([.scale(to: 1, duration: 0.22), .fadeOut(withDuration: 0.55)]), .removeFromParent()]))
        }]))
    }

    /// A lucky hit: a starburst and a big comic callout over the target.
    private func showCrit(at p: CGPoint) {
        let word = ["CRIT!", "SMASH!", "WHAM!", "CRUSHING!"].randomElement() ?? "CRIT!"
        let tilt = CGFloat.random(in: -0.15...0.15)
        for (i, c) in [SKColor.black, SKColor(red: 1, green: 0.82, blue: 0.2, alpha: 1)].enumerated() {
            let l = SKLabelNode(fontNamed: GameFont.banner)
            l.text = word; l.fontSize = 46; l.fontColor = c; l.zRotation = tilt
            l.position = CGPoint(x: p.x + (i == 0 ? 3 : 0), y: p.y + 40 + (i == 0 ? -3 : 0)); l.zPosition = 9700 + CGFloat(i)
            l.setScale(0.3)
            addChild(l)
            l.run(.sequence([.scale(to: 1.35, duration: 0.07), .scale(to: 1, duration: 0.1), .wait(forDuration: 0.25),
                             .group([.moveBy(x: 0, y: 40, duration: 0.35), .fadeOut(withDuration: 0.35)]), .removeFromParent()]))
        }
        let burst = SKShapeNode(circleOfRadius: 26)
        burst.fillColor = SKColor(red: 1, green: 0.95, blue: 0.6, alpha: 0.9); burst.strokeColor = .white; burst.lineWidth = 4; burst.glowWidth = 6
        burst.position = p; burst.zPosition = 9650; burst.setScale(0.3)
        addChild(burst)
        burst.run(.sequence([.group([.scale(to: 2.2, duration: 0.14), .fadeOut(withDuration: 0.18)]), .removeFromParent()]))
        NSLog("CRIT %@", word)
    }

    private func updateCombat(now: TimeInterval) {
        logCrowd(now: now)
        let wyrmContacts = wyrm?.resolve(hero: hero, arrows: arrows) ?? []
        let contacts = Combat.resolve([hero] + enemies) + Combat.resolveProjectiles(arrows, [hero] + enemies) + wyrmContacts
        for c in contacts {
            spawnImpact(at: c.point, damage: c.damage)
            c.attacker?.addMeter(dealt: c.damage)
            if c.crit { showCrit(at: c.point) }
        }
        for c in crates.resolve(hero: hero, pickups: pickups) { spawnImpact(at: c.point, damage: c.damage) }      // smashing crates doesn't charge the special
        comboHUD.update(now: now, hits: contacts.filter { $0.attacker === hero }.count, heroHealth: hero.health, heroDead: hero.dead)
        if comboHUD.count == 0 { finisherAt = FinisherTuning.threshold }
        hero.finisherReady = args.contains("-finishertest") || (comboHUD.count >= finisherAt && !hero.dead)
        comboHUD.finisherReady = hero.finisherReady && comboHUD.count > 0
        updateFinisherAura()
        emphasize(contacts)
        if args.contains("-launchprofile"), profileHit0 == nil, contacts.contains(where: { $0.move?.name == "uppercut" }) { profileHit0 = realNow }

        // Health bars float over enemies (hidden at full health); the hero's sits at the bottom of the screen
        for e in enemies {
            guard let bar = bars[ObjectIdentifier(e)] else { continue }
            bar.position = CGPoint(x: e.rig.position.x, y: e.rig.position.y + (e.rig.height + 98) * e.rig.scaleFactor)
            bar.set(e.healthFraction)
            bar.isHidden = e.dead || e.healthFraction >= 1
        }
        heroBar.set(hero.healthFraction)
        meterBar.set(hero.meter)
        if mode == .survival {
            let text = Buff.allCases.compactMap { b in hero.buffs[b.rawValue].map { "\(b.rawValue) x\($0)" } }.joined(separator: "   ")
            if buffLabel.text != text { buffLabel.text = text; (buffLabel.children.first as? SKLabelNode)?.text = text }
        }

        // Loot: some KO'd enemies drop food
        for e in enemies where e.dead && !e.lootDropped {
            e.lootDropped = true
            kills += 1; updateKills()
            // Skeletons sometimes just fall apart: every bone flies off on its own
            if e.deathStyle == .breakApart, let world = e.rig.parent {
                poof(at: CGPoint(x: e.rig.position.x, y: e.rig.position.y + e.rig.height + 30))
                e.rig.shatter(in: world, groundY: e.rig.position.y)
            }
            if mode == .survival, e.stats.size > 1, !e.stats.flies || e.brain is DemonBrain {      // a giant or a Demon always drops a permanent buff
                pickups.launch(.item(Buff.random(for: hero).item), from: e.rig.position, height: 50, vx: .random(in: -40...40), vz: 700)
            }
            if !testMode, Double.random(in: 0...1) < foodDropChance {
                pickups.launch(.item(Items.food), from: e.rig.position, height: 40, vx: .random(in: -60...60), vz: 600)
            }
        }

        // Clear out the dead; keep the playground stocked
        enemies.removeAll { e in
            guard e.dead, let since = e.deadSince, now - since > 1.5, !testMode else { return false }
            e.rig.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
            bars.removeValue(forKey: ObjectIdentifier(e))?.removeFromParent()
            return true
        }
        if mode == .survival { updateSurvival(now: now); return }
        if testMode { if hero.dead, let since = hero.deadSince, now - since > 2.5 { hero.restore() } }
        else { updateLevel(now: now) }
    }

    // MARK: Levels

    private func makeLamp(_ l: Lamp) -> SKNode {
        let n = SKNode(); n.position = CGPoint(x: l.x, y: l.lane); n.zPosition = 300 - l.lane - 1
        let iron = SKColor(red: 0.16, green: 0.15, blue: 0.19, alpha: 1)
        n.addChild(styled(SKShapeNode(rect: CGRect(x: -4, y: 0, width: 8, height: 138), cornerRadius: 2), iron, line: 3))
        n.addChild(styled(SKShapeNode(rect: CGRect(x: -12, y: 0, width: 24, height: 8), cornerRadius: 3), iron, line: 3))
        let box = styled(SKShapeNode(rect: CGRect(x: -11, y: 138, width: 22, height: 26), cornerRadius: 4), SKColor(red: 1, green: 0.82, blue: 0.4, alpha: 1), line: 3)
        box.glowWidth = 9
        n.addChild(box)
        n.addChild(styled(SKShapeNode(rect: CGRect(x: -14, y: 164, width: 28, height: 6), cornerRadius: 2), iron, line: 3))
        addChild(n)
        return n
    }

    /// Gathers every light source and redraws the veil. Runs after the camera has moved, so the holes sit exactly on their sources.
    private func updateDarkness() {
        guard darkness.enabled else { return }
        let t = Double(gameTime)
        let base = size.height * 0.62
        var lights: [DarknessLayer.Light] = []
        if !hero.dead {
            heroLightRadius = base * (1 + (hero.weapon?.lightBonus ?? 0)) * (gameTime < gloomUntil ? 0.72 : 1)          // a glowing weapon widens it; the Wraith's gloom shrinks it
            lights.append(.init(x: hero.rig.position.x, y: hero.rig.position.y + hero.rig.height + 70, radius: heroLightRadius))
        }
        for l in lampNodes {
            let flicker = 1 + 0.03 * CGFloat(sin(t * 9 + Double(l.light.x)))
            lights.append(.init(x: l.light.x, y: l.light.lane + 150, radius: l.light.radius * flicker))
        }
        for e in enemies where e.lanternLight > 0 {
            if e.dead { e.lanternLight = 0; e.rig.childNode(withName: "lantern")?.removeFromParent(); continue }     // kill the carrier, kill the light
            lights.append(.init(x: e.rig.position.x, y: e.rig.position.y + e.rig.height + 70, radius: e.lanternLight))
        }
        for e in enemies where e.stats.flies && !e.dead { lights.append(.init(x: e.rig.position.x, y: e.rig.position.y + e.rig.height + 40, radius: 85)) }     // glowing eyes
        for a in arrows.arrows where !a.spent { lights.append(.init(x: a.position.x, y: a.position.y, radius: 95)) }                                           // arrows give themselves away
        for p in pickups.pickups { if case .weapon(let w) = p.kind, w.lightBonus > 0 { lights.append(.init(x: p.position.x, y: p.position.y + 24, radius: 130)) } }
        for c in crates.crates where c.isAltar { lights.append(.init(x: c.position.x, y: c.position.y + 70, radius: 160)) }
        let b = UserDefaults.standard.object(forKey: "brightness") as? Double ?? 0.5
        darkness.render(lights: lights, camPos: cam.position, camScale: cam.xScale, darkness: CGFloat(0.99 - 0.12 * b))
    }

    private func loadLevel(_ d: LevelData, memory m: AreaMemory? = nil) {
        hazards.load(d.hazards, width: d.width)
        darkness.enabled = d.theme == .graveyard || args.contains("-dark")
        darkness.removeAllActions(); darkness.alpha = 1; gloomUntil = 0
        lampNodes.forEach { $0.node.removeFromParent() }
        lampNodes = d.lamps.map { l in (makeLamp(l), l) }
        if !testMode {
            for (i, p) in d.props.enumerated() {
                switch p.kind {
                case .crate(let contents):
                    if m?.props.contains(i) ?? true { crates.place(x: p.x, lane: p.lane, contents: contents).tag = i }
                case .altar(let contents):
                    if m?.props.contains(i) ?? true { crates.place(x: p.x, lane: p.lane, contents: contents, altar: true).tag = i }
                case .scenery(let style):
                    if m?.props.contains(i) ?? true { crates.place(x: p.x, lane: p.lane, style: style, scale: .random(in: 0.85...1.3)).tag = i }
                case .pickup(let kind):
                    if m?.props.contains(i) ?? true { pickups.place(kind, at: CGPoint(x: p.x, y: p.lane)).tag = i }
                case .door(let level):
                    doors.place(x: p.x, lane: p.lane, level: level, name: Levels.all[level].name)
                case .areaDoor(let area, let arrival, let name):
                    if !clearedAreas.contains(area) { doors.place(x: p.x, lane: p.lane, level: -2, name: name, area: area, arrival: arrival) }
                }
            }
        }
        for (i, e) in d.placed.enumerated() where m?.placed.contains(i) ?? true {
            spawnEnemy(x: e.x, y: e.lane, giant: e.kind == .giant, tier: e.tier, bow: e.kind == .archer, bat: e.kind == .bat, goblin: e.kind == .goblin, shield: e.shield, hammer: e.hammer, lantern: e.lantern).placedIndex = i
        }
    }

    /// Fade, swap to another area of the level, and appear at the named entry point.
    /// The hero, health, weapon, meter and score carry over; the old area is remembered for if you come back.
    private func changeArea(to index: Int, arrival: String) {
        guard let full = fullLevel, index >= 0, index <= full.areas.count else { entering = false; return }
        memory[currentArea] = AreaMemory(
            nextEncounter: nextEncounter, nextSay: nextSay,
            props: Set(crates.crates.map(\.tag).filter { $0 >= 0 } + pickups.pickups.map(\.tag).filter { $0 >= 0 }),
            placed: Set(enemies.filter { $0.placedIndex >= 0 && !$0.dead }.map(\.placedIndex)))

        crates.clear(); doors.clear(); pickups.clear(); arrows.clear()
        enemies.forEach { $0.rig.removeFromParent() }; enemies = []
        bars.values.forEach { $0.removeFromParent() }; bars = [:]
        bubbles.forEach { $0.node.removeFromParent() }; bubbles = []
        activeEncounter = nil; hideGo()

        currentArea = index
        let d = full.area(index)
        levelData = d
        level = LevelConfig(minX: 0, maxX: d.width)
        if d.theme != theme { applyTheme(d.theme) }
        let m = memory[index]
        nextEncounter = m?.nextEncounter ?? 0; nextSay = m?.nextSay ?? 0
        loadLevel(d, memory: m)

        let x = d.arrivals[arrival] ?? d.heroStart
        hero.rig.removeAction(forKey: "doorWalk")
        hero.rig.alpha = 1
        hero.rig.position.x = x
        let half = visibleHalfWidth
        cam.position.x = min(max(x, level.minX + half), max(level.minX + half, level.maxX - half))
    }

    /// Rebuild the scrolling background in a new look.
    private func applyTheme(_ t: Theme) {
        layers.forEach { $0.node.removeFromParent() }
        layers = []
        theme = t
        switch t {
        case .cave:   backgroundColor = SKColor(red: 0.08, green: 0.06, blue: 0.13, alpha: 1)
        case .mirror: backgroundColor = SKColor(red: 0.09, green: 0.07, blue: 0.19, alpha: 1)
        case .forge:  backgroundColor = SKColor(red: 0.13, green: 0.05, blue: 0.04, alpha: 1)
        case .graveyard: backgroundColor = SKColor(red: 0.06, green: 0.08, blue: 0.14, alpha: 1)
        case .forest: backgroundColor = SKColor(red: 0.55, green: 0.78, blue: 0.85, alpha: 1)
        case .snow:   backgroundColor = SKColor(red: 0.74, green: 0.85, blue: 0.94, alpha: 1)
        }
        buildWorld(t)
        snowFall?.removeFromParent(); snowFall = nil
        if t == .snow { startSnowfall() }
    }

    private func updateLevel(now: TimeInterval) {
        guard let d = levelData else { return }
        if let t = levelCompleteAt, now >= t, let x = exitPortalX {         // beat the level: a portal opens to take you out
            levelCompleteAt = nil; exitPortalX = nil
            openExitPortal(at: x)
        }
        if hero.dead, !gameOver, let since = hero.deadSince, now - since > 1.8 {      // death restarts the whole level
            gameOver = true
            onGameOver?(GameResult(kills: kills, won: false))
        }
        guard !gameOver, !hero.dead, !args.contains("-passive") else { return }

        if let gx = goUntilX, hero.rig.position.x >= gx { hideGo() }
        while nextSay < d.says.count, hero.rig.position.x >= d.says[nextSay].x {
            let s = d.says[nextSay]; nextSay += 1
            showBubble(s.text, over: hero)                                   // the hero says it: the bubble follows them
        }

        if activeEncounter == nil, nextEncounter < d.encounters.count, hero.rig.position.x >= d.encounters[nextEncounter].triggerX {
            let half = size.width / 2
            let center = min(max(hero.rig.position.x, level.minX + half), max(level.minX + half, level.maxX - half))
            var a = ActiveEncounter(index: nextEncounter, center: center)
            startWave(&a, d.encounters[nextEncounter], now: now)
            activeEncounter = a
            hideGo()
        }
        guard var a = activeEncounter else { return }
        let enc = d.encounters[a.index]

        while let next = a.queue.first, now >= next.at {
            a.queue.removeFirst()
            if next.spawn.kind == .wyrm { spawnWyrm(next.spawn, center: a.center); continue }
            if next.spawn.kind == .necromancer { a.foes.append(spawnNecromancer(next.spawn, center: a.center)); continue }
            if next.spawn.kind == .batKing { a.foes.append(spawnBatKing(next.spawn, center: a.center)); continue }
            if next.spawn.kind == .doppel { a.foes.append(spawnDoppel(next.spawn, center: a.center)); continue }
            if next.spawn.kind == .forgeKing { a.foes.append(spawnForgeKing(next.spawn, center: a.center)); continue }
            if next.spawn.kind == .wraith { a.foes.append(spawnWraith(next.spawn, center: a.center)); continue }
            if next.spawn.kind == .wizard { a.foes.append(spawnWizard(next.spawn, center: a.center)); continue }
            if next.spawn.kind == .demon { a.foes.append(spawnDemon(next.spawn, center: a.center)); continue }
            if next.spawn.kind == .archmage { a.foes.append(spawnArchmage(next.spawn, center: a.center)); continue }
            let f = spawnLevelEnemy(next.spawn, center: a.center)
            a.foes.append(f)
            if a.line != nil, a.lineFoe == nil { a.lineFoe = f }
        }
        if let f = a.lineFoe, let line = a.line {                      // speak once he's actually on screen
            if f.dead { a.line = nil; a.lineFoe = nil }
            else if abs(f.rig.position.x - cam.position.x) < size.width / 2 - 80 { showBubble(line, over: f); a.line = nil; a.lineFoe = nil }
        }

        if a.queue.isEmpty, a.foes.allSatisfy({ $0.dead }), wyrm == nil {
            if let at = a.nextWaveAt {
                if now >= at { a.nextWaveAt = nil; startWave(&a, enc, now: now) }
            } else if a.wave + 1 < enc.waves.count {
                a.wave += 1; a.nextWaveAt = now + 1.2
            } else {                                                     // encounter cleared: unlock
                activeEncounter = nil; nextEncounter += 1
                if enc.endsLevel { levelCompleteAt = now + 1.6; exitPortalX = a.center }
                else if let to = enc.leadsTo {
                    clearedAreas.insert(currentArea)               // the detour is done: its door outside stays shut
                    let x = a.center, arrival = enc.arrival
                    run(.sequence([.wait(forDuration: 1.6), .run { [weak self] in
                        self?.doors.place(x: x, lane: 110, level: -2, name: "Onward", popIn: true, area: to, arrival: arrival)
                        self?.camShake = 8
                    }]))
                } else { showGo() }
                return
            }
        }
        activeEncounter = a
    }

    private func startWave(_ a: inout ActiveEncounter, _ enc: Encounter, now: TimeInterval) {
        let w = enc.waves[a.wave]
        a.foes = []
        a.queue = w.spawns.map { (at: now + 0.3 + $0.delay, spawn: $0) }.sorted { $0.at < $1.at }
        a.line = w.line; a.lineFoe = nil
    }

    /// Enemies walk in from just beyond the locked screen edge.
    private func spawnLevelEnemy(_ s: Spawn, center: CGFloat) -> Fighter {
        let x = center + (s.side == .left ? -1 : 1) * (size.width / 2 + 90)
        let e = spawnEnemy(x: x, y: s.lane ?? .random(in: 40...180), giant: s.kind == .giant, tier: s.tier, bow: s.kind == .archer, bat: s.kind == .bat, goblin: s.kind == .goblin, shield: s.shield, hammer: s.hammer, lantern: s.lantern)
        e.rig.facingRight = s.side == .left
        return e
    }

    // MARK: Doors

    /// The level is won: a portal opens in the arena, and a banner shows the kills. Swipe up in front of it to leave.
    private func openExitPortal(at x: CGFloat) {
        doors.place(x: x, lane: 110, level: -1, name: levelData?.name == "Hub" ? "Hub" : "Exit", popIn: true)
        camShake = 8
        let banner = SKNode()
        for (text, size, y, color) in [("LEVEL CLEAR", CGFloat(64), CGFloat(40), SKColor.white), ("KILLS \(kills)", 30, -14, SKColor(red: 1, green: 0.85, blue: 0.4, alpha: 1))] {
            let l = SKLabelNode(fontNamed: GameFont.banner)
            l.text = text; l.fontSize = size; l.fontColor = color; l.verticalAlignmentMode = .center; l.position = CGPoint(x: 0, y: y)
            let s = SKLabelNode(fontNamed: GameFont.banner)
            s.text = text; s.fontSize = size; s.fontColor = .black; s.verticalAlignmentMode = .center
            s.position = CGPoint(x: 4, y: y - 4); s.zPosition = -1
            banner.addChild(s); banner.addChild(l)
        }
        banner.position = CGPoint(x: 0, y: visibleHalfHeight - 150); banner.zPosition = 10_000
        banner.setScale(1.8); banner.alpha = 0
        cam.addChild(banner)
        banner.run(.sequence([.group([.scale(to: 1, duration: 0.2), .fadeIn(withDuration: 0.2)]), .wait(forDuration: 5), .fadeOut(withDuration: 0.6), .removeFromParent()]))
    }

    /// Grounded swipe up in front of a door: walk into the portal, flash, then load the level.
    private func tryEnterDoor() -> Bool {
        if entering { return true }
        guard activeEncounter == nil, wyrm == nil, levelCompleteAt == nil,           // no ducking out of a fight
              let d = doors.nearest(to: hero.rig.position) else { return false }
        entering = true
        let level = d.level
        hero.rig.run(.group([.moveTo(x: d.position.x, duration: 0.3), .fadeOut(withDuration: 0.4)]), withKey: "doorWalk")
        if d.area >= 0 {                                   // another area of this level: a quick fade to black and back
            let fade = SKSpriteNode(color: .black, size: CGSize(width: size.width * 2, height: size.height * 2))
            fade.alpha = 0; fade.zPosition = 9900
            cam.addChild(fade)
            fade.run(.sequence([.fadeAlpha(to: 1, duration: 0.25),
                                .run { [weak self] in self?.changeArea(to: d.area, arrival: d.arrival) },
                                .fadeOut(withDuration: 0.25),
                                .run { [weak self] in self?.entering = false },
                                .removeFromParent()]))
            return true
        }
        let flash = SKSpriteNode(color: .white, size: CGSize(width: size.width * 2, height: size.height * 2))
        flash.alpha = 0; flash.zPosition = 9900
        cam.addChild(flash)
        flash.run(.sequence([.wait(forDuration: 0.25), .fadeAlpha(to: 1, duration: 0.3)]))
        run(.sequence([.wait(forDuration: 0.6), .run { [weak self] in if level < 0 { self?.onExitLevel?() } else { self?.onEnterLevel?(level) } }]))
        return true
    }

    // MARK: Boss

    private func spawnWyrm(_ s: Spawn, center: CGFloat) {
        let side: CGFloat = s.side == .left ? -1 : 1
        let w = BoneWyrm(x: center + side * (size.width / 2 + 110), lane: 110, dir: -side)
        w.onSlam = { [weak self] k in self?.bossSlam(k) }
        w.onEnrage = { [weak self] in self?.wyrmEnrage() }
        w.onDefeated = { [weak self] in self?.wyrmDefeated() }
        addChild(w)
        wyrm = w
        bossName.text = "BONE WYRM"
        bossBar.isHidden = false; bossName.isHidden = false
        bossBar.set(1)
        camShake = 10
        let card = SKLabelNode(fontNamed: GameFont.banner)
        card.text = "BONE WYRM"; card.fontSize = 84; card.fontColor = SKColor(red: 1, green: 0.85, blue: 0.75, alpha: 1)
        card.verticalAlignmentMode = .center; card.zPosition = 10_000
        let shadow = SKLabelNode(fontNamed: GameFont.banner)
        shadow.text = card.text; shadow.fontSize = 84; shadow.fontColor = .black; shadow.verticalAlignmentMode = .center
        shadow.position = CGPoint(x: 5, y: -5); shadow.zPosition = -1
        card.addChild(shadow)
        card.position = CGPoint(x: 0, y: 110); card.setScale(2.4); card.alpha = 0
        cam.addChild(card)
        card.run(.sequence([.group([.scale(to: 1, duration: 0.18), .fadeIn(withDuration: 0.18)]), .wait(forDuration: 1.7),
                            .fadeOut(withDuration: 0.4), .removeFromParent()]))
    }

    private func bossSlam(_ k: CGFloat) {
        camShake = max(camShake, 14 * k)
        guard fxEnabled else { return }
        fx.add(zoom: 0.06 * k, slow: k > 1 ? 0.3 : 0.55, attack: 0.04, hold: 0.25 * Double(k), release: 0.5, at: realNow)
    }

    /// At half health it calls skeletons to the fight.
    private func wyrmEnrage() {
        guard let c = activeEncounter?.center else { return }
        for side in [Side.left, .right] {
            let f = spawnLevelEnemy(Spawn(.skeleton, side, tier: 0.4), center: c)
            activeEncounter?.foes.append(f)
        }
    }

    private func wyrmDefeated() {
        kills += 1; updateKills()
        bossBar.isHidden = true; bossName.isHidden = true
    }

    // MARK: Necromancer

    private func spawnNecromancer(_ s: Spawn, center: CGFloat) -> Fighter {
        let x = center + (s.side == .left ? -1 : 1) * (size.width / 2 + 90)
        let e = spawnEnemy(x: x, y: 110, bow: false, necro: true)
        e.rig.facingRight = s.side == .left
        necro = e
        if let b = e.brain as? NecromancerBrain {
            b.minions = { [weak self] in self?.activeEncounter?.foes.filter { !$0.dead && $0 !== self?.necro }.count ?? 0 }
            b.onSummon = { [weak self] count, giant in self?.summonSkeletons(count: count, giant: giant) }
            b.onEruption = { [weak self] x, lane in self?.eruption(x: x, lane: lane) }
            b.onPoof = { [weak self] p in self?.poof(at: p) }
            b.onEnrage = { [weak self, weak e] in
                self?.bossSlam(1)
                if let e { self?.showBubble("ENOUGH!", over: e, duration: 2) }
            }
        }
        bossName.text = "THE NECROMANCER"
        bossBar.isHidden = false; bossName.isHidden = false
        bossBar.set(1)
        camShake = 6
        bossCard("THE NECROMANCER")
        showBubble("Join us...", over: e)
        return e
    }

    // MARK: Difficulty

    /// Campaign difficulty on a freshly spawned enemy: damage, health and how fast it acts. Medium changes nothing.
    private func applyDifficulty(_ e: Fighter) {
        let d = Difficulty.active
        guard d != .medium else { return }
        e.stats.damageScale *= d.enemyDamage
        e.scaleMaxHealth(by: d.enemyHealth)
        let brain = (e.brain as? EnemyBrain) ?? (e.brain as? GiantBrain)?.inner ?? (e.brain as? DemonBrain)?.inner
        guard let brain else { return }
        func scaled(_ r: ClosedRange<Double>) -> ClosedRange<Double> { (r.lowerBound * d.aiPace)...(r.upperBound * d.aiPace) }
        brain.traits.reaction = scaled(brain.traits.reaction)
        brain.traits.cooldown = scaled(brain.traits.cooldown)
    }

    // MARK: Demon

    private func spawnDemon(_ s: Spawn, center: CGFloat) -> Fighter {
        makeDemon(x: center + (s.side == .left ? -1 : 1) * (size.width / 2 + 120), facingRight: s.side == .left, tier: 0)
    }

    /// `miniBoss`: spawned anywhere (survival) like a giant: just the overhead health bar, no boss bar or name card.
    private func makeDemon(x: CGFloat, facingRight: Bool, tier: CGFloat, miniBoss: Bool = false) -> Fighter {
        var stats = FighterStats.demon
        if tier > 0 { stats.maxHealth *= 1 + tier * 0.5; stats.damageScale *= 1 + tier * 0.15 }
        if mode == .survival { stats.maxHealth *= Self.survivalHealthScale }
        let e = Fighter(name: "demon", skin: SpriteSkin.wrap("demon", ShadowSkin(base: SpriteSkin.wrap("skeleton", SkeletonSkin()), strength: 0.8)), stats: stats)     // drawn art once Sprites/demon_*.png exist
        e.team = 1
        e.world = pickups
        e.projectiles = arrows
        if !args.contains("-passive") {
            let brain = EnemyBrain(director: crowd)
            brain.traits.attackRange = 210; brain.traits.holdDistance = 300
            brain.traits.reaction = 0.5...0.9; brain.traits.cooldown = 1.6...2.8
            brain.traits.chargeChance = 0; brain.traits.retreatChance = 0; brain.traits.comboChance = 0.15
            let b = DemonBrain(inner: brain)
            b.onPoof = { [weak self] p in self?.poof(at: p) }
            b.onRain = { [weak self, weak e] spots in
                for p in spots {
                    self?.groundMark(at: p, duration: 0.9, width: 220)
                    self?.run(.sequence([.wait(forDuration: 0.9), .run { [weak self] in self?.fireBurst(at: p, owner: e) }]))
                }
            }
            b.onSlam = { [weak self] _ in self?.bossSlam(1) }
            b.onHeroHit = { [weak self] h in self?.spawnImpact(at: CGPoint(x: h.rig.position.x, y: h.rig.position.y + h.rig.height + 60), damage: Hit.giantSlam.damage) }
            b.onEnrage = { [weak self, weak e] in
                self?.bossSlam(1)
                if let e { self?.showBubble("BURN!", over: e, duration: 2) }
            }
            e.brain = b
        }
        e.rig.scaleFactor = 2.4
        e.rig.facingRight = facingRight
        e.rig.position = CGPoint(x: x, y: 110)
        e.rig.zPosition = 300 - 110
        enemies.append(e); applyDifficulty(e)
        addChild(e.rig)
        let bar = HealthBar(width: 150)
        bar.zPosition = 9000
        bars[ObjectIdentifier(e)] = bar
        addChild(bar)
        if miniBoss {
            (e.brain as? DemonBrain)?.arena = (level.minX + 80)...(level.maxX - 80)
            return e
        }
        demon = e
        bossName.text = "THE DEMON"
        bossBar.isHidden = false; bossName.isHidden = false
        bossBar.set(1)
        camShake = 6
        bossCard("THE DEMON", color: SKColor(red: 1, green: 0.45, blue: 0.2, alpha: 1))
        return e
    }

    /// Fire lands on a marked spot. Stand outside the ring, or jump.
    private func fireBurst(at p: CGPoint, owner: Fighter?) {
        guard let owner, !owner.dead else { return }
        // Flames erupt from the marked ring: a scorched patch, a fan of flame tongues shooting up, then a few embers.
        let z = 300 - p.y
        let scorch = SKShapeNode(ellipseOf: CGSize(width: 220, height: 82))
        scorch.fillColor = SKColor(red: 1, green: 0.4, blue: 0.1, alpha: 0.7); scorch.strokeColor = .clear
        scorch.position = p; scorch.zPosition = z - 1
        addChild(scorch)
        scorch.run(.sequence([.wait(forDuration: 0.25), .fadeOut(withDuration: 0.35), .removeFromParent()]))
        func tongue(_ w: CGFloat, _ h: CGFloat, _ color: SKColor) -> SKShapeNode {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -w / 2, y: 0))
            path.addQuadCurve(to: CGPoint(x: 0, y: h), control: CGPoint(x: -w * 0.6, y: h * 0.45))
            path.addQuadCurve(to: CGPoint(x: w / 2, y: 0), control: CGPoint(x: w * 0.6, y: h * 0.45))
            path.closeSubpath()
            let n = SKShapeNode(path: path)
            n.fillColor = color; n.strokeColor = .clear; n.glowWidth = 4
            return n
        }
        for i in 0..<9 {
            let t = CGFloat(i) / 8 - 0.5
            let h = CGFloat.random(in: 150...230) * (1 - abs(t) * 0.6)
            let outer = tongue(.random(in: 46...64), h, SKColor(red: 1, green: 0.4, blue: 0.1, alpha: 0.95))
            outer.addChild(tongue(24, h * 0.62, SKColor(red: 1, green: 0.9, blue: 0.45, alpha: 1)))
            outer.position = CGPoint(x: p.x + t * 190, y: p.y + t * 0 + CGFloat.random(in: -10...10))
            outer.zPosition = z + 1; outer.yScale = 0.05
            addChild(outer)
            outer.run(.sequence([.wait(forDuration: Double(i % 3) * 0.04),
                                 .scaleY(to: 1, duration: 0.12),
                                 .wait(forDuration: 0.18),
                                 .group([.fadeOut(withDuration: 0.25), .scaleX(to: 0.4, duration: 0.25)]),
                                 .removeFromParent()]))
        }
        for _ in 0..<10 {
            let e = SKShapeNode(circleOfRadius: .random(in: 3...5))
            e.fillColor = SKColor(red: 1, green: 0.75, blue: 0.3, alpha: 1); e.strokeColor = .clear
            e.position = CGPoint(x: p.x + .random(in: -100...100), y: p.y + 10); e.zPosition = z + 2
            addChild(e)
            e.run(.sequence([.group([.moveBy(x: .random(in: -30...30), y: .random(in: 120...260), duration: 0.6), .fadeOut(withDuration: 0.6)]), .removeFromParent()]))
        }
        bossSlam(0.4)
        let h = hero
        if abs(h.rig.position.x - p.x) <= 110, abs(h.rig.position.y - p.y) <= 41, h.rig.height < 80, h.vulnerable {
            h.receive(.eruption, power: 1, scale: 1, from: owner, away: h.rig.position.x >= p.x ? 1 : -1)
            spawnImpact(at: CGPoint(x: h.rig.position.x, y: h.rig.position.y + h.rig.height + 60), damage: Hit.eruption.damage)
        }
    }

    private func demonDefeated() {
        guard let d = demon else { return }
        demon = nil
        bossBar.isHidden = true; bossName.isHidden = true
        bossSlam(2)
        poof(at: d.rig.position)
    }

    // MARK: Frost wizards

    /// A frost wizard: keeps its distance, teleports, and throws ice that slows you. Shared by the boss (`boss: true`).
    private func makeWizard(x: CGFloat, y: CGFloat, tier: CGFloat, boss: Bool, facingRight: Bool) -> Fighter {
        var stats: FighterStats = boss ? .archmage : .wizard
        if tier > 0 { stats.maxHealth *= 1 + tier * 0.6; stats.damageScale *= 1 + tier * 0.25 }
        if mode == .survival, !boss { stats.maxHealth *= Self.survivalHealthScale }
        let e = Fighter(name: boss ? "frost archmage" : "frost wizard", skin: boss ? WizardSkin(archmage: true) : SpriteSkin.wrap("wizard", WizardSkin()), stats: stats)
        e.team = 1
        e.world = pickups
        e.projectiles = arrows
        e.keepsWeapon = true                                       // a hard hit won't knock his staff away
        if !args.contains("-passive") {
            let b = WizardBrain(boss: boss)
            b.onPoof = { [weak self] p in self?.icePoof(at: p) }
            e.brain = b
        }
        e.rig.scaleFactor = boss ? 2.8 : 1.45
        e.rig.facingRight = facingRight
        e.rig.position = CGPoint(x: x, y: y)
        e.rig.zPosition = 300 - y
        enemies.append(e); applyDifficulty(e)
        addChild(e.rig)
        let bar = HealthBar(width: boss ? 150 : 64)
        bar.zPosition = 9000
        bars[ObjectIdentifier(e)] = bar
        addChild(bar)
        return e
    }

    private func spawnWizard(_ s: Spawn, center: CGFloat) -> Fighter {
        let x = center + (s.side == .left ? -1 : 1) * (size.width / 2 + 90)
        return makeWizard(x: x, y: s.lane ?? .random(in: 50...170), tier: s.tier, boss: false, facingRight: s.side == .left)
    }

    private func spawnArchmage(_ s: Spawn, center: CGFloat) -> Fighter {
        let x = center + (s.side == .left ? -1 : 1) * (size.width / 2 + 120)
        let e = makeWizard(x: x, y: 110, tier: s.tier, boss: true, facingRight: s.side == .left)
        archmage = e
        if let b = e.brain as? WizardBrain {
            b.onSummon = { [weak self] in self?.summonWizards() }
            b.onEnrage = { [weak self, weak e] in
                self?.bossSlam(1)
                if let e { self?.showBubble("FREEZE!", over: e, duration: 2) }
            }
        }
        bossName.text = "THE FROST ARCHMAGE"
        bossBar.isHidden = false; bossName.isHidden = false
        bossBar.set(1)
        camShake = 6
        bossCard("THE FROST ARCHMAGE", color: SKColor(red: 0.75, green: 0.93, blue: 1, alpha: 1))
        showBubble("Chill out.", over: e)
        return e
    }

    /// Two wizards teleport in, one from each side.
    private func summonWizards() {
        guard let c = activeEncounter?.center, let m = archmage, !m.dead else { return }
        for side in [Side.left, .right] {
            let f = spawnWizard(Spawn(.wizard, side, tier: 0.4), center: c)
            let half = size.width / 2
            f.rig.position.x = c + (side == .left ? -1 : 1) * (half - 170)
            f.rig.alpha = 0; f.rig.run(.fadeIn(withDuration: 0.3))
            activeEncounter?.foes.append(f)
            icePoof(at: f.rig.position)
        }
    }

    private func archmageDefeated() {
        guard let m = archmage else { return }
        archmage = nil
        bossBar.isHidden = true; bossName.isHidden = true
        bossSlam(2)
        icePoof(at: m.rig.position)
        for f in activeEncounter?.foes ?? [] where !f.dead && f !== m {
            f.receive(.crumble, power: 1, scale: 1, from: nil, away: f.rig.position.x >= m.rig.position.x ? 1 : -1)
        }
    }

    /// A bomb goes off. Everything in the ellipse takes damage that fades toward the edge: enemies, the hero, the thrower too.
    private func explode(at p: CGPoint, owner: Fighter) {
        let radius: CGFloat = 170, depth: CGFloat = 80
        NSLog("BOMB explode x%.0f lane%.0f owner %@", p.x, p.y, owner.name)
        let flash = SKShapeNode(circleOfRadius: radius * 0.6)
        flash.fillColor = SKColor(red: 1, green: 0.85, blue: 0.4, alpha: 0.95); flash.strokeColor = .clear
        flash.position = CGPoint(x: p.x, y: p.y + 40); flash.zPosition = 9000; flash.setScale(0.3)
        addChild(flash)
        flash.run(.sequence([.group([.scale(to: 1.25, duration: 0.2), .fadeOut(withDuration: 0.3)]), .removeFromParent()]))
        let ring = SKShapeNode(ellipseOf: CGSize(width: radius * 2, height: depth * 2))
        ring.fillColor = SKColor(red: 1, green: 0.5, blue: 0.1, alpha: 0.28); ring.strokeColor = SKColor(red: 1, green: 0.65, blue: 0.2, alpha: 1); ring.lineWidth = 6
        ring.position = p; ring.zPosition = 8000; ring.setScale(0.2)
        addChild(ring)
        ring.run(.sequence([.group([.scale(to: 1, duration: 0.18), .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
        for _ in 0..<9 {
            let smoke = SKShapeNode(circleOfRadius: .random(in: 14...28))
            smoke.fillColor = SKColor(white: .random(in: 0.2...0.4), alpha: 0.75); smoke.strokeColor = .clear
            smoke.position = CGPoint(x: p.x + .random(in: -70...70), y: p.y + .random(in: 10...60)); smoke.zPosition = 8900
            addChild(smoke)
            smoke.run(.sequence([.group([.moveBy(x: .random(in: -40...40), y: .random(in: 70...150), duration: 0.9), .scale(to: 1.8, duration: 0.9), .fadeOut(withDuration: 0.9)]), .removeFromParent()]))
        }
        for _ in 0..<12 {
            let spark = SKShapeNode(circleOfRadius: .random(in: 3...6))
            spark.fillColor = SKColor(red: 1, green: .random(in: 0.5...0.9), blue: 0.15, alpha: 1); spark.strokeColor = .clear
            spark.position = CGPoint(x: p.x, y: p.y + 30); spark.zPosition = 9000
            addChild(spark)
            let fly = SKAction.moveBy(x: .random(in: -200...200), y: .random(in: 40...190), duration: 0.5); fly.timingMode = .easeOut
            spark.run(.sequence([.group([fly, .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
        }
        camShake = max(camShake, 20)
        bossSlam(0.8)
        for t in [hero] + enemies where !t.dead && t.vulnerable {
            let dx = t.rig.position.x - p.x, dy = t.rig.position.y - p.y
            let d = hypot(dx / radius, dy / depth)
            guard d <= 1, t.rig.height <= 100 else { continue }                      // jump high enough and it passes underneath
            let away: CGFloat = dx == 0 ? (Bool.random() ? 1 : -1) : (dx > 0 ? 1 : -1)
            let scale = owner.stats.damageScale * (1 - 0.45 * d)
            t.receive(.bombBlast, power: 1, scale: scale, from: t === owner ? nil : owner, away: away)
            spawnImpact(at: CGPoint(x: t.rig.position.x, y: t.rig.position.y + t.rig.height + 70), damage: Hit.bombBlast.damage * scale)
            NSLog("BOMB hit %@ d=%.2f hp %.0f%@", t.name, d, t.health, t.dead ? " KO" : "")
        }
        crates.blast(at: p, radiusX: radius, radiusY: depth, pickups: pickups)
    }

    private func icePoof(at p: CGPoint) {
        for _ in 0..<9 {
            let c = SKShapeNode(circleOfRadius: .random(in: 7...15))
            c.fillColor = SKColor(red: 0.78, green: 0.94, blue: 1, alpha: 0.8); c.strokeColor = SKColor(white: 1, alpha: 0.9); c.lineWidth = 2
            c.position = CGPoint(x: p.x + .random(in: -30...30), y: p.y + .random(in: 10...110)); c.zPosition = 9000
            addChild(c)
            c.run(.sequence([.group([.moveBy(x: .random(in: -60...60), y: .random(in: 10...70), duration: 0.5),
                                     .scale(to: 1.7, duration: 0.5), .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
        }
    }

    // MARK: Lantern Wraith

    private func spawnWraith(_ s: Spawn, center: CGFloat) -> Fighter {
        let e = Fighter(name: "lantern wraith", skin: WraithSkin(), stats: .wraith)
        e.team = 1
        e.world = pickups
        e.projectiles = arrows
        e.keepsWeapon = true
        e.lanternLight = 240                                       // he carries his own light
        let lamp = SKNode(); lamp.name = "lantern"; lamp.position = CGPoint(x: 34, y: 56); lamp.zPosition = 6
        let flame = styled(SKShapeNode(circleOfRadius: 10), SKColor(red: 0.7, green: 0.95, blue: 1, alpha: 1), line: 2)
        flame.glowWidth = 10
        let cap = styled(SKShapeNode(rect: CGRect(x: -6, y: 10, width: 12, height: 5), cornerRadius: 2), SKColor(red: 0.2, green: 0.25, blue: 0.3, alpha: 1), line: 2)
        lamp.addChild(flame); lamp.addChild(cap)
        e.rig.addChild(lamp)
        let b = WraithBrain()
        b.heroLight = { [weak self] in
            guard let r = self?.heroLightRadius, r > 0 else { return 465 }
            return r
        }
        b.onEruption = { [weak self] x, lane in self?.eruption(x: x, lane: lane) }
        b.onPoof = { [weak self] p in self?.poof(at: p) }
        b.onGloom = { [weak self] t in
            guard let self else { return }
            self.gloomUntil = self.gameTime + t
            self.camShake = max(self.camShake, 4)
            self.pickups.floatText("THE LIGHT FADES", at: CGPoint(x: self.hero.rig.position.x, y: self.hero.rig.position.y + self.hero.rig.height + 170), color: SKColor(red: 0.6, green: 0.9, blue: 1, alpha: 1))
        }
        b.onEnrage = { [weak self, weak e] in
            self?.bossSlam(1)
            if let e { self?.showBubble("YOUR LIGHT WILL FAIL!", over: e, duration: 2) }
        }
        e.brain = b
        e.rig.scaleFactor = 1.8
        e.rig.facingRight = s.side == .left
        let x = center + (s.side == .left ? -1 : 1) * (size.width / 2 + 100)
        e.rig.position = CGPoint(x: x, y: 110)
        e.rig.zPosition = 300 - 110
        enemies.append(e); applyDifficulty(e)
        addChild(e.rig)
        let bar = HealthBar(width: 100)
        bar.zPosition = 9000
        bars[ObjectIdentifier(e)] = bar
        addChild(bar)
        wraith = e
        bossName.text = "THE LANTERN WRAITH"
        bossBar.isHidden = false; bossName.isHidden = false
        bossBar.set(1)
        camShake = 6
        bossCard("THE LANTERN WRAITH")
        showBubble("The dark is mine.", over: e)
        return e
    }

    private func wraithDefeated() {
        guard let w = wraith else { return }
        wraith = nil
        bossBar.isHidden = true; bossName.isHidden = true
        gloomUntil = 0
        bossSlam(2)
        poof(at: w.rig.position)
        darkness.run(.sequence([.fadeOut(withDuration: 2.5), .run { [weak self] in self?.darkness.enabled = false; self?.darkness.alpha = 1 }]))     // dawn
    }

    // MARK: Forge King

    private func spawnForgeKing(_ s: Spawn, center: CGFloat) -> Fighter {
        let e = Fighter(name: "forge king", skin: ForgeKingSkin(), stats: .forgeKing)
        e.team = 1
        e.world = pickups
        e.projectiles = arrows
        e.keepsWeapon = true
        e.immuneToHazards = true
        e.equip(Weapons.hammer)
        let b = ForgeKingBrain()
        b.onErupt = { [weak self] lo, hi, warn, active in
            guard let self else { return }
            self.hazards.erupt(minY: max(lo, self.laneMinY), maxY: min(hi, self.groundHeight - 30), warn: warn, active: active)
        }
        b.onThud = { [weak self] p in self?.bossSlam(1); self?.poof(at: p) }
        b.onHeroHit = { [weak self] h in self?.spawnImpact(at: CGPoint(x: h.rig.position.x, y: h.rig.position.y + h.rig.height + 60), damage: Hit.forgeSmash.damage) }
        b.onEnrage = { [weak self, weak e] in
            self?.bossSlam(1)
            if let e { self?.showBubble("NOW IT BURNS!", over: e, duration: 2) }
        }
        b.onSay = { [weak self, weak e] t in if let e { self?.showBubble(t, over: e, duration: 1.4) } }
        e.brain = b
        e.rig.scaleFactor = 2.4
        e.rig.facingRight = s.side == .left
        let x = center + (s.side == .left ? -1 : 1) * (size.width / 2 + 160)
        e.rig.position = CGPoint(x: x, y: 110)
        e.rig.zPosition = 300 - 110
        enemies.append(e); applyDifficulty(e)
        addChild(e.rig)
        let bar = HealthBar(width: 130)
        bar.zPosition = 9000
        bars[ObjectIdentifier(e)] = bar
        addChild(bar)
        forgeKing = e
        bossName.text = "THE FORGE KING"
        bossBar.isHidden = false; bossName.isHidden = false
        bossBar.set(1)
        camShake = 6
        bossCard("THE FORGE KING")
        return e
    }

    private func forgeKingDefeated() {
        guard let k = forgeKing else { return }
        forgeKing = nil
        bossBar.isHidden = true; bossName.isHidden = true
        hazards.load([], width: 0)                                        // the forge goes cold
        bossSlam(2)
        poof(at: k.rig.position)
    }

    // MARK: Doppelgänger

    private func spawnDoppel(_ s: Spawn, center: CGFloat) -> Fighter {
        let kind = HeroKind.selected
        var stats = kind.stats
        stats.maxHealth = 320; stats.damageScale = 0.85; stats.runSpeed *= 0.9
        let e = Fighter(name: "doppelganger", skin: ShadowSkin(base: kind.skin, strength: 0.7), stats: stats)
        e.team = 1
        e.world = pickups
        e.projectiles = arrows
        e.special = kind.special
        e.keepsWeapon = true
        e.onSpecial = { [weak self] _ in self?.bossSlam(1) }
        let mirrorable = ["sword", "axe", "spear", "hammer"]
        e.equip(hero.weapon.flatMap { mirrorable.contains($0.name) ? $0 : nil } ?? Weapons.sword)
        let b = DoppelBrain()
        b.onRead = { [weak self, weak e] t in if let e { self?.showBubble(t, over: e, duration: 1.4) } }
        b.onEnrage = { [weak self, weak e] in
            self?.bossSlam(1)
            if let e { self?.showBubble("You fight like me.", over: e, duration: 2) }
        }
        e.brain = b
        e.rig.scaleFactor = kind.bulk * 1.15
        e.rig.facingRight = s.side == .left
        let x = center + (s.side == .left ? -1 : 1) * (size.width / 2 + 90)
        e.rig.position = CGPoint(x: x, y: 110)
        e.rig.zPosition = 300 - 110
        enemies.append(e); applyDifficulty(e)
        addChild(e.rig)
        let bar = HealthBar(width: 90)
        bar.zPosition = 9000
        bars[ObjectIdentifier(e)] = bar
        addChild(bar)
        doppel = e
        bossName.text = "THE DOPPELGÄNGER"
        bossBar.isHidden = false; bossName.isHidden = false
        bossBar.set(1)
        camShake = 6
        bossCard("THE DOPPELGÄNGER")
        showBubble("Hello, me.", over: e)
        return e
    }

    private func doppelDefeated() {
        guard let d = doppel else { return }
        doppel = nil
        bossBar.isHidden = true; bossName.isHidden = true
        bossSlam(2)
        poof(at: d.rig.position)
    }

    // MARK: Bat King

    private func spawnBatKing(_ s: Spawn, center: CGFloat) -> Fighter {
        let x = center + (s.side == .left ? -1 : 1) * (size.width / 2 + 160)
        let e = spawnEnemy(x: x, y: 110, bow: false, king: true)
        e.rig.facingRight = s.side == .left
        batKing = e
        if let b = e.brain as? BatKingBrain {
            b.minions = { [weak self] in self?.activeEncounter?.foes.filter { !$0.dead && $0 !== self?.batKing }.count ?? 0 }
            b.onSummon = { [weak self] n in self?.summonBats(n) }
            b.onShockwave = { [weak self] x, lane, double in
                self?.sendShockwave(x: x, lane: lane, dir: -1, delay: 0); self?.sendShockwave(x: x, lane: lane, dir: 1, delay: 0)
                if double {
                    self?.sendShockwave(x: x, lane: lane, dir: -1, delay: 0.45); self?.sendShockwave(x: x, lane: lane, dir: 1, delay: 0.45)
                }
            }
            b.onTelegraph = { [weak self] lane in self?.laneWarning(lane, duration: 0.95) }
            b.onThud = { [weak self] p in self?.bossSlam(1); self?.poof(at: p) }
            b.onHeroHit = { [weak self] h in self?.spawnImpact(at: CGPoint(x: h.rig.position.x, y: h.rig.position.y + h.rig.height + 60), damage: Hit.batSwoop.damage) }
            b.onEnrage = { [weak self] in
                self?.bossSlam(1)
                if let king = self?.batKing { self?.showBubble("SCREEEEE!", over: king, duration: 2) }
            }
        }
        bossName.text = "THE BAT KING"
        bossBar.isHidden = false; bossName.isHidden = false
        bossBar.set(1)
        camShake = 6
        bossCard("THE BAT KING")
        return e
    }

    /// A pulsing red ring on the ground: something is about to land here.
    private func groundMark(at p: CGPoint, duration: TimeInterval, width: CGFloat = 300) {
        let ring = SKShapeNode(ellipseOf: CGSize(width: width, height: width * 0.37))
        ring.fillColor = SKColor(red: 1, green: 0.1, blue: 0.15, alpha: 0.22)
        ring.strokeColor = SKColor(red: 1, green: 0.3, blue: 0.3, alpha: 0.95); ring.lineWidth = 4
        ring.position = CGPoint(x: p.x, y: p.y - 4); ring.zPosition = 3
        ring.run(.repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 0.1), .fadeAlpha(to: 1, duration: 0.1)])))
        addChild(ring)
        ring.run(.sequence([.wait(forDuration: duration), .removeFromParent()]))
    }

    /// A red band across the arena in the lane the King is about to dive along.
    private func laneWarning(_ lane: CGFloat, duration: TimeInterval) {
        guard let c = activeEncounter?.center else { return }
        let band = SKShapeNode(rect: CGRect(x: c - size.width / 2, y: lane - 42, width: size.width, height: 84))
        band.fillColor = SKColor(red: 1, green: 0.1, blue: 0.2, alpha: 0.2)
        band.strokeColor = SKColor(red: 1, green: 0.3, blue: 0.3, alpha: 0.9); band.lineWidth = 4
        band.zPosition = 40
        band.run(.repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 0.1), .fadeAlpha(to: 1, duration: 0.1)])))
        addChild(band)
        band.run(.sequence([.wait(forDuration: duration), .removeFromParent()]))
    }

    /// A wall of sound sweeping along the ground in one lane. Jump it.
    private func sendShockwave(x: CGFloat, lane: CGFloat, dir: CGFloat, delay: TimeInterval) {
        let wave = SKShapeNode(ellipseOf: CGSize(width: 46, height: 120))
        wave.fillColor = SKColor(red: 0.9, green: 0.4, blue: 1, alpha: 0.35); wave.strokeColor = .white
        wave.lineWidth = 5; wave.glowWidth = 8
        wave.position = CGPoint(x: x, y: lane + 50); wave.zPosition = 300 - lane + 2; wave.alpha = 0
        addChild(wave)
        var landed = false
        let speed: CGFloat = 640, life: TimeInterval = 1.5
        wave.run(.sequence([
            .wait(forDuration: delay), .fadeIn(withDuration: 0.05),
            .customAction(withDuration: life) { [weak self] node, t in
                guard let self else { return }
                node.position.x = x + dir * speed * t
                node.alpha = 1 - t / CGFloat(life) * 0.6
                let h = self.hero
                if !landed, abs(h.rig.position.x - node.position.x) <= 36, abs(h.rig.position.y - lane) <= 46, h.rig.height < 55, h.vulnerable {
                    landed = true
                    h.receive(.batShock, power: 1, scale: 1, from: self.batKing, away: dir)
                    self.spawnImpact(at: CGPoint(x: h.rig.position.x, y: h.rig.position.y + h.rig.height + 60), damage: Hit.batShock.damage)
                }
            },
            .removeFromParent()]))
    }

    private func summonBats(_ n: Int) {
        guard let c = activeEncounter?.center else { return }
        for i in 0..<n {
            let f = spawnLevelEnemy(Spawn(.bat, i % 2 == 0 ? .left : .right, tier: 0.2), center: c)
            activeEncounter?.foes.append(f)
        }
        camShake = max(camShake, 5)
        if let king = batKing { showBubble("SCREEEECH!", over: king, duration: 1.6) }
    }

    /// The King falls and his bats go with him.
    private func batKingDefeated() {
        guard let k = batKing else { return }
        batKing = nil
        bossBar.isHidden = true; bossName.isHidden = true
        bossSlam(2)
        for f in activeEncounter?.foes ?? [] where !f.dead && f !== k {
            f.receive(.crumble, power: 1, scale: 1, from: nil, away: f.rig.position.x >= k.rig.position.x ? 1 : -1)
        }
    }

    private func bossCard(_ text: String, color: SKColor = SKColor(red: 0.85, green: 0.75, blue: 1, alpha: 1)) {
        let card = SKLabelNode(fontNamed: GameFont.banner)
        card.text = text; card.fontSize = 70; card.fontColor = color
        card.verticalAlignmentMode = .center; card.zPosition = 10_000
        let shadow = SKLabelNode(fontNamed: GameFont.banner)
        shadow.text = text; shadow.fontSize = 70; shadow.fontColor = .black; shadow.verticalAlignmentMode = .center
        shadow.position = CGPoint(x: 5, y: -5); shadow.zPosition = -1
        card.addChild(shadow)
        card.position = CGPoint(x: 0, y: 110); card.setScale(2.4); card.alpha = 0
        cam.addChild(card)
        card.run(.sequence([.group([.scale(to: 1, duration: 0.18), .fadeIn(withDuration: 0.18)]), .wait(forDuration: 1.7),
                            .fadeOut(withDuration: 0.4), .removeFromParent()]))
    }

    /// Graves open across the arena, then skeletons climb out of them.
    private func summonSkeletons(count: Int, giant: Bool) {
        guard let c = activeEncounter?.center else { return }
        let half = size.width / 2
        for i in 0..<count {
            let x = c + CGFloat.random(in: (-half + 200)...(half - 200)), lane = CGFloat.random(in: 40...180)
            let makeGiant = giant && i == 0 && !enemies.contains { $0.stats.size > 1 && !$0.dead }
            let mound = styled(SKShapeNode(ellipseOf: CGSize(width: 90, height: 28)), SKColor(red: 0.36, green: 0.25, blue: 0.18, alpha: 1), line: 4)
            mound.position = CGPoint(x: x, y: lane); mound.zPosition = 300 - lane - 1; mound.setScale(0.2)
            addChild(mound)
            let delay = 0.8 + Double(i) * 0.25
            mound.run(.sequence([.scale(to: 1, duration: 0.3), .repeat(.sequence([.moveBy(x: 3, y: 0, duration: 0.04), .moveBy(x: -6, y: 0, duration: 0.08), .moveBy(x: 3, y: 0, duration: 0.04)]), count: 4),
                                 .wait(forDuration: max(0, delay - 0.8)), .fadeOut(withDuration: 0.5), .removeFromParent()]))
            run(.sequence([.wait(forDuration: delay), .run { [weak self] in
                guard let self, let n = self.necro, !n.dead, self.activeEncounter != nil else { return }
                let f = self.spawnEnemy(x: x, y: lane, giant: makeGiant, tier: 0.3)
                f.rig.facingRight = x < self.hero.rig.position.x
                f.rig.alpha = 0; f.rig.run(.fadeIn(withDuration: 0.25))
                self.activeEncounter?.foes.append(f)
                self.poof(at: CGPoint(x: x, y: lane))
            }]))
        }
    }

    /// A red mark on the floor where you were standing; a second later bone spikes burst up through it.
    private func eruption(x: CGFloat, lane: CGFloat) {
        let marker = SKShapeNode(ellipseOf: CGSize(width: 210, height: 60))
        marker.fillColor = SKColor(red: 1, green: 0.1, blue: 0.2, alpha: 0.22)
        marker.strokeColor = SKColor(red: 1, green: 0.3, blue: 0.3, alpha: 0.95); marker.lineWidth = 4
        marker.position = CGPoint(x: x, y: lane); marker.zPosition = 40
        marker.run(.repeatForever(.sequence([.fadeAlpha(to: 0.4, duration: 0.1), .fadeAlpha(to: 1, duration: 0.1)])))
        addChild(marker)
        run(.sequence([.wait(forDuration: 0.9), .run { [weak self] in
            guard let self else { return }
            marker.removeFromParent()
            self.camShake = max(self.camShake, 6)
            for k in 0..<5 {
                let h = CGFloat.random(in: 70...115)
                let p = CGMutablePath()
                p.move(to: CGPoint(x: -9, y: 0)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: 9, y: 0)); p.closeSubpath()
                let spike = styled(SKShapeNode(path: p), SKColor(white: 0.93, alpha: 1), line: 4)
                spike.position = CGPoint(x: x + CGFloat(k - 2) * 40 + .random(in: -8...8), y: lane + .random(in: -8...8))
                spike.zPosition = 300 - lane + 1; spike.yScale = 0.1
                self.addChild(spike)
                spike.run(.sequence([.scaleY(to: 1, duration: 0.08), .wait(forDuration: 0.35),
                                     .group([.fadeOut(withDuration: 0.2), .scaleY(to: 0.1, duration: 0.2)]), .removeFromParent()]))
            }
            self.poof(at: CGPoint(x: x, y: lane))
            let h = self.hero
            if abs(h.rig.position.x - x) <= 105, abs(h.rig.position.y - lane) <= 32, h.rig.height < 60, h.vulnerable {
                h.receive(.eruption, power: 1, scale: self.necro?.stats.damageScale ?? 1, from: self.necro, away: h.rig.position.x >= x ? 1 : -1)
                self.spawnImpact(at: CGPoint(x: h.rig.position.x, y: h.rig.position.y + h.rig.height + 60), damage: Hit.eruption.damage)
            }
        }]))
    }

    private func poof(at p: CGPoint) {
        for _ in 0..<8 {
            let c = SKShapeNode(circleOfRadius: .random(in: 10...22))
            c.fillColor = SKColor(red: 0.55, green: 0.3, blue: 0.85, alpha: 0.7); c.strokeColor = .clear
            c.position = CGPoint(x: p.x + .random(in: -30...30), y: p.y + .random(in: 10...110)); c.zPosition = 9000
            addChild(c)
            c.run(.sequence([.group([.moveBy(x: .random(in: -50...50), y: .random(in: 20...80), duration: 0.5),
                                     .scale(to: 1.8, duration: 0.5), .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
        }
    }

    /// The Necromancer falls: his summons crumble with him.
    private func necroDefeated() {
        guard let n = necro else { return }
        necro = nil
        bossBar.isHidden = true; bossName.isHidden = true
        bossSlam(2)
        for f in activeEncounter?.foes ?? [] where !f.dead && f !== n {
            f.receive(.crumble, power: 1, scale: 1, from: nil, away: f.rig.position.x >= n.rig.position.x ? 1 : -1)
        }
    }

    // MARK: GO prompt and speech bubbles

    private func setupGoLabel() {
        let shadow = SKLabelNode(fontNamed: GameFont.banner)
        for l in [goLabel, shadow] {
            l.text = "GO →"; l.fontSize = 56
            l.horizontalAlignmentMode = .center; l.verticalAlignmentMode = .center
        }
        goLabel.fontColor = .white; shadow.fontColor = .black
        shadow.position = CGPoint(x: 4, y: -4); shadow.zPosition = -1
        goLabel.addChild(shadow)
        goLabel.zPosition = 10_000
        goLabel.isHidden = true
        cam.addChild(goLabel)
    }

    private func showGo() {
        goUntilX = hero.rig.position.x + 420
        goLabel.removeAllActions(); goLabel.isHidden = false; goLabel.alpha = 1
        goLabel.run(.repeatForever(.sequence([.fadeAlpha(to: 0.25, duration: 0.35), .fadeAlpha(to: 1, duration: 0.35)])))
    }

    private func hideGo() {
        goUntilX = nil
        goLabel.removeAllActions(); goLabel.isHidden = true
    }

    /// A chunky speech bubble over a fighter (follows him) or at a fixed world point.
    private func showBubble(_ text: String, over target: Fighter? = nil, at point: CGPoint = .zero, duration: TimeInterval = 2.8) {
        let label = SKLabelNode(fontNamed: GameFont.speech)
        label.text = text; label.fontSize = 27; label.fontColor = ink
        label.verticalAlignmentMode = .center
        let w = label.frame.width + 32, h = label.frame.height + 22
        let tailPath = CGMutablePath()
        tailPath.move(to: CGPoint(x: -9, y: 4)); tailPath.addLine(to: CGPoint(x: 9, y: 4)); tailPath.addLine(to: CGPoint(x: 0, y: -14)); tailPath.closeSubpath()
        let tail = SKShapeNode(path: tailPath)
        tail.fillColor = .white; tail.strokeColor = ink; tail.lineWidth = 4
        let box = SKShapeNode(rect: CGRect(x: -w / 2, y: 0, width: w, height: h), cornerRadius: 10)
        box.fillColor = .white; box.strokeColor = ink; box.lineWidth = 4; box.zPosition = 1
        label.position = CGPoint(x: 0, y: h / 2); label.zPosition = 2
        let node = SKNode()
        node.addChild(tail); node.addChild(box); node.addChild(label)
        node.position = point; node.zPosition = 9500
        node.setScale(0.5); node.alpha = 0
        node.run(.group([.scale(to: 1, duration: 0.12), .fadeIn(withDuration: 0.12)]))
        addChild(node)
        bubbles.append(Bubble(node: node, target: target, until: gameTime + duration))
    }

    private func updateBubbles(now: TimeInterval) {
        for b in bubbles {
            if let t = b.target { b.node.position = CGPoint(x: t.rig.position.x, y: t.rig.position.y + (t.rig.height + 98) * t.rig.scaleFactor + 34) }
        }
        bubbles.removeAll { b in
            guard now >= b.until || (b.target?.dead ?? false) else { return false }
            b.node.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
            return true
        }
    }

    // MARK: World

    private func buildWorld(_ theme: Theme = .forest) {
        if theme == .cave { buildCave(); return }
        if theme == .mirror { buildMirror(); return }
        if theme == .forge { buildForge(); return }
        if theme == .graveyard { buildGraveyard(); return }
        if theme == .snow { buildSnow(); return }
        // Far hills
        addLayer(factor: 0.2, tileW: 700, z: -3000) {
            let t = SKNode()
            for (x, w, h) in [(180, 620, 240), (520, 520, 180)] as [(CGFloat, CGFloat, CGFloat)] {
                let hill = styled(SKShapeNode(ellipseOf: CGSize(width: w, height: h)),
                                  SKColor(red: 0.45, green: 0.68, blue: 0.62, alpha: 1))
                hill.position = CGPoint(x: x, y: self.groundHeight + 20)
                t.addChild(hill)
            }
            return t
        }
        // Mid pines
        addLayer(factor: 0.5, tileW: 520, z: -2000) {
            let t = SKNode()
            for (x, s) in [(120, 1.0), (390, 1.4)] as [(CGFloat, CGFloat)] {
                let tree = self.pine()
                tree.position = CGPoint(x: x, y: self.groundHeight - 50)   // sunk so vertical parallax never exposes a gap
                tree.setScale(s)
                t.addChild(tree)
            }
            return t
        }
        // Ground
        addLayer(factor: 1.0, tileW: 400, z: -1000) {
            let t = SKNode()
            for (i, c) in [SKColor(red: 0.20, green: 0.50, blue: 0.48, alpha: 1),
                           SKColor(red: 0.23, green: 0.55, blue: 0.52, alpha: 1)].enumerated() {
                // Extends well below the lane so there's no gap when the camera follows the hero down
                let r = SKShapeNode(rect: CGRect(x: CGFloat(i) * 200, y: -600, width: 200, height: self.groundHeight + 600))
                r.fillColor = c
                r.strokeColor = .clear
                t.addChild(r)
            }
            let edge = SKShapeNode(rect: CGRect(x: -4, y: self.groundHeight - 2, width: 408, height: 4))
            edge.fillColor = ink
            edge.strokeColor = .clear
            t.addChild(edge)
            return t
        }
    }

    /// Falling snow, drawn over the world and under the HUD.
    private func startSnowfall() {
        let n = SKNode(); n.zPosition = 9500
        cam.addChild(n); snowFall = n
        let w = size.width, h = size.height
        n.run(.repeatForever(.sequence([.run { [weak n] in
            guard let n else { return }
            let f = SKShapeNode(circleOfRadius: .random(in: 1.5...3.6))
            f.fillColor = .white; f.strokeColor = .clear; f.alpha = .random(in: 0.55...0.95)
            f.position = CGPoint(x: .random(in: (-w / 2 - 60)...(w / 2 + 120)), y: h / 2 + 12)
            n.addChild(f)
            f.run(.sequence([.moveBy(x: -110 + .random(in: -40...40), y: -(h + 30), duration: .random(in: 3.2...5.2)), .removeFromParent()]))
        }, .wait(forDuration: 0.05)])))
    }

    private func snowPine() -> SKNode {
        let tree = SKNode()
        tree.addChild(styled(SKShapeNode(rect: CGRect(x: -12, y: 0, width: 24, height: 60)), SKColor(red: 0.36, green: 0.27, blue: 0.24, alpha: 1)))
        for (i, w) in [(0, 150), (1, 120), (2, 85)] as [(Int, CGFloat)] {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -w / 2, y: 0)); p.addLine(to: CGPoint(x: w / 2, y: 0)); p.addLine(to: CGPoint(x: 0, y: 110)); p.closeSubpath()
            let layer = styled(SKShapeNode(path: p), SKColor(red: 0.17, green: 0.36, blue: 0.40, alpha: 1))
            layer.position = CGPoint(x: 0, y: 40 + CGFloat(i) * 55)
            tree.addChild(layer)
            let cap = CGMutablePath()                                  // snow lying on the branches
            cap.move(to: CGPoint(x: 0, y: 110)); cap.addLine(to: CGPoint(x: w * 0.27, y: 60)); cap.addLine(to: CGPoint(x: w * 0.08, y: 66))
            cap.addLine(to: CGPoint(x: 0, y: 52)); cap.addLine(to: CGPoint(x: -w * 0.1, y: 66)); cap.addLine(to: CGPoint(x: -w * 0.27, y: 60)); cap.closeSubpath()
            let snow = styled(SKShapeNode(path: cap), SKColor(white: 0.97, alpha: 1), line: 3)
            snow.position = layer.position
            tree.addChild(snow)
        }
        return tree
    }

    private func buildSnow() {
        addLayer(factor: 0.2, tileW: 760, z: -3000) {                  // far mountains
            let t = SKNode()
            for (x, w, h) in [(190, 520, 300), (560, 440, 220)] as [(CGFloat, CGFloat, CGFloat)] {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: -w / 2, y: 0)); p.addLine(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: w / 2, y: 0)); p.closeSubpath()
                let peak = styled(SKShapeNode(path: p), SKColor(red: 0.62, green: 0.74, blue: 0.86, alpha: 1))
                peak.position = CGPoint(x: x, y: self.groundHeight - 40)
                t.addChild(peak)
                let cap = CGMutablePath()
                cap.move(to: CGPoint(x: 0, y: h)); cap.addLine(to: CGPoint(x: w * 0.17, y: h * 0.66)); cap.addLine(to: CGPoint(x: w * 0.05, y: h * 0.7))
                cap.addLine(to: CGPoint(x: -w * 0.04, y: h * 0.6)); cap.addLine(to: CGPoint(x: -w * 0.17, y: h * 0.66)); cap.closeSubpath()
                let ice = styled(SKShapeNode(path: cap), SKColor(white: 0.97, alpha: 1), line: 3)
                ice.position = peak.position
                t.addChild(ice)
            }
            return t
        }
        addLayer(factor: 0.5, tileW: 520, z: -2000) {
            let t = SKNode()
            for (x, s) in [(120, 1.0), (390, 1.4)] as [(CGFloat, CGFloat)] {
                let tree = self.snowPine()
                tree.position = CGPoint(x: x, y: self.groundHeight - 50)
                tree.setScale(s)
                t.addChild(tree)
            }
            return t
        }
        addLayer(factor: 1.0, tileW: 400, z: -1000) {                  // packed snow
            let t = SKNode()
            for (i, c) in [SKColor(red: 0.90, green: 0.94, blue: 0.98, alpha: 1), SKColor(red: 0.84, green: 0.90, blue: 0.96, alpha: 1)].enumerated() {
                let r = SKShapeNode(rect: CGRect(x: CGFloat(i) * 200, y: -600, width: 200, height: self.groundHeight + 600))
                r.fillColor = c; r.strokeColor = .clear
                t.addChild(r)
            }
            let edge = SKShapeNode(rect: CGRect(x: -4, y: self.groundHeight - 2, width: 408, height: 4))
            edge.fillColor = ink; edge.strokeColor = .clear
            t.addChild(edge)
            return t
        }
    }

    private func buildCave() {
        // Far rock wall
        addLayer(factor: 0.2, tileW: 700, z: -3000) {
            let t = SKNode()
            for (x, w, h) in [(180, 640, 300), (540, 500, 220)] as [(CGFloat, CGFloat, CGFloat)] {
                let rock = styled(SKShapeNode(ellipseOf: CGSize(width: w, height: h)), SKColor(red: 0.17, green: 0.13, blue: 0.25, alpha: 1))
                rock.position = CGPoint(x: x, y: self.groundHeight + 20)
                t.addChild(rock)
            }
            return t
        }
        // Stalagmites
        addLayer(factor: 0.5, tileW: 520, z: -2000) {
            let t = SKNode()
            for (x, s) in [(110, 1.0), (390, 1.5)] as [(CGFloat, CGFloat)] {
                for (dx, w, h) in [(-34, 70, 150), (0, 90, 230), (38, 60, 120)] as [(CGFloat, CGFloat, CGFloat)] {
                    let p = CGMutablePath()
                    p.move(to: CGPoint(x: -w / 2, y: 0)); p.addLine(to: CGPoint(x: w * 0.1, y: h)); p.addLine(to: CGPoint(x: w / 2, y: 0)); p.closeSubpath()
                    let spike = styled(SKShapeNode(path: p), SKColor(red: 0.24, green: 0.2, blue: 0.34, alpha: 1))
                    spike.position = CGPoint(x: x + dx * s, y: self.groundHeight - 50)
                    spike.setScale(s)
                    t.addChild(spike)
                }
            }
            return t
        }
        // Stone floor
        addLayer(factor: 1.0, tileW: 400, z: -1000) {
            let t = SKNode()
            for (i, c) in [SKColor(red: 0.27, green: 0.24, blue: 0.33, alpha: 1), SKColor(red: 0.30, green: 0.27, blue: 0.37, alpha: 1)].enumerated() {
                let r = SKShapeNode(rect: CGRect(x: CGFloat(i) * 200, y: -600, width: 200, height: self.groundHeight + 600))
                r.fillColor = c; r.strokeColor = .clear
                t.addChild(r)
            }
            let edge = SKShapeNode(rect: CGRect(x: -4, y: self.groundHeight - 2, width: 408, height: 4))
            edge.fillColor = ink; edge.strokeColor = .clear
            t.addChild(edge)
            return t
        }
    }

    /// A graveyard at night: a low moon, bare trees, leaning tombstones and crosses behind an iron fence, patchy earth underfoot.
    private func buildGraveyard() {
        let bone = SKColor(red: 0.50, green: 0.53, blue: 0.60, alpha: 1)
        addLayer(factor: 0.15, tileW: 900, z: -3000) {
            let t = SKNode()
            let moon = SKShapeNode(circleOfRadius: 48)
            moon.fillColor = SKColor(red: 0.92, green: 0.93, blue: 0.80, alpha: 1); moon.strokeColor = .clear; moon.glowWidth = 22
            moon.position = CGPoint(x: 620, y: self.groundHeight + 290)
            t.addChild(moon)
            for x in [90, 380, 760] as [CGFloat] {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: x, y: self.groundHeight - 20)); p.addLine(to: CGPoint(x: x + 4, y: self.groundHeight + 200))
                p.move(to: CGPoint(x: x + 3, y: self.groundHeight + 90)); p.addLine(to: CGPoint(x: x - 60, y: self.groundHeight + 160))
                p.move(to: CGPoint(x: x + 4, y: self.groundHeight + 140)); p.addLine(to: CGPoint(x: x + 64, y: self.groundHeight + 210))
                p.move(to: CGPoint(x: x + 4, y: self.groundHeight + 190)); p.addLine(to: CGPoint(x: x - 30, y: self.groundHeight + 250))
                let tree = SKShapeNode(path: p)
                tree.strokeColor = SKColor(red: 0.07, green: 0.07, blue: 0.11, alpha: 1); tree.lineWidth = 9; tree.lineCap = .round
                t.addChild(tree)
            }
            return t
        }
        addLayer(factor: 0.5, tileW: 640, z: -2000) {
            let t = SKNode()
            for (i, x) in ([60, 230, 400, 560] as [CGFloat]).enumerated() {
                if i % 2 == 0 {
                    let stone = styled(SKShapeNode(rect: CGRect(x: x - 26, y: self.groundHeight - 30, width: 52, height: 90), cornerRadius: 24), bone, line: 4)
                    stone.zRotation = i == 0 ? 0.08 : -0.06
                    t.addChild(stone)
                } else {
                    t.addChild(styled(SKShapeNode(rect: CGRect(x: x - 7, y: self.groundHeight - 30, width: 14, height: 100)), bone, line: 4))
                    t.addChild(styled(SKShapeNode(rect: CGRect(x: x - 26, y: self.groundHeight + 36, width: 52, height: 13)), bone, line: 4))
                }
            }
            let rail = SKShapeNode(rect: CGRect(x: 0, y: self.groundHeight + 8, width: 640, height: 5))
            rail.fillColor = SKColor(red: 0.12, green: 0.12, blue: 0.17, alpha: 1); rail.strokeColor = .clear
            t.addChild(rail)
            return t
        }
        addLayer(factor: 1.0, tileW: 400, z: -1000) {
            let t = SKNode()
            for (i, c) in [SKColor(red: 0.14, green: 0.17, blue: 0.16, alpha: 1), SKColor(red: 0.18, green: 0.21, blue: 0.19, alpha: 1)].enumerated() {
                let r = SKShapeNode(rect: CGRect(x: CGFloat(i) * 200, y: -600, width: 200, height: self.groundHeight + 600))
                r.fillColor = c; r.strokeColor = .clear
                t.addChild(r)
            }
            let edge = SKShapeNode(rect: CGRect(x: -4, y: self.groundHeight - 3, width: 408, height: 5))
            edge.fillColor = SKColor(red: 0.26, green: 0.36, blue: 0.28, alpha: 1); edge.strokeColor = .clear
            t.addChild(edge)
            return t
        }
    }

    /// A forge: furnaces glowing in the far wall, iron pillars with hanging chains, riveted plate floor with a hot seam.
    private func buildForge() {
        let ember = SKColor(red: 1, green: 0.55, blue: 0.15, alpha: 1)
        let iron = SKColor(red: 0.20, green: 0.12, blue: 0.11, alpha: 1)
        addLayer(factor: 0.2, tileW: 760, z: -3000) {
            let t = SKNode()
            for x in [80, 450] as [CGFloat] {
                let furnace = styled(SKShapeNode(rect: CGRect(x: x, y: self.groundHeight - 30, width: 200, height: 290), cornerRadius: 26), iron, line: 5)
                let mouth = SKShapeNode(rect: CGRect(x: x + 50, y: self.groundHeight + 25, width: 100, height: 85), cornerRadius: 42)
                mouth.fillColor = ember; mouth.strokeColor = SKColor(red: 1, green: 0.85, blue: 0.4, alpha: 1); mouth.lineWidth = 3; mouth.glowWidth = 14
                let chimney = styled(SKShapeNode(rect: CGRect(x: x + 75, y: self.groundHeight + 255, width: 50, height: 130)), iron, line: 4)
                chimney.zPosition = -1
                t.addChild(chimney); t.addChild(furnace); t.addChild(mouth)
            }
            return t
        }
        addLayer(factor: 0.5, tileW: 540, z: -2000) {
            let t = SKNode()
            for x in [100, 380] as [CGFloat] {
                let pillar = styled(SKShapeNode(rect: CGRect(x: x - 24, y: self.groundHeight - 50, width: 48, height: 380), cornerRadius: 5), SKColor(red: 0.16, green: 0.10, blue: 0.10, alpha: 1))
                t.addChild(pillar)
                for i in 0..<9 {                                                                  // a hanging chain
                    let link = styled(SKShapeNode(ellipseOf: CGSize(width: 12, height: 18)), SKColor(red: 0.38, green: 0.34, blue: 0.34, alpha: 1), line: 2)
                    link.position = CGPoint(x: x + 60, y: self.groundHeight + 320 - CGFloat(i) * 17)
                    t.addChild(link)
                }
            }
            let anvil = CGMutablePath()
            anvil.move(to: CGPoint(x: 210, y: self.groundHeight - 20)); anvil.addLine(to: CGPoint(x: 290, y: self.groundHeight - 20))
            anvil.addLine(to: CGPoint(x: 280, y: self.groundHeight + 20)); anvil.addLine(to: CGPoint(x: 330, y: self.groundHeight + 30))
            anvil.addLine(to: CGPoint(x: 180, y: self.groundHeight + 50)); anvil.addLine(to: CGPoint(x: 220, y: self.groundHeight + 20)); anvil.closeSubpath()
            t.addChild(styled(SKShapeNode(path: anvil), SKColor(red: 0.28, green: 0.26, blue: 0.30, alpha: 1), line: 4))
            return t
        }
        addLayer(factor: 1.0, tileW: 400, z: -1000) {
            let t = SKNode()
            for (i, c) in [SKColor(red: 0.17, green: 0.12, blue: 0.12, alpha: 1), SKColor(red: 0.24, green: 0.17, blue: 0.16, alpha: 1)].enumerated() {
                let r = SKShapeNode(rect: CGRect(x: CGFloat(i) * 200, y: -600, width: 200, height: self.groundHeight + 600))
                r.fillColor = c; r.strokeColor = .clear
                t.addChild(r)
                for (dx, dy) in [(20, 20), (170, 20), (20, 160), (170, 160)] as [(CGFloat, CGFloat)] {
                    let rivet = SKShapeNode(circleOfRadius: 4)
                    rivet.fillColor = SKColor(white: 0.1, alpha: 0.6); rivet.strokeColor = .clear
                    rivet.position = CGPoint(x: CGFloat(i) * 200 + dx, y: dy)
                    t.addChild(rivet)
                }
            }
            let seam = SKShapeNode(rect: CGRect(x: -4, y: self.groundHeight - 3, width: 408, height: 6))
            seam.fillColor = ember; seam.strokeColor = .clear; seam.glowWidth = 5
            t.addChild(seam)
            return t
        }
    }

    /// A ruined ballroom: tall gilt-framed mirrors, pillars and a pale marble floor.
    private func buildMirror() {
        let gold = SKColor(red: 0.88, green: 0.70, blue: 0.30, alpha: 1)
        addLayer(factor: 0.2, tileW: 700, z: -3000) {
            let t = SKNode()
            for x in [60, 380] as [CGFloat] {
                let frame = styled(SKShapeNode(rect: CGRect(x: x, y: self.groundHeight - 40, width: 200, height: 420), cornerRadius: 70),
                                   SKColor(red: 0.26, green: 0.34, blue: 0.58, alpha: 1), line: 6)
                frame.strokeColor = gold
                t.addChild(frame)
                let glint = CGMutablePath()
                glint.move(to: CGPoint(x: x + 50, y: self.groundHeight + 40)); glint.addLine(to: CGPoint(x: x + 90, y: self.groundHeight + 40))
                glint.addLine(to: CGPoint(x: x + 170, y: self.groundHeight + 300)); glint.addLine(to: CGPoint(x: x + 130, y: self.groundHeight + 300)); glint.closeSubpath()
                let g = SKShapeNode(path: glint)
                g.fillColor = SKColor(white: 1, alpha: 0.12); g.strokeColor = .clear
                t.addChild(g)
            }
            return t
        }
        addLayer(factor: 0.5, tileW: 520, z: -2000) {
            let t = SKNode()
            for x in [90, 350] as [CGFloat] {
                let pillar = styled(SKShapeNode(rect: CGRect(x: x - 26, y: self.groundHeight - 50, width: 52, height: 360), cornerRadius: 6), SKColor(red: 0.20, green: 0.16, blue: 0.32, alpha: 1))
                let cap = styled(SKShapeNode(rect: CGRect(x: x - 36, y: self.groundHeight + 290, width: 72, height: 22), cornerRadius: 5), gold, line: 3)
                t.addChild(pillar); t.addChild(cap)
            }
            let orb = SKShapeNode(circleOfRadius: 11)
            orb.fillColor = SKColor(red: 0.7, green: 0.95, blue: 1, alpha: 1); orb.strokeColor = .clear; orb.glowWidth = 10
            orb.position = CGPoint(x: 220, y: self.groundHeight + 260)
            t.addChild(orb)
            return t
        }
        addLayer(factor: 1.0, tileW: 400, z: -1000) {
            let t = SKNode()
            for (i, c) in [SKColor(red: 0.20, green: 0.15, blue: 0.32, alpha: 1), SKColor(red: 0.34, green: 0.28, blue: 0.50, alpha: 1)].enumerated() {
                let r = SKShapeNode(rect: CGRect(x: CGFloat(i) * 200, y: -600, width: 200, height: self.groundHeight + 600))
                r.fillColor = c; r.strokeColor = .clear
                t.addChild(r)
            }
            let sheen = SKShapeNode(rect: CGRect(x: 0, y: self.groundHeight - 40, width: 400, height: 10))
            sheen.fillColor = SKColor(white: 1, alpha: 0.1); sheen.strokeColor = .clear
            t.addChild(sheen)
            let edge = SKShapeNode(rect: CGRect(x: -4, y: self.groundHeight - 2, width: 408, height: 4))
            edge.fillColor = ink; edge.strokeColor = .clear
            t.addChild(edge)
            return t
        }
    }

    private func pine() -> SKNode {
        let tree = SKNode()
        let trunk = styled(SKShapeNode(rect: CGRect(x: -12, y: 0, width: 24, height: 60)),
                           SKColor(red: 0.42, green: 0.28, blue: 0.2, alpha: 1))
        tree.addChild(trunk)
        for (i, w) in [(0, 150), (1, 120), (2, 85)] as [(Int, CGFloat)] {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -w / 2, y: 0))
            p.addLine(to: CGPoint(x: w / 2, y: 0))
            p.addLine(to: CGPoint(x: 0, y: 110))
            p.closeSubpath()
            let layer = styled(SKShapeNode(path: p), SKColor(red: 0.16, green: 0.40, blue: 0.34, alpha: 1))
            layer.position = CGPoint(x: 0, y: 40 + CGFloat(i) * 55)
            tree.addChild(layer)
        }
        return tree
    }

    /// Tiles must be identical (period = tileW) so they loop seamlessly.
    /// fx / fy: 1 = moves with the world (foreground), 0 = pinned to the screen (infinitely far).
    /// fy defaults to fx; set it separately for levels that scroll mostly vertically (e.g. a mountain climb).
    private func addLayer(factor fx: CGFloat, factorY fy: CGFloat? = nil, tileW: CGFloat, z: CGFloat,
                          tile: () -> SKNode) {
        let layer = SKNode()
        layer.zPosition = z
        for i in 0..<(Int(ceil(size.width / tileW)) + 2) {
            let t = tile()
            t.position.x = CGFloat(i) * tileW
            layer.addChild(t)
        }
        addChild(layer)
        layers.append((layer, fx, fy ?? fx, tileW))
    }

    // MARK: Input

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        setupKeyboard()
        if ProcessInfo.processInfo.arguments.contains("-demo") { runDemo() }
        if ProcessInfo.processInfo.arguments.contains("-enemylog") {
            for (i, e) in enemies.enumerated() { e.logPrefix = "\(e.name)#\(i): " }
        }
        if ProcessInfo.processInfo.arguments.contains("-hittest") { runHitTest() }
        if ProcessInfo.processInfo.arguments.contains("-divetest") { runDiveTest() }
        if ProcessInfo.processInfo.arguments.contains("-itemtest") { runItemTest() }
        if ProcessInfo.processInfo.arguments.contains("-bowtest") { runBowTest() }
        if ProcessInfo.processInfo.arguments.contains("-fxtest") { runFxTest() }
        if ProcessInfo.processInfo.arguments.contains("-launchtest") { runLaunchTest() }
        if ProcessInfo.processInfo.arguments.contains("-juggletest") { runJuggleTest() }
        if ProcessInfo.processInfo.arguments.contains("-uppertest") { runUpperTest() }
        if ProcessInfo.processInfo.arguments.contains("-crowdtest") { hero.stats.maxHealth = 1_000_000; hero.restore() }
        if ProcessInfo.processInfo.arguments.contains("-dump") { dumpTree(hero.rig) }
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-pose"), i + 1 < args.count, let a = CharacterAnimation(rawValue: args[i + 1]) {
            run(.sequence([.wait(forDuration: 1), .run { [weak self] in   // slow-mo, hero and skeletons side by side
                guard let self else { return }
                if a == .shoot { ([self.hero] + self.enemies).forEach { $0.equip(Weapons.bow) } }
                for r in ([self.hero] + self.enemies).map(\.rig) {
                    if a == .slam || a == .uppercut { r.height = 150 }
                    r.speed = 0.08; r.play(a)
                }
            }]))
        }
    }

    /// Debug: print every descendant's transform and shape so a refactor can be diffed against a baseline.
    private func dumpTree(_ n: SKNode, depth: Int = 0) {
        for c in n.children {
            var line = String(repeating: " ", count: depth) + "\(type(of: c))"
            line += String(format: " p(%.1f,%.1f) z%.1f r%.3f s(%.2f,%.2f)", c.position.x, c.position.y, c.zPosition, c.zRotation, c.xScale, c.yScale)
            if let sh = c as? SKShapeNode {
                let b = sh.path?.boundingBox ?? .zero
                line += String(format: " box(%.1f,%.1f,%.1f,%.1f) lw%.1f glow%.1f ", b.minX, b.minY, b.width, b.height, sh.lineWidth, sh.glowWidth)
                line += "fill=\(sh.fillColor.cgColor.components ?? []) stroke=\(sh.strokeColor.cgColor.components ?? [])"
            }
            NSLog("DUMP %@", line)
            dumpTree(c, depth: depth + 1)
        }
    }

    /// Hardware keyboard (Mac keyboard in the simulator). No view focus needed.
    /// WASD = move (Shift = run), arrow keys = swipes, Space = tap.
    private func setupKeyboard() {
        func attach(_ kb: GCKeyboard) {
            kb.keyboardInput?.keyChangedHandler = { [weak self] pad, _, code, down in
                guard let self else { return }
                let shift = (pad.button(forKeyCode: .leftShift)?.isPressed ?? false)
                    || (pad.button(forKeyCode: .rightShift)?.isPressed ?? false)
                let letters: [GCKeyCode: Character] = [.keyW: "w", .keyA: "a", .keyS: "s", .keyD: "d"]
                if let ch = letters[code] {
                    if down { self.input.keyDown(ch, run: shift) } else { self.input.keyUp(ch) }
                    return
                }
                if code == .keyE { self.input.onHold?(down); return }      // E = hold for special
                guard down else { return }
                switch code {
                case .upArrow:    self.input.fire(.swipe(.up))
                case .downArrow:  self.input.fire(.swipe(.down))
                case .leftArrow:  self.input.fire(.swipe(.left))
                case .rightArrow: self.input.fire(.swipe(.right))
                case .spacebar:   self.input.fire(.tap)
                case .keyH:       self.hitOverlay.enabled.toggle()
                case .keyP, .escape: DispatchQueue.main.async { self.onTogglePause?() }
                default: break
                }
            }
        }
        if let kb = GCKeyboard.coalesced { attach(kb) }
        NotificationCenter.default.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { n in
            if let kb = n.object as? GCKeyboard { attach(kb) }
        }
    }

    /// Launch with `-uppertest -opener hook|punch|dash`: opener, a varied delay, then an uppercut swipe.
    /// Logs the skeleton's state at the moment of the swipe and (via HIT lines) whether the uppercut connected.
    private func runUpperTest() {
        guard let e = enemies.first else { return }
        let opener = args.firstIndex(of: "-opener").map { args[$0 + 1] } ?? "hook"
        let walking = args.contains("-walk")
        func w(_ t: Double) -> SKAction { .wait(forDuration: t) }
        func fire(_ g: Gesture) -> SKAction { .run { [weak self] in self?.hero.handle(g) } }
        func sprint(_ on: Bool) -> SKAction { .run { [weak self] in if on { self?.input.keyDown("d", run: true) } else { self?.input.keyUp("d") } } }
        func setup(_ title: String, gap: CGFloat) -> SKAction { .run { [weak self] in
            guard let self else { return }
            NSLog("UPPERTEST --- %@", title)
            self.input.keyUp("d")
            self.hero.restore(); self.hero.rig.position = CGPoint(x: 667, y: 120); self.hero.rig.facingRight = true
            for other in self.enemies where other !== e { other.rig.position.x = 3000 }
            e.restore(); e.rig.position = CGPoint(x: 667 + gap, y: 120); e.rig.facingRight = false
            e.brain = walking ? WalkBrain(direction: CGVector(dx: -1, dy: 0), intensity: 0.5) : nil
        } }
        let pre = SKAction.run { [weak self] in
            guard let self else { return }
            NSLog("UPPERTEST pre gap=%.0f down=%d hurt=%d launched=%d hero_move=%@", e.rig.position.x - self.hero.rig.position.x,
                  e.isDown ? 1 : 0, e.isHurt ? 1 : 0, e.launched ? 1 : 0, self.hero.currentMoveName)
        }
        var steps: [SKAction] = [w(1)]
        for delay in [0.1, 0.25, 0.45, 0.7] {
            switch opener {
            case "dash":
                for t in [0.55, 0.7, 0.85] {
                    steps += [setup("dash run=\(t) delay=\(delay)", gap: 400), sprint(true), w(t), fire(.swipe(.right)), w(delay), pre,
                              fire(.swipe(.up)), w(1.4)]
                }
            case "punch":
                for gap: CGFloat in [70, 100, 130] {
                    steps += [setup("punch2 gap=\(Int(gap)) delay=\(delay)", gap: gap), fire(.tap), w(0.2), fire(.tap), w(delay), pre,
                              fire(.swipe(.up)), w(1.4)]
                }
            default:
                for gap: CGFloat in [70, 100, 130] {
                    steps += [setup("hook gap=\(Int(gap)) delay=\(delay)", gap: gap), fire(.swipe(.right)), w(delay), pre,
                              fire(.swipe(.up)), w(1.4)]
                }
            }
        }
        steps.append(sprint(false))
        run(.sequence(steps))
    }

    /// Launch with `-juggletest`: hook, uppercut, then an air slam `slamAt` seconds after the uppercut. Logs both fighters every 50ms.
    private func runJuggleTest() {
        guard let e = enemies.first else { return }
        let slamAt = Double(args.firstIndex(of: "-slamat").flatMap { Double(args[$0 + 1]) } ?? 0.5)
        var t0: TimeInterval = 0
        func sample() -> SKAction { .run { [weak self] in
            guard let self else { return }
            NSLog("JUGGLE t=%.2f hero x=%.0f h=%.0f %@ | skel x=%.0f h=%.0f hp=%.0f launched=%d", self.gameTime - t0,
                  self.hero.rig.position.x, self.hero.rig.height, self.hero.currentMoveName, e.rig.position.x, e.rig.height, e.health, e.launched ? 1 : 0)
        } }
        var steps: [SKAction] = [
            .wait(forDuration: 1),
            .run { [weak self] in
                guard let self else { return }
                self.hero.restore(); self.hero.rig.position = CGPoint(x: 667, y: 120); self.hero.rig.facingRight = true
                e.restore(); e.rig.position = CGPoint(x: 757, y: 120); e.rig.facingRight = false
                for other in self.enemies where other !== e { other.rig.position.x = 3000 }
                t0 = self.gameTime
                self.hero.handle(.swipe(.right))
            },
            .wait(forDuration: 0.3), .run { [weak self] in self?.hero.handle(.swipe(.up)) }
        ]
        var elapsed = 0.0
        let slamStep = Int(slamAt / 0.05)
        for i in 0..<30 {
            steps.append(.wait(forDuration: 0.05)); elapsed += 0.05
            if i == slamStep { steps.append(.run { [weak self] in self?.hero.handle(.swipe(.down)) }) }
            steps.append(sample())
        }
        run(.sequence(steps))
    }

    /// Launch with `-launchtest`: hook into uppercut on a standing skeleton; reports how high it is launched and how long it stays up.
    private func runLaunchTest() {
        guard let e = enemies.first else { return }
        var peak: CGFloat = 0, airStart: TimeInterval?, airTime: TimeInterval = 0, t: TimeInterval = 0
        run(.repeatForever(.sequence([.wait(forDuration: 1.0 / 120), .run { [weak self] in
            guard let self else { return }
            t += 1.0 / 120 / Double(max(self.speed, 0.01))
            if e.launched || e.rig.height > 1 {
                peak = max(peak, e.rig.height); airStart = airStart ?? t; airTime = t - (airStart ?? t)
            }
        }])), withKey: "sampler")
        run(.sequence([
            .wait(forDuration: 1),
            .run { [weak self] in
                guard let self else { return }
                self.hero.restore(); self.hero.rig.position = CGPoint(x: 667, y: 120); self.hero.rig.facingRight = true
                e.restore(); e.rig.position = CGPoint(x: 757, y: 120); e.rig.facingRight = false
                for other in self.enemies where other !== e { other.rig.position.x = 3000 }
                self.hero.handle(.swipe(.right))
            },
            .wait(forDuration: 0.3), .run { [weak self] in self?.hero.handle(.swipe(.up)) },
            .wait(forDuration: 4),
            .run { NSLog("LAUNCHTEST enemy peak height %.1f pt, airborne %.2f s (game time)", peak, airTime) }
        ]))
    }

    /// Launch with `-fxtest`: one move per case; reports the peak zoom / slowest time scale / seconds active for each.
    private func runFxTest() {
        guard enemies.count >= 2 else { return }
        let e = enemies[0], e2 = enemies[1]
        func fire(_ g: Gesture) -> SKAction { .run { [weak self] in self?.hero.handle(g) } }
        func w(_ t: Double) -> SKAction { .wait(forDuration: t) }
        func act(_ f: @escaping (Fighter, Fighter) -> Void) -> SKAction { .run { [weak self] in if let self { f(self.hero, e) } } }
        func reset(_ title: String, gap: CGFloat = 90, second: Bool = false, lastOne: Bool = false) -> SKAction { .run { [weak self] in
            guard let self else { return }
            NSLog("FXTEST --- %@", title)
            self.fxPeakZoom = 0; self.fxMinScale = 1; self.fxActive = 0
            self.pickups.clear(); self.arrows.clear()
            self.hero.restore(); self.hero.rig.position = CGPoint(x: 667, y: 120); self.hero.rig.facingRight = true
            for (i, f) in self.enemies.enumerated() { f.restore(); f.rig.position = CGPoint(x: 1900 + CGFloat(i) * 150, y: 120); f.rig.facingRight = false }
            e.rig.position = CGPoint(x: 667 + gap, y: 120)
            if second { e2.rig.position = CGPoint(x: 667 + gap + 30, y: 126) }
            if lastOne { for f in self.enemies where f !== e { f.debugSetHealth(0) } }
        } }
        func report() -> SKAction { .run { [weak self] in
            guard let self else { return }
            NSLog("FXTEST result peak_zoom=%.3f min_timescale=%.2f active=%.2fs", self.fxPeakZoom, self.fxMinScale, self.fxActive)
        } }
        func sprint(_ on: Bool) -> SKAction { .run { [weak self] in if on { self?.input.keyDown("d", run: true) } else { self?.input.keyUp("d") } } }
        run(.sequence([
            w(1),
            reset("A jab (expect none)"), fire(.tap), w(2.2), report(),
            reset("B heavy attack / hook (light)"), fire(.swipe(.right)), w(2.2), report(),
            reset("C power dash (medium)", gap: 330), sprint(true), w(0.7), fire(.swipe(.right)), w(0.5), sprint(false), w(2.2), report(),
            reset("D hook into uppercut (heavy)"), fire(.swipe(.right)), w(0.3), fire(.swipe(.up)), w(3), report(),
            reset("E ground smash alone (heavy)", gap: 150), act { h, _ in h.debugPerform(MoveTable.groundSmash) }, w(2.5), report(),
            reset("F air slam dive + landing shockwave (massive)", gap: 60), fire(.swipe(.up)), w(0.5), fire(.swipe(.down)), w(3), report(),
            reset("G uppercut whiffs (windup only)", gap: 400), fire(.swipe(.right)), w(0.3), fire(.swipe(.up)), w(3), report(),
            reset("H a KO with other enemies left (kill)"), act { _, e in e.debugSetHealth(5) }, fire(.tap), w(2.2), report(),
            reset("I the LAST enemy falls (massive)", lastOne: true), act { _, e in e.debugSetHealth(5) }, fire(.tap), w(2.5), report(),
            reset("D2 uppercut alone, one enemy in range"), act { h, _ in h.debugPerform(MoveTable.chain(from: "heavy attack", .up)!) }, w(3), report(),
            reset("J same uppercut, TWO enemies in range (expect ~25% bigger than D2)", second: true),
            act { h, _ in h.debugPerform(MoveTable.chain(from: "heavy attack", .up)!) }, w(3), report(),
            reset("K ENEMY uppercuts the hero (expect none)"), act { _, e in e.debugPerform(MoveTable.chain(from: "heavy attack", .up)!) }, w(2.5), report()
        ]))
    }

    /// Launch with `-bowtest`: shooting, ammo, arrow hits, dodging, interrupts, quiver and swapping. Prints `BOWTEST` lines.
    private func runBowTest() {
        guard let e = enemies.first else { return }
        func fire(_ g: Gesture) -> SKAction { .run { [weak self] in self?.hero.handle(g) } }
        func w(_ t: Double) -> SKAction { .wait(forDuration: t) }
        func act(_ f: @escaping (Fighter, Fighter) -> Void) -> SKAction { .run { [weak self] in if let self { f(self.hero, e) } } }
        func report(_ label: String) -> SKAction { .run { [weak self] in
            guard let self else { return }
            let ground = self.pickups.pickups.map { "\($0.label)@\(Int($0.position.x))" }.joined(separator: ",")
            NSLog("BOWTEST %@ | hero hp=%ld weapon=%@ ammo=%@ | enemy hp=%ld weapon=%@ ammo=%@ | arrows in flight=%ld | ground=[%@]", label,
                  Int(self.hero.health), self.hero.weapon?.name ?? "none", self.hero.ammo.map(String.init) ?? "-",
                  Int(e.health), e.weapon?.name ?? "none", e.ammo.map(String.init) ?? "-", self.arrows.arrows.count, ground)
        } }
        func reset(_ title: String, gap: CGFloat = 400, dy: CGFloat = 0, bow: Bool = true) -> SKAction { .run { [weak self] in
            guard let self else { return }
            NSLog("BOWTEST --- %@", title)
            self.pickups.clear(); self.arrows.clear()
            self.hero.restore(); self.hero.rig.position = CGPoint(x: 667, y: 120); self.hero.rig.facingRight = true
            if bow { self.hero.equip(Weapons.bow) }
            e.restore(); e.rig.position = CGPoint(x: 667 + gap, y: 120 + dy); e.rig.facingRight = false
        } }
        let back: Gesture = .swipe(.left)       // hero faces right, so left = back
        var steps: [SKAction] = [
            w(1),
            reset("A back swipe shoots, enemy takes an arrow"), fire(back), w(0.3), report("mid-draw"), w(1.2), report("expect ammo 7, enemy hp 35.8"),
            reset("B arrow misses in another lane", dy: 80), fire(back), w(1.5), report("expect ammo 7, enemy hp 40"),
            reset("C jump over the arrow", gap: 300),
            act { _, e in e.equip(Weapons.bow); e.debugSetAmmo(3); e.rig.facingRight = false },
            act { _, e in e.handle(.swipe(.right)) }, fire(.swipe(.up)), w(1.4), report("expect hero hp 100 (arrow passed under)"),
            reset("D out of arrows", bow: true), act { h, _ in h.debugSetAmmo(0) }, fire(back), w(0.8), report("expect no shot, ammo 0"),
            reset("E melee still works with bow", gap: 90), fire(.tap), w(1.0), report("expect jab 6*1.0 = 6 dmg"),
            reset("F weak weapon moves", gap: 90), fire(.swipe(.right)), w(1.2), report("expect hook 12*0.6 = 7.2 dmg"),
            reset("G quiver refills"), act { h, _ in h.debugSetAmmo(2) }, .run { [weak self] in self?.pickups.place(.item(Items.quiver), at: CGPoint(x: 697, y: 120)) },
            fire(.swipe(.down)), w(0.9), report("expect ammo 8, quiver gone"),
            reset("H quiver ignored without a bow", bow: false), .run { [weak self] in self?.pickups.place(.item(Items.quiver), at: CGPoint(x: 697, y: 120)) },
            fire(.swipe(.down)), w(0.9), report("expect quiver stays"),
            reset("I full quiver is not wasted"), act { h, _ in h.debugSetAmmo(12) }, .run { [weak self] in self?.pickups.place(.item(Items.quiver), at: CGPoint(x: 697, y: 120)) },
            fire(.swipe(.down)), w(0.9), report("expect quiver stays, ammo 8"),
            reset("J hit mid-draw cancels the shot", gap: 90), fire(back), w(0.05),
            act { _, e in e.debugPerform(MoveTable.move(.grounded, .tap)!) }, w(1.2), report("expect ammo 8 (no arrow spent)"),
            reset("K swap bow for sword keeps arrows on the bow"), act { h, _ in h.debugSetAmmo(5) },
            .run { [weak self] in self?.pickups.place(.weapon(Weapons.sword), at: CGPoint(x: 697, y: 120)) },
            fire(.swipe(.down)), w(1.0), report("expect sword, bow on ground"),
            .run { [weak self] in
                if let bow = self?.pickups.pickups.first(where: { $0.label == "bow" }) {
                    if case .weapon(let wp) = bow.kind { NSLog("BOWTEST dropped bow carries ammo=%@", wp.ammo.map(String.init) ?? "-") }
                }
            },
            reset("L enemy archer kites a hero who does not move"),
            act { _, e in e.equip(Weapons.bow); e.brain = EnemyBrain(director: CrowdDirector()); e.rig.position.x = 667 + 300 }, w(10),
            report("archer after 10s")
        ]

        /// The hero walks (or runs) straight at an archer without attacking; logs the gap twice a second.
        func approach(_ title: String, tag: String, running: Bool, samples: Int) {
            steps.append(reset(title, gap: 450))
            steps.append(act { _, e in e.equip(Weapons.bow); e.rig.position.x = 667 + 450 })
            steps.append(.run { [weak self] in self?.input.keyDown("d", run: running) })
            for _ in 0..<samples {
                steps.append(w(0.5))
                steps.append(.run { [weak self] in
                    guard let self else { return }
                    NSLog("BOWTEST %@ gap=%.0f archer_hp=%.0f archer_ammo=%@ hero_hp=%.0f", tag, e.rig.position.x - self.hero.rig.position.x,
                          e.health, e.ammo.map(String.init) ?? "-", self.hero.health)
                })
            }
            steps.append(.run { [weak self] in self?.input.keyUp("d") })
        }
        approach("M hero walks at an archer", tag: "M", running: false, samples: 14)
        approach("N hero RUNS at an archer", tag: "N", running: true, samples: 10)
        run(.sequence(steps))
    }

    /// Launch with `-itemtest`: pickups, swaps, disarming and bare-handed damage. Prints `ITEMTEST` state lines.
    private func runItemTest() {
        guard let e = enemies.first else { return }
        func fire(_ g: Gesture) -> SKAction { .run { [weak self] in self?.hero.handle(g) } }
        func w(_ t: Double) -> SKAction { .wait(forDuration: t) }
        func act(_ f: @escaping (Fighter, Fighter) -> Void) -> SKAction { .run { [weak self] in if let self { f(self.hero, e) } } }
        func place(_ k: PickupKind, dx: CGFloat) -> SKAction { .run { [weak self] in self?.pickups.place(k, at: CGPoint(x: 667 + dx, y: 120)) } }
        func report(_ label: String) -> SKAction { .run { [weak self] in
            guard let self else { return }
            let ground = self.pickups.pickups.map { "\($0.label)@\(Int($0.position.x))" + ($0.landed ? "" : "(air)") }.joined(separator: ",")
            NSLog("ITEMTEST %@ | hero hp=%ld weapon=%@ | enemy hp=%ld weapon=%@ | ground=[%@]", label, Int(self.hero.health),
                  self.hero.weapon?.name ?? "none", Int(e.health), e.weapon?.name ?? "none", ground)
        } }
        func reset(_ title: String, gap: CGFloat = 400) -> SKAction { .run { [weak self] in
            guard let self else { return }
            NSLog("ITEMTEST --- %@", title)
            self.pickups.clear()
            self.hero.restore(); self.hero.rig.position = CGPoint(x: 667, y: 120); self.hero.rig.facingRight = true
            e.restore(); e.rig.position = CGPoint(x: 667 + gap, y: 120); e.rig.facingRight = false
        } }
        let uppercut = MoveTable.chain(from: "heavy attack", .up)!
        let jab = MoveTable.move(.grounded, .tap)!
        let pick = MoveTable.move(.grounded, .down)!
        run(.sequence([
            w(1),
            reset("A heal when hurt"), act { h, _ in h.debugSetHealth(50) }, place(.item(Items.food), dx: 30), fire(.swipe(.down)), w(0.9),
            report("expect hp 75, apple gone"),
            reset("B food at full health stays"), place(.item(Items.food), dx: 30), fire(.swipe(.down)), w(0.9),
            report("expect hp 100, apple stays"),
            reset("C swap weapon"), place(.weapon(Weapons.axe), dx: 30), fire(.swipe(.down)), w(0.35),
            report("mid-swap"), w(1.0), report("expect weapon axe, sword on ground"),
            reset("D bare-handed pickup"), act { h, _ in h.equip(nil) }, place(.weapon(Weapons.sword), dx: 30), fire(.swipe(.down)), w(0.9),
            report("expect weapon sword"),
            reset("E strong hit disarms", gap: 70), act { _, e in e.debugPerform(uppercut) }, w(0.5),
            report("mid-flip"), w(1.4), report("expect hero weapon none, sword on ground"),
            reset("F jab keeps weapon", gap: 70), act { _, e in e.debugPerform(jab) }, w(1.0), report("expect weapon sword"),
            reset("G armed heavy attack", gap: 90), fire(.swipe(.right)), w(1.2), report("expect enemy hp 28 (12 dmg)"),
            reset("H bare-handed heavy attack", gap: 90), act { h, _ in h.equip(nil) }, fire(.swipe(.right)), w(1.2),
            report("expect enemy hp 31.6 (8.4 dmg)"),
            reset("I hero with axe", gap: 90), act { h, _ in h.equip(Weapons.axe) }, fire(.swipe(.right)), w(1.2),
            report("expect enemy hp 24.4 (15.6 dmg)"),
            reset("J enemies skip items"), place(.item(Items.food), dx: 400), act { _, e in e.debugPerform(pick) }, w(1.0),
            report("expect apple stays")
        ]))
    }

    /// Launch with `-divetest`: jump, hang, dive onto a standing skeleton at several offsets. Logs every hit with the move that caused it.
    private func runDiveTest() {
        guard let e = enemies.first else { return }
        func fire(_ g: Gesture) -> SKAction { .run { [weak self] in self?.hero.handle(g) } }
        func w(_ t: Double) -> SKAction { .wait(forDuration: t) }
        func reset(_ title: String, gap: CGFloat, dy: CGFloat = 0) -> SKAction { .run { [weak self] in
            guard let self else { return }
            NSLog("HITTEST --- %@", title)
            self.hero.restore(); self.hero.rig.position = CGPoint(x: 667, y: 120); self.hero.rig.facingRight = true
            e.restore(); e.rig.position = CGPoint(x: 667 + gap, y: 120 + dy); e.rig.facingRight = false
        } }
        var steps: [SKAction] = [w(1)]
        for (gap, dy) in [(0, 0), (40, 0), (80, 0), (120, 0), (160, 0), (60, 30), (60, 60), (-60, 0)] as [(CGFloat, CGFloat)] {
            steps += [reset("dive onto skeleton: gap \(Int(gap)) lane \(Int(dy))", gap: gap, dy: dy),
                      fire(.swipe(.up)), w(0.5), fire(.swipe(.down)), w(1.6)]
        }
        run(.sequence(steps))
    }

    /// Launch with `-hittest`: one passive skeleton in front of the hero; each case resets both and fires gestures.
    /// Results appear as `HIT ...` lines (damage, remaining hp, LAUNCH / KO).
    private func runHitTest() {
        guard let e = enemies.first else { return }
        func fire(_ g: Gesture) -> SKAction { .run { [weak self] in self?.hero.handle(g) } }
        func w(_ t: Double) -> SKAction { .wait(forDuration: t) }
        func reset(_ title: String, gap: CGFloat = 90) -> SKAction { .run { [weak self] in
            guard let self else { return }
            NSLog("HITTEST --- %@", title)
            self.hero.restore(); self.hero.rig.position = CGPoint(x: 667, y: 120); self.hero.rig.facingRight = true
            e.restore(); e.rig.position = CGPoint(x: 667 + gap, y: 120); e.rig.facingRight = false
        } }
        run(.sequence([
            w(1),
            reset("jab"), fire(.tap), w(1.5),
            reset("hook"), fire(.swipe(.right)), w(1.5),
            reset("jab jab"), fire(.tap), w(0.2), fire(.tap), w(1.5),
            reset("hook uppercut"), fire(.swipe(.right)), w(0.3), fire(.swipe(.up)), w(2.0),
            reset("juggle: hook uppercut slam"), fire(.swipe(.right)), w(0.3), fire(.swipe(.up)), w(0.5), fire(.swipe(.down)), w(2.2),
            reset("out of reach", gap: 400), fire(.tap), w(1.2),
            reset("power dash", gap: 330), .run { [weak self] in self?.input.keyDown("d", run: true) }, w(0.7),
            fire(.swipe(.right)), w(0.5), .run { [weak self] in self?.input.keyUp("d") }, w(1.5),
            reset("dash attack then smash", gap: 330), .run { [weak self] in self?.input.keyDown("d", run: true) }, w(0.7),
            fire(.tap), w(0.25), fire(.swipe(.down)), w(0.5), .run { [weak self] in self?.input.keyUp("d") }, w(1.5),
            reset("smash alone, standing, gap 70", gap: 70), .run { [weak self] in self?.hero.debugPerform(MoveTable.groundSmash) }, w(1.2),
            reset("smash alone, standing, gap 150", gap: 150), .run { [weak self] in self?.hero.debugPerform(MoveTable.groundSmash) }, w(1.2),
            reset("smash alone, standing, gap 230", gap: 230), .run { [weak self] in self?.hero.debugPerform(MoveTable.groundSmash) }, w(1.2),
            reset("smash alone, standing, gap 300", gap: 300), .run { [weak self] in self?.hero.debugPerform(MoveTable.groundSmash) }, w(1.2),
            reset("smash alone, standing, gap 380", gap: 380), .run { [weak self] in self?.hero.debugPerform(MoveTable.groundSmash) }, w(1.2),
            reset("smash alone, running, gap 330", gap: 330), .run { [weak self] in self?.input.keyDown("d", run: true) }, w(0.7), .run { [weak self] in self?.hero.debugPerform(MoveTable.groundSmash) }, w(0.6), .run { [weak self] in self?.input.keyUp("d") }, w(1.2),
        ]))
    }

    /// Launch with `-demo` to play a scripted input sequence (no touch needed). Exercises every move-table context.
    private func runDemo() {
        func fire(_ g: Gesture) -> SKAction { .run { [weak self] in self?.input.fire(g) } }
        func hold(run: Bool) -> SKAction { .run { [weak self] in self?.input.keyDown("d", run: run) } }
        let release = SKAction.run { [weak self] in self?.input.keyUp("d") }
        run(.sequence([
            .wait(forDuration: 1),
            fire(.tap), .wait(forDuration: 0.8),                       // grounded tap
            fire(.swipe(.right)), .wait(forDuration: 0.8),             // grounded forward
            fire(.swipe(.left)), .wait(forDuration: 0.5),              // grounded back (open: nothing)
            fire(.swipe(.down)), .wait(forDuration: 0.5),              // grounded down
            fire(.swipe(.up)), .wait(forDuration: 1.0),                // small jump
            hold(run: true), .wait(forDuration: 1.8),                  // build up to a full run
            fire(.tap), .wait(forDuration: 0.7),                       // running tap
            fire(.swipe(.right)), .wait(forDuration: 0.7),             // running forward
            fire(.swipe(.up)), .wait(forDuration: 0.25),               // big jump
            fire(.swipe(.down)), .wait(forDuration: 1.0),              // air slam
            hold(run: true), .wait(forDuration: 1.8),
            fire(.swipe(.left)), .wait(forDuration: 0.6),              // running back: skid
            release, .wait(forDuration: 1.2),                          // stand still before the combo tests
            fire(.tap), .wait(forDuration: 0.2),                       // COMBO: punch ...
            fire(.tap), .wait(forDuration: 0.2),                       // ... punch 2 ...
            fire(.swipe(.up)), .wait(forDuration: 0.3),                // ... uppercut ...
            fire(.swipe(.down)), .wait(forDuration: 1.2),              // ... air slam (airborne)
            fire(.tap), .wait(forDuration: 0.05),                      // EARLY: arrives before the cancel point ...
            fire(.tap), .wait(forDuration: 1.0),                       // ... buffered, fires as punch 2
            fire(.tap), .wait(forDuration: 0.9),                       // EXPIRED: window closes before the next tap ...
            fire(.tap), .wait(forDuration: 1.0),                       // ... so this is a fresh punch, not punch 2
            hold(run: true), .wait(forDuration: 1.8),
            fire(.swipe(.right)), .wait(forDuration: 0.2),             // COMBO: power dash ...
            fire(.swipe(.down)), .wait(forDuration: 1.2),              // ... ground smash
            fire(.swipe(.right)), .wait(forDuration: 0.2),             // running power dash ...
            fire(.swipe(.up)), .wait(forDuration: 1.2),                // ... uppercut (new)
            release, .wait(forDuration: 1.2),
            fire(.swipe(.right)), .wait(forDuration: 0.2),             // standing heavy attack ...
            fire(.swipe(.up)), .wait(forDuration: 1.2),                // ... uppercut (new)
            release, .wait(forDuration: 1.2),
            fire(.swipe(.up)), .wait(forDuration: 0.3),                // jump, into the hang
            fire(.swipe(.down)), .wait(forDuration: 0.3),              // air slam; lands during this wait
            fire(.swipe(.right)), .wait(forDuration: 1.2),             // forward in the cooldown -> power dash
            fire(.swipe(.up)), .wait(forDuration: 0.3),
            fire(.swipe(.down)), .wait(forDuration: 0.03),             // slam ...
            fire(.swipe(.right)), .wait(forDuration: 1.2),             // ... forward mashed mid-dive: buffered, chains on landing
            release, .wait(forDuration: 1)
        ]))
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { if let v = view { input.began(touches, in: v) } }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { if let v = view { input.moved(touches, in: v) } }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { if let v = view { input.ended(touches, in: v) } }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { input.cancelled(touches) }

    // MARK: Debug overlay

    /// Half the visible height in scene units. aspectFill crops the scene on wider screens, so size.height overshoots.
    private var visibleHalfHeight: CGFloat {
        guard let v = view, v.bounds.width > 0, v.bounds.height > 0 else { return size.height / 2 }
        let scale = max(v.bounds.width / size.width, v.bounds.height / size.height)
        return v.bounds.height / scale / 2
    }

    private var visibleHalfWidth: CGFloat {
        guard let v = view, v.bounds.width > 0, v.bounds.height > 0 else { return size.width / 2 }
        let scale = max(v.bounds.width / size.width, v.bounds.height / size.height)
        return v.bounds.width / scale / 2
    }

    private func updateDebug() {
        debugLayer.removeAllChildren()
        killLabel.position = CGPoint(x: visibleHalfWidth - 28, y: visibleHalfHeight - 100)
        buffLabel.position = CGPoint(x: visibleHalfWidth - 28, y: visibleHalfHeight - 140)
        comboHUD.position = CGPoint(x: -visibleHalfWidth + 40, y: visibleHalfHeight - 150)
        goLabel.position = CGPoint(x: visibleHalfWidth - 150, y: 40)
        debugLabel.position = CGPoint(x: 0, y: visibleHalfHeight - 56)
        // Top left: the hero's name, health and special. Bottom centre: the boss.
        let left = -visibleHalfWidth + 40
        heroName.position = CGPoint(x: left, y: visibleHalfHeight - 40)
        heroBar.position = CGPoint(x: left + 150, y: visibleHalfHeight - 88)
        meterBar.position = CGPoint(x: left + 150, y: visibleHalfHeight - 104)
        bossBar.position = CGPoint(x: 0, y: -visibleHalfHeight + 30)
        bossName.position = CGPoint(x: 0, y: -visibleHalfHeight + 74)
        for t in input.debugTouches {
            let o = cam.convert(convertPoint(fromView: t.origin), from: self)
            let c = cam.convert(convertPoint(fromView: t.current), from: self)
            let color: SKColor = t.isLeft ? .cyan : .orange
            let ring = SKShapeNode(circleOfRadius: 40)
            ring.strokeColor = color; ring.lineWidth = 3; ring.fillColor = .clear; ring.alpha = 0.6
            ring.position = o
            let dot = SKShapeNode(circleOfRadius: 16)
            dot.fillColor = color; dot.strokeColor = .clear; dot.alpha = 0.7
            dot.position = c
            debugLayer.addChild(ring); debugLayer.addChild(dot)
        }
        if debugLabel.parent != nil { debugLabel.text = "\(hero.debugState)  speed \(Int(hero.velocity))  h \(Int(hero.rig.height))  hp \(Int(hero.health))  wpn \(hero.weapon?.name ?? "none")\(hero.ammo.map { " x\($0)" } ?? "")  |  last: \(hero.lastGesture)" }
    }

    // MARK: Loop

    override func update(_ currentTime: TimeInterval) {
        if gamePaused { lastTime = 0; return }          // resuming then starts from a zero-length frame
        let realDT = lastTime == 0 ? 0 : min(currentTime - lastTime, 1.0 / 20)
        lastTime = currentTime
        realNow = currentTime
        var sample: (zoom: CGFloat, slow: CGFloat) = fxEnabled ? fx.sample(at: currentTime) : (0, 1)
        if fxEnabled, hero.isCharging {                      // the camera creeps in as the power builds
            let p = hero.chargeProgress
            chargeZoom = 0.12 * p * p
            sample.zoom = max(sample.zoom, chargeZoom)
        } else if fxEnabled, realNow < chargeZoomUntil {      // released: no dip while the slam winds up
            sample.zoom = max(sample.zoom, chargeZoom)
        }
        speed = sample.slow                 // SKScene.speed also slows every SKAction: animations, effects, scripted tests
        let dt = realDT * Double(sample.slow)
        gameTime += dt
        let now = gameTime
        if args.contains("-fxtest") {
            fxPeakZoom = max(fxPeakZoom, sample.zoom); fxMinScale = min(fxMinScale, sample.slow)
            if sample.zoom > 0.001 || sample.slow < 0.999 { fxActive += realDT; NSLog("FXSAMPLE zoom=%.3f ts=%.2f", sample.zoom, sample.slow) }
        }

        var bounds = WorldBounds(minX: level.minX + level.heroInset, maxX: level.maxX - level.heroInset,
                                 minY: laneMinY, maxY: groundHeight - 30)
        var foeBounds = bounds
        if let a = activeEncounter {                          // encounter: the hero is held to one screen, enemies may arrive from just outside it
            let half = size.width / 2
            foeBounds = WorldBounds(minX: a.center - half - 140, maxX: a.center + half + 140, minY: bounds.minY, maxY: bounds.maxY)
            bounds = WorldBounds(minX: a.center - half + 70, maxX: a.center + half - 70, minY: bounds.minY, maxY: bounds.maxY)
        }
        crowd.members = enemies
        hero.step(now: now, dt: dt, bounds: bounds, foes: enemies)
        for e in enemies { e.step(now: now, dt: dt, bounds: foeBounds, foes: [hero]) }
        separateEnemies(dt: CGFloat(dt), bounds: foeBounds)
        if let w = wyrm {
            let c = activeEncounter?.center ?? (level.minX + level.maxX) / 2
            w.step(now: now, dt: CGFloat(dt), hero: hero, center: c, half: size.width / 2)
            bossBar.set(w.healthFraction)
            if w.isFinished { w.removeFromParent(); wyrm = nil }
        }
        if let n = necro {
            bossBar.set(n.healthFraction)
            if let b = n.brain as? NecromancerBrain {
                let c = activeEncounter?.center ?? (level.minX + level.maxX) / 2, h = size.width / 2
                b.arena = (c - h + 150)...(c + h - 150)
            }
            if n.dead { necroDefeated() }
        }
        if let k = batKing {
            bossBar.set(k.healthFraction)
            if let b = k.brain as? BatKingBrain {
                let c = activeEncounter?.center ?? (level.minX + level.maxX) / 2, h = size.width / 2
                b.arena = (c - h + 180)...(c + h - 180)
            }
            if k.dead { batKingDefeated() }
        }
        if let d = doppel {
            bossBar.set(d.healthFraction)
            if d.dead { doppelDefeated() }
        }
        if let k = forgeKing {
            bossBar.set(k.healthFraction)
            if k.dead { forgeKingDefeated() }
        }
        if let w = wraith {
            bossBar.set(w.healthFraction)
            if let b = w.brain as? WraithBrain {
                let c = activeEncounter?.center ?? (level.minX + level.maxX) / 2, h = size.width / 2
                b.arena = (c - h + 150)...(c + h - 150)
            }
            if w.dead { wraithDefeated() }
        }
        for e in enemies {                                        // wizards may only teleport onto the locked screen
            guard let b = e.brain as? WizardBrain else { continue }
            if let c = activeEncounter?.center { let h = size.width / 2; b.arena = (c - h + 150)...(c + h - 150) }
            else { b.arena = (level.minX + 80)...(level.maxX - 80) }
        }
        if let d = demon {
            bossBar.set(d.healthFraction)
            if let b = d.brain as? DemonBrain {
                let c = activeEncounter?.center ?? (level.minX + level.maxX) / 2, h = size.width / 2
                b.arena = (c - h + 160)...(c + h - 160)
            }
            if d.dead { demonDefeated() }
        }
        if let m = archmage {
            bossBar.set(m.healthFraction)
            if m.dead { archmageDefeated() }
        }
        crates.block([hero] + enemies, dt: CGFloat(dt))
        pickups.step(dt: CGFloat(dt), minX: level.minX + 20, maxX: level.maxX - 20)
        arrows.step(dt: CGFloat(dt), minX: level.minX, maxX: level.maxX)
        updateCombat(now: now)
        hitOverlay.update([hero] + enemies, heroTeam: hero.team, dt: CGFloat(realDT))
        hazards.update(dt: TimeInterval(CGFloat(realDT)), fighters: [hero] + enemies, lanes: laneMinY...(groundHeight - 30))
        if let t0 = profileHit0, realNow - t0 < 0.7, let e = enemies.first {
            NSLog("PROFILE t=%.3f slow=%.2f skel_h=%.1f hero_h=%.1f", realNow - t0, sample.slow, e.rig.height, hero.rig.height)
        }
        updateBubbles(now: now)
        if !entering, !doors.doors.isEmpty { doors.update(near: activeEncounter == nil && wyrm == nil ? hero.rig.position : CGPoint(x: -99_999, y: 0)) }
        updateDebug()

        // Camera follows the hero in both axes (vertical is damped so the horizon shifts, not snaps).
        // Moments zoom it in; while zoomed it also drifts toward the hero's chest so he stays the focus.
        let follow = min(1, CGFloat(realDT) * 6)
        let camScale = 1 - sample.zoom
        cam.setScale(camScale)
        let focus = min(1, sample.zoom / 0.05)
        var camTargetY = baseCamY + (hero.rig.position.y - laneStartY) * verticalFollow
        let chest = hero.rig.position.y + (hero.rig.height + 60) * hero.rig.scaleFactor
        camTargetY += (chest - camTargetY) * focus * 0.5
        let halfW = size.width / 2 * camScale
        let camMinX = level.minX + halfW, camMaxX = max(camMinX, level.maxX - halfW)
        let camTargetX = min(max(activeEncounter?.center ?? hero.rig.position.x, camMinX), camMaxX)
        cam.position.x += (camTargetX - (cam.position.x - shakeOffset.x)) * follow
        cam.position.y += (camTargetY - (cam.position.y - shakeOffset.y)) * follow
        cam.position.x -= shakeOffset.x; cam.position.y -= shakeOffset.y
        camShake *= exp(-7 * CGFloat(realDT)); if camShake < 0.3 { camShake = 0 }
        shakeOffset = CGPoint(x: .random(in: -1...1) * camShake, y: .random(in: -1...1) * camShake)
        cam.position.x += shakeOffset.x; cam.position.y += shakeOffset.y

        // Parallax: horizontal layers tile and wrap; vertical offset is a simple scaled shift
        for l in layers {
            var m = (cam.position.x * l.fx).truncatingRemainder(dividingBy: l.tileW)
            if m < 0 { m += l.tileW }
            l.node.position.x = cam.position.x - size.width / 2 - m
            l.node.position.y = (cam.position.y - baseCamY) * (1 - l.fy)
        }
        updateDarkness()
    }
}

struct GameView: View {
    @State private var mode: GameMode
    @State private var levelIndex = 0
    @State private var fromHub = false
    let onBack: () -> Void
    @State private var scene: GameScene
    @State private var runID = 0
    @State private var result: GameResult?
    @State private var paused = ProcessInfo.processInfo.arguments.contains("-startpaused")

    init(mode: GameMode, onBack: @escaping () -> Void) {
        _mode = State(initialValue: mode)
        self.onBack = onBack
        _scene = State(initialValue: GameScene(mode: mode))
    }

    var body: some View {
        SpriteView(scene: scene, isPaused: paused, debugOptions: [.showsFPS, .showsNodeCount])
            .id(runID)
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                if result == nil, !paused {
                    Button { setPaused(true) } label: { Image(systemName: "pause.fill").font(.title3) }
                        .buttonStyle(.borderedProminent)
                        .padding()
                }
            }
            .overlay {
                if paused, result == nil {
                    PauseView(onResume: { setPaused(false) }, onRestart: retry, showRestart: mode != .hub,
                              homeTitle: mode == .hub ? "MENU" : fromHub ? "HUB" : "HOME", onHome: fromHub ? backToHub : onBack, showBrightness: scene.isDark)
                        .transition(.opacity)
                }
            }
            .overlay {
                if let r = result {
                    GameOverView(title: r.won ? "LEVEL CLEAR" : "GAME OVER", retryTitle: r.won ? "REPLAY" : "TRY AGAIN",
                                 homeTitle: fromHub ? "HUB" : "HOME",
                                 kills: r.kills, onRetry: retry, onHome: fromHub ? backToHub : onBack)
                        .transition(.opacity)
                }
            }
            .animation(.easeIn(duration: 0.3), value: result == nil)
            .onAppear { wire() }
    }

    private func wire() {
        scene.onGameOver = { result = $0 }
        scene.onEnterLevel = { enter($0) }
        scene.onExitLevel = { fromHub ? backToHub() : onBack() }
        scene.onTogglePause = { if result == nil { setPaused(!paused) } }
    }

    private func setPaused(_ p: Bool) {
        scene.gamePaused = p
        withAnimation(.easeOut(duration: 0.15)) { paused = p }
    }

    private func swap(to s: GameScene) {
        scene = s
        wire()
        result = nil
        paused = false
        s.gamePaused = false
        runID += 1
    }

    private func enter(_ level: Int) {
        levelIndex = level; mode = .campaign; fromHub = true
        swap(to: GameScene(mode: .campaign, levelIndex: level))
    }

    private func backToHub() {
        mode = .hub; fromHub = false
        swap(to: GameScene(mode: .hub, returnDoor: levelIndex))
    }

    private func retry() { swap(to: GameScene(mode: mode, levelIndex: levelIndex)) }
}
