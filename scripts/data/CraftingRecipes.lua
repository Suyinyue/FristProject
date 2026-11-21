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
}

return CraftingRecipes
