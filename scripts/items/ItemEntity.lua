-- ====================================================================
-- items/ItemEntity.lua
-- 地面掉落物实体（不是 UI 图标）
--
--   - 独立 3D 节点：小方块 + 物品颜色
--   - 受重力影响，落到地面后悬浮 + 旋转
--   - 有拾取冷却、生命周期（默认 5 分钟，见 Config.Items）
--   - 相同且可堆叠的掉落物在生成时合并
-- ====================================================================

local Config = require("config.GameConfig")
local ItemRegistry = require("items.ItemRegistry")

local BLOCK_SIZE = Config.World.BLOCK_SIZE

-- 共享材质缓存（颜色 → Material）
---@type table<string, Material>
local materialCache = {}

---@param r number
---@param g number
---@param b number
---@return Material
local function getMaterial(r, g, b)
    local key = string.format("%.3f,%.3f,%.3f", r, g, b)
    local mat = materialCache[key]
    if not mat then
        mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTexture.xml"))
        mat:SetShaderParameter("MatDiffColor", Variant(Color(r, g, b)))
        materialCache[key] = mat
    end
    return mat
end

---@class ItemEntity
---@field scene Scene
---@field world World
---@field node Node
---@field stack ItemStack
---@field age number
---@field velocityY number
---@field groundTimer number
---@field bobPhase number
---@field pickupDelay number
---@field lifetime number
local ItemEntity = {}
ItemEntity.__index = ItemEntity

---创建掉落物
---@param scene Scene
---@param world World
---@param stack ItemStack
---@param position Vector3 世界坐标
---@param pickupDelay number|nil 拾取冷却（秒）
---@return ItemEntity
function ItemEntity.new(scene, world, stack, position, pickupDelay)
    local self = setmetatable({}, ItemEntity)
    self.scene = scene
    self.world = world
    self.stack = stack
    self.age = 0.0
    self.velocityY = 0.0
    self.groundTimer = 0.0
    self.bobPhase = math.random() * math.pi * 2
    self.pickupDelay = pickupDelay or Config.Items.PICKUP_DELAY
    self.lifetime = Config.Items.DESPAWN_TIME

    self.node = scene:CreateChild("ItemDrop_" .. stack.id)
    self.node.position = position
    self.node.scale = Vector3(0.9, 0.9, 0.9)

    local def = ItemRegistry:get(stack.id)
    local cr, cg, cb = 0.7, 0.7, 0.7
    if def and def.color then
        cr = def.color[1] or cr
        cg = def.color[2] or cg
        cb = def.color[3] or cb
    end

    -- 小方块模型（方块物品压扁一点，普通物品拉长一点，视觉上能区分）
    local body = self.node:CreateChild("Body")
    local isBlock = stack:isBlock()
    local sx = isBlock and 0.30 or 0.16
    local sy = isBlock and 0.30 or 0.36
    local sz = isBlock and 0.30 or 0.16
    body.scale = Vector3(sx, sy, sz) * BLOCK_SIZE
    local model = body:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")
    model.material = getMaterial(cr, cg, cb)

    -- 普通物品再加一个浅色小部件（看起来像"有造型的物品"）
    if not isBlock then
        local accent = self.node:CreateChild("Accent")
        accent.position = Vector3(0, sy * BLOCK_SIZE * 0.45, 0)
        accent.scale = Vector3(0.22, 0.08, 0.22) * BLOCK_SIZE
        local accentModel = accent:CreateComponent("StaticModel")
        accentModel.model = cache:GetResource("Model", "Models/Box.mdl")
        accentModel.material = getMaterial(
            math.min(1.0, cr * 1.3 + 0.15),
            math.min(1.0, cg * 1.3 + 0.15),
            math.min(1.0, cb * 1.3 + 0.15))
    end

    return self
end

---@return ItemStack
function ItemEntity:getStack()
    return self.stack
end

---@return number
function ItemEntity:getAge()
    return self.age
end

---同时更新数量（合并其它掉落物后）
---@param stack ItemStack
function ItemEntity:setStack(stack)
    self.stack = stack
end

---拾取冷却是否结束
---@return boolean
function ItemEntity:isPickupReady()
    return self.age >= self.pickupDelay
end

---是否已超过生命周期
---@return boolean
function ItemEntity:isExpired()
    return self.age >= self.lifetime
end

---当前位置
---@return Vector3
function ItemEntity:getPosition()
    return self.node.position
end

---是否在拾取范围内
---@param playerPos Vector3
---@return boolean
function ItemEntity:isInPickupRange(playerPos)
    if not self:isPickupReady() then
        return false
    end
    local p = self.node.position
    local dx = p.x - playerPos.x
    local dy = p.y - (playerPos.y + BLOCK_SIZE)
    local dz = p.z - playerPos.z
    local r = Config.Items.PICKUP_RADIUS
    return (dx * dx + dy * dy + dz * dz) <= r * r
end

---每帧更新：重力 / 悬浮 / 旋转
---@param dt number
function ItemEntity:update(dt)
    self.age = self.age + dt
    if not self.node then
        return
    end

    self.bobPhase = self.bobPhase + dt * 3.0

    -- 地面高度轮询（0.25 秒一次，避免每帧向下扫描整列）
    self.groundTimer = self.groundTimer - dt
    local p = self.node.position
    if self.groundTimer <= 0 or self.velocityY < 0 then
        self.groundTimer = 0.25
        local bx = math.floor(p.x / BLOCK_SIZE)
        local bz = math.floor(p.z / BLOCK_SIZE)
        local gh = self.world:getGroundHeight(bx, bz)
        local targetY = gh * BLOCK_SIZE + 0.45

        -- 简单重力
        self.velocityY = self.velocityY + Config.Player.GRAVITY * dt
        local ny = p.y + self.velocityY * dt
        if ny <= targetY then
            ny = targetY
            self.velocityY = 0.0
        end
        -- 悬浮
        if self.velocityY == 0.0 then
            ny = targetY + math.sin(self.bobPhase) * 0.08
        end
        self.node.position = Vector3(p.x, ny, p.z)
    else
        self.node.position = Vector3(p.x, p.y + self.velocityY * dt, p.z)
    end

    -- 旋转
    self.node.rotation = Quaternion(0, self.age * 90.0, 0)
end

---销毁节点
function ItemEntity:destroy()
    if self.node then
        self.node:Remove()
        self.node = nil
    end
end

return ItemEntity
