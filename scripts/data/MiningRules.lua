-- ====================================================================
-- data/MiningRules.lua
-- 方块硬度 / 持续挖掘时间 / 工具效率
--
--   baseTime：徒手 + 正确工具基准下的挖掘秒数
--   实际时间 = baseTime / 工具效率
--   工具效率：匹配工具 1.0；错误工具 0.35；徒手 0.2
--   不可破坏方块：基岩、水、岩浆
-- ====================================================================

local Blocks = require("data.BlockRegistry")
local BlockHarvest = require("data.BlockHarvest")

local MiningRules = {}

-- 逐方块基础时间（秒）；未列出的用 DEFAULT_TIME
local BASE_TIME = {
    [Blocks.DIRT] = 0.3,
    [Blocks.GRASS] = 0.3,
    [Blocks.SNOWY_GRASS] = 0.3,
    [Blocks.SAND] = 0.3,
    [Blocks.GRAVEL] = 0.35,
    [Blocks.CLAY] = 0.35,
    [Blocks.SNOW_BLOCK] = 0.3,

    [Blocks.WOOD] = 1.0,
    [Blocks.PLANKS] = 0.9,
    [Blocks.CRAFTING_TABLE] = 1.0,
    [Blocks.FENCE_WOOD] = 0.9,
    [Blocks.DOOR_WOOD] = 0.9,
    [Blocks.TRAPDOOR_WOOD] = 0.9,
    [Blocks.BOOKSHELF] = 1.2,

    [Blocks.STONE] = 1.5,
    [Blocks.COBBLESTONE] = 1.5,
    [Blocks.MOSSY_COBBLESTONE] = 1.5,
    [Blocks.STONE_BRICKS] = 1.5,
    [Blocks.SANDSTONE] = 1.4,
    [Blocks.BRICKS] = 1.6,
    [Blocks.OBSIDIAN] = 5.0,
    [Blocks.WALL_COBBLESTONE] = 1.5,
    [Blocks.FURNACE] = 1.8,

    [Blocks.COAL_ORE] = 2.0,
    [Blocks.IRON_ORE] = 2.0,
    [Blocks.GOLD_ORE] = 2.0,
    [Blocks.COPPER_ORE] = 2.0,
    [Blocks.LAPIS_ORE] = 2.0,
    [Blocks.REDSTONE_ORE] = 2.2,
    [Blocks.DIAMOND_ORE] = 3.0,
    [Blocks.EMERALD_ORE] = 3.0,
    [Blocks.ADAMANT_ORE] = 3.0,
    [Blocks.FLAME_STONE_ORE] = 3.0,
    [Blocks.GLOWSTONE] = 0.6,

    [Blocks.ADAMANT] = 4.0,
    [Blocks.FLAME_STONE] = 2.0,

    [Blocks.GLASS] = 0.4,
    [Blocks.ICE] = 0.5,
    [Blocks.LEAVES] = 0.2,
    [Blocks.CHEST] = 1.2,
    [Blocks.ENCHANTING_TABLE] = 2.0,
    [Blocks.FARMLAND] = 0.5,
    [Blocks.WHEAT_CROP] = 0.05,
    [Blocks.REDSTONE_DUST] = 0.05,
    [Blocks.REDSTONE_TORCH] = 0.1,
    [Blocks.REDSTONE_BLOCK] = 1.5,
    [Blocks.LEVER] = 0.4,
    [Blocks.STONE_BUTTON] = 0.4,
    [Blocks.REDSTONE_LAMP] = 0.6,
    [Blocks.TALL_GRASS] = 0.1,
    [Blocks.ROSE] = 0.1,
    [Blocks.FLOWER_YELLOW] = 0.1,
    [Blocks.FLOWER_BLUE] = 0.1,
    [Blocks.SAPLING] = 0.1,
    [Blocks.MUSHROOM_RED] = 0.1,
    [Blocks.MUSHROOM_BROWN] = 0.1,
    [Blocks.TORCH] = 0.1,
    [Blocks.CACTUS] = 0.5,
}

local DEFAULT_TIME = 1.0

-- 不可破坏
local UNBREAKABLE = {
    [Blocks.BEDROCK] = true,
    [Blocks.WATER] = true,
    [Blocks.LAVA] = true,
}

---@param blockId integer
---@return boolean
function MiningRules.isUnbreakable(blockId)
    return UNBREAKABLE[blockId] == true
end

---基础挖掘时间（秒）
---@param blockId integer
---@return number
function MiningRules.baseTime(blockId)
    return BASE_TIME[blockId] or DEFAULT_TIME
end

---工具效率
---@param blockId integer
---@param heldTool string|nil
---@return number
function MiningRules.toolEfficiency(blockId, heldTool)
    local required = BlockHarvest.requiredTool(blockId)
    if not required then
        -- 徒手可挖的方块：工具没有额外加成
        return 1.0
    end
    if heldTool == required then
        return 1.0
    end
    if heldTool then
        return 0.35
    end
    return 0.2
end

---实际挖掘时间（秒）
---@param blockId integer
---@param heldTool string|nil
---@return number
function MiningRules.miningTime(blockId, heldTool)
    if MiningRules.isUnbreakable(blockId) then
        return math.huge
    end
    local base = MiningRules.baseTime(blockId)
    local eff = MiningRules.toolEfficiency(blockId, heldTool)
    if eff <= 0 then
        eff = 0.01
    end
    return base / eff
end

---进度 → 裂纹阶段 0..4
---@param progress number 0..1
---@return integer
function MiningRules.crackStage(progress)
    if progress <= 0 then return 0 end
    if progress < 0.25 then return 1 end
    if progress < 0.5 then return 2 end
    if progress < 0.75 then return 3 end
    return 4
end

return MiningRules
