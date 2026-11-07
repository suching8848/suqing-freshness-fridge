local C=SuQingFreshnessFridge
local A=C.Capacity
local B=C.Building
local R=C.Runtime
local T=CapacityRefreshAudit
local object,container=ProbeObject,ProbeFridge
local cases,assertions=0,0
local function check(value,label) assertions=assertions+1;assert(value,label or "capacity refresh") end
local function eq(actual,expected,label) check(actual==expected,(label or "equal").." / "..tostring(actual).." vs "..tostring(expected)) end
local function test(name,fn) cases=cases+1;fn();print("CAPACITY_REFRESH_CASE "..name.." PASS") end
check(type(C.ResetCapacityCache)=="function","required production reset ABI")
check(A.Install() and A.IsReady(),"real native/UI capacity overlay installed")
local items=container:getItems();local saved={}
for n=0,items:size()-1 do saved[n+1]=items:get(n) end
local age,heat,last=ProbeFood:getAge(),ProbeFood:getHeat(),ProbeFood:getLastAged()
local state=C.State(object);local stateId,stateOn=state.id,state.on
local foodData=ProbeFood:getModData();local foodRecord=foodData[C.foodKey]
test("10000 stable refreshes write native setter once despite getter100",function()
    C.ResetCapacityCache();T.clearCounts();SandboxVars.SuQingFreshnessFridge.Capacity=200
    for n=1,10000 do check(C.RefreshCapacity(object),"stable refresh") end
    eq(T.calls,1);eq(T.targets[1],200)
    eq(A.originals.getCapacity(container),100,"real native furniture getter clamps to100")
    eq(ProbeRawCapacity(container),200,"read-only reflection sees the actual serialized physical target")
    eq(container.capacity,nil,"physical capacity is not exposed as a Lua field")
    eq(container:getCapacity(),200,"effective Lua/UI capacity remains200")
end)
test("mixed EnsureObject and Refresh share exactly one successful memo",function()
    C.ResetCapacityCache();T.clearCounts()
    for n=1,10000 do
        local ok,result=B.EnsureObject(object);check(ok and result==container,"real Building keeps same container")
        check(C.RefreshCapacity(object),"mixed direct refresh")
    end
    eq(T.calls,1,"10000 pairs share one setter write")
    eq(object:getContainer(),container);eq(container:getParent(),object)
    eq(container:getCapacity(),200)
end)
test("a Live Wire equipment cut retains building identity and real capacity",function()
    local data=object:getModData()
    local circuit={v=1,kind="fridge",cut=true,types={["0"]="fridge"}}
    LiveWire={VERSION="1.7.2",Appliances={
        saved=function(target) return target:getModData().LiveWireCircuit end,
        blocked=function(target) return target:getModData().LiveWireCircuit==circuit end,
    }}
    data.LiveWireCircuit=circuit
    container:setType("none")
    check(not container:isFridge(),"physical fridge remains disabled")
    eq(C.Container(object),container,"validated original type keeps the same ItemContainer")
    eq(container:getCapacity(),200,"capacity overlay stays active while refrigeration is cut")
    eq(A.originals.getCapacity(container),100,"native furniture clamp remains active")
    check(not C.Powered(object,container),"freshness cannot run in the cut state")
    T.clearCounts();T.nativeSetter(container,80)
    local ok,result=B.EnsureObject(object,true)
    check(ok and result==container,"Building accepts a loaded, cut fridge without rebuilding")
    eq(T.calls,1);eq(ProbeRawCapacity(container),200,"forced load rewrites the actual configured capacity")
    eq(container:getType(),"none");eq(object:getContainer(),container)
    eq(data.LiveWireCircuit,circuit,"the Live Wire receipt is not overwritten")
    eq(items:size(),#saved)
    for n=0,items:size()-1 do eq(items:get(n),saved[n+1],"item identity preserved through cut load") end
    container:setType("fridge");data.LiveWireCircuit=nil;LiveWire=nil
    eq(object:getContainer(),container);eq(container:getCapacity(),200)
end)
test("targets50 100 200 1000 each rewrite once and retain effective capacity",function()
    C.ResetCapacityCache();T.clearCounts()
    for _,target in ipairs({50,100,200,1000}) do
        SandboxVars.SuQingFreshnessFridge.Capacity=target
        local previous=T.calls
        for n=1,100 do check(C.RefreshCapacity(object)) end
        eq(T.calls,previous+1);eq(T.targets[T.calls],target)
        eq(A.originals.getCapacity(container),math.min(target,100));eq(container:getCapacity(),target)
        eq(ProbeRawCapacity(container),target)
    end
    eq(T.calls,4)
end)
test("replacement genuine container receives its own first write",function()
    SandboxVars.SuQingFreshnessFridge.Capacity=200;C.ResetCapacityCache();C.RefreshCapacity(object)
    local replacement=ProbeOtherFridge;local parent=replacement:getParent()
    object:setContainer(replacement);replacement:setParent(object)
    T.clearCounts();check(C.RefreshCapacity(object));check(C.RefreshCapacity(object))
    eq(T.calls,1);eq(object:getContainer(),replacement);eq(replacement:getCapacity(),200)
    object:setContainer(container);container:setParent(object);replacement:setParent(parent)
    C.ResetCapacityCache()
end)
test("throw before setter does not cache and next refresh retries",function()
    C.ResetCapacityCache();T.clearCounts();T.failBefore=true
    local ok,message=pcall(C.RefreshCapacity,object)
    eq(ok,false);check(string.find(tostring(message),"before sentinel",1,true)~=nil)
    eq(T.calls,1);check(C.RefreshCapacity(object));eq(T.calls,2)
    check(C.RefreshCapacity(object));eq(T.calls,2)
end)
test("throw after setter also retries rather than claiming completion",function()
    C.ResetCapacityCache();T.clearCounts();T.failAfter=true
    local ok,message=pcall(C.RefreshCapacity,object)
    eq(ok,false);check(string.find(tostring(message),"after sentinel",1,true)~=nil)
    eq(T.calls,1);check(C.RefreshCapacity(object));eq(T.calls,2)
    check(C.RefreshCapacity(object));eq(T.calls,2)
end)
test("explicit reset and force each cause exactly one physical write",function()
    C.ResetCapacityCache();T.clearCounts();C.RefreshCapacity(object);eq(T.calls,1)
    check(C.RefreshCapacity(object,true));eq(T.calls,2)
    check(C.RefreshCapacity(object));eq(T.calls,2)
    C.ResetCapacityCache();check(C.RefreshCapacity(object));eq(T.calls,3)
end)
test("forced same-target failure clears the earlier success memo",function()
    C.ResetCapacityCache();C.RefreshCapacity(object);T.clearCounts();T.failBefore=true
    eq(pcall(C.RefreshCapacity,object,true),false);eq(T.calls,1)
    check(C.RefreshCapacity(object));eq(T.calls,2)
    check(C.RefreshCapacity(object));eq(T.calls,2)
end)
test("setter identity replacement rewrites once and deletion cannot skip",function()
    C.ResetCapacityCache();C.RefreshCapacity(object);T.clearCounts()
    local prior=T.index.setCapacity
    T.index.setCapacity=function(...) return prior(...) end
    check(C.RefreshCapacity(object));eq(T.calls,1)
    check(C.RefreshCapacity(object));eq(T.calls,1)
    T.index.setCapacity=nil
    local ok=pcall(C.RefreshCapacity,object);eq(ok,false,"missing setter is never cached success")
    T.index.setCapacity=prior
    check(C.RefreshCapacity(object));eq(T.calls,2,"deleted setter failure remains retryable")
end)
test("Runtime Start resets before pending-object registration",function()
    R.Stop();C.RefreshCapacity(object)
    C.pending[object]=true;T.clearCounts();R.Start()
    check(R.ready);eq(T.calls,1,"startup pending registration rewrites once after reset")
    check(C.RefreshCapacity(object));eq(T.calls,1)
end)
test("Runtime Stop resets even before a restoration error",function()
    local restore=R.RestoreAll
    R.RestoreAll=function() error("restore sentinel",0) end
    local ok=pcall(R.Stop);R.RestoreAll=restore;eq(ok,false)
    T.clearCounts();check(C.RefreshCapacity(object));eq(T.calls,1,"Stop reset happened first")
    R.Stop();R.Start();T.clearCounts();check(C.RefreshCapacity(object));eq(T.calls,1)
end)
test("freshness master switch retains the200 capacity overlay",function()
    C.ResetCapacityCache();C.RefreshCapacity(object);T.clearCounts()
    SandboxVars.SuQingFreshnessFridge.Enabled=false
    check(C.RefreshCapacity(object));eq(container:getCapacity(),200);eq(T.calls,0)
    SandboxVars.SuQingFreshnessFridge.Enabled=true
    check(C.RefreshCapacity(object));eq(container:getCapacity(),200);eq(T.calls,0)
end)
test("each Save forces one write and repairs opaque external physical edits",function()
    R.Stop();R.Start();C.ResetCapacityCache();C.RefreshCapacity(object)
    local isLoaded=R.IsLoaded;R.IsLoaded=function(o) return o==object end
    R.objects[object]=true
    T.nativeSetter(container,80)
    T.clearCounts();check(C.RefreshCapacity(object));eq(T.calls,0)
    eq(ProbeRawCapacity(container),80,"opaque Java physical edit is not claimed to be polled")
    eq(container:getCapacity(),200,"effective overlay stays200")
    T.nativeSetter(container,350);eq(ProbeRawCapacity(container),350)
    T.clearCounts()
    for n=1,3 do
        local prior=T.calls;R.Save();eq(T.calls,prior+1,"Save exactly one forced write")
        eq(T.targets[T.calls],200);eq(container:getCapacity(),200)
        eq(ProbeRawCapacity(container),200,"Save restores physical serialization target")
        check(C.RefreshCapacity(object));eq(T.calls,prior+1,"normal refresh after Save is deduplicated")
    end
    R.objects[object]=nil;R.IsLoaded=isLoaded
end)
test("create placement and grid callbacks force one write without a register duplicate",function()
    C.ResetCapacityCache();C.RefreshCapacity(object)
    local isLoaded=R.IsLoaded;R.IsLoaded=function(o) return o==object end
    T.clearCounts();B.OnCreate({thumpable=object});eq(T.calls,1)
    T.clearCounts();B.OnObjectAdded(object);eq(T.calls,1)
    local square={getObjects=function() return {size=function() return 1 end,get=function() return object end} end}
    T.nativeSetter(container,300);T.clearCounts();B.OnLoadSquare(square)
    eq(T.calls,1);eq(ProbeRawCapacity(container),200)
    R.objects[object]=nil;R.IsLoaded=isLoaded
end)
test("Building propagates an explicit failed shared refresh",function()
    local refresh=C.RefreshCapacity;C.RefreshCapacity=function() return false end
    local ok,reason=B.EnsureObject(object);C.RefreshCapacity=refresh
    eq(ok,false);eq(reason,"capacity_refresh_failed")
end)
test("contents age state and schema are preserved",function()
    eq(object:getContainer(),container);eq(items:size(),#saved)
    for n=0,items:size()-1 do eq(items:get(n),saved[n+1],"same native contents identity") end
    eq(ProbeFood:getAge(),age);eq(ProbeFood:getHeat(),heat);eq(ProbeFood:getLastAged(),last)
    eq(ProbeFood:getModData(),foodData);eq(foodData[C.foodKey],foodRecord)
    eq(C.State(object),state);eq(state.id,stateId);eq(state.on,stateOn);eq(state.schema,1)
    eq(A.errors,0);check(A.IsReady())
end)
local summary="CAPACITY_REFRESH_NATIVE cases="..cases.." assertions="..assertions.." stable_writes=1 mixed_writes=1 failures=0"
print(summary)
return summary
