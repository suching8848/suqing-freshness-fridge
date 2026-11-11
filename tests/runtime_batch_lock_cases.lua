-- Run after runtime_mock_bootstrap, fridge Core/Batch, fridge Lock and UI.
-- For the shared case, load lunchbox Core/Batch before fridge Lock and its
-- Lock after fridge Lock so the same world-start ordering is exercised.
local C=SuQingFreshnessFridge
local B=C.Batch
local L=C.Lock
local checks=0
local function check(condition,message)
    checks=checks+1
    assert(condition,message)
end

ArrayList={new=mockList}
local function forward() return true,"original" end
ISInventoryTransferAction={isValidStart=forward,isValid=forward,transferItem=forward}
ISDestroyStuffAction={isValid=forward,complete=forward}
ISEatFoodAction={isValidStart=forward,isValid=forward,complete=forward,eat=forward,getRequiredItem=forward}
ISAddItemInRecipe={isValid=forward,complete=forward}
ISCraftAction={isValid=forward,complete=forward}
ISHandcraftAction={isValid=forward,start=forward,performRecipe=forward}
ISInventoryPane={refreshContainer=function(pane) pane.refreshes=(pane.refreshes or 0)+1 end}
ISInventoryPage={
    GetFloorContainer=function() return Mock.container(nil,"floor") end,
    addContainerButton=function(page,container)
        local button={inventory=container}
        page.backpacks[#page.backpacks+1]=button
        return button
    end,
    refreshBackpacks=function(page) page.rebuilds=(page.rebuilds or 0)+1 end,
    selectContainer=function(page,button) page.inventoryPane.inventory=button.inventory end,
    selectButtonForContainer=function(page,container) page.inventoryPane.inventory=container end,
    setNewContainer=function(page,container) page.inventoryPane.inventory=container end,
}

local fridge=Mock.fridge()
local food=Mock.food(fridge.container,3)
local floor=Mock.container(nil,"floor")
local sources=ArrayList.new({floor,fridge.container})
ISInventoryPaneContextMenu={getContainers=function() return sources end}
local page=setmetatable({
    player=0,inventory=fridge.container,backpacks={},buttonPool={},
    containerButtonPanel={removeChild=function(panel) panel.removed=true end},
}, {__index=ISInventoryPage})
page.inventoryPane=setmetatable({inventoryPage=page,inventory=fridge.container,lastinventory=fridge.container},
    {__index=ISInventoryPane})
local player={messages=0,Say=function(self) self.messages=self.messages+1 end}
function getNumActivePlayers() return 1 end
function getPlayerInventory() return nil end
function getPlayerLoot() return page end
function getSpecificPlayer() return player end
function getText(key,value) return key..(value and "="..value or "") end
function getTextOrNull() return nil end

local starts=0
C.Runtime={
    CanStartBatch=function() return L.Ready() end,
    StartBatch=function(object) check(object==fridge,"context hands exact object to runtime");starts=starts+1;return true end,
}
local other=SuQingFreshnessLunchbox
if other then
    other.Runtime={CanStartBatch=function() return other.Lock.Ready() end}
end
emit("OnGameStart")
check(L.Ready(),"fridge lock ready")
check((L.SharedTransfer()~=nil)==(other~=nil),"shared transfer detected exactly when modern lunchbox is loaded")
if other then
    check(L.SharedTransferReady() and other.Lock.Ready(),"both mods retain one ready hook chain")
end

local context={addOption=function(self,label,target,action)
    self.option={label=label,target=target,action=action}
    return self.option
end}
emit("OnFillWorldObjectContextMenu",0,context,{fridge,fridge},false)
check(context.option.label=="IGUI_SuQingFreshnessFridge_SealBatch" and not context.option.notAvailable,"powered idle action available")
context.option.action(context.option.target)
check(starts==1,"manual start dispatches once")
check(ISInventoryTransferAction.isValid({srcContainer=fridge.container,destContainer=floor}),"idle fridge access preserved")
check(ISDestroyStuffAction.isValid({item=fridge}) and ISDestroyStuffAction.complete({item=fridge}),"idle fridge destruction preserved")

local state=C.State(fridge)
fridge.md[B.objectKey]={schema=1,id="test",phase="sealed",fridgeId=state.id,startedAt=100,
    hours=0.25,poweredHours=0.125,count=1,roster={}}
emit("OnFillWorldObjectContextMenu",0,context,{fridge},false)
check(context.option.notAvailable and context.option.label=="IGUI_SuQingFreshnessFridge_BatchRemaining=8",
    "sealed menu shows remaining powered minutes")
fridge.container.powered=false
emit("OnFillWorldObjectContextMenu",0,context,{fridge},false)
check(context.option.notAvailable and context.option.label=="IGUI_SuQingFreshnessFridge_BatchPaused=8","outage visibly pauses")
check(not ISInventoryTransferAction.isValidStart({srcContainer=fridge.container,destContainer=floor}),"take denied")
check(not ISInventoryTransferAction.isValid({srcContainer=floor,destContainer=fridge.container}),"insert denied")
check(not ISInventoryTransferAction.transferItem({srcContainer=fridge.container,destContainer=floor},food),"direct action denied")
check(not ISDestroyStuffAction.isValid({item=fridge}) and not ISDestroyStuffAction.complete({item=fridge}),"sealed fridge destruction denied at both boundaries")
check(ISDestroyStuffAction.isValid({item=floor}) and ISDestroyStuffAction.complete({item=floor}),"unrelated destruction preserved")
check(not ISEatFoodAction.complete({item=food}),"eat denied")
check(not ISAddItemInRecipe.complete({usedItem=food}),"ingredient denied")
check(not ISHandcraftAction.performRecipe({items=ArrayList.new({food})}),"queued handcraft denied")

L.Refresh()
check(page.inventoryPane.inventory~=fridge.container and page.inventoryPane.refreshes==1,"already open pane ejected")
local button=page:addContainerButton(fridge.container)
check(button and #page.backpacks==0 and page.containerButtonPanel.removed,"sealed source excluded from merged tabs")
check(not page:selectContainer(button) and not page:selectButtonForContainer(fridge.container),"stale selections denied")
local filtered=ISInventoryPaneContextMenu.getContainers()
check(filtered:size()==1 and filtered:get(0)==floor and sources:size()==2,"craft sources filtered without mutating callers")
page.inventoryPane.inventory=Mock.container(nil,"proxInv")
L.Refresh()
check(page.rebuilds==1,"selected merged view rebuilt at boundary")

if other then
    local lunchbox={kind="InventoryContainer",md={}}
    function lunchbox:getFullType() return other.FullType end
    function lunchbox:getModData() return self.md end
    local inner=Mock.container()
    inner.bag=lunchbox
    function lunchbox:getInventory() return inner end
    lunchbox.md[other.Batch.boxKey]={}
    check(other.Batch.IsLockedContainer(fridge.container) and other.Batch.IsLockedContainer(inner),"shared transfer sees both locked types")
    check(not ISInventoryTransferAction.isValid({srcContainer=inner,destContainer=floor}),"lunchbox remains independently locked")
    check(L.Ready() and other.Lock.Ready(),"neither mod invalidates the other's wrappers")
    local plain,orphan,parked=Mock.food(floor),Mock.food(floor),Mock.food(inner)
    orphan.md[B.foodKey]={}
    parked.md[B.foodKey]={}
    local loaded,probes,recoveries=false,0,0
    C.Runtime.IsFoodLoaded=function() probes=probes+1;return loaded end
    local priorRecover=B.RecoverFood
    B.RecoverFood=function(item,confirmed)
        check(item==orphan and confirmed==true,"only loaded orphan dispatched to fridge recovery")
        recoveries=recoveries+1
    end
    other.Batch.RecoverFood(plain)
    other.Batch.RecoverFood(parked)
    check(probes==0,"ordinary or sealed food skips the ownership probe")
    other.Batch.RecoverFood(orphan)
    check(probes==1 and recoveries==0,"unloaded orphan untouched")
    loaded=true
    local result,reason=other.Batch.RecoverFood(orphan)
    check(probes==2 and recoveries==1 and result==false and reason=="not_guarded","fridge recovery preserves lunchbox return values")
    B.RecoverFood=priorRecover
end

fridge.md[B.objectKey]=nil
check(ISInventoryTransferAction.isValid({srcContainer=fridge.container,destContainer=floor}),"release restores access")
check(page:addContainerButton(fridge.container) and #page.backpacks==1,"released fridge tab restored")
check(ISDestroyStuffAction.complete({item=fridge}),"released fridge destruction restored")
local destroy=ISDestroyStuffAction.complete
ISDestroyStuffAction.complete=forward
check(not L.Ready() and not L.SharedTransferReady(),"replaced destruction hook prevents sealing")
ISDestroyStuffAction.complete=destroy
print("FRIDGE_BATCH_LOCK checks="..checks.." shared="..tostring(other~=nil).." PASS")
