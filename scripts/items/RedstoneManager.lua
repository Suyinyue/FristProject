-- ====================================================================
-- items/RedstoneManager.lua
-- 红石（简化版，Design.md「红石系统」）
--
--   信号源：红石块 / 红石火把（恒 15）、拉杆（on/off）、按钮（按下 1 秒）
--   导线：红石粉（向 6 邻衰减传播，信号存 blockState 0..15）
--   输出：红石灯（信号 ≥1 点亮）、门/活板门（信号 ≥1 打开）
--
--   事件驱动：只在玩家放置/破坏红石类方块时 recompute，BFS 限制在
--   已登记的红石组件集合内，不会全图扫描。
-- ====================================================================

local Config = require("config.GameConfig")
local Blocks = require("data.BlockRegistry")
local BlockState = require("data.BlockState")

local MAX_SIGNAL = Config.Redstone.MAX_SIGNAL or 15

local DIRS = {
    { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 },
}

---@param x integer
---@param y integer
---@param z integer
---@return string
local function coordKey(x, y, z)
    return x .. "," .. y .. "," .. z
end

---红石组件（参与信号网络，登记在 components 里）
---@param t integer
---@return boolean
local function isComponent(t)
    return t == Blocks.REDSTONE_DUST or t == Blocks.REDSTONE_TORCH
        or t == Blocks.REDSTONE_BLOCK or t == Blocks.LEVER
        or t == Blocks.STONE_BUTTON or t == Blocks.REDSTONE_LAMP
end

---@class RedstoneManager
---@field world World
---@field components table<string, { x: integer, y: integer, z: integer }>
---@field doorOutputs table<string, { x: integer, y: integer, z: integer }>
---@field buttons table<string, number>
local RedstoneManager = {}
RedstoneManager.__index = RedstoneManager

---@param world World
---@return RedstoneManager
function RedstoneManager.new(world)
    local self = setmetatable({}, RedstoneManager)
    self.world = world
    self.components = {}
    self.doorOutputs = {}
    self.buttons = {}
    return self
end

---某格的红石信号强度（源 / 导线）
---@param x integer
---@param y integer
---@param z integer
---@return integer
function RedstoneManager:powerAt(x, y, z)
    local b = self.world:getBlock(x, y, z)
    if b == Blocks.REDSTONE_BLOCK or b == Blocks.REDSTONE_TORCH then
        return MAX_SIGNAL
    end
    if b == Blocks.LEVER or b == Blocks.STONE_BUTTON then
        return self.world:getBlockState(x, y, z) == 1 and MAX_SIGNAL or 0
    end
    if b == Blocks.REDSTONE_DUST then
        return math.floor(self.world:getBlockState(x, y, z))
    end
    return 0
end

---某格 6 邻的最大信号强度
---@param x integer
---@param y integer
---@param z integer
---@return integer
function RedstoneManager:adjacentPower(x, y, z)
    local best = 0
    for _, d in ipairs(DIRS) do
        local p = self:powerAt(x + d[1], y + d[2], z + d[3])
        if p > best then best = p end
    end
    return best
end

---方块变化回调（由 BlockInteraction 调用）
---@param x integer
---@param y integer
---@param z integer
---@param oldType integer
---@param newType integer
function RedstoneManager:onBlockChanged(x, y, z, oldType, newType)
    local key = coordKey(x, y, z)

    if isComponent(oldType) then
        self.components[key] = nil
    end
    if isComponent(newType) then
        self.components[key] = { x = x, y = y, z = z }
    end

    if oldType == Blocks.DOOR_WOOD or oldType == Blocks.DOOR_IRON or oldType == Blocks.TRAPDOOR_WOOD then
        self.doorOutputs[key] = nil
    end

    if isComponent(oldType) or isComponent(newType)
        or oldType == Blocks.DOOR_WOOD or oldType == Blocks.DOOR_IRON or oldType == Blocks.TRAPDOOR_WOOD
        or newType == Blocks.DOOR_WOOD or newType == Blocks.DOOR_IRON or newType == Blocks.TRAPDOOR_WOOD then
        self:recompute(x, y, z)
    end
end

---重新计算整个红石网络
---@param _cx integer
---@param _cy integer
---@param _cz integer
function RedstoneManager:recompute(_cx, _cy, _cz)
    -- 1. 清零所有导线的信号
    for _, c in pairs(self.components) do
        if self.world:getBlock(c.x, c.y, c.z) == Blocks.REDSTONE_DUST then
            self.world:setBlockState(c.x, c.y, c.z, 0)
        end
    end

    -- 2. 多源 BFS：所有满信号源作为种子，向导线衰减传播
    local queue = {}
    local function seed(x, y, z)
        local n = #queue
        queue[n + 1] = x; queue[n + 2] = y; queue[n + 3] = z; queue[n + 4] = MAX_SIGNAL
    end
    for _, c in pairs(self.components) do
        if self:powerAt(c.x, c.y, c.z) >= MAX_SIGNAL then
            seed(c.x, c.y, c.z)
        end
    end

    local head = 1
    while head <= #queue do
        local x, y, z, p = queue[head], queue[head + 1], queue[head + 2], queue[head + 3]
        head = head + 4
        local np = p - 1
        if np > 0 then
            for _, d in ipairs(DIRS) do
                local nx, ny, nz = x + d[1], y + d[2], z + d[3]
                if self.world:getBlock(nx, ny, nz) == Blocks.REDSTONE_DUST
                    and self.world:getBlockState(nx, ny, nz) < np then
                    self.world:setBlockState(nx, ny, nz, np)
                    local n = #queue
                    queue[n + 1] = nx; queue[n + 2] = ny; queue[n + 3] = nz; queue[n + 4] = np
                end
            end
        end
    end

    -- 3. 应用输出
    self:applyOutputs()
