-- ====================================================================
-- world/DayNightCycle.lua
-- 昼夜循环系统 - 连续渐变的天空 / 太阳 / 雾 / 环境光
-- ====================================================================
--
-- 视觉模型（全部按太阳高度连续插值，没有预设切换的硬跳变）：
--   - 天空：ProceduralSky 的天顶/地平线颜色
--   - 雾色：与地平线同色，避免天地接缝
--   - 太阳：颜色、亮度、角度
--   - 环境光：SkyLightCapture 实时捕获程序化天空，环境漫反射/反射跟着天空渐变
--
-- 时段仅用于 HUD / 生物生成判断（dawn / day / dusk / night），不参与视觉切换。
--
-- ====================================================================

---@class DayNightCycle
---@field dayDuration number
---@field fogStart number
---@field fogEnd number
---@field scene Scene
---@field sky ProceduralSky|nil
---@field skyCapture SkyLightCapture|nil
---@field daylight number 当前太阳高度换算出的白天强度 0..1
---@field weatherDarkness number 天气压暗系数 0..1（由 WeatherManager 写入）
local DayNightCycle = {}
DayNightCycle.__index = DayNightCycle

-- ====================================================================
-- 颜色关键帧（sRGB，天空色 / 太阳色）
-- ====================================================================
local SKY_TOP_NIGHT   = Color(0.02, 0.03, 0.08, 1)
local SKY_TOP_DAY     = Color(0.25, 0.45, 0.85, 1)
local SKY_HORIZON_NIGHT = Color(0.06, 0.09, 0.18, 1)
local SKY_HORIZON_DAY = Color(0.65, 0.75, 0.90, 1)
local SKY_HORIZON_TWILIGHT = Color(0.95, 0.52, 0.28, 1)
local GROUND_BOTTOM_NIGHT = Color(0.02, 0.02, 0.03, 1)
local GROUND_BOTTOM_DAY = Color(0.20, 0.17, 0.13, 1)
local GROUND_HORIZON_NIGHT = Color(0.05, 0.06, 0.10, 1)
local GROUND_HORIZON_DAY = Color(0.65, 0.70, 0.78, 1)
local GROUND_HORIZON_TWILIGHT = Color(0.75, 0.42, 0.22, 1)

local SUN_COLOR_NIGHT = Color(0.30, 0.45, 0.85, 1)
local SUN_COLOR_DAY   = Color(1.00, 0.93, 0.88, 1)
local SUN_COLOR_TWILIGHT = Color(1.00, 0.48, 0.18, 1)

local SUN_BRIGHTNESS_DAY = 3.0
local MOON_BRIGHTNESS = 0.10
local MOON_PITCH = 50          -- 夜间方向光从高处照下（当作月光）
local SUN_SWITCH_ELEV = 0.03   -- 太阳高度低于此值后，天空不再画日盘

-- ====================================================================
-- 构造函数
-- ====================================================================

---创建昼夜循环系统
---@param options table { scene, zone, sunLight, sunNode, lightGroup, startTime, dayDuration }
---@return DayNightCycle
function DayNightCycle.new(options)
    options = options or {}
    local self = setmetatable({}, DayNightCycle)
    
    -- 场景引用（用于切换 LightGroup）
    self.scene = options.scene
    self.lightGroup = options.lightGroup  -- 当前 LightGroup 节点
    
    -- 组件引用
    self.zone = options.zone
    self.sunLight = options.sunLight
    self.sunNode = options.sunNode
    self.sky = options.sky
    self.skyCapture = options.skyCapture
    self.daylight = 1.0
    self.weatherDarkness = 0.0
    
    -- 时间参数
    self.currentTime = options.startTime or 7.0      -- 游戏时间 (0-24)
    self.dayDuration = options.dayDuration or 600    -- 真实秒数 = 1 游戏天
    self.paused = false
    self.timeScale = options.timeScale or 1.0
    
    -- 保存初始雾效距离（用于保持一致）
    self.fogStart = options.fogStart or 30.0
    self.fogEnd = options.fogEnd or 200.0
    
    -- 当前 LightGroup 预设名（用于检测是否需要切换）
    self.currentPreset = nil
    
    -- 太阳旋转平滑插值参数
    self.sunRotationLerpSpeed = options.sunRotationLerpSpeed or 5.0  -- 插值速度
    self.currentSunRotation = nil  -- 当前实际旋转（用于平滑插值）
    
    -- 初始应用光照
    self:applyCurrentLighting()
    
    return self
end

-- ====================================================================
-- 时间管理
-- ====================================================================

---获取当前游戏时间
---@return number 时间 (0-24)
function DayNightCycle:getTime()
    return self.currentTime
end

