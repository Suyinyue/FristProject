-- ====================================================================
-- devtools/SaveLoadCheck.lua
-- 验收：设置持久化 + 世界存档（保存→破坏方块→加载→方块恢复）。
-- ====================================================================

local SaveManager = require("save.SaveManager")
local SettingsManager = require("save.SettingsManager")
local Blocks = require("data.BlockRegistry")
local GameSystems = require("core.GameSystems")
local V = _G.V

local ctx
local savedSlot
local probeX, probeY, probeZ
local probeType

V.atFrame(300, function()
    ctx = GetDebugGameContext()
    if not ctx or not ctx.world or not ctx.player then
        V.fail("拿不到单机上下文")
        return
    end
    GameSystems.dayNightCycle:setTime(12.0)

    -- 设置写入
    SettingsManager.data.game.showFps = true
    SettingsManager.data.game.autosaveInterval = 120
    V.assert(SettingsManager.save(), "设置保存失败")
    SettingsManager.data.game.showFps = false
    SettingsManager.load()
    V.assert(SettingsManager.data.game.showFps == true, "设置读取不一致")
    V.assert(SettingsManager.data.game.autosaveInterval == 120, "设置读取不一致")

    -- 找一个可破坏的方块做探针
    local p = ctx.player:getPosition()
    local bx = math.floor(p.x / 2)
    local bz = math.floor(p.z / 2)
    local gh = ctx.world:getGroundHeight(bx, bz)
    probeX, probeY, probeZ = bx, gh - 1, bz
    probeType = ctx.world:getBlock(probeX, probeY, probeZ)
    if probeType == 0 then
        probeX, probeY, probeZ = bx, gh - 2, bz
        probeType = ctx.world:getBlock(probeX, probeY, probeZ)
    end
    V.assert(probeType ~= 0, "找不到可探测的方块")

    -- 保存
    local ok, msg = SaveManager.saveWorld(ctx, "TestWorld", "测试世界")
    V.assert(ok, "存档失败: " .. tostring(msg))
    savedSlot = "TestWorld"
end)

V.atFrame(360, function()
    -- 破坏探针方块
    ctx.world:setBlock(probeX, probeY, probeZ, Blocks.AIR)
    V.assert(ctx.world:getBlock(probeX, probeY, probeZ) == Blocks.AIR, "破坏失败")
end)

V.atFrame(420, function()
    -- 加载：探针方块应恢复（挖掉的不复活规则也依赖区块不重生成）
    local ok, msg = SaveManager.loadWorld(ctx, savedSlot)
    V.assert(ok, "加载失败: " .. tostring(msg))
    V.assert(ctx.world:getBlock(probeX, probeY, probeZ) == probeType,
        string.format("加载后方块未恢复：期望 %d 实际 %d",
            probeType, ctx.world:getBlock(probeX, probeY, probeZ)))
end)

V.atFrame(600, function()
    -- 删除测试存档
    local ok, msg = SaveManager.deleteWorld(savedSlot)
    V.assert(ok, "删除失败: " .. tostring(msg))
    V.finish()
end)
