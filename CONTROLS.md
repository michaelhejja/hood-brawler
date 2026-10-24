# Control scheme

No virtual controls: the device is the controller. The screen splits 50/50 by where a touch STARTS.

## Left half: movement (momentum)
- Floating origin at touch start; drag distance sets target speed (walk -> full run).
- Drag distance AND drag speed set how fast he accelerates. Fast flick = quick run-up.
- Thumb lifted: quick stop; small skid if at full run.

## Right half: actions (contextual)
Gestures: tap, swipe up / down / forward / back (forward/back are relative to facing).
Swipes fire the moment they pass the distance threshold, taps on release.

| Context        | Tap          | Up                  | Down             | Forward              | Back        |
|----------------|--------------|---------------------|------------------|----------------------|-------------|
| Standing/walk  | jab (off hand)  | small jump          | pick up item     | hook (weapon hand)    | (open)      |
| Running        | dash attack  | big forward jump    | -                | strong dash attack   | skid stop   |
| Airborne       | -            | -                   | air-to-ground    | -                    | -           |

Back-swipe while standing is intentionally unassigned: reserved for future special weapons/abilities.

## Quick rise
Knocked down: swipe up (after a 0.3s beat on the floor) gets you up at once, with 0.35s of invulnerability. Swipe back gets up and goes straight into the dodge roll. About 6% of enemy knockdowns get up early on their own. Tuning is in `QuickRise` (Fighter.swift).

## Combos (timing based, generous windows to start)
- tap, tap, swipe up -> punch, punch, uppercut -> swipe down (airborne)
- run, swipe forward, swipe down -> dash attack, then overhead ground smash (knockback)

## Combo rules (input-driven: no hit required)
- Early cancel: a chained move may cut in 0.12s after the previous move starts.
- Chain window: stays open 0.4s after the previous move's lock ends.
- Input buffer: a gesture that arrives too early (or during an unchainable move) is held 0.25s, then fires.
- Chains: punch -tap-> punch 2; ground smash after power dash / dash attack (swipe down).
- Uppercut (swipe up) follows punch 2 and any strong attack (heavy attack, power dash), standing or running.
- Air slam (swipe down in the air): dive pitched hard forward, both hands out, weapon leading. Landing has a 0.3s cooldown with the chain open from the first frame: forward -> power dash, up -> uppercut. Input mashed mid-dive is buffered and fires on landing.
- Uppercut: weapon hand cocks low, then swings up in a big arc with a rising slash trail. Front knee drives up, back leg stays pointed down, head cocks back to follow the blade. Pose holds through the jump's hang.
- Ground smash (swipe down after power dash / dash attack): two-handed overhead swing, feet leave the ground, shockwave ahead. Same effect as the air slam at `power` 0.7 vs 1.0 (damage/knockback, once hit detection exists).
- Ground smash advances ~150pt on its own (root motion, eased) and hits 0-175pt ahead. Attacking fighters stop at arm's length from an opponent instead of running through them.
- Jumps use a strong ease-in-out height curve (`JumpTuning`): tension at the bottom and apex, fast in between.
- Tuning lives in `ComboTuning` (Moves.swift). Chains are rows in `MoveTable.chains`.

## Simulator keyboard backend
WASD move (Shift = run), arrow keys = swipes, Space = tap. Tuning lives in `InputTuning` (GameInput.swift)
and the locomotion constants at the top of `GameScene.swift`.

## Status
Done: input layer, momentum locomotion, debug overlay, keyboard backend.
Done: height axis, move table (`Moves.swift`, one row per move).
Placeholder animations: pick up (none), skid stop (reuses landing pose), weapon attack (no weapon system yet).
Done: combo chains, early cancel, input buffer.
Next: hit detection, then dedicated animations for each move.

## Character architecture (composition)
- `HumanoidRig` (HumanoidRig.swift): owns the joints and every animation. One implementation for everyone.
- `Skin` (Skin.swift): art for head / torso / legs / arms / weapon plus a `RigLayout` (joint positions). `HeroSkin`, `SkeletonSkin`.
  A new look = a new skin; it plays every animation automatically. Parts can be mixed across skins.
- `Fighter` (Fighter.swift): all state and rules for one character (locomotion, height axis, move execution, combo chain,
  input buffer, health). Brain-agnostic: `update(intent:)` each frame + `handle(gesture)`. `FighterStats` holds per-character numbers.
- `Brain` (Brain.swift): decides what a Fighter does each frame. `PlayerBrain` wraps touch/keyboard input; `EnemyBrain` is a
  state machine (approach, pause, attack, recover, back off) with `EnemyTraits` (reaction time, cooldown, reach, combo/charge/retreat odds).
  Brains only send gestures through `Fighter.handle`, so enemies use the same move table and combos as the player.