---设置游戏时间
---@param hour number 时间 (0-24)
function DayNightCycle:setTime(hour)
    self.currentTime = hour % 24
    self.currentSunRotation = nil   -- 立即对齐太阳/月亮角度，避免慢速插值追赶
    self:applyCurrentLighting()
end

---增加游戏时间
---@param hours number 增加的小时数
function DayNightCycle:addTime(hours)
    self.currentTime = (self.currentTime + hours) % 24
    self.currentSunRotation = nil
    self:applyCurrentLighting()
    print(string.format("[DayNight] Time set to %02d:%02d (%s)", 
        math.floor(self.currentTime), 
        math.floor((self.currentTime % 1) * 60),
        self:getPhase()))
end

---暂停时间流逝
function DayNightCycle:pause()
    self.paused = true
end

---恢复时间流逝
function DayNightCycle:resume()
    self.paused = false
end

---检查是否暂停
---@return boolean
function DayNightCycle:isPaused()
    return self.paused
end

---设置时间流速
---@param scale number 倍率 (1.0 = 正常)
function DayNightCycle:setTimeScale(scale)
    self.timeScale = scale
end

---获取时间流速
---@return number
function DayNightCycle:getTimeScale()
    return self.timeScale
end

-- ====================================================================
-- 阶段判断
-- ====================================================================

---获取当前阶段名称
---@return string "dawn" | "day" | "dusk" | "night"
function DayNightCycle:getPhase()
    local hour = self.currentTime
    
    if hour >= 5 and hour < 7 then
        return "dawn"
    elseif hour >= 7 and hour < 17 then
        return "day"
    elseif hour >= 17 and hour < 19 then
        return "dusk"
    else
        return "night"
    end
end

---获取当前阶段和插值信息
---@return string phase, string fromPhase, string toPhase, number t
function DayNightCycle:getPhaseInfo()
    local hour = self.currentTime
    
    -- 日出过渡 (5-7): night → day
    if hour >= 5 and hour < 7 then
        return "dawn", "night", "day", (hour - 5) / 2
    -- 白天稳定 (7-17)
    elseif hour >= 7 and hour < 17 then
        return "day", "day", "day", 1
    -- 日落过渡 (17-19): day → night
    elseif hour >= 17 and hour < 19 then
        return "dusk", "day", "night", (hour - 17) / 2
    -- 夜晚 (19-24 或 0-5): 跨夜处理
    else
        return "night", "night", "night", 1
    end
end

---检查是否为白天
---@return boolean
function DayNightCycle:isDay()
    local phase = self:getPhase()
    return phase == "day" or phase == "dawn"
end

-- ====================================================================
-- 更新循环
-- ====================================================================

---每帧更新
---@param timeStep number 帧时间步长
function DayNightCycle:update(timeStep)
    if self.paused then 
        return 
    end
    
    -- 更新时间
    local hoursPerSecond = 24 / self.dayDuration
    self.currentTime = self.currentTime + timeStep * hoursPerSecond * self.timeScale
    
    -- 时间回绕
    if self.currentTime >= 24 then
        self.currentTime = self.currentTime - 24
    end
    
    -- 应用光照变化
    self:applyCurrentLighting()
    
    -- 更新太阳旋转（传入 timeStep 用于平滑插值）
    self:updateSunRotation(timeStep)
end

-- ====================================================================
-- 光照应用
-- ====================================================================

---@param v number
---@return number
local function clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

---太阳高度：6 点/18 点为 0，正午 1，午夜 -1
---@return number
function DayNightCycle:getSunElevation()
    return math.sin((self.currentTime - 6.0) / 12.0 * math.pi)
end

---当前白天强度 0..1（供天气/生物系统使用）
---@return number
function DayNightCycle:getDaylight()
    return self.daylight
end

---天气压暗系数（0 = 晴，1 = 最暗）；由 WeatherManager 每帧写入
---@param value number
function DayNightCycle:setWeatherDarkness(value)
    self.weatherDarkness = math.max(0, math.min(1, value or 0))
end

