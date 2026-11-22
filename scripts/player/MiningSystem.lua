-- ====================================================================
-- player/MiningSystem.lua
-- 持续挖掘：按住左键累积进度，完成后才破坏方块。
--
--   - 硬度/工具效率来自 data/MiningRules.lua
--   - 目标变化 / 松开 / 切换物品 / 超出距离 / 死亡 / 打开 UI → 立即中断
--   - 视觉：方块表面的裂纹立方体（4 级程序化裂纹贴图）+ 阶段粒子
--   - 完成后调用 BlockInteraction:breakBlockAt 走正常破坏/掉落/耐久逻辑
-- ====================================================================

local Config = require("config.GameConfig")
local Blocks = require("data.BlockRegistry")
local MiningRules = require("data.MiningRules")

local BLOCK_SIZE = Config.World.BLOCK_SIZE

-- ====================================================================
-- 裂纹贴图（程序化生成，透明背景 + 深色裂纹）
-- ====================================================================

---@param seed integer
---@return function
local function makeRng(seed)
    local s = seed % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function()
        s = (s * 48271) % 2147483647
        return s / 2147483647
    end
end

---@param image Image
---@param x integer
---@param y integer
local function crackPixel(image, x, y)
    if x < 0 or y < 0 or x >= 32 or y >= 32 then
        return
    end
    image:SetPixel(x, y, Color(0.05, 0.05, 0.05, 0.85))
    image:SetPixel(math.min(31, x + 1), y, Color(0.05, 0.05, 0.05, 0.55))
end

---@param stage integer 1..4
---@return Image
local function createCrackImage(stage)
    local image = Image:new()
    image:SetSize(32, 32, 4)
    image:Clear(Color(0, 0, 0, 0))
    local rng = makeRng(9001 + stage * 131)

    local lines = 2 + stage * 2
    for i = 1, lines do
        local x = math.floor(rng() * 32)
        local y = math.floor(rng() * 32)
        local steps = 6 + math.floor(rng() * 10)
        ---@type integer
        local dx = rng() < 0.5 and -1 or 1
        ---@type integer
        local dy = rng() < 0.5 and -1 or 1
        for _ = 1, steps do
            crackPixel(image, x, y)
            if rng() < 0.45 then dx = -dx end
            if rng() < 0.45 then dy = -dy end
            x = x + dx
            y = y + dy
        end
    end
    return image
end

---@param image Image
---@return Texture2D
local function createCrackTexture(image)
    local texture = Texture2D:new()
    texture:SetSRGB(true)
    texture:SetNumLevels(1)
    texture:SetFilterMode(FILTER_NEAREST)
    texture:SetData(image, false)
    return texture
end

-- ====================================================================
-- 裂纹立方体
-- ====================================================================

