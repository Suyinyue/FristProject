-- ====================================================================
-- items/ItemBehaviors.lua
-- 物品使用行为（策略模式）
--
-- 每种行为一个函数，输入 ctx：
--   ctx.player            Player
--   ctx.stack             ItemStack（当前选中的那一堆）
--   ctx.slotIndex         integer 快捷栏槽位下标
--   ctx.blockInteraction  BlockInteraction（需要射线/放置时用）
--   ctx.projectiles       ProjectileManager|nil（弓箭）
--   ctx.world             World
--
-- 返回 true = 已使用（可能消耗物品 / 耐久），false = 该物品右键无行为。
-- 方块放置不在这里：BlockInteraction 直接处理（它还要算朝向 / 上下半）。
-- ====================================================================

local Config = require("config.GameConfig")
local Blocks = require("data.BlockRegistry")
local ItemStack = require("items.ItemStack")
local AudioManager = require("core.AudioManager")

local ItemBehaviors = {}

-- ====================================================================
-- 通用：替换手上的物品（桶 / 药水等需要转换的）
-- ====================================================================

---@param player Player
---@param slotIndex integer
---@param itemId string
---@param count integer|nil
local function replaceHeld(player, slotIndex, itemId, count)
    local inventory = player:getInventory()
    local stack = ItemStack.new(itemId, count or 1)
    inventory:setStack(slotIndex, stack)
    inventory:markDirty()
end

-- ====================================================================
-- 食物
-- ====================================================================

---饥饿值和血量都满了就不浪费食物
---@param player Player
---@return boolean
local function isPlayerFull(player)
    return player:getHunger() >= player:getMaxHunger() and player:getHealth() >= player:getMaxHealth()
end

---@param ctx table
---@return boolean
local function useFood(ctx)
    local def = ctx.stack:getDefinition()
    if not def then
        return false
    end
    if isPlayerFull(ctx.player) then
        return false
    end

    local player = ctx.player
    local saturation = def.foodSaturation
        or (Config.FoodSaturation and Config.FoodSaturation[def.id])
        or 0
    player:eat(def.foodHunger or 0, def.foodHeal or 0, saturation)
    player:consumeSelected(1)
    player:swingArm()
    print(string.format("[Items] 食用 %s（饥饿 %d/%d）", def.name, player:getHunger(), player:getMaxHunger()))
    return true
end

-- ====================================================================
-- 药水
-- ====================================================================

---@param ctx table
---@return boolean
local function usePotion(ctx)
    local def = ctx.stack:getDefinition()
    if not def or not def.effect then
        return false
    end

    local effect = def.effect
    if effect.kind == "heal" then
        ctx.player:heal(effect.value)
    else
        ctx.player:applyEffect(effect.kind, effect.value, effect.duration or 30)
    end

    ctx.player:consumeSelected(1)
    ctx.player:swingArm()
    print("[Items] 使用药水：" .. def.name)
    return true
end

-- ====================================================================
-- 护甲：右键直接穿上（装备栏已满则交换）
-- ====================================================================

---@param ctx table
---@return boolean
function ItemBehaviors.equipArmor(ctx)
    local def = ctx.stack:getDefinition()
    if not def or def.behavior ~= "armor" or not def.equipSlot then
        return false
    end

    local inventory = ctx.player:getInventory()
    local targetIndex = inventory.ARMOR_SLOTS[def.equipSlot]
    if not targetIndex then
        return false
    end

    local current = inventory:getStack(targetIndex)
    inventory:setStack(targetIndex, ctx.stack)
    inventory:setStack(ctx.slotIndex, current)
    inventory:markDirty()
    print("[Items] 装备 " .. def.name)
    return true
end

-- ====================================================================
-- 桶
-- ====================================================================

---@param ctx table
---@return boolean
local function useBucket(ctx)
    local bi = ctx.blockInteraction
    if not bi then
        return false
    end

    local bx, by, bz = bi:getTargetBlock()
    if not bx then
        return false
    end

    if ctx.world:getBlock(bx, by, bz) ~= Blocks.WATER then
        return false
    end

    ctx.world:setBlock(bx, by, bz, Blocks.AIR)
    replaceHeld(ctx.player, ctx.slotIndex, "water_bucket", 1)
    ctx.player:swingArm()
    print("[Items] 装了一桶水")
    return true
end

---@param ctx table
---@return boolean
local function useWaterBucket(ctx)
    local bi = ctx.blockInteraction
    if not bi then
        return false
    end

    local bx, by, bz, px, py, pz = bi:getTargetBlock()
    if not bx or not px then
        return false
    end
    if py < 0 or py >= Config.World.WORLD_HEIGHT then
        return false
    end
    if ctx.world:getBlock(px, py, pz) ~= Blocks.AIR then
        return false
    end

    ctx.world:setBlock(px, py, pz, Blocks.WATER)
    replaceHeld(ctx.player, ctx.slotIndex, "bucket", 1)
    ctx.player:swingArm()
    print("[Items] 放置水源")
    return true
