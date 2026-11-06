local C=SuQingFreshnessFridge
local R=C.Runtime
local assertions,cases,failures=0,0,0
local function check(value,label)
    assertions=assertions+1
    if not value then error(label or "assertion failed") end
end
local function equal(actual,expected,label)
    assertions=assertions+1
    if actual~=expected then error((label or "not equal")..": "..tostring(actual).." ~= "..tostring(expected)) end
end
local function near(actual,expected,label)
    assertions=assertions+1
    if math.abs(actual-expected)>0.00001 then error((label or "not near")..": "..tostring(actual).." ~= "..tostring(expected)) end
end
local function case(name,fn)
    cases=cases+1
    Mock.reset()
    local ok,why=pcall(fn)
    if not ok then failures=failures+1;print("FAIL "..name..": "..tostring(why)) end
end
local function setup(age,fresh,rotten)
    local object=Mock.fridge()
    local food=Mock.food(object.container,age,fresh,rotten)
    return object,food
end
local function settle(food,object,time,continuous,powered)
    Mock.clock=time
    return C.SettleFood(food,object,time,{continuous=continuous==true,powered=powered~=false})
end
local function prime(food,object)
    return settle(food,object,Mock.clock,false,true)
end

case("sandbox defaults and limits",function()
    local cfg=C.Config()
    equal(cfg.capacity,200);equal(cfg.restoreHours,10);check(cfg.enabled);check(cfg.allowRotten)
    SandboxVars.SuQingFreshnessFridge.Capacity=49;equal(C.Config().capacity,50)
    SandboxVars.SuQingFreshnessFridge.Capacity=1001;equal(C.Config().capacity,1000)
    SandboxVars.SuQingFreshnessFridge.Capacity=355.9;equal(C.Config().capacity,355)
    SandboxVars.SuQingFreshnessFridge.Capacity="600";equal(C.Config().capacity,200)
    SandboxVars.SuQingFreshnessFridge.Capacity=0/0;equal(C.Config().capacity,200)
end)

case("capacity changes preserve container and contents",function()
    local object,food=setup()
    local container=object.container
    SandboxVars.SuQingFreshnessFridge.Capacity=1000
    check(C.RefreshCapacity(object));equal(object.container,container);equal(container:getCapacity(),1000)
    equal(container.items:get(0),food)
    SandboxVars.SuQingFreshnessFridge.Capacity=50
    check(C.RefreshCapacity(object));equal(container:getCapacity(),50);equal(container.items:size(),1)
end)

case("only exact four independent sprites are recognized",function()
    for index=0,3 do check(C.IsFridge(Mock.fridge(C.spritePrefix..index))) end
    check(not C.IsFridge(Mock.fridge(C.spritePrefix..4)))
    check(not C.IsFridge(Mock.fridge("appliances_refrigeration_01_25")))
    check(not C.IsFridge({}))
end)

case("wrong container type and dual compartment are rejected",function()
    local object=Mock.fridge();object.container.type="freezer"
    equal(C.Container(object),nil)
    object.container.type="fridge";object.containerCount=2
    equal(C.Container(object),nil)
end)

case("future object schema is retained without migration",function()
    local object=Mock.fridge()
    local record={schema=99,on=true,id="future",other="keep"}
    object.md[C.objectKey]=record
    equal(C.State(object),nil);equal(object.md[C.objectKey],record)
    equal(record.schema,99);equal(record.other,"keep");check(not C.RegisterObject(object))
end)

case("object identity and per fridge switch persist",function()
    local object=Mock.fridge()
    local record=C.State(object);local id=record.id
    record.on=false
    equal(C.State(object).id,id);equal(C.State(object).on,false)
end)

case("observed restoration follows each food fresh period",function()
    local object,food=setup(6,5,10)
    prime(food,object)
    local result=settle(food,object,100.2,true)
    near(result.elapsed,0.2);near(food.age,5.9)
    local other=Mock.food(object.container,6,10,20)
    prime(other,object);settle(other,object,100.4,true)
    near(other.age,5.8)
end)

case("restoration stops at zero",function()
    local object,food=setup(0.02,5,10)
    prime(food,object);settle(food,object,100.2,true)
    near(food.age,0)
    settle(food,object,100.4,true);near(food.age,0)
end)

