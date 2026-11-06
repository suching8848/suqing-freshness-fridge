-- Existing host supplies real Java ItemContainer/IsoObject/Food, no World.
local callbacks={}
Events=setmetatable({}, {__index=function(t,key)
    callbacks[key]={};local event={Add=function(fn) callbacks[key][#callbacks[key]+1]=fn end};rawset(t,key,event);return event
end})
function CapacityRefreshEmit(name,...) for _,f in ipairs(callbacks[name] or {}) do f(...) end end
function getCell() return nil end
function getNumActivePlayers() return 0 end
function isGamePaused() return false end
ISTransferAction={transferItem=function(self,character,item) return item end}
CapacityRefreshAudit={calls=0,targets={},failBefore=false,failAfter=false}
local T=CapacityRefreshAudit
T.index=__classmetatables[ItemContainer.class].__index
T.nativeSetter=T.index.setCapacity
T.index.setCapacity=function(container,target,...)
    T.calls=T.calls+1;T.targets[#T.targets+1]=target
    if T.failBefore then T.failBefore=false;error("capacity setter before sentinel",0) end
    local result=T.nativeSetter(container,target,...)
    if T.failAfter then T.failAfter=false;error("capacity setter after sentinel",0) end
    return result
end
function T.clearCounts() T.calls=0;T.targets={} end
return "native capacity-refresh setup; real containers, controlled events/cell absence"
