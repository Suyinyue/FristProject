-- ====================================================================
-- items/FurnaceManager.lua
-- 熔炉方块实体 + 烧炼逻辑（Design.md「熔炉与烧炼系统」）
--
--   - 方块实体用「坐标 → 数据」旁路表存储（World 只存方块/光照/状态）
--   - 燃烧态：把 FURNACE(23) 换成 LIT_FURNACE(72)（发光），熄灭换回
--   - 放置时 register，破坏时 unregister 并掉落 3 个槽位内容
--   - 每帧推进所有燃烧中的熔炉，受 UPDATE_BUDGET 限制
-- ====================================================================

local Config = require("config.GameConfig")
local Blocks = require("data.BlockRegistry")
local ItemStack = require("items.ItemStack")
local InventorySlot = require("items.InventorySlot")

local BLOCK_SIZE = Config.World.BLOCK_SIZE

---@param x integer
---@param y integer
---@param z integer
---@return string
local function coordKey(x, y, z)
    return x .. "," .. y .. "," .. z
end

---@class FurnaceManager
---@field scene Scene
---@field world World
---@field dropSystem ItemDropSystem|nil
---@field furnaces table<string, { x: integer, y: integer, z: integer, input: InventorySlot, fuel: InventorySlot, output: InventorySlot, burnTimeLeft: number, progress: number, lit: boolean }>
local FurnaceManager = {}
FurnaceManager.__index = FurnaceManager

---@param scene Scene
---@param world World
---@param dropSystem ItemDropSystem|nil
---@return FurnaceManager
function FurnaceManager.new(scene, world, dropSystem)
    local self = setmetatable({}, FurnaceManager)
    self.scene = scene
    self.world = world
    self.dropSystem = dropSystem
    self.furnaces = {}
    return self
end

---@param x integer
---@param y integer
---@param z integer
---@return table
function FurnaceManager:getFurnace(x, y, z)
    return self.furnaces[coordKey(x, y, z)]
end

---@param x integer
---@param y integer
---@param z integer
function FurnaceManager:registerFurnace(x, y, z)
    local key = coordKey(x, y, z)
    if self.furnaces[key] then
        return
    end
    self.furnaces[key] = {
        x = x, y = y, z = z,
        input = InventorySlot.new(nil),
        fuel = InventorySlot.new(nil),
        output = InventorySlot.new(nil),
        burnTimeLeft = 0.0,
        progress = 0.0,
        lit = false,
    }
end

---破坏熔炉：掉落 3 个槽位内容并移除实体
---@param x integer
---@param y integer
---@param z integer
function FurnaceManager:unregisterFurnace(x, y, z)
    local key = coordKey(x, y, z)
    local f = self.furnaces[key]
    if not f then
        return
    end
    self.furnaces[key] = nil

    if self.dropSystem then
        local pos = Vector3(
            x * BLOCK_SIZE + BLOCK_SIZE * 0.5,
            y * BLOCK_SIZE + BLOCK_SIZE * 0.5,
            z * BLOCK_SIZE + BLOCK_SIZE * 0.5)
        for _, slot in ipairs({ f.input, f.fuel, f.output }) do
            local stack = slot:take(slot:getCount())
            if stack then
                self.dropSystem:spawn(stack, pos)
            end
        end
    end
end

---方块变化回调（由 BlockInteraction 调用）
---@param x integer
---@param y integer
---@param z integer
---@param oldType integer
---@param newType integer
function FurnaceManager:onBlockChanged(x, y, z, oldType, newType)
    local isFurnace = function(t)
        return t == Blocks.FURNACE or t == Blocks.LIT_FURNACE
    end
    if isFurnace(oldType) and not isFurnace(newType) then
        self:unregisterFurnace(x, y, z)
    elseif isFurnace(newType) then
        self:registerFurnace(x, y, z)
    end
end

---当前是否有可烧炼的输入且成品槽能容纳
---@param f table
---@return boolean
function FurnaceManager:canSmelt(f)
    local input = f.input:get()
    if not input or input.count <= 0 then
        return false
    end
    local recipe = Config.Smelting[input.id]
    if not recipe then
        return false
    end
    local out = f.output:get()
    if out then
        if out.id ~= recipe.id then
            return false
        end
        if out:getRemainingSpace() < recipe.count then
            return false
        end
    end
    return true
end

---产出 1 件成品（调用前已确认 canSmelt）
---@param f table
function FurnaceManager:smeltOne(f)
    local input = f.input:get()
    local recipe = Config.Smelting[input.id]
    f.input:take(1)

    local out = f.output:get()
    if not out then
        f.output:set(ItemStack.new(recipe.id, recipe.count))
    else
        out.count = out.count + recipe.count
    end
end

---切换燃烧态（换方块触发光照与网格更新）
---@param f table
---@param lit boolean
function FurnaceManager:setBurning(f, lit)
    if f.lit == lit then
        return
    end
    f.lit = lit
    local blockType = lit and Blocks.LIT_FURNACE or Blocks.FURNACE
    self.world:setBlock(f.x, f.y, f.z, blockType)
end

---推进一台熔炉
---@param f table
---@param dt number
function FurnaceManager:advanceFurnace(f, dt)
    local cfg = Config.Furnace

    -- 熄火时尝试消耗燃料点燃
    if f.burnTimeLeft <= 0 then
        local fuelStack = f.fuel:get()
        if fuelStack and fuelStack.count > 0 then
            local per = Config.Fuel[fuelStack.id]
            if per and per > 0 then
                f.fuel:take(1)
                f.burnTimeLeft = per * cfg.COOK_TIME
                self:setBurning(f, true)
            end
        end
    end

    if f.burnTimeLeft > 0 then
        f.burnTimeLeft = f.burnTimeLeft - dt

        if self:canSmelt(f) then
            f.progress = f.progress + dt
            if f.progress >= cfg.COOK_TIME then
                f.progress = f.progress - cfg.COOK_TIME
                self:smeltOne(f)
            end
        else
            f.progress = 0.0
        end

        if f.burnTimeLeft <= 0 then
            f.burnTimeLeft = 0.0
            self:setBurning(f, false)
        end
    end
end

---每帧更新（受预算限制）
---@param dt number
function FurnaceManager:update(dt)
    local budget = Config.Furnace.UPDATE_BUDGET
    local processed = 0
    for _, f in pairs(self.furnaces) do
        if f.burnTimeLeft > 0 then
            if processed >= budget then
                break
            end
            processed = processed + 1
            self:advanceFurnace(f, dt)
        end
    end
end

---当前熔炉数量
---@return integer
function FurnaceManager:getFurnaceCount()
    local n = 0
    for _ in pairs(self.furnaces) do
        n = n + 1
    end
    return n
end

function FurnaceManager:destroy()
    self.furnaces = {}
end

return FurnaceManager
