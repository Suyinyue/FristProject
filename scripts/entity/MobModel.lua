-- ====================================================================
-- entity/MobModel.lua
-- 生物方块模型（比单个方块精致：躯干/头/吻部/眼睛/四肢/尾巴/翅膀等）
--
-- 性能要点：
--   - 材质按颜色缓存共享（同类型生物共用同一批 Material，不会每只新建）
--   - 部件数控制在 8~12 个方格，远处生物由 Mob 整体禁用节点
-- ====================================================================

local Config = require("config.GameConfig")

local BLOCK_SIZE = Config.World.BLOCK_SIZE

-- ============================================================
-- 共享材质缓存（颜色 → Material）
-- ============================================================
---@type table<string, Material>
local materialCache = {}

---获取（或创建）纯色材质
---@param r number 0-1
---@param g number 0-1
---@param b number 0-1
---@return Material
local function getMaterial(r, g, b)
    local key = string.format("%.3f,%.3f,%.3f", r, g, b)
    local mat = materialCache[key]
    if not mat then
        mat = Material:new()
        mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTexture.xml"))
        mat:SetShaderParameter("MatDiffColor", Variant(Color(r, g, b)))
        materialCache[key] = mat
    end
    return mat
end

---颜色明暗调整
---@param c number[] {r,g,b}
---@param factor number 0-1 之间（<1 变暗，>1 变亮）
---@return number, number, number
local function shade(c, factor)
    local r = math.min(1, c[1] * factor)
    local g = math.min(1, c[2] * factor)
    local b = math.min(1, c[3] * factor)
    return r, g, b
end

---向父节点添加一个方块部件
---@param parent Node 父节点
---@param name string 部件名
---@param pos number[] {x,y,z}（方块单位，相对父节点）
---@param size number[] {w,h,d}（方块单位）
---@param r number 红 0-1
---@param g number 绿 0-1
---@param b number 蓝 0-1
---@return Node
local function addBox(parent, name, pos, size, r, g, b)
    local node = parent:CreateChild(name)
    node.position = Vector3(pos[1] * BLOCK_SIZE, pos[2] * BLOCK_SIZE, pos[3] * BLOCK_SIZE)
    node.scale = Vector3(size[1] * BLOCK_SIZE, size[2] * BLOCK_SIZE, size[3] * BLOCK_SIZE)
    local model = node:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")
    model.material = getMaterial(r, g, b)
    return node
end

-- ============================================================
-- 各类生物外形参数（方块单位）
-- ============================================================
---@class MobModel
---@field root Node
---@field legs { pivot: Node, sign: number }[]
---@field arms { pivot: Node, sign: number }[]
---@field wings { pivot: Node, sign: number }[]
---@field bodyGroup Node|nil
---@field bobBase number
---@field bobPhase number
---@field walkPhase number
---@field flapPhase number
---@field kind string
local MobModel = {}
MobModel.__index = MobModel

---各类型模型种类
local KINDS = {
    ZOMBIE = "biped", ARCHER = "biped", BOMBER = "bomber", GHOST = "ghost",
    COW = "quadruped", SHEEP = "quadruped", PIG = "quadruped", CHICKEN = "bird",
}

---创建生物模型
---@param parentNode Node 生物根节点
---@param mobType string 生物类型键
---@param def table 生物定义（Config.Mobs 项）
---@return MobModel
function MobModel.new(parentNode, mobType, def)
    local self = setmetatable({}, MobModel)
    self.root = parentNode
    self.legs = {}
    self.arms = {}
    self.wings = {}
    self.bodyGroup = nil
    self.bobBase = 0
    self.bobPhase = 0
    self.walkPhase = 0
    self.flapPhase = 0

    local kind = KINDS[mobType] or "biped"
    self.kind = kind
    local c = def.color or { 0.7, 0.7, 0.7 }

    if kind == "biped" then
        self:buildBiped(c, mobType, def)
    elseif kind == "bomber" then
        self:buildBomber(c)
    elseif kind == "ghost" then
        self:buildGhost(c)
    elseif kind == "quadruped" then
        self:buildQuadruped(c, mobType)
    else
        self:buildBird(c)
    end

    return self
end

