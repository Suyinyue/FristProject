-- ====================================================================
-- items/ItemRegistry.lua
-- 统一物品注册表（Item Registry）
--
-- 职责：
--   - 加载 data/ItemDefinitions.lua 的定义（数据驱动）
--   - 校验定义合法性，按 ID 索引
--   - 方块 ID ↔ 物品 ID 双向查询（"block:3" ↔ 3）
--   - 可选：从 JSON 追加/覆盖定义（扩展内容时不用改 Lua 业务代码）
-- ====================================================================

local Blocks = require("data.BlockRegistry")
local ItemDefinitions = require("data.ItemDefinitions")

---@class ItemDefinition
---@field id string
---@field name string
---@field icon string|nil
---@field iconTexture string|nil UI 图标贴图（非方块物品：Textures/items/<id>.png）
---@field color number[]
---@field category string
---@field maxStack integer
---@field durability number|nil
---@field behavior string
---@field description string
---@field attackBonus number|nil
---@field armorBonus number|nil
---@field equipSlot string|nil
---@field foodHunger number|nil
---@field foodHeal number|nil
---@field toolType string|nil
---@field effect table|nil
---@field blockId integer|nil

---@class ItemRegistry
---@field defs table<string, ItemDefinition>
---@field order string[]
---@field byBlock table<integer, string>
local ItemRegistry = {
    defs = {},
    order = {},
    byBlock = {},
}

local VALID_BEHAVIORS = {
    material = true, food = true, weapon = true, tool = true,
    block = true, potion = true, bow = true, bucket = true,
    water_bucket = true, armor = true, fishing_rod = true,
}

---注册一个物品定义（重复 ID 会覆盖）
---@param def ItemDefinition
---@return boolean ok, string|nil err
function ItemRegistry:register(def)
    if type(def) ~= "table" or type(def.id) ~= "string" or def.id == "" then
        return false, "物品定义缺少 id"
    end
    if type(def.name) ~= "string" or def.name == "" then
        return false, "物品 " .. def.id .. " 缺少名称"
    end

    def.maxStack = def.maxStack or 64
    def.color = def.color or { 0.6, 0.6, 0.6 }
    def.category = def.category or "material"
    def.behavior = def.behavior or "material"
    def.description = def.description or ""
    -- 非方块物品的 UI 图标贴图（方块物品仍用颜色块/方块纹理）。
    -- iconTexture == false 表示「明确不要贴图」，回退到 icon 字符 + color 色块；
    -- nil 则按约定自动指向 Textures/items/<id>.png。
    if def.iconTexture == nil and not def.blockId then
        def.iconTexture = "Textures/items/" .. def.id .. ".png"
    end

    if not VALID_BEHAVIORS[def.behavior] then
        return false, "物品 " .. def.id .. " 的 behavior 未知：" .. tostring(def.behavior)
    end
    if def.maxStack < 1 or def.maxStack > 99 then
        return false, "物品 " .. def.id .. " 的 maxStack 非法：" .. tostring(def.maxStack)
    end
    if def.durability and def.durability <= 0 then
        return false, "物品 " .. def.id .. " 的 durability 非法：" .. tostring(def.durability)
    end
    if def.behavior == "block" and type(def.blockId) ~= "number" then
        return false, "方块物品 " .. def.id .. " 缺少 blockId"
    end
    if def.behavior == "armor" and not def.equipSlot then
        return false, "护甲物品 " .. def.id .. " 缺少 equipSlot"
    end

    if not self.defs[def.id] then
        self.order[#self.order + 1] = def.id
    end
    self.defs[def.id] = def
    if def.blockId then
        self.byBlock[def.blockId] = def.id
    end
    return true
end

---批量加载
---@param list table[]
---@return integer loaded, integer failed
function ItemRegistry:loadDefinitions(list)
    local loaded, failed = 0, 0
    for _, def in ipairs(list) do
        local ok = self:register(def)
        if ok then loaded = loaded + 1 else failed = failed + 1 end
    end
    return loaded, failed
end

---按 ID 取定义
---@param id string
---@return ItemDefinition|nil
function ItemRegistry:get(id)
    return self.defs[id]
end

---按方块 ID 取方块物品定义
---@param blockId integer
---@return ItemDefinition|nil
function ItemRegistry:getByBlockId(blockId)
    if not blockId then
        return nil
    end
    local id = self.byBlock[blockId]
    return id and self.defs[id] or nil
end

---方块 ID → 物品 ID
---@param blockId integer
---@return string|nil
function ItemRegistry:getItemIdForBlock(blockId)
    return self.byBlock[blockId]
end

---所有定义（按注册顺序）
---@return ItemDefinition[]
function ItemRegistry:getAll()
    local list = {}
    for _, id in ipairs(self.order) do
        list[#list + 1] = self.defs[id]
    end
    return list
end

---按分类筛选
---@param category string
---@return ItemDefinition[]
function ItemRegistry:getByCategory(category)
    local list = {}
    for _, id in ipairs(self.order) do
        local def = self.defs[id]
        if def.category == category then
            list[#list + 1] = def
        end
    end
    return list
end

---从 JSON 追加/覆盖定义（可选扩展）
--- JSON 形如 [{ "id": "ruby", "name": "红宝石", ... }]
---@param fileName string 资源路径（相对资源根，比如 "Data/items.json"）
---@return integer loaded
function ItemRegistry:loadFromJson(fileName)
    local ok, list = pcall(function()
        local file = cache:GetFile(fileName)
        if not file then
            return nil
        end
        local text = file:ReadString()
        file:Close()
        return cjson.decode(text)
    end)
    if not ok or type(list) ~= "table" then
        print("[ItemRegistry] JSON 定义读取失败：" .. tostring(fileName))
        return 0
    end
    return (self:loadDefinitions(list))
end

-- ====================================================================
-- 初始化：加载内置定义 + 自动生成方块物品
-- ====================================================================

ItemDefinitions.buildBlockItems(Blocks)
local loaded, failed = ItemRegistry:loadDefinitions(ItemDefinitions.items)
if failed > 0 then
    print(string.format("[ItemRegistry] 物品定义校验失败 %d 条（已跳过）", failed))
end
print(string.format("[ItemRegistry] 已加载 %d 个物品定义", loaded))

return ItemRegistry