case("duplicate settlement at same time cannot add credit",function()
    local object,food=setup(6)
    prime(food,object);settle(food,object,100.2,true)
    local age=food.age
    for _=1,10 do settle(food,object,100.2,true) end
    near(food.age,age)
end)

case("existing rotten food recovers gradually without full reset",function()
    local object,food=setup(15)
    prime(food,object);settle(food,object,100.2,true)
    near(food.age,14.9);check(food:isRotten())
end)

case("burnt food remains unchanged",function()
    local object,food=setup(15);food.burnt=true;food.lastAged=92
    local result=prime(food,object)
    check(not result.active);near(food.age,15);equal(food.lastAged,92)
end)

case("fertilized eggs are excluded",function()
    local object,food=setup(15);food.fertilized=true;food.lastAged=92
    local result=prime(food,object)
    check(not result.active);near(food.age,15);equal(food.lastAged,92)
end)

case("invalid or infinite food thresholds are excluded",function()
    local object,food=setup()
    food.fresh=0;check(not prime(food,object).active)
    food.fresh=1000000000;check(not prime(food,object).active)
    food.fresh=5;food.rotten=2;check(not prime(food,object).active)
    food.rotten=10;food.age=0/0;check(not prime(food,object).active)
end)

case("rotten option rejects existing rotten food",function()
    local object,food=setup(15);food.lastAged=92
    SandboxVars.SuQingFreshnessFridge.AllowRotten=false
    local result=prime(food,object)
    check(not result.active);near(food.age,15);equal(food.lastAged,92)
end)

case("master disabled preserves native aging responsibility",function()
    local object,food=setup(6);food.lastAged=92
    SandboxVars.SuQingFreshnessFridge.Enabled=false
    local result=prime(food,object)
    check(not result.active);near(food.age,6);equal(food.lastAged,92);equal(food.nativeCalls,0)
end)

case("unpowered fridge does not write lastAged",function()
    local object,food=setup(6);food.lastAged=92
    local result=settle(food,object,100,false,false)
    check(not result.active);near(food.age,6);equal(food.lastAged,92)
end)

case("per fridge switch disables only its own effect",function()
    local first,a=setup(6)
    local second,b=setup(6)
    C.State(first).on=false
    prime(a,first);prime(b,second)
    settle(a,first,100.2,true);settle(b,second,100.2,true)
    near(a.age,6);near(b.age,5.9)
end)

case("food inside a bag in fridge is not direct food",function()
    local object=Mock.fridge()
    local bag={kind="InventoryContainer"}
    local pocket=Mock.container(nil,"bag");pocket.bag=bag
    object.container:AddItem(bag)
    local food=Mock.food(pocket,6)
    check(not C.IsDirectFood(food,object))
    local result=prime(food,object)
    check(not result.active);near(food.age,6);equal(food.md[C.foodKey],nil)
end)

case("ordinary fridge never acquires freshness behavior",function()
    local object=Mock.fridge("appliances_refrigeration_01_25")
    local food=Mock.food(object.container,6)
    check(not C.RegisterObject(object));check(not prime(food,object).active)
    near(food.age,6);equal(food.md[C.foodKey],nil)
end)

case("future food schema is retained untouched",function()
    local object,food=setup(6)
    local record={schema=7,age=900,shield={logicalAge=900},custom=true}
    food.md[C.foodKey]=record;food.lastAged=92
    local result=prime(food,object)
    equal(result.reason,"unknown_schema");equal(food.md[C.foodKey],record)
    near(food.age,6);equal(food.lastAged,92);equal(food.nativeCalls,0)
    C.ClearFood(food);equal(food.md[C.foodKey],record)
end)

case("copied metadata with new object id cannot grant credit",function()
    local object,food=setup(6)
    prime(food,object);food.id=food.id+999
    local result=settle(food,object,100.2,true)
    near(result.elapsed,0);check(food.age>=6)
end)

case("item transformation cannot inherit credit",function()
    local object,food=setup(6)
    prime(food,object);food.fullType="OtherMod.DifferentFood"
    local result=settle(food,object,100.2,true)
    near(result.elapsed,0);check(food.age>=6)
end)

