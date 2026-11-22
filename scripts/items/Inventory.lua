-- ====================================================================
-- items/Inventory.lua
-- 玩家背包（参考 Minecraft Java 生存模式结构）
--
--   1  .. 27   主背包 27 格（3 行 × 9）
--   28 .. 36   快捷栏 9 格
--   37         头盔
--   38         胸甲
--   39         护腿
--   40         护臂
--   41         副手
--
-- 只负责数据：放入 / 取出 / 堆叠 / 转移 / 护甲与武器加成 / 存档序列化。
-- UI 在 ui/InventoryUI.lua，掉落物在世界里（items/ItemDropSystem.lua）。
-- ====================================================================

local ItemStack = require("items.ItemStack")
local ItemRegistry = require("items.ItemRegistry")
local InventorySlot = require("items.InventorySlot")
local Enchantments = require("data.Enchantments")

---@class Inventory
---@field slots InventorySlot[]
---@field dirty boolean
local Inventory = {}
Inventory.__index = Inventory

-- 槽位区段
Inventory.MAIN_START = 1
Inventory.MAIN_END = 27
Inventory.HOTBAR_START = 28
Inventory.HOTBAR_END = 36
Inventory.ARMOR_HEAD = 37
Inventory.ARMOR_CHEST = 38
Inventory.ARMOR_LEGS = 39
Inventory.ARMOR_ARMS = 40
Inventory.OFFHAND = 41
Inventory.SLOT_COUNT = 41

-- 装备栏位置 → 槽位下标
---@type table<string, integer>
Inventory.ARMOR_SLOTS = {
    head = Inventory.ARMOR_HEAD,
    chest = Inventory.ARMOR_CHEST,
    legs = Inventory.ARMOR_LEGS,
    arms = Inventory.ARMOR_ARMS,
}

---创建背包（全部空槽）
---@return Inventory
function Inventory.new()
    local self = setmetatable({}, Inventory)
    ---@type InventorySlot[]
    local slots = {}
    self.slots = slots
    self.dirty = true

    for i = 1, Inventory.SLOT_COUNT do
        local accept = nil
        if i == Inventory.ARMOR_HEAD then accept = "head"
        elseif i == Inventory.ARMOR_CHEST then accept = "chest"
        elseif i == Inventory.ARMOR_LEGS then accept = "legs"
        elseif i == Inventory.ARMOR_ARMS then accept = "arms"
        end
        table.insert(slots, InventorySlot.new(accept))
    end

    return self
end

-- ====================================================================
-- 基础访问
-- ====================================================================

---@param index integer
---@return InventorySlot|nil
function Inventory:getSlot(index)
    return self.slots[index]
end

---@param index integer
---@return ItemStack|nil
function Inventory:getStack(index)
    local slot = self.slots[index]
    return slot and slot.stack or nil
end

---设置槽位内容
---@param index integer
---@param stack ItemStack|nil
---@return boolean
function Inventory:setStack(index, stack)
    local slot = self.slots[index]
    if not slot then
        return false
    end
    local ok = slot:set(stack)
    if ok then self.dirty = true end
    return ok
end

---快捷栏第 n 格（n = 1..9）
---@param n integer
---@return ItemStack|nil
function Inventory:getHotbarStack(n)
    return self:getStack(Inventory.HOTBAR_START + n - 1)
end

---快捷栏第 n 格下标（n = 1..9）
---@param n integer
---@return integer
function Inventory:getHotbarIndex(n)
    return self.HOTBAR_START + n - 1
end

---装备栏某个部位
---@param equipSlot string "head"/"chest"/"legs"/"arms"
---@return ItemStack|nil
function Inventory:getEquipped(equipSlot)
    local index = Inventory.ARMOR_SLOTS[equipSlot]
    if not index then
        return nil
    end
    return self:getStack(index)
end

---@return ItemStack|nil
function Inventory:getOffhand()
    return self:getStack(Inventory.OFFHAND)
end

-- ====================================================================
-- 放入 / 取出
-- ====================================================================

