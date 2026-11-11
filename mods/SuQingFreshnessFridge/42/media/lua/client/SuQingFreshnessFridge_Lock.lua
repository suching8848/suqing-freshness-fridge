require "SuQingFreshnessFridge/Batch"
require "ISUI/ISInventoryPage"
require "ISUI/ISInventoryPaneContextMenu"
require "TimedActions/ISInventoryTransferAction"
require "TimedActions/ISDestroyStuffAction"
require "TimedActions/ISEatFoodAction"
require "TimedActions/ISAddItemInRecipe"
require "TimedActions/ISCraftAction"
require "Entity/TimedActions/ISHandcraftAction"

local C=SuQingFreshnessFridge
local B=C.Batch
C.Lock=C.Lock or {}
local L=C.Lock
if L.loaded then return L end
L.loaded=true

local borrowed
local function modernLunchbox()
    local other=SuQingFreshnessLunchbox
    if not other or (other.version~="0.2.0-rc.1" and other.version~="0.2.0-rc.2"
        and other.version~="0.2.0-rc.3" and other.version~="0.2.0-rc.4")
        or not other.Batch or not other.Lock
        or type(other.Batch.IsLockedContainer)~="function" or type(other.Batch.IsSealedFood)~="function"
        or type(other.Batch.RecoverFood)~="function"
        or type(other.Lock.Ready)~="function" or type(other.Lock.Refresh)~="function" then return nil end
    return other
end

function L.SharedTransfer()
    local other=modernLunchbox()
    return other and other.Runtime
end

local function borrowLunchbox(other)
    local batch=other.Batch
    local priorContainer,priorFood,priorRecover=batch.IsLockedContainer,batch.IsSealedFood,batch.RecoverFood
    local function bothContainers(container)
        return B.IsLockedContainer(container) or priorContainer(container)
    end
    local function bothFoods(food)
        return B.IsSealedFood(food) or priorFood(food)
    end
    local function recover(food)
        local runtime=C.Runtime
        if runtime and runtime.IsFoodLoaded and C.SP() and C.IsFood(food)
            and (not food.hasModData or food:hasModData()) then
            local md=food:getModData()
            if (md[B.foodKey]~=nil or md[C.foodKey]~=nil) and not bothContainers(food:getContainer())
                and runtime.IsFoodLoaded(food) then
                B.RecoverFood(food,true)
            end
        end
        return priorRecover(food)
    end
    batch.IsLockedContainer=bothContainers
    batch.IsSealedFood=bothFoods
    batch.RecoverFood=recover
    borrowed={other=other,container=bothContainers,food=bothFoods,recover=recover}
end

local function borrowedReady()
    if not borrowed or modernLunchbox()~=borrowed.other then return false end
    local other=borrowed.other
    return other.Batch.IsLockedContainer==borrowed.container and other.Batch.IsSealedFood==borrowed.food
        and other.Batch.RecoverFood==borrowed.recover and other.Lock.Ready()
end

function L.SharedTransferReady()
    local runtime=L.SharedTransfer()
    return L.Ready() and runtime and runtime.CanStartBatch and runtime.CanStartBatch(true) or false
end

local function locked(container)
    return container and C.SP() and B.IsLockedContainer(container) or false
end

local function sealedFood(food)
    return food and C.SP() and B.IsSealedFood(food) or false
end

local function eject(page)
    local pane=page and page.inventoryPane
    if not pane then return false end
    if locked(page.forceSelectedContainer) then page.forceSelectedContainer=nil end
    local current=pane.inventory
    local currentLocked=locked(current)
    local lastLocked=locked(pane.lastinventory)
    local pageLocked=locked(page.inventory)
    if not currentLocked and not lastLocked and not pageLocked then
        return false
    end
    local fallback=not currentLocked and current or nil
    if not fallback and page.onCharacter then
        local player=getSpecificPlayer(page.player)
        fallback=player and player:getInventory()
    elseif not fallback then
        fallback=ISInventoryPage.GetFloorContainer(page.player)
    end
    if not fallback then return false end
    pane.inventory=fallback
    pane.lastinventory=fallback
    pane.selected={}
    page.inventory=fallback
    page.selectedButton=nil
    return true
end

