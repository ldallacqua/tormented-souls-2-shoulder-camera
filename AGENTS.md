# Working on this mod

Read `docs/AI_CONTEXT.md`, `README.md` and `CHANGELOG.md` before changing runtime behavior.
Use `src/TormentedShoulderCamera/Scripts` as the source of truth. Generated `dist/`
files must not be edited or committed. Regenerate them with `python tools/build.py`.

## Preserve validated behavior

- Movement must remain relative to the visible camera through fixed-camera triggers.
- Keep all four direction-reference rotators synchronized. Do not reintroduce tank movement.
- Keep right-stick shortcuts disabled only in exploration presets; preserve inventory/puzzle controls.
- Up/down shortcut axes differ from movement axes. Preserve the tested inversion.
- Camera sweeps must use hit fraction/distance, not the unreliable packed penetration boolean.
- Pause freezes the shoulder view. Inventory and interaction cameras must keep their native framing.
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