local CUBE_FACES = {
    { n = { 1, 0, 0 }, v = {
        { 0.5, -0.5, -0.5, 1, 1 }, { 0.5, 0.5, -0.5, 1, 0 }, { 0.5, 0.5, 0.5, 0, 0 },
        { 0.5, -0.5, -0.5, 1, 1 }, { 0.5, 0.5, 0.5, 0, 0 }, { 0.5, -0.5, 0.5, 0, 1 },
    } },
    { n = { -1, 0, 0 }, v = {
        { -0.5, -0.5, 0.5, 1, 1 }, { -0.5, 0.5, 0.5, 1, 0 }, { -0.5, 0.5, -0.5, 0, 0 },
        { -0.5, -0.5, 0.5, 1, 1 }, { -0.5, 0.5, -0.5, 0, 0 }, { -0.5, -0.5, -0.5, 0, 1 },
    } },
    { n = { 0, 1, 0 }, v = {
        { -0.5, 0.5, -0.5, 0, 0 }, { -0.5, 0.5, 0.5, 0, 1 }, { 0.5, 0.5, 0.5, 1, 1 },
        { -0.5, 0.5, -0.5, 0, 0 }, { 0.5, 0.5, 0.5, 1, 1 }, { 0.5, 0.5, -0.5, 1, 0 },
    } },
    { n = { 0, -1, 0 }, v = {
        { -0.5, -0.5, 0.5, 0, 1 }, { -0.5, -0.5, -0.5, 0, 0 }, { 0.5, -0.5, -0.5, 1, 0 },
        { -0.5, -0.5, 0.5, 0, 1 }, { 0.5, -0.5, -0.5, 1, 0 }, { 0.5, -0.5, 0.5, 1, 1 },
    } },
    { n = { 0, 0, 1 }, v = {
        { -0.5, -0.5, 0.5, 0, 1 }, { 0.5, -0.5, 0.5, 1, 1 }, { 0.5, 0.5, 0.5, 1, 0 },
        { -0.5, -0.5, 0.5, 0, 1 }, { 0.5, 0.5, 0.5, 1, 0 }, { -0.5, 0.5, 0.5, 0, 0 },
    } },
    { n = { 0, 0, -1 }, v = {
        { 0.5, -0.5, -0.5, 0, 1 }, { -0.5, -0.5, -0.5, 1, 1 }, { -0.5, 0.5, -0.5, 1, 0 },
        { 0.5, -0.5, -0.5, 0, 1 }, { -0.5, 0.5, -0.5, 1, 0 }, { 0.5, 0.5, -0.5, 0, 0 },
    } },
}

---@class MiningSystem
---@field player Player
---@field blockInteraction BlockInteraction
---@field particleSystem ParticleSystem|nil
---@field node Node|nil
---@field geometry CustomGeometry|nil
---@field materials Material[]
---@field active boolean
---@field progress number
---@field duration number
---@field stage integer
---@field blockX integer
---@field blockY integer
---@field blockZ integer
---@field blockType integer
---@field slotIndex integer
local MiningSystem = {}
MiningSystem.__index = MiningSystem

---@param player Player
---@param blockInteraction BlockInteraction
---@param scene Scene
---@param particleSystem ParticleSystem|nil
---@return MiningSystem
function MiningSystem.new(player, blockInteraction, scene, particleSystem)
    local self = setmetatable({}, MiningSystem)
    self.player = player
    self.blockInteraction = blockInteraction
    self.particleSystem = particleSystem
    self.active = false
    self.progress = 0.0
    self.duration = 1.0
    self.stage = 0
    self.blockX = 0
    self.blockY = 0
    self.blockZ = 0
    self.blockType = 0
    self.slotIndex = 1

    self:createVisual_(scene)
    return self
end

---@param scene Scene
function MiningSystem:createVisual_(scene)
    self.node = scene:CreateChild("MiningCracks")
    self.node.enabled = false
    self.node.scale = Vector3(BLOCK_SIZE * 1.004, BLOCK_SIZE * 1.004, BLOCK_SIZE * 1.004)

    self.geometry = self.node:CreateComponent("CustomGeometry")
    self.geometry:SetNumGeometries(1)
    self.geometry:BeginGeometry(0, TRIANGLE_LIST)
    for _, face in ipairs(CUBE_FACES) do
        local normal = Vector3(face.n[1], face.n[2], face.n[3])
        for _, v in ipairs(face.v) do
            self.geometry:DefineVertex(Vector3(v[1], v[2], v[3]))
            self.geometry:DefineNormal(normal)
            self.geometry:DefineTexCoord(Vector2(v[4], v[5]))
        end
    end
    self.geometry:Commit()

    local technique = cache:GetResource("Technique", "Techniques/DiffUnlitAlpha.xml")
    if not technique then
        technique = cache:GetResource("Technique", "Techniques/DiffAlpha.xml")
    end
    if not technique then
        technique = cache:GetResource("Technique", "Techniques/DiffVCol.xml")
    end

    self.materials = {}
    for stage = 1, 4 do
        local texture = createCrackTexture(createCrackImage(stage))
        local material = Material:new()
        material:SetTechnique(0, technique)
        material:SetTexture(TU_DIFFUSE, texture)
        material:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
        self.materials[stage] = material
    end
    self.geometry:SetMaterial(0, self.materials[1])
