# Context for AI-assisted maintenance

## Purpose and current state

An unofficial UE4SS Lua mod for Tormented Souls 2 (Windows, tested UE 5.5.4 executable
identified in README). It replaces fixed exploration cameras with an orbiting shoulder
view for a controller. Native target selection, damage, animations and puzzle logic remain;
aiming is reworked (free aim to the crosshair, RE4-style walking while aiming).

Version 0.4.2 audits all ammo (sphere traces, in-flight traces left alone, loose aim-walk IDs).
Version 0.4.1 moves hitscan shots onto the camera ray and ignores puzzle flags stuck in gameplay.
Version 0.4.0 bends the torso to the crosshair (`RotationToAim`), limits steep shots and adds
impact marks (impact.lua). Version 0.3.1 rebuilds the aim walk (reversed weapon aim-walk montage for the backpedal,
side-step montages, CharacterMovement velocity instead of per-frame teleports). Version 0.3.0 adds: hold/freeze of the shoulder view for inventory and short interactions
(no fixed-camera flash), free aim + UMG crosshair, RE4-style aim walk (aimwalk.lua), L3
shoulder swap, quick turn, breathing sway/turn lean (no footstep bob: it caused motion
sickness). 0.2.1 brought two-stage collision, character hiding near the head and the zone
camera snap fix. See CHANGELOG for what is validated in game and what is not.

## Runtime flow

`main.lua` registers F6/F7/Home and Blueprint input-context hooks. It calls `camera.update`
once per game frame with world delta time. Calls are guarded; an error restores camera
and input state and disables further updates for the current session.

`camera.lua` obtains the native character's `CameraBoom` and `FollowCamera`, snapshots
their properties, and uses them for shoulder framing. A native pre-hook on
`/Script/Engine.PlayerController:SetViewTargetWithBlend` redirects fixed CameraActor or
RailCamera targets to the character only when the mod owns the view. CineCameraActor
targets and blocked gameplay modes are excluded. `holdReasons` (pause, inventory, puzzle,
preview, POI, text and the puzzle/POI flags) keep the last shoulder view frozen. During a
hold, pause/inventory redirect any fixed camera; other holds redirect only the room camera
that was replaced (`originalView`). Any other requested camera is the game's close-up: it is
shown (`handedOff`) and the rig stays configured for the return. A close-up redirected less
than 0.5 s before the hold, or a `GameInstance.CurrentCamera` that is not the room camera,
is restored the same way. `isInteractingWithPuzzleComp`/`isInteractingWithChildPuzzleComp` set for more than 1.5 s in
gameplay mode are ignored (stuck after entering TortureChamber_Bad); the timer resets on any
non-gameplay mode. Other blocked states (cinematic, dialogue, menus, death, climbing,
`isInputDisabled`, `bIsCharacterInteracting`) still restore native view/component settings;
the return configures the rig one frame before switching the view target.

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

## Inventory/item return flicker (inventory and puzzle close-up validated)

Logs showed the game never changes view target when the inventory opens, and short item/
puzzle interactions run `puzzle -> inventory -> puzzle -> gameplay`, followed by about 0.5 s
of `isInteractingWithPuzzleComp`. The old full restore exposed the room camera for that
whole span. The hold model above replaces it. Still unverified in game: puzzles with real
close-ups, item inspection and document reading. Use the `State`, `Native camera during`
and `Close-up camera restored` log lines when testing. If a puzzle shows the frozen shoulder
view instead of its close-up, log which camera the game used before widening the redirect rule.

## Free aim (experimental, in validation)

`aim.lua` arms itself only while `isAiming` in the shoulder view. Each frame it traces from
the screen centre (starting level with Caroline) and caches the point under the crosshair.
Player ammo (`/Game/GameplaySystems/WeaponSystem/Ammo/BP_BaseAmmo`) gets its muzzle socket,
turns with `FindLookAtRotation` + `K2_SetActorRotation`, then fires `LineTraceMulti` and
applies damage (dump of the ubergraph locals; not decompiled). Native pre-hooks rotate both
towards the crosshair point with a Rodrigues rotation, so deviations from the base direction
(pellet spread) survive. Deviations above 20 deg are treated as an unrelated base. The trace
channel of the last shot is reused for the crosshair trace (aim capsules). Unknowns: which
weapons trace vs. fly, whether shotgun pellets are separate actors, and how the game's
target lock (`RotateToTarget`) interacts with the body alignment. Read the `Free aim` logs.

