require "SuQingFreshnessFridge/Core"
require "SuQingFreshnessFridge/Capacity"
require "TimedActions/ISTransferAction"
local C=SuQingFreshnessFridge
C.Runtime=C.Runtime or {}
local R=C.Runtime
if R.loaded then return R end
R.loaded=true
R.objects=setmetatable({}, {__mode="k"})
R.foods=setmetatable({}, {__mode="k"})
R.observed=setmetatable({}, {__mode="k"})
R.powerEdges=setmetatable({}, {__mode="k"})
R.pendingLoads=setmetatable({}, {__mode="k"})
R.squares=setmetatable({}, {__mode="k"})
R.stats={settled=0,protected=0,errors=0,unknownIntervals=0}
R.pass=0

local function now() return getGameTime():getWorldAgeHours() end
local function paused() return type(isGamePaused)=="function" and isGamePaused() end
local function report(errorText)
    R.stats.errors=R.stats.errors+1
    if R.stats.errors<=10 then print("[SuQingFreshnessFridge] "..tostring(errorText)) end
end

function R.IsLoaded(object)
    if not C.IsFridge(object) or not object.getSquare then return false end
    local square=object:getSquare()
    local cell=getCell()
    if not square or not cell or cell:getGridSquare(square:getX(),square:getY(),square:getZ())~=square then return false end
    local objects=square:getObjects()
    for i=0,objects:size()-1 do if objects:get(i)==object then return true end end
    return false
end

function R.Register(object)
    if not C.IsFridge(object) or not C.Container(object) or not C.State(object) then return false end
    C.RefreshCapacity(object)
    R.objects[object]=true
    C.pending[object]=nil
    return true
end

function R.RestoreAll()
    for food in pairs(R.foods) do C.RestoreFood(food) end
end

function R.Release(food)
    C.ClearFood(food)
    R.foods[food]=nil
    R.observed[food]=nil
end

local function liveWireReplayReady()
    local catchup=R.liveWireCatchup and LiveWire and LiveWire.FridgeCatchup
    local registry=catchup and catchup.onLoadChunk==R.liveWireCatchup and LiveWire.Registry
    return registry and registry.ready and not registry.readOnly
end

local function waitingForReplay(object)
    if not R.pendingLoads[object] then return false end
    if liveWireReplayReady() and object:getChunk()==R.pendingLoads[object] then return true end
    R.pendingLoads[object]=nil
    return false
end

function R.SettleOne(food,object,time,forceAnchor,protect,powered)
    if waitingForReplay(object) then return end
    if not C.IsDirectFood(food,object) then R.Release(food);return end
    C.RestoreFood(food)
    local observation=R.observed[food]
    local continuous=not forceAnchor and observation and observation.object==object and
        (observation.pass==R.pass or
        (observation.pass==R.pass-1 and R.completedPass==R.pass-1)) or false
    if not continuous then R.stats.unknownIntervals=R.stats.unknownIntervals+1 end
    if powered==nil then powered=C.Powered(object,C.Container(object)) end
    local result=C.SettleFood(food,object,time,{continuous=continuous,
        powered=powered and R.powerEdges[object]~=R.pass})
    R.foods[food]=object
    R.observed[food]={object=object,pass=R.pass}
    R.stats.settled=R.stats.settled+1
    if protect and result.active and C.ProtectFood(food,object,time) then
        R.stats.protected=R.stats.protected+1
    end
    return result
end

function R.SettleObject(object,time,protect,forceAnchor,forceCapacity)
    if not R.IsLoaded(object) then
        for food,owner in pairs(R.foods) do if owner==object then R.Release(food) end end
        R.objects[object]=nil
        R.pendingLoads[object]=nil
        R.powerEdges[object]=nil
        return
    end
    if waitingForReplay(object) then return end
    if not C.RefreshCapacity(object,forceCapacity) then return end
    local container=C.Container(object)
    local powered=C.Powered(object,container)
    local list=container:getItems()
    for i=0,list:size()-1 do
        local food=list:get(i)
        if C.IsFood(food) then R.SettleOne(food,object,time,forceAnchor,protect,powered) end
    end
end

function R.ScanSquare(square,streaming)
    if not square then return end
    if not R.ready then R.squares[square]=true end
    local chunk=streaming and liveWireReplayReady() and square.getChunk and square:getChunk()
    if not R.ready and not chunk then return end
    local objects=square:getObjects()
    for i=0,objects:size()-1 do
        local object=objects:get(i)
        if C.IsFridge(object) then
            -- PZO can dispatch LoadChunk across frames after LoadGridsquare.
            -- Do not advance lastAged before Live Wire has replayed this absence.
            if chunk then R.pendingLoads[object]=chunk end
            if R.ready then
                if C.Building and C.Building.EnsureObject then C.Building.EnsureObject(object) end
                R.Register(object)
            end
        end
    end