case("cooking state change creates a new accounting baseline",function()
    local object,food=setup(6)
    prime(food,object);food.cooked=true
    local result=settle(food,object,100.2,true)
    near(result.elapsed,0);check(food.age>=6)
end)

case("direct transfer between fridges cannot reuse old credit",function()
    local first,food=setup(6);local second=Mock.fridge()
    prime(food,first)
    first.container:Remove(food);second.container:AddItem(food)
    local result=settle(food,second,100.2,true)
    near(result.elapsed,0);check(food.age>=6)
end)

case("changed restore rate is not retroactive",function()
    local object,food=setup(6)
    prime(food,object)
    SandboxVars.SuQingFreshnessFridge.RestoreHours=1
    local result=settle(food,object,100.2,true)
    near(result.elapsed,0);check(food.age>=6)
end)

case("time reversal cannot restore food",function()
    local object,food=setup(6)
    prime(food,object)
    local result=settle(food,object,99,true)
    near(result.elapsed,0);near(food.age,6)
end)

case("large clock jump applies native catchup without freshness credit",function()
    local object,food=setup(6)
    prime(food,object)
    local result=settle(food,object,124,true)
    near(result.elapsed,0);near(food.age,6.2);equal(food.lastAged,124)
end)

case("unobserved initial claim cannot erase normal aging",function()
    local object,food=setup(6);food.lastAged=76
    local result=prime(food,object)
    near(result.elapsed,0);near(food.age,6.2);equal(food.lastAged,100);equal(food.nativeCalls,1)
end)

case("catchup crossing rotten threshold respects rotten option",function()
    local object,food=setup(9.9);food.lastAged=76
    SandboxVars.SuQingFreshnessFridge.AllowRotten=false
    local result=prime(food,object)
    check(not result.active);near(food.age,10.1)
end)

case("physical shield preserves real rotten state after restore",function()
    local object,food=setup(15)
    prime(food,object);check(C.ProtectFood(food,object,100))
    check(food.age<food.rotten);check(food.md[C.foodKey].shield~=nil)
    local ok,reason=C.RestoreFood(food)
    check(ok);equal(reason,"restored");near(food.age,15);check(food:isRotten())
    equal(food.md[C.foodKey].shield,nil)
end)

case("shield identity mismatch never overwrites transformed item",function()
    local object,food=setup(15)
    prime(food,object);C.ProtectFood(food,object,100)
    food.id=food.id+999;food.age=3
    local ok,reason=C.RestoreFood(food)
    check(not ok);equal(reason,"identity_changed");near(food.age,3)
    equal(food.md[C.foodKey].shield,nil)
end)

case("shield does not erase another mod explicit age edit",function()
    local object,food=setup(15)
    prime(food,object);C.ProtectFood(food,object,100)
    food.age=2
    local ok,reason=C.RestoreFood(food)
    check(not ok);equal(reason,"external_age_edit");near(food.age,2)
end)

case("uncorrupted fresh or stale food does not need a shield",function()
    local object,food=setup(6)
    prime(food,object);check(not C.ProtectFood(food,object,100))
    near(food.age,6);equal(food.md[C.foodKey].shield,nil)
end)

case("returning freshness preserves portions nutrition and hazards",function()
    local object,food=setup(15)
    local originalMD={value="preserve"};food.md.OtherMod=originalMD
    prime(food,object);C.ProtectFood(food,object,100);C.RestoreFood(food)
    settle(food,object,100.2,true)
    equal(food.portion,0.4);equal(food.calories,123);equal(food.poison,9);check(food.tainted)
    equal(food.cooked,false);equal(food.burnt,false);equal(food.md.OtherMod,originalMD)
end)

case("runtime starts with anchor but no historical credit",function()
    local object,food=setup(6);food.lastAged=76
    Mock.start(object)
    check(R.ready);near(food.age,6.2);equal(object.container.capacity,200)
end)

case("runtime continuous frames restore normalized food age",function()
    local object,food=setup(6)
    Mock.start(object)
    for _=1,10 do Mock.step(0.1) end
    near(food.age,5.5);check(R.ready)
end)

