require "SuQingFreshnessFridge/Core"

local C=SuQingFreshnessFridge
C.Batch=C.Batch or {}
local B=C.Batch
if B.loaded then return B end
B.loaded=true
B.objectKey="SuQingFreshnessFridgeBatch"
B.foodKey="SuQingFreshnessFridgeBatchFood"
-- Stock B42 Food.updateRotting, finishupdate and shouldUpdateInWorld recognize
-- this exact nonperishable value. Food.save/load preserve it and cookability.
B.nonperishable=1000000000
local serial=0
local busy=setmetatable({}, {__mode="k"})

function B.Hours()
    local settings=SandboxVars and SandboxVars.SuQingFreshnessFridge
    local hours=settings and settings.BatchHours
    return C.Finite(hours) and math.max(0.25,math.min(24,hours)) or 12
end

function B.Get(object)
    if object and object.getModData and (not object.hasModData or object:hasModData())
        and C.IsFridge(object) then
        return object:getModData()[B.objectKey]
    end
end

function B.IsSealed(object)
    -- Unknown receipts are also locked until they can be safely recovered.
    return B.Get(object)~=nil
end

function B.IsLockedContainer(container)
    local object=container and container.getParent and container:getParent()
    if not B.IsSealed(object) then return false end
    local actual=object.getContainer and object:getContainer()
    if not actual and object.getContainerByIndex then actual=object:getContainerByIndex(0) end
    return actual==container
end

function B.IsSealedFood(food)
    if not C.IsFood(food) then return false end
    if (not food.hasModData or food:hasModData()) and food:getModData()[B.foodKey]~=nil then return true end
    return B.IsLockedContainer(food:getContainer())
end

local function nativeMethods(food)
    return food.getOffAgeMax and food.setOffAgeMax and food.isCookable and food.setIsCookable
        and food.getAge and food.setAge and food.getLastAged and food.setLastAged
end

local function validGuard(food,guard,id,fullType)
    return type(guard)=="table" and guard.schema==1 and guard.foodId==id and guard.fullType==fullType
        and type(guard.batchId)=="string" and type(guard.fridgeId)=="string"
        and C.Finite(guard.offAgeMax) and guard.offAgeMax>=0 and guard.offAgeMax<100000000
        and guard.offAgeMax==math.floor(guard.offAgeMax) and type(guard.cookable)=="boolean"
        and nativeMethods(food)
end

local function setGuard(food)
    food:setOffAgeMax(B.nonperishable)
    food:setIsCookable(false)
    if food:getOffAgeMax()~=B.nonperishable or food:isCookable() then
        error("sealed fridge native guard was not retained")
    end
end

local function canRestore(food,guard)
    local maxAge=food:getOffAgeMax()
    local cookable=food:isCookable()
    return (maxAge==B.nonperishable or maxAge==guard.offAgeMax)
        and (cookable==false or cookable==guard.cookable)
end

local function restoreNative(food,guard)
    if not canRestore(food,guard) then error("sealed fridge native state changed") end
    food:setOffAgeMax(guard.offAgeMax)
    food:setIsCookable(guard.cookable)
    if food:getOffAgeMax()~=guard.offAgeMax or food:isCookable()~=guard.cookable then
        error("sealed fridge native state could not be restored")
    end
end

local function resume(food)
    local cell=type(getCell)=="function" and getCell()
    if cell and cell.addToProcessItems then cell:addToProcessItems(food) end
end

local function retire(food)
    local cell=type(getCell)=="function" and getCell()
    if cell and cell.addToProcessItemsRemove then cell:addToProcessItemsRemove(food) end
end

local function identity(food)
    return food.getID and tostring(food:getID()) or "unknown",food:getFullType()
end

local function validBatch(object,batch)
    if type(batch)~="table" or batch.schema~=1 or type(batch.id)~="string"
        or type(batch.roster)~="table" or not C.Finite(batch.count) or batch.count<1
        or batch.count~=math.floor(batch.count) or not C.Finite(batch.startedAt) or batch.startedAt<0
        or not C.Finite(batch.hours) or batch.hours<0.25 or batch.hours>24
        or not C.Finite(batch.poweredHours) or batch.poweredHours<0 or batch.poweredHours>batch.hours then return false end
    local state=object:getModData()[C.objectKey]
    return type(state)=="table" and state.schema==1 and type(state.on)=="boolean"
        and type(state.id)=="string" and batch.fridgeId==state.id
        and (batch.phase=="sealing" or batch.phase=="sealed"
            or batch.phase=="finishing" or batch.phase=="recovering")
end

function B.Remaining(object)
    local batch=B.Get(object)
    if validBatch(object,batch) then return batch.hours-batch.poweredHours end
end

