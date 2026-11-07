-- Offline mocks for native movable-state helpers and our container setup.
require = function() end
getCore = function() return {
    getGoodHighlitedColor = function() return {} end,
    getBadHighlitedColor = function() return {} end,
} end
IsoGridSquare = {ignoreBlockingSprites={add=function() end}}
IsoFlagType = setmetatable({}, {__index=function(_,key) return key end})
IsoObjectType = setmetatable({}, {__index=function(_,key) return key end})
Events = {}
for _, name in ipairs({"OnDynamicMovableRecipe","OnObjectAdded","LoadGridsquare"}) do
    Events[name] = {callbacks={}, Add=function(fn) table.insert(Events[name].callbacks,fn) end}
end
function copyTable(source)
    local out={}
    for k,v in pairs(source) do out[k]=type(v)=="table" and copyTable(v) or v end
    return out
end
instanceof = function(object, name) return object and object.kind==name end
local function derive(self)
    local class={}
    setmetatable(class,{__index=self})
    return class
end
ISBaseTimedAction={derive=derive,stop=function(self) self.stopped=true end}
ISBuildingObject={derive=derive}
isServer=function() return false end
isClient=function() return false end
showDebugInfoInChat=function() end
removeAction=function(_,_,cancelled) SuQingFreshnessFridge.lastCancelled=cancelled end
SuQingFreshnessFridge={
    capacity=200, registered=0,
    Config=function() return {capacity=SuQingFreshnessFridge.capacity} end,
    RegisterObject=function(object)
        SuQingFreshnessFridge.registered=SuQingFreshnessFridge.registered+1
        SuQingFreshnessFridge.lastObject=object
    end,
}
-- Building-only model dependency. Actual Core memo/native clamping is tested
-- separately with the complete Core/Building and real ItemContainer host.
SuQingFreshnessFridge.Container=function(object)
    if object:getContainerCount() ~= 1 then return nil end
    local container=object:getContainerByIndex(0)
    if container and container:getType()=="fridge" then return container end
end
SuQingFreshnessFridge.RefreshCapacity=function(object)
    local container=SuQingFreshnessFridge.Container(object)
    if not container then return false end
    local value=tonumber(SuQingFreshnessFridge.Config().capacity)
    if not value or value~=value or value<=-math.huge or value>=math.huge then value=200 end
    container:setCapacity(math.floor(math.max(50,math.min(1000,value))))
    return true
end
