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

## Simulator keyboard backend
WASD move (Shift = run), arrow keys = swipes, Space = tap. Tuning lives in `InputTuning` (GameInput.swift)
and the locomotion constants at the top of `GameScene.swift`.

## Status
Done: input layer, momentum locomotion, debug overlay, keyboard backend.
Done: height axis, move table (`Moves.swift`, one row per move).
Placeholder animations: pick up (none), skid stop (reuses landing pose), weapon attack (no weapon system yet).
Next: combo buffer + chain windows, hit detection.