-- Runtime computes a verified powered interval from consecutive observations.
-- The saved record deliberately holds no wall-clock or unobserved credit.
function B.Advance(object,elapsed)
    if not C.SP() then return false,"unsupported" end
    local batch=B.Get(object)
    if not validBatch(object,batch) then return false,"invalid_batch" end
    if batch.phase~="sealed" or busy[object] then return false,"busy" end
    if not C.Finite(elapsed) or elapsed<0 then return false,"invalid_time" end
    batch.poweredHours=math.min(batch.hours,batch.poweredHours+elapsed)
    return true
end

local function collect(inventory,batch,expectGuard)
    local list=inventory:getItems()
    local entries,seen={},{}
    local matches=list:size()==batch.count
    for i=0,list:size()-1 do
        local food=list:get(i)
        local isDirect=C.IsFood(food) and food:getContainer()==inventory
        local id,fullType
        if isDirect then id,fullType=identity(food) end
        local md=isDirect and food:getModData()
        local guard=md and md[B.foodKey]
        if md and guard~=nil then
            if not validGuard(food,guard,id,fullType) or not canRestore(food,guard) then return nil end
            entries[#entries+1]={food=food,md=md,guard=guard}
            if expectGuard and (food:getOffAgeMax()~=B.nonperishable or food:isCookable()) then matches=false end
        elseif isDirect and batch.roster[id]==fullType and food.getOffAgeMax
            and food:getOffAgeMax()==B.nonperishable then
            -- A known guarded item lost the only copy of its original state.
            return nil
        end
        if not isDirect or seen[id] or batch.roster[id]~=fullType or not guard
            or guard.batchId~=batch.id or guard.fridgeId~=batch.fridgeId then
            matches=false
        end
        if id then seen[id]=true end
    end
    for id in pairs(batch.roster) do
        if not seen[id] then matches=false;break end
    end
    return entries,matches
end

local function release(object,batch,entries)
    if B.Get(object)~=batch then return false end
    for _,entry in ipairs(entries) do
        if entry.md[B.foodKey]~=entry.guard then return false end
    end
    for _,entry in ipairs(entries) do entry.md[B.foodKey]=nil end
    object:getModData()[B.objectKey]=nil
    return true
end

local function reassert(entries)
    local rolledBack=true
    for _,entry in ipairs(entries) do
        local reverted=pcall(function()
            if entry.md[B.foodKey]~=entry.guard or not canRestore(entry.food,entry.guard) then
                error("sealed fridge food receipt changed")
            end
            setGuard(entry.food)
            if entry.age~=nil then entry.food:setAge(entry.age) end
            if entry.lastAged~=nil then entry.food:setLastAged(entry.lastAged) end
            retire(entry.food)
        end)
        rolledBack=rolledBack and reverted
    end
    return rolledBack
end

local function recoverBatch(object,batch,entries)
    batch.phase="recovering"
    for _,entry in ipairs(entries) do
        local ok=pcall(function()
            restoreNative(entry.food,entry.guard)
            resume(entry.food)
        end)
        if not ok then reassert(entries);return false,"recovery_required" end
    end
    if not release(object,batch,entries) then reassert(entries);return false,"recovery_required" end
    return false,"manifest_changed"
end

local function start(object,time)
    if B.IsSealed(object) then return false,"already_sealed" end
    if not C.Finite(time) or time<0 then return false,"invalid_time" end
    local cfg=C.Config()
    if not cfg.enabled then return false,"disabled" end
    local state=C.State(object)
    local inventory=C.Container(object)
    if not state or not inventory then return false,"invalid_fridge" end
    if not C.Powered(object,inventory) then return false,"unpowered" end
    local list=inventory:getItems()
    local count=list:size()
    if count==0 then return false,"empty" end
    serial=serial+1
    local stamp=type(getTimestampMs)=="function" and getTimestampMs() or 0
    local batchId=state.id..":"..tostring(stamp)..":"..tostring(serial)
    local foods={}
    for i=0,count-1 do foods[i+1]=list:get(i) end
    local entries,roster={},{}
    for _,food in ipairs(foods) do
        -- Native heat can purify taint even when a food is not cookable.
        if not C.IsFood(food) or food:getContainer()~=inventory or not nativeMethods(food)
            or (food.isTainted and food:isTainted()) then return false,"unsafe_food" end
        local md=food:getModData()
        if md[B.foodKey]~=nil then return false,"guard_present" end
        C.RestoreFood(food)
        local fresh,rotten=C.Eligible(food,cfg)
        local id,fullType=identity(food)
        local cookable=food:isCookable()
        if not fresh or not C.Finite(rotten) or rotten~=math.floor(rotten)
            or id=="unknown" or type(fullType)~="string" or roster[id] or type(cookable)~="boolean" then
            return false,"unsafe_food"
        end
        roster[id]=fullType
        entries[#entries+1]={food=food,md=md,guard={schema=1,foodId=id,fullType=fullType,
            batchId=batchId,fridgeId=state.id,offAgeMax=rotten,cookable=cookable}}
    end
    local batch={schema=1,id=batchId,phase="sealing",fridgeId=state.id,startedAt=time,
        hours=B.Hours(),poweredHours=0,count=count,roster=roster}
    if not validBatch(object,batch) then return false,"invalid_time" end
    object:getModData()[B.objectKey]=batch
    local ok=pcall(function()
        for _,entry in ipairs(entries) do
            entry.md[B.foodKey]=entry.guard
            setGuard(entry.food)
            retire(entry.food)
        end
        local _,matches=collect(inventory,batch,true)
        if not matches or C.Container(object)~=inventory or not C.Powered(object,inventory) then
            error("sealed fridge changed during seal")
        end
        for _,entry in ipairs(entries) do C.ClearFood(entry.food) end
        batch.phase="sealed"
    end)
    if ok then return true,"sealed" end
    local current=collect(inventory,batch)
    if not current then return false,"recovery_required" end
    local _,reason=recoverBatch(object,batch,current)
    return false,reason=="manifest_changed" and "seal_failed" or reason
