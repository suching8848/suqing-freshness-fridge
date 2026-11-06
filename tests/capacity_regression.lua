local C=SuQingFreshnessFridge
local A=C.Capacity
local checks=0
local function check(value,message) checks=checks+1;assert(value,message) end
check(not A.Install() and not A.installed,"missing action queue does not partially install")
local pending={}
ISTimedActionQueue={add=function(action) table.insert(pending,action) end}
check(A.Install() and A.IsReady(),"all six methods and queue helper install atomically")
local wrapper=javaTransferItems
check(A.Install() and javaTransferItems==wrapper,"repeat installation does not stack")
local player=CAPACITY_Player()
local organized=CAPACITY_Player(CharacterTrait.ORGANIZED)
local disorganized=CAPACITY_Player(CharacterTrait.DISORGANIZED)
local object=CAPACITY_Object()
local target=object.container
check(target:getCapacity()==200 and target:getMaxWeight()==200,"capacity/maxWeight exceed native world 100")
check(target:getEffectiveCapacity(player)==200,"neutral effective capacity")
check(target:getEffectiveCapacity(organized)==260 and target:getEffectiveCapacity(disorganized)==140,"default native trait capacities")
for _,row in ipairs(CAPACITY_TRAIT_ORACLE) do
    check(A.AdjustedCapacity(row[1],organized)==row[2],"float32 organized oracle "..row[1])
    check(A.AdjustedCapacity(row[1],disorganized)==row[3],"float32 disorganized oracle "..row[1])
