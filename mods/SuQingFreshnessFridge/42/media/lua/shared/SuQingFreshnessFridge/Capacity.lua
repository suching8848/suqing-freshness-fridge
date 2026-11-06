-- B42.21 clamps world furniture to 100 in Java. This SP Lua overlay is scoped
-- to the four independent fridge sprites and their one validated container.
-- It changes neither global/native limits nor the semantics of other storage.
require "SuQingFreshnessFridge/Core"

local C = SuQingFreshnessFridge
C.Capacity = C.Capacity or {}
local A = C.Capacity
if A.loaded then return A end
A.loaded = true
A.errors = 0
local methodNames = {"getCapacity", "getEffectiveCapacity", "getMaxWeight",
    "getFreeCapacity", "isFull", "hasRoomFor"}

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function nonnegative(value)
    return finite(value) and value >= 0
end

local function indexTable()
    local meta = __classmetatables and ItemContainer and __classmetatables[ItemContainer.class]
    return meta and meta.__index
end

local function owned(container)
    if not A.installed or not C.SP() or not container or not container.getParent then return nil end
    local parent = container:getParent()
    if not C.IsFridge(parent) then return nil end
    -- Check only after the cheap foreign-container rejection. A later mod
    -- replacing one required hook must not leave a partly active overlay.
    if not A.IsReady() or C.Container(parent) ~= container or not C.State(parent) then return nil end
    return C.Config().capacity
end

-- Java converts the float32 trait multiplication to int (towards zero).
-- Using Lua doubles or ceil disagrees at integer boundaries, e.g. 30*1.3f.
-- All values here are positive and small; powers of two and the exact float32
-- constants make round-to-nearest-even deterministic without a Java hook.
local function float32(value)
    if value == 0 then return 0 end
    local power = 1
    while power * 2 <= value do power = power * 2 end
    while power > value do power = power / 2 end
    local scale = 8388608 / power
    local scaled = value * scale
    local lower = math.floor(scaled)
    local remainder = scaled - lower
    if remainder > 0.5 or (remainder == 0.5 and lower % 2 == 1) then lower = lower + 1 end
    return lower / scale
end

local traitCapacities = {}
function A.AdjustedCapacity(base, character)
    if not character then return base end
    local values = traitCapacities[base]
    if not values then
        values = {
            math.floor(math.max(float32(base * 1.2999999523162842), base + 1)),
            math.floor(math.max(float32(base * 0.699999988079071), 1)),
        }
        traitCapacities[base] = values
    end
    if character:hasTrait(CharacterTrait.ORGANIZED) then return values[1] end
    if character:hasTrait(CharacterTrait.DISORGANIZED) then return values[2] end
    return base
end

function A.GetEffective(container, character)
    local base = owned(container)
    if base then return A.AdjustedCapacity(base, character) end
end

local function correctedWeight(container)
    local weight = container:getCapacityWeight()
    if not nonnegative(weight) then return nil end
    return ItemContainer.floatingPointCorrection(weight)
end

function A.WrapCapacity(original)
    return function(container, ...)
        local base = owned(container)
        if base then return base end
        return original(container, ...)
    end
end

function A.WrapEffective(original)
    return function(container, character, ...)
        local capacity = A.GetEffective(container, character)
        if capacity then return capacity end
        return original(container, character, ...)
    end
end

function A.WrapFree(original)
    return function(container, character, ...)
        local capacity = A.GetEffective(container, character)
        if not capacity then return original(container, character, ...) end
        local current = correctedWeight(container)
        if not current then return 0 end
        return float32(math.max(capacity - current, 0))
    end
end

function A.WrapFull(original)
    return function(container, character, ...)
        local capacity = A.GetEffective(container, character)
        if not capacity then return original(container, character, ...) end
        local current = correctedWeight(container)
        return current == nil or current >= capacity
    end
end

-- Mirror the native world-furniture room branch. Bags, floor containers,
-- vehicle parts and character inventories never satisfy owned(). Their more
-- complex native rules remain in the original continuation unchanged.
local function room(container, character, incoming, floorDelta, explicitFloorDelta)
    local capacity = A.GetEffective(container, character)
    if not capacity then return false end
    local weight
    if type(incoming) == "number" then
        weight = incoming
    elseif incoming and instanceof(incoming, "InventoryItem") then
        if container:isInside(incoming) or not container:isItemAllowed(incoming) then return false end
        weight = incoming:getUnequippedWeight()
    else
        return false
    end
    if not nonnegative(weight) then return false end
    -- The drag-preview overload supplies a net floor delta, sometimes negative.
    -- A world appliance has no ground-item square guard, but malformed input
    -- must not turn an uncertain preview into permission.
    if explicitFloorDelta and not finite(floorDelta) then return false end
    local current = correctedWeight(container)
    -- Native overloads take float, and their final addition is float32. A
    -- double sum such as 199.99f + .01f can otherwise incorrectly exceed 200.
    return current ~= nil and float32(current + float32(weight)) <= capacity
