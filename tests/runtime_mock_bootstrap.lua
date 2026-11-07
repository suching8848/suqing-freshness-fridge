-- Independent deterministic engine model. This file never opens a client/save.
require=function(name)
    -- Runtime/lifecycle tests isolate the capacity bridge. Its real native/Lua
    -- integration is exercised by the separate capacity/native probe suite.
    if name=="SuQingFreshnessFridge/Capacity" then
        SuQingFreshnessFridge=SuQingFreshnessFridge or {}
        SuQingFreshnessFridge.Capacity={Install=function() return true end,IsReady=function() return true end}
    end
    return true
end
local callbacks={}
Events=setmetatable({}, {__index=function(t,key)
    callbacks[key]={}
    local event={Add=function(fn) table.insert(callbacks[key],fn) end}
    rawset(t,key,event)
    return event
end})
function emit(name,...)
    for _,fn in ipairs(callbacks[name] or {}) do fn(...) end
end

Mock={clock=100,paused=false,sequence=0,grid={},allFoods={}}
function isClient() return false end
function isServer() return false end
function isGamePaused() return Mock.paused end
function getTimestampMs() return 1793880000000+Mock.sequence end
function getGameTime() return {getWorldAgeHours=function() return Mock.clock end} end
function instanceof(value,kind) return type(value)=="table" and value.kind==kind end
function getText(key,...) return key end
SandboxVars={SuQingFreshnessFridge={Enabled=true,Capacity=200,RestoreHours=10,AllowRotten=true}}

function mockList(values)
    local result={values=values or {}}
    function result:size() return #self.values end
    function result:get(index) return self.values[index+1] end
    function result:add(value) table.insert(self.values,value) end
    function result:contains(value)
        for _,item in ipairs(self.values) do if item==value then return true end end
        return false
    end
    function result:remove(value)
        for index,item in ipairs(self.values) do
            if item==value then table.remove(self.values,index);return true end
        end
        return false
    end
    return result
end

Mock.process=mockList()
local function squareKey(x,y,z) return tostring(x)..":"..tostring(y)..":"..tostring(z) end
function getCell()
    return {
        getGridSquare=function(_,x,y,z) return Mock.grid[squareKey(x,y,z)] end,
        getProcessItems=function() return Mock.process end,
    }
end

function Mock.container(owner,kind)
    local result={owner=owner,type=kind or "fridge",items=mockList(),capacity=200,powered=true}
    function result:getParent() return self.owner end
    function result:getType() return self.type end
    function result:getContainingItem() return self.bag end
    function result:getCapacity() return self.capacity end
    function result:setCapacity(value) self.capacity=value end
    function result:getItems() return self.items end
    function result:isPowered() return self.powered end
    function result:AddItem(value) self.items:add(value);value.container=self;return value end
    function result:Remove(value) self.items:remove(value);if value.container==self then value.container=nil end end
    return result
end

function Mock.fridge(name)
    Mock.sequence=Mock.sequence+1
    local result={md={},spriteName=name or "suqing_freshness_fridge_01_0",containerCount=1}
    local square={x=Mock.sequence,y=5,z=0,objects=mockList({result})}
    local chunk={}
    function square:getX() return self.x end
    function square:getY() return self.y end
    function square:getZ() return self.z end
    function square:getObjects() return self.objects end
    function square:getChunk() return chunk end
    result.square=square
    result.container=Mock.container(result)
    function result:getSprite() return {getName=function() return self.spriteName end} end
    function result:getModData() return self.md end
    function result:hasModData() return next(self.md)~=nil end
    function result:getContainerCount() return self.containerCount end
    function result:getContainer() return self.container end
    function result:getContainerByIndex(index) if index==0 then return self.container end end
    function result:getSquare() return self.square end
    function result:getChunk() return self.square:getChunk() end
    function result:transmitModData() self.transmitted=(self.transmitted or 0)+1 end
    function result:getObjectIndex() return self.removed and -1 or 0 end
    Mock.grid[squareKey(square.x,square.y,square.z)]=square
    return result
