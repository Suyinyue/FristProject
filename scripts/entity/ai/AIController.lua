-- ====================================================================
-- entity/ai/AIController.lua
-- 生物 AI 总控制器（Design.md「AI机制」）
--
-- 把原来散在 Mob:update 里的 if/else 收敛成「状态机 + 行为模块」，
-- 并保持通用：所有行为由 GameConfig.Mobs（def）与 GameConfig.MobAI 驱动，
-- 不针对单一生物硬编码。
--
-- 状态（AIStateMachine）：
--   IDLE       待机，随机等待后转入 WANDERING；敌对生物持续检测目标
--   WANDERING  朝随机目标点游走（A* 路径），到达后回 IDLE
--   CHASING    朝目标追踪（地面 A* / 飞行直线），进攻击范围转 ATTACKING
--   ATTACKING  站定面向目标，冷却结束攻击；目标离开范围转 CHASING
--
-- 性能（Design.md §九）：
--   - 重决策（检测/状态切换/重算路径）按 TICK_INTERVAL 节流，与渲染帧解耦
--   - 逐帧只做「沿已有路径移动」这种轻量操作
--   - 路径按目标移动超过阈值 / 到重算间隔 / 路径走完时才重算
-- ====================================================================

local AIStateMachine = require("entity.ai.AIStateMachine")
local Pathfinding = require("entity.ai.Pathfinding")
local Config = require("config.GameConfig")

local BLOCK_SIZE = Config.World.BLOCK_SIZE
local AI = Config.MobAI

---@class AIController
---@field mob Mob
---@field world World
---@field def table
---@field hostile boolean
---@field fly boolean
---@field height integer
---@field sm AIStateMachine
---@field decisionTimer number
---@field canDecide boolean
---@field isNight boolean
---@field attackCooldown number
---@field target Player|nil
---@field loseTimer number
---@field noLosTimer number
---@field path {x:integer,y:integer,z:integer}[]|nil
---@field pathIndex integer
---@field repathAccum number
---@field lastTargetX number
---@field lastTargetZ number
---@field wanderTarget Vector3|nil
---@field wanderWait number
---@field homeX number
---@field homeZ number
local AIController = {}
AIController.__index = AIController

---创建 AI 控制器
---@param mob Mob
---@param world World
---@param def table 生物定义（GameConfig.Mobs 里的一项）
---@return AIController
function AIController.new(mob, world, def)
    local self = setmetatable({}, AIController)
    self.mob = mob
    self.world = world
    self.def = def
    self.hostile = def.hostile
    self.fly = def.fly
    self.height = math.max(1, math.ceil(def.size and def.size[2] or 1.0))

    self.decisionTimer = 0
    self.canDecide = false
    self.isNight = false
    self.attackCooldown = 0
    self.target = nil
    self.loseTimer = 0
    self.noLosTimer = 0
    self.path = nil
    self.pathIndex = 1
    self.repathAccum = 0
    self.lastTargetX = 0
    self.lastTargetZ = 0
    self.wanderTarget = nil
    self.wanderWait = 0
    self.homeX = mob.homeX
    self.homeZ = mob.homeZ

    local sm = AIStateMachine.new(self)
    sm:addState("IDLE", {
        enter = function(ai) ai:enterIdle() end,
        update = function(ai, dt, player) return ai:updateIdle(dt, player) end,
    })
    sm:addState("WANDERING", {
        enter = function(ai) ai:enterWandering() end,
        update = function(ai, dt, player) return ai:updateWandering(dt, player) end,
    })
    sm:addState("CHASING", {
        enter = function(ai) ai:enterChasing() end,
        update = function(ai, dt, player) return ai:updateChasing(dt, player) end,
    })
    sm:addState("ATTACKING", {
        enter = function(ai) ai:enterAttacking() end,
        update = function(ai, dt, player) return ai:updateAttacking(dt, player) end,
    })
    self.sm = sm
    self.sm:setState("IDLE")

    return self
end

-- ====================================================================
-- 通用工具
-- ====================================================================

