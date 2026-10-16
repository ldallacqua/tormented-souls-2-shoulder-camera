-- Remap only the three exploration presets. Menu and puzzle contexts stay native.
local M={}
local saved={}
local elapsed=1
local library
local function valid(o) return o and o:IsValid() end
local function rebuild(ctx)
    if not valid(library) then library=StaticFindObject('/Script/EnhancedInput.Default__EnhancedInputLibrary') end
    library:RequestRebuildControlMappingsUsingContext(ctx,false)
end
local function restore()
    for _,state in pairs(saved) do
        if valid(state.context) then
            state.context.Mappings:ForEach(function(i,entry)
                local old=state.entries[i]
                if old then
                    local m=entry:get()
                    -- Do not overwrite an unrelated remap performed by another mod.
                    if m.Action:GetAddress()==old.appliedAction:GetAddress() and m.Key.KeyName:ToString()==old.appliedKey then
                        m.Action=old.action
                        m.Key={KeyName=FName(old.key)}
                    end
                end
            end)
            rebuild(state.context)
        end
    end
    saved={};elapsed=1
end
M.restore=restore
function M.update(enabled,dt)
    if not enabled then if next(saved) then restore() end;return end
    elapsed=elapsed+dt
    if elapsed<1 then return end
    elapsed=0
    for _,name in ipairs({'IMC_InGame','IMC_InGame2','IMC_InGame3'}) do
        local ctx=StaticFindObject('/Game/NewInputSystem/'..name..'.'..name)
        if valid(ctx) and (not saved[name] or not valid(saved[name].context) or saved[name].context:GetAddress()~=ctx:GetAddress()) then
            local shortcut
            ctx.Mappings:ForEach(function(_,entry)
                local m=entry:get()
                if m.Action:GetFName():ToString()=='IA_InGame_Shortcut_Stick' then shortcut=m.Action end
            end)
            if valid(shortcut) then
                local state={context=ctx,entries={}}
                saved[name]=state -- Save before mutating, so error recovery can restore partial work.
                ctx.Mappings:ForEach(function(i,entry)
                    local m=entry:get()
                    local key=m.Key.KeyName:ToString()
                    local action=m.Action:GetFName():ToString()
                    if action=='IA_Move_DPAD' and key:match('^Gamepad_DPad_') then
                        -- Shortcut UI uses the opposite Y sign from movement.
                        local mapped=key=='Gamepad_DPad_Up' and 'Gamepad_DPad_Down' or key=='Gamepad_DPad_Down' and 'Gamepad_DPad_Up' or key
                        state.entries[i]={action=m.Action,key=key,appliedAction=shortcut,appliedKey=mapped}
                        m.Action=shortcut
                        m.Key={KeyName=FName(mapped)}
                    elseif action=='IA_InGame_Shortcut_Stick' and key=='Gamepad_Right2D' then
                        state.entries[i]={action=m.Action,key=key,appliedAction=m.Action,appliedKey='None'}
                        m.Key={KeyName=FName('None')}
                    end
                end)
                rebuild(ctx)
                print('[ShoulderCamera] D-pad shortcuts enabled: '..name..'\n')
            end
        end
    end
end
return M
