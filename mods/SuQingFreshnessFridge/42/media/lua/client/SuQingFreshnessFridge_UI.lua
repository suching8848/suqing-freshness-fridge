require "SuQingFreshnessFridge/Batch"
require "SuQingFreshnessFridge_Lock"
local C=SuQingFreshnessFridge
local B=C.Batch
local prefix="IGUI_SuQingFreshnessFridge_"

local function addFridge(context,object,container,playerIndex)
    local runtime=C.Runtime
    local sealed=B.IsSealed(object)
    local cfg=C.Config()
    local powered=C.Powered(object,container)
    local available=runtime and runtime.CanStartBatch and runtime.CanStartBatch()
    local label=getText(prefix.."SealBatch")
    local status
    if sealed then
        local hours=B.Remaining(object)
        local minutes=hours and math.max(0,math.ceil(hours*60))
        local batch=B.Get(object)
        if not minutes then label=getText(prefix.."BatchSealed")
        elseif minutes==0 then label=getText(prefix.."BatchReady")
        elseif not powered then label=getText(prefix.."BatchPaused",tostring(minutes))
        else label=getText(prefix.."BatchRemaining",tostring(minutes)) end
        status=getText(prefix..(type(batch)=="table" and batch.phase=="recovering"
            and "BatchReason_recovery_required" or "BatchLocked"))
    elseif not cfg.enabled then status=getText(prefix.."GlobalOff")
    elseif not powered then status=getText(prefix.."BatchReason_unpowered")
    elseif not available then status=getText(prefix.."BatchReason_lock_unavailable")
    else status=getText(prefix.."BatchInfo",tostring(B.Hours())) end

    local option=context:addOption(label,object,function(target)
        if not runtime or not runtime.StartBatch then return end
        local ok,reason=runtime.StartBatch(target)
        if ok then return end
        local player=getSpecificPlayer(playerIndex)
        if player then
            player:Say(getTextOrNull(prefix.."BatchReason_"..tostring(reason))
                or getText(prefix.."BatchRejected"))
        end
    end)
    option.notAvailable=sealed or not cfg.enabled or not powered or not available
    if not ISToolTip then return end
    local tip=ISToolTip:new()
    tip:initialise()
    tip:setVisible(false)
    tip.description=status.." <LINE> "..getText(prefix.."Capacity",tostring(cfg.capacity))
    option.toolTip=tip
end

local function fill(playerIndex,context,worldObjects,test)
    if not C.SP() then return end
    local seen={}
    for _,object in ipairs(worldObjects) do
        if C.IsFridge(object) and not seen[object] then
            seen[object]=true
            local container=C.Container(object)
            if container then
                if test then return true end
                addFridge(context,object,container,playerIndex)
            end
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(fill)
