local C=SuQingFreshnessFridge
local B=C.Building
local checks=0
local function check(value,message) checks=checks+1; assert(value,message) end
local function container(kind)
    return {kind=kind or "fridge",items={"food"},
        getType=function(self) return self.kind end,
        setCapacity=function(self,v) self.capacity=v end,
        setParent=function(self,v) self.parent=v end,
        setExplored=function(self,v) self.explored=v end,
    }
end
local function object(sprite,count)
    local o={sprite=sprite or "suqing_freshness_fridge_01_0",md={SuQingFreshnessFridge={on=false,schema=1}},
        containers={},created=0,name="fridge",health=211,maxHealth=300,
        getSprite=function(self) return {getName=function() return self.sprite end} end,
        getContainerCount=function(self) return #self.containers end,
        getContainerByIndex=function(self,index) return self.containers[index+1] end,
        createContainersFromSpriteProperties=function(self)
            self.created=self.created+1;self.containers[1]=container()
        end,
        setExplored=function(self,v) self.explored=v end,
        setIsContainer=function() error("destructive native setter called") end,
        getModData=function(self) return self.md end,
        hasModData=function() return true end,
        getName=function(self) return self.name end,
        getHealth=function(self) return self.health end,
        getMaxHealth=function(self) return self.maxHealth end,
        getThumpSound=function() return "ZombieThumpMetal" end,
        getCustomColor=function() return nil end,
        getLightSourceRadius=function() return 0 end,
        canBeLockByPadlock=function() return false end,
        isLockedByPadlock=function() return false end,
        getLockedByCode=function() return 0 end,
        setName=function(self,v) self.name=v end,
        setHealth=function(self,v) self.health=v end,
        setMaxHealth=function(self,v) self.maxHealth=v end,
        setThumpSound=function(self,v) self.thumpSound=v end,
        getRenderYOffset=function() return 0 end,
        isObjectNoContainerOrEmpty=function(self)
            for _,c in ipairs(self.containers) do if #c.items>0 then return false end end
            return true
        end,
    }
    for index=1,(count==nil and 1 or count) do o.containers[index]=container() end
    return o
end
local original=object()
local food=original.containers[1].items
local md=original.md
check(B.EnsureObject(original),"existing fridge recognized")
check(B.EnsureObject(original),"repeat initialization succeeds")
check(original.created==0,"existing container never reconstructed")
check(original.containers[1].items==food and food[1]=="food","food preserved")
check(original.md==md and md.SuQingFreshnessFridge.on==false,"full state retained")
check(original.containers[1].capacity==200,"default capacity")
check(original.containers[1].parent==original,"parent consistent")
check(original.containers[1].explored and original.explored,"no generated loot")
for _,capacity in ipairs({50,201.9,1000,5000,-2}) do
    C.capacity=capacity;B.EnsureObject(original)
    check(original.containers[1].capacity==math.floor(math.max(50,math.min(1000,capacity))),"capacity clamped "..capacity)