end

local function complete(object,time)
    local batch=B.Get(object)
    if batch==nil then return false,"not_sealed" end
    if not validBatch(object,batch) then return false,"invalid_batch" end
    if not C.Finite(time) or time<batch.startedAt then return false,"invalid_time" end
    local recovering=batch.phase=="sealing" or batch.phase=="recovering"
    if not recovering and batch.poweredHours<batch.hours then return false,"not_due" end
    local inventory=C.Container(object)
    if not inventory then return false,"invalid_fridge" end
    if not recovering and not C.Powered(object,inventory) then return false,"unpowered" end
    local entries,matches=collect(inventory,batch,batch.phase=="sealed")
    if not entries then return false,"recovery_required" end
    if recovering or not matches then return recoverBatch(object,batch,entries) end
    batch.phase="finishing"
    local ok=pcall(function()
        for _,entry in ipairs(entries) do
            local food=entry.food
            entry.age,entry.lastAged=food:getAge(),food:getLastAged()
            food:setAge(0)
            food:setLastAged(time)
            if food:getAge()~=0 or food:getLastAged()~=time then
                error("sealed fridge food age could not be committed")
            end
            restoreNative(food,entry.guard)
            resume(food)
        end
        local _,unchanged=collect(inventory,batch)
        if not unchanged or C.Container(object)~=inventory or not C.Powered(object,inventory)
            or not release(object,batch,entries) then error("sealed fridge changed during finish") end
    end)
    if ok then return true,"complete" end
    return false,reassert(entries) and "finish_failed" or "recovery_required"
end

local function runBatch(operation,object,time)
    if not C.SP() then return false,"unsupported" end
    if not C.IsFridge(object) then return false,"invalid_fridge" end
    if busy[object] then return false,"busy" end
    busy[object]=true
    local ok,result,reason=pcall(operation,object,time)
    busy[object]=nil
    if not ok then return false,B.IsSealed(object) and "recovery_required" or "seal_failed" end
    return result,reason
end

function B.Start(object,time)
    return runBatch(start,object,time)
end

function B.Complete(object,time)
    return runBatch(complete,object,time)
end

local function trustedOwner(food,loaded)
    if not loaded then return false end
    local inventory=food:getContainer()
    if inventory and inventory:getItems():contains(food) then return true end
    local world=food.getWorldItem and food:getWorldItem()
    local square=world and world:getSquare()
    return square and world:getItem()==food and square:getWorldObjects():contains(world) or false
end

function B.RecoverFood(food,loaded)
    if not C.SP() then return false,"unsupported" end
    if not C.IsFood(food) then return false,"unsafe_food" end
    if food.hasModData and not food:hasModData() then return false,"not_guarded" end
    local md=food:getModData()
    local guard=md[B.foodKey]
    local legacy=guard==nil and C.FoodRecord(food)
    if guard==nil and not legacy then return false,"not_guarded" end
    if B.IsLockedContainer(food:getContainer()) then return false,"still_sealed" end
    if not trustedOwner(food,loaded) then return false,"unknown_owner" end
    if guard==nil then C.ClearFood(food);resume(food);return true,"legacy_recovered" end
    local id,fullType=identity(food)
    if not validGuard(food,guard,id,fullType) or not canRestore(food,guard) then return false,"recovery_required" end
    local ok=pcall(function()
        restoreNative(food,guard)
        resume(food)
    end)
    if not ok or md[B.foodKey]~=guard or B.IsLockedContainer(food:getContainer()) or not trustedOwner(food,loaded) then
        reassert({{food=food,md=md,guard=guard}})
        return false,"recovery_required"
    end
    md[B.foodKey]=nil
    return true,"recovered"
end

return B