end

-- ====================================================================
-- 弓
-- ====================================================================

---@param ctx table
---@return boolean
local function useBow(ctx)
    local inventory = ctx.player:getInventory()
    if not inventory:hasItem("arrow", 1) then
        print("[Items] 没有箭了")
        return false
    end
    if not ctx.projectiles then
        return false
    end

    inventory:removeItem("arrow", 1)
    local eye = ctx.player:getEyePosition()
    local dir = ctx.player:getLookDirection()
    -- 伤害按玩家当前攻击力计算（含武器加成）
    ctx.projectiles:spawnArrow(eye + dir * 1.2, dir, ctx.player:getAttack())
    inventory:damageSlot(ctx.slotIndex, 1)
    ctx.player:swingArm()
    AudioManager.play("bow_release")
    return true
end

-- ====================================================================
-- 锄头（耕地）
-- ====================================================================

---@param ctx table
---@return boolean
local function useHoe(ctx)
    local bi = ctx.blockInteraction
    if not bi then
        return false
    end
    local bx, by, bz = bi:getTargetBlock()
    if not bx then
        return false
    end
    local block = ctx.world:getBlock(bx, by, bz)
    if block ~= Blocks.DIRT and block ~= Blocks.GRASS then
        return false
    end
    ctx.world:setBlock(bx, by, bz, Blocks.FARMLAND)
    ctx.player:damageSelected(1)
    ctx.player:swingArm()
    print("[Farming] 耕地")
    return true
end

-- ====================================================================
-- 小麦种子（在耕地上种植）
-- ====================================================================

---@param ctx table
---@return boolean
local function useSeed(ctx)
    local bi = ctx.blockInteraction
    if not bi then
        return false
    end
    local bx, by, bz = bi:getTargetBlock()
    if not bx then
        return false
    end
    if ctx.world:getBlock(bx, by, bz) ~= Blocks.FARMLAND then
        return false
    end
    if by + 1 >= Config.World.WORLD_HEIGHT then
        return false
    end
    if ctx.world:getBlock(bx, by + 1, bz) ~= Blocks.AIR then
        return false
    end
    ctx.world:setBlock(bx, by + 1, bz, Blocks.WHEAT_CROP, 0)
    -- 种植是直接 setBlock，绕过 placeBlock 的 notifyBlockChanged，这里显式登记作物
    if ctx.farming then
        ctx.farming:registerCrop(bx, by + 1, bz)
    end
    ctx.player:consumeSelected(1)
    ctx.player:swingArm()
    print("[Farming] 种植小麦")
    return true
end

-- ====================================================================
-- 钓鱼竿
-- ====================================================================

---@param ctx table
---@return boolean
local function useFishingRod(ctx)
    local fishing = ctx.fishing
    if not fishing then
        return false
    end
    if fishing:isCasting() then
        fishing:reel()
        ctx.player:damageSelected(Config.Fishing.ROD_DURABILITY_COST or 1)
        ctx.player:swingArm()
        return true
    end

    local bi = ctx.blockInteraction
    if not bi then
        return false
    end
    local bx, by, bz = bi:getTargetBlock()
    if not bx then
        return false
    end
    if ctx.world:getBlock(bx, by, bz) ~= Blocks.WATER then
        return false
    end
    fishing:cast(bx, by, bz)
    ctx.player:swingArm()
    return true
end

-- ====================================================================
-- 分发
-- ====================================================================

---使用当前选中物品
---@param ctx table
---@return boolean handled
function ItemBehaviors.use(ctx)
    if not ctx or not ctx.player or not ctx.stack then
        return false
    end
    local def = ctx.stack:getDefinition()
    if not def then
        return false
    end

    if def.behavior == "food" then
        return useFood(ctx)
    elseif def.behavior == "potion" then
        return usePotion(ctx)
    elseif def.behavior == "armor" then
        return ItemBehaviors.equipArmor(ctx)
    elseif def.behavior == "bucket" then
        return useBucket(ctx)
    elseif def.behavior == "water_bucket" then
        return useWaterBucket(ctx)
    elseif def.behavior == "bow" then
        return useBow(ctx)
    elseif def.behavior == "fishing_rod" then
        return useFishingRod(ctx)
    elseif def.toolType == "hoe" then
        return useHoe(ctx)
    elseif def.id == "wheat_seed" then
        return useSeed(ctx)
    end

    -- material / weapon / tool / block：右键无特殊行为
    return false
end

return ItemBehaviors
