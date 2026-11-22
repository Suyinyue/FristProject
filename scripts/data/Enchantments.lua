-- ====================================================================
-- data/Enchantments.lua
-- 附魔定义（数据驱动，Design.md「附魔系统」）
--
-- 附魔效果是「按等级加成」：
--   sharpness  锋利：攻击力 +10/级（读手上武器）
--   protection 保护：护甲   +10/级（读四件装备）
--   unbreaking 耐久：有 1/(level+1) 概率不消耗耐久（读任意耐久物品）
-- 实际加成计算在 items/Inventory.lua，本文件只提供「有哪些附魔 / 能附到什么上」。
-- ====================================================================

local Enchantments = {}

---@type table<string, { name: string, max: integer, applies: string[], description: string }>
Enchantments.list = {
    sharpness = {
        name = "锋利",
        max = 5,
        applies = { "weapon" },
        description = "攻击力 +10/级",
    },
    protection = {
        name = "保护",
        max = 4,
        applies = { "armor" },
        description = "护甲 +10/级",
    },
    unbreaking = {
        name = "耐久",
        max = 3,
        applies = { "weapon", "tool", "armor" },
        description = "降低耐久消耗",
    },
}

-- 附魔 ID 列表（供 UI 随机选择）
Enchantments.ids = {}
for id in pairs(Enchantments.list) do
    Enchantments.ids[#Enchantments.ids + 1] = id
end

---附魔效果数值（给 Inventory 计算加成用）
---@param id string
---@param level integer
---@return number
function Enchantments.value(id, level)
    if id == "sharpness" or id == "protection" then
        return 10 * (level or 0)
    end
    return 0
end

---一件物品是否可附魔（剑/弓/工具/护甲）
---@param def table ItemDefinition
---@return boolean
function Enchantments.isEnchantable(def)
    if not def then
        return false
    end
    return def.durability ~= nil
        or (def.attackBonus and def.attackBonus > 0)
        or (def.armorBonus and def.armorBonus > 0)
        or def.toolType ~= nil
end

---某个附魔能否施加到该物品
---@param id string
---@param def table ItemDefinition
---@return boolean
function Enchantments.appliesTo(id, def)
    local entry = Enchantments.list[id]
    if not entry or not def then
        return false
    end
    for _, cat in ipairs(entry.applies) do
        if def.category == cat then
            return true
        end
    end
    return false
end

---已附魔等级（没有则 0）
---@param stack table ItemStack
---@param id string
---@return integer
function Enchantments.level(stack, id)
    if not stack or not stack.enchantments then
        return 0
    end
    return stack.enchantments[id] or 0
end

return Enchantments
