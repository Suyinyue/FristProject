-- ====================================================================
-- building/TowerManager.lua
-- 防御塔（Design.md「建筑」）
--
-- 建造规则：
--   - 基座由圆石构成，第 k 层（从塔顶往下数）必须正好有 3*k 块
--     圆石（顶层 3、第二层 6、第三层 9 ...）
--   - 攻击台 = 顶层基座上的火焰石
--   - 基座有 n 层 → 攻击范围 3n 格
--   - 同一基座上放多个火焰石时，只激活层数最多（范围最大）的那个
--
-- 结构检测：从火焰石下方那一格开始，逐层向下做「同 y 平面连通块」检测，
-- 每层块数必须等于 3*k，且上一层每块正下方都必须是圆石（不能悬空）。
-- 同一顶层连通块 + 顶层 y 视为同一个基座。
--
-- 攻击：每隔 ATTACK_INTERVAL 秒锁定范围内最近的敌对生物，发射独立轨迹的火焰弹，
-- 命中后造成 ATTACK_DAMAGE 伤害（火焰弹速度 PROJECTILE_SPEED 格/秒）。
-- ====================================================================

local Config = require("config.GameConfig")
local Blocks = require("data.BlockRegistry")

local BLOCK_SIZE = Config.World.BLOCK_SIZE
local BASE_BLOCK = Blocks.COBBLESTONE   -- 基座方块（Design.md：圆石）
local FLAME = Blocks.FLAME_STONE

-- 共享火焰弹材质（自发光，不随光照变化）
---@type Material|nil
local projectileMaterial = nil

---@return Material
local function getProjectileMaterial()
    if not projectileMaterial then
        projectileMaterial = Material:new()
        projectileMaterial:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
        projectileMaterial:SetShaderParameter("MatDiffColor", Variant(Color(2.0, 0.95, 0.30)))
    end
    return projectileMaterial
end

-- 共享光罩材质（半透明，提示攻击范围）
---@type Material|nil
local shieldMaterial = nil

---@return Material
local function getShieldMaterial()
    if not shieldMaterial then
        shieldMaterial = Material:new()
        shieldMaterial:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
        local a = Config.Tower.SHIELD_ALPHA or 0.10
        shieldMaterial:SetShaderParameter("MatDiffColor", Variant(Color(1.0, 0.55, 0.20, a)))
    end
    return shieldMaterial
end

---@class DefenseTower
---@field x integer 火焰石方块坐标
---@field y integer
---@field z integer
---@field layers integer 基座层数
---@field range number 攻击范围（格）
---@field cooldown number
---@field pulse number
---@field lightNode Node|nil
---@field light Light|nil
---@field shieldNode Node|nil

---@class TowerProjectile
---@field node Node
---@field target Mob|nil
---@field tx number
---@field ty number
---@field tz number
---@field damage number
---@field life number

---@class TowerManager
---@field scene Scene
---@field world World
---@field towers DefenseTower[]
---@field flameStones table<string, { x: integer, y: integer, z: integer }>
---@field projectiles TowerProjectile[]
---@field mobProvider fun(): Mob[]|nil
---@field time number
local TowerManager = {}
TowerManager.__index = TowerManager

-- ====================================================================
-- 构造
-- ====================================================================

---@param scene Scene
---@param world World
---@return TowerManager
function TowerManager.new(scene, world)
    local self = setmetatable({}, TowerManager)
    self.scene = scene
    self.world = world
    self.towers = {}
    self.flameStones = {}
    self.projectiles = {}
    self.mobProvider = nil
    self.time = 0.0
    return self
end

---设置生物列表来源（MobManager.mobs）
---@param provider fun(): Mob[]
function TowerManager:setMobProvider(provider)
    self.mobProvider = provider
end

-- ====================================================================
-- 结构检测
-- ====================================================================

---@param x integer
---@param y integer
---@param z integer
---@return string
local function posKey(x, y, z)
    return x .. "," .. y .. "," .. z
end

---@param x integer
---@param z integer
---@return string
local function xzKey(x, z)
    return x .. "," .. z
end

