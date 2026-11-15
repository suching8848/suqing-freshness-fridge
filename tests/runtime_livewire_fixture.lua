-- Engine doubles for the unmodified Live Wire modules passed by runtime_run_tests.py.
local originalRequire=require
function require(name)
    if string.find(name,"TimedActions/",1,true) or string.find(name,"Fluids/",1,true)
       or string.find(name,"RadioCom/",1,true) then
        local class=string.match(name,"([^/]+)$")
        _G[class]=_G[class] or setmetatable({}, {__index=function() return function() return true end end})
    end
    return originalRequire(name)
end

local data={}
ModData={getOrCreate=function(key) data[key]=data[key] or {};return data[key] end}
function getSandboxOptions() return nil end
function triggerEvent() end

local originalCell=getCell
function getCell()
    local cell=originalCell()
    function cell:getChunkForGridSquare() return nil end
    return cell
end

LiveWire={
    Config={tileRange=function() return 2 end,verticalRange=function() return 0 end},
    Consumption={watts=function() return 100 end},
    Demand={category=function() return "fridge" end},
    Registry={ready=true,readOnly=false,data={powerHistory={}},inverters={},devicesInChunk=function() return {} end},
}

function Mock.wireFridge()
    local object=Mock.fridge()
    object.kind="IsoObject"
    function object:couldBePoweredByGenerator() return false end
    function object:checkHaveElectricity() end
    local container=object:getContainer()
    function container:isFridge() return self.type=="fridge" end
    function container:isFreezer() return false end
    function container:setType(value) self.type=value end
    function object:getContainerByType(value)
        if container:getType()==value then return container end
    end
    local chunk=object:getChunk()
    function chunk:removeObjectPoweredByGenerator() end
    function chunk:getMinLevel() return 0 end
    function chunk:getMaxLevel() return 0 end
    function chunk:getGridSquare(x,y,z)
        local square=object:getSquare()
        if x==square:getX()%8 and y==square:getY()%8 and z==square:getZ() then return square end
    end
    return object
end

function Mock.wireFood(container)
    local food=Mock.food(container,0,5,10)
    function food:getFreezingTime() return 0 end
    function food:isFrozen() return false end
    function food:canBeFrozen() return false end
    function food:setFreezingTime() end
    function food:setFrozen() end
    return food
end