end
C.capacity=0/0;B.EnsureObject(original)
check(original.containers[1].capacity==200,"NaN capacity falls back")
C.capacity=math.huge;B.EnsureObject(original)
check(original.containers[1].capacity==200,"infinite capacity falls back")
C.capacity=200
local blank=object(nil,0)
check(B.EnsureObject(blank),"new built object receives a container")
check(B.EnsureObject(blank) and blank.created==1,"only one new container")
local other=object("appliances_refrigeration_01_25")
check(not B.EnsureObject(other) and other.created==0 and other.containers[1].capacity==nil,"vanilla fridge untouched")
local freezer=object(nil,2);freezer.containers[2].kind="freezer"
check(not B.EnsureObject(freezer),"unexpected freezer rejects processing")
check(#freezer.containers==2 and freezer.containers[2].items[1]=="food","unexpected freezer contents never removed")
local wrong=object();wrong.containers[1].kind="crate"
check(not B.EnsureObject(wrong) and wrong.containers[1].items[1]=="food","wrong container is preserved and rejected")
for index=0,3 do
    local built=object("suqing_freshness_fridge_01_"..index)
    local before=C.registered
    B.OnCreate({thumpable=built})
    check(C.registered==before+1 and C.lastObject==built,"on-create registers facing "..index)
end
-- Execute the actual vanilla state-copy functions rather than our own clone.
local carried={}
ISMoveableSpriteProps:saveThumpableParameters(carried,original)
local placed=object("suqing_freshness_fridge_01_3")
placed.md={};placed.containers[1].items={}
ISMoveableSpriteProps:restoreThumpableParameters(carried,placed)
B.OnObjectAdded(placed)
check(placed.md.SuQingFreshnessFridge.on==false,"native pickup/place preserves disabled state")
check(placed.health==211 and placed.maxHealth==300,"native pickup/place preserves durability")
check(placed.md.SuQingFreshnessFridge~=original.md.SuQingFreshnessFridge,"native state copy independent")
check(placed.containers[1].capacity==200 and placed.created==0,"placed container set without rebuilding")
local props=setmetatable({isMoveable=true,weight=10,type="Object"},{__index=ISMoveableSpriteProps})
local square={kind="IsoGridSquare"}
local player={kind="IsoGameCharacter",getInventory=function() return {hasRoomFor=function() return true end} end}
props.hasRequiredSkill=function() return true end
check(not props:canPickUpMoveableInternal(player,square,original,false),"native pickup blocks food-filled fridge")
original.containers[1].items={}
check(props:canPickUpMoveableInternal(player,square,original,false),"native pickup permits cleared fridge")
check(#Events.OnObjectAdded.callbacks==1 and #Events.LoadGridsquare.callbacks==1,"discovery hooks registered once")
-- Native timed-action cancellation must not call the entity payment/create
-- path. Native entity completion pays once; rejected payment creates nothing.
local nativeCreateCalls,nativePayCalls,nativeDestroyCalls=0,0,0
local action={item={ghostSprite={},onTimedActionStop=function() end,
    create=function() nativeCreateCalls=nativeCreateCalls+1 end},
    character={},transactionId=1}
ISBuildAction.stop(action)
check(action.stopped and C.lastCancelled==true,"native action stop signals cancellation")
check(nativeCreateCalls==0,"native cancel never enters entity create/payment")
local sq={}
getWorld=function() return {getCell=function() return {getGridSquare=function() return sq end} end} end
getCell=function() return {getGridSquare=function() return sq end} end
local tile={getSpriteName=function() return "suqing_freshness_fridge_01_0" end}
local face={getzLayers=function() return 1 end,getWidth=function() return 1 end,getHeight=function() return 1 end,
    getTileInfo=function() return tile end}
local paid=true
local selected=true
local recipeData={luaCallOnCreate=function() end,getRecipe=function() return {} end,
    processDestroyAndUsedItems=function() nativeDestroyCalls=nativeDestroyCalls+1 end}
local cursor={character={isBuildCheat=function() return false end},
    getFace=function() return face end,getOpenFace=function() return nil end,
    isValid=function() return selected end,updateModData=function() end,
    buildPanelLogic={performCurrentRecipe=function() nativePayCalls=nativePayCalls+1;return paid end,
        getRecipeDataInProgress=function() return recipeData end},
    setInfo=function() nativeCreateCalls=nativeCreateCalls+1 end}
selected=false
ISBuildIsoEntity.create(cursor,0,0,0,false,"suqing_freshness_fridge_01_0")
check(nativePayCalls==0 and nativeCreateCalls==0,"native invalid placement never pays or creates")
selected=true;paid=false
ISBuildIsoEntity.create(cursor,0,0,0,false,"suqing_freshness_fridge_01_0")
check(nativePayCalls==1 and nativeCreateCalls==0 and nativeDestroyCalls==0,"native failed payment never builds or destroys inputs")
paid=true
ISBuildIsoEntity.create(cursor,0,0,0,false,"suqing_freshness_fridge_01_0")
check(nativePayCalls==2 and nativeCreateCalls==1 and nativeDestroyCalls==1,"native successful completion pays and builds once")
print("BUILDING_LUA assertions="..checks.." failures=0")
return "BUILDING_LUA assertions="..checks.." failures=0"
