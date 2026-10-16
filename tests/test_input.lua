function FName(s) return {ToString=function() return s end} end
local function object(name)
    return {IsValid=function() return true end,GetFName=function() return FName(name) end,GetAddress=function() return name end}
end
local function array(values)
    function values:ForEach(fn) for i,v in ipairs(self) do fn(i,{get=function() return v end}) end end
    return values
end
local move,shortcut,other=object('IA_Move_DPAD'),object('IA_InGame_Shortcut_Stick'),object('OtherAction')
local contexts={}
for _,name in ipairs({'IMC_InGame','IMC_InGame2','IMC_InGame3','IMC_Inventory'}) do
    local ctx=object(name)
    ctx.Mappings=array({})
    for _,key in ipairs({'Gamepad_DPad_Up','Gamepad_DPad_Down','Gamepad_DPad_Left','Gamepad_DPad_Right','W'}) do
        table.insert(ctx.Mappings,{Action=move,Key={KeyName=FName(key)},Modifiers={key}})
    end
    table.insert(ctx.Mappings,{Action=shortcut,Key={KeyName=FName('Gamepad_Right2D')},Modifiers={'deadzone'}})
    contexts[name]=ctx
end
local rebuilds=0
function StaticFindObject(path)
    if path:find('Default__EnhancedInputLibrary') then
        return {IsValid=function() return true end,RequestRebuildControlMappingsUsingContext=function() rebuilds=rebuilds+1 end}
    end
    return contexts[path:match('%.([^%.]+)$')]
end
local input=dofile(SOURCE..'/input.lua')
input.update(true,0.016)
assert(rebuilds==3)
for _,name in ipairs({'IMC_InGame','IMC_InGame2','IMC_InGame3'}) do
    local maps=contexts[name].Mappings
    for i=1,4 do assert(maps[i].Action==shortcut and maps[i].Modifiers[1]:find('DPad')) end
    assert(maps[1].Key.KeyName:ToString()=='Gamepad_DPad_Down','Shortcut Y direction must be opposite movement Y')
    assert(maps[2].Key.KeyName:ToString()=='Gamepad_DPad_Up')
    assert(maps[3].Key.KeyName:ToString()=='Gamepad_DPad_Left')
    assert(maps[4].Key.KeyName:ToString()=='Gamepad_DPad_Right')
    assert(maps[5].Action==move,'Keyboard movement must remain unchanged')
    assert(maps[6].Key.KeyName:ToString()=='None','Right stick shortcut must be disabled')
end
assert(contexts.IMC_Inventory.Mappings[1].Action==move,'Menu context must remain unchanged')
input.update(false,0.016)
for _,name in ipairs({'IMC_InGame','IMC_InGame2','IMC_InGame3'}) do
    assert(contexts[name].Mappings[1].Action==move)
    assert(contexts[name].Mappings[1].Key.KeyName:ToString()=='Gamepad_DPad_Up')
    assert(contexts[name].Mappings[2].Key.KeyName:ToString()=='Gamepad_DPad_Down')
    assert(contexts[name].Mappings[6].Key.KeyName:ToString()=='Gamepad_Right2D')
end
input.update(true,0.016)
contexts.IMC_InGame.Mappings[1].Action=other
input.restore()
assert(contexts.IMC_InGame.Mappings[1].Action==other,'Restore must preserve another mod remap')
print('PASS: all three presets, D-pad, right stick, keyboard/menu preservation, toggle and restoration')