case("native rot deletion model is prevented during protected pass",function()
    local object,food=setup(15)
    Mock.start(object)
    Mock.step(0.1,{removeRotten=true})
    check(not food.deleted);equal(food.container,object.container)
    near(food.age,14.95);check(food:isRotten())
end)

case("pause restores stale guard and never leaves an active guard",function()
    local object,food=setup(15)
    Mock.start(object);emit("OnTickEvenPaused")
    check(C.FoodRecord(food).shield~=nil)
    Mock.paused=true;emit("OnTickEvenPaused")
    near(food.age,15);equal(C.FoodRecord(food).shield,nil)
    for _=1,5 do emit("OnTickEvenPaused") end
    near(food.age,15)
end)

case("OnPlayerUpdate restores guard before player timed actions",function()
    local object,food=setup(15)
    Mock.start(object);emit("OnTickEvenPaused")
    check(not food:isRotten())
    emit("OnPlayerUpdate",{})
    check(food:isRotten());near(food.age,15);equal(C.FoodRecord(food).shield,nil)
end)

case("save restores actual food age before serialization",function()
    local object,food=setup(15)
    Mock.start(object);emit("OnTickEvenPaused")
    emit("OnSave")
    near(food.age,15);equal(C.FoodRecord(food).shield,nil)
end)

case("missing post tick is recovered before the next frame",function()
    local object,food=setup(15)
    Mock.start(object);Mock.step(0.1,{post=false,player=false})
    check(food.age<10)
    emit("OnTickEvenPaused");emit("OnPlayerUpdate",{})
    check(food.age>=15);equal(C.FoodRecord(food).shield,nil)
end)

case("main menu clears transient state and restores real age",function()
    local object,food=setup(15)
    Mock.start(object);emit("OnTickEvenPaused")
    emit("OnMainMenuEnter")
    check(not R.ready);near(food.age,15);equal(C.FoodRecord(food).shield,nil)
    local objectCount,observedCount=0,0
    for _ in pairs(R.objects) do objectCount=objectCount+1 end
    for _ in pairs(R.observed) do observedCount=observedCount+1 end
    equal(objectCount,0);equal(observedCount,0)
end)

case("unloaded object cannot gain remote freshness credit",function()
    local object,food=setup(6)
    Mock.start(object);Mock.step(0.1)
    local before=food.age
    Mock.unload(object);Mock.clock=Mock.clock+24;emit("OnTickEvenPaused");emit("OnTick")
    equal(R.foods[food],nil);equal(R.objects[object],nil);near(food.age,before)
    Mock.reload(object);emit("LoadGridsquare",object.square);emit("OnTickEvenPaused");emit("OnTick")
    check(food.age>=before);check(food.nativeCalls>=2)
end)

case("foreign direct move is released at next pre frame",function()
    local object,food=setup(15)
    local outside=Mock.container(nil,"inventory")
    Mock.start(object);emit("OnTickEvenPaused")
    object.container:Remove(food);outside:AddItem(food)
    emit("OnTickEvenPaused")
    near(food.age,15);equal(food.md[C.foodKey],nil);equal(R.foods[food],nil)
end)

case("native transfer hook restores guard before leaving fridge",function()
    local object,food=setup(15);local outside=Mock.container(nil,"inventory")
    Mock.start(object);emit("OnTickEvenPaused")
    local result=ISTransferAction.transferItem({},nil,food,object.container,outside)
    equal(result,food);equal(food.container,outside);near(food.age,15)
    equal(food.md[C.foodKey],nil);equal(R.foods[food],nil)
end)

case("transferring to another fridge establishes a fresh baseline",function()
    local first,food=setup(6);local second=Mock.fridge()
    Mock.start(first);C.RegisterObject(second)
    Mock.step(0.1)
    local before=food.age
    ISTransferAction.transferItem({},nil,food,first.container,second.container)
    equal(food.container,second.container);near(food.age,before)
    equal(C.FoodRecord(food).fridgeId,C.State(second).id)
    Mock.step(0.1);near(food.age,before-0.05)
end)

case("transfer failure after mutation cannot retain a shield",function()
    local object,food=setup(15);local outside=Mock.container(nil,"inventory")
    Mock.start(object);emit("OnTickEvenPaused")
    local ok=pcall(ISTransferAction.transferItem,{failAfter=true},nil,food,object.container,outside)
    check(not ok);equal(food.container,outside);near(food.age,15)
    emit("OnTickEvenPaused")
    equal(food.md[C.foodKey],nil);equal(R.foods[food],nil)
end)

