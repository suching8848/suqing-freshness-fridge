local C=SuQingFreshnessFridge
local A=C.Capacity
local container=ProbeFridge
local assertions=0
local function check(value,label)
    assertions=assertions+1
    assert(value,label)
end
check(A.Install(),"native Lua capacity hooks installed")
check(A.IsReady(),"native Lua capacity hooks match their registration")
check(C.IsFridge(ProbeObject),"real IsoObject recognized through its independent sprite")
check(C.Container(ProbeObject)==container,"real IsoObject contains the exact native fridge container")
check(container:getCapacityWeight()==101,"native contents actually weigh 101")
check(A.originals.getCapacity(container)==100,"raw Java getter remains bounded and was not globally patched")
check(container:getCapacity()==200,"normal Lua/UI getter exposes base200")
check(container:getEffectiveCapacity(nil)==200,"normal Lua/UI effective getter exposes base200")
check(container:getMaxWeight()==200,"normal Lua/UI max-weight getter exposes base200")
check(container:getFreeCapacity(nil)==99,"native contents weight participates in correct free capacity")
check(not container:isFull(nil),"native contents above100 remain usable at base200")
check(container:hasRoomFor(nil,99),"numeric room accepts exact boundary at200")
check(not container:hasRoomFor(nil,100),"numeric room rejects above200")
check(container:hasRoomFor(ProbeIncoming),"item room accepts 5kg above the raw Java100 limit")

SandboxVars.SuQingFreshnessFridge.Capacity=50
check(container:getCapacity()==50,"lower sandbox capacity applies")
check(container:isFull(nil),"lowering below existing contents blocks new additions")
check(container:getItems():size()==101,"lowering capacity does not delete existing contents")
check(not container:hasRoomFor(ProbeIncoming),"lowered full container rejects a new item")
SandboxVars.SuQingFreshnessFridge.Capacity=1000
check(container:getCapacity()==1000,"upper sandbox capacity applies")
check(container:getFreeCapacity(nil)==899,"upper capacity uses actual native contents")
check(container:hasRoomFor(nil,899),"numeric exact boundary at1000 accepted")
check(not container:hasRoomFor(nil,900),"above1000 rejected")

javaTransferItems(ProbeCharacter,ProbeIncoming,ProbeSource,container)
check(#NativeCapacityQueue==1,"normal queue bridge accepts a genuine native item above100")
local queued=NativeCapacityQueue[1]
check(queued.item==ProbeIncoming and queued.source==ProbeSource and queued.destination==container,"queue identity and endpoints preserved")
container:AddItem(queued.item)
check(not ProbeSource:contains(ProbeIncoming),"native AddItem removes incoming item from original source")
check(container:contains(ProbeIncoming),"native AddItem stores incoming item in target")
check(container:getCapacityWeight()==106,"real native contents now weigh106")
check(container:getItems():size()==102,"all actual native items remain present")

check(ProbeOtherFridge:getCapacity()==100,"ordinary fridge keeps the native getter")
check(not ProbeOtherFridge:hasRoomFor(nil,101),"ordinary fridge keeps native room limit")
local old=C.State(ProbeObject)
ProbeObject:getModData()[C.objectKey]={schema=9,on=true,id="future"}
check(container:getCapacity()==100,"unknown future state does not acquire custom capacity")
check(ProbeObject:getModData()[C.objectKey].schema==9,"unknown future state is not overwritten")
ProbeObject:getModData()[C.objectKey]=old

SandboxVars.SuQingFreshnessFridge.Capacity=200
local first=container:getItems():get(0)
local originalWeight=first:getActualWeight()
first:setActualWeight(94.99)
check(math.abs(container:getCapacityWeight()-199.99)<0.0001,"real native contents represent the 199.99 float32 boundary")
check(container:hasRoomFor(nil,0.01),"native float32 199.99 + .01 exact-capacity boundary is accepted")
check(not container:hasRoomFor(nil,0.02),"native float32 boundary rejects .02 beyond200")
check(math.abs(container:getFreeCapacity(nil)-0.0099945068359375)<0.00000001,"free-capacity subtraction matches the native float32 result")
first:setActualWeight(originalWeight)
check(container:getCapacityWeight()==106,"boundary test restores original native contents weight")

return "NATIVE_CAPACITY_BRIDGE cases=6 assertions="..assertions.." failures=0; real ItemContainer/contents/AddItem PASS; queue shell simulated"
