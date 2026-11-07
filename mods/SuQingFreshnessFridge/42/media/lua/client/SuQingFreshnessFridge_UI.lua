require "SuQingFreshnessFridge/Core"
local C=SuQingFreshnessFridge

local function fill(playerIndex,context,worldObjects,test)
    if not C.SP() or not C.Runtime or not C.Runtime.ready then return end
    local seen={}
    for _,object in ipairs(worldObjects) do
        if C.IsFridge(object) and not seen[object] then
            seen[object]=true
            local state=C.State(object)
            local container=C.Container(object)
            if state and container then
                if test then return true end
                local label=state.on and "IGUI_SuQingFreshnessFridge_TurnOff" or "IGUI_SuQingFreshnessFridge_TurnOn"
                local option=context:addOption(getText(label),object,function(target)
                    C.Runtime.Toggle(target)
                end)
                if ISToolTip then
                    local tip=ISToolTip:new()
                    tip:initialise()
                    tip:setVisible(false)
                    local powered=C.Powered(object,container)
                    local cfg=C.Config()
                    local status=not cfg.enabled and "IGUI_SuQingFreshnessFridge_GlobalOff" or
                        (not powered and "IGUI_SuQingFreshnessFridge_Unpowered" or
                        (state.on and "IGUI_SuQingFreshnessFridge_Restoring" or "IGUI_SuQingFreshnessFridge_Off"))
                    tip.description=getText(status).." <LINE> "..
                        getText("IGUI_SuQingFreshnessFridge_Capacity",tostring(cfg.capacity)).." <LINE> "..
                        getText("IGUI_SuQingFreshnessFridge_Hours",tostring(cfg.restoreHours)).." <LINE> "..
                        getText("IGUI_SuQingFreshnessFridge_ObservedOnly")
                    option.toolTip=tip
                end
            end
        end
    end
end

Events.OnFillWorldObjectContextMenu.Add(fill)
