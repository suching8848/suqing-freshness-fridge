-- Exercise the selected upstream modules with the installed mod entry points.
local C=SuQingFreshnessFridge
local B,R=C.Batch,C.Runtime
local lw=LiveWire
local appliances,anchor,catchup=lw.Appliances,lw.Anchor,lw.FridgeCatchup
local count=0

local function check(value,message)
    count=count+1
    if not value then error(message,0) end
end

local function near(value,expected,message)
    check(math.abs(value-expected)<0.00001, message..": "..tostring(value).." ~= "..tostring(expected))
end

local function prepareBatch(object)
    local batch={schema=1,id="existing batch",fridgeId=C.State(object).id,roster={["1"]="Base.Apple"},
        count=1,startedAt=100,hours=1,poweredHours=0,phase="sealed"}
    object:getModData()[B.objectKey]=batch
    check(R.Register(object),"register pre-existing sealed batch")
    return batch
end

local function observe(time)
    Mock.clock=time
    R.PostTick()
end

local apply=appliances.apply
local set=anchor.set
local replay=catchup.onLoadChunk
local version=lw.VERSION
lw.VERSION="unsupported"
R.InstallLiveWire()
check(appliances.apply==apply and anchor.set==set and catchup.onLoadChunk==replay,"unknown release is untouched")
lw.VERSION=version

-- The optional shared appliances table can arrive before authority modules.
lw.Anchor=nil
lw.FridgeCatchup=nil
R.InstallLiveWire()
check(appliances.apply~=apply,"appliance hook installs with authority modules absent")
lw.Anchor=anchor
lw.FridgeCatchup=catchup
R.Start()
check(anchor.set~=set and catchup.onLoadChunk~=replay,"later startup installs anchor and replay hooks")
local installedApply,installedSet,installedReplay=appliances.apply,anchor.set,catchup.onLoadChunk
R.InstallLiveWire()
check(appliances.apply==installedApply and anchor.set==installedSet and catchup.onLoadChunk==installedReplay,
    "repeated lifecycle installation is idempotent")

local fridge=Mock.wireFridge()
local batch=prepareBatch(fridge)
local c=fridge:getContainer()
observe(100)
observe(100)
check(R.observed[fridge]==100 and C.Powered(fridge,c),"known power establishes the baseline")
Mock.clock=100.02
local saved=appliances.capture(fridge,{id="network"})
check(C.IsLiveWireFridgeRecord(saved),"actual circuit receipt retains fridge identity")
check(appliances.apply(fridge,saved,true) and c:getType()=="none","actual upstream service cut")
check(C.Container(fridge)==c and not C.Powered(fridge,c),"cut retains capacity and status container with power paused")
check(B.IsLockedContainer(c),"cut retains the sealed lock")
check(R.observed[fridge]==nil,"cut clears observed time immediately")
Mock.clock=100.07
appliances.restore(fridge)
check(c:getType()=="fridge" and C.Powered(fridge,c),"upstream restoration re-enables power")
observe(100.1)
near(batch.poweredHours,0,"no credit for the interval across a brief power loss")
observe(100.2)
near(batch.poweredHours,0.1,"next powered interval is credited")

local other=Mock.wireFridge()
prepareBatch(other)
observe(100.2)
local entry={x=fridge:getSquare():getX(),y=fridge:getSquare():getY(),z=0,on=true}
anchor.table()["network"]=entry
local coverage=lw.Coverage
if coverage then
    local extra=fridge:getSquare():getX()
    local provider={
        replacesDisc=true,
        covers=function(_,_,x,y,z) return x==extra and y==entry.y and z==entry.z end,
        bounds=function() return extra,entry.y,extra,entry.y end,
        positions=function() return {} end,
        scan=function() return nil end,
        step=function() return true,0 end,
        idsAt=function() return {} end,
    }
    check(coverage.register(provider),"actual 2.x coverage registration")
    entry.x=entry.x-4
    anchor.set("network",entry,true)
    check(R.observed[fridge]==nil and R.observed[other]==100.2,"first application invalidates only extra coverage")
    observe(100.3)
    anchor.set("network",entry,true)
    check(R.observed[fridge]==100.3,"repeated anchor application keeps the interval")
    anchor.set("network",entry,false)
    check(R.observed[fridge]==nil and R.observed[other]==100.3,"2.x anchor event sees provider coverage")
    anchor.set("network",entry,true)
    observe(100.4)
    anchor.reshape("network",function() extra=other:getSquare():getX() end)
    check(R.observed[fridge]==nil and R.observed[other]==nil,"reshape clears old and new coverage")
    anchor.reshape("network",function() extra=fridge:getSquare():getX() end)
else
    anchor.set("network",entry,true)
    check(R.observed[fridge]==nil,"legacy disc hook observes first activation")
    observe(100.3)
    anchor.set("network",entry,false)
    check(R.observed[fridge]==nil,"legacy disc hook observes an outage")
end

local food=Mock.wireFood(c)
food:setLastAged(100)
lw.Registry.data.powerHistory["network"]={
    id="network",x=entry.x,y=entry.y,z=entry.z,log0=true,log={},panelLog={{t=102,off=true}},
}
local chunk=fridge:getChunk()
emit("LoadGridsquare",fridge:getSquare())
check(R.pendingLoads[fridge]==chunk,"split chunk lifecycle waits after LoadGridsquare")
local before=batch.poweredHours
observe(104)
check(R.observed[fridge]==nil and batch.poweredHours==before,"waiting replay accrues no progress")
check(food:getLastAged()==100,"waiting leaves the upstream aging marker untouched")
emit("LoadChunk",chunk)
check(R.pendingLoads[fridge]==nil and R.observed[fridge]==nil,"actual chunk sync releases the replay barrier")
check(food:getLastAged()==104,"actual upstream replay updates the aging marker")
near(food:getAge(),(2*0.2+2)/24,"actual upstream replay applies cold and warm intervals")
observe(104.1)
near(batch.poweredHours,before,"resuming creates a new observation")
observe(104.2)
near(batch.poweredHours,before+0.1,"resumed observation credits new powered time")

print("RUNTIME_FRIDGE_LIVEWIRE version="..version.." assertions="..count.." PASS")
