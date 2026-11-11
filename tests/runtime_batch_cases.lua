-- Load after runtime_mock_bootstrap.lua, Core.lua, Batch.lua and Runtime.lua.
local C = SuQingFreshnessFridge
local B = C.Batch
local R = C.Runtime
local cases, assertions, failures = 0, 0, 0

C.Lock = {Ready=function() return true end, Refresh=function() end}

local function check(value, message)
    assertions = assertions + 1
    if not value then error(message or "check failed", 0) end
end

local function equal(actual, expected, message)
    check(actual == expected, (message or "not equal")..": "..tostring(actual).." ~= "..tostring(expected))
end

local function near(actual, expected, message)
    check(math.abs(actual - expected) < 0.00001,
        (message or "not near")..": "..tostring(actual).." ~= "..tostring(expected))
end

local function observe(time)
    Mock.clock = time
    emit("OnTickEvenPaused")
    if not Mock.paused then emit("OnTick") end
end

local function makeFood(container, age)
    local food = Mock.food(container, age, 5, 10)
    food.cookable = true
    food.tainted = false
    food.replacement = "Base.Compost"
    food.setOffAgeMax = function(self, value) self.rotten = value end
    food.isCookable = function(self) return self.cookable end
    food.setIsCookable = function(self, value) self.cookable = value end
    food.isTainted = function(self) return self.tainted end
    return food
end

local function startRuntime(object)
    Mock.start(object)
    emit("OnTick")
    emit("OnTick")
    check(R.ready, "fridge runtime ready")
end

local function seal(object)
    local ok, reason = R.StartBatch(object)
    check(ok, "seal failed: "..tostring(reason))
    check(B.IsSealed(object), "batch locks the fridge")
    local batch = B.Get(object)
    check(batch and batch.phase == "sealed", "durable sealed record")
    return batch
end

