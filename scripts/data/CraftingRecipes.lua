-- ====================================================================
-- data/CraftingRecipes.lua
-- 合成配方（数据驱动）
--
-- 两种格式：
--   有序（shape）：shape 是若干行字符串，key 把字符映射到物品 ID
--   无序（shapeless）：ingredients 物品 ID 列表（每个消耗 1 个）
--
-- 物品 ID：
--   方块物品统一是 "block:<方块ID>"（见 items/ItemRegistry.lua）
-- ====================================================================

local CraftingRecipes = {}

---@type table[]
CraftingRecipes.recipes = {
    -- ==================== 基础材料 ====================
    {
        id = "planks_from_wood",
        shape = { "W" },
        key = { W = "block:4" },              -- 原木
        result = { id = "block:19", count = 4 }, -- 木板
    },
    {
        id = "stick_from_planks",
        shape = { "P", "P" },
        key = { P = "block:19" },
        result = { id = "stick", count = 4 },
    },
    {
        id = "crafting_table",
        shape = { "PP", "PP" },
        key = { P = "block:19" },
        result = { id = "block:22", count = 1 },
    },
    {
        id = "torch",
        shape = { "C", "S" },
        key = { C = "coal", S = "stick" },
        result = { id = "block:9", count = 4 },  -- 火把
    },
    {
        id = "torch_from_planks",
        shape = { "P", "S" },
        key = { P = "block:19", S = "stick" },
        result = { id = "block:9", count = 2 },
    },
    {
        id = "bread",
        shapeless = { "wheat", "wheat", "wheat" },
        result = { id = "bread", count = 1 },
    },
    {
        id = "bucket",
        shape = { "I I", " I " },
        key = { I = "iron_ingot" },
        result = { id = "bucket", count = 1 },
    },
    {
        id = "arrow",
        shape = { "I", "S", "F" },
        key = { I = "iron_ingot", S = "stick", F = "feather" },
        result = { id = "arrow", count = 4 },
    },
    -- 粗矿 → 锭（熔炉系统落地前的临时过渡配方）
    {
        id = "raw_iron_to_ingot",
        shapeless = { "raw_iron" },
        result = { id = "iron_ingot", count = 1 },
    },
    {
        id = "raw_gold_to_ingot",
        shapeless = { "raw_gold" },
        result = { id = "gold_ingot", count = 1 },
    },

    -- ==================== 武器 ====================
    {
        id = "sword",
        shape = { "I", "I", "S" },
        key = { I = "iron_ingot", S = "stick" },
        result = { id = "sword", count = 1 },
    },
    {
        id = "bow",
        shape = { " ST", "S T", " ST" },
        key = { S = "stick", T = "string" },
        result = { id = "bow", count = 1 },
    },

    -- ==================== 工具 ====================
    {
        id = "pickaxe",
        shape = { "III", " S ", " S " },
        key = { I = "iron_ingot", S = "stick" },
        result = { id = "pickaxe", count = 1 },
    },
    {
        id = "axe",
        shape = { "II ", "IS ", " S " },
        key = { I = "iron_ingot", S = "stick" },
        result = { id = "axe", count = 1 },
    },
    {
        id = "shovel",
        shape = { " I ", " S ", " S " },
        key = { I = "iron_ingot", S = "stick" },
        result = { id = "shovel", count = 1 },
    },

    -- ==================== 护甲（Design.md 物品内容）====================
    {
        id = "helmet",
        shape = { "III", "I I" },
        key = { I = "iron_ingot" },
        result = { id = "helmet", count = 1 },
    },
    {
        id = "chestplate",
        shape = { "I I", "III", "III" },
        key = { I = "iron_ingot" },
        result = { id = "chestplate", count = 1 },
    },
    {
        id = "leggings",
        shape = { "III", "I I", "I I" },
        key = { I = "iron_ingot" },
        result = { id = "leggings", count = 1 },
    },
    {
        id = "armguards",
        shape = { "I I", "III" },
        key = { I = "iron_ingot" },
        result = { id = "armguards", count = 1 },
    },
    {
        id = "leather_helmet",
        shapeless = { "leather", "leather", "leather" },
        result = { id = "helmet", count = 1 },
    },

    -- ==================== 建筑（防御塔）====================
    {
        -- 4 黑曜石 + 1 钻石 → 1 金刚岩（需要工作台 3×3）
        id = "adamant",
        shapeless = { "block:17", "block:17", "block:17", "block:17", "diamond" },
        result = { id = "block:67", count = 1 },
    },
    {
        -- 1 萤石 + 3 煤炭 → 1 火焰石
        id = "flame_stone",
        shapeless = { "block:30", "coal", "coal", "coal" },
        result = { id = "block:66", count = 1 },
    },

    -- ==================== 熔炉 / 容器 / 附魔 / 农业 / 红石 ====================
    {
        -- 8 圆石围一圈 → 熔炉
        id = "furnace",
        shape = { "CCC", "C C", "CCC" },
        key = { C = "block:13" },
        result = { id = "block:23", count = 1 },
    },
    {
        -- 8 木板围一圈 → 箱子
        id = "chest",
        shape = { "PPP", "P P", "PPP" },
        key = { P = "block:19" },
        result = { id = "block:73", count = 1 },
    },
    {
        -- 4 黑曜石 + 2 钻石 + 1 书架 → 附魔台
        id = "enchanting_table",
        shapeless = { "block:17", "block:17", "block:17", "block:17", "diamond", "diamond", "block:21" },
        result = { id = "block:74", count = 1 },
    },
    {
        -- 2 铁锭 + 2 木棍 → 锄头
        id = "hoe",
        shape = { "II ", " S ", " S " },
        key = { I = "iron_ingot", S = "stick" },
        result = { id = "hoe", count = 1 },
    },
    {
        -- 3 木棍 + 2 线 → 钓鱼竿
        id = "fishing_rod",
        shape = { "  S", " SL", "S L" },
        key = { S = "stick", L = "string" },
        result = { id = "fishing_rod", count = 1 },
    },
    {
        -- 9 红石粉 → 红石块
        id = "redstone_block",
        shape = { "RRR", "RRR", "RRR" },
        key = { R = "redstone" },
        result = { id = "block:79", count = 1 },
    },
    {
        -- 4 红石粉 + 1 萤石 → 红石灯
        id = "redstone_lamp",
        shape = { " R ", "RGR", " R " },
        key = { R = "redstone", G = "block:30" },
        result = { id = "block:82", count = 1 },
    },
    {
        -- 1 红石粉 + 1 木棍 → 红石火把
        id = "redstone_torch",
        shape = { "R", "S" },
        key = { R = "redstone", S = "stick" },
        result = { id = "block:78", count = 1 },
    },
    {
        -- 1 木棍 + 1 圆石 → 拉杆
        id = "lever",
        shape = { "S", "C" },
        key = { S = "stick", C = "block:13" },
        result = { id = "block:80", count = 1 },
    },
    {
        -- 1 石头 → 石按钮
        id = "stone_button",
        shapeless = { "block:3" },
        result = { id = "block:81", count = 1 },
    },
}

return CraftingRecipes
