require "SuQingFreshnessFridge/Core"

local C = SuQingFreshnessFridge
C.Building = C.Building or {}
local B = C.Building

B.spriteNames = {
    suqing_freshness_fridge_01_0 = true, -- S
    suqing_freshness_fridge_01_1 = true, -- E
    suqing_freshness_fridge_01_2 = true, -- N
    suqing_freshness_fridge_01_3 = true, -- W
}

function B.IsObject(object)
    if not object or not object.getSprite then return false end
    local sprite = object:getSprite()
    return sprite ~= nil and B.spriteNames[sprite:getName()] == true
end

-- This function is deliberately idempotent. It never clears containers or
-- rewrites object ModData: native furniture pickup retains the full state.
function B.EnsureObject(object,forceCapacity)
    if not B.IsObject(object) then return false, "not_our_sprite" end
    if object:getContainerCount() == 0 then
        object:createContainersFromSpriteProperties()
    end
    if object:getContainerCount() ~= 1 then
        -- An unexpected secondary container must not be destroyed along with
        -- its contents. The runtime can refuse processing and log the fault.
        return false, "expected_one_container"
    end
    local container = object:getContainerByIndex(0)
    if not container or container:getType() ~= "fridge" then
        return false, "expected_fridge_container"
    end
    if not C.RefreshCapacity(object,forceCapacity) then return false,"capacity_refresh_failed" end
    container:setExplored(true)
    container:setParent(object)
    if object.setExplored then object:setExplored(true) end
    -- Never call IsoThumpable:setIsContainer(true) here: in B42.21 it
    -- allocates a fresh crate and overwrites an existing container.
    return true, container
end

function B.RegisterObject(object,forceCapacity)
    local valid, result = B.EnsureObject(object,forceCapacity)
    if not valid then return false, result end
    if C.RegisterObject then
        local registered, reason = C.RegisterObject(object)
        if registered == false then return false, reason or "core_state_rejected" end
    end
    return true, result
end

function B.OnCreate(params)
    local object = params and params.thumpable
    local valid, reason = B.RegisterObject(object,true)
    if not valid then
        print("[SuQingFreshnessFridge] built object registration failed: " .. tostring(reason))
    end
    -- Returning nil leaves native construction in charge of transmission.
    -- Materials, tool fuel and cancellation remain native BuildLogic work.
end

function B.OnObjectAdded(object)
    if B.IsObject(object) then
        local valid, reason = B.RegisterObject(object,true)
        if not valid then
            print("[SuQingFreshnessFridge] placed object registration failed: " .. tostring(reason))
        end
    end
end

function B.OnLoadSquare(square)
    if not square then return end
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        B.OnObjectAdded(objects:get(index))
    end
end

return B
