local C=SuQingFreshnessFridge
local food,object=ProbeFood,NativeCoreObject
food:setAge(100000)
food:setLastAged(NativeCoreClock)
food:getModData()[C.foodKey]=nil
local initial=food:getAge()
assert(C.IsFood(food),"actual native Food recognition")
assert(C.IsDirectFood(food,object),"actual native container identity")
assert(C.SettleFood(food,object,NativeCoreClock,{continuous=false,powered=true}).active)
for pass=1,3600 do
    local t=NativeCoreClock+pass/3600
    local result=C.SettleFood(food,object,t,{continuous=true,powered=true})
    assert(result.active,"native old Food remains eligible")
end
local expected=initial-0.5
assert(math.abs(food:getAge()-expected)<0.01,"high native float32 food age must accumulate tiny restoration: "..tostring(food:getAge()).." expected "..tostring(expected))
local record=C.FoodRecord(food)
assert(record and record.logicalAge and math.abs(record.logicalAge-expected)<0.0001,"double precision ledger tracks sub-ULP restoration")
local precisionSummary="NATIVE_CORE_PRECISION cases=1 passes=3600 assertions=3605 failures=0; real Food getAge/setAge PASS"

-- Native display regression: this is a real Food in a real ItemContainer.
-- Food.updateRotting is invoked directly by the Java callback, with no world.
local displayAssertions,displayCases=0,0
local function check(value,label)
    displayAssertions=displayAssertions+1
    assert(value,label)
end
local oldRemoval=SandboxVars.DaysForRottenFoodRemoval
local nativeRemoval=ProbeNativeRemoval:getValue()
SandboxVars.DaysForRottenFoodRemoval=-1
ProbeNativeRemoval:setValue(-1)
local originalReplacement=food:getReplaceOnRotten()
local originalCooked=food:isCooked()
food:setCooked(false)
local originalCount=ProbeFridge:getItems():size()
ProbeFridge:AddItem(food)
check(ProbeFridge:contains(food),"display probe is physically stored in native container")

local function prepare(replacement)
    C.ClearFood(food)
    food:setReplaceOnRotten(replacement)
    food:setAge(15)
    food:setLastAged(NativeCoreClock)
    check(C.SettleFood(food,object,NativeCoreClock,{continuous=false,powered=true}).active,"display food anchored active")
end
local function snapshot()
    return {
        age=food:getAge(),lastAged=food:getLastAged(),name=food:getName(),
        rotten=food:isRotten(),fresh=food:isFresh(),hunger=food:getHungerChange(),
        stress=food:getStressChange(),endurance=food:getEnduranceChange(),
        unhappy=food:getUnhappyChange(),boredom=food:getBoredomChange(),
        calories=food:getCalories(),carbs=food:getCarbohydrates(),
        lipids=food:getLipids(),proteins=food:getProteins(),
        cooked=food:isCooked(),poison=food:getPoisonPower(),
    }
end
local function unchanged(expected,label)
    local actual=snapshot()
    for key,value in pairs(expected) do check(actual[key]==value,label.." native "..key) end
    check(ProbeFridge:contains(food),label.." original item not removed")
    check(ProbeFridge:getItems():size()==originalCount+1,label.." no replacement item added")
end

for _,replacement in ipairs({false,""}) do
    displayCases=displayCases+1
    prepare(replacement or nil)
    local before=snapshot()
    check(before.rotten and not before.fresh,"unshielded sample starts genuinely rotten")
    check(not C.ProtectFood(food,object,NativeCoreClock),"no replacement/removal risk needs no shield")
    check(C.FoodRecord(food).shield==nil,"no needless physical guard record")
    for pass=1,12 do ProbeNativeRot();unchanged(before,"no replacement pass "..pass) end
end

displayCases=displayCases+1
prepare(originalReplacement)
local before=snapshot()
check(before.name:find("Rotten",1,true)~=nil,"native getName reports real rotten classification")
check(C.ProtectFood(food,object,NativeCoreClock),"replacement protection acquired")
check(C.FoodRecord(food).shield.mode=="replacement","replacement-only receipt used")
check(food:getReplaceOnRotten()=="","only native rotten replacement suspended")
-- Repeated native updates without any intervening Lua tick/post callback model
-- the optimizer's delayed callback window. Age and all status readers stay real.
for pass=1,120 do ProbeNativeRot();unchanged(before,"replacement guard pass "..pass) end
check(C.RestoreFood(food),"save/restore entry point releases replacement protection")
check(food:getReplaceOnRotten()==originalReplacement,"original native replacement restored")
unchanged(before,"after save/restore entry point")

displayCases=displayCases+1
prepare(originalReplacement)
check(C.ProtectFood(food,object,NativeCoreClock),"clear protection acquired")
C.ClearFood(food)
check(food:getReplaceOnRotten()==originalReplacement,"ClearFood restores original replacement")
check(C.FoodRecord(food)==nil,"ClearFood clears only this module's record")
check(food:getAge()==15 and food:isRotten(),"ClearFood never rewrites age or rotten status")

displayCases=displayCases+1
prepare(originalReplacement)
check(C.ProtectFood(food,object,NativeCoreClock),"external age edit protection acquired")
food:setAge(23)
check(C.RestoreFood(food),"external age edit does not block replacement recovery")
check(food:getAge()==23,"external age edit respected exactly")
check(food:getReplaceOnRotten()==originalReplacement,"replacement restored independently of age")

displayCases=displayCases+1
prepare(originalReplacement)
check(C.ProtectFood(food,object,NativeCoreClock),"external replacement edit protection acquired")
food:setReplaceOnRotten("DifferentExternalReplacement")
local restored,reason=C.RestoreFood(food)
check(not restored and reason=="external_replacement_edit","external replacement edit identified")
check(food:getReplaceOnRotten()=="DifferentExternalReplacement","external replacement edit not overwritten")
check(food:getAge()==15 and food:isRotten(),"external replacement recovery does not touch age")

C.ClearFood(food)
food:setReplaceOnRotten(originalReplacement)
food:setCooked(originalCooked)
ProbeFridge:Remove(food)
food:setContainer(ProbeFridge)
check(ProbeFridge:getItems():size()==originalCount,"native display test restores container contents")
SandboxVars.DaysForRottenFoodRemoval=oldRemoval
ProbeNativeRemoval:setValue(nativeRemoval)
return precisionSummary.."; NATIVE_DISPLAY_GUARD cases="..displayCases.." assertions="..displayAssertions.." native_updates=144 failures=0; real Food names/status/effects and native rotting PASS"