---把物品堆加入指定区段，返回没放下的剩余
---@param stack ItemStack
---@param startIndex integer
---@param endIndex integer
---@return ItemStack|nil leftover
function Inventory:addToRange(stack, startIndex, endIndex)
    if not stack or stack.count <= 0 then
        return nil
    end

    -- 先找可合并的堆（保持槽位顺序稳定）
    for i = startIndex, endIndex do
        local slot = self.slots[i]
        local cur = slot and slot.stack
        if slot and cur and cur:canMergeWith(stack) then
            slot:add(stack)
            if stack.count <= 0 then
                self.dirty = true
                return nil
            end
        end
    end

    -- 再找空槽：空槽直接接管整堆，然后结束
    -- （以前继续循环会让同一个 ItemStack 表被塞进所有空槽，导致整背包显示同一件物品）
    for i = startIndex, endIndex do
        local slot = self.slots[i]
        if slot and slot:isEmpty() and slot:canAccept(stack) then
            slot:add(stack)
            self.dirty = true
            return nil
        end
    end

    self.dirty = true
    if stack.count <= 0 then
        return nil
    end
    return stack
end

---加入背包（快捷栏优先，和 MC 拾取顺序一致）
---@param stack ItemStack
---@return ItemStack|nil leftover
function Inventory:addStack(stack)
    local left = self:addToRange(stack, Inventory.HOTBAR_START, Inventory.HOTBAR_END)
    if not left then
        return nil
    end
    return self:addToRange(left, Inventory.MAIN_START, Inventory.MAIN_END)
end

---统计某物品数量
---@param id string
---@return integer
function Inventory:countItem(id)
    local n = 0
    for _, slot in ipairs(self.slots) do
        local stack = slot.stack
        if stack and stack.id == id then
            n = n + stack.count
        end
    end
    return n
end

---是否拥有足够数量
---@param id string
---@param count integer|nil
---@return boolean
function Inventory:hasItem(id, count)
    return self:countItem(id) >= (count or 1)
end