local function refreshPage(page)
    local changed=eject(page)
    local pane=page and page.inventoryPane
    local container=pane and pane.inventory
    local kind=container and container.getType and container:getType()
    if (kind=="proxInv" or kind=="local") and page.refreshBackpacks then
        -- Rebuild the selected merged view from visible source tabs at the
        -- seal/release boundary, before its old rows can be used again.
        page:refreshBackpacks()
    elseif changed then
        pane:refreshContainer()
    end
end

function L.Refresh()
    if borrowed then return borrowed.other.Lock.Refresh() end
    ISInventoryPage.renderDirty=true
    for index=0,getNumActivePlayers()-1 do
        refreshPage(getPlayerInventory(index))
        refreshPage(getPlayerLoot(index))
    end
end

function L.FilterContainers(containers)
    if not containers or not C.SP() then return containers end
    for index=0,containers:size()-1 do
        if locked(containers:get(index)) then
            local filtered=ArrayList.new()
            for i=0,containers:size()-1 do
                local container=containers:get(i)
                if not locked(container) then filtered:add(container) end
            end
            return filtered
        end
    end
    return containers
end

local function containsSealedFood(items)
    if not items then return false end
    for i=0,items:size()-1 do
        if sealedFood(items:get(i)) then return true end
    end
    return false
end

local function craftLocked(action)
    if containsSealedFood(action.items) then return true end
    if action.manualInputs then
        for _,items in pairs(action.manualInputs) do
            if containsSealedFood(items) then return true end
        end
    end
    local data=action.logic and action.logic:getRecipeData()
    return data and containsSealedFood(data:getAllInputItems()) or false
end

