-- ====================================================================
-- items/ItemStack.lua
-- 物品实例（ItemStack）
--
-- 同一种物品可以存在多个 ItemStack；只有「物品 ID + 影响堆叠的实例数据」
-- 完全相同的两个堆才能合并（Design.md 三、物品实例系统）。
--
-- 实例字段：
--   id           物品 ID
--   count        当前数量（>=1）
--   durability   当前耐久（nil = 无耐久；满耐久时也存数值）
--   enchantments 附魔数据（预留）
--   components   自定义组件数据（预留）
-- ====================================================================

local ItemRegistry = require("items.ItemRegistry")

---@class ItemStack
---@field id string
---@field count integer
---@field durability number|nil
---@field enchantments table
---@field components table
local ItemStack = {}
ItemStack.__index = ItemStack

-- ====================================================================
-- 深比较 / 序列化（用于判断"影响堆叠的实例数据是否相同"）
-- ====================================================================

---递归比较两个值
---@param a any
---@param b any
---@return boolean
local function deepEqual(a, b)
    if a == b then return true end
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return false end
    for k, v in pairs(a) do
        if not deepEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

---把表转成稳定字符串（键排序），用于比较与存档
---@param value any
---@return string
local function stableEncode(value)
    if type(value) ~= "table" then
        return tostring(value)
    end
    local keys = {}
    for k in pairs(value) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = tostring(k) .. "=" .. stableEncode(value[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
end
ItemStack.stableEncode = stableEncode
ItemStack.deepEqual = deepEqual

-- ====================================================================
-- 构造
-- ====================================================================

---创建物品堆
---@param id string 物品 ID
---@param count integer|nil 数量（默认 1）
---@param opts table|nil { durability = number, enchantments = table, components = table }
---@return ItemStack|nil 物品 ID 不存在时返回 nil
function ItemStack.new(id, count, opts)
    local def = ItemRegistry:get(id)
    if not def then
        print("[ItemStack] 未知物品 ID：" .. tostring(id))
        return nil
    end

    local self = setmetatable({}, ItemStack)
    self.id = id
    self.count = math.max(1, math.floor(count or 1))
    self.enchantments = {}
    self.components = {}

    opts = opts or {}
    if def.durability then
        self.durability = opts.durability or def.durability
    else
        self.durability = nil
    end
    if opts.enchantments then self.enchantments = opts.enchantments end
    if opts.components then self.components = opts.components end

    if self.count > def.maxStack then
        self.count = def.maxStack
    end
    return self
end

---按定义创建一整堆
---@param def table ItemDefinition
---@param count integer|nil
---@return ItemStack|nil
function ItemStack.fromDefinition(def, count)
    return ItemStack.new(def.id, count or 1)
end

---从存档数据恢复
---@param data table { id, count, durability, enchantments, components }
---@return ItemStack|nil
function ItemStack.deserialize(data)
    if type(data) ~= "table" or not data.id then
        return nil
    end
    return ItemStack.new(data.id, data.count or 1, {
        durability = data.durability,
        enchantments = data.enchantments,
        components = data.components,
    })
end

---导出为可被 cjson 编码的表
---@return table
function ItemStack:serialize()
    return {
        id = self.id,
        count = self.count,
        durability = self.durability,
        enchantments = next(self.enchantments) and self.enchantments or nil,
        components = next(self.components) and self.components or nil,
    }
end

-- ====================================================================
-- 查询
-- ====================================================================

---@return ItemDefinition|nil
function ItemStack:getDefinition()
    return ItemRegistry:get(self.id)
end

---@return string
function ItemStack:getName()
    local def = self:getDefinition()
    return def and def.name or self.id
end

---@return integer
function ItemStack:getMaxStack()
    local def = self:getDefinition()
    return def and def.maxStack or 64
end

---@return integer
function ItemStack:getRemainingSpace()
    return math.max(0, self:getMaxStack() - self.count)
end

---@return boolean
function ItemStack:isEmpty()
    return self.count <= 0
end

---@return boolean
function ItemStack:isBlock()
    local def = self:getDefinition()
    return def ~= nil and def.behavior == "block" and def.blockId ~= nil
end

---@return integer|nil
function ItemStack:getBlockId()
    local def = self:getDefinition()
    return def and def.blockId or nil
end

---@return string|nil
function ItemStack:getBehavior()
    local def = self:getDefinition()
    return def and def.behavior or nil
end

---@return string|nil
function ItemStack:getToolType()
    local def = self:getDefinition()
    return def and def.toolType or nil
end

-- ====================================================================
-- 堆叠判断（Design.md 三、1~6）
-- ====================================================================

---是否与另一个堆属于同一种"可合并实例"
---@param other ItemStack|nil
---@return boolean
function ItemStack:isSameInstance(other)
    if not other or other.id ~= self.id then
        return false
    end
    -- 耐久不同、附魔不同、组件不同的物品不能错误合并
    if (self.durability or 0) ~= (other.durability or 0) then
        return false
    end
    if not deepEqual(self.enchantments, other.enchantments) then
        return false
    end
    if not deepEqual(self.components, other.components) then
        return false
    end
    return true
end

---能否把 other 合并进当前堆（同实例 + 未满）
---@param other ItemStack|nil
---@return boolean
function ItemStack:canMergeWith(other)
    return self:isSameInstance(other) and self:getRemainingSpace() > 0
end

---把 other 的一部分/全部并入当前堆
---@param other ItemStack
---@return integer moved 实际并入数量
function ItemStack:mergeFrom(other)
    if not self:isSameInstance(other) then
        return 0
    end
    local space = self:getRemainingSpace()
    local moved = math.min(space, other.count)
    if moved <= 0 then
        return 0
    end
    self.count = self.count + moved
    other.count = other.count - moved
    return moved
end

---拆分出 n 个（原堆减少，返回新堆）
---@param n integer
---@return ItemStack|nil
function ItemStack:split(n)
    n = math.max(1, math.floor(n))
    if n > self.count then
        n = self.count
    end
    if n <= 0 then
        return nil
    end
    local copy = self:copy()
    if not copy then
        return nil
    end
    copy.count = n
    self.count = self.count - n
    return copy
end

---完整拷贝
---@return ItemStack|nil
function ItemStack:copy()
    return ItemStack.new(self.id, self.count, {
        durability = self.durability,
        enchantments = deepEqual({}, self.enchantments) and nil or self.enchantments,
        components = deepEqual({}, self.components) and nil or self.components,
    })
end

-- ====================================================================
-- 耐久度
-- ====================================================================

---@return boolean 是否有耐久度
function ItemStack:hasDurability()
    local def = self:getDefinition()
    return def ~= nil and def.durability ~= nil and self.durability ~= nil
end

---@return number 0-1 剩余耐久比例
function ItemStack:getDurabilityFraction()
    local def = self:getDefinition()
    if not def or not def.durability or not self.durability then
        return 1.0
    end
    return math.max(0, math.min(1, self.durability / def.durability))
end

---消耗耐久
---@param amount number|nil 默认 1
---@return boolean broken 是否损坏（耐久归零）
function ItemStack:damage(amount)
    local current = self.durability
    if not self:hasDurability() or current == nil then
        return false
    end
    current = current - (amount or 1)
    if current <= 0 then
        self.durability = 0
        return true
    end
    self.durability = current
    return false
end

return ItemStack
