-- ====================================================================
-- ui/WeatherOverlay.lua
-- 天气覆盖层：屏幕空间的雨丝 / 雪花 / 闪电闪光。
--
-- 用 urhox-libs/UI 的自定义 Widget 绘制，挂到 UI 根节点最底层（zIndex 为负），
-- 不接收指针事件，不影响 HUD / 背包交互。
-- ====================================================================

local Widget = require("urhox-libs/UI/Core/Widget")

local RAIN_COUNT = 220
local SNOW_COUNT = 140

---@class WeatherOverlayWidget : Widget
---@overload fun(props?: table): WeatherOverlayWidget
---@field drops_ table[]
---@field mode_ string
---@field intensity_ number
---@field flash_ number
local WeatherOverlayWidget = Widget:Extend("WeatherOverlay")

---@param props table|nil
function WeatherOverlayWidget:Init(props)
    props = props or {}
    props.position = "absolute"
    props.left = 0
    props.top = 0
    props.width = "100%"
    props.height = "100%"
    props.pointerEvents = "none"
    props.zIndex = -20
    Widget.Init(self, props)

    self.mode_ = "none"
    self.intensity_ = 0.0
    self.flash_ = 0.0
    self.drops_ = {}
end

---@param count integer
function WeatherOverlayWidget:initDrops_(count)
    self.drops_ = {}
    for i = 1, count do
        self.drops_[i] = {
            x = math.random(),
            y = math.random(),
            speed = 0.55 + math.random() * 0.85,
            len = 0.035 + math.random() * 0.05,
            phase = math.random() * math.pi * 2,
        }
    end
end

---@param mode string "none" | "rain" | "snow"
---@param intensity number 0..1
---@param flash number 0..1
function WeatherOverlayWidget:SetWeather(mode, intensity, flash)
    if mode ~= self.mode_ then
        if mode == "rain" then
            self:initDrops_(RAIN_COUNT)
        elseif mode == "snow" then
            self:initDrops_(SNOW_COUNT)
        end
        self.mode_ = mode
    end
    self.intensity_ = math.max(0, math.min(1, intensity or 0))
    self.flash_ = math.max(0, math.min(1, flash or 0))
end

---@param dt number
function WeatherOverlayWidget:UpdateParticles(dt)
    local mode = self.mode_
    if mode ~= "rain" and mode ~= "snow" then
        return
    end

    local n = #self.drops_
    local snow = mode == "snow"
    for i = 1, n do
        local d = self.drops_[i]
        if d then
            d.y = d.y + d.speed * dt * (snow and 0.35 or 1.0)
            if snow then
                d.x = d.x + math.sin(d.phase + d.y * 12.0) * dt * 0.03
            else
                d.x = d.x + dt * 0.01
            end
            if d.y > 1.05 then
                d.y = -0.05
                d.x = math.random()
                d.phase = math.random() * math.pi * 2
            end
            if d.x > 1.0 then d.x = d.x - 1.0 end
        end
    end
end

---@param nvg NVGContextWrapper
function WeatherOverlayWidget:Render(nvg)
    local l = self:GetAbsoluteLayout()
    if l.w <= 0 or l.h <= 0 then
        return
    end

    local mode = self.mode_
    local intensity = self.intensity_
    if intensity > 0 and (mode == "rain" or mode == "snow") then
        local count = math.floor(#self.drops_ * intensity)
        if mode == "rain" then
            nvgBeginPath(nvg)
            nvgStrokeColor(nvg, nvgRGBA(175, 200, 240, math.floor(150 * intensity)))
            nvgStrokeWidth(nvg, 1.4)
            for i = 1, count do
                local d = self.drops_[i]
                if d then
                    local x = l.x + d.x * l.w
                    local y = l.y + d.y * l.h
                    nvgMoveTo(nvg, x, y)
                    nvgLineTo(nvg, x + l.w * 0.004, y + d.len * l.h)
                end
            end
            nvgStroke(nvg)
        else
            nvgFillColor(nvg, nvgRGBA(240, 246, 255, math.floor(210 * intensity)))
            for i = 1, count do
                local d = self.drops_[i]
                if d then
                    nvgBeginPath(nvg)
                    nvgCircle(nvg, l.x + d.x * l.w, l.y + d.y * l.h, 1.6 + (i % 3) * 0.35)
                    nvgFill(nvg)
                end
            end
        end
    end

    if self.flash_ > 0 then
        nvgBeginPath(nvg)
        nvgRect(nvg, l.x, l.y, l.w, l.h)
        nvgFillColor(nvg, nvgRGBA(245, 248, 255, math.floor(190 * self.flash_)))
        nvgFill(nvg)
    end
end

-- ====================================================================
-- 对外包装
-- ====================================================================

---@class WeatherOverlay
---@field widget WeatherOverlayWidget
local WeatherOverlay = {}
WeatherOverlay.__index = WeatherOverlay

---@param uiRoot Widget
---@return WeatherOverlay
function WeatherOverlay.new(uiRoot)
    local self = setmetatable({}, WeatherOverlay)
    self.widget = WeatherOverlayWidget({})
    uiRoot:AddChild(self.widget)
    return self
end

---@param mode string
---@param intensity number
---@param flash number
function WeatherOverlay:set(mode, intensity, flash)
    self.widget:SetWeather(mode, intensity, flash)
end

---@param dt number
function WeatherOverlay:update(dt)
    self.widget:UpdateParticles(dt)
end

return WeatherOverlay
