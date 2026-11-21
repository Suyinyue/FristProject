-- ====================================================================
-- devtools/TowerCheck.lua
-- 防御塔验收脚本（只由 validate 的 -validate-test 加载）
--
-- 用法：
--   taptap-maker preview validate --mode both \
--     --validate-test devtools/TowerCheck.lua --validate-frames 1900 ...
--
-- 覆盖：
--   2 层基座（3 + 6 块金刚岩）+ 2 个火焰石 → 只激活 1 座塔、范围 6 格
--   范围内的僵尸被 500 攻击力击杀
--   块数不足的基座不成塔
--   破坏顶层后防御塔失效
-- ====================================================================

---validate 断言 API（引擎在加载本脚本前注入全局 V）
---@class TowerValidateAPI
---@field assert fun(cond: boolean, msg: string)
---@field fail fun(msg: string)
---@field atFrame fun(n: integer, fn: function)
---@field finish fun()

---@type TowerValidateAPI
local V = _G.V

local Blocks = require("data.BlockRegistry")
local Config = require("config.GameConfig")

local BS = Config.World.BLOCK_SIZE

---@type DebugGameContext
local ctx
---@type { x: integer, y: integer, z: integer }
local towerPos
---@type Mob
local zombie

-- 1. 搭一座 2 层基座的防御塔（顶层 3 块、底层 6 块），放 2 个火焰石
V.atFrame(1200, function()
    ctx = GetDebugGameContext()
    V.assert(ctx ~= nil and ctx.world ~= nil and ctx.towerManager ~= nil, "拿不到单机上下文")

    local p = ctx.player:getPosition()
    local bx = math.floor(p.x / BS) + 10
    local bz = math.floor(p.z / BS) + 10
    local gh = ctx.world:getGroundHeight(bx, bz)
    local by = math.floor(math.min(gh + 2, Config.World.WORLD_HEIGHT - 8))
    towerPos = { x = bx, y = by, z = bz }

    -- 底层：3×2 = 6 块
    for i = 0, 2 do
        ctx.world:setBlock(bx + i, by, bz, Blocks.ADAMANT)
        ctx.world:setBlock(bx + i, by, bz + 1, Blocks.ADAMANT)
    end
    -- 顶层：3 块
    for i = 0, 2 do
        ctx.world:setBlock(bx + i, by + 1, bz, Blocks.ADAMANT)
    end
    -- 同一基座上放两个火焰石
    ctx.world:setBlock(bx, by + 2, bz, Blocks.FLAME_STONE)
    ctx.world:setBlock(bx + 1, by + 2, bz, Blocks.FLAME_STONE)
    ctx.towerManager:trackFlameStone(bx, by + 2, bz)
    ctx.towerManager:trackFlameStone(bx + 1, by + 2, bz)
    ctx.towerManager:rebuildTowers()
end)

-- 2. 检查塔参数，并在范围内生成一只僵尸
V.atFrame(1320, function()
    V.assert(ctx.towerManager:getTowerCount() == 1,
        "同一基座 2 个火焰石应只激活 1 座塔，实际 " .. ctx.towerManager:getTowerCount())
    V.assert(ctx.towerManager:getFlameStoneCount() == 2,
        "火焰石计数应为 2，实际 " .. ctx.towerManager:getFlameStoneCount())

    local t = ctx.towerManager:getTower(1)
    V.assert(t ~= nil, "没有找到激活的防御塔")
    if t then
        V.assert(t.layers == 2, "基座层数应为 2，实际 " .. t.layers)
        V.assert(t.range == 6, "攻击范围应为 6 格，实际 " .. t.range)
    end

    -- 直接生成在火焰石正上方：距离最近，保证两次攻击内不会走出范围
    zombie = ctx.mobManager:spawnMobAt("ZOMBIE", towerPos.x, towerPos.y + 3, towerPos.z)
    V.assert(zombie ~= nil, "僵尸生成失败")
end)

-- 3. 等待防御塔击杀范围内的僵尸（每 1 秒 500 攻击力，两击击杀 100 血僵尸）
V.atFrame(1600, function()
    V.assert(zombie ~= nil, "僵尸对象丢失")
    if zombie then
        V.assert(zombie:isDead(), "防御塔没有击杀范围内的敌对生物")
    end
end)

-- 4. 块数不足的基座（顶层只有 2 块）不应成塔
V.atFrame(1650, function()
    local bx = towerPos.x + 8
    local by = towerPos.y
    local bz = towerPos.z
    ctx.world:setBlock(bx, by, bz, Blocks.ADAMANT)
    ctx.world:setBlock(bx + 1, by, bz, Blocks.ADAMANT)
    ctx.world:setBlock(bx, by + 1, bz, Blocks.FLAME_STONE)
    ctx.towerManager:trackFlameStone(bx, by + 1, bz)
    ctx.towerManager:rebuildTowers()
end)

V.atFrame(1700, function()
    V.assert(ctx.towerManager:getTowerCount() == 1,
        "只有 2 块金刚岩的基座不应成塔，实际塔数 " .. ctx.towerManager:getTowerCount())
end)

-- 5. 破坏原塔顶层的一块金刚岩 → 塔失效
V.atFrame(1750, function()
    local bx, by, bz = towerPos.x, towerPos.y, towerPos.z
    ctx.world:setBlock(bx, by + 1, bz, Blocks.AIR)
    ctx.towerManager:onBlockChanged(bx, by + 1, bz, Blocks.ADAMANT, Blocks.AIR)
end)

V.atFrame(1800, function()
    V.assert(ctx.towerManager:getTowerCount() == 0,
        "破坏基座顶层后塔应失效，实际塔数 " .. ctx.towerManager:getTowerCount())
end)
