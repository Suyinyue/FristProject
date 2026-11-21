-- ====================================================================
-- items/ProjectileManager.lua
-- 弓箭投射物（简易版）
--
--   - 箭沿视线方向飞行，撞到固体方块或生物后消失
--   - 命中生物造成 攻击力/护甲 伤害（与近战同一公式）
-- ====================================================================

local Config = require("config.GameConfig")
local Blocks = require("data.BlockRegistry")

local BLOCK_SIZE = Config.World.BLOCK_SIZE
local AIR = Blocks.AIR

-- 共享材质
local arrowMaterial = nil

---@return Material
local function getArrowMaterial()
    if not arrowMaterial then
        arrowMaterial = Material:new()
        arrowMaterial:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTexture.xml"))
        arrowMaterial:SetShaderParameter("MatDiffColor", Variant(Color(0.55, 0.42, 0.25)))
    end
    return arrowMaterial
end

---@class Projectile
---@field node Node
---@field velocity Vector3
---@field life number
---@field attack number

---@class ProjectileManager
---@field scene Scene
---@field world World
---@field arrows Projectile[]
local ProjectileManager = {}
ProjectileManager.__index = ProjectileManager

---@param scene Scene
---@param world World
---@return ProjectileManager
function ProjectileManager.new(scene, world)
    local self = setmetatable({}, ProjectileManager)
    self.scene = scene
    self.world = world
    self.arrows = {}
    return self
end

---发射一支箭
---@param position Vector3
---@param direction Vector3
---@param attack number
---@return Projectile
function ProjectileManager:spawnArrow(position, direction, attack)
    local dir = direction:Normalized()

    local node = self.scene:CreateChild("Arrow")
    node.position = position
    local yaw = math.deg(math.atan(dir.x, dir.z))
    local pitch = -math.deg(math.asin(math.max(-1, math.min(1, dir.y))))
    node.rotation = Quaternion(pitch, yaw, 0)

    local body = node:CreateChild("Body")
    body.scale = Vector3(0.05, 0.05, 0.7) * BLOCK_SIZE
    local model = body:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Box.mdl")
    model.material = getArrowMaterial()

    local projectile = {
        node = node,
        velocity = dir * 40.0,
        life = 3.0,
        attack = attack,
    }
    self.arrows[#self.arrows + 1] = projectile
    return projectile
end

---@param projectile Projectile
function ProjectileManager:remove(projectile)
    if projectile.node then
        projectile.node:Remove()
        projectile.node = nil
    end
end

---每帧更新
---@param dt number
---@param mobs Mob[]
function ProjectileManager:update(dt, mobs)
    for i = #self.arrows, 1, -1 do
        local arrow = self.arrows[i]
        arrow.life = arrow.life - dt

        local remove = arrow.life <= 0
        if not remove and arrow.node then
            local pos = arrow.node.position + arrow.velocity * dt
            arrow.node.position = pos

            -- 撞方块
            local bx = math.floor(pos.x / BLOCK_SIZE)
            local by = math.floor(pos.y / BLOCK_SIZE)
            local bz = math.floor(pos.z / BLOCK_SIZE)
            local block = self.world:getBlock(bx, by, bz)
            if block ~= AIR and Blocks:isSolid(block) then
                remove = true
            end

            -- 撞生物
            if not remove and mobs then
                for _, mob in ipairs(mobs) do
                    if not mob:isDead() then
                        local mp = mob:getPosition()
                        local dx = mp.x - pos.x
                        local dy = (mp.y + BLOCK_SIZE * 0.5) - pos.y
                        local dz = mp.z - pos.z
                        if dx * dx + dy * dy + dz * dz < (BLOCK_SIZE * 0.6) ^ 2 then
                            mob:takeDamage(arrow.attack)
                            remove = true
                            break
                        end
                    end
                end
            end
        end

        if remove then
            self:remove(arrow)
            table.remove(self.arrows, i)
        end
    end
end

---销毁全部箭
function ProjectileManager:destroy()
    for _, arrow in ipairs(self.arrows) do
        self:remove(arrow)
    end
    self.arrows = {}
end

return ProjectileManager