---当前脚部方块坐标
---@return integer, integer, integer
function AIController:blockPos()
    local p = self.mob:getPosition()
    return math.floor(p.x / BLOCK_SIZE), math.floor(p.y / BLOCK_SIZE), math.floor(p.z / BLOCK_SIZE)
end

---攻击距离（世界单位）：远程/自爆用各自 range，近战用 MobAI.ATTACK_RANGE
---@return number
function AIController:attackRangeWorld()
    if self.def.ranged or self.def.explodes then
        return (self.def.range or 2.0) * BLOCK_SIZE
    end
    return AI.ATTACK_RANGE * BLOCK_SIZE
end

---视线检测（从生物半高处到玩家眼睛）
---@param player Player
---@return boolean
function AIController:hasLineOfSight(player)
    local mp = self.mob:getPosition()
    local eyeY = mp.y + self.height * 0.5 * BLOCK_SIZE
    return Pathfinding.hasLineOfSight(
        self.world,
        Vector3(mp.x, eyeY, mp.z),
        player:getEyePosition()
    )
end

---检测到有效目标则返回该玩家，否则 nil
---@param player Player
---@return Player|nil
function AIController:detect(player)
    if not player or player:isDead() then
        return nil
    end
    -- 夜晚：敌对生物无视距离与视线，全部锁定玩家（Design.md「敌对生物」）
    if self.isNight then
        return player
    end
    local mp = self.mob:getPosition()
    local pp = player:getPosition()
    local dx = pp.x - mp.x
    local dz = pp.z - mp.z
    local dist = math.sqrt(dx * dx + dz * dz)
    if dist > AI.DETECT_RANGE * BLOCK_SIZE then
        return nil
    end
    if AI.REQUIRE_LOS and not self:hasLineOfSight(player) then
        return nil
    end
    return player
end

---锁定目标
---@param player Player
function AIController:acquireTarget(player)
    self.target = player
    self.loseTimer = 0
    self.noLosTimer = 0
    self.lastTargetX = player:getPosition().x
    self.lastTargetZ = player:getPosition().z
    self.path = nil
    self.pathIndex = 1
end

---目标是否仍有效（存活且在保持范围内）
---@param player Player
---@return boolean
function AIController:isTargetValid(player)
    if not player or player:isDead() then
        return false
    end
    -- 夜晚：目标只要存活就一直有效，不受距离限制
    if self.isNight then
        return true
    end
    local mp = self.mob:getPosition()
    local pp = player:getPosition()
    local dx = pp.x - mp.x
    local dz = pp.z - mp.z
    local d2 = dx * dx + dz * dz
    local loseRange = AI.LOSE_RANGE * BLOCK_SIZE
    return d2 <= loseRange * loseRange
end

---丢弃目标
function AIController:dropTarget()
    self.target = nil
    self.path = nil
    self.pathIndex = 1
    self.loseTimer = 0
    self.noLosTimer = 0
end

---计算到某世界坐标的路径（结果写入 self.path，失败为 nil）
---@param targetWorldPos Vector3
function AIController:computePathTo(targetWorldPos)
    local sx, sy, sz = self:blockPos()
    local tx = math.floor(targetWorldPos.x / BLOCK_SIZE)
    local tz = math.floor(targetWorldPos.z / BLOCK_SIZE)
    self.path = Pathfinding.findPath(self.world, sx, sy, sz, tx, tz, self.height)
    self.pathIndex = 2 -- 跳过起点
    if self.path and #self.path <= 1 then
        self.path = nil
    end
    self.repathAccum = 0
end

---沿已有路径移动，返回本帧归一化移动方向（无路径返回 0,0）
---@return number moveX
---@return number moveZ
function AIController:followPath()
    if not self.path or self.pathIndex > #self.path then
        return 0, 0
    end
    local wp = self.path[self.pathIndex]
    local p = self.mob:getPosition()
    local wx = (wp.x + 0.5) * BLOCK_SIZE
    local wz = (wp.z + 0.5) * BLOCK_SIZE
    local dx = wx - p.x
    local dz = wz - p.z
    if dx * dx + dz * dz < 0.25 then
        self.pathIndex = self.pathIndex + 1
        return self:followPath()
    end
    local len = math.sqrt(dx * dx + dz * dz)
    return dx / len, dz / len