-- ============================================================
-- 双足人形（僵尸 / 弓箭手）
-- ============================================================
---@param c number[] 主色
---@param mobType string
---@param def table
function MobModel:buildBiped(c, mobType, def)
    local root = self.root
    local isArcher = (mobType == "ARCHER")
    -- 弓箭手用皮革棕，僵尸用主色
    local skinR, skinG, skinB = shade(c, 1.1)
    local shirtR, shirtG, shirtB = shade(c, 0.8)
    local pantR, pantG, pantB = shade(c, 0.55)

    -- 躯干
    addBox(root, "Torso", { 0, 1.05, 0 }, { 0.52, 0.68, 0.30 }, shirtR, shirtG, shirtB)
    -- 胯部
    addBox(root, "Hips", { 0, 0.72, 0 }, { 0.48, 0.14, 0.28 }, pantR, pantG, pantB)

    -- 头
    local head = addBox(root, "Head", { 0, 1.62, 0 }, { 0.46, 0.46, 0.46 }, skinR, skinG, skinB)
    -- 眼睛（深色小块，朝前）
    addBox(head, "EyeL", { -0.10, 0.05, 0.24 }, { 0.09, 0.06, 0.03 }, 0.08, 0.08, 0.10)
    addBox(head, "EyeR", { 0.10, 0.05, 0.24 }, { 0.09, 0.06, 0.03 }, 0.08, 0.08, 0.10)
    -- 嘴（僵尸裂口 / 弓箭手口罩）
    addBox(head, "Mouth", { 0, -0.12, 0.24 }, { 0.16, 0.05, 0.02 }, 0.15, 0.10, 0.10)

    -- 手臂（肩部为轴心，便于摆动）
    for i, sign in ipairs({ -1, 1 }) do
        local shoulder = root:CreateChild("Shoulder" .. i)
        shoulder.position = Vector3(sign * 0.36 * BLOCK_SIZE, 1.30 * BLOCK_SIZE, 0)
        local armNode = addBox(shoulder, "Arm", { 0, -0.30, 0 }, { 0.16, 0.62, 0.16 }, shirtR, shirtG, shirtB)
        addBox(armNode, "Hand", { 0, -0.30, 0 }, { 0.17, 0.12, 0.17 }, skinR, skinG, skinB)
        self.arms[#self.arms + 1] = { pivot = shoulder, sign = sign }
    end

    -- 腿（胯部为轴心）
    for i, sign in ipairs({ -1, 1 }) do
        local hip = root:CreateChild("Hip" .. i)
        hip.position = Vector3(sign * 0.14 * BLOCK_SIZE, 0.72 * BLOCK_SIZE, 0)
        addBox(hip, "Leg", { 0, -0.34, 0 }, { 0.19, 0.66, 0.19 }, pantR, pantG, pantB)
        addBox(hip, "Foot", { 0, -0.66, 0.03 }, { 0.20, 0.10, 0.26 }, 0.18, 0.16, 0.14)
        self.legs[#self.legs + 1] = { pivot = hip, sign = sign }
    end

    if isArcher then
        -- 背上的箭袋 + 手里的弓
        addBox(root, "Quiver", { 0.22, 1.10, -0.22 }, { 0.14, 0.34, 0.10 }, 0.35, 0.22, 0.12)
        addBox(root, "QuiverTop", { 0.22, 1.30, -0.22 }, { 0.15, 0.06, 0.11 }, 0.85, 0.85, 0.80)
        local bow = addBox(root, "Bow", { -0.42, 1.00, 0.14 }, { 0.06, 0.62, 0.06 }, 0.45, 0.28, 0.12)
        bow.rotation = Quaternion(0, 0, 12)
    end
end

-- ============================================================
-- 炸弹人（圆胖身体 + 翅膀 + 引线）
-- ============================================================
---@param c number[] 主色
function MobModel:buildBomber(c)
    local root = self.root
    local bodyR, bodyG, bodyB = shade(c, 1.0)
    local darkR, darkG, darkB = shade(c, 0.6)

    -- 身体（偏圆：宽高接近）
    addBox(root, "Torso", { 0, 0.80, 0 }, { 0.66, 0.64, 0.60 }, bodyR, bodyG, bodyB)
    addBox(root, "Belly", { 0, 0.62, 0.05 }, { 0.56, 0.30, 0.56 }, darkR, darkG, darkB)

    -- 头
    local head = addBox(root, "Head", { 0, 1.24, 0 }, { 0.42, 0.40, 0.42 }, bodyR, bodyG, bodyB)
    addBox(head, "EyeL", { -0.09, 0.02, 0.22 }, { 0.09, 0.09, 0.03 }, 1.0, 0.35, 0.15)
    addBox(head, "EyeR", { 0.09, 0.02, 0.22 }, { 0.09, 0.09, 0.03 }, 1.0, 0.35, 0.15)
    addBox(head, "Cap", { 0, 0.22, 0 }, { 0.30, 0.10, 0.30 }, darkR, darkG, darkB)

    -- 引线（顶部小方块，橙色）
    addBox(head, "Fuse", { 0, 0.36, 0 }, { 0.06, 0.16, 0.06 }, 0.35, 0.25, 0.15)
    addBox(head, "Spark", { 0, 0.46, 0 }, { 0.10, 0.08, 0.10 }, 1.0, 0.72, 0.20)

    -- 翅膀（左右可扇动）
    for i, sign in ipairs({ -1, 1 }) do
        local wingPivot = root:CreateChild("WingPivot" .. i)
        wingPivot.position = Vector3(sign * 0.34 * BLOCK_SIZE, 0.95 * BLOCK_SIZE, -0.06 * BLOCK_SIZE)
        addBox(wingPivot, "Wing", { sign * 0.22, 0, 0 }, { 0.46, 0.05, 0.34 }, darkR, darkG, darkB)
        self.wings[#self.wings + 1] = { pivot = wingPivot, sign = sign }
    end

    -- 腿
    for i, sign in ipairs({ -1, 1 }) do
        local hip = root:CreateChild("Hip" .. i)
        hip.position = Vector3(sign * 0.16 * BLOCK_SIZE, 0.50 * BLOCK_SIZE, 0)
        addBox(hip, "Leg", { 0, -0.22, 0 }, { 0.18, 0.44, 0.18 }, darkR, darkG, darkB)
        self.legs[#self.legs + 1] = { pivot = hip, sign = sign }
    end
end

-- ============================================================
-- 幽灵（悬浮、下摆飘散、无腿）
-- ============================================================
---@param c number[] 主色
function MobModel:buildGhost(c)
    local root = self.root
    local bodyR, bodyG, bodyB = shade(c, 1.0)
    local wispR, wispG, wispB = shade(c, 0.85)

    -- 身体组（用于上下浮动）
    self.bodyGroup = root:CreateChild("BodyGroup")
    local g = self.bodyGroup

    addBox(g, "Torso", { 0, 0.95, 0 }, { 0.52, 0.62, 0.44 }, bodyR, bodyG, bodyB)
    -- 下摆三层，逐渐变窄（飘散感）
    addBox(g, "Skirt1", { 0, 0.58, 0 }, { 0.50, 0.16, 0.42 }, wispR, wispG, wispB)
    addBox(g, "Skirt2", { -0.06, 0.44, 0.02 }, { 0.34, 0.14, 0.30 }, wispR, wispG, wispB)
    addBox(g, "Skirt3", { 0.07, 0.32, -0.03 }, { 0.22, 0.12, 0.20 }, wispR, wispG, wispB)

    -- 头
    local head = addBox(g, "Head", { 0, 1.36, 0 }, { 0.44, 0.42, 0.40 }, bodyR, bodyG, bodyB)
    addBox(head, "EyeL", { -0.10, 0.04, 0.21 }, { 0.10, 0.11, 0.03 }, 0.10, 0.10, 0.22)
    addBox(head, "EyeR", { 0.10, 0.04, 0.21 }, { 0.10, 0.11, 0.03 }, 0.10, 0.10, 0.22)
    addBox(head, "Mouth", { 0, -0.12, 0.21 }, { 0.10, 0.08, 0.02 }, 0.12, 0.10, 0.20)

    -- 手臂（细长，摆动）
    for i, sign in ipairs({ -1, 1 }) do
        local shoulder = g:CreateChild("Shoulder" .. i)
        shoulder.position = Vector3(sign * 0.30 * BLOCK_SIZE, 1.12 * BLOCK_SIZE, 0)
        addBox(shoulder, "Arm", { 0, -0.24, 0 }, { 0.13, 0.48, 0.13 }, wispR, wispG, wispB)
        self.arms[#self.arms + 1] = { pivot = shoulder, sign = sign }
    end
end

-- ============================================================
-- 四足动物（牛 / 羊 / 猪）
-- ============================================================
---@param c number[] 主色
---@param mobType string
function MobModel:buildQuadruped(c, mobType)
    local root = self.root
    local isCow = (mobType == "COW")
    local isPig = (mobType == "PIG")

    -- 四足都是「身体较长、头在前方」的体型
    local bodyW = isCow and 0.66 or (isPig and 0.60 or 0.62)
    local bodyH = isPig and 0.46 or 0.52
    local bodyD = isCow and 1.10 or 0.94

    local bodyR, bodyG, bodyB = shade(c, 1.0)
    local darkR, darkG, darkB = shade(c, 0.78)

    -- 躯干
    addBox(root, "Torso", { 0, bodyH * 0.5 + 0.34, 0 }, { bodyW, bodyH, bodyD }, bodyR, bodyG, bodyB)

    -- 头（在前方 +Z）
    local headY = bodyH + 0.44
    local headZ = bodyD * 0.5 + 0.12
    local head = addBox(root, "Head", { 0, headY, headZ }, { 0.42, 0.40, 0.40 }, bodyR, bodyG, bodyB)
    -- 吻部
    addBox(head, "Snout", { 0, -0.06, 0.24 }, { 0.30, 0.20, 0.16 }, darkR, darkG, darkB)
    -- 眼睛
    addBox(head, "EyeL", { -0.11, 0.07, 0.21 }, { 0.07, 0.07, 0.03 }, 0.08, 0.08, 0.10)
    addBox(head, "EyeR", { 0.11, 0.07, 0.21 }, { 0.07, 0.07, 0.03 }, 0.08, 0.08, 0.10)

    if isCow then
        -- 牛角
        addBox(head, "HornL", { -0.16, 0.22, 0.02 }, { 0.06, 0.16, 0.06 }, 0.92, 0.88, 0.76)
        addBox(head, "HornR", { 0.16, 0.22, 0.02 }, { 0.06, 0.16, 0.06 }, 0.92, 0.88, 0.76)
        -- 奶牛花纹
        addBox(root, "Patch1", { 0.30, bodyH * 0.5 + 0.36, 0.18 }, { 0.10, 0.30, 0.34 }, 0.12, 0.12, 0.14)
        addBox(root, "Patch2", { -0.30, bodyH * 0.5 + 0.38, -0.22 }, { 0.10, 0.26, 0.30 }, 0.12, 0.12, 0.14)
    elseif not isPig then
        -- 羊耳
        addBox(head, "EarL", { -0.22, 0.10, 0.0 }, { 0.14, 0.10, 0.08 }, darkR, darkG, darkB)
        addBox(head, "EarR", { 0.22, 0.10, 0.0 }, { 0.14, 0.10, 0.08 }, darkR, darkG, darkB)
        -- 羊毛绒边
        addBox(root, "Fleece", { 0, bodyH * 0.5 + 0.36, 0 }, { bodyW + 0.10, bodyH + 0.10, bodyD + 0.06 }, 1.0, 1.0, 1.0)
    else
        -- 猪耳
        addBox(head, "EarL", { -0.14, 0.20, 0.02 }, { 0.10, 0.12, 0.05 }, darkR, darkG, darkB)
        addBox(head, "EarR", { 0.14, 0.20, 0.02 }, { 0.10, 0.12, 0.05 }, darkR, darkG, darkB)
        -- 猪鼻
        addBox(head, "Nose", { 0, -0.12, 0.30 }, { 0.16, 0.10, 0.08 }, 0.90, 0.55, 0.60)
    end

    -- 尾巴
    local tailPivot = root:CreateChild("TailPivot")
    tailPivot.position = Vector3(0, bodyH + 0.42, -bodyD * 0.5 - 0.04)
    addBox(tailPivot, "Tail", { 0, -0.12, -0.06 }, { 0.07, 0.26, 0.07 }, darkR, darkG, darkB)

    -- 四条腿
    local legH = 0.46
    local legY = legH * 0.5
    local positions = {
        { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 },
    }
    for i, p in ipairs(positions) do
        local x = p[1] * (bodyW * 0.5 - 0.08)
        local z = p[2] * (bodyD * 0.5 - 0.16)
        local hip = root:CreateChild("Hip" .. i)
        hip.position = Vector3(x * BLOCK_SIZE, (legH + 0.02) * BLOCK_SIZE, z * BLOCK_SIZE)
        addBox(hip, "Leg", { 0, -legY, 0 }, { 0.16, legH, 0.16 }, darkR, darkG, darkB)
        self.legs[#self.legs + 1] = { pivot = hip, sign = (i % 2 == 1) and 1 or -1 }
    end
end

-- ============================================================
-- 鸟类（鸡）
-- ============================================================
---@param c number[] 主色
function MobModel:buildBird(c)
    local root = self.root
    local bodyR, bodyG, bodyB = shade(c, 1.0)
    local wingR, wingG, wingB = shade(c, 0.85)

    -- 身体
    addBox(root, "Torso", { 0, 0.44, 0 }, { 0.38, 0.34, 0.32 }, bodyR, bodyG, bodyB)
    -- 头
    local head = addBox(root, "Head", { 0, 0.72, 0.10 }, { 0.22, 0.22, 0.22 }, bodyR, bodyG, bodyB)
    -- 喙
    addBox(head, "Beak", { 0, -0.02, 0.14 }, { 0.08, 0.06, 0.10 }, 0.95, 0.70, 0.20)
    -- 鸡冠
    addBox(head, "Comb", { 0, 0.14, 0.02 }, { 0.06, 0.08, 0.12 }, 0.85, 0.15, 0.15)
    -- 眼睛
    addBox(head, "EyeL", { -0.08, 0.03, 0.11 }, { 0.04, 0.04, 0.02 }, 0.08, 0.08, 0.10)
    addBox(head, "EyeR", { 0.08, 0.03, 0.11 }, { 0.04, 0.04, 0.02 }, 0.08, 0.08, 0.10)
    -- 尾巴
    addBox(root, "Tail", { 0, 0.56, -0.20 }, { 0.16, 0.18, 0.10 }, wingR, wingG, wingB)

    -- 翅膀
    for i, sign in ipairs({ -1, 1 }) do
        local wingPivot = root:CreateChild("WingPivot" .. i)
        wingPivot.position = Vector3(sign * 0.16 * BLOCK_SIZE, 0.50 * BLOCK_SIZE, 0)
        addBox(wingPivot, "Wing", { sign * 0.10, 0, 0 }, { 0.20, 0.06, 0.24 }, wingR, wingG, wingB)
        self.wings[#self.wings + 1] = { pivot = wingPivot, sign = sign }
    end

    -- 细腿
    for i, sign in ipairs({ -1, 1 }) do
        local hip = root:CreateChild("Hip" .. i)
        hip.position = Vector3(sign * 0.08 * BLOCK_SIZE, 0.28 * BLOCK_SIZE, 0)
        addBox(hip, "Leg", { 0, -0.12, 0 }, { 0.05, 0.24, 0.05 }, 0.95, 0.62, 0.20)
        self.legs[#self.legs + 1] = { pivot = hip, sign = sign }
    end
end

-- ============================================================
-- 动画
-- ============================================================

---每帧更新模型动画
---@param dt number 时间步长
---@param moving boolean 是否在移动
---@param bob boolean 是否上下浮动（幽灵）
function MobModel:update(dt, moving, bob)
    -- 行走相位
    if moving then
        self.walkPhase = self.walkPhase + dt * 9.0
    else
        self.walkPhase = self.walkPhase * 0.85
    end
    local swing = math.sin(self.walkPhase) * 30

    for _, leg in ipairs(self.legs) do
        leg.pivot.rotation = Quaternion(swing * leg.sign, 0, 0)
    end
    for _, arm in ipairs(self.arms) do
        arm.pivot.rotation = Quaternion(-swing * arm.sign, 0, 0)
    end

    -- 翅膀扇动
    self.flapPhase = self.flapPhase + dt * 10.0
    local flap = math.sin(self.flapPhase) * 34
    for _, wing in ipairs(self.wings) do
        wing.pivot.rotation = Quaternion(0, 0, flap * wing.sign)
    end

    -- 幽灵上下浮动
    if bob and self.bodyGroup then
        self.bobPhase = self.bobPhase + dt * 2.2
        local y = math.sin(self.bobPhase) * 0.18 * BLOCK_SIZE
        self.bodyGroup.position = Vector3(0, y, 0)
    end
end

return MobModel
