-- ====================================================================
-- entity/Mob.lua
-- 生物实体（敌对 + 中立）
-- 模型见 entity/MobModel.lua；本文件负责 AI、血量、位置与剔除
--
-- 性能要点：
--   - 地面高度按 0.25s 轮询缓存，不再每帧向下扫描整列
--   - 超出 RENDER_CULL_DISTANCE 的生物整体禁用节点（不渲染）
-- ====================================================================

local Config = require("config.GameConfig")
local HealthBar = require("entity.HealthBar")
local MobModel = require("entity.MobModel")

local BLOCK_SIZE = Config.World.BLOCK_SIZE

---@class Mob
---@field scene Scene
---@field world World
---@field node Node
---@field def table
---@field mobType string
---@field health number
---@field maxHealth number
---@field armor number
---@field attack number
---@field hostile boolean
---@field ranged boolean
---@field fly boolean
---@field dead boolean
---@field model MobModel
---@field healthBar HealthBar
---@field attackCooldown number
---@field wanderDirX number
---@field wanderDirZ number
---@field wanderTimer number
---@field homeX number
---@field homeZ number
---@field homeRadius number
---@field groundY number
---@field groundTimer number
---@field cullTimer number
---@field culled boolean
---@field moving boolean
---@field airborne boolean
---@field yaw number
local Mob = {}
Mob.__index = Mob

---创建生物
---@param scene Scene 场景
---@param world World 世界实例
---@param mobType string 生物类型键（见 Config.Mobs）
---@param spawnPos Vector3 出生位置
---@return Mob
function Mob.new(scene, world, mobType, spawnPos)
    local self = setmetatable({}, Mob)
    local def = Config.Mobs[mobType]

    self.scene = scene
    self.world = world
    self.mobType = mobType
    self.def = def

    self.health = def.health
    self.maxHealth = def.health
    self.armor = def.armor
    self.attack = def.attack
    self.hostile = def.hostile
    self.ranged = def.ranged
    self.fly = def.fly
    self.dead = false

    -- AI 状态
    self.attackCooldown = 0.0
    self.wanderDirX = 0.0
    self.wanderDirZ = 0.0
    self.wanderTimer = 0.0
    self.homeX = spawnPos.x
    self.homeZ = spawnPos.z
    self.homeRadius = 6.0
    self.moving = false
    self.airborne = false
    self.yaw = 0.0

    -- 性能缓存
    self.groundY = spawnPos.y
    self.groundTimer = 0.0
    self.cullTimer = 0.0
    self.culled = false

    -- 场景节点
    self.node = scene:CreateChild("Mob_" .. mobType)
    self.node.position = spawnPos

    -- 模型（多部件方块生物，原点在脚下）
    self.model = MobModel.new(self.node, mobType, def)

    -- 血条：挂在模型头顶上方，宽度随体型
    local modelH = (def.size and def.size[2] or 1.0) * BLOCK_SIZE
    local modelW = (def.size and def.size[1] or 0.8) * BLOCK_SIZE
    self.healthBar = HealthBar.new(
        self.node,
        def.health,
        modelH + 0.45,
        math.max(1.0, modelW * 1.1)
    )

    return self
end

---受击：伤害 = 攻击力 / 护甲
---@param rawAttack number 攻击者的攻击力
function Mob:takeDamage(rawAttack)
    if self.dead then
        return
    end
    local damage = rawAttack / self.armor
    self.health = self.health - damage
    if self.health <= 0 then
        self.health = 0
        self.dead = true
    end
    self.healthBar:setHealth(self.health, self.maxHealth)
end

---是否死亡
---@return boolean
function Mob:isDead()
    return self.dead
end

---获取当前位置
---@return Vector3
function Mob:getPosition()
    return self.node.position
end

---获取血量
---@return number
function Mob:getHealth()
    return self.health
end

---刷新地面高度缓存
---@param dt number
function Mob:refreshGroundY(dt)
    self.groundTimer = self.groundTimer - dt
    if self.groundTimer <= 0 then
        self.groundTimer = 0.25
        local px = self.node.position.x / BLOCK_SIZE
        local pz = self.node.position.z / BLOCK_SIZE
        local gh = self.world:getGroundHeight(math.floor(px), math.floor(pz))
        self.groundY = gh * BLOCK_SIZE
    end
end

---中立生物：在出生点附近漫游
---@param dt number 时间步长
---@return number moveX, number moveZ 本帧移动方向（用于设置朝向）
function Mob:wander(dt)
    self.wanderTimer = self.wanderTimer - dt
    if self.wanderTimer <= 0 then
        self.wanderTimer = 2.0 + math.random() * 3.0
        local angle = math.random() * 2 * math.pi
        self.wanderDirX = math.cos(angle)
        self.wanderDirZ = math.sin(angle)
    end

    local speed = self.def.speed
    local mp = self.node.position
    local nx = mp.x + self.wanderDirX * speed * dt
    local nz = mp.z + self.wanderDirZ * speed * dt

    -- 限制在出生点附近，避免走进未生成区域
    local hx = nx - self.homeX
    local hz = nz - self.homeZ
    local dist = math.sqrt(hx * hx + hz * hz)
    if dist > self.homeRadius then
        self.wanderDirX = -hx / dist
        self.wanderDirZ = -hz / dist
        nx = mp.x + self.wanderDirX * speed * dt
        nz = mp.z + self.wanderDirZ * speed * dt
    end

    self.node.position = Vector3(nx, mp.y, nz)
    self.moving = true
    return self.wanderDirX, self.wanderDirZ