end

---随机挑选一个可站立的游走目标点（在出生点 WANDER_RADIUS 内、距出生点 ≥ WANDER_MIN_DIST）
---@return boolean
function AIController:pickWanderTarget()
    local p = self.mob:getPosition()
    local hx = self.homeX or p.x
    local hz = self.homeZ or p.z
    for _ = 1, AI.WANDER_TRY do
        local angle = math.random() * 2 * math.pi
        local dist = AI.WANDER_MIN_DIST + math.random() * (AI.WANDER_RADIUS - AI.WANDER_MIN_DIST)
        local tx = math.floor((hx + math.cos(angle) * dist * BLOCK_SIZE) / BLOCK_SIZE)
        local tz = math.floor((hz + math.sin(angle) * dist * BLOCK_SIZE) / BLOCK_SIZE)
        local gy = self.world:getGroundHeight(tx, tz)
        if Pathfinding.isStandable(self.world, tx, gy, tz, self.height) then
            self.wanderTarget = Vector3((tx + 0.5) * BLOCK_SIZE, gy * BLOCK_SIZE, (tz + 0.5) * BLOCK_SIZE)
            return true
        end
    end
    return false
end

-- ====================================================================
-- 状态行为
-- ====================================================================

function AIController:enterIdle()
    self.path = nil
    self.pathIndex = 1
    self.wanderWait = AI.WANDER_WAIT_MIN + math.random() * (AI.WANDER_WAIT_MAX - AI.WANDER_WAIT_MIN)
end

---@param dt number
---@param player Player
function AIController:updateIdle(dt, player)
    if self.hostile and self.canDecide and self:detect(player) then
        self:acquireTarget(player)
        self.sm:setState("CHASING")
        return 0, 0, 0, 0
    end

    self.wanderWait = self.wanderWait - dt
    if self.wanderWait <= 0 then
        if self:pickWanderTarget() then
            self.sm:setState("WANDERING")
        else
            self.wanderWait = AI.WANDER_WAIT_MIN
        end
    end
    return 0, 0, 0, 0
end

function AIController:enterWandering()
    self.path = nil
    self.pathIndex = 1
    self.repathAccum = 0
end

---@param dt number
---@param player Player
function AIController:updateWandering(dt, player)
    if self.hostile and self.canDecide and self:detect(player) then
        self:acquireTarget(player)
        self.sm:setState("CHASING")
        return 0, 0, 0, 0
    end

    if not self.wanderTarget then
        self.sm:setState("IDLE")
        return 0, 0, 0, 0
    end

    if not self.path and self.canDecide then
        self:computePathTo(self.wanderTarget)
        if not self.path then
            -- 目标不可达：放弃本次游走，回 IDLE 稍后重试
            self.wanderTarget = nil
            self.sm:setState("IDLE")
            return 0, 0, 0, 0
        end
    end

    local mx, mz = self:followPath()
    if self.path and self.pathIndex > #self.path then
        self.wanderTarget = nil
        self.sm:setState("IDLE")
        return 0, 0, 0, 0
    end
    return mx, mz, mx, mz
end

function AIController:enterChasing()
    self.path = nil
    self.pathIndex = 1
    self.repathAccum = 0
end

