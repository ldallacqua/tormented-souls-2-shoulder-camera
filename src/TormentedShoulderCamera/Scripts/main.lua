local directory = debug.getinfo(1, 'S').source:sub(2):match('^(.*[/\\])')
local core = dofile(directory .. 'camera.lua')
local initializedHooks = false
local pending = {}
local UEHelpers = require('UEHelpers')
local function log(s) print('[ShoulderCamera] ' .. s .. '\n') end
for key, action in pairs({[Key.F6]='toggle', [Key.F7]='shoulder', [Key.HOME]='recenter'}) do
    RegisterKeyBind(key, function() pending[#pending+1]=action end)
end
local controllerPath = '/Game/NewInputSystem/TormentedSouls2PlayerController.TormentedSouls2PlayerController_C:'
local modeHooks = {
    SwitchMapToMain='gameplay', SwitchMapToInGame='gameplay',
    SwitchMapToInventory='inventory', SwitchMapInventory='inventory',
    SwitchMapPauseMenu='pause', SwitchMapToPauseMenu='pause',
    SwitchMapToPuzzle='puzzle', SwitchToPuzzle='puzzle',
    SwitchMapToPreview='preview', SwitchMapToPOI='poi',
    SwitchMapToDialogue='dialogue', SwitchMapToCinematic='cinematic',
    SwitchMapToSaveScreen='save', SwitchMapToMainMenu='menu',
    SwitchMapToGameOver='gameover', SwitchMapToCredits='credits',
    SwitchMapToDebug='debug', SwitchMapToPopUpText='text', SwitchMapToTextDisplayer='text',
}
LoopInGameThreadAfterFrames(1, function()
    if not initializedHooks then
        if StaticFindObject(controllerPath .. 'SwitchMapToMain'):IsValid() then
            initializedHooks = true
            for name, mode in pairs(modeHooks) do
                if StaticFindObject(controllerPath .. name):IsValid() then
                    local ok, err = pcall(RegisterHook, controllerPath .. name, function() core.mode_changed(mode) end)
                    if not ok then log('Mode hook unavailable: '..name..' '..tostring(err)) end
                end
            end
        end
    end
    local pc = UEHelpers.GetPlayerController()
    if pc and pc:IsValid() then
        local dt = UEHelpers.GetGameplayStatics():GetWorldDeltaSeconds(pc)
        for _,action in ipairs(pending) do core.action(action) end
        pending={}
        local ok,err=pcall(core.update, pc, dt)
        if not ok then pcall(core.shutdown);core.fault=true;log('DISABLED after error: '..tostring(err)) end
    end
end)
log('Loaded. F6 toggle, F7 shoulder, Home recenter.')
