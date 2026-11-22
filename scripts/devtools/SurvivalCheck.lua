-- ====================================================================
-- devtools/SurvivalCheck.lua
-- 验收：经验升级、饱和度自然回血、动物喂食繁殖。
-- ====================================================================

local GameSystems = require("core.GameSystems")
local ItemStack = require("items.ItemStack")
local V = _G.V

local cowA, cowB

V.atFrame(300, function()
    local ctx = GetDebugGameContext()
    if not ctx or not ctx.player or not ctx.mobManager then
        V.fail("拿不到单机上下文")
        return
    end
    if GameSystems.dayNightCycle then
        GameSystems.dayNightCycle:setTime(12.0)
    end

    local player = ctx.player

    -- 经验
    player:addXp(100)
    V.assert(player:getLevel() >= 2, "增加 100 经验后没有升级")
    V.assert(player:getXpTotal() >= 100, "累计经验没有增加")

    -- 饱和度自然回血：血量压低，饥饿/饱和度拉满
    player.health = 40
    player:setHunger(player:getMaxHunger())
    player:setSaturation(20)

    -- 给小麦并喂两只相邻的牛
    local inv = player:getInventory()
    inv:setStack(inv:getHotbarIndex(1), ItemStack.new("wheat", 4))
    player:selectSlot(1)

    local pos = player:getPosition()
    local bx = math.floor(pos.x / 2)
    local bz = math.floor(pos.z / 2)
    local g1 = ctx.world:getGroundHeight(bx + 1, bz)
    local g2 = ctx.world:getGroundHeight(bx + 2, bz)
    cowA = ctx.mobManager:spawnMobAt("COW", bx + 1, g1, bz)
    cowB = ctx.mobManager:spawnMobAt("COW", bx + 2, g2, bz)
    V.assert(ctx.mobManager:tryFeed(player, cowA), "第一只牛喂食失败")
    V.assert(ctx.mobManager:tryFeed(player, cowB), "第二只牛喂食失败")
end)

V.atFrame(900, function()
    local ctx = GetDebugGameContext()
    V.assert(ctx.player:getHealth() > 40, "饱和度没有触发自然回血")

    local baby = false
    for _, mob in ipairs(ctx.mobManager.mobs) do
        if mob.baby and mob.mobType == "COW" then
            baby = true
            break
        end
    end
    V.assert(baby, "两只求偶的牛没有生成幼体")
    V.finish()
end)