---@param dt number
---@param player Player
function AIController:updateChasing(dt, player)
    if not self:isTargetValid(player) then
        self:dropTarget()
        self.sm:setState("IDLE")
        return 0, 0, 0, 0
    end

    local mp = self.mob:getPosition()
    local pp = player:getPosition()
    local dx = pp.x - mp.x
    local dz = pp.z - mp.z
    local distXZ = math.sqrt(dx * dx + dz * dz)

    if distXZ <= self:attackRangeWorld() then
        self.sm:setState("ATTACKING")
        return 0, 0, dx, dz
    end

    -- 目标长时间不可见（隔墙）→ 判定丢失（夜晚追踪不受此限制）
    if self.canDecide and not self.isNight then
        if AI.REQUIRE_LOS and not self:hasLineOfSight(player) then
            self.noLosTimer = self.noLosTimer + AI.TICK_INTERVAL
        else
            self.noLosTimer = 0
        end
        if self.noLosTimer > AI.LOSE_TIME then
            self:dropTarget()
            self.sm:setState("IDLE")
            return 0, 0, 0, 0
        end
    end

    -- 飞行生物：直线追击（垂直定位由 Mob:update 处理）
    if self.fly then
        local len = math.max(distXZ, 0.0001)
        return dx / len, dz / len, dx, dz
    end

    -- 地面生物：按需重算路径
    if self.canDecide then
        self.repathAccum = self.repathAccum + AI.TICK_INTERVAL
        local moved = math.abs(pp.x - self.lastTargetX) + math.abs(pp.z - self.lastTargetZ)
        if moved > AI.REPATH_DIST * BLOCK_SIZE
            or self.path == nil
            or (self.path and self.pathIndex > #self.path)
            or self.repathAccum >= AI.REPATH_INTERVAL then
            self:computePathTo(pp)
            self.lastTargetX = pp.x
            self.lastTargetZ = pp.z
        end
    end

    local mx, mz = self:followPath()
    if not self.path then
        -- 无路径（不可达）：站定不穿墙，累计丢失计时
        if self.canDecide then
            self.loseTimer = self.loseTimer + AI.TICK_INTERVAL
            if self.loseTimer > AI.LOSE_TIME then
                self:dropTarget()
                self.sm:setState("IDLE")
                return 0, 0, 0, 0
            end
        end
        return 0, 0, dx, dz
    end

    self.loseTimer = 0
    return mx, mz, mx, mz
end

function AIController:enterAttacking()
    self.path = nil
    self.pathIndex = 1
end

---@param dt number
---@param player Player
function AIController:updateAttacking(dt, player)
    if not self:isTargetValid(player) then
        self:dropTarget()
        self.sm:setState("IDLE")
        return 0, 0, 0, 0
    end

    local mp = self.mob:getPosition()
    local pp = player:getPosition()
    local dx = pp.x - mp.x
    local dz = pp.z - mp.z
    local distXZ = math.sqrt(dx * dx + dz * dz)

    if distXZ > self:attackRangeWorld() then
        self.sm:setState("CHASING")
        return 0, 0, dx, dz
    end

    if self.attackCooldown <= 0 then
        self:doAttack(player)
        self.attackCooldown = AI.ATTACK_INTERVAL
    end
    return 0, 0, dx, dz
end

---执行一次攻击（自爆走 onExplode，其余走玩家伤害系统）
---@param player Player
function AIController:doAttack(player)
    if player:isDead() then
        return
    end
    if self.def.explodes and self.mob.onExplode then
        self.mob.onExplode(self.mob, player)
        return
    end
    player:takeDamage(self.def.attack)
end

-- ====================================================================
-- 逐帧入口
-- ====================================================================

---每帧更新（由 Mob:update 调用）
---@param dt number
---@param player Player
---@param isNight boolean|nil
---@return number moveX
---@return number moveZ
---@return number faceX
---@return number faceZ
function AIController:update(dt, player, isNight)
    self.isNight = isNight or false
    if self.attackCooldown > 0 then
        self.attackCooldown = self.attackCooldown - dt
    end

    self.decisionTimer = self.decisionTimer - dt
    self.canDecide = false
    if self.decisionTimer <= 0 then
        self.decisionTimer = AI.TICK_INTERVAL
        self.canDecide = true
    end

    local mx, mz, fx, fz = self.sm:update(dt, player)
    return mx or 0, mz or 0, fx or 0, fz or 0
end

---当前状态名（供验收脚本读取）
---@return string|nil
function AIController:getState()
    return self.sm:getState()
end

return AIController
