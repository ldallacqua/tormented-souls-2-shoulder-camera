-- Edit with the game closed. Distances in centimetres, angles in degrees.
return {
    enabled=true,
    distance=220,
    height=57,
    shoulder=43,
    fov=75,
    aimDistance=170,
    aimFov=67,
    yawSpeed=135,
    pitchSpeed=95,
    deadzone=0.20,
    stickCurve=1.5, -- >1 gives finer control near the centre of the right stick.
    aimSensitivity=0.6, -- Right-stick speed multiplier while aiming.
    aimMove=true, -- RE4-style: walk in any direction while aiming, facing the crosshair.
    aimWalkSpeed=96, -- cm/s, the game's own aim-walk speed.
    aimBackSpeed=0.9, -- Backpedal speed/animation rate multiplier.
    aimSideSpeed=0.85, -- Side-step speed/animation rate multiplier.
    aimWalkSlot='DefaultSlot', -- Montage slot for the backpedal/side-step animations.
    aimLeftStick=0.7, -- With aimMove=false Caroline stands still and the left stick aims.
    aimWalk=false, -- true hands movement back to the game (it turns her towards the stick).
    invertY=true, -- Stick up looks up with the tested controller.
    transitionSpeed=10, -- How fast distance/shoulder/height blend (aim, shoulder swap).
    collisionRadius=16,
    hideCharacterBelow=30, -- Hide Caroline when the camera is closer than this to her head.
    freeAim=true, -- Shots follow the crosshair while aiming in the shoulder view.
    crosshair=true,
    shoulderSwapButton='Gamepad_LeftThumbstick', -- L3; set to false to disable.
    quickTurn=true, -- Left stick back + run/dodge button turns the camera 180 degrees.
    sway=true, -- Breathing sway and a slight lean into camera turns.
    swayAmount=1.0,
    followLag=false, -- Soft positional follow (max 6 cm); off to avoid motion sickness.
}
