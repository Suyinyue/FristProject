-- ====================================================================
-- items/InventorySlot.lua
-- 背包槽位（InventorySlot）
--
-- 一个槽位有一份（可能有约束的）物品堆。装备栏用 acceptSlot 限制
-- 只能放对应部位的护甲；主背包 / 快捷栏 / 副手不限。
-- ====================================================================

local ItemRegistry = require("items.ItemRegistry")

---@class InventorySlot
---@field stack ItemStack|nil
---@field acceptSlot string|nil 只接受 equipSlot 为该值的护甲（nil = 不限）
local InventorySlot = {}
InventorySlot.__index = InventorySlot

---创建槽位
---@param acceptSlot string|nil "head"/"chest"/"legs"/"arms"，nil 表示不限
---@return InventorySlot
function InventorySlot.new(acceptSlot)
    local self = setmetatable({}, InventorySlot)
    self.stack = nil
    self.acceptSlot = acceptSlot
    return self
end

---该槽位能否接收这个物品堆
---@param stack ItemStack|nil
---@return boolean
function InventorySlot:canAccept(stack)
    if not stack then
        return true
    end
    if not self.acceptSlot then
        return true
    end

    local def = ItemRegistry:get(stack.id)
    if not def then
        return false
    end
    return def.behavior == "armor" and def.equipSlot == self.acceptSlot
end

---@return ItemStack|nil
function InventorySlot:get()
    return self.stack
end

---@param stack ItemStack|nil
---@return boolean
function InventorySlot:set(stack)
    if stack and not self:canAccept(stack) then
        return false
    end
    if stack and stack.count <= 0 then
        stack = nil
    end
    self.stack = stack
    return true
end

---@return boolean 是否为空
function InventorySlot:isEmpty()
    return self.stack == nil or self.stack.count <= 0
end

---@return integer 当前数量
function InventorySlot:getCount()
    if not self.stack then
        return 0
    end
    return self.stack.count
end

---清空槽位
function InventorySlot:clear()
    self.stack = nil
end

---向槽位放入物品堆（能合并则合并，返回剩余）
---@param incoming ItemStack
---@return ItemStack|nil leftover
function InventorySlot:add(incoming)
    if not incoming or incoming.count <= 0 then
        return nil
    end

    if self:isEmpty() then
        if not self:canAccept(incoming) then
            return incoming
        end
        self.stack = incoming
        return nil
    end

    local cur = self.stack
    if cur and cur:canMergeWith(incoming) then
        cur:mergeFrom(incoming)
        if incoming.count <= 0 then
            return nil
        end
    end
    return incoming
end

---从槽位取出 n 个
---@param n integer
---@return ItemStack|nil taken
function InventorySlot:take(n)
    local cur = self.stack
    if not cur or cur.count <= 0 then
        return nil
    end
    n = math.max(1, math.floor(n or 1))
    if n >= cur.count then
        self.stack = nil
        return cur
    end
    return cur:split(n)
end

return InventorySlot
