-- ====================================================================
-- devtools/DayNightCheck.lua
-- 视觉验收：把时间设到指定小时，等天空/环境光捕获完成后截图。
-- 用法：preview validate --mode both --validate-test devtools/DayNightCheck.lua
--       修改下面的 HOUR 后重新运行，可对比白天/黄昏/夜晚。
-- ====================================================================

local GameSystems = require("core.GameSystems")
local V = _G.V

local HOUR = 18.15

V.atFrame(300, function()
    local cycle = GameSystems.dayNightCycle
    if not cycle then
        V.fail("DayNightCycle 未初始化")
        return
    end
    cycle:setTime(HOUR)
    print(string.format("[DayNightCheck] hour=%.2f phase=%s daylight=%.2f",
        HOUR, cycle:getPhase(), cycle:getDaylight()))
end)

V.atFrame(900, function()
    V.finish()
end)