case("toggle restores shield and changes only one object",function()
    local object,food=setup(15);local other=Mock.fridge()
    Mock.start(object);C.RegisterObject(other);emit("OnTickEvenPaused")
    R.Toggle(object)
    near(food.age,15);check(not C.State(object).on);check(C.State(other).on)
    check(not C.FoodRecord(food).active);equal(C.FoodRecord(food).shield,nil)
end)

case("power interruption earns no credit until reanchored",function()
    local object,food=setup(6)
    Mock.start(object);Mock.step(0.1)
    local before=food.age
    object.container.powered=false;Mock.step(0.1)
    check(food.age>=before)
    object.container.powered=true;Mock.step(0.1)
    check(food.age>=before-0.05)
    local restoredStart=food.age;Mock.step(0.1)
    near(food.age,restoredStart-0.05)
end)

case("guarded exception restores all shields and fails closed",function()
    local object,food=setup(15)
    Mock.start(object);emit("OnTickEvenPaused")
    object.container.getItems=function() error("injected container enumeration error") end
    emit("OnTickEvenPaused")
    check(not R.ready);near(food.age,15);equal(C.FoodRecord(food).shield,nil)
end)

case("prestart loaded square queue discovers fridge",function()
    local object,food=setup(6)
    emit("LoadGridsquare",object.square)
    emit("OnGameStart")
    check(R.ready);check(R.objects[object]);equal(R.foods[food],object)
end)

case("persisted interrupted guard is restored at startup",function()
    local object,food=setup(15)
    prime(food,object);C.ProtectFood(food,object,100)
    R.Stop()
    -- Simulate a serialized object carrying its recovery receipt, without using a save file.
    C.FoodRecord(food).shield={id=tostring(food.id),fullType=food.fullType,logicalAge=15,physicalAge=9.999,time=100}
    food.age=9.999
    Mock.start(object)
    near(food.age,15);equal(C.FoodRecord(food).shield,nil)
end)

case("new session cannot trust old timestamps for credit",function()
    local object,food=setup(6)
    Mock.start(object);Mock.step(0.1)
    local before=food.age
    R.Stop();Mock.clock=Mock.clock+24
    Mock.start(object)
    check(food.age>=before);near(food.age,before+0.2)
end)

case("runtime clock discontinuity cannot award huge credit",function()
    local object,food=setup(6)
    Mock.start(object);Mock.step(24)
    check(food.age>=6);check(food.age<7)
end)

case("sub float32 ULP restoration accumulates on very old food",function()
    local object,food=setup(100000)
    food.float32=true
    prime(food,object)
    for pass=1,3600 do settle(food,object,100+pass/3600,true) end
    near(food.age,99999.5)
    near(C.FoodRecord(food).logicalAge,99999.5)
end)

case("float32 shield cycles preserve the fractional restoration ledger",function()
    local object,food=setup(100000)
    food.float32=true
    Mock.start(object)
    for _=1,360 do Mock.step(1/3600) end
    check(math.abs(food.age-99999.95)<0.005)
    check(math.abs(C.FoodRecord(food).logicalAge-99999.95)<0.0001)
end)

case("disabled native removal needs no age shield or replacement writes",function()
    SandboxVars.DaysForRottenFoodRemoval=-1
    local object,food=setup(15)
    prime(food,object)
    check(not C.ProtectFood(food,object,100));near(food.age,15);check(food:isRotten())
    equal(C.FoodRecord(food).shield,nil);equal(food:getReplaceOnRotten(),nil)
    food:setReplaceOnRotten("")
    check(not C.ProtectFood(food,object,100));near(food.age,15);check(food:isRotten())
end)

case("all visible frame phases keep rotten food rotten with removal disabled",function()
    SandboxVars.DaysForRottenFoodRemoval=-1
    local object,food=setup(15)
    Mock.start(object)
    for _=1,30 do
        emit("OnTickEvenPaused")
        check(food:isRotten());equal(C.FoodRecord(food).shield,nil)
        Mock.nativeAge(food)
        check(food:isRotten())
        Mock.clock=Mock.clock+1/3600
        emit("OnPlayerUpdate",{})
        check(food:isRotten())
        emit("OnTick")
        check(food:isRotten())
    end
    check(food.age<15);check(food.age>14)
end)

