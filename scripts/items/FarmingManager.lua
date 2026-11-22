-- ====================================================================
-- items/FarmingManager.lua
-- 农业种植（Design.md「农业种植系统」）
--
--   - 耕地由锄头右键泥土/草方块得到（见 ItemBehaviors.useHoe）
--   - 小麦作物由种子右键耕地种植（见 ItemBehaviors.useSeed）
--   - 生长阶段 0..7 存 blockState；本模块额外存一份 stage（因为破坏时
--     blockState 已被清空，收获需要靠这里记的成熟度）
--   - 随机 tick 生长：检查光照 + 附近水源，成熟后破坏掉小麦 + 种子
-- ====================================================================

local Config = require("config.GameConfig")
local Blocks = require("data.BlockRegistry")
local ItemStack = require("items.ItemStack")

local BLOCK_SIZE = Config.World.BLOCK_SIZE

---@param x integer
---@param y integer
---@param z integer
---@return string
local function coordKey(x, y, z)
    return x .. "," .. y .. "," .. z
end

---@class FarmingManager
---@field world World
---@field dropSystem ItemDropSystem|nil
---@field crops table<string, integer>  coordKey → stage
---@field cropKeys string[]
---@field tickTimer number
local FarmingManager = {}
FarmingManager.__index = FarmingManager

---@param world World
---@param dropSystem ItemDropSystem|nil
---@return FarmingManager
function FarmingManager.new(world, dropSystem)
    local self = setmetatable({}, FarmingManager)
    self.world = world
    self.dropSystem = dropSystem
    self.crops = {}
    self.cropKeys = {}
    self.tickTimer = 0.0
    return self
end

---@param x integer
---@param y integer
---@param z integer
function FarmingManager:registerCrop(x, y, z)
    local key = coordKey(x, y, z)
    if self.crops[key] ~= nil then
        return
    end
    self.crops[key] = 0
    self.cropKeys[#self.cropKeys + 1] = key
end

---@param x integer
---@param y integer
---@param z integer
function FarmingManager:removeCrop(x, y, z)
    local key = coordKey(x, y, z)
    if self.crops[key] == nil then
        return
    end
    self.crops[key] = nil
    for i = #self.cropKeys, 1, -1 do
        if self.cropKeys[i] == key then
            table.remove(self.cropKeys, i)
            break
        end
    end
end

---附近（水平 4 格内）是否有水源
---@param x integer
---@param y integer
---@param z integer
---@return boolean
function FarmingManager:isWet(x, y, z)
    local r = Config.Farming.WATER_RANGE or 4
    for dx = -r, r do
        for dz = -r, r do
            if self.world:getBlock(x + dx, y, z + dz) == Blocks.WATER
                or self.world:getBlock(x + dx, y - 1, z + dz) == Blocks.WATER then
                return true
            end
        end
    end
    return false
end

---尝试让一株作物生长
---@param x integer
---@param y integer
---@param z integer
function FarmingManager:tryGrow(x, y, z)
    local key = coordKey(x, y, z)
    local stage = self.crops[key]
    if stage == nil or stage >= (Config.Farming.MATURE_STAGE or 7) then
        return
    end

    local light = math.max(self.world:getSkyLight(x, y, z), self.world:getBlockLight(x, y, z))
    if light < (Config.Farming.NEED_LIGHT or 8) then
        return
    end

    local chance = Config.Farming.TICK_CHANCE or 0.3
    if self:isWet(x, y, z) then
        chance = chance * (Config.Farming.GROW_ACCEL_WET or 2.0)
    end
    if math.random() >= chance then
        return
    end

    stage = stage + 1
    self.crops[key] = stage
    self.world:setBlockState(x, y, z, stage)
end

---破坏作物：按成熟度掉落
---@param x integer
---@param y integer
---@param z integer
function FarmingManager:harvestCrop(x, y, z)
    local key = coordKey(x, y, z)
    local stage = self.crops[key] or 0
    self:removeCrop(x, y, z)

    if not self.dropSystem then
        return
    end

    local pos = Vector3(
        x * BLOCK_SIZE + BLOCK_SIZE * 0.5,
        y * BLOCK_SIZE + BLOCK_SIZE * 0.5,
        z * BLOCK_SIZE + BLOCK_SIZE * 0.5)

    local drops = { { "wheat_seed", 1 } }
    if stage >= (Config.Farming.MATURE_STAGE or 7) then
        drops[#drops + 1] = { "wheat", 1 }
        drops[#drops + 1] = { "wheat_seed", math.random(1, 3) }
    end

    for _, entry in ipairs(drops) do
        local stack = ItemStack.new(entry[1], entry[2])
        if stack then
            self.dropSystem:spawn(stack, pos)
        end
    end
end

---方块变化回调
---@param x integer
---@param y integer
---@param z integer
---@param oldType integer
---@param newType integer
function FarmingManager:onBlockChanged(x, y, z, oldType, newType)
    if newType == Blocks.WHEAT_CROP then
        self:registerCrop(x, y, z)
    elseif oldType == Blocks.WHEAT_CROP then
        self:harvestCrop(x, y, z)
    end
end

---每帧更新（随机 tick）
---@param dt number
function FarmingManager:update(dt)
    self.tickTimer = self.tickTimer + dt
    if self.tickTimer < (Config.Farming.TICK_INTERVAL or 0.5) then
        return
    end
    self.tickTimer = 0.0

    local count = #self.cropKeys
    if count == 0 then
        return
    end

    local budget = math.min(count, Config.Farming.TICK_BUDGET or 16)
    for _ = 1, budget do
        local idx = math.random(1, #self.cropKeys)
        local key = self.cropKeys[idx]
        -- key 形如 "x,y,z"
        local sx, sy, sz = key:match("(-?%d+),(-?%d+),(-?%d+)")
        ---@type integer
        local x = math.floor(tonumber(sx) or 0)
        ---@type integer
        local y = math.floor(tonumber(sy) or 0)
        ---@type integer
        local z = math.floor(tonumber(sz) or 0)
        if self.world:getBlock(x, y, z) == Blocks.WHEAT_CROP then
            self:tryGrow(x, y, z)
        else
            self:removeCrop(x, y, z)
        end
    end
end

---@return integer
function FarmingManager:getCropCount()
    return #self.cropKeys
end

function FarmingManager:destroy()
    self.crops = {}
    self.cropKeys = {}
end

return FarmingManager
