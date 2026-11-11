require "SuQingFreshnessFridge/Batch"
require "SuQingFreshnessFridge/Capacity"
require "TimedActions/ISTransferAction"
local C=SuQingFreshnessFridge
local B=C.Batch
C.Runtime=C.Runtime or {}
local R=C.Runtime
if R.loaded then return R end
R.loaded=true
R.objects={}
R.batches={}
R.observed={}
R.pendingLoads={}
R.squares={}
R.retry={}
R.stats={completed=0,errors=0}

local function now() return getGameTime():getWorldAgeHours() end
local function paused() return type(isGamePaused)=="function" and isGamePaused() end
local function report(errorText)
    R.stats.errors=R.stats.errors+1
    if R.stats.errors<=10 then print("[SuQingFreshnessFridge] "..tostring(errorText)) end
end

local function refreshAccess()
    if not C.Lock or not C.Lock.Refresh then return end
    local ok,message=pcall(C.Lock.Refresh)
    if not ok then report(message) end
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


function R.IsFoodLoaded(food)
    local lunch=SuQingFreshnessLunchbox and SuQingFreshnessLunchbox.Runtime
    if lunch and lunch.Location and lunch.Location(food) then return true end
    local container=food and food:getContainer()
    local parent=container and container:getParent()
    if not parent or not parent.getSquare then return false end
    local square,cell=parent:getSquare(),getCell()
    if not square or not cell or cell:getGridSquare(square:getX(),square:getY(),square:getZ())~=square then return false end
    if not container:getItems():contains(food) then return false end
    if instanceof(parent,"IsoGameCharacter") then return true end
    return square:getObjects():contains(parent)
end

function R.Register(object)
    if not C.IsFridge(object) then return false end
    if not R.ready then C.pending[object]=true;return true end
    local container=C.Container(object)
    if not container or not C.State(object) or not R.IsLoaded(object) then return false end
    C.pending[object]=nil
    if R.objects[object] then return true end
    R.objects[object]=true
    C.RefreshCapacity(object)
    if B.IsSealed(object) then
        R.batches[object]=true
    else
        -- Recover saved legacy shields once on discovery. A sealed batch's
        -- contents remain untouched until its completion or recovery.
        local items=container:getItems()
        for i=0,items:size()-1 do B.RecoverFood(items:get(i),true) end
    end
    return true
end

local function remove(object)
    R.objects[object]=nil;R.batches[object]=nil;R.observed[object]=nil
    R.pendingLoads[object]=nil;R.retry[object]=nil
end

local function attemptComplete(object,time)
    if R.retry[object] and time<R.retry[object] then return end
    local ok,reason=B.Complete(object,time)
    if ok or not B.IsSealed(object) then
        R.batches[object]=nil;R.observed[object]=nil;R.retry[object]=nil
        if ok then R.stats.completed=R.stats.completed+1 end
        refreshAccess()
    elseif reason~="not_due" and reason~="unpowered" then
        R.retry[object]=time+0.05
        report("batch completion deferred: "..tostring(reason))
    end
end

local function observeBatches(time,allowCredit)
    if not R.operational then return end
    for object in pairs(R.batches) do
        if not R.IsLoaded(object) then
            remove(object)
        elseif waitingForReplay(object) then
            R.observed[object]=nil
        else
            local batch=B.Get(object)
            if type(batch)~="table" then
                R.batches[object]=nil;R.observed[object]=nil
            else
                local powered=C.Powered(object,C.Container(object))
                local previous=R.observed[object]
                R.observed[object]=powered and time or nil
                if allowCredit and powered and previous and time>previous and time-previous<=C.maxObservedGapHours then
                    B.Advance(object,time-previous)
                end
                if batch.phase=="sealing" or batch.phase=="recovering" or batch.phase=="finishing"
                    or (powered and C.Finite(batch.poweredHours) and C.Finite(batch.hours) and batch.poweredHours>=batch.hours) then
                    attemptComplete(object,time)
                end
            end
        end
    end
end

function R.PreTick()
    if not R.ready then return end
    for square in pairs(R.squares) do R.ScanSquare(square);R.squares[square]=nil end
    for object in pairs(C.pending) do R.Register(object) end
    for object in pairs(R.objects) do
        if R.IsLoaded(object) then C.RefreshCapacity(object) else remove(object) end
    end
    observeBatches(now(),not paused())
end
R.Tick=R.PreTick

