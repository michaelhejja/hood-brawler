# Handoff

Project: `/Users/michael.hejja/Projects/Brawler`
Repo: github.com/michaelhejja/hood-brawler
Controls reference: `CONTROLS.md`

## Latest build
Version 0.2, build 5 (see `git log` for the commit). Previous builds: 4 `50d7f7a`, 3 `8ee7a87`.
Raise `CURRENT_PROJECT_VERSION` in `project.yml` before the next upload.

## Art
- Cloak, Ember, Bully, the skeleton, the goblin, the ice wizard and the Demon use hand-drawn parts through SpriteSkin.
- The slicer is `Art/slice_sheet.py`. Each character can have a `<prefix>_pivots.json`.
- Templates exist for the necromancer, forge king and bat. Nothing loads them yet.
- The Demon has two extra parts, `wing_back` and `wing_front`, defined in `Art/templates/demon_spec.json`. Slice with `python3 Art/slice_sheet.py <sheet> demon Art/templates/demon_spec.json`.

## Demon (mini-boss)
- `DemonBrain` in `Combat.swift`: ground melee and fire bolts, a blink, then an air phase that rains fire and slams to a stunned landing.
- Its fire needs no weapon: `Stats.innateMoves` (set from `Weapons.fireBreathMoves`) is checked after the held weapon.
- Level 8, The Ashlands, borrows the Foundry look (`theme: .forge`) until it gets its own art. Launch with `-level 7`, or `-demon` for a one-screen arena.

## Open items
1. The two alternate knockdown poses now set the sword angle to match the standard knockdown. Not yet checked by eye.
2. The uppercut connect test hasn't been re-run since the variants and finishers went in. It was 10 of 12 at the last run.
3. The black pill in some screenshots: ignore it, it has not been seen on device.

## Testing
- The simulator tools time out at about 30 seconds. Launch and screenshot in separate steps.
- Debug launch flags (`-combotest`, `-finishertest`, `-bombgoblin` and others) are defined in `GameScene.swift`.

## Survival mode
- Every survival enemy has 65% of its health (`survivalHealthScale` in `GameScene.swift`), on top of the per-minute tier boost.
- Frost wizards join at 3:00 (cap rises to 3). The Demon is a giant-style mini-boss from 5:00, roughly every 75-100 seconds, never alongside a giant, and drops a permanent buff.
- Test flags: `-earlywizards`, `-earlydemon`. All timings and the 0.65 scale are untuned guesses.
