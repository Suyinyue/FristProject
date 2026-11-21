-- ====================================================================
-- entity/HealthBar.lua
-- 生物头顶悬浮血条（3D 盒型，绿→黄→红）
--
-- 结构：容器节点 → 背景盒 + 填充盒（填充盒前移，避免被背景盒挡住）
-- 容器可整体旋转朝向玩家
-- ====================================================================

---创建纯色材质
---@param r number 红 0-1
---@param g number 绿 0-1
---@param b number 蓝 0-1
---@return Material
local function makeColorMaterial(r, g, b)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", Variant(Color(r, g, b)))
    return mat
end

---@class HealthBar
---@field container Node
---@field bgNode Node
---@field fgNode Node
---@field fgModel StaticModel
---@field fgMaterial Material
---@field barW number
---@field barH number
---@field barD number
---@field yOffset number
local HealthBar = {}
HealthBar.__index = HealthBar

---创建血条（挂到生物节点下，随生物移动）
---@param parentNode Node 生物节点
---@param maxHealth number 最大血量
---@param yOffset number|nil 血条高度（世界单位，默认 2.0）
---@param barW number|nil 血条宽度（世界单位，默认 1.4）
---@return HealthBar
function HealthBar.new(parentNode, maxHealth, yOffset, barW)
    local self = setmetatable({}, HealthBar)
    self.maxHealth = maxHealth
    self.barW = barW or 1.4
    self.barH = 0.20
    self.barD = 0.10
    self.yOffset = yOffset or 2.0

    -- 容器（便于整体旋转朝向玩家）
    self.container = parentNode:CreateChild("HealthBar")
    self.container.position = Vector3(0, self.yOffset, 0)

    -- 背景（深色，略大于填充）
    self.bgNode = self.container:CreateChild("BG")
    self.bgNode.scale = Vector3(self.barW, self.barH, self.barD)
    local bgModel = self.bgNode:CreateComponent("StaticModel")
    bgModel.model = cache:GetResource("Model", "Models/Box.mdl")
    bgModel.material = makeColorMaterial(0.06, 0.06, 0.08)

    -- 填充（前移到背景盒外面，否则会被挡成一根黑条）
    local fgDepth = self.barD * 0.35
    local fgZ = self.barD * 0.5 + fgDepth * 0.5 + 0.005
    self.fgZ = fgZ
    self.fgDepth = fgDepth
    self.fgNode = self.container:CreateChild("FG")
    self.fgNode.position = Vector3(0, 0, fgZ)
    self.fgNode.scale = Vector3(self.barW, self.barH * 0.62, fgDepth)
    self.fgModel = self.fgNode:CreateComponent("StaticModel")
    self.fgModel.model = cache:GetResource("Model", "Models/Box.mdl")
    self.fgMaterial = makeColorMaterial(0.2, 0.8, 0.2)
    self.fgModel.material = self.fgMaterial

    self:setHealth(maxHealth, maxHealth)
    return self
end

---更新血条显示
---@param health number 当前血量
---@param maxHealth number 最大血量
function HealthBar:setHealth(health, maxHealth)
    local frac = maxHealth > 0 and (health / maxHealth) or 0.0
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end

    local w = self.barW * frac
    if w < 0.02 then w = 0.02 end

    -- 左对齐：中心 X = -(barW - w)/2
    self.fgNode.scale = Vector3(w, self.barH * 0.62, self.fgDepth)
    self.fgNode.position = Vector3(-(self.barW - w) / 2, 0, self.fgZ)

    -- 颜色：满血绿 → 半血红 → 残血红
    local r, g = 0.9, 0.2
    if frac > 0.5 then
        r = (1.0 - frac) * 2.0 * 0.9
        g = 0.8
    else
        r = 0.9
        g = frac * 2.0 * 0.8
    end
    if r < 0 then r = 0 elseif r > 0.9 then r = 0.9 end
    if g < 0 then g = 0 elseif g > 0.8 then g = 0.8 end

    if self.fgMaterial then
        self.fgMaterial:SetShaderParameter("MatDiffColor", Variant(Color(r, g, 0.15)))
    end
end

---设置朝向（绕 Y 轴），让血条面向玩家
---@param yawDeg number 角度
function HealthBar:setYaw(yawDeg)
    if self.container then
        self.container.rotation = Quaternion(0, yawDeg, 0)
    end
end

---设置整体可见性
---@param visible boolean
function HealthBar:setVisible(visible)
    if self.container then
        self.container:SetDeepEnabled(visible)
    end
end

---销毁血条节点
function HealthBar:destroy()
    if self.container then
        self.container:Remove()
        self.container = nil
        self.bgNode = nil
        self.fgNode = nil
    end
end

return HealthBar