Ammo audit (dump + pak index, 2026-10-17): every ammo class is a BP_BaseAmmo child. Some also
call SphereTraceMulti (hooked, same retarget) and LineTraceSingle (not hooked: used by flying
ammo). Retargets apply only to traces starting within 250 cm of Caroline (fire time); in-flight and
impact traces are left alone. Only five aim-walk sequences exist (nail, automatic nail, hand cannon,
hammer, crowbar); other weapons back-pedal with `back_pedal`.
Hitscan shots (LineTraceMulti from BP_BaseAmmo children: Nail, ShotgunShell with 9 pellets, ...)
are moved onto the camera ray: start = camera location + forward * (Caroline's depth), direction =
camera forward (spread kept). Aiming from the muzzle missed at close range and on surfaces that
ignore the crosshair trace channel. Flying ammo (rotation hook) still aims from its own location.

`aim.lua` also writes `RotationToAim.pitch` from the hands (actor + 40 cm) to the crosshair point,
eased, and resets it to 0 when aiming ends; it limits shots to -50 deg pitch. Camera pitch while
aiming stops at `aimMinPitch` (-35). `impact.lua` gets each adjusted shot from the hooks, traces it on
the next frame (never inside the native hook) and places the decal; no marks on pawns.

`HUD:ReceiveDrawHUD` never fires here (no Blueprint HUD draw event), so `crosshair.lua`
creates a `WBP_FPSShow` instance as a host, replaces its `WidgetTree.RootWidget` with a
CanvasPanel of five Images and adds it to the viewport (hit-test invisible). UE4SS removes
native hooks only after their next call and still runs the pending pre-callback, so shot
hooks are registered once on the first aim and gated by `armed`; never unregister them per
aim. `Aim probe` logs list up to 12 classes calling the hooked functions while aiming.

## Procedural motion

`motion.lua` is pure: yaw rate and aim state in; FollowCamera relative rotation out
(breathing sway < 0.3 deg, turn lean <= 1.6 deg). A footstep bob was tried and removed: it
caused motion sickness. Do not reintroduce walking oscillation without an explicit request.
The spring-arm positional lag (`followLag`, max 6 cm) is off by default for the same reason.

## Aiming and movement (probed in game, 2026-10-17)

Measured with a dev probe (planted-foot slide in Caroline's local frame, velocity relative
to facing, ABP variables), not by decompiling:
- Native aim movement: the C++ character turns towards the camera-relative stick and walks
  along its facing at ~96 cm/s. `Moving F` is set for every direction; `Moving B/L/R`,
  `Direction` and tank mode never produce a backpedal or strafe while aiming.
- Writing `StickX/StickY` properties plays the aim-walk cycle (feet ~77 cm/s) without moving
  her; movement only happens through `SetStick*Value`.
- While aiming, `AddMovementInput` (from Lua or from a ReceiveTick hook) is ignored; a swept
  `K2_SetActorLocation` moves her. `GlobalAnimRateScale=-1` turns the cycle into a correct
  backpedal (feet slide forward).
- A hidden mesh (`OwnerNoSee`, tick option 4) stops refreshing bones; probes force option 0.
- Negative `GlobalAnimRateScale` looked right in foot measurements but froze/stretched the
  spine in play (negative delta time into other anim nodes). Do not use it.
- Forcing ABP variables (`Moving B/L/R`, `Direction`, `Target Assigned`, `Auto Moving
  Backwards`, analog/tank flags) after `BlueprintUpdateAnimation` never changes the aim locomotion.
- `PlaySlotAnimationAsDynamicMontage` works while aiming on `DefaultSlot`/`UpperBody` (both
  drive the legs; `EquipAnimSlot`, `AttackInIdle`, `GrabSlot`, `FallSlot` do nothing then).
  Planted foot: `back_pedal` +88 cm/s, `side_step_Left/Right` +-104 cm/s. `back_pedal` lowers the
  weapon and turns her head (user feedback). The weapon's aim-walk sequence matches the native
  cycle (Nailgun: `Nailer_Walk_Aim`, identical average hand positions; `Automatic_Nailer_Aim_Walk`
  differs). Played at rate -1 from the end it backpedals at +92 cm/s with the weapon raised; a
  reversed montage does not loop, so `Montage_SetPosition` wraps it near 0.
- `currentWeaponID` (FString) names the weapon (`Nailgun`); the ABP has `Weapon ID` too.
- Teleporting with swept `K2_SetActorLocation` each frame made the actor height oscillate
  ~1 cm per frame (camera judder). Writing `CharacterMovement.Velocity` with `GroundFriction=0`
  and `BrakingDecelerationWalking=0` moves her while aiming with a stable height and smooth steps.
- Torso pitch: `BP_TormentedSoulCharacter.RotationToAim` (rotator, lowercase `pitch`) feeds four
  ModifyBone nodes on `spine_02_x` in `ABP_CarolineCharacter` (BreakRotator -> Multiply -> FClamp ->
  MakeRotator roll). Measured 1:1 bend, clamped by the ABP to -30..+40 deg. The game does not write it
  while aiming without a target. A LookAt node on `neck_x` (clamp 35) uses `TargetLocation`/`LookAtAlpha`.
- Decals: the particle decal materials (`MI_BurnDecal` parent `M_Alpha_Sprite_Lit`, `MI_GroundCrackDecal`,
  `MI_BloodStainDecal`) render as plain squares from `SpawnDecalAtLocation`. `M_MS_Decal_Material`
  (Megascans, params Albedo/Normal/DRO) with a dynamic instance (Albedo `/Engine/EngineResources/Black`,
  Normal `FlatNormal`, DRO `/Game/Particles/Textures/Impact23`) gives a dark impact star.
`aimwalk.lua` builds the RE4 walk from these: pre-hooks zero the game's stick input,
post-hooks rewrite `StickY` for the forward cycle, `plan` picks forward/back/left/right and the
rate, the animator plays side steps or the reversed aim walk (`back_pedal` for unmapped weapons)
as montages, and `drive`/`release` own the CharacterMovement settings. No walking during a shot
or reload (their montages share the slot group).

## Exploration input mappings (probed in game)

Preset 1/3: A interact, X run/dodge, Y inventory, B reload, LB aim (+change target in
preset 1; RB in preset 3), RT shoot, R3 centre shortcut, L3 `IA_InGame_OpenDebugMenu`, View
map, Menu pause. Preset 2 differs: B inventory, Y reload, RT aim+shoot, LT change target.
L3 is reused for the shoulder swap; quick turn polls X (`Gamepad_FaceButton_Left`).

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
