-- ====================================================================
-- devtools/WeatherCheck.lua
-- 视觉验收：正午强制下雨，检查天空压暗 + 雨丝覆盖层，同时确认新系统无 Lua 报错。
-- ====================================================================

local GameSystems = require("core.GameSystems")
local V = _G.V

V.atFrame(300, function()
    local ctx = GetDebugGameContext()
    if not ctx or not ctx.weatherManager then
        V.fail("WeatherManager 未初始化")
        return
    end
    if GameSystems.dayNightCycle then
        GameSystems.dayNightCycle:setTime(12.0)
    end
    ctx.weatherManager:setState("rain", 300.0)
    print("[WeatherCheck] rain forced")
end)

V.atFrame(900, function()
    local ctx = GetDebugGameContext()
    local w = ctx and ctx.weatherManager
    V.assert(w ~= nil and w:getState() == "rain", "天气未进入 rain")
    V.assert(w ~= nil and w:getDarkness() > 0.1, "雨天天空没有压暗")
    V.finish()
end)
