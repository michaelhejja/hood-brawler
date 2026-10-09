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
| Standing/walk  | small punch  | small jump          | pick up item     | big/weapon attack    | (open)      |
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
- Chains: punch -tap-> punch 2 -up-> uppercut; power dash / dash attack -down-> ground smash.
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