---收集同一 y 平面上的圆石连通块（4 邻域），从 seeds 出发
---@param y integer
---@param seeds { x: integer, z: integer }[]
---@param limit integer 最多收集多少块（超过说明结构不合法，提前停止）
---@return { x: integer, z: integer }[] cells
---@return table<string, boolean> visited
function TowerManager:collectLayer(y, seeds, limit)
    local visited = {}
    local queue = {}
    local cells = {}

    for _, seed in ipairs(seeds) do
        local k = xzKey(seed.x, seed.z)
        if not visited[k] and self.world:getBlock(seed.x, y, seed.z) == BASE_BLOCK then
            visited[k] = true
            queue[#queue + 1] = { x = seed.x, z = seed.z }
            cells[#cells + 1] = { x = seed.x, z = seed.z }
        end
    end

    local head = 1
    local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    while head <= #queue do
        local cur = queue[head]
        head = head + 1
        for _, d in ipairs(dirs) do
            local nx, nz = cur.x + d[1], cur.z + d[2]
            local k = xzKey(nx, nz)
            if not visited[k] and self.world:getBlock(nx, y, nz) == BASE_BLOCK then
                visited[k] = true
                queue[#queue + 1] = { x = nx, z = nz }
                cells[#cells + 1] = { x = nx, z = nz }
                if #cells > limit then
                    return cells, visited
                end
            end
        end
    end

    return cells, visited
end

---检测火焰石下方的基座
---@param fx integer 火焰石 X
---@param fy integer 火焰石 Y
---@param fz integer 火焰石 Z
---@return integer layers 基座层数（0 = 不是有效防御塔）
---@return { x: integer, z: integer }[]|nil topLayer 顶层基座方块
function TowerManager:detectBase(fx, fy, fz)
    local cfg = Config.Tower
    if self.world:getBlock(fx, fy - 1, fz) ~= BASE_BLOCK then
        return 0, nil
    end

    local maxLayers = cfg.MAX_LAYERS
    local topLimit = cfg.LAYER_BLOCK_BASE + 1
    local topLayer = self:collectLayer(fy - 1, { { x = fx, z = fz } }, topLimit)
    if #topLayer ~= cfg.LAYER_BLOCK_BASE then
        return 0, nil
    end

    local layers = 1
    local prev = topLayer

    while layers < maxLayers do
        local k = layers + 1
        local yLevel = fy - k

        -- 上一层每一块正下方都必须是圆石，否则基座在此结束
        for _, cell in ipairs(prev) do
            if self.world:getBlock(cell.x, yLevel, cell.z) ~= BASE_BLOCK then
                return layers, topLayer
            end
        end

        local need = cfg.LAYER_BLOCK_BASE * k
        local comp, visited = self:collectLayer(yLevel, prev, need + 1)
        if #comp ~= need then
            return layers, topLayer
        end

        -- 所有种子必须落在同一个连通块里（不能是两段拼起来凑人数）
        for _, cell in ipairs(prev) do
            if not visited[xzKey(cell.x, cell.z)] then
                return layers, topLayer
            end
        end

        layers = k
        prev = comp
    end

    return layers, topLayer
end

---顶层连通块的稳定标记（同一基座 key 相同）
---@param topLayer { x: integer, z: integer }[]
---@param y integer
---@return string
local function makeBaseKey(topLayer, y)
    local parts = {}
    for _, cell in ipairs(topLayer) do
        parts[#parts + 1] = cell.x .. ":" .. cell.z
    end
    table.sort(parts)
    return y .. "|" .. table.concat(parts, ";")
end

-- ====================================================================
-- 火焰石跟踪 / 重建
-- ====================================================================

---记录一个火焰石方块
---@param x integer
---@param y integer
---@param z integer
function TowerManager:trackFlameStone(x, y, z)
    self.flameStones[posKey(x, y, z)] = { x = x, y = y, z = z }
end

---@param x integer
---@param y integer
---@param z integer
function TowerManager:untrackFlameStone(x, y, z)
    self.flameStones[posKey(x, y, z)] = nil
end

---方块变化回调（由 BlockInteraction 调用）
---@param x integer
---@param y integer
---@param z integer
---@param oldType integer
---@param newType integer
function TowerManager:onBlockChanged(x, y, z, oldType, newType)
    if oldType == FLAME then
        self:untrackFlameStone(x, y, z)
    end
    if newType == FLAME then
        self:trackFlameStone(x, y, z)
    end

    local relevant = oldType == BASE_BLOCK or newType == BASE_BLOCK
        or oldType == FLAME or newType == FLAME
    if relevant then
        self:rebuildTowers()
    end
end

---清除所有塔的灯光节点与光罩
function TowerManager:clearTowerLights()
    for _, tower in ipairs(self.towers) do
        if tower.lightNode then
            tower.lightNode:Remove()
            tower.lightNode = nil
            tower.light = nil
        end
        if tower.shieldNode then
            tower.shieldNode:Remove()
            tower.shieldNode = nil
        end
    end
end

---重新检测所有已知火焰石，重建激活塔列表
function TowerManager:rebuildTowers()
    self:clearTowerLights()
    self.towers = {}

    -- 先按基座分组：同一基座可能放了多个火焰石
    ---@type table<string, { x: integer, y: integer, z: integer, layers: integer, range: number }[]>
    local groups = {}

    for _, fs in pairs(self.flameStones) do
        if self.world:getBlock(fs.x, fs.y, fs.z) == FLAME then
            local layers, topLayer = self:detectBase(fs.x, fs.y, fs.z)
            if layers > 0 and topLayer then
                local key = makeBaseKey(topLayer, fs.y - 1)
                local list = groups[key]
                if not list then
                    list = {}
                    groups[key] = list
                end
                list[#list + 1] = {
                    x = fs.x,
                    y = fs.y,
                    z = fs.z,
                    layers = layers,
                    range = layers * Config.Tower.RANGE_PER_LAYER,
                }
            end
        else
            -- 方块已经不在（例如区块重载），清掉记录
            self:untrackFlameStone(fs.x, fs.y, fs.z)
        end
    end

    for _, list in pairs(groups) do
        -- 只激活层数最多（攻击范围最大）的火焰石；同层数按坐标固定选择
        table.sort(list, function(a, b)
            if a.layers ~= b.layers then
                return a.layers > b.layers
            end
            if a.x ~= b.x then
                return a.x < b.x
            end
            return a.z < b.z
        end)

        local best = list[1]
        ---@type DefenseTower
        local tower = {
            x = best.x,
            y = best.y,
            z = best.z,
            layers = best.layers,
            range = best.range,
            cooldown = 0.0,
            pulse = math.random() * math.pi * 2,
            lightNode = nil,
            light = nil,
        }
        self:createTowerLight(tower)
        self.towers[#self.towers + 1] = tower

        if #list > 1 then
            print(string.format(
                "[Tower] %d 个火焰石共用同一基座，仅激活范围最大者 (%d,%d,%d)，范围 %.0f 格",
                #list, best.x, best.y, best.z, best.range))
        else
            print(string.format("[Tower] 激活防御塔 (%d,%d,%d)：基座 %d 层，范围 %.0f 格",
                best.x, best.y, best.z, best.layers, best.range))
        end
    end
end

---给激活的塔创建火焰石点光源 + 攻击范围光罩
---@param tower DefenseTower
function TowerManager:createTowerLight(tower)
    local node = self.scene:CreateChild("TowerLight")
    node.position = Vector3(
        tower.x * BLOCK_SIZE + BLOCK_SIZE * 0.5,
        tower.y * BLOCK_SIZE + BLOCK_SIZE * 0.75,
        tower.z * BLOCK_SIZE + BLOCK_SIZE * 0.5)

    local light = node:CreateComponent("Light")
    light.lightType = LIGHT_POINT
    light.color = Color(1.0, 0.55, 0.20)
    light.range = Config.Tower.LIGHT_BASE_RANGE + tower.range * BLOCK_SIZE * 0.5
    light.brightness = 2.0
    light.castShadows = false

    tower.lightNode = node
    tower.light = light

    -- 光罩：以火焰石为中心的半透明球，半径 = 攻击范围（Design.md「攻击范围光罩提示」）
    local shield = self.scene:CreateChild("TowerShield")
    shield.position = Vector3(
        tower.x * BLOCK_SIZE + BLOCK_SIZE * 0.5,
        tower.y * BLOCK_SIZE + BLOCK_SIZE * 0.5,
        tower.z * BLOCK_SIZE + BLOCK_SIZE * 0.5)
    -- Sphere.mdl 直径 1（半径 0.5），缩放到攻击范围半径
    local radius = tower.range * BLOCK_SIZE
    shield.scale = Vector3(radius * 2, radius * 2, radius * 2)
    local model = shield:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Sphere.mdl")
    model.material = getShieldMaterial()

    tower.shieldNode = shield
end

-- ====================================================================
-- 攻击
-- ====================================================================

---@param tower DefenseTower
---@return Vector3
local function towerCenter(tower)
    return Vector3(
        tower.x * BLOCK_SIZE + BLOCK_SIZE * 0.5,
        tower.y * BLOCK_SIZE + BLOCK_SIZE * 0.5,
        tower.z * BLOCK_SIZE + BLOCK_SIZE * 0.5)
end

---距离塔最近的敌对生物
---@param tower DefenseTower
---@return Mob|nil
function TowerManager:findTarget(tower)
    if not self.mobProvider then
        return nil
    end

    local mobs = self.mobProvider()
    if not mobs then
        return nil
    end

    local from = towerCenter(tower)
    local maxDist = tower.range * BLOCK_SIZE
    local bestDist2 = maxDist * maxDist
    local best = nil

    for _, mob in ipairs(mobs) do
        if mob.hostile and not mob:isDead() then
            local mp = mob:getPosition()
            local dx = mp.x - from.x
            local dy = (mp.y + BLOCK_SIZE * 0.5) - from.y
            local dz = mp.z - from.z
            local d2 = dx * dx + dy * dy + dz * dz
            if d2 <= bestDist2 then
                bestDist2 = d2
                best = mob
            end
        end
    end

    return best
end

---发射一颗朝目标飞行的火焰弹（独立轨迹）
---@param tower DefenseTower
---@param mob Mob
function TowerManager:spawnProjectile(tower, mob)
    local from = towerCenter(tower)
    local mp = mob:getPosition()
    local ty = mp.y + BLOCK_SIZE * 0.5

    local node = self.scene:CreateChild("TowerProjectile")
    node.position = from
    local size = BLOCK_SIZE * 0.30
    node.scale = Vector3(size, size, size)

    local model = node:CreateComponent("StaticModel")
    model.model = cache:GetResource("Model", "Models/Sphere.mdl")
    model.material = getProjectileMaterial()

    self.projectiles[#self.projectiles + 1] = {
        node = node,
        target = mob,
        tx = mp.x,
        ty = ty,
        tz = mp.z,
        damage = Config.Tower.ATTACK_DAMAGE,
        life = Config.Tower.PROJECTILE_LIFE,
    }
end

---更新火焰弹：朝目标（或最后已知位置）飞行，命中判定后结算伤害
---@param dt number
function TowerManager:updateProjectiles(dt)
    local cfg = Config.Tower
    local step = cfg.PROJECTILE_SPEED * BLOCK_SIZE * dt
    local hitR = cfg.PROJECTILE_HIT_RADIUS * BLOCK_SIZE
    local hitR2 = hitR * hitR

    for i = #self.projectiles, 1, -1 do
        local p = self.projectiles[i]
        p.life = p.life - dt
        if p.life <= 0 or not p.node then
            if p.node then
                p.node:Remove()
                p.node = nil
            end
            table.remove(self.projectiles, i)
        else
            -- 目标仍存活则持续追踪其当前位置
            if p.target and not p.target:isDead() then
                local tp = p.target:getPosition()
                p.tx = tp.x
                p.ty = tp.y + BLOCK_SIZE * 0.5
                p.tz = tp.z
            end

            local pos = p.node.position
            local dx = p.tx - pos.x
            local dy = p.ty - pos.y
            local dz = p.tz - pos.z
            local dist2 = dx * dx + dy * dy + dz * dz

            if dist2 <= hitR2 or dist2 <= step * step then
                -- 命中：对目标结算伤害（目标可能已死，此时只消失不结算）
                if p.target and not p.target:isDead() then
                    p.target:takeDamage(p.damage)
                end
                p.node:Remove()
                p.node = nil
                table.remove(self.projectiles, i)
            else
                local dist = math.sqrt(dist2)
                local k = step / dist
                p.node.position = Vector3(pos.x + dx * k, pos.y + dy * k, pos.z + dz * k)
            end
        end
    end
end

---每帧更新：攻击范围内敌对生物 + 灯光呼吸 + 火焰弹
---@param dt number
function TowerManager:update(dt)
    self.time = self.time + dt
    local cfg = Config.Tower

    for _, tower in ipairs(self.towers) do
        tower.cooldown = tower.cooldown - dt

        if tower.cooldown <= 0 then
            local target = self:findTarget(tower)
            if target then
                self:spawnProjectile(tower, target)
                tower.cooldown = cfg.ATTACK_INTERVAL
            else
                tower.cooldown = cfg.NO_TARGET_RETRY
            end
        end

        if tower.light then
            tower.light.brightness = 1.8 + math.sin(self.time * 4.0 + tower.pulse) * 0.35
        end
    end

    self:updateProjectiles(dt)
end

-- ====================================================================
-- 查询（调试 / 自动化验收）
-- ====================================================================

---@return integer
function TowerManager:getTowerCount()
    return #self.towers
end

---@return integer
function TowerManager:getFlameStoneCount()
    local n = 0
    for _ in pairs(self.flameStones) do
        n = n + 1
    end
    return n
end

---@param index integer
---@return DefenseTower|nil
function TowerManager:getTower(index)
    return self.towers[index]
end

---销毁所有灯光和火焰弹
function TowerManager:destroy()
    self:clearTowerLights()
    self.towers = {}
    self.flameStones = {}

    for _, p in ipairs(self.projectiles) do
        if p.node then
            p.node:Remove()
        end
    end
    self.projectiles = {}
end

return TowerManager
