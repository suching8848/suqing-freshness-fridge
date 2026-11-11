-- Load the fridge model bootstrap followed by each mod's Core, Batch, Lock
-- and Runtime. This exercises the actual shared guard, with model UI classes.
local F, L = SuQingFreshnessFridge, SuQingFreshnessLunchbox
local assertions = 0
local function check(value, label)
    assertions = assertions + 1
    assert(value, label)
end
local function allowed() return true end

ArrayList = {new=function() return mockList() end}
ISInventoryTransferAction = {isValidStart=allowed, isValid=allowed, transferItem=allowed}
ISDestroyStuffAction = {isValid=allowed, complete=allowed}
ISEatFoodAction = {isValidStart=allowed, isValid=allowed, complete=allowed, eat=allowed}
ISAddItemInRecipe = {isValid=allowed, complete=allowed}
ISCraftAction = {isValid=allowed, complete=allowed}
ISHandcraftAction = {isValid=allowed, start=allowed, performRecipe=allowed}
ISInventoryPane = {refreshContainer=function(pane) pane.refreshes=(pane.refreshes or 0)+1 end}
local floor = Mock.container(nil, "floor")
ISInventoryPage = {
    GetFloorContainer=function() return floor end,
    addContainerButton=function(page, inventory)
        local button = {inventory=inventory}
        page.backpacks[#page.backpacks+1] = button
        return button
    end,
    selectContainer=function(page, button) page.inventoryPane.inventory=button.inventory end,
    setNewContainer=function(page, inventory) page.inventoryPane.inventory=inventory end,
    selectButtonForContainer=function(page, inventory) page.inventoryPane.inventory=inventory end,
}

local fridge = Mock.fridge()
local player = {kind="IsoGameCharacter", square=fridge.square}
player.inventory = Mock.container(player, "inventory")
function player:getInventory() return self.inventory end
function player:getSquare() return self.square end
function getNumActivePlayers() return 1 end
function getSpecificPlayer() return player end
function getPlayer() return player end

local box = {kind="InventoryContainer", md={}, id=900, fullType=L.FullType}
box.inventory = Mock.container(nil, "container")
box.inventory.bag = box
function box:getInventory() return self.inventory end
function box:getID() return self.id end
function box:getFullType() return self.fullType end
function box:getModData() return self.md end
function box:getContainer() return self.container end
function box:setCapacity(capacity) self.inventory.capacity=capacity end
player.inventory:AddItem(box)

local function foodIn(container)
    local food = Mock.food(container, 15, 5, 10)
    food.tainted = false
    food.cookable = true
    food.isTainted = function(self) return self.tainted end
    food.setOffAgeMax = function(self, value) self.rotten=value end
    food.isCookable = function(self) return self.cookable end
    food.setIsCookable = function(self, value) self.cookable=value end
    return food
end
local fridgeFood, boxFood = foodIn(fridge.container), foodIn(box.inventory)
local sources = mockList({player.inventory, fridge.container, box.inventory})
ISInventoryPaneContextMenu = {getContainers=function() return sources end}
local page = setmetatable({onCharacter=true, player=0, inventory=fridge.container,
    backpacks={}, buttonPool={}, containerButtonPanel={removeChild=function() end}}, {__index=ISInventoryPage})
page.inventoryPane = setmetatable({inventoryPage=page, inventory=fridge.container,
    lastinventory=fridge.container}, {__index=ISInventoryPane})
function getPlayerInventory() return page end
function getPlayerLoot() return nil end

SandboxVars.SuQingFreshnessFridge.BatchHours = 0.25
SandboxVars.SuQingFreshnessLunchbox = {Enabled=true, BaseCapacity=4, BatchHours=0.5, AllowRotten=true}
F.RegisterObject(fridge)
emit("OnGameStart")
for _ = 1, 4 do emit("OnTick") end
check(F.Runtime.ready and L.Runtime.ready, "both runtimes initialized")
check(F.Lock.Ready() and L.Lock.Ready(), "shared UI lock stays ready for both mods")
local startupSelection=ISInventoryPage.setNewContainer
ISInventoryPage.setNewContainer=function(self,...) return startupSelection(self,...) end
check(not F.Lock.SharedTransferReady(), "startup polling cannot spend the first menu's final binding")
check(F.Runtime.CanStartBatch() and L.Runtime.CanStartBatch(), "shared transfer chain stays ready")
check(F.Runtime.StartBatch(fridge), "seal the powered fridge")
check(page.inventoryPane.inventory == player.inventory, "fridge seal ejects the open panel")
check(L.Runtime.StartBatch(box), "seal the lunchbox independently")
check(F.Batch.IsSealed(fridge) and L.Batch.IsSealed(box), "both active")
check(ISInventoryPaneContextMenu.getContainers():size() == 1 and sources:size() == 3,
    "common crafting sources hide both sealed inventories without editing the source")
check(not page:setNewContainer(fridge.container), "cannot switch directly into sealed fridge")
check(not page:setNewContainer(box.inventory), "cannot switch directly into sealed lunchbox")
check(not ISInventoryTransferAction.isValid({srcContainer=fridge.container,destContainer=floor}),
    "fridge queued transfer denied")
check(not ISInventoryTransferAction.isValid({srcContainer=box.inventory,destContainer=floor}),
    "lunchbox queued transfer denied")
check(not ISEatFoodAction.complete({item=fridgeFood}) and not ISEatFoodAction.complete({item=boxFood}),
    "both sealed foods denied at consumption boundary")
ISTransferAction.transferItem({}, player, fridgeFood, fridge.container, player.inventory)
ISTransferAction.transferItem({}, player, boxFood, box.inventory, player.inventory)
check(fridgeFood.container == fridge.container and boxFood.container == box.inventory,
    "both sealed foods denied at direct transfer boundary")

local function observe(time)
    Mock.clock = time
    emit("OnTickEvenPaused")
    emit("OnTick")
end
observe(100.125)
observe(100.25)
check(not F.Batch.IsSealed(fridge) and L.Batch.IsSealed(box), "only powered fridge reaches quarter-hour")
check(fridgeFood.age == 0 and boxFood.age == 15, "each batch applies its own deadline")
check(ISInventoryPaneContextMenu.getContainers():size() == 2, "fridge source returns first")
ISTransferAction.transferItem({}, player, fridgeFood, fridge.container, player.inventory)
check(fridgeFood.container == player.inventory, "completed fridge allows normal transfers")
observe(100.5)
check(not L.Batch.IsSealed(box) and boxFood.age == 0, "lunchbox finishes separately")
check(ISInventoryPaneContextMenu.getContainers() == sources, "no filtering copy once both have reopened")
check(F.Runtime.CanStartBatch() and L.Runtime.CanStartBatch(), "shared hooks remain valid for the next batch")

print("RUNTIME_FRIDGE_LUNCHBOX_BATCH assertions="..assertions.." PASS")
