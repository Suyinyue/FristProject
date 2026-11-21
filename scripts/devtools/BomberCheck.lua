-- ====================================================================
-- devtools/BomberCheck.lua
-- 炸弹人自爆验收脚本（只由 validate 的 -validate-test 加载）
--
-- 用法：
--   taptap-maker preview validate --mode both \
--     --validate-test devtools/BomberCheck.lua --validate-frames 1500 ...
--
-- 覆盖：
--   炸弹人贴近玩家后自爆 →
--     玩家受到 300 攻击力伤害（按护甲结算）
--     2 格内的其它生物受伤
--     2 格内的方块被清除
--     炸弹人自身死亡
-- ====================================================================

---validate 断言 API（引擎在加载本脚本前注入全局 V）
---@class BomberValidateAPI
---@field assert fun(cond: boolean, msg: string)
---@field fail fun(msg: string)
---@field atFrame fun(n: integer, fn: function)
---@field finish fun()

---@type BomberValidateAPI
local V = _G.V

local Blocks = require("data.BlockRegistry")
local Config = require("config.GameConfig")

local BS = Config.World.BLOCK_SIZE

---@type DebugGameContext
local ctx
---@type Mob
local bomber
---@type Mob
local zombie
local healthBefore = 0.0
---@type { x: integer, y: integer, z: integer }|nil
local testBlock = nil

-- 1. 把玩家移到远离出生塔的地方，生成炸弹人和一个陪炸的僵尸
V.atFrame(1100, function()
    ctx = GetDebugGameContext()
    V.assert(ctx ~= nil and ctx.world ~= nil and ctx.mobManager ~= nil, "拿不到单机上下文")

    local p = ctx.player:getPosition()
    local spawnX = math.floor(p.x / BS)
    local spawnZ = math.floor(p.z / BS)

    -- 找一块 2×2 都同高的平坦地面，保证炸弹人/僵尸与玩家同层、视线通畅，
    -- 且爆炸中心（炸弹人脚下）与测试方块的高差不受地形起伏影响。
    -- 用环形搜索覆盖更大范围（出生点周围 ±20 格），避免固定候选点恰好落在坡上。
    local px, pz, gh
    for r = 0, 20 do
        for dx = -r, r do
            for dz = -r, r do
                if math.max(math.abs(dx), math.abs(dz)) == r then
                    local x = spawnX + dx
                    local z = spawnZ + dz
                    local h = ctx.world:getGroundHeight(x, z)
                    if h > Config.World.WATER_LEVEL + 3 and h < Config.World.WORLD_HEIGHT - 3 then
                        if ctx.world:getGroundHeight(x + 1, z) == h
                            and ctx.world:getGroundHeight(x, z + 1) == h
                            and ctx.world:getGroundHeight(x + 1, z + 1) == h then
                            px, pz, gh = x, z, h
                            break
                        end
                    end
                end
            end
        end
        if px then break end
    end
    if not px or not pz or not gh then
        V.fail("找不到合适的测试地面")
        return
    end

    -- 玩家站到测试点
    ctx.player:setPosition(Vector3(px * BS, gh * BS, pz * BS))
    ctx.player:setVelocity(Vector3(0, 0, 0))
    ctx.player:setOnGround(false)
    healthBefore = ctx.player:getHealth()

    -- 在爆炸范围内放一块泥土，用于验证方块清除
    testBlock = { x = px, y = gh + 1, z = pz + 1 }
    ctx.world:setBlock(testBlock.x, testBlock.y, testBlock.z, Blocks.DIRT)

    -- 炸弹人紧贴玩家（2 格内），僵尸站在旁边一起挨炸
    bomber = ctx.mobManager:spawnMobAt("BOMBER", px + 1, gh, pz)
    zombie = ctx.mobManager:spawnMobAt("ZOMBIE", px + 1, gh, pz + 1)
    V.assert(bomber ~= nil and zombie ~= nil, "炸弹人/僵尸生成失败")
end)

-- 2. 炸弹人进入攻击距离后应立即自爆
V.atFrame(1320, function()
    V.assert(bomber ~= nil, "炸弹人对象丢失")
    if bomber then
        V.assert(bomber:isDead(), "炸弹人没有自爆死亡")
    end

    V.assert(ctx.player:getHealth() < healthBefore,
        "玩家没有受到自爆伤害（" .. healthBefore .. " -> " .. ctx.player:getHealth() .. "）")

    V.assert(zombie ~= nil and zombie:getHealth() < 100,
        "2 格内的僵尸没有受到爆炸伤害")

    if testBlock then
        local block = ctx.world:getBlock(testBlock.x, testBlock.y, testBlock.z)
        V.assert(block == Blocks.AIR,
            "爆炸范围内的方块没有被清除，实际 " .. tostring(block))
    end
end)