- Hit detection (Combat.swift): each `Move` lists `Hit` windows (start, duration, reach, lane depth, height tolerance, damage,
  knockback, launch, stun). Same code for any Fighter; fighters only hit other `team`s. Damage = hit.damage x move.power x attacker.damageScale.
  Reactions: flinch, blasted flat (heavy knockback), launched into the air (juggle: any hit keeps them up; a spike drives them down), KO.
  Hit-stop freezes both fighters briefly, longer for heavier hits.
- Crowd control (`CrowdDirector`, Brain.swift): at most 2 enemies hold an attack token and close in (started 0.6s apart,
  nearest first); the rest wait in a ring ~230pt out, spread across lanes by slot, and take over as tokens free up.
  A soft separation push (GameScene) keeps grounded enemies from standing on each other; it never disturbs an attack.
- Weapons and items (Items.swift): `Weapon` and `Item` are data (name, art, power / effect). Swipe down while standing or walking
  picks up whatever is within 80pt x 40pt lane at the feet (grab lands 0.2s into the move). A weapon replaces the one in hand and
  the old one is tossed behind you; food heals 25 and stays on the ground at full health. Only the player collects items.
- Strong hits (launch, spike, or knockback >= 500) knock the victim's weapon out: it flips away and lands as a pickup.
  Weapon moves (`.armed`) scale with the weapon's power; unarmed weapon moves do 0.7x.
- Weapon move overrides: a `Weapon` can carry `moves: [MoveKey: Move]` that replace single entries of the default table while held
  (everything else falls through). Bow: grounded back swipe = shoot (draw 0.18s, arrow flies straight ahead along the lane at 800pt/s,
  7 dmg, jump over it). Ammo is per weapon (8 start, 12 max, travels with a dropped bow); a quiver pickup adds 6 and is ignored
  without a bow or at full ammo. A hit during the draw cancels the shot and spends no arrow. Bow melee power is 0.6x.
- Archers (enemies holding a ranged weapon with ammo) skip the melee queue: they hold 270-470pt out, backpedal while still facing you
  (hurrying when you're close), slide into your lane, pause, then shoot with the same back-swipe gesture. Pressed at point-blank for
  ~1s with planted feet they jab weakly. Out of arrows, they fall back to the normal melee brain.
- Camera moments (CameraFX.swift): the bigger the moment, the bigger the effect. A `Move` carries an `Emphasis` tier (zoom in,
  slow-mo, hold, release); only the hero's moves and hits drive it. Tiers: none (jab) | light (hook, 2% zoom) | medium (power dash,
  dive; 4.5%, 0.8x speed) | heavy (uppercut, ground smash; 8%, 0.55x) | massive (landing shockwave, last enemy falling; 13%+, 0.35x).
  A windup zoom starts with the move (even if it whiffs). On a hit it scales up by 25% per extra enemy hit and 20% for a KO;
  any KO gets at least `kill`, the last enemy `massive`. While zoomed the camera drifts toward the hero's chest and stays inside the
  level. Slow-mo scales all game time (movement, animations, timers) but not the camera's own easing. `-nofx` disables it.
- Uppercut reliability: openers stagger the target instead of flooring it (hook knockback 300, power dash 420; below the 500 that
  lays an enemy flat), the uppercut steps 45pt forward as it starts and reaches -10..150pt, and a launcher never causes hit-stop so
  the victim flies on the first frame. `Hit.disarm` decides who drops their weapon, independent of knockback.
  A run can't carry the hero past an enemy he just hit while the combo chain is open, and the uppercut plants his feet (it supplies
  its own 45pt step), so a late uppercut after a dash still lands.
  Measured with `-uppertest -opener hook|punch|dash` (12 timings each): connects 12/12 after a hook, 12/12 after punch-punch, 12/12 after a power dash.
- Next: tune damage/knockback, hit reaction animations, more weapons (whip, spear, hammer, shield).
- Debug launch args: `-game`, `-lab`, `-demo` (scripted inputs), `-pose <animation>` (slow-mo, hero + skeletons), `-dump` (node tree), `-enemylog` (log enemy moves), `-passive` (enemies get no brain), `-hittest` / `-divetest` (scripted hit cases, log `HIT` lines), `-crowdtest` (hero can't die; logs `CROWD` spacing metrics), `-itemtest` (scripted pickup / swap / disarm cases), `-bowtest` (shooting, ammo, dodging, archers), `-fxtest` (camera zoom / slow-mo per move), `-nofx`, `-fxhold`, `-uppertest` / `-juggletest` / `-launchtest` (uppercut + slam probes) (stretch the peak for screenshots).