end
check(#CAPACITY_TRAIT_ORACLE==951,"all integer sandbox capacities checked")
target.baseWeight=150
check(target:getFreeCapacity(player)==50 and not target:isFull(player),"free/full use bridged effective capacity")
local item=CAPACITY_Item(player.inventory,1)
check(target:hasRoomFor(player,item) and target:hasRoomFor(item),"both item room overloads exceed 100")
check(target:hasRoomFor(player,50) and not target:hasRoomFor(player,50.01),"numeric capacity exact boundary")
check(target:hasRoomFor(player,50,-100),"batch drag overload preserves legitimate negative floor delta")
check(not target:hasRoomFor(player,1,0/0),"invalid floor delta rejected")
item.allowed=false;check(not target:hasRoomFor(player,item),"item acceptance filter preserved");item.allowed=true
item.recursive=true;check(not target:hasRoomFor(player,item),"recursive container placement rejected");item.recursive=nil
check(not target:hasRoomFor("not-a-character",item),"invalid character rejected")
check(not target:hasRoomFor(player,-1),"negative incoming weight rejected")
target.baseWeight=199.99
check(target:hasRoomFor(player,0.01),"native float32 addition accepts exact decimal capacity boundary")
check(not target:hasRoomFor(player,0.02),"native float32 addition still rejects actual decimal overflow")
check(not target:hasRoomFor(1),"one-argument overload requires an inventory item")
target.baseWeight=200
check(target:isFull(player) and target:getFreeCapacity(player)==0,"exact full boundary")
target.baseWeight=220
check(target:isFull(player) and not target:hasRoomFor(player,item),"capacity reduction blocks new input without deleting contents")
check(target:getFreeCapacity(organized)==40,"organized free capacity follows its own native bonus")
local vanilla=CAPACITY_Object("appliances_refrigeration_01_25").container
local cap,sentinel,argc=vanilla:getCapacity("untouched")
check(cap==100 and sentinel=="native" and argc==1,"ordinary fridge forwards exact arguments and returns")
local allowed,sentinel,argc=vanilla:hasRoomFor(player,5,-3)
check(allowed and sentinel=="native" and argc==3,"ordinary room overload forwards all arguments/returns")
local foreign=CAPACITY_Container("crate",{})
check(foreign:getCapacity()==100,"foreign furniture unchanged")
local detached=CAPACITY_Container("fridge",object)
check(detached:getCapacity()==100,"sprite parent alone is insufficient without container identity")
object.md[C.objectKey]={schema=99}
check(target:getCapacity()==100,"unsupported state schema uses original continuation")
object.md[C.objectKey]=nil
check(target:getCapacity()==200,"valid own state restored")
CAPACITY_MP=true
check(target:getCapacity()==100 and not A.IsReady(),"MP leaves native capacities")
CAPACITY_MP=false
check(A.IsReady(),"SP readiness returns without reinstall")

-- Real native UI Lua functions operate on mocks through the installed bridge.
local currentPlayer=player
getSpecificPlayer=function() return currentPlayer end
local loot={inventory=target,inventoryPane={selected={}}}
local inventoryUI={inventory=player.inventory,inventoryPane={selected={}}}
getPlayerLoot=function() return loot end
getPlayerInventory=function() return inventoryUI end
getPlayerHotbar=function() return {isInHotbar=function() return false end} end
local pane=setmetatable({player=0,inventory=player.inventory},{__index=ISInventoryPane})
target.baseWeight=150;target.items={};player.inventory.items={}
local dragItems={}
for index=1,60 do dragItems[index]=CAPACITY_Item(player.inventory,1) end
ISMouseDrag.dragging=dragItems
check(ISInventoryPane.canPutIn({player=0,inventory=target}),"actual inventory-pane drag acceptance above 100")
local dragging=setmetatable({inventoryPane=pane,items=dragItems,itemNotOK={},
    getDropContainer=function() return target,"button" end},{__index=DraggedItems})
dragging:update()
local fit=0
for _,v in ipairs(dragItems) do if not dragging.itemNotOK[v] then fit=fit+1 end end
check(fit==50,"actual multi-item drag preview allows exactly remaining capacity")

-- Actual transfer-all -> TransferUtil -> native timed-action constructor and
-- isValid -> actual vanilla remove/add. The surrounding game objects are mocks.
local function drainQueue()
    local moved=0
    for _,action in ipairs(pending) do
        if action:isValid() then
            ISTransferAction:transferItem(action.character,action.item,action.srcContainer,action.destContainer)
            moved=moved+1
        end
    end
    pending={}
    return moved
end
target.baseWeight=98;target.items={};player.inventory.items={}
for index=1,105 do CAPACITY_Item(player.inventory,1) end
pane:transferAll()
check(#pending==105,"actual transfer-all queues ordinary native actions")
check(drainQueue()==102 and target:getCapacityWeight()==200,"actual native action/transfer path fills beyond 100 to 200")
check(#player.inventory.items==3 and #target.items==102,"transfer-all neither loses nor duplicates items")
SandboxVars.SuQingFreshnessFridge.Capacity=1000
target.baseWeight=990;target.items={};player.inventory.items={}
for index=1,15 do CAPACITY_Item(player.inventory,1) end
pane:transferAll()
check(drainQueue()==10 and target:getCapacityWeight()==1000,"actual native path respects configurable 1000 boundary")
check(#player.inventory.items==5,"overflow remains in source")

SandboxVars.SuQingFreshnessFridge.Capacity=200
target.baseWeight=250;target.items={};organized.inventory.items={}
local queued=CAPACITY_Item(organized.inventory,1)
javaTransferItems(organized,queued,organized.inventory,target)
check(#pending==1,"javaTransferItems respects character organized capacity above base")
check(drainQueue()==1 and target:getCapacityWeight()==251,"queued helper uses normal native action and real Lua transfer")
target.baseWeight=260;target.items={};queued=CAPACITY_Item(organized.inventory,1)
javaTransferItems(organized,queued,organized.inventory,target)
check(#pending==0,"queue helper rejects organized overflow")
target.baseWeight=150;queued.actualWeight=51
javaTransferItems(organized,queued,organized.inventory,target)
check(#pending==1,"queue helper preserves actual-weight check with effective capacity")
pending={};queued.actualWeight=111
javaTransferItems(organized,queued,organized.inventory,target)
check(#pending==0,"queue helper rejects actual-weight overflow even if unequipped weight fits")
target.baseWeight=199.99000549316406
local fractional=CAPACITY_Item(player.inventory,0.009999999776482582)
javaTransferItems(player,fractional,player.inventory,target)
check(#pending==1,"queue helper accepts native 199.99f plus .01f exact capacity boundary")
pending={}
fractional.weight=0.019999999552965164
javaTransferItems(player,fractional,player.inventory,target)
check(#pending==0,"queue helper rejects native 199.99f plus .02f overflow")
local initialIndex=CAPACITY_INDEX.getCapacity
CAPACITY_INDEX.getCapacity=function() return 17 end
check(not A.IsReady() and not A.Install(),"foreign replacement prevents uncertain reinstallation")
check(target:getMaxWeight()==100,"partly replaced hook set cannot leave other capacity overlays active")
CAPACITY_INDEX.getCapacity=initialIndex
check(A.IsReady(),"restored original bridge is recognized")
return "CAPACITY_LUA assertions="..checks.." failures=0"