---应用当前时间的天空 / 太阳 / 雾（全部连续插值，无预设切换）
function DayNightCycle:applyCurrentLighting()
    local elev = self:getSunElevation()
    local day = clamp01(elev * 3.0)
    -- 日出/日落权重：太阳贴近地平线时为 1
    local twilight = clamp01(1.0 - math.abs(elev) * 3.0)
    self.daylight = day

    local skyTop = SKY_TOP_NIGHT:Lerp(SKY_TOP_DAY, day)
    local skyHorizon = SKY_HORIZON_NIGHT:Lerp(SKY_HORIZON_DAY, day)
    skyHorizon = skyHorizon:Lerp(SKY_HORIZON_TWILIGHT, twilight * 0.75)
    local groundBottom = GROUND_BOTTOM_NIGHT:Lerp(GROUND_BOTTOM_DAY, day)
    local groundHorizon = GROUND_HORIZON_NIGHT:Lerp(GROUND_HORIZON_DAY, day)
    groundHorizon = groundHorizon:Lerp(GROUND_HORIZON_TWILIGHT, twilight * 0.6)

    -- 天气压暗：雨天/雷雨把天空压向灰暗，太阳变弱
    local dark = self.weatherDarkness or 0
    if dark > 0 then
        skyTop = skyTop:Lerp(Color(0.14, 0.15, 0.18, 1), dark)
        skyHorizon = skyHorizon:Lerp(Color(0.32, 0.33, 0.36, 1), dark)
        groundBottom = groundBottom:Lerp(Color(0.04, 0.04, 0.05, 1), dark)
        groundHorizon = groundHorizon:Lerp(Color(0.18, 0.18, 0.20, 1), dark)
    end

    if self.sky then
        self.sky.skyTopColor = skyTop
        self.sky.skyHorizonColor = skyHorizon
        self.sky.groundBottomColor = groundBottom
        self.sky.groundHorizonColor = groundHorizon
        -- sunEnergy 随白天强度归零：夜里日盘和光晕自动消失，天空仍保留渐变
        self.sky.sunEnergy = day
        self.sky.sunLight = self.sunLight
    end

    -- 雾与地平线同色，避免天地接缝
    if self.zone then
        self.zone.fogColor = skyHorizon
        self.zone.depthFogStart = self.fogStart
        self.zone.depthFogEnd = self.fogEnd
    end

    -- 太阳颜色：白天暖白，地平线附近偏橙，夜间转月光蓝
    if self.sunLight then
        local sunColor = SUN_COLOR_NIGHT:Lerp(SUN_COLOR_DAY, day)
        sunColor = sunColor:Lerp(SUN_COLOR_TWILIGHT, twilight * 0.9)
        self.sunLight.color = sunColor
        self.sunLight.brightness = (day * SUN_BRIGHTNESS_DAY + (1.0 - day) * MOON_BRIGHTNESS)
            * (1.0 - dark * 0.75)
    end
end

---计算目标太阳 pitch 角度
---白天跟随太阳高度；夜间改用高处月光方向（否则方向光会从地下往上照）
---@return number pitch 角度
function DayNightCycle:calculateTargetSunPitch()
    local elev = self:getSunElevation()
    if elev > SUN_SWITCH_ELEV then
        return elev * 70.0
    end
    return MOON_PITCH
end

---更新太阳节点旋转（使用平滑插值避免抖动）
---@param timeStep number 帧时间步长（可选，用于平滑插值）
function DayNightCycle:updateSunRotation(timeStep)
    if not self.sunNode then 
        return 
    end
    
    -- 太阳角度计算：
    -- 6:00 地平线 (0°) → 12:00 最高点 (60°) → 18:00 地平线 (0°)
    -- 夜间太阳在地平线以下
    local targetPitch = self:calculateTargetSunPitch()
    local targetYaw = 45  -- 保持 yaw 不变
    
    -- 创建目标四元数
    local targetRotation = Quaternion(targetPitch, targetYaw, 0)
    
    -- 初始化当前旋转（首次调用时）
    if not self.currentSunRotation then
        self.currentSunRotation = targetRotation
        self.sunNode.rotation = targetRotation
        return
    end
    
    -- 使用引擎内置 Slerp 平滑插值（避免角度跳变导致的抖动）
    -- 计算插值因子：基于时间步长和插值速度
    timeStep = timeStep or 0.016  -- 默认约 60fps
    local lerpFactor = math.min(1.0, timeStep * self.sunRotationLerpSpeed)
    
    -- 球面插值到目标旋转（使用引擎原生 Slerp 方法）
    self.currentSunRotation = self.currentSunRotation:Slerp(targetRotation, lerpFactor)
    
    -- 应用平滑后的旋转
    self.sunNode.rotation = self.currentSunRotation
end

-- ====================================================================
-- 格式化输出
-- ====================================================================

---获取格式化的时间字符串
---@return string "HH:MM" 格式
function DayNightCycle:getTimeString()
    local h = math.floor(self.currentTime)
    local m = math.floor((self.currentTime % 1) * 60)
    return string.format("%02d:%02d", h, m)
end

---获取阶段的显示名称
---@return string
function DayNightCycle:getPhaseDisplayName()
    local phase = self:getPhase()
    local names = {
        dawn = "Dawn",
        day = "Day",
        dusk = "Dusk",
        night = "Night",
    }
    return names[phase] or phase
end

return DayNightCycle

