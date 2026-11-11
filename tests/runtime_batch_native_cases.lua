-- Run with the shared NativeProbe host after its native bootstrap, fridge Core and Batch.
local C = SuQingFreshnessFridge
local B = C.Batch
local check, near, test = Native.check, Native.near, Native.test

test("native fridge food and observed power progress survive serialization", function()
    SandboxVars.DaysForRottenFoodRemoval = 0
    SandboxVars.SuQingFreshnessFridge = {Enabled=true, Capacity=200, BatchHours=0.25, AllowRotten=true}
    ProbeRemoval:setValue(0)
    local fridge, container = ProbeMakeFridge()
    local food = ProbeMakeFood(15, 5, 10, "Base.Compost")
    food:setTainted(false)
    food:setIsCookable(true)
    container:AddItem(food)

    -- Supply power explicitly: the fixture has native items and containers
    -- but no loaded grid, utility shutoff or electrical network.
    local powered = C.Powered
    C.Powered = function(object, inventory) return C.Container(object) == inventory end
    local calories, hunger = food:getCalories(), food:getHungerChange()
    local poison, cooked = food:getPoisonPower(), food:isCooked()
    local started, reason = B.Start(fridge, Native.now())
    check(started, "native fridge seal failed: "..tostring(reason))
    local batch = B.Get(fridge)
    near(batch.hours, 0.25)
    check(food:getOffAgeMax() == B.nonperishable and not food:isCookable())
    near(food:getAge(), 15)
    B.Advance(fridge, 0.125)
    near(batch.poweredHours, 0.125)
    ProbeNativeRot(food, container)
    check(container:getItems():contains(food), "native rot and replacement preserve sealed food")

    local restoredFood = ProbeRoundTrip(food, 10, true)
    check(restoredFood:getID() == food:getID(), "native food ID survives serialization")
    check(restoredFood:getOffAgeMax() == B.nonperishable and not restoredFood:isCookable(),
        "native save applies guard over ordinary defaults")
    check(restoredFood:getModData()[B.foodKey], "native guard receipt survives serialization")

    -- Use the native item ModData codec for the object metadata as well.
    local carrier = ProbeMakeFood(1, 5, 10)
    carrier:getModData()[C.objectKey] = fridge:getModData()[C.objectKey]
    carrier:getModData()[B.objectKey] = batch
    local saved = ProbeRoundTrip(carrier):getModData()
    local restoredFridge, restoredContainer = ProbeMakeFridge()
    restoredFridge:getModData()[C.objectKey] = saved[C.objectKey]
    restoredFridge:getModData()[B.objectKey] = saved[B.objectKey]
    restoredContainer:AddItem(restoredFood)
    check(B.IsSealed(restoredFridge))
    check(B.Get(restoredFridge) ~= batch)
    near(B.Get(restoredFridge).poweredHours, 0.125)

    local now = Native.advance(8)
    ProbeNativeAge(restoredFood)
    ProbeNativeRot(restoredFood, restoredContainer)
    check(restoredContainer:getItems():contains(restoredFood), "native update after reload retains original food")
    check(not B.Complete(restoredFridge, now), "a wall-clock gap cannot complete a powered batch")
    check(B.IsSealed(restoredFridge))
    B.Advance(restoredFridge, 0.125)
    local completed, finishReason = B.Complete(restoredFridge, now)
    check(completed, "native fridge completion failed: "..tostring(finishReason))
    check(not B.IsSealed(restoredFridge))
    near(restoredFood:getAge(), 0)
    near(restoredFood:getLastAged(), now)
    check(restoredFood:getOffAge() == 5 and restoredFood:getOffAgeMax() == 10 and restoredFood:isCookable())
    check(restoredFood:getReplaceOnRotten() == "Base.Compost")
    near(restoredFood:getCalories(), calories)
    near(restoredFood:getHungerChange(), hunger)
    check(restoredFood:getPoisonPower() == poison and restoredFood:isCooked() == cooked)
    check(not restoredFood:isTainted())
    check(restoredFood:getModData()[B.foodKey] == nil)
    C.Powered = powered
    ProbeRemoval:setValue(-1)
end)

print("RUNTIME_FRIDGE_BATCH_NATIVE cases="..Native.cases.." assertions="..Native.assertions.." PASS")
