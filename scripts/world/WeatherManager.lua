-- ====================================================================
-- world/WeatherManager.lua
-- 天气系统：晴 / 雨 / 雷雨 / 雪
--
--   - 状态机随机切换，明暗通过 DayNightCycle:setWeatherDarkness 连续过渡
--   - 降水用屏幕空间覆盖层（ui/WeatherOverlay）绘制雨丝 / 雪花 / 闪电闪光
--   - 雷雨每隔随机时间落雷：闪光 + 对玩家附近生物造成伤害
--   - 雪只出现在山地群系
-- ====================================================================

local Config = require("config.GameConfig")
local WeatherOverlay = require("ui.WeatherOverlay")
local BiomeGenerator = require("terrain.BiomeGenerator")

local BLOCK_SIZE = Config.World.BLOCK_SIZE

---@param a number
---@param b number
---@return number
local function randRange(a, b)
    if b <= a then
        return a
    end
    return a + (b - a) * math.random()
end

---@class WeatherManager
---@field world World
---@field player Player
---@field mobManager MobManager|nil
---@field dayNightCycle DayNightCycle|nil
---@field biome table|nil
---@field overlay WeatherOverlay|nil
---@field state string "clear" | "rain" | "thunder" | "snow"
---@field timer number
---@field darkness number
---@field flash number
---@field lightningTimer number
local WeatherManager = {}
WeatherManager.__index = WeatherManager

---@param options table { world, player, mobManager, dayNightCycle, biome, uiRoot }
---@return WeatherManager
function WeatherManager.new(options)
    local self = setmetatable({}, WeatherManager)
    self.world = options.world
    self.player = options.player
    self.mobManager = options.mobManager
    self.dayNightCycle = options.dayNightCycle
    self.biome = options.biome

    local cfg = Config.Weather
    self.state = "clear"
    self.timer = randRange(cfg.CLEAR_MIN, cfg.CLEAR_MAX)
    self.darkness = 0.0
    self.flash = 0.0
    self.lightningTimer = randRange(cfg.LIGHTNING_INTERVAL_MIN, cfg.LIGHTNING_INTERVAL_MAX)

    if options.uiRoot then
        self.overlay = WeatherOverlay.new(options.uiRoot)
    end
    return self
end

---@return boolean
function WeatherManager:isRaining()
    return self.state ~= "clear"
end

---@return boolean
function WeatherManager:isSnowing()
    return self.state == "snow"
end

---@return string
function WeatherManager:getState()
    return self.state
end

---调试 / 验收：强制切换天气
---@param state string "clear" | "rain" | "thunder" | "snow"
---@param duration number|nil
function WeatherManager:setState(state, duration)
    self.state = state
    self.timer = duration or 120.0
    print("[Weather] forced -> " .. state)
end

---@return number
function WeatherManager:getDarkness()
    return self.darkness
end

---玩家所在位置是否是雪地（山地群系）
---@return boolean
function WeatherManager:isSnowBiome()
    if not self.biome or not self.player then
        return false
    end
    local p = self.player:getPosition()
    local bx = math.floor(p.x / BLOCK_SIZE)
    local bz = math.floor(p.z / BLOCK_SIZE)
    return self.biome:getBiome(bx, bz) == BiomeGenerator.MOUNTAINS
end

---玩家是否露天（用于雨天是否显示降水）
---@return boolean
function WeatherManager:isExposed()
    if not self.world or not self.player then
        return true
    end
    local eye = self.player:getEyePosition()
    local bx = math.floor(eye.x / BLOCK_SIZE)
    local by = math.floor(eye.y / BLOCK_SIZE)
    local bz = math.floor(eye.z / BLOCK_SIZE)
    return self.world:getSkyLight(bx, by, bz) >= 8
end

---切换天气状态
function WeatherManager:advanceState()
    local cfg = Config.Weather
    if self.state == "clear" then
        if self:isSnowBiome() then
            self.state = "snow"
        elseif math.random() < cfg.THUNDER_CHANCE then
            self.state = "thunder"
        else
            self.state = "rain"
        end
        self.timer = randRange(cfg.RAIN_MIN, cfg.RAIN_MAX)
    else
        self.state = "clear"
        self.timer = randRange(cfg.CLEAR_MIN, cfg.CLEAR_MAX)
    end
    print("[Weather] -> " .. self.state)
end

---@return number
function WeatherManager:targetDarkness()
    local cfg = Config.Weather
    if self.state == "thunder" then
        return cfg.DARKNESS_THUNDER
    elseif self.state == "rain" then
        return cfg.DARKNESS_RAIN
    elseif self.state == "snow" then
        return cfg.DARKNESS_SNOW
    end
    return cfg.DARKNESS_CLEAR
end

---雷击：闪光 + 对玩家附近一只生物造成大量伤害
function WeatherManager:strikeLightning()
    local cfg = Config.Weather
    self.flash = 1.0

    if not (self.mobManager and self.player) then
        return
    end
    local eye = self.player:getEyePosition()
    local r2 = cfg.LIGHTNING_RADIUS * cfg.LIGHTNING_RADIUS
    local best, bestD = nil, r2
    for _, mob in ipairs(self.mobManager.mobs) do
        if not mob:isDead() then
            local p = mob:getPosition()
            local dx, dy, dz = p.x - eye.x, p.y - eye.y, p.z - eye.z
            local d2 = dx * dx + dy * dy + dz * dz
            if d2 <= bestD then
                bestD = d2
                best = mob
            end
        end
    end
    if best then
        best:takeDamage(cfg.LIGHTNING_DAMAGE)
        print(string.format("[Weather] 闪电命中 %s", best.def.name))
    end
end

---@param timeStep number
function WeatherManager:update(timeStep)
    local cfg = Config.Weather
    self.timer = self.timer - timeStep
    if self.timer <= 0 then
        self:advanceState()
    end

    -- 明暗连续过渡（约 2~3 秒）
    local target = self:targetDarkness()
    local k = math.min(1.0, cfg.FADE_SPEED * timeStep * 3.0)
    self.darkness = self.darkness + (target - self.darkness) * k

    if self.dayNightCycle then
        self.dayNightCycle:setWeatherDarkness(self.darkness)
    end

    -- 雷雨：定时落雷
    if self.state == "thunder" then
        self.lightningTimer = self.lightningTimer - timeStep
        if self.lightningTimer <= 0 then
            self.lightningTimer = randRange(cfg.LIGHTNING_INTERVAL_MIN, cfg.LIGHTNING_INTERVAL_MAX)
            self:strikeLightning()
        end
    end
    self.flash = math.max(0, self.flash - timeStep * 2.5)

    -- 覆盖层
    if self.overlay then
        local mode = "none"
        if self.state == "snow" then
            mode = "snow"
        elseif self.state == "rain" or self.state == "thunder" then
            mode = "rain"
        end
        local intensity = 0.0
        if mode ~= "none" then
            intensity = self:isExposed() and 1.0 or 0.2
        end
        self.overlay:set(mode, intensity, self.flash)
        self.overlay:update(timeStep)
    end
end

return WeatherManager
