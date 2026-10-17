# Working on this mod

Read `docs/AI_CONTEXT.md`, `README.md` and `CHANGELOG.md` before changing runtime behavior.
Use `src/TormentedShoulderCamera/Scripts` as the source of truth. Generated `dist/`
files must not be edited or committed. Regenerate them with `python tools/build.py`.

## Preserve validated behavior

- Movement must remain relative to the visible camera through fixed-camera triggers.
- Keep all four direction-reference rotators synchronized. Do not reintroduce tank movement.
- Keep right-stick shortcuts disabled only in exploration presets; preserve inventory/puzzle controls.
- While aiming the game's stick input is held at zero and aimwalk.lua moves Caroline through
  CharacterMovement (friction/braking off, written velocity). `aimwalk.release` must run whenever
  aiming ends or the camera is restored. Never use negative `GlobalAnimRateScale` (it broke her
  spine); reverse a sequence with a negative montage play rate instead.
- A nil object or FName passed to an engine call crashes UE4SS natively (pcall cannot catch it).
  Check every argument before calling. `UAnimInstance:GetCurrentStateName(i)` with an index that
  is not a state machine also crashes the game: do not probe anim nodes by index.
- Up/down shortcut axes differ from movement axes. Preserve the tested inversion.
- Camera sweeps must use hit fraction/distance, not the unreliable packed penetration boolean.
- Free-aim native hooks (K2_SetActorRotation, LineTraceMulti) fire for every actor: register them
  once on the first aim, return early unless armed, filter on BP_BaseAmmo, self-disable on error.
  Do not unregister per aim: UE4SS defers native removal and still runs the pending callback.
- The crosshair is a UMG viewport widget; HUD:ReceiveDrawHUD does not fire in this game.
- Hitscan shots start on the camera ray through the crosshair, not at the muzzle. Do not go back
  to muzzle-to-point aiming: it missed close enemies and surfaces outside the crosshair channel.
- Torso aim writes `RotationToAim.pitch` every aiming frame and must reset it to 0 when aiming ends
  (`aim.clear`). The ABP clamps it to -30..+40; do not bend the spine through other bones.
- Impact marks are traced outside native hooks. The game's particle decal materials do not work as
  plain decals; keep the Megascans decal + dynamic textures, and hide a decal whose instance failed.
- Pause, inventory and short puzzle/item interactions freeze the shoulder view. Close-up cameras
  the game requests during interactions, cinematics and dialogue must keep their native framing.
- F6 and error recovery must restore changes. Keep mod state independent of saves.

## Verification and release

Run `lua tests/run.lua` from repository root with Lua 5.4. Python's `lupa.lua54`
can run the same file if no standalone interpreter is available. Parse PowerShell
scripts and validate installer integrity checks before shipping installer changes.
Use actual in-game tests for camera transitions, collision and controller behavior;
mock tests cannot establish rendering correctness. State what was tested and what
remains unverified. Do not claim full campaign compatibility.

Never commit game binaries/assets, user saves, reflected object dumps, logs with local
paths, tokens or machine-specific development settings. Runtime ZIPs/DLLs belong in
release assets, with the original UE4SS license; download only from the official repo
and check the pinned checksum. Preserve other mods and user configuration on install.

Keep changes scoped to the requested issue. A game restart or a controlled hot reload
may be needed. Do not terminate a game with unsaved progress. Ask the player for visual
validation when no suitable automated renderer is available.
