# Handoff

Project: `/Users/michael.hejja/Projects/Brawler`
Repo: github.com/michaelhejja/hood-brawler
Controls reference: `CONTROLS.md`

## Latest build
Version 0.2, build 11 (see `git log` for the commit). Previous builds: 10 `2c49ff5`, 9 `5751a7f`, 8 `87d45e0`, 7 `c5ffd7b`, 6 `b401b9f`, 5 `ba34f42`, 4 `50d7f7a`, 3 `8ee7a87`.
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
- Fixed a bug where a killing blow's hit-stop left the copied pieces paused, so the skeleton froze upright until the game was paused and resumed. `shatter` now unpauses each piece.
- Still worth checking: skeletons facing left (mirroring of the loose parts) and giants (throw speed).

## Added in build 10
- **Quick rise:** knocked down, swipe up (after 0.3s) stands you up with 0.35s invulnerability; swipe back stands up and rolls. About 6% of enemy knockdowns pop up early (`QuickRise` in `Fighter.swift`; `-quickrise` forces it).
- **Death styles:** `DeathStyle.swift` holds all alternate-death odds in one table (kneel-and-topple 15% for every grounded enemy; skeleton break-apart 30%, giant skeleton 50%). `-kneel` and `-bonebreak` force them. Keep each enemy's total under 1.
- **Theme scenery:** smashable decor per theme via `Levels.withScenery(..., style:)`: bush (forest), withered (graveyard), frozen (snow), crystal (cave), charred (ashlands). `-scenery` loads a test arena.
- **Weapon art import:** draw on `Art/templates/weapon_guides.png` (2560x1640), then run `Art/import_weapons.sh weapons.png`. `WeaponArt` in `Sprites.swift` loads `weapon_<name>.png` and rebuilds the bow string, staff glows, shield glow, light blade glow and bomb spark as overlays. Weapons with no drawing keep their code art. Not yet tried with a real drawing.
- **Speech:** every level `Say` is spoken by the hero and follows them; the Bat King's cries follow him. No loose bubbles remain.
- Unchecked on screen: kneel timing, quick rise feel, the new scenery, the weapon loader.

## HUD (build 11)
- Top left: hero name (44pt), health bar, special bar. Bottom centre: boss name (40pt) and health bar.
- No Menu button in play. Pause (top right) has RESUME / RESTART / HOME, or HUB for levels entered from the hub. The hub now pauses too, with RESUME / MENU and no restart.
- The state read-out text and the touch-zone divider line only show with the `-debug` launch flag. The FPS/node counts and touch circles are still always on.
