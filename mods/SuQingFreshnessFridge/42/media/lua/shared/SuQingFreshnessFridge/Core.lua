-- SuQing's Freshness Fridge. No world or user files are edited by this module.
SuQingFreshnessFridge = SuQingFreshnessFridge or {}
local C = SuQingFreshnessFridge
if C.coreLoaded then return C end
C.coreLoaded = true
C.version = "0.1.0-rc.3"
C.objectKey = "SuQingFreshnessFridge"
C.foodKey = "SuQingFreshnessFridgeFood"
C.maxObservedGapHours = 0.25 -- larger clock jumps have unprovable power history
C.spritePrefix = "suqing_freshness_fridge_01_"
C.pending = setmetatable({}, {__mode="k"})
C.sprites = {}
for i=0,3 do C.sprites[C.spritePrefix..i] = true end

function C.Finite(value)
    return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end

local function number(value, default, low, high)
    if not C.Finite(value) then value=default end
    return math.max(low,math.min(high,value))
end

function C.Config()
    local s=SandboxVars and SandboxVars.SuQingFreshnessFridge or {}
    return {
        enabled=s.Enabled~=false,
        capacity=math.floor(number(s.Capacity,200,50,1000)),
        restoreHours=number(s.RestoreHours,10,0.25,1000),
        allowRotten=s.AllowRotten~=false,
    }
end

function C.SP()
    return not (type(isClient)=="function" and isClient())
       and not (type(isServer)=="function" and isServer())
end

function C.IsFridge(object)
    if not object or not object.getSprite then return false end
    local sprite=object:getSprite()
    return sprite and sprite.getName and C.sprites[sprite:getName()]==true or false
end

function C.LiveWireAppliances()
    return LiveWire and LiveWire.VERSION=="1.7.2" and LiveWire.Appliances or nil
end

function C.IsLiveWireFridgeRecord(record)
    return type(record)=="table" and record.v==1 and record.kind=="fridge"
        and type(record.types)=="table" and record.types["0"]=="fridge"
end

local function liveWireCut(object)
    local appliances=C.LiveWireAppliances()
    local record=appliances and type(appliances.saved)=="function" and appliances.saved(object)
    return C.IsLiveWireFridgeRecord(record) and record.cut==true
end

function C.Container(object)
    if not C.IsFridge(object) then return nil end
    if object.getContainerCount and object:getContainerCount()~=1 then return nil end
    local container=object.getContainer and object:getContainer() or nil
    if not container and object.getContainerByIndex then container=object:getContainerByIndex(0) end
    if not container or not container.getType then return nil end
    local kind=container:getType()
    if kind=="fridge" or (kind=="none" and liveWireCut(object)) then return container end
    return nil
end

function C.Powered(object,container)
    -- A live tile can still contain an appliance isolated by the equipment breaker.
    return container~=nil and container:getType()=="fridge" and not liveWireCut(object)
        and container.isPowered~=nil and container:isPowered()==true
end

function C.State(object)
    if not C.IsFridge(object) or not object.getModData then return nil end
    local md=object:getModData()
    local state=md[C.objectKey]
    if state~=nil and (type(state)~="table" or state.schema~=1) then return nil end
    if not state then
        C.serial=(C.serial or 0)+1
        local stamp=type(getTimestampMs)=="function" and getTimestampMs() or 0
        state={schema=1,id="SFF:"..tostring(stamp)..":"..tostring(C.serial),on=true}
        md[C.objectKey]=state
    end
    if type(state.id)~="string" or state.id=="" or type(state.on)~="boolean" then return nil end
    return state
end

-- Native furniture getters clamp to 100; the Lua overlay returns the configured
-- value. Neither is a raw-field oracle. Memoize only successful writes, without
-- retaining a container through an unknown per-instance setter closure.
local capacityApplied = setmetatable({}, {__mode="k"})
local capacitySetters = setmetatable({}, {__mode="kv"})
function C.ResetCapacityCache()
    capacityApplied = setmetatable({}, {__mode="k"})
    capacitySetters = setmetatable({}, {__mode="kv"})
end