end

-- A bounded fallback catches native/foreign AddItem paths without world scans.
function R.Discover()
    local cell=getCell()
    local list=cell and cell:getProcessItems() or nil
    local size=list and list:size() or 0
    if size==0 then return end
    for _=1,math.min(size,32) do
        R.cursor=((R.cursor or -1)+1)%size
        local item=list:get(R.cursor)
        if C.IsFood(item) then
            C.RestoreFood(item)
            local container=item:getContainer()
            local object=container and container:getParent() or nil
            if C.IsFridge(object) and C.IsDirectFood(item,object) then R.Register(object) end
        end
    end
end

function R.PreTick()
    if not R.ready then return end
    R.RestoreAll()
    R.pass=R.pass+1
    R.phase="pre"
    for object in pairs(C.pending) do R.Register(object) end
    for square in pairs(R.squares) do R.ScanSquare(square);R.squares[square]=nil end
    R.Discover()
    for food,object in pairs(R.foods) do
        if not C.IsDirectFood(food,object) then R.Release(food) end
    end
    local time=now()
    local prepare=not paused()
    for object in pairs(R.objects) do R.SettleObject(object,time,prepare,not prepare) end
end

function R.PostTick()
    if not R.ready then return end
    R.RestoreAll()
    R.phase="post"
    local time=now()
    for object in pairs(R.objects) do R.SettleObject(object,time,false,false) end
    R.completedPass=R.pass
end

function R.Toggle(object)
    if not R.ready or not R.IsLoaded(object) then return end
    R.RestoreAll()
    R.SettleObject(object,now(),false,false)
    local state=C.State(object)
    if not state then return end
    state.on=not state.on
    for food,owner in pairs(R.foods) do if owner==object then R.observed[food]=nil end end
    R.SettleObject(object,now(),false,true)
    if object.transmitModData then object:transmitModData() end
end

local function ownerOf(food)
    if not C.IsFood(food) then return nil end
    local container=food:getContainer()
    local object=container and container:getParent() or nil
    return C.IsDirectFood(food,object) and object or nil
end

function R.InstallTransferHook()
    if R.transferInstalled then return true end
    if not ISTransferAction or type(ISTransferAction.transferItem)~="function" then return false end
    R.nativeTransfer=ISTransferAction.transferItem
    R.transferWrapper=function(self,character,item,source,destination,...)
        if not R.ready then return R.nativeTransfer(self,character,item,source,destination,...) end
        if C.IsFood(item) then
            C.RestoreFood(item)
            local old=ownerOf(item)
            if old then R.SettleOne(item,old,now(),false,false) end
        end
        local result=R.nativeTransfer(self,character,item,source,destination,...)
        if C.IsFood(item) then
            local owner=ownerOf(item)
            if owner then R.Register(owner);R.SettleOne(item,owner,now(),true,false) else R.Release(item) end
        end
        if result and result~=item and C.IsFood(result) then
            local owner=ownerOf(result)
            if owner then R.Register(owner);R.SettleOne(result,owner,now(),true,false) end
        end
        return result
    end
    ISTransferAction.transferItem=R.transferWrapper
    R.transferInstalled=true
    return true
end

local function preparePowerBoundary(object,container)
    R.powerEdges[object]=R.pass
    local items=container:getItems()
    for i=0,items:size()-1 do
        local food=items:get(i)
        if C.IsFood(food) then
            C.RestoreFood(food)
            R.observed[food]=nil
        end
    end
end

local function prepareCircuit(object,saved,off)
    if not C.IsLiveWireFridgeRecord(saved) then return end
    local container=C.Container(object)
    if container and container:getType()~=(off and "none" or "fridge") then
        preparePowerBoundary(object,container)
    end
end

local function prepareAnchor(config,anchor)
    local radius,floors=config.tileRange(),config.verticalRange()
    local radiusSquared=radius*radius
    for object in pairs(R.objects) do
        local square=object:getSquare()
        if square then
            local dx,dy=square:getX()-anchor.x,square:getY()-anchor.y
            if dx*dx+dy*dy<=radiusSquared and math.abs(square:getZ()-anchor.z)<=floors
               and R.IsLoaded(object) then
                local container=C.Container(object)
                if container and container:getType()=="fridge" then preparePowerBoundary(object,container) end
            end
        end
    end
end

local function prepareChunk(chunk)
    for object,pending in pairs(R.pendingLoads) do
        if pending==chunk and object:getChunk()==chunk then
            local container=C.Container(object)
            if container then preparePowerBoundary(object,container) end
        end
    end
    for object in pairs(R.objects) do
        if not R.pendingLoads[object] and object.getChunk and object:getChunk()==chunk then
            local container=C.Container(object)
            if container then preparePowerBoundary(object,container) end
        end
    end