local hooks={}
local function addHook(owner,key,make)
    if not owner or type(owner[key])~="function" then return false end
    for _,hook in ipairs(hooks) do
        if hook.owner==owner and hook.key==key then return true end
    end
    local hook={owner=owner,key=key,make=make,wrapper=make(owner[key])}
    hooks[#hooks+1]=hook
    return true
end

local function denyWhen(predicate)
    return function(prior)
        return function(self,...)
            if predicate(self,...) then return false end
            return prior(self,...)
        end
    end
end

local function transferLocked(action)
    return locked(action.srcContainer) or locked(action.destContainer)
end

local function eatLocked(action)
    return sealedFood(action.item)
end

local function recipeAdditionLocked(action)
    return sealedFood(action.usedItem) or sealedFood(action.baseItem)
end

local function filterCraftContainers(prior)
    return function(self,...)
        self.containers=L.FilterContainers(self.containers)
        return prior(self,...)
    end
end

local function legacyCraft(prior)
    return filterCraftContainers(denyWhen(function(action) return sealedFood(action.item) end)(prior))
end

local pageClasses,paneClasses={},{}
local function addInventoryHooks(pageClass,paneClass)
    if not pageClass or not paneClass or type(pageClass.addContainerButton)~="function"
        or type(pageClass.selectContainer)~="function" or type(pageClass.setNewContainer)~="function"
        or type(pageClass.selectButtonForContainer)~="function" or type(paneClass.refreshContainer)~="function" then
        return false
    end
    addHook(pageClass,"addContainerButton",function(prior)
        return function(self,container,...)
            local button=prior(self,container,...)
            if button and locked(container) and self.backpacks[#self.backpacks]==button then
                -- Vanilla callers immediately tint the returned button. Return
                -- the real button, but keep it out of the visible/craft list.
                self.containerButtonPanel:removeChild(button)
                self.backpacks[#self.backpacks]=nil
                self.buttonPool[#self.buttonPool+1]=button
            end
            return button
        end
    end)
    addHook(pageClass,"selectContainer",denyWhen(function(_,button)
        return button and locked(button.inventory)
    end))
    addHook(pageClass,"setNewContainer",denyWhen(function(_,container)
        return locked(container)
    end))
    addHook(pageClass,"selectButtonForContainer",denyWhen(function(_,container)
        return locked(container)
    end))
    addHook(paneClass,"refreshContainer",function(prior)
        return function(self,...)
            if locked(self.inventory) then
                eject(self.inventoryPage)
                if locked(self.inventory) then return end
            end
            return prior(self,...)
        end
    end)
    pageClasses[pageClass]=true
    paneClasses[paneClass]=true
    return true
end

local function addCleanUIHooks()
    -- CleanUI 42.22 can switch the active class tables without reloading Lua.
    -- Protect both its enhanced and namespaced stock-mode windows.
    addInventoryHooks(CleanUI_Clean_ISInventoryPage,CleanUI_Clean_ISInventoryPane)
    addInventoryHooks(CleanUI_Vanilla_ISInventoryPage,CleanUI_Vanilla_ISInventoryPane)
end

local function addStandaloneHooks()
    local ok=addInventoryHooks(ISInventoryPage,ISInventoryPane)
    addCleanUIHooks()
    ok=addHook(ISInventoryPaneContextMenu,"getContainers",function(prior)
        return function(...)
            return L.FilterContainers(prior(...))
        end
    end) and ok
    ok=addHook(ISInventoryTransferAction,"isValidStart",denyWhen(transferLocked)) and ok
    ok=addHook(ISInventoryTransferAction,"isValid",denyWhen(transferLocked)) and ok
    ok=addHook(ISInventoryTransferAction,"transferItem",denyWhen(transferLocked)) and ok
    ok=addHook(ISEatFoodAction,"isValidStart",denyWhen(function(action)
        return eatLocked(action) or sealedFood(action:getRequiredItem())
    end)) and ok
    ok=addHook(ISEatFoodAction,"isValid",denyWhen(eatLocked)) and ok
    ok=addHook(ISEatFoodAction,"complete",denyWhen(eatLocked)) and ok
    ok=addHook(ISEatFoodAction,"eat",denyWhen(eatLocked)) and ok
    ok=addHook(ISAddItemInRecipe,"isValid",denyWhen(recipeAdditionLocked)) and ok
    ok=addHook(ISAddItemInRecipe,"complete",denyWhen(recipeAdditionLocked)) and ok
    ok=addHook(ISCraftAction,"isValid",legacyCraft) and ok
    ok=addHook(ISCraftAction,"complete",legacyCraft) and ok
    ok=addHook(ISHandcraftAction,"isValid",denyWhen(craftLocked)) and ok
    ok=addHook(ISHandcraftAction,"start",filterCraftContainers) and ok
    ok=addHook(ISHandcraftAction,"performRecipe",denyWhen(craftLocked)) and ok
    return ok
end

local function install()
    if #hooks>0 or not C.SP() then return end
    local function sealedTarget(action)
        return C.SP() and B.IsSealed(action.item)
    end
    local ok=addHook(ISDestroyStuffAction,"isValid",denyWhen(sealedTarget))
    ok=addHook(ISDestroyStuffAction,"complete",denyWhen(sealedTarget)) and ok
    local other=modernLunchbox()
    if not ok or (not other and not addStandaloneHooks()) then hooks={};return end
    if other then
        -- The audited lunchbox guards dispatch these predicates dynamically.
        -- Sharing them preserves both modules' hook identity checks.
        borrowLunchbox(other)
    end
    for _,hook in ipairs(hooks) do hook.owner[hook.key]=hook.wrapper end
end

function L.Ready()
    if #hooks==0 then return false end
    for _,hook in ipairs(hooks) do
        if hook.owner[hook.key]~=hook.wrapper then return false end
    end
    if borrowed then return borrowedReady() end
    return pageClasses[ISInventoryPage]==true and paneClasses[ISInventoryPane]==true
end

local passes=0
local startupCaptured=false
local function captureStartupChain()
    passes=passes+1
    if passes<2 then return end
    Events.OnTick.Remove(captureStartupChain)
    startupCaptured=true
    -- Some mods install their forwarding wrappers on the first normal tick.
    -- Capture the completed startup chain once, without following later drift.
    if not borrowed then
        addInventoryHooks(ISInventoryPage,ISInventoryPane)
        addCleanUIHooks()
    end
    for _,hook in ipairs(hooks) do
        local current=hook.owner[hook.key]
        if current~=hook.wrapper and type(current)=="function" then
            hook.wrapper=hook.make(current)
            hook.owner[hook.key]=hook.wrapper
        end
    end
end

Events.OnGameStart.Add(function()
    install()
    if #hooks>0 and not startupCaptured and Events.OnTick.Remove then
        passes=0
        Events.OnTick.Remove(captureStartupChain)
        Events.OnTick.Add(captureStartupChain)
    end
end)
Events.OnRefreshInventoryWindowContainers.Add(function(page,phase)
    if not borrowed and (phase=="begin" or phase=="buttonsAdded") then eject(page) end
end)

return L