function C.RefreshCapacity(object,force)
    local container=C.Container(object)
    if not container then return false end
    local capacity=C.Config().capacity
    local setter=container.setCapacity
    if not force and setter~=nil and capacityApplied[container]==capacity and capacitySetters[container]==setter then
        return true
    end
    -- setIsContainer(true) would replace the native ItemContainer and lose items.
    -- Clear first: even a forced same-target failure must retry on the next call.
    capacityApplied[container],capacitySetters[container]=nil,nil
    setter(container,capacity)
    capacityApplied[container],capacitySetters[container]=capacity,setter
    return true
end

function C.RegisterObject(object)
    if not C.IsFridge(object) or not C.State(object) then return false end
    C.pending[object]=true
    if C.Runtime and C.Runtime.Register then return C.Runtime.Register(object) end
    return true
end

function C.IsFood(food)
    return food and type(instanceof)=="function" and instanceof(food,"Food") or false
end

function C.IsDirectFood(food,object)
    if not C.IsFood(food) then return false end
    local container=C.Container(object)
    return container~=nil and food:getContainer()==container
end

local function identity(food)
    return food.getID and tostring(food:getID()) or "?", food:getFullType()
end

function C.Eligible(food,config)
    if not C.IsFood(food) then return nil,"not_food" end
    if food.isBurnt and food:isBurnt() then return nil,"burnt" end
    if food.isFertilized and food:isFertilized() then return nil,"fertilized" end
    local fresh=food:getOffAge()
    local rotten=food:getOffAgeMax()
    local age=food:getAge()
    if not C.Finite(fresh) or fresh<=0 or fresh>=100000000
       or not C.Finite(rotten) or rotten<fresh or rotten>=100000000
       or not C.Finite(age) or age<0 then return nil,"unsupported_age" end
    if not config.allowRotten and age>=rotten then return nil,"rotten_disabled" end
    return fresh,rotten
end

function C.FoodRecord(food)
    if not food or not food.getModData then return nil end
    local record=food:getModData()[C.foodKey]
    return type(record)=="table" and record.schema==1 and record or nil
end

-- Native replacement/removal protection is conditional. When automatic removal
-- is disabled, never move age across a freshness boundary: only suspend an
-- existing per-item rotten replacement, if any. Older age shields still recover.
function C.RestoreFood(food)
    local record=C.FoodRecord(food)
    local shield=record and record.shield
    if type(shield)~="table" then return false,"no_shield" end
    record.shield=nil
    local id,fullType=identity(food)
    if shield.id~=id or shield.fullType~=fullType then return false,"identity_changed" end
    if shield.mode=="replacement" then
        if type(shield.originalReplacement)~="string" or shield.originalReplacement==""
           or shield.physicalReplacement~="" then return false,"invalid_shield" end
        if not food.getReplaceOnRotten or not food.setReplaceOnRotten then
            return false,"missing_replacement_api"
        end
        -- Replacement restoration is independent of age. An age edit must not
        -- strand the original replacement rule, and a new replacement rule from
        -- another mod must not be overwritten by our recovery receipt.
        if food:getReplaceOnRotten()~=shield.physicalReplacement then
            return false,"external_replacement_edit"
        end
        food:setReplaceOnRotten(shield.originalReplacement)
        return true,"restored"
    end
    if shield.mode~=nil then return false,"unknown_shield" end
    if not C.Finite(shield.logicalAge) or shield.logicalAge<0
       or not C.Finite(shield.physicalAge) or not C.Finite(shield.time) then
        return false,"invalid_shield"
    end
    local current=food:getAge()
    -- Another mod explicitly edited age: respect it rather than restoring over it.
    if not C.Finite(current) or math.abs(current-shield.physicalAge)>0.0001 then
        return false,"external_age_edit"
    end
    food:setAge(shield.logicalAge)
    food:setLastAged(shield.time)
    record.age=food:getAge()
    record.logicalAge=shield.logicalAge
    return true,"restored"
end

function C.ClearFood(food)
    if not food or not food.getModData then return end
    C.RestoreFood(food)
    local md=food:getModData()
    if C.FoodRecord(food) then md[C.foodKey]=nil end
end

local function signature(food,fresh,rotten)
    local cooked=food.isCooked and food:isCooked() or false
    return food:getFullType()..":"..tostring(fresh)..":"..tostring(rotten)..":"..tostring(cooked)
end