end

local function beforeLiveWire(prepare,...)
    local ok,errorText=pcall(prepare,...)
    if not ok then report(errorText) end
end

function R.InstallLiveWire()
    local appliances=C.LiveWireAppliances()
    if not C.SP() or not appliances or type(appliances.apply)~="function"
       or R.liveWireInstalled==appliances then return end
    local apply=appliances.apply
    appliances.apply=function(object,saved,off)
        if R.ready and type(saved)=="table" and saved.kind=="fridge" then
            beforeLiveWire(prepareCircuit,object,saved,off)
        end
        return apply(object,saved,off)
    end
    local anchor,config=LiveWire.Anchor,LiveWire.Config
    if anchor and type(anchor.set)=="function" and type(anchor.appliedState)=="table"
       and config and type(config.tileRange)=="function" and type(config.verticalRange)=="function" then
        local set=anchor.set
        anchor.set=function(id,entry,on)
            if R.ready and (anchor.appliedState[id]==true)~=(on==true) then
                beforeLiveWire(prepareAnchor,config,entry)
            end
            return set(id,entry,on)
        end
    end
    local catchup=LiveWire.FridgeCatchup
    if catchup and type(catchup.onLoadChunk)=="function" then
        local onLoadChunk=catchup.onLoadChunk
        catchup.onLoadChunk=function(chunk)
            beforeLiveWire(prepareChunk,chunk)
            local ok,result=pcall(onLoadChunk,chunk)
            for object,pending in pairs(R.pendingLoads) do
                if pending==chunk then R.pendingLoads[object]=nil end
            end
            if not ok then error(result) end
            return result
        end
        R.liveWireCatchup=catchup.onLoadChunk
    end
    R.liveWireInstalled=appliances
end

function R.Start()
    if R.ready or not C.SP() then return end
    if not C.Capacity or not C.Capacity.Install() or not C.Capacity.IsReady() then
        print("[SuQingFreshnessFridge] scoped capacity bridge unavailable; freshness disabled")
        return
    end
    if not R.InstallTransferHook() then
        print("[SuQingFreshnessFridge] native transfer hook unavailable; freshness disabled")
        return
    end
    R.InstallLiveWire()
    R.ready=true
    C.ResetCapacityCache()
    R.pass=0;R.completedPass=nil
    for square in pairs(R.squares) do R.ScanSquare(square);R.squares[square]=nil end
    for object in pairs(C.pending) do R.Register(object) end
    R.Discover()
    for object in pairs(R.objects) do R.SettleObject(object,now(),false,true) end
    print("[SuQingFreshnessFridge] "..C.version.." single-player ready; loaded, observed intervals only")
end

function R.Save()
    if not R.ready then return end
    R.RestoreAll()
    -- ItemContainer.save writes the physical field. Unknown Java writes above
    -- 100 cannot be observed through Lua getters, so reassert at this boundary.
    for object in pairs(R.objects) do R.SettleObject(object,now(),false,false,true) end
end

function R.Stop()
    C.ResetCapacityCache()
    R.RestoreAll()
    R.ready=false;R.phase=nil;R.completedPass=nil;R.cursor=nil
    R.objects=setmetatable({}, {__mode="k"})
    R.foods=setmetatable({}, {__mode="k"})
    R.observed=setmetatable({}, {__mode="k"})
    R.powerEdges=setmetatable({}, {__mode="k"})
    R.pendingLoads=setmetatable({}, {__mode="k"})
    R.squares=setmetatable({}, {__mode="k"})
end

local function guarded(callback)
    return function(...)
        local ok,errorText=pcall(callback,...)
        if not ok then
            -- Restore before failing closed, so no physical guard can survive.
            R.RestoreAll();R.ready=false;report(errorText)
        end
    end
end

Events.OnGameStart.Add(guarded(R.Start))
if Events.OnInitGlobalModData then Events.OnInitGlobalModData.Add(guarded(R.InstallLiveWire)) end
Events.OnTickEvenPaused.Add(guarded(R.PreTick))
Events.OnTick.Add(guarded(R.PostTick))
Events.OnPlayerUpdate.Add(guarded(R.RestoreAll))
Events.LoadGridsquare.Add(guarded(function(square) R.ScanSquare(square,true) end))
Events.OnSave.Add(guarded(R.Save))
Events.OnMainMenuEnter.Add(guarded(R.Stop))
if Events.OnObjectAdded then Events.OnObjectAdded.Add(guarded(function(object)
    if C.IsFridge(object) then C.RegisterObject(object) end
end)) end

return R
