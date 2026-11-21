-- ====================================================================
-- devtools/OreCheck.lua
-- 矿石生成验收脚本（Design.md「矿石」）——只由 validate 的 -validate-test 加载
--
-- 扫描出生点附近地下，统计各矿石方块数量：
--   常见矿石（煤/铁/铜/金刚岩）必须生成；稀有矿石只打印统计、不做硬断言。
-- ====================================================================

---@class OreValidateAPI
---@field assert fun(cond: boolean, msg: string)
---@field atFrame fun(n: integer, fn: function)

---@type OreValidateAPI
local V = _G.V

local Blocks = require("data.BlockRegistry")

---@type DebugGameContext
local ctx

V.atFrame(1200, function()
    ctx = GetDebugGameContext()
    V.assert(ctx ~= nil and ctx.world ~= nil, "拿不到单机上下文")

    local world = ctx.world
    local counts = {}

    -- 扫描出生点周围 64×64，地下 2~40 层
    for x = -32, 32 do
        for z = -32, 32 do
            for y = 2, 40 do
                local b = world:getBlock(x, y, z)
                if b == Blocks.COAL_ORE then counts.coal = (counts.coal or 0) + 1
                elseif b == Blocks.IRON_ORE then counts.iron = (counts.iron or 0) + 1
                elseif b == Blocks.COPPER_ORE then counts.copper = (counts.copper or 0) + 1
                elseif b == Blocks.ADAMANT_ORE then counts.adamant = (counts.adamant or 0) + 1
                elseif b == Blocks.GOLD_ORE then counts.gold = (counts.gold or 0) + 1
                elseif b == Blocks.DIAMOND_ORE then counts.diamond = (counts.diamond or 0) + 1
                elseif b == Blocks.EMERALD_ORE then counts.emerald = (counts.emerald or 0) + 1
                elseif b == Blocks.FLAME_STONE_ORE then counts.flame = (counts.flame or 0) + 1
                end
            end
        end
    end

    -- 常见矿石必须生成
    V.assert((counts.coal or 0) > 0, "煤矿未生成")
    V.assert((counts.iron or 0) > 0, "铁矿未生成")
    V.assert((counts.copper or 0) > 0, "铜矿未生成")
    V.assert((counts.adamant or 0) > 0, "金刚岩矿未生成")

    print(string.format(
        "[OreCheck] coal=%d iron=%d copper=%d adamant=%d gold=%d diamond=%d emerald=%d flame=%d",
        counts.coal or 0, counts.iron or 0, counts.copper or 0, counts.adamant or 0,
        counts.gold or 0, counts.diamond or 0, counts.emerald or 0, counts.flame or 0))
end)
