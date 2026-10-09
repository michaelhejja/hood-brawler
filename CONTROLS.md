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
- Next: `Fighter` (state, locomotion, height axis, move execution, combo chain, health) pulled out of `GameScene`,
  and `Brain` (player input or AI) that feeds it gestures.
- Debug launch args: `-game`, `-lab`, `-demo` (scripted inputs), `-pose <animation>` (slow-mo, hero + skeletons), `-dump` (node tree).
