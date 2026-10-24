# Handoff

Project: `/Users/michael.hejja/Projects/Brawler`
Repo: github.com/michaelhejja/hood-brawler
Controls reference: `CONTROLS.md`

## Latest build
Version 0.2, build 8 (see `git log` for the commit). Previous builds: 7 `c5ffd7b`, 6 `b401b9f`, 5 `ba34f42`, 4 `50d7f7a`, 3 `8ee7a87`.
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
- Every survival enemy has 50% of its health (`survivalHealthScale` in `GameScene.swift`), on top of the per-minute tier boost.
- Frost wizards join at 3:00 (cap rises to 3). The Demon is a giant-style mini-boss from 5:00, roughly every 75-100 seconds, never alongside a giant, and drops a permanent buff.
- Test flags: `-earlywizards`, `-earlydemon`. All timings and the 0.5 scale are untuned guesses.

## Campaign difficulty
- Menu button cycles Easy / Medium / Hard (`Difficulty` in `MenuView.swift`, saved in UserDefaults; `-difficulty 0|1|2` overrides). Medium is the game as designed; survival always plays as Medium.
- Scales enemy damage, enemy health, food healing, and the reaction/cooldown times of standard melee brains. Applied in `GameScene.applyDifficulty`. Multipliers are untuned guesses.
- The Character Lab button was replaced by the difficulty button. The lab is still reachable with `-lab`.

## Boss anti-spam
- `AntiSpam` in `Combat.swift`: a boss that takes enough light melee hits in a short window (6 in 3s; 8 on Easy, 5 on Hard) goes immune, winds up and smashes. 9s cooldown.
- Wired into `DemonBrain` and `ForgeKingBrain` only. Not the giant (has its ambush), necromancer, doppelganger, Bat King or Archmage.
- Survival health scale is now 0.5 (was 0.65).

## Finishers
- Armed at 10 combo hits, spent on the next uppercut, ground smash, forward swipe (standing heavy attack or running power dash) or air slam. Back swipe is deliberately not a finisher (it fires weapons and rolls).
- Names, color and tuning are per hero in `Skin.swift` (`HeroKind.finisherNames`, `.color`, `.finisherStyle`). Cloak: Skybreaker / Earthshatter / Knockout / Meteor (yellow). Ember: Air Flurry / Dance Shoes / Mega Slap / Reckoning (hot pink, lighter hits). Bully: Launched / Pulverized / Outta My Way / Anvil Drop (light blue, wider and heavier).
- `FinisherStyle` multipliers (damage, reach, knockback, launch, stun) are first guesses. Cloak is the 1x baseline.
- Hub and level portal titles are larger (32pt) for phone readability.

## Skeleton break-apart
- A dying skeleton (30%) or giant skeleton (50%) can break into its parts, which fly off, bounce and fade. `HumanoidRig.shatter` does it, and `boneBreakChance` in `GameScene.swift` sets the odds. `-bonebreak` forces it.
- Not yet seen running. Check skeletons facing left (mirroring of the loose parts) and giants (throw speed).