end

---@return boolean
function MiningSystem:isMining()
    return self.active
end

---@return number
function MiningSystem:getProgress()
    return self.progress
end

---@return integer
function MiningSystem:getStage()
    return self.stage
end

---开始挖掘（左键按下）
---@return boolean
function MiningSystem:startMining()
    if self.active or not self.player or self.player:isDead() then
        return false
    end

    local bx, by, bz = self.blockInteraction:getTargetBlock()
    if not bx then
        return false
    end
    local world = self.blockInteraction.world
    local blockType = world:getBlock(bx, by, bz)
    if blockType == Blocks.AIR or MiningRules.isUnbreakable(blockType) then
        return false
    end

    local inventory = self.player:getInventory()
    local slot = self.player:getSelectedSlotIndex()
    local heldTool = inventory and inventory:getHeldToolType(slot) or nil
    local duration = MiningRules.miningTime(blockType, heldTool)
    if duration == math.huge or duration <= 0 then
        return false
    end

    self.active = true
    self.progress = 0.0
    self.duration = duration
    self.stage = 0
    self.blockX, self.blockY, self.blockZ = bx, by, bz
    self.blockType = blockType
    self.slotIndex = slot

    if self.node then
        self.node.position = Vector3(
            (bx + 0.5) * BLOCK_SIZE,
            (by + 0.5) * BLOCK_SIZE,
            (bz + 0.5) * BLOCK_SIZE)
        self.node.enabled = true
    end
    if self.geometry then
        self.geometry:SetMaterial(0, self.materials[1])
    end
    return true
end

---中断挖掘
function MiningSystem:stopMining()
    self.active = false
    self.progress = 0.0
    self.stage = 0
    if self.node then
        self.node.enabled = false
    end
end

---@param bx integer
---@param by integer
---@param bz integer
---@return boolean
function MiningSystem:targetStillValid(bx, by, bz)
    if not self.player or self.player:isDead() then
        return false
    end
    if self.player:getSelectedSlotIndex() ~= self.slotIndex then
        return false
    end
    local world = self.blockInteraction.world
    if world:getBlock(bx, by, bz) ~= self.blockType then
        return false
    end
    local tx, ty, tz = self.blockInteraction:getTargetBlock()
    if tx ~= bx or ty ~= by or tz ~= bz then
        return false
    end
    local eye = self.player:getEyePosition()
    local cx = (bx + 0.5) * BLOCK_SIZE
    local cy = (by + 0.5) * BLOCK_SIZE
    local cz = (bz + 0.5) * BLOCK_SIZE
    local dx, dy, dz = cx - eye.x, cy - eye.y, cz - eye.z
    local reach = Config.Player.REACH_DISTANCE + BLOCK_SIZE
    if dx * dx + dy * dy + dz * dz > reach * reach then
        return false
    end
    return true
end

---每帧推进
---@param dt number
function MiningSystem:update(dt)
    if not self.active then
        return
    end
    if not self:targetStillValid(self.blockX, self.blockY, self.blockZ) then
        self:stopMining()
        return
    end

    self.progress = self.progress + dt / self.duration
    local stage = MiningRules.crackStage(self.progress)
    if stage ~= self.stage then
        self.stage = stage
        if self.geometry and self.materials[math.max(1, stage)] then
            self.geometry:SetMaterial(0, self.materials[math.max(1, stage)])
        end
        if self.particleSystem then
            self.particleSystem:spawnBreakParticles(
                self.blockX, self.blockY, self.blockZ, self.blockType)
        end
    end

    if self.progress >= 1.0 then
        local bx, by, bz = self.blockX, self.blockY, self.blockZ
        self:stopMining()
        if self.player.swingArm then
            self.player:swingArm()
        end
        self.blockInteraction:breakBlockAt(bx, by, bz)
    end
end

---销毁节点
function MiningSystem:destroy()
    self:stopMining()
    if self.node then
        self.node:Remove()
        self.node = nil
    end
    self.geometry = nil
    self.materials = {}
end

return MiningSystem
