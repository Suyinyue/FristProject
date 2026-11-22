-- ====================================================================
-- items/ContainerManager.lua
-- 箱子方块实体（Design.md「箱子与容器存储系统」）
--
--   - 方块实体用「坐标 → 数据」旁路表存储
--   - 放置 CHEST 时 register，破坏时掉落内容再 unregister
--   - 容器槽位复用 InventorySlot（27 格，无装备过滤）
-- ====================================================================

local Config = require("config.GameConfig")
local Blocks = require("data.BlockRegistry")
local InventorySlot = require("items.InventorySlot")

local BLOCK_SIZE = Config.World.BLOCK_SIZE

---@param x integer
---@param y integer
---@param z integer
---@return string
local function coordKey(x, y, z)
    return x .. "," .. y .. "," .. z
end

---@class ContainerManager
---@field scene Scene
---@field world World
---@field dropSystem ItemDropSystem|nil
---@field containers table<string, { x: integer, y: integer, z: integer, slots: InventorySlot[] }>
local ContainerManager = {}
ContainerManager.__index = ContainerManager

---@param scene Scene
---@param world World
---@param dropSystem ItemDropSystem|nil
---@return ContainerManager
function ContainerManager.new(scene, world, dropSystem)
    local self = setmetatable({}, ContainerManager)
    self.scene = scene
    self.world = world
    self.dropSystem = dropSystem
    self.containers = {}
    return self
end

---@param x integer
---@param y integer
---@param z integer
---@return table|nil
function ContainerManager:getContainer(x, y, z)
    return self.containers[coordKey(x, y, z)]
end

---@param x integer
---@param y integer
---@param z integer
function ContainerManager:registerContainer(x, y, z)
    local key = coordKey(x, y, z)
    if self.containers[key] then
        return
    end
    local slots = {}
    for i = 1, (Config.Container.CHEST_SLOTS or 27) do
        slots[i] = InventorySlot.new(nil)
    end
    self.containers[key] = { x = x, y = y, z = z, slots = slots }
end

---@param x integer
---@param y integer
---@param z integer
function ContainerManager:unregisterContainer(x, y, z)
    local key = coordKey(x, y, z)
    local c = self.containers[key]
    if not c then
        return
    end
    self.containers[key] = nil

    if self.dropSystem then
        local pos = Vector3(
            x * BLOCK_SIZE + BLOCK_SIZE * 0.5,
            y * BLOCK_SIZE + BLOCK_SIZE * 0.5,
            z * BLOCK_SIZE + BLOCK_SIZE * 0.5)
        for _, slot in ipairs(c.slots) do
            local stack = slot:take(slot:getCount())
            if stack then
                self.dropSystem:spawn(stack, pos)
            end
        end
    end
end

---方块变化回调
---@param x integer
---@param y integer
---@param z integer
---@param oldType integer
---@param newType integer
function ContainerManager:onBlockChanged(x, y, z, oldType, newType)
    if oldType == Blocks.CHEST and newType ~= Blocks.CHEST then
        self:unregisterContainer(x, y, z)
    elseif newType == Blocks.CHEST then
        self:registerContainer(x, y, z)
    end
end

---@return integer
function ContainerManager:getContainerCount()
    local n = 0
    for _ in pairs(self.containers) do
        n = n + 1
    end
    return n
end

function ContainerManager:destroy()
    self.containers = {}
end

return ContainerManager
