-- On-screen crosshair made of plain UMG widgets. HUD:ReceiveDrawHUD never fires in this
-- game (its HUD has no Blueprint draw event), so the crosshair is a viewport widget.
-- A small game widget (WBP_FPSShow) only hosts it: its tree root becomes our canvas.
local M={}
local log
local widget,parts=nil,{}
local shownColor=nil
local visible=false
local failed=false
local serial=0
local trustViewport=true -- Cleared if IsInViewport does not report our own widget.
local hosts={'/Game/UI/Utils/WBP_FPSShow.WBP_FPSShow_C','/Game/UI/Utils/WBP_Hover.WBP_Hover_C'}
local HIDDEN,HIT_TEST_INVISIBLE=2,3 -- ESlateVisibility
local NORMAL={R=1.0,G=1.0,B=1.0,A=0.85}
local ENEMY={R=1.0,G=0.18,B=0.12,A=0.95}
-- Centre dot and four ticks as {x,y,width,height} around the screen centre (Slate units).
local GAP,SIZE,THICK=6,9,2
local SHAPE={{-1.5,-1.5,3,3},{-THICK/2,-GAP-SIZE,THICK,SIZE},{-THICK/2,GAP,THICK,SIZE},
    {-GAP-SIZE,-THICK/2,SIZE,THICK},{GAP,-THICK/2,SIZE,THICK}}
local function valid(o) return o and o:IsValid() end
local function name(kind)
    serial=serial+1
    return FName(string.format('ShoulderCamera%s_%d_%d',kind,os.time(),serial))
end
-- Widgets are dropped from the viewport on level changes; rebuild then.
local function inViewport(w)
    if not trustViewport then return true end
    local ok,result=pcall(function() return w:IsInViewport() end)
    return not ok or result
end
local function build(pc)
    local class=nil
    for _,path in ipairs(hosts) do
        local c=StaticFindObject(path)
        if valid(c) then class=c;break end
    end
    if not class then error('no host widget class loaded') end
    local w=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary'):Create(pc,class,pc)
    if not valid(w) then error('widget creation failed') end
    local tree=w.WidgetTree
    local canvas=StaticConstructObject(StaticFindObject('/Script/UMG.CanvasPanel'),tree,name('Canvas'))
    tree.RootWidget=canvas
    local imageClass=StaticFindObject('/Script/UMG.Image')
    parts={}
    for _,r in ipairs(SHAPE) do
        local image=StaticConstructObject(imageClass,tree,name('Tick'))
        local slot=canvas:AddChildToCanvas(image)
        slot:SetAnchors({Minimum={X=0.5,Y=0.5},Maximum={X=0.5,Y=0.5}})
        slot:SetAlignment({X=0,Y=0})
        slot:SetPosition({X=r[1],Y=r[2]})
        slot:SetSize({X=r[3],Y=r[4]})
        parts[#parts+1]=image
    end
    w:SetVisibility(HIDDEN)
    w:AddToViewport(10)
    widget=w;shownColor=nil;visible=false
    -- Never rebuild every frame because of an unreliable viewport query.
    if not inViewport(w) then trustViewport=false;log('IsInViewport unreliable; rebuilding only when invalid') end
    log('Crosshair widget created on '..class:GetFName():ToString())
end
function M.init(logger) log=logger end
function M.update(pc,show,enemy)
    if failed then return end
    if not show then
        if visible and valid(widget) then pcall(function() widget:SetVisibility(HIDDEN) end) end
        visible=false
        return
    end
    local ok,err=pcall(function()
        if not valid(widget) or not inViewport(widget) then build(pc) end
        local color=enemy and ENEMY or NORMAL
        if color~=shownColor then
            for _,image in ipairs(parts) do image:SetColorAndOpacity(color) end
            shownColor=color
        end
        if not visible then widget:SetVisibility(HIT_TEST_INVISIBLE);visible=true end
    end)
    if not ok then failed=true;log('Crosshair unavailable: '..tostring(err));M.shutdown() end
end
function M.shutdown()
    if valid(widget) then pcall(function() widget:RemoveFromParent() end) end
    widget=nil;parts={};visible=false
end
return M
