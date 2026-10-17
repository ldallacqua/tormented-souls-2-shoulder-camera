# Context for AI-assisted maintenance

## Purpose and current state

An unofficial UE4SS Lua mod for Tormented Souls 2 (Windows, tested UE 5.5.4 executable
identified in README). It replaces fixed exploration cameras with an orbiting shoulder
view for a controller. Native combat, target selection, animation and puzzle logic remain.

Version 0.2.1 incorporates two-stage camera collision (head-to-shoulder, shoulder-back),
safe character hiding when close to head (<30 cm), and elimination of the ~180° snap
when entering zone cameras by disabling AutoNorthLocal on BP_RailCamera and synchronizing
movement references. A small flash remains when returning from inventory/item interaction
to the shoulder view. This is the next investigation target; do not describe it as already fixed.

## Runtime flow

`main.lua` registers F6/F7/Home and Blueprint input-context hooks. It calls `camera.update`
once per game frame with world delta time. Calls are guarded; an error restores camera
and input state and disables further updates for the current session.

`camera.lua` obtains the native character's `CameraBoom` and `FollowCamera`, snapshots
their properties, and uses them for shoulder framing. A native pre-hook on
`/Script/Engine.PlayerController:SetViewTargetWithBlend` redirects fixed CameraActor or
RailCamera targets to the character only when the mod owns the view. CineCameraActor
targets and blocked gameplay modes are excluded. Pause keeps the last shoulder view
frozen. Inventory, puzzle and interaction modes restore native view/component settings.

`input.lua` modifies existing mapping entries in `/Game/NewInputSystem/IMC_InGame`,
`IMC_InGame2` and `IMC_InGame3` in memory. It replaces the action of the four gamepad
`IA_Move_DPAD` bindings with `IA_InGame_Shortcut_Stick`, keeping negate/swizzle modifiers,
swapping Up/Down keys because shortcut UI Y is opposite movement Y, and setting the
old `Gamepad_Right2D` shortcut key to None. Keyboard mappings and other contexts remain
unchanged. It requests mapping rebuilds and restores snapshots when disabled/unloaded.
Restoration skips entries changed by another mod after this mod applied its mapping.

`collision.lua` computes camera clearance via a two-stage sweep: first from the head
pivot to the shoulder lateral point, then from that lateral point backward along the
camera orientation. It uses Visibility/Camera queries with simple and complex geometry,
ignores pawns and UI widgets (such as QTE components), and retries with a thin probe
if initially penetrating decorative meshes. Lateral and backward fractions ease outward
independently. Native spring-arm collision is disabled during shoulder view to prevent
it from collapsing the camera back to the head when against a back wall.

## Verified reflection details and pitfalls

- Character class: `/Script/TormentedSouls2.TormentedSouls2Character`.
- Observed pawn: `BP_CarolineNew_C`, inheriting `BP_TormentedSoulCharacter_C`.
- Controller Blueprint prefix:
  `/Game/NewInputSystem/TormentedSouls2PlayerController.TormentedSouls2PlayerController_C:`.
- Relevant mode hooks: `SwitchMapToInGame`, `SwitchMapToMain`, `SwitchMapToInventory`,
  `SwitchMapInventory`, `SwitchMapToPauseMenu`, `SwitchMapPauseMenu`, `SwitchMapToPuzzle`.
  The full list lives in `main.lua`.
- Rotator pitch property in this build is **`pitch`**, lowercase. `Yaw`/`Roll` are uppercase.
- Movement uses `NorthCamera`, `Last Camera Rotator`, `Current Camera Rotator` and
  `RAfterCameraChange`; changing only NorthCamera causes direction flips at some positions.
  `ChangeNorth=false`, `AutoNorth=false`, `TankMode=false` are part of the active setup.
- Spring-arm `ProbeChannel` is **ECollisionChannel**: Pawn=2, Visibility=3, Camera=4.
  Kismet sphere trace uses **ETraceTypeQuery**: Visibility=0. These are different enums.
- Observed UE4SS FHitResult `bStartPenetrating=true` despite ordinary hits with
  Time=0.13..0.31 and Distance=130..310 cm. Do not infer initial overlap from that bit.
  `Time=0` handles genuine initial overlap without collapsing every ordinary hit.
- Blueprint RegisterHook callbacks run after the Blueprint function. Native first
  callbacks run before the native function. `RemoteUnrealParam:set()` can replace native
  arguments. UFunction hook timing matters for one-frame camera flashes.
- `LoopInGameThreadAfterFrames(1, ...)` runs every game frame; no dt parameter is supplied.
  `GetWorldDeltaSeconds` is used and rotation dt is clamped to 0.05 seconds.

## Next investigation: inventory/item return flicker

Working hypothesis, not yet proved: the mode callback restores the native camera, then
resume leaves a frame before the next `camera.update` reclaims the pawn. The native
spring arm may also still have the old transform when SetViewTarget switches back.

Inspect the order of mode hooks, interaction flags, SetViewTargetWithBlend and camera
component updates. Consider synchronizing the return transition before rendering or
preparing the shoulder components while the native inventory view remains active.
Do not force the shoulder camera during inventory, puzzle close-ups or cutscenes.
Avoid delaying all transitions or overriding every CameraActor without mode checks.
Validate repeated inventory open/close, item inspect/close, pause, fixed-camera triggers,
and F6 restoration. Preserve the validated movement and collision algorithms.

## Local debugging without leaking user data

UE4SS reflection dumps can identify loaded properties and Blueprint functions, but they
must stay outside this repository. Local development can use a separate ModsFolderPath
and controlled hot swapping; production scripts must not poll source files or depend on
an absolute workspace path. Do not include those diagnostics in release packages.

## Build and packaging

`tools/build.py` pins the exact official runtime ZIP SHA-256, selects allowed archive
members, copies source scripts, and generates file hashes plus the tested executable
hash. The package includes a conservative PowerShell installer and original runtime
license. The installer refuses unrelated UE4SS installations and mismatching binaries;
on owned upgrades it preserves config.lua, runtime settings and mods.txt.

No proprietary game code, executable, assets or saves are needed in Git. Source and
documentation are MIT; UE4SS retains its own MIT license in the release.
