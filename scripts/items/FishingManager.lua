-- ====================================================================
-- items/FishingManager.lua
-- 钓鱼（Design.md「钓鱼系统」）
--
--   - 抛竿：在水面生成浮漂节点，进入等待咬钩
--   - 咬钩：BITE_MIN..BITE_MAX 秒后进入 REEL_WINDOW 秒的可收杆窗口
--   - 收杆：窗口内收杆从钓获表加权抽 1 件掉落；错过窗口无收获
-- ====================================================================

local Config = require("config.GameConfig")
local Blocks = require("data.BlockRegistry")
local ItemStack = require("items.ItemStack")

local BLOCK_SIZE = Config.World.BLOCK_SIZE

---@class FishingManager
---@field scene Scene
---@field world World
---@field dropSystem ItemDropSystem|nil
---@field bobber Node|nil
---@field state string "idle"|"waiting"|"bite"
---@field biteTimer number
---@field reelWindow number
---@field bobPhase number
local FishingManager = {}
FishingManager.__index = FishingManager

---@param scene Scene
---@param world World
---@param dropSystem ItemDropSystem|nil
---@return FishingManager
function FishingManager.new(scene, world, dropSystem)
    local self = setmetatable({}, FishingManager)
    self.scene = scene
    self.world = world
    self.dropSystem = dropSystem
    self.bobber = nil
    self.state = "idle"
    self.biteTimer = 0.0
    self.reelWindow = 0.0
    self.bobPhase = 0.0
    return self
end

---是否正在钓鱼
---@return boolean
function FishingManager:isCasting()
    return self.bobber ~= nil
end

---抛竿：在指定水面方块上方生成浮漂
---@param bx integer 水面方块 X
---@param by integer 水面方块 Y
---@param bz integer 水面方块 Z
---@return boolean
function FishingManager:cast(bx, by, bz)
    if self.bobber then
        return false
    end

    -- 找水面最高一格
    while self.world:getBlock(bx, by + 1, bz) == Blocks.WATER do
        by = by + 1
    end

    local node = self.scene:CreateChild("FishingBobber")
    node.position = Vector3(
        bx * BLOCK_SIZE + BLOCK_SIZE * 0.5,
        (by + 1) * BLOCK_SIZE + 0.3,
        bz * BLOCK_SIZE + BLOCK_SIZE * 0.5)
    local bob = node:CreateChild("Bob")
    bob.scale = Vector3(0.18, 0.18, 0.18) * BLOCK_SIZE
    local model = bob:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Sphere.mdl")
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(0.85, 0.20, 0.15)))
    model.material = mat

    self.bobber = node
    self.state = "waiting"
    self.biteTimer = Config.Fishing.BITE_MIN + math.random() * (Config.Fishing.BITE_MAX - Config.Fishing.BITE_MIN)
    self.reelWindow = 0.0
    print("[Fishing] 抛竿，等待咬钩…")
    return true
end

---收杆：咬钩窗口内成功钓到，否则落空
---@return boolean caught
function FishingManager:reel()
    if not self.bobber then
        return false
    end

    local caught = self.state == "bite"
    if caught and self.dropSystem then
        local loot = self:pickLoot()
        if loot then
            local stack = ItemStack.new(loot.id, loot.count)
            if stack then
                self.dropSystem:spawn(stack, self.bobber.position)
            end
        end
        print("[Fishing] 钓到了！")
    else
        print("[Fishing] 落空了")
    end

    self:clearBobber()
    return caught
end

---从钓获表加权抽一件
---@return table|nil { id: string, count: integer }
function FishingManager:pickLoot()
    local loot = Config.FishingLoot
    if not loot or #loot == 0 then
        return nil
    end
    local total = 0
    for _, entry in ipairs(loot) do
        total = total + (entry.weight or 1)
    end
    local roll = math.random() * total
    local acc = 0
    for _, entry in ipairs(loot) do
        acc = acc + (entry.weight or 1)
        if roll <= acc then
            return { id = entry.id, count = 1 }
        end
    end
    return { id = loot[#loot].id, count = 1 }
end

---@param dt number
function FishingManager:update(dt)
    if not self.bobber then
        return
    end

    self.bobPhase = self.bobPhase + dt * 4.0
    if self.state == "waiting" then
        self.biteTimer = self.biteTimer - dt
        -- 浮漂浮动
        self.bobber.position = Vector3(
            self.bobber.position.x,
            self.bobber.position.y + math.sin(self.bobPhase) * 0.03,
            self.bobber.position.z)
        if self.biteTimer <= 0 then
            self.state = "bite"
            self.reelWindow = Config.Fishing.REEL_WINDOW
            print("[Fishing] 咬钩了！")
        end
    elseif self.state == "bite" then
        self.reelWindow = self.reelWindow - dt
        -- 咬钩：浮漂下坠
        self.bobber.position = Vector3(
            self.bobber.position.x,
            self.bobber.position.y - dt * 0.4,
            self.bobber.position.z)
        if self.reelWindow <= 0 then
            print("[Fishing] 鱼跑了")
            self:clearBobber()
        end
    end
end

function FishingManager:clearBobber()
    if self.bobber then
        self.bobber:Remove()
        self.bobber = nil
    end
    self.state = "idle"
end

function FishingManager:destroy()
    self:clearBobber()
end

return FishingManager