end

---应用红石灯 / 门 / 活板门的输出状态
function RedstoneManager:applyOutputs()
    -- 红石灯（来自 components）
    for _, c in pairs(self.components) do
        if self.world:getBlock(c.x, c.y, c.z) == Blocks.REDSTONE_LAMP then
            self:setLamp(c.x, c.y, c.z, self:adjacentPower(c.x, c.y, c.z) >= 1)
        end
    end

    -- 关闭失去信号的门 / 活板门
    for key, c in pairs(self.doorOutputs) do
        if self:adjacentPower(c.x, c.y, c.z) < 1 then
            self:setDoorOutput(c.x, c.y, c.z, false)
            self.doorOutputs[key] = nil
        end
    end

    -- 打开紧邻信号的门 / 活板门（只处理门的正半格，避免双格重复）
    for _, c in pairs(self.components) do
        if self:powerAt(c.x, c.y, c.z) >= 1 then
            for _, d in ipairs(DIRS) do
                local nx, ny, nz = c.x + d[1], c.y + d[2], c.z + d[3]
                local b = self.world:getBlock(nx, ny, nz)
                if b == Blocks.DOOR_WOOD or b == Blocks.DOOR_IRON then
                    if not BlockState.isTopHalf(self.world:getBlockState(nx, ny, nz)) then
                        self:setDoorOutput(nx, ny, nz, true)
                        self.doorOutputs[coordKey(nx, ny, nz)] = { x = nx, y = ny, z = nz }
                    end
                elseif b == Blocks.TRAPDOOR_WOOD then
                    self:setDoorOutput(nx, ny, nz, true)
                    self.doorOutputs[coordKey(nx, ny, nz)] = { x = nx, y = ny, z = nz }
                end
            end
        end
    end
end

---设置红石灯亮灭（含方块光注入/移除）
---@param x integer
---@param y integer
---@param z integer
---@param powered boolean
function RedstoneManager:setLamp(x, y, z, powered)
    local lit = self.world:getBlockState(x, y, z) == 1
    if lit == powered then
        return
    end
    self.world:setBlock(x, y, z, Blocks.REDSTONE_LAMP, powered and 1 or 0)
    if powered then
        self.world:addBlockLight(x, y, z, MAX_SIGNAL)
    else
        self.world:removeBlockLight(x, y, z)
    end
end

---设置门 / 活板门开合（门双格同步）
---@param x integer
---@param y integer
---@param z integer
---@param powered boolean
function RedstoneManager:setDoorOutput(x, y, z, powered)
    local b = self.world:getBlock(x, y, z)
    if b == Blocks.DOOR_WOOD or b == Blocks.DOOR_IRON then
        local state = self.world:getBlockState(x, y, z)
        if BlockState.isOpen(state) == powered then
            return
        end
        self.world:setBlock(x, y, z, b, BlockState.toggleOpen(state))
        local partnerY = BlockState.isTopHalf(state) and (y - 1) or (y + 1)
        if self.world:getBlock(x, partnerY, z) == b then
            local ps = self.world:getBlockState(x, partnerY, z)
            self.world:setBlock(x, partnerY, z, b, BlockState.toggleOpen(ps))
        end
    elseif b == Blocks.TRAPDOOR_WOOD then
        local state = self.world:getBlockState(x, y, z)
        if BlockState.isOpen(state) ~= powered then
            self.world:setBlock(x, y, z, b, BlockState.toggleOpen(state))
        end
    end
end

---玩家右键拉杆
---@param x integer
---@param y integer
---@param z integer
---@return boolean
function RedstoneManager:toggleLever(x, y, z)
    if self.world:getBlock(x, y, z) ~= Blocks.LEVER then
        return false
    end
    local on = self.world:getBlockState(x, y, z) == 1
    self.world:setBlock(x, y, z, Blocks.LEVER, on and 0 or 1)
    self:recompute(x, y, z)
    return true
end

---玩家按下按钮
---@param x integer
---@param y integer
---@param z integer
---@return boolean
function RedstoneManager:pressButton(x, y, z)
    if self.world:getBlock(x, y, z) ~= Blocks.STONE_BUTTON then
        return false
    end
    self.world:setBlock(x, y, z, Blocks.STONE_BUTTON, 1)
    self.buttons[coordKey(x, y, z)] = Config.Redstone.BUTTON_PULSE or 1.0
    self:recompute(x, y, z)
    return true
end

---每帧更新：按钮复位
---@param dt number
function RedstoneManager:update(dt)
    for key, left in pairs(self.buttons) do
        left = left - dt
        if left <= 0 then
            self.buttons[key] = nil
            local sx, sy, sz = key:match("(-?%d+),(-?%d+),(-?%d+)")
            local x = math.floor(tonumber(sx) or 0)
            local y = math.floor(tonumber(sy) or 0)
            local z = math.floor(tonumber(sz) or 0)
            if self.world:getBlock(x, y, z) == Blocks.STONE_BUTTON then
                self.world:setBlock(x, y, z, Blocks.STONE_BUTTON, 0)
                self:recompute(x, y, z)
            end
        else
            self.buttons[key] = left
        end
    end
end

---@return integer
function RedstoneManager:getComponentCount()
    local n = 0
    for _ in pairs(self.components) do
        n = n + 1
    end
    return n
end

function RedstoneManager:destroy()
    self.components = {}
    self.doorOutputs = {}
    self.buttons = {}
end

return RedstoneManager