end

---距离剔除：远处生物整体禁用节点
---@param dt number
---@param playerPos Vector3
function Mob:updateCulling(dt, playerPos)
    self.cullTimer = self.cullTimer - dt
    if self.cullTimer > 0 then
        return
    end
    self.cullTimer = 0.5

    local p = self.node.position
    local dx = p.x - playerPos.x
    local dz = p.z - playerPos.z
    local maxD = Config.MobSpawning.RENDER_CULL_DISTANCE
    local shouldCull = (dx * dx + dz * dz) > maxD * maxD

    if shouldCull ~= self.culled then
        self.culled = shouldCull
        -- SetDeepEnabled 会连血条一起隐藏/显示
        self.node:SetDeepEnabled(not shouldCull)
    end
end

---每帧更新
---@param dt number 时间步长
---@param player Player 玩家实例
function Mob:update(dt, player)
    if self.dead then
        return
    end

    local pp = player:getPosition()
    self:updateCulling(dt, pp)

    local mp = self.node.position
    local dx = pp.x - mp.x
    local dz = pp.z - mp.z
    local distXZ = math.sqrt(dx * dx + dz * dz)

    self.moving = false

    -- 朝向与移动方向一致：记录本帧的移动方向，最后统一设置朝向
    local moveX, moveZ = 0.0, 0.0

    local aggroRange = Config.MobSpawning.AGGRO_RANGE
    if self.hostile and distXZ <= aggroRange then
        -- 敌对且进入索敌范围：追玩家，进攻击距离就攻击
        local attackRangeWorld = self.def.range * BLOCK_SIZE
        if distXZ > attackRangeWorld and distXZ > 0.0001 then
            local speed = self.def.speed
            local nx = mp.x + (dx / distXZ) * speed * dt
            local nz = mp.z + (dz / distXZ) * speed * dt
            self.node.position = Vector3(nx, mp.y, nz)
            self.moving = true
            moveX, moveZ = dx, dz
        else
            -- 已在攻击距离内：站定并面向玩家
            moveX, moveZ = dx, dz
        end

        if distXZ <= attackRangeWorld and self.attackCooldown <= 0 then
            if not player:isDead() then
                player:takeDamage(self.attack)
            end
            self.attackCooldown = 1.0
        end
    else
        -- 中立生物 / 未索敌的敌对生物：漫游
        moveX, moveZ = self:wander(dt)
    end

    -- 统一设置朝向：与移动方向一致
    if (moveX ~= 0 or moveZ ~= 0) then
        local yaw = math.deg(math.atan(moveX, moveZ))
        self.yaw = yaw
        self.node.rotation = Quaternion(0, yaw, 0)
    end

    -- 垂直定位
    --   fly = true      ：始终悬浮（幽灵）
    --   canFly = true   ：平时贴地行走（炸弹人），玩家明显高于自己时起飞追击
    self:refreshGroundY(dt)
    local groundY = self.groundY

    local airborne = self.fly
    if not airborne and self.def.canFly then
        airborne = (pp.y - self.node.position.y) > 3.0
    end
    self.airborne = airborne

    if self.fly then
        -- 飞行生物：悬停在玩家高度附近
        self.node.position = Vector3(self.node.position.x, pp.y + 0.6, self.node.position.z)
    elseif airborne then
        -- 起飞追击：平滑上升到玩家高度
        local cur = self.node.position
        local targetY = math.max(groundY, pp.y + 0.2)
        local ny = cur.y + (targetY - cur.y) * math.min(1.0, dt * 3.0)
        self.node.position = Vector3(cur.x, ny, cur.z)
    elseif self.node.position.y > groundY + 0.05 then
        -- 落地：平滑下降回地面
        local cur = self.node.position
        local ny = cur.y + (groundY - cur.y) * math.min(1.0, dt * 6.0)
        self.node.position = Vector3(cur.x, ny, cur.z)
    else
        self.node.position = Vector3(self.node.position.x, groundY, self.node.position.z)
    end

    -- 模型动画（幽灵/起飞的炸弹人：上下浮动 + 扇翅膀）
    if self.model then
        self.model:update(dt, self.moving, airborne)
    end

    -- 血条朝向玩家：抵消身体自身朝向，让血条正面始终对着玩家
    if self.healthBar then
        local yawToPlayer = math.deg(math.atan(dx, dz))
        self.healthBar:setYaw(yawToPlayer - self.yaw)
    end

    -- 攻击冷却
    if self.attackCooldown > 0 then
        self.attackCooldown = self.attackCooldown - dt
    end
end

---销毁生物（移除节点和血条）
function Mob:destroy()
    if self.healthBar then
        self.healthBar:destroy()
        self.healthBar = nil
    end
    if self.node then
        self.node:Remove()
        self.node = nil
    end
end

return Mob
