-- ====================================================================
-- items/EnchantingManager.lua
-- 附魔服务（Design.md「附魔系统」）
--
-- 附魔台本身没有内容槽（只有位置），因此不需要方块实体表；
-- 这里提供「书架等级计算 / 随机附魔选项 / 施加附魔」三个纯服务。
-- 附魔效果接入在 items/Inventory.lua（读 stack.enchantments）。
-- ====================================================================

local Config = require("config.GameConfig")
local Blocks = require("data.BlockRegistry")
local Enchantments = require("data.Enchantments")

---@class EnchantingManager
---@field world World
---@field dropSystem ItemDropSystem|nil
local EnchantingManager = {}
EnchantingManager.__index = EnchantingManager

---@param world World
---@param dropSystem ItemDropSystem|nil
---@return EnchantingManager
function EnchantingManager.new(world, dropSystem)
    local self = setmetatable({}, EnchantingManager)
    self.world = world
    self.dropSystem = dropSystem
    return self
end

---附魔台周围书架数量
---@param x integer
---@param y integer
---@param z integer
---@return integer
function EnchantingManager:countBookshelves(x, y, z)
    local r = Config.Enchanting.MAX_BOOKSHELF_RANGE or 2
    local n = 0
    for dx = -r, r do
        for dy = -r, r do
            for dz = -r, r do
                if self.world:getBlock(x + dx, y + dy, z + dz) == Blocks.BOOKSHELF then
                    n = n + 1
                end
            end
        end
    end
    return n
end

---附魔台等级（书架加成，封顶 MAX_COST）
---@param x integer
---@param y integer
---@param z integer
---@return integer
function EnchantingManager:tableLevel(x, y, z)
    local books = self:countBookshelves(x, y, z)
    local per = Config.Enchanting.BOOKSHELF_PER_LEVEL or 15
    local lvl = math.floor(books / per) + 1
    return math.max(1, math.min(Config.Enchanting.MAX_COST or 30, lvl))
end

---随机一个可施加到该物品的附魔选项
---@param stack ItemStack
---@param tableLevel integer
---@return table|nil { id: string, name: string, level: integer, cost: integer }
function EnchantingManager:rollOption(stack, tableLevel)
    local def = stack:getDefinition()
    if not def or not Enchantments.isEnchantable(def) then
        return nil
    end

    -- 从可施加的附魔里随机选
    local candidates = {}
    for _, id in ipairs(Enchantments.ids) do
        if Enchantments.appliesTo(id, def) then
            candidates[#candidates + 1] = id
        end
    end
    if #candidates == 0 then
        return nil
    end

    local id = candidates[math.random(#candidates)]
    local entry = Enchantments.get(id)
    local maxLevel = math.min(entry.max, math.max(1, tableLevel))
    local level = math.random(1, maxLevel)
    local cost = Config.Enchanting.BASE_COST + math.random(0, 2 * tableLevel)

    return {
        id = id,
        name = entry.name,
        level = level,
        cost = math.min(Config.Enchanting.MAX_COST or 30, cost),
    }
end

---施加附魔
---@param stack ItemStack
---@param id string
---@param level integer
function EnchantingManager:apply(stack, id, level)
    if not stack or not stack.enchantments then
        return
    end
    ---@type table<string, integer>
    local ench = stack.enchantments
    ench[id] = level
end

function EnchantingManager:destroy()
end

return EnchantingManager