end

local function reportError(message)
    A.errors = A.errors + 1
    if A.errors <= 5 then print("[SuQingFreshnessFridge] capacity guard: " .. tostring(message)) end
end

function A.WrapRoom(original)
    return function(container, ...)
        if not owned(container) then return original(container, ...) end
        local count = select("#", ...)
        local first, second, third = ...
        local character, incoming, floorDelta, explicitFloorDelta
        if count == 1 then
            incoming = first -- Native hasRoomFor(item) uses no character traits.
            if not incoming or not instanceof(incoming, "InventoryItem") then return false end
        elseif count == 2 or count == 3 then
            character, incoming = first, second
            if character ~= nil and not instanceof(character, "IsoGameCharacter") then return false end
            if count == 3 then floorDelta, explicitFloorDelta = third, true end
        else
            return false
        end
        local ok, result = pcall(room, container, character, incoming, floorDelta, explicitFloorDelta)
        if not ok then reportError(result); return false end
        return result == true
    end
end

-- javaTransferItems is itself a vanilla Lua queue helper. Its separate
-- getCapacity/hasRoomFor(item) prechecks ignore a character's organized bonus.
-- Route only this appliance through identical source/weight/filter guards,
-- with that character's native trait-adjusted effective capacity, then enqueue
-- the ordinary timed action. Actual removal/addition stays vanilla.
function A.WrapTransfer(original)
    return function(character, item, source, destination, ...)
        local target = destination
        if target and instanceof(target, "InventoryContainer") then target = target:getInventory() end
        if not owned(target) then return original(character, item, source, destination, ...) end
        if source and instanceof(source, "InventoryContainer") then source = source:getInventory() end
        if not character or not instanceof(character, "IsoGameCharacter") or not source or source == target
            or not item or not instanceof(item, "InventoryItem") or not source:contains(item)
            or item:getContainer() ~= source or target:isInside(item) then return end
        local capacity = A.GetEffective(target, character)
        local current, incoming = target:getCapacityWeight(), item:getActualWeight()
        if not capacity or not nonnegative(current) or not nonnegative(incoming)
            or float32(current + float32(incoming)) > capacity or not target:hasRoomFor(character, item) then return end
        ISTimedActionQueue.add(ISInventoryTransferAction:new(character, item, source, target, 10))
    end
end

function A.IsReady()
    if not C.SP() or not A.installed then return false end
    local index = indexTable()
    if not index or not A.wrappers or javaTransferItems ~= A.transferWrapper then return false end
    for _, name in ipairs(methodNames) do
        if index[name] ~= A.wrappers[name] then return false end
    end
    return ISTimedActionQueue ~= nil and ISInventoryTransferAction ~= nil
end

function A.Install()
    if not C.SP() then return false end
    if A.installed then return A.IsReady() end
    local index = indexTable()
    if not index or type(javaTransferItems) ~= "function" or not ISTimedActionQueue
        or not ISTimedActionQueue.add or not ISInventoryTransferAction or not ISInventoryTransferAction.new then return false end
    for _, name in ipairs(methodNames) do if not index[name] then return false end end
    -- Save all continuations before changing anything. Never install a second
    -- layer beneath an unknown replacement on a later Install() call.
    A.originals, A.wrappers = {}, {}
    for _, name in ipairs(methodNames) do A.originals[name] = index[name] end
    A.wrappers.getCapacity = A.WrapCapacity(A.originals.getCapacity)
    A.wrappers.getEffectiveCapacity = A.WrapEffective(A.originals.getEffectiveCapacity)
    A.wrappers.getMaxWeight = A.WrapCapacity(A.originals.getMaxWeight)
    A.wrappers.getFreeCapacity = A.WrapFree(A.originals.getFreeCapacity)
    A.wrappers.isFull = A.WrapFull(A.originals.isFull)
    A.wrappers.hasRoomFor = A.WrapRoom(A.originals.hasRoomFor)
    A.originalTransfer = javaTransferItems
    A.transferWrapper = A.WrapTransfer(A.originalTransfer)
    for _, name in ipairs(methodNames) do index[name] = A.wrappers[name] end
    javaTransferItems = A.transferWrapper
    A.installed = true
    return A.IsReady()
end

return A
