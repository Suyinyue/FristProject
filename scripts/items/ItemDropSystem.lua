-- ====================================================================
-- items/ItemDropSystem.lua
-- 掉落与拾取系统（Item Drop / Pickup System）
--
--   - 方块破坏、生物死亡、玩家主动丢弃都从这里生成世界掉落物
--   - 每帧更新掉落物，玩家靠近自动拾取
--   - 相同且可堆叠的掉落物在生成时合并
--   - 支持存档 / 恢复（世界重启后未消失的掉落物还在）
-- ====================================================================

local Config = require("config.GameConfig")
local BlockHarvest = require("data.BlockHarvest")
local ItemStack = require("items.ItemStack")
local ItemRegistry = require("items.ItemRegistry")
local ItemEntity = require("items.ItemEntity")

local BLOCK_SIZE = Config.World.BLOCK_SIZE

---@class ItemDropSystem
---@field scene Scene
---@field world World
---@field entities ItemEntity[]
local ItemDropSystem = {}
ItemDropSystem.__index = ItemDropSystem

---创建掉落物系统
---@param scene Scene
---@param world World
---@return ItemDropSystem
function ItemDropSystem.new(scene, world)
    local self = setmetatable({}, ItemDropSystem)
    self.scene = scene
    self.world = world
    self.entities = {}
    return self
end

-- ====================================================================
-- 生成掉落物
-- ====================================================================

---在世界中生成一个物品堆（先尝试与附近同类掉落物合并）
---@param stack ItemStack
---@param position Vector3
---@return ItemEntity|nil
function ItemDropSystem:spawn(stack, position)
    if not stack or stack.count <= 0 then
        return nil
    end

    local mergeR2 = Config.Items.MERGE_RADIUS * Config.Items.MERGE_RADIUS
    for _, entity in ipairs(self.entities) do
        local other = entity:getStack()
        local p = entity:getPosition()
        local dx = p.x - position.x
        local dy = p.y - position.y
        local dz = p.z - position.z
        if (dx * dx + dy * dy + dz * dz) <= mergeR2 and other:canMergeWith(stack) then
            other:mergeFrom(stack)
            if stack.count <= 0 then
                return entity
            end
        end
    end

    local entity = ItemEntity.new(self.scene, self.world, stack, position, Config.Items.PICKUP_DELAY)
    self.entities[#self.entities + 1] = entity
    return entity
end

---方块被破坏时掉落的物品
---@param blockType integer
---@param bx integer
---@param by integer
---@param bz integer
---@param canHarvest boolean|nil 是否满足工具要求（false = 不掉落）
function ItemDropSystem:dropBlock(blockType, bx, by, bz, canHarvest)
    if canHarvest == false then
        return
    end

    local itemId = BlockHarvest.dropFor(blockType)
    if not itemId or not ItemRegistry:get(itemId) then
        return
    end

    local stack = ItemStack.new(itemId, 1)
    if not stack then
        return
    end

    local pos = Vector3(
        bx * BLOCK_SIZE + BLOCK_SIZE * 0.5,
        by * BLOCK_SIZE + BLOCK_SIZE * 0.5,
        bz * BLOCK_SIZE + BLOCK_SIZE * 0.5)
    self:spawn(stack, pos)
end

---生物死亡掉落
---@param mobType string
---@param position Vector3
function ItemDropSystem:dropMobLoot(mobType, position)
    local loot = Config.Loot[mobType]
    if not loot then
        return
    end

    for _, entry in ipairs(loot) do
        local count = math.random(entry.min, entry.max)
        local stack = ItemStack.new(entry.id, count)
        if stack then
            local jitterX = (math.random() - 0.5) * 1.2
            local jitterZ = (math.random() - 0.5) * 1.2
            self:spawn(stack, Vector3(position.x + jitterX, position.y + 0.6, position.z + jitterZ))
        end
    end
end

---玩家主动丢弃当前选中物品
---@param player Player
---@param count integer|nil 丢弃数量（默认 1）
---@return boolean
function ItemDropSystem:dropFromPlayer(player, count)
    local inventory = player:getInventory()
    if not inventory then
        return false
    end

    local index = inventory:getHotbarIndex(math.floor(player:getSelectedSlotIndex()))
    local slot = inventory:getSlot(index)
    if not slot or slot:isEmpty() then
        return false
    end

    local stack = slot:take(count or 1)
    if not stack then
        return false
    end

    inventory:markDirty()

    local eye = player:getEyePosition()
    local look = player:getLookDirection()
    local pos = eye + look * 1.2
    -- 往前一抛，让它落在地上而不是脚下
    local entity = self:spawn(stack, pos)
    if entity and entity.node then
        entity.node.position = pos
    end
    print("[Items] 丢弃：" .. stack:getName() .. " x" .. tostring(stack.count))
    return true
end

-- ====================================================================
-- 每帧更新 / 拾取
-- ====================================================================

---@param dt number
---@param player Player
function ItemDropSystem:update(dt, player)
    local inventory = player:getInventory()
    local playerPos = player:getPosition()
    local pickedUp = false

    for i = #self.entities, 1, -1 do
        local entity = self.entities[i]
        entity:update(dt)

        if entity:isExpired() then
            entity:destroy()
            table.remove(self.entities, i)
        elseif inventory and entity:isInPickupRange(playerPos) then
            local stack = entity:getStack()
            local leftover = inventory:addStack(stack)

            if not leftover then
                -- 全部拾取
                entity:destroy()
                table.remove(self.entities, i)
                pickedUp = true
            elseif leftover.count < stack.count then
                -- 部分拾取，地面保留剩余数量
                entity:setStack(leftover)
                pickedUp = true
            end
            -- 背包满：留在地上等下次
        end
    end

    if pickedUp then
        inventory:markDirty()
    end
end

---当前掉落物数量
---@return integer
function ItemDropSystem:getCount()
    return #self.entities
end

-- ====================================================================
-- 存档
-- ====================================================================

---@return table[]
function ItemDropSystem:serialize()
    local data = {}
    for _, entity in ipairs(self.entities) do
        local p = entity:getPosition()
        data[#data + 1] = {
            x = p.x, y = p.y, z = p.z,
            stack = entity:getStack():serialize(),
        }
    end
    return data
end

---@param data table[]|nil
function ItemDropSystem:restore(data)
    if type(data) ~= "table" then
        return
    end
    local restored = 0
    for _, entry in ipairs(data) do
        local stack = ItemStack.deserialize(entry.stack)
        if stack then
            local pos = Vector3(entry.x or 0, entry.y or 0, entry.z or 0)
            -- 读档后的掉落物给 1 秒拾取冷却，避免"刚进游戏就被吸走"
            local entity = ItemEntity.new(self.scene, self.world, stack, pos, 1.0)
            self.entities[#self.entities + 1] = entity
            restored = restored + 1
        end
    end
    if restored > 0 then
        print(string.format("[Items] 从存档恢复 %d 个掉落物", restored))
    end
end

---销毁全部掉落物
function ItemDropSystem:destroy()
    for _, entity in ipairs(self.entities) do
        entity:destroy()
    end
    self.entities = {}
end

return ItemDropSystem