local function pack(...) return {n=select("#",...),...} end
function R.InstallTransferHook(captureStartup)
    if C.Lock and C.Lock.SharedTransfer and C.Lock.SharedTransfer() then
        return C.Lock.SharedTransferReady()
    end
    if not ISTransferAction or type(ISTransferAction.transferItem)~="function" then return false end
    if R.transferWrapper and ISTransferAction.transferItem==R.transferWrapper then return true end
    local legacy=SuQingFreshnessLunchbox
    local transfer=legacy and legacy.version=="0.1.0-rc.8-perf.9.1" and legacy.Runtime and legacy.Runtime.transfer
    if R.transferWrapper and transfer and transfer.prior==R.transferWrapper
        and transfer.wrapper==ISTransferAction.transferItem then return true end
    if R.transferWrapper and not captureStartup then return false end
    local prior=ISTransferAction.transferItem
    local wrapper
    wrapper=function(self,character,item,source,destination,...)
        if R.transferWrapper~=wrapper or not C.SP() then return prior(self,character,item,source,destination,...) end
        if B.IsLockedContainer(source) or B.IsLockedContainer(destination) then return item end
        if R.ready and C.IsFood(item) then B.RecoverFood(item,R.IsFoodLoaded(item)) end
        if B.IsSealedFood(item) then return item end
        local result=pack(prior(self,character,item,source,destination,...))
        return unpack(result,1,result.n)
    end
    R.transferWrapper=wrapper
    ISTransferAction.transferItem=wrapper
    return true
end

function R.CanStartBatch()
    if not R.ready or not C.Lock or not C.Lock.Ready then return false end
    local shared=C.Lock.SharedTransfer and C.Lock.SharedTransfer()
    if shared and shared.CanStartBatch and not shared.CanStartBatch() then return false end
    if not R.operational or not C.Lock.Ready() then return false end
    return R.InstallTransferHook()
end

function R.StartBatch(object)
    if not R.CanStartBatch() then return false,"lock_unavailable" end
    if not R.Register(object) then return false,"invalid_box" end
    if waitingForReplay(object) then return false,"unpowered" end
    local time=now()
    local ok,reason=B.Start(object,time)
    if B.IsSealed(object) then
        R.batches[object]=true
        if ok then R.observed[object]=time end
        refreshAccess()
    end
    return ok,reason
end

function R.PostTick()
    if not R.ready then return end
    if not R.operational then
        R.startupTicks=R.startupTicks+1
        if R.startupTicks<2 or not R.InstallTransferHook(true) then return end
        R.operational=true
    end
    observeBatches(now(),true)
end

local function preparePowerBoundary(object)
    R.observed[object]=nil
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
            if chunk then R.pendingLoads[object]=chunk;R.observed[object]=nil end
            if R.ready then
                if C.Building and C.Building.EnsureObject then C.Building.EnsureObject(object) end
                R.Register(object)
            end
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
    R.InstallLiveWire()
    R.ready=true;R.operational=false;R.startupTicks=0
    C.ResetCapacityCache()
    for square in pairs(R.squares) do R.ScanSquare(square);R.squares[square]=nil end
    for object in pairs(C.pending) do R.Register(object) end
    print("[SuQingFreshnessFridge] "..C.version.." single-player ready; sealed powered batches")
end

function R.Save()
    if not R.ready then return end
    observeBatches(now(),false)
    -- Preserve the physical capacity field for ItemContainer.save.
    for object in pairs(R.objects) do
        if R.IsLoaded(object) then C.RefreshCapacity(object,true) end
    end
end

function R.Stop()
    C.ResetCapacityCache()
    R.ready=false;R.operational=false;R.startupTicks=0
    R.objects={};R.batches={};R.observed={};R.pendingLoads={};R.squares={};R.retry={}
end

local function guarded(callback)
    return function(...)
        local ok,message=pcall(callback,...)
        if not ok then
            R.ready=false;R.operational=false
            report(message)
        end
    end
end

Events.OnGameStart.Add(guarded(R.Start))
if Events.OnInitGlobalModData then Events.OnInitGlobalModData.Add(guarded(R.InstallLiveWire)) end
Events.OnTickEvenPaused.Add(guarded(R.PreTick))
Events.OnTick.Add(guarded(R.PostTick))
Events.LoadGridsquare.Add(guarded(function(square) R.ScanSquare(square,true) end))
Events.OnSave.Add(guarded(R.Save))
Events.OnMainMenuEnter.Add(guarded(R.Stop))
if Events.OnObjectAdded then
    Events.OnObjectAdded.Add(guarded(function(object)
        if C.IsFridge(object) then C.RegisterObject(object) end
    end))
end

return R