end

function Mock.unload(object)
    local square=object.square
    Mock.grid[squareKey(square.x,square.y,square.z)]=nil
end
function Mock.reload(object)
    local square=object.square
    Mock.grid[squareKey(square.x,square.y,square.z)]=square
end

FoodIndex={}
function Mock.nativeAge(food)
    food.nativeCalls=food.nativeCalls+1
    if food.lastAged>Mock.clock then food.lastAged=Mock.clock end
    food.age=food.age+math.max(0,Mock.clock-food.lastAged)/24*food.nativeRate
    food.lastAged=Mock.clock
end
FoodIndex.updateAge=Mock.nativeAge
Food={class="MockFoodClass"}
__classmetatables={[Food.class]={__index=FoodIndex}}
function Mock.food(container,age,fresh,rotten)
    Mock.sequence=Mock.sequence+1
    local result={kind="Food",md={},id=Mock.sequence,fullType="Base.Apple",age=age or 6,
        fresh=fresh or 5,rotten=rotten or 10,lastAged=Mock.clock,nativeRate=0.2,nativeCalls=0,
        cooked=false,burnt=false,fertilized=false,portion=0.4,calories=123,poison=9,tainted=true}
    function result:getID() return self.id end
    function result:getFullType() return self.fullType end
    function result:getModData() return self.md end
    function result:getContainer() return self.container end
    function result:getAge() return self.age end
    function result:setAge(value) self.age=self.float32 and nativeFloat32(value) or value end
    function result:getLastAged() return self.lastAged end
    function result:setLastAged(value) self.lastAged=value end
    function result:getOffAge() return self.fresh end
    function result:getOffAgeMax() return self.rotten end
    function result:isCooked() return self.cooked end
    function result:isBurnt() return self.burnt end
    function result:isFertilized() return self.fertilized end
    function result:isRotten() return self.age>=self.rotten end
    function result:getReplaceOnRotten() return self.replaceOnRotten end
    function result:setReplaceOnRotten(value) self.replaceOnRotten=value end
    setmetatable(result,{__index=FoodIndex})
    if container then container:AddItem(result) end
    Mock.allFoods[#Mock.allFoods+1]=result
    Mock.process:add(result)
    return result
end

ISTransferAction={transferItem=function(self,player,item,source,destination)
    if self and self.failBefore then error("injected transfer before mutation") end
    source:Remove(item)
    destination:AddItem(item)
    if self and self.failAfter then error("injected transfer after mutation") end
    return item
end}

function Mock.reset()
    if SuQingFreshnessFridge and SuQingFreshnessFridge.Runtime then
        SuQingFreshnessFridge.Runtime.Stop()
        SuQingFreshnessFridge.pending=setmetatable({}, {__mode="k"})
    end
    Mock.clock=100;Mock.paused=false;Mock.grid={};Mock.allFoods={};Mock.process=mockList()
    LiveWire=nil
    SandboxVars={SuQingFreshnessFridge={Enabled=true,Capacity=200,RestoreHours=10,AllowRotten=true}}
end

function Mock.start(object)
    local C=SuQingFreshnessFridge
    if object then C.RegisterObject(object) end
    emit("OnGameStart")
end

function Mock.step(hours,options)
    options=options or {}
    emit("OnTickEvenPaused")
    if Mock.paused then return end
    if options.native~=false then
        for _,food in ipairs(Mock.allFoods) do
            if food.container then
                Mock.nativeAge(food)
                if options.removeRotten and food:isRotten() then
                    food.container:Remove(food);food.deleted=true
                end
            end
        end
    end
    Mock.clock=Mock.clock+hours
    if options.player~=false then emit("OnPlayerUpdate",{}) end
    if options.post~=false then emit("OnTick") end
end

return "runtime mock bootstrap ready"