-- context.continuous is a volatile proof from this running session, never from
-- serialized timestamps. Unknown unloaded/offline/power intervals earn no credit.
function C.SettleFood(food,object,time,context)
    context=context or {}
    C.RestoreFood(food)
    if not C.Finite(time) or not C.IsDirectFood(food,object) then
        C.ClearFood(food)
        return {active=false,elapsed=0,reason="outside_fridge"}
    end
    local state=C.State(object)
    local cfg=C.Config()
    local fresh,rotten=C.Eligible(food,cfg)
    local active=state~=nil and state.on and cfg.enabled and context.powered==true and fresh~=nil
    local md=food:getModData()
    local previous=md[C.foodKey]
    if previous~=nil and (type(previous)~="table" or previous.schema~=1) then
        return {active=false,elapsed=0,reason="unknown_schema"}
    end
    local id,fullType=identity(food)
    local token=tostring(cfg.enabled)..":"..tostring(cfg.restoreHours)..":"..tostring(cfg.allowRotten)
    local sig=fresh and signature(food,fresh,rotten) or "unsupported"
    local elapsed=0
    local logicalAge=food:getAge()
    local canCredit=active and context.continuous==true and type(previous)=="table"
       and previous.active==true and previous.id==id and previous.fullType==fullType
       and previous.fridgeId==state.id and previous.token==token and previous.signature==sig
       and C.Finite(previous.time) and time>=previous.time
       and time-previous.time<=C.maxObservedGapHours
    if active and not canCredit then
        -- Settle the ordinary native aging that occurred before we observed this
        -- item. Stamping lastAged first would accidentally grant free preservation.
        food:updateAge(false)
        fresh,rotten=C.Eligible(food,cfg)
        active=fresh~=nil
        sig=fresh and signature(food,fresh,rotten) or "unsupported"
    end
    if canCredit then
        elapsed=time-previous.time
        if food:getAge()==previous.age and C.Finite(previous.logicalAge) then
            logicalAge=previous.logicalAge
        end
        if elapsed>0 then
            logicalAge=math.max(0,logicalAge-fresh*elapsed/cfg.restoreHours)
            food:setAge(logicalAge)
        end
    else
        logicalAge=food:getAge()
    end
    if active then food:setLastAged(time) end
    md[C.foodKey]={schema=1,id=id,fullType=fullType,fridgeId=state and state.id or "invalid",
        time=time,age=food:getAge(),logicalAge=logicalAge,active=active,token=token,signature=sig}
    return {active=active,elapsed=elapsed,reason=active and "restoring" or
        (not fresh and rotten or (context.powered~=true and "unpowered" or "disabled"))}
end

function C.ProtectFood(food,object,time)
    if not C.IsDirectFood(food,object) then return false end
    local cfg=C.Config()
    local fresh,rotten=C.Eligible(food,cfg)
    local record=C.FoodRecord(food)
    if not fresh or not record or not record.active or record.time~=time then return false end
    local age=food:getAge()
    if age<rotten then return false end
    local id,fullType=identity(food)
    local removal=SandboxVars and SandboxVars.DaysForRottenFoodRemoval
    if C.Finite(removal) and removal<0 then
        -- With native automatic removal disabled, age itself poses no deletion
        -- risk. Keep the actual rotten state throughout the entire update, even
        -- if an optimizer schedules pre/post callbacks on different frames.
        local replacement=food.getReplaceOnRotten and food:getReplaceOnRotten() or nil
        if type(replacement)~="string" or replacement=="" then return false end
        if not food.setReplaceOnRotten then return false end
        record.shield={mode="replacement",id=id,fullType=fullType,
            originalReplacement=replacement,physicalReplacement="",time=time}
        food:setReplaceOnRotten("")
        return true
    end
    -- Keep the existing conservative age guard for enabled/unknown native
    -- removal policies. This branch is not used by the current personal save.
    local physical=math.max(0,rotten-math.max(0.001,rotten*0.00001))
    local logicalAge=C.Finite(record.logicalAge) and record.age==age and record.logicalAge or age
    record.shield={id=id,fullType=fullType,logicalAge=logicalAge,physicalAge=physical,time=time}
    food:setAge(physical)
    record.shield.physicalAge=food:getAge() -- native float32 rounding is expected
    food:setLastAged(time)
    return true
end

return C
