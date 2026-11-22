-- ====================================================================
-- data/BlockHarvest.lua
-- 方块采集规则（工具要求 / 掉落物）
--
--   requiredTool：正常采集需要的工具类型；手上没有对应工具仍能破坏方块，
--                 但不会掉落物品（和 Minecraft 一致）
--   dropFor：破坏后掉落的物品 ID（nil = 不掉落）
-- ====================================================================

local Blocks = require("data.BlockRegistry")

local BlockHarvest = {}

-- 工具要求
---@type table<integer, string>
local REQUIRED_TOOL = {
    -- 石质方块 → 镐
    [Blocks.STONE] = "pickaxe",
    [Blocks.COBBLESTONE] = "pickaxe",
    [Blocks.MOSSY_COBBLESTONE] = "pickaxe",
    [Blocks.STONE_BRICKS] = "pickaxe",
    [Blocks.SANDSTONE] = "pickaxe",
    [Blocks.OBSIDIAN] = "pickaxe",
    [Blocks.BRICKS] = "pickaxe",
    [Blocks.BOOKSHELF] = "axe",
    [Blocks.COAL_ORE] = "pickaxe",
    [Blocks.IRON_ORE] = "pickaxe",
    [Blocks.GOLD_ORE] = "pickaxe",
    [Blocks.DIAMOND_ORE] = "pickaxe",
    [Blocks.REDSTONE_ORE] = "pickaxe",
    [Blocks.LAPIS_ORE] = "pickaxe",
    [Blocks.GLOWSTONE] = "pickaxe",
    [Blocks.FURNACE] = "pickaxe",
    [Blocks.ICE] = "pickaxe",
    [Blocks.WALL_COBBLESTONE] = "pickaxe",
    [Blocks.ADAMANT] = "pickaxe",       -- 金刚岩（防御塔基座）
    [Blocks.FLAME_STONE] = "pickaxe",   -- 火焰石（防御塔攻击台）

    -- 木质方块 → 斧
    [Blocks.WOOD] = "axe",
    [Blocks.PLANKS] = "axe",
    [Blocks.CRAFTING_TABLE] = "axe",
    [Blocks.FENCE_WOOD] = "axe",
    [Blocks.DOOR_WOOD] = "axe",
    [Blocks.TRAPDOOR_WOOD] = "axe",

    -- 泥土 / 沙砾类 → 铲
    [Blocks.DIRT] = "shovel",
    [Blocks.GRASS] = "shovel",
    [Blocks.SNOWY_GRASS] = "shovel",
    [Blocks.SAND] = "shovel",
    [Blocks.GRAVEL] = "shovel",
    [Blocks.CLAY] = "shovel",
    [Blocks.SNOW_BLOCK] = "shovel",
}

-- 掉落物（未列出的方块掉落自身方块物品）
---@type table<integer, string|nil>
local BLOCK_DROPS = {
    [Blocks.STONE] = "block:13",          -- 圆石
    [Blocks.GRASS] = "block:2",           -- 泥土
    [Blocks.SNOWY_GRASS] = "block:2",
    [Blocks.COAL_ORE] = "coal",
    [Blocks.IRON_ORE] = "raw_iron",
    [Blocks.GOLD_ORE] = "raw_gold",
    [Blocks.DIAMOND_ORE] = "diamond",
    [Blocks.LEAVES] = "block:45",         -- 树苗
}

-- 明确不掉的方块
---@type table<integer, boolean>
local NO_DROP = {
    [Blocks.TALL_GRASS] = true,
    [Blocks.BEDROCK] = true,
    [Blocks.LEAVES] = false,
}

---方块需要的工具类型
---@param blockId integer
---@return string|nil
function BlockHarvest.requiredTool(blockId)
    return REQUIRED_TOOL[blockId]
end

---手上工具能否正常采集该方块
---@param blockId integer
---@param heldTool string|nil
---@return boolean
function BlockHarvest.canHarvest(blockId, heldTool)
    local need = REQUIRED_TOOL[blockId]
    if not need then
        return true
    end
    return heldTool == need
end

---破坏后的掉落物 ID
---@param blockId integer
---@return string|nil itemId
function BlockHarvest.dropFor(blockId)
    if NO_DROP[blockId] then
        return nil
    end
    if BLOCK_DROPS[blockId] then
        return BLOCK_DROPS[blockId]
    end
    -- 默认掉落自身方块物品（有注册才掉）
    return "block:" .. blockId
end

return BlockHarvest