---移除指定数量（先主背包再快捷栏）
---@param id string
---@param count integer|nil
---@return integer removed
function Inventory:removeItem(id, count)
    count = count or 1
    local removed = 0
    local order = {}
    for i = Inventory.MAIN_START, Inventory.MAIN_END do order[#order + 1] = i end
    for i = Inventory.HOTBAR_START, Inventory.HOTBAR_END do order[#order + 1] = i end

    for _, i in ipairs(order) do
        if removed >= count then break end
        ---@type InventorySlot|nil
        local slot = self.slots[i]
        local stack = slot and slot.stack
        if slot and stack and stack.id == id then
            local take = math.min(stack.count, count - removed)
            slot:take(take)
            removed = removed + take
        end
    end
    if removed > 0 then self.dirty = true end
    return removed
end

---消耗快捷栏某一格 1 个（n = 1..9）
---@param n integer
---@param amount integer|nil
---@return boolean
function Inventory:consumeHotbar(n, amount)
    local index = self:getHotbarIndex(n)
    local slot = self.slots[index]
    if not slot or slot:isEmpty() then
        return false
    end
    slot:take(amount or 1)
    self.dirty = true
    return true
end

-- ====================================================================
-- 加成计算（Design.md 物品内容）
-- ====================================================================

---护甲加成总和（含「保护」附魔）
---@return number
function Inventory:getArmorBonus()
    ---@type number
    local bonus = 0
    for _, equip in ipairs({ "head", "chest", "legs", "arms" }) do
        local stack = self:getEquipped(equip)
        local def = stack and ItemRegistry:get(stack.id)
        if def and def.armorBonus then
            bonus = bonus + def.armorBonus
        end
        if stack and stack.enchantments then
            bonus = bonus + Enchantments.value("protection", Enchantments.level(stack, "protection"))
        end
    end
    return bonus
end

---手上物品的攻击力加成（含「锋利」附魔）
---@param hotbarIndex integer 1..9
---@return number
function Inventory:getHeldAttackBonus(hotbarIndex)
    local stack = self:getHotbarStack(hotbarIndex)
    local def = stack and ItemRegistry:get(stack.id)
    ---@type number
    local bonus = 0
    if def and def.attackBonus then
        bonus = def.attackBonus
    end
    if stack and stack.enchantments then
        bonus = bonus + Enchantments.value("sharpness", Enchantments.level(stack, "sharpness"))
    end
    return bonus
end

---手上物品的工具类型
---@param hotbarIndex integer
---@return string|nil
function Inventory:getHeldToolType(hotbarIndex)
    local stack = self:getHotbarStack(hotbarIndex)
    local def = stack and ItemRegistry:get(stack.id)
    return def and def.toolType or nil
end

-- ====================================================================
-- 耐久
-- ====================================================================

---对某个槽位的物品消耗耐久，耐久归零则移除
---（「耐久」附魔有 1/(level+1) 概率跳过本次消耗）
---@param index integer
---@param amount integer|nil
---@return boolean broken
function Inventory:damageSlot(index, amount)
    local slot = self.slots[index]
    if not slot or not slot.stack then
        return false
    end
    if not slot.stack:hasDurability() then
        return false
    end

    if slot.stack.enchantments then
        local ub = Enchantments.level(slot.stack, "unbreaking")
        if ub > 0 and math.random() < 1 / (ub + 1) then
            return false
        end
    end

    local broken = slot.stack:damage(amount or 1)
    self.dirty = true
    if broken then
        local name = slot.stack:getName()
        slot:clear()
        print("[Items] " .. name .. " 已损坏")
    end
    return broken
end

---玩家受击时消耗护甲耐久（每件 1 点）
---@return integer brokenCount
function Inventory:damageEquippedArmor()
    local brokenCount = 0
    for _, index in pairs(Inventory.ARMOR_SLOTS) do
        local slot = self.slots[index]
        local stack = slot and slot.stack
        if slot and stack and stack:hasDurability() then
            if stack:damage(1) then
                brokenCount = brokenCount + 1
                local name = stack:getName()
                slot:clear()
                print("[Items] " .. name .. " 已损坏")
            end
            self.dirty = true
        end
    end
    return brokenCount
end

-- ====================================================================
-- 转移
-- ====================================================================

---把某个槽位的物品移到目标区段（Shift 快捷转移）
---@param index integer
---@param startIndex integer
---@param endIndex integer
---@return boolean moved
function Inventory:transferSlot(index, startIndex, endIndex)
    local slot = self.slots[index]
    if not slot or slot:isEmpty() then
        return false
    end

    local stack = slot:take(slot:getCount())
    if not stack then
        return false
    end

    local left = self:addToRange(stack, startIndex, endIndex)
    if left and left.count > 0 then
        -- 目标塞不下：放回原槽
        slot:add(left)
    end
    self.dirty = true
    return true
end

-- ====================================================================
-- 脏标记
-- ====================================================================

function Inventory:markDirty()
    self.dirty = true
end

---@return boolean
function Inventory:isDirty()
    return self.dirty
end

function Inventory:clearDirty()
    self.dirty = false
end

-- ====================================================================
-- 存档序列化
-- ====================================================================

---@return table
function Inventory:toData()
    local data = {}
    for i, slot in ipairs(self.slots) do
        if slot.stack then
            data[tostring(i)] = slot.stack:serialize()
        end
    end
    return data
end

---从存档数据恢复（未知物品 ID 会被跳过）
---@param data table|nil
function Inventory:fromData(data)
    for i = 1, Inventory.SLOT_COUNT do
        local slot = self.slots[i]
        if slot then
            slot:clear()
        end
    end
    if type(data) ~= "table" then
        self.dirty = true
        return
    end

    local restored = 0
    for key, itemData in pairs(data) do
        local index = tonumber(key)
        if index and index >= 1 and index <= Inventory.SLOT_COUNT then
            local stack = ItemStack.deserialize(itemData)
            local slot = self.slots[index]
            if stack and slot then
                slot:set(stack)
                restored = restored + 1
            end
        end
    end
    self.dirty = true
    print(string.format("[Inventory] 从存档恢复 %d 个槽位", restored))
end

return Inventory
