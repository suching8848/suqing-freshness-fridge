-- Headless mock surfaces only. No game state or live UI is touched.
require=function() end
SuQingFreshnessFridge=nil
SandboxVars={SuQingFreshnessFridge={Capacity=200}}
CAPACITY_MP=false
isClient=function() return CAPACITY_MP end
isServer=function() return false end
CharacterTrait=setmetatable({ORGANIZED="organized",DISORGANIZED="disorganized"},{__index=function(_,key) return key end})
ItemType={KEY_RING="keyring"}
ItemTag={KEY_RING="keyring"}
function instanceof(object,name)
    if type(object)~="table" then return false end
    if name=="InventoryItem" then return object.inventoryItem==true end
    return object.kind==name
end
local function derive(self)
    local class={}
    setmetatable(class,{__index=self})
    return class
end
ISBaseTimedAction={derive=derive}
ISBaseObject={derive=derive}
ISInventoryPage={}
ISInventoryPane={}
ISInventoryPaneDraggedItems={}
DraggedItems=ISInventoryPaneDraggedItems
ISMouseDrag={dragging={}}
ISInventoryPane.getActualItems=function(items) return items end
ISInventoryPane.sortItemsByTypeAndWeight=function() end
getTimestampMs=function() return 0 end
getCore=function() return {getGameMode=function() return "Sandbox" end} end
table.wipe=function(t) for key in pairs(t) do t[key]=nil end end
luautils={walkToContainer=function() return true end}
corpseStorageCheck={isPlayerGrabbingCorpseItem=function() return false end}

ItemContainer={class="ItemContainer",floatingPointCorrection=function(weight) return math.floor(weight*100+0.5)/100 end}
CAPACITY_NATIVE_CALLS={}
CAPACITY_INDEX={}
__classmetatables={[ItemContainer.class]={__index=CAPACITY_INDEX}}
local function native(name,fn)
    CAPACITY_INDEX[name]=function(self,...)
        CAPACITY_NATIVE_CALLS[name]=(CAPACITY_NATIVE_CALLS[name] or 0)+1
        return fn(self,...)
    end
end
native("getCapacity",function(self,...) return self.nativeCapacity or 100,"native",select("#",...) end)
native("getEffectiveCapacity",function(self) return self.nativeCapacity or 100 end)
native("getMaxWeight",function(self,...) return self.nativeCapacity or 100,"native",select("#",...) end)
native("getFreeCapacity",function(self) return math.max((self.nativeCapacity or 100)-self:getCapacityWeight(),0) end)
native("isFull",function(self) return self:getCapacityWeight()>=(self.nativeCapacity or 100) end)
native("hasRoomFor",function(self,...)
    local count=select("#",...)
    local first,second=...
    local incoming=count==1 and first or second
    local weight=type(incoming)=="number" and incoming or incoming:getUnequippedWeight()
    return self:getCapacityWeight()+weight<=(self.nativeCapacity or 100),"native",count
end)

function CAPACITY_Container(kind,parent)
    local c={kind="ItemContainer",type=kind or "fridge",parent=parent,items={},baseWeight=0,
        getType=function(self) return self.type end,
        getParent=function(self) return self.parent end,
        getContainingItem=function() return nil end,
        getContainerCount=function() return 1 end,
        getCapacityWeight=function(self)
            local total=self.baseWeight
            for _,item in ipairs(self.items) do total=total+item.weight end
            return total
        end,
        contains=function(self,item) for _,owned in ipairs(self.items) do if owned==item then return true end end return false end,
        isInside=function(self,item) return item.recursive==true end,
        isItemAllowed=function(self,item) return item.allowed~=false end,
        isInCharacterInventory=function(self,character) return self.parent==character end,
        isExistYet=function() return true end,
        isRemoveItemAllowed=function() return true end,
        isVehicleSeat=function() return false end,
        hasWorldItem=function() return false end,
        getItems=function(self) return {size=function() return #self.items end,get=function(_,index) return self.items[index+1] end} end,
        DoRemoveItem=function(self,item)
            for i,v in ipairs(self.items) do if v==item then table.remove(self.items,i);break end end
        end,
        AddItem=function(self,item) table.insert(self.items,item);item.container=self;return item end,
    }
    setmetatable(c,{__index=CAPACITY_INDEX})
    return c
end

function CAPACITY_Object(sprite)
    local object={kind="IsoThumpable",sprite=sprite or "suqing_freshness_fridge_01_0",md={},
        getSprite=function(self) return {getName=function() return self.sprite end} end,
        getContainerCount=function() return 1 end,
        getContainer=function(self) return self.container end,
        getContainerByIndex=function(self,index) if index==0 then return self.container end end,
        getModData=function(self) return self.md end,
    }
    object.container=CAPACITY_Container("fridge",object)
    return object
end

function CAPACITY_Player(trait)
    local character={kind="IsoGameCharacter",trait=trait,
        hasTrait=function(self,value) return self.trait==value end,
        getInventory=function(self) return self.inventory end,
        isWearingAwkwardGloves=function() return false end,
        isTimedActionInstant=function() return false end,
        removeAttachedItem=function() end,isEquipped=function() return false end,
    }
    character.inventory=CAPACITY_Container("inventory",character)
    return character
end

function CAPACITY_Item(source,weight)
    local item={inventoryItem=true,kind="Food",weight=weight or 1,container=source,
        getUnequippedWeight=function(self) return self.weight end,
        getActualWeight=function(self) return self.actualWeight or self.weight end,
        getContainer=function(self) return self.container end,
        getIsCraftingConsumed=function(self) return self.consumed==true end,
        isFavorite=function(self) return self.favorite==true end,
        isEquipped=function() return false end,
        isItemType=function() return false end,hasTag=function() return false end,
        getWorldItem=function() return nil end,getFullType=function() return "Base.Apple" end,
        getType=function() return "Apple" end,
    }
    if source then table.insert(source.items,item) end
    return item
end
