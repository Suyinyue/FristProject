-- ====================================================================
-- devtools/MiningCheck.lua
-- 验收：按住左键持续挖掘、松开中断、完成后方块才消失。
-- ====================================================================

local Blocks = require("data.BlockRegistry")
local GameSystems = require("core.GameSystems")
local V = _G.V

---@type DebugGameContext
local ctx
local targetX, targetY, targetZ, targetType

local function mouseDown()
    local ed = VariantMap()
    ed["Button"] = Variant(MOUSEB_LEFT)
    HandleMouseButtonDown("MouseButtonDown", ed)
end

local function mouseUp()
    local ed = VariantMap()
    ed["Button"] = Variant(MOUSEB_LEFT)
    HandleMouseButtonUp("MouseButtonUp", ed)
end

---@return integer slot
local function bestSlotFor(blockType)
    if blockType == Blocks.STONE or blockType == Blocks.COBBLESTONE
        or blockType == Blocks.COAL_ORE or blockType == Blocks.IRON_ORE
        or blockType == Blocks.GOLD_ORE or blockType == Blocks.DIAMOND_ORE
        or blockType == Blocks.COPPER_ORE or blockType == Blocks.ADAMANT_ORE then
        return 2 -- 铁镐
    end
    return 4 -- 铁铲（泥土/沙）
end

V.atFrame(300, function()
    ctx = GetDebugGameContext()
    if not ctx or not ctx.player or not ctx.blockInteraction then
        V.fail("拿不到单机上下文")
        return
    end
    GameSystems.dayNightCycle:setTime(12.0)

    local p = ctx.player
    local pos = p:getPosition()
    local bx = math.floor(pos.x / 2)
    local bz = math.floor(pos.z / 2)
    local gh = ctx.world:getGroundHeight(bx, bz)
    targetX, targetY, targetZ = bx, gh - 1, bz
    targetType = ctx.world:getBlock(targetX, targetY, targetZ)
    p:selectSlot(bestSlotFor(targetType))
    p.pitch = 85   -- 正 pitch 朝下
    p:updateCamera()
end)

V.atFrame(330, function()
    local bx, by, bz = ctx.blockInteraction:getTargetBlock()
    if not bx then
        V.fail("看向脚下时没有命中方块")
        return
    end
    targetX, targetY, targetZ = bx, by, bz
    targetType = ctx.world:getBlock(bx, by, bz)
    V.assert(targetType ~= 0, "目标方块是空气")
    mouseDown()
    V.assert(ctx.miningSystem:isMining(), "按下左键后没有进入挖掘状态")
end)

V.atFrame(560, function()
    V.assert(ctx.world:getBlock(targetX, targetY, targetZ) == 0,
        "按住左键约 3.8 秒后目标方块仍未破坏")
    V.assert(not ctx.miningSystem:isMining(), "方块破坏后挖掘状态没有结束")

    -- 第二轮：按下后很快松开，进度应被重置
    local p = ctx.player
    local pos = p:getPosition()
    local bx = math.floor(pos.x / 2)
    local bz = math.floor(pos.z / 2)
    local gh = ctx.world:getGroundHeight(bx, bz)
    targetX, targetY, targetZ = bx, gh - 1, bz
    targetType = ctx.world:getBlock(targetX, targetY, targetZ)
    p:selectSlot(bestSlotFor(targetType))
    p.pitch = 85
    p:updateCamera()
end)

V.atFrame(580, function()
    local bx, by, bz = ctx.blockInteraction:getTargetBlock()
    if bx then
        targetX, targetY, targetZ = bx, by, bz
        targetType = ctx.world:getBlock(bx, by, bz)
        mouseDown()
    end
end)

V.atFrame(592, function()
    mouseUp()
    V.assert(not ctx.miningSystem:isMining(), "松开左键后挖掘没有中断")
end)

V.atFrame(900, function()
    V.assert(ctx.world:getBlock(targetX, targetY, targetZ) == targetType,
        "挖掘中断后目标方块仍被破坏")
    V.finish()
end)
