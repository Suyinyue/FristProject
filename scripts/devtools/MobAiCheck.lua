-- ====================================================================
-- devtools/MobAiCheck.lua
-- 生物 AI 验收脚本（Design.md「AI机制」）——只由 validate 的 -validate-test 加载
--
-- 用法：
--   taptap-maker preview validate --mode validate \
--     --validate-test devtools/MobAiCheck.lua --validate-frames 1800 ...
--
-- 覆盖：
--   1. 中立生物（牛）不追击，状态停留在 IDLE/WANDERING
--   2. 检测范围外（>16 格）的僵尸不追击
--   3. 检测范围内、视线通畅的僵尸进入 CHASING/ATTACKING
--   4. 近身僵尸进入 ATTACKING 并对玩家造成伤害（走玩家伤害系统）
-- ====================================================================

---validate 断言 API（引擎在加载本脚本前注入全局 V）
---@class MobAiValidateAPI
---@field assert fun(cond: boolean, msg: string)
---@field fail fun(msg: string)
---@field atFrame fun(n: integer, fn: function)
---@field finish fun()

---@type MobAiValidateAPI
local V = _G.V

local Config = require("config.GameConfig")
local BS = Config.World.BLOCK_SIZE

---@type DebugGameContext
local ctx
---@type Mob
local cow
---@type Mob
local farZombie
---@type Mob
local nearZombie
---@type Mob
local meleeZombie
local healthBefore = 0.0

-- 1. 找开阔地面、摆放测试生物
V.atFrame(1100, function()
    ctx = GetDebugGameContext()
    V.assert(ctx ~= nil and ctx.world ~= nil and ctx.mobManager ~= nil and ctx.player ~= nil,
        "拿不到单机上下文")

    local p = ctx.player:getPosition()
    local baseX = math.floor(p.x / BS)
    local baseZ = math.floor(p.z / BS)

    -- 沿 +X 找一块可站立的地面（避开水面 / 世界顶部）
    local gx = baseX
    for _ = 1, 40 do
        local g = ctx.world:getGroundHeight(gx, baseZ)
        if g > Config.World.WATER_LEVEL + 3 and g < Config.World.WORLD_HEIGHT - 3 then
            break
        end
        gx = gx + 2
    end

    -- 把玩家挪到测试地面，并静止
    local gy = ctx.world:getGroundHeight(gx, baseZ)
    ctx.player:setPosition(Vector3(gx * BS, gy * BS, baseZ * BS))
    ctx.player:setVelocity(Vector3(0, 0, 0))

    ---@param type string
    ---@param dx integer
    ---@return Mob|nil
    local function spawnAt(type, dx)
        local x = gx + dx
        local g = ctx.world:getGroundHeight(x, baseZ)
        return ctx.mobManager:spawnMobAt(type, x, g, baseZ)
    end

    cow = spawnAt("COW", 3)
    nearZombie = spawnAt("ZOMBIE", 2)
    meleeZombie = spawnAt("ZOMBIE", 1)
    farZombie = spawnAt("ZOMBIE", 28)

    V.assert(cow ~= nil and nearZombie ~= nil and meleeZombie ~= nil and farZombie ~= nil,
        "测试生物生成失败")

    healthBefore = ctx.player:getHealth()
end)

-- 2. 校验 AI 状态与攻击效果
V.atFrame(1400, function()
    V.assert(ctx ~= nil, "上下文丢失")

    -- 1) 中立生物不追击
    V.assert(cow ~= nil and not cow:isDead(), "牛死亡")
    if cow then
        local s = cow.ai and cow.ai:getState()
        V.assert(s == "IDLE" or s == "WANDERING", "中立生物进入了非游走状态：" .. tostring(s))
    end

    -- 2) 检测范围外僵尸不追击
    if farZombie and not farZombie:isDead() then
        local s = farZombie.ai and farZombie.ai:getState()
        V.assert(s == "IDLE" or s == "WANDERING", "检测范围外的僵尸在追击：" .. tostring(s))
    end

    -- 3) 检测范围内、视线通畅的僵尸进入追击/攻击
    local nearChasing = false
    if nearZombie and not nearZombie:isDead() then
        local s = nearZombie.ai and nearZombie.ai:getState()
        nearChasing = (s == "CHASING" or s == "ATTACKING")
    end
    V.assert(nearChasing, "检测范围内的僵尸没有进入追击状态")

    -- 4) 近身僵尸进入攻击状态并对玩家造成伤害
    local meleeAttacking = false
    if meleeZombie and not meleeZombie:isDead() then
        local s = meleeZombie.ai and meleeZombie.ai:getState()
        meleeAttacking = (s == "ATTACKING")
    end
    V.assert(meleeAttacking, "近身僵尸没有进入攻击状态")
    V.assert(ctx.player:getHealth() < healthBefore,
        "近身僵尸没有对玩家造成伤害（" .. healthBefore .. " -> " .. ctx.player:getHealth() .. "）")
end)