case("replacement-only guard keeps real age despite delayed callbacks",function()
    SandboxVars.DaysForRottenFoodRemoval=-1
    local object,food=setup(15)
    food:setReplaceOnRotten("RottenReplacement")
    Mock.start(object);emit("OnTickEvenPaused")
    near(food.age,15);check(food:isRotten());equal(food:getReplaceOnRotten(),"")
    equal(C.FoodRecord(food).shield.mode,"replacement")
    for _=1,8 do
        Mock.clock=Mock.clock+1/3600
        Mock.nativeAge(food)
        check(food:isRotten());equal(food:getReplaceOnRotten(),"")
    end
    local before=food.age
    emit("OnPlayerUpdate",{})
    near(food.age,before);equal(food:getReplaceOnRotten(),"RottenReplacement")
    equal(C.FoodRecord(food).shield,nil)
end)

case("external age edit cannot strand a replacement-only guard",function()
    SandboxVars.DaysForRottenFoodRemoval=-1
    local object,food=setup(15);food:setReplaceOnRotten("RottenReplacement")
    prime(food,object);check(C.ProtectFood(food,object,100))
    food:setAge(3)
    local ok,reason=C.RestoreFood(food)
    check(ok);equal(reason,"restored");near(food.age,3)
    equal(food:getReplaceOnRotten(),"RottenReplacement");equal(C.FoodRecord(food).shield,nil)
end)

case("external replacement edit is not overwritten",function()
    SandboxVars.DaysForRottenFoodRemoval=-1
    local object,food=setup(15);food:setReplaceOnRotten("OldReplacement")
    prime(food,object);check(C.ProtectFood(food,object,100))
    food:setReplaceOnRotten("OtherModReplacement")
    local ok,reason=C.RestoreFood(food)
    check(not ok);equal(reason,"external_replacement_edit")
    equal(food:getReplaceOnRotten(),"OtherModReplacement");near(food.age,15)
end)

case("replacement-only guard restores before save and transfer",function()
    SandboxVars.DaysForRottenFoodRemoval=-1
    local object,food=setup(15);food:setReplaceOnRotten("RottenReplacement")
    Mock.start(object);emit("OnTickEvenPaused");emit("OnSave")
    near(food.age,15);equal(food:getReplaceOnRotten(),"RottenReplacement")
    emit("OnTickEvenPaused")
    local outside=Mock.container(nil,"inventory")
    ISTransferAction.transferItem({},nil,food,object.container,outside)
    equal(food:getReplaceOnRotten(),"RottenReplacement");near(food.age,15)
    equal(C.FoodRecord(food),nil);equal(food.container,outside)
end)

case("replacement-only guard restores on toggle and power loss",function()
    SandboxVars.DaysForRottenFoodRemoval=-1
    local object,food=setup(15);food:setReplaceOnRotten("RottenReplacement")
    Mock.start(object);emit("OnTickEvenPaused");R.Toggle(object)
    equal(food:getReplaceOnRotten(),"RottenReplacement");near(food.age,15)
    check(not C.FoodRecord(food).active)
    R.Toggle(object);emit("OnTickEvenPaused")
    equal(food:getReplaceOnRotten(),"")
    object.container.powered=false;emit("OnTickEvenPaused")
    equal(food:getReplaceOnRotten(),"RottenReplacement");near(food.age,15)
    check(not C.FoodRecord(food).active)
end)

case("known enabled native removal retains existing protective path",function()
    SandboxVars.DaysForRottenFoodRemoval=0
    local object,food=setup(15)
    prime(food,object);check(C.ProtectFood(food,object,100))
    check(food.age<10);equal(C.FoodRecord(food).shield.mode,nil)
    check(C.RestoreFood(food));near(food.age,15)
end)

print("RUNTIME_MODEL cases="..cases.." assertions="..assertions.." failures="..failures)
if failures>0 then error("runtime regression failures: "..failures) end
return "RUNTIME_MODEL PASS"
