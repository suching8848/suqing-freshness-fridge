require=function() return true end
local nativeInstanceof=instanceof
function instanceof(value,name)
    if type(value)=="table" and value.auditKind then return value.auditKind==name end
    return nativeInstanceof(value,name)
end
NativeCapacityQueue={}
ISTimedActionQueue={add=function(action) NativeCapacityQueue[#NativeCapacityQueue+1]=action end}
ISInventoryTransferAction={new=function(self,character,item,source,destination,time)
    return {character=character,item=item,source=source,destination=destination,time=time}
end}
NativeCapacityFallback=0
javaTransferItems=function() NativeCapacityFallback=NativeCapacityFallback+1 end
ProbeCharacter={auditKind="IsoGameCharacter",hasTrait=function() return false end}
return "native capacity bootstrap: real Java objects; only queue/character shell is simulated"
