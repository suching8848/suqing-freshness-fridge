-- SuQing's Freshness Fridge. No world or user files are edited by this module.
SuQingFreshnessFridge = SuQingFreshnessFridge or {}
local C = SuQingFreshnessFridge
if C.coreLoaded then return C end
C.coreLoaded = true
C.version = "0.2.0-rc.3"
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

local function refreshCapacity(container,capacity,force)
    local setter=container.setCapacity
    if not force and setter~=nil and capacityApplied[container]==capacity and capacitySetters[container]==setter then
        return false
    end
    -- setIsContainer(true) would replace the native ItemContainer and lose items.
    -- Clear first: even a forced same-target failure must retry on the next call.
    capacityApplied[container],capacitySetters[container]=nil,nil
    setter(container,capacity)
    capacityApplied[container],capacitySetters[container]=capacity,setter
    return true
end

function C.RefreshCapacity(object,force)
    local container=C.Container(object)
    if not container then return false end
    refreshCapacity(container,C.Config().capacity,force)
    return true
end

local function configToken(cfg)
    return tostring(cfg.enabled)..":"..tostring(cfg.restoreHours)..":"..tostring(cfg.allowRotten)
end

-- A pass belongs to one fridge in one synchronous sweep. Runtime invalidates
-- it at transfer, streaming and power boundaries, never across tick phases.
function C.BeginPass(object,forceCapacity)
    local container=C.Container(object)
    if not container then return nil end
    local cfg=C.Config()
    if refreshCapacity(container,cfg.capacity,forceCapacity) then
        container=C.Container(object)
        if not container then return nil end
        cfg=C.Config()
    end
    local state=C.State(object)
    return {object=object,container=container,cfg=cfg,token=configToken(cfg),powered=C.Powered(object,container),
        state=state,stateId=state and state.id,stateOn=state and state.on}
end

local function validPass(object,pass)
    if not pass or pass.invalidated or pass.powerInvalidated or pass.object~=object then return false end
    local state=pass.state
    return not state or (state.id==pass.stateId and state.on==pass.stateOn and state.schema==1)
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

local function directIn(food,container,pass,strict)
    if not container or food:getContainer()~=container then return false end
    if not pass then return true end
    local list=container:getItems()
    local slot=not strict and pass.index
    if slot and slot>=0 and slot<list:size() and list:get(slot)==food then return true end
    return list:contains(food)
end

function C.IsDirectFood(food,object,pass)
    if not C.IsFood(food) then return false end
    local container=validPass(object,pass) and pass.container or C.Container(object)
    return directIn(food,container,pass)
end

local function identity(food)
    return food.getID and tostring(food:getID()) or "?", food:getFullType()
end

local function eligibleFood(food,config,age,rotten)
    if food.isBurnt and food:isBurnt() then return nil,"burnt" end
    if food.isFertilized and food:isFertilized() then return nil,"fertilized" end
    local fresh=food:getOffAge()
    rotten=rotten or food:getOffAgeMax()
    age=age or food:getAge()
    if not C.Finite(fresh) or fresh<=0 or fresh>=100000000
       or not C.Finite(rotten) or rotten<fresh or rotten>=100000000
       or not C.Finite(age) or age<0 then return nil,"unsupported_age" end
    if not config.allowRotten and age>=rotten then return nil,"rotten_disabled" end
    return fresh,rotten
end

function C.Eligible(food,config)
    if not C.IsFood(food) then return nil,"not_food" end
    return eligibleFood(food,config)
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
    local record=C.FoodRecord(food)
    if not record then return end
    local md=food:getModData()
    C.RestoreFood(food)
    if md[C.foodKey]==record then md[C.foodKey]=nil end
end

local function signature(food,fullType,fresh,rotten)
    local cooked=food.isCooked and food:isCooked() or false
    return fullType..":"..tostring(fresh)..":"..tostring(rotten)..":"..tostring(cooked)
end

-- context.continuous is a volatile proof from this running session, never from
-- serialized timestamps. Unknown unloaded/offline/power intervals earn no credit.
local function stillOwned(food,object,pass,md,record,strict)
    if md[C.foodKey]~=record then return false end
    local container=not strict and validPass(object,pass) and pass.container or C.Container(object)
    if directIn(food,container,pass,strict) then return container end
    C.ClearFood(food)
    return false
end

local function ownershipChanged()
    return {active=false,elapsed=0,reason="ownership_changed"}
end