local function cloneData(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, entry in pairs(value) do copy[key] = cloneData(entry) end
    return copy
end

local function case(name, fn)
    cases = cases + 1
    Mock.reset()
    local ok, reason = pcall(fn)
    if ok then
        print("FRIDGE_BATCH_CASE "..name.." PASS")
    else
        failures = failures + 1
        print("FRIDGE_BATCH_CASE "..name.." FAIL: "..tostring(reason))
    end
end

case("fridge duration has an independent default and quarter-hour minimum", function()
    local config = SandboxVars.SuQingFreshnessFridge
    SandboxVars.SuQingFreshnessLunchbox = {BatchHours=2}
    config.RestoreHours = 0.25
    equal(B.Hours(), 12, "legacy rate and lunchbox duration cannot set the fridge batch time")
    config.BatchHours = 0.1
    equal(B.Hours(), 0.25)
    config.BatchHours = 80
    equal(B.Hours(), 24)
    config.BatchHours = "invalid"
    equal(B.Hours(), 12)
end)

case("manual batch pauses without power and finishes after one quarter powered hour", function()
    local object = Mock.fridge()
    local food = makeFood(object.container, 15)
    SandboxVars.SuQingFreshnessFridge.BatchHours = 0.25
    startRuntime(object)
    check(not B.IsSealed(object), "an idle fridge does not auto-seal")
    object.container.powered = false
    local ok = R.StartBatch(object)
    check(not ok, "unpowered fridge cannot start")
    object.container.powered = true
    observe(100)

    local batch = seal(object)
    equal(batch.hours, 0.25)
    near(batch.poweredHours, 0)
    check(B.IsLockedContainer(object.container) and B.IsSealedFood(food))
    equal(food.rotten, B.nonperishable)
    equal(food.cookable, false)
    near(food.age, 15, "sealing itself does not reset age")
    SandboxVars.SuQingFreshnessFridge.BatchHours = 24
    observe(100.125)
    near(batch.poweredHours, 0.125)
    object.container.powered = false
    observe(100.125)
    observe(103)
    near(batch.poweredHours, 0.125, "unpowered gap gives no credit")
    check(B.IsSealed(object))
    object.container.powered = true
    observe(103)
    near(batch.poweredHours, 0.125, "restoring power only reanchors")
    observe(103.125)
    check(not B.IsSealed(object))
    near(food.age, 0)
    near(food.lastAged, 103.125)
    equal(food.rotten, 10)
    equal(food.cookable, true)
    equal(food.replacement, "Base.Compost")
    equal(food.portion, 0.4)
    equal(food.poison, 9)
    equal(food.calories, 123)

    Mock.clock = 103.25
    Mock.nativeAge(food)
    local aged = food.age
    check(aged > 0)
    observe(103.25)
    near(food.age, aged, "ordinary aging resumes without a second reset")
end)

case("saved progress survives reload without credit for the absent interval", function()
    local object = Mock.fridge()
    local food = makeFood(object.container, 8)
    SandboxVars.SuQingFreshnessFridge.BatchHours = 0.25
    startRuntime(object)
    local batch = seal(object)
    local roster = batch.roster
    observe(100.125)
    emit("OnSave")
    near(batch.poweredHours, 0.125)
    equal(batch.roster, roster, "save does not rebuild the roster")
    local objectData, foodData = cloneData(object.md), cloneData(food.md)
    local foodId, age, cookable, rotten = food.id, food.age, food.cookable, food.rotten

    Mock.reset()
    Mock.clock = 110
    local loaded = Mock.fridge()
    local loadedFood = makeFood(loaded.container, age)
    loaded.md, loadedFood.md, loadedFood.id = objectData, foodData, foodId
    loadedFood.cookable, loadedFood.rotten = cookable, rotten
    startRuntime(loaded)
    observe(110)
    local loadedBatch = B.Get(loaded)
    check(B.IsSealed(loaded))
    near(loadedBatch.poweredHours, 0.125)
    near(loadedFood.age, 8)
    observe(110.125)
    check(not B.IsSealed(loaded))
    near(loadedFood.age, 0)
    near(loadedFood.lastAged, 110.125)
end)

case("streaming out drops the old power anchor and reentry resumes saved progress", function()
    local object = Mock.fridge()
    local food = makeFood(object.container, 8)
    SandboxVars.SuQingFreshnessFridge.BatchHours = 0.25
    startRuntime(object)
    local batch = seal(object)
    observe(100.125)
    near(batch.poweredHours, 0.125)
    Mock.unload(object)
    observe(100.25)
    observe(120)
    check(B.IsSealed(object))
    near(batch.poweredHours, 0.125)
    near(food.age, 8)
    Mock.reload(object)
    emit("LoadGridsquare", object.square)
    observe(120)
    near(batch.poweredHours, 0.125)
    observe(120.125)
    check(not B.IsSealed(object))
    near(food.age, 0)
end)

case("Live Wire cut and restore between ticks cannot credit the off interval", function()
    local object = Mock.fridge()
    local food = makeFood(object.container, 15)
    local circuit = {v=1, kind="fridge", cut=false, types={["0"]="fridge"}}
    object.md.LiveWireCircuit = circuit
    local calls = 0
    local appliances = {
        saved=function(target) return target.md.LiveWireCircuit end,
        apply=function(target, saved, off)
            calls = calls + 1
            target.container.type = off and "none" or "fridge"
            saved.cut = off
            return "original"
        end,
    }
    LiveWire = {VERSION="1.7.2", Appliances=appliances}
    SandboxVars.SuQingFreshnessFridge.BatchHours = 0.25
    startRuntime(object)
    local batch = seal(object)
    observe(100.125)
    near(batch.poweredHours, 0.125)
    Mock.clock = 100.1875
    equal(appliances.apply(object,circuit,true), "original")
    equal(object.container.type, "none")
    check(B.IsLockedContainer(object.container), "a cut fridge stays locked")
    Mock.clock = 100.3125
    equal(appliances.apply(object,circuit,false), "original")
    equal(calls, 2)
    observe(100.3125)
    check(B.IsSealed(object))
    check(batch.poweredHours >= 0.125 and batch.poweredHours <= 0.1875,
        "at most the observed powered interval before the cut is creditable")
    near(food.age, 15)
    observe(100.4375)
    check(not B.IsSealed(object))
    near(food.age, 0)
end)

local function measureWaiting(count, sealed)
    Mock.reset()
    local object = Mock.fridge()
    local foods = {}
    for i = 1, count do foods[i] = makeFood(object.container, 15) end
    startRuntime(object)
    local batch = sealed and seal(object) or nil
    local roster = batch and batch.roster
    local inventoryReads, processReads, foodCalls = 0, 0, 0
    local getItems = object.container.getItems
    object.container.getItems = function(self)
        inventoryReads = inventoryReads + 1
        return getItems(self)
    end
    local originalCell = getCell
    getCell = function()
        local cell = originalCell()
        local process = cell.getProcessItems
        cell.getProcessItems = function(self)
            processReads = processReads + 1
            return process(self)
        end
        return cell
    end
    for _, food in ipairs(foods) do
        for _, method in ipairs({"getAge","setAge","getContainer","getModData","getID","getFullType",
            "getOffAge","getOffAgeMax","setOffAgeMax","setLastAged","getLastAged","updateAge",
            "isCookable","setIsCookable","isTainted"}) do
            local original = food[method]
            food[method] = function(self, ...)
                foodCalls = foodCalls + 1
                return original(self, ...)
            end
        end
    end
    for i = 1, 240 do observe(100 + i / 1000) end
    emit("OnSave")
    getCell = originalCell
    print("FRIDGE_BATCH_WAIT foods="..count.." sealed="..tostring(sealed)
        .." inventoryReads="..inventoryReads.." processReads="..processReads.." foodCalls="..foodCalls)
    check(R.ready)
    equal(inventoryReads, 0, "waiting and saving must not enumerate fridge contents")
    equal(processReads, 0, "no global process-list polling")
    equal(foodCalls, 0, "waiting and saving must not touch individual foods")
    if batch then
        equal(B.Get(object), batch)
        equal(batch.roster, roster)
        equal(batch.count, count)
        near(batch.poweredHours, 0.24, "power time is tracked once per fridge")
    end
end

case("waiting work has no per-food reads at 32, 64 or 128 foods", function()
    measureWaiting(32, false)
    measureWaiting(32, true)
    measureWaiting(64, true)
    measureWaiting(128, true)
end)

print("RUNTIME_FRIDGE_BATCH cases="..cases.." assertions="..assertions.." failures="..failures)
if failures > 0 then error("fridge batch regression failures: "..failures) end