function C.SettleFood(food,object,time,context,pass)
    context=context or {}
    if not C.Finite(time) or not C.IsDirectFood(food,object,pass) then
        local record=C.FoodRecord(food)
        if not pass or (record and record.fridgeId==pass.stateId) then C.ClearFood(food) end
        return {active=false,elapsed=0,reason="outside_fridge"}
    end
    local md=food:getModData()
    local previous=md[C.foodKey]
    if previous~=nil and (type(previous)~="table" or previous.schema~=1) then
        return {active=false,elapsed=0,reason="unknown_schema"}
    end
    if previous and type(previous.shield)=="table" then
        local restored=C.RestoreFood(food)
        if restored then
            if pass then pass.invalidated=true end
            if not stillOwned(food,object,pass,md,previous,true) then return ownershipChanged() end
        end
    end
    local usePass=validPass(object,pass)
    local state,cfg,token
    if usePass then
        state,cfg,token=pass.state,pass.cfg,pass.token
    else
        state,cfg=C.State(object),C.Config()
        token=configToken(cfg)
    end
    local powered=context.powered==true and not (pass and pass.powerInvalidated)
    if pass and not usePass and powered then powered=C.Powered(object,C.Container(object)) end
    local age=food:getAge()
    local fresh,rotten=eligibleFood(food,cfg,age)
    local active=state~=nil and state.on and cfg.enabled and powered and fresh~=nil
    local id,fullType=identity(food)
    local sig=fresh and signature(food,fullType,fresh,rotten) or "unsupported"
    local elapsed=0
    local logicalAge=age
    local canCredit=active and context.continuous==true and previous
       and previous.active==true and previous.id==id and previous.fullType==fullType
       and previous.fridgeId==state.id and previous.token==token and previous.signature==sig
       and C.Finite(previous.time) and time>=previous.time
       and time-previous.time<=C.maxObservedGapHours
    if active and not canCredit then
        -- Settle the ordinary native aging that occurred before we observed this
        -- item. Stamping lastAged first would accidentally grant free preservation.
        food:updateAge(false)
        local container=stillOwned(food,object,pass,md,previous,true)
        if not container then
            if pass then pass.invalidated=true end
            return ownershipChanged()
        end
        state,cfg=C.State(object),C.Config()
        token=configToken(cfg)
        if pass then
            local currentPower=C.Powered(object,container)
            usePass=validPass(object,pass) and pass.container==container and pass.state==state
                and pass.powered==currentPower and pass.token==token and pass.cfg.capacity==cfg.capacity
            if not usePass then pass.invalidated=true end
            powered=powered and currentPower and not pass.powerInvalidated
        end
        age=food:getAge()
        fresh,rotten=eligibleFood(food,cfg,age)
        active=state~=nil and state.on and cfg.enabled and powered and fresh~=nil
        id,fullType=identity(food)
        sig=fresh and signature(food,fullType,fresh,rotten) or "unsupported"
    end
    if canCredit then
        elapsed=time-previous.time
        if age==previous.age and C.Finite(previous.logicalAge) then
            logicalAge=previous.logicalAge
        end
        if elapsed>0 then
            logicalAge=math.max(0,logicalAge-fresh*elapsed/cfg.restoreHours)
            if not usePass or logicalAge~=age then
                food:setAge(logicalAge)
                local container=stillOwned(food,object,pass,md,previous,false)
                if not container then return ownershipChanged() end
                age=food:getAge()
                if usePass and not validPass(object,pass) then
                    usePass=false
                    state,cfg=C.State(object),C.Config()
                    token=configToken(cfg)
                    powered=powered and not pass.powerInvalidated and C.Powered(object,container)
                    fresh,rotten=eligibleFood(food,cfg,age)
                    sig=fresh and signature(food,fullType,fresh,rotten) or "unsupported"
                    active=state~=nil and state.on and cfg.enabled and powered and fresh~=nil
                end
            end
        end
    else
        logicalAge=age
    end
    if active and not (usePass and previous and previous.time==time and food.getLastAged and food:getLastAged()==time) then
        food:setLastAged(time)
        if md[C.foodKey]~=previous then return ownershipChanged() end
    end
    local fridgeId=state and state.id or "invalid"
    if not usePass or not previous or previous.shield~=nil or previous.time~=time
        or previous.id~=id or previous.fullType~=fullType or previous.fridgeId~=fridgeId
        or previous.age~=age or previous.logicalAge~=logicalAge or previous.active~=active
        or previous.token~=token or previous.signature~=sig then
        md[C.foodKey]={schema=1,id=id,fullType=fullType,fridgeId=fridgeId,
            time=time,age=age,logicalAge=logicalAge,active=active,token=token,signature=sig}
    end
    return {active=active,elapsed=elapsed,reason=active and "restoring" or
        (not fresh and rotten or (not powered and "unpowered" or "disabled"))}
end

function C.ProtectFood(food,object,time,pass)
    if pass and pass.powerInvalidated then return false end
    if not C.IsDirectFood(food,object,pass) then return false end
    local usePass=validPass(object,pass)
    local age=food:getAge()
    local maxAge=usePass and food:getOffAgeMax()
    if usePass and C.Finite(maxAge) and C.Finite(age) and age<maxAge then return false end
    local cfg=usePass and pass.cfg or C.Config()
    local fresh,rotten=eligibleFood(food,cfg,age,maxAge)
    local record=C.FoodRecord(food)
    if not fresh or not record or not record.active or record.time~=time then return false end
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
    local shield={id=id,fullType=fullType,logicalAge=logicalAge,physicalAge=physical,time=time}
    record.shield=shield
    food:setAge(physical)
    if record.shield~=shield or C.FoodRecord(food)~=record then return false end
    shield.physicalAge=food:getAge() -- native float32 rounding is expected
    if pass and pass.powerInvalidated then C.RestoreFood(food);return false end
    food:setLastAged(time)
    return true
end

return C
