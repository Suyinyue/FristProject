-- ====================================================================
-- entity/MobManager.lua
-- 生物生成与管理系统（按 Design.md「生成机制」实现）
--
-- 生成流程（周期性任务）：
--   1. 以玩家为中心，在已加载区块中筛选距离合适的候选区块
--   2. 随机选一个区块，区块内随机取一个生成中心
--   3. 依据生物群系 / 地面类型 / 光照（昼夜）/ 周边空间筛选可生成的生物
--   4. 按各生物的生成权重加权随机抽选种类
--   5. 随机群体数量，在中心附近找多个合法位置成群生成
--   6. 每个位置独立校验（地面、空间、液体、玩家保护距离、群系、光照）
--   7. 分类数量上限（monster / animal）达标时暂停该类生成
--   8. 距玩家过远的生物自然消失
-- 新加载的区块还会额外尝试一次「环境原生动物」生成。
-- ====================================================================

local Config = require("config.GameConfig")
local Blocks = require("data.BlockRegistry")
local BiomeGenerator = require("terrain.BiomeGenerator")
local Mob = require("entity.Mob")

local CHUNK_SIZE = Config.World.CHUNK_SIZE
local BLOCK_SIZE = Config.World.BLOCK_SIZE

-- 可生成的生物类型
local MOB_TYPES = { "ZOMBIE", "GHOST", "BOMBER", "ARCHER", "COW", "SHEEP", "PIG", "CHICKEN" }

-- 群系编号 → 配置里的名称
local BIOME_KEYS = {
    [BiomeGenerator.PLAINS] = "plains",
    [BiomeGenerator.FOREST] = "forest",
    [BiomeGenerator.DESERT] = "desert",
    [BiomeGenerator.MOUNTAINS] = "mountains",
}

-- 地面方块 → 配置里的地面类型
local GROUND_GRASS = { [Blocks.GRASS] = true, [Blocks.SNOWY_GRASS] = true }
local GROUND_SAND = { [Blocks.SAND] = true, [Blocks.SANDSTONE] = true }
local GROUND_DIRT = { [Blocks.DIRT] = true }
local GROUND_STONE = { [Blocks.STONE] = true, [Blocks.COBBLESTONE] = true, [Blocks.STONE_BRICKS] = true }
local GROUND_SNOW = { [Blocks.SNOW_BLOCK] = true }

---@param blockType number
---@return string
local function groundKind(blockType)
    if GROUND_GRASS[blockType] then return "grass" end
    if GROUND_SAND[blockType] then return "sand" end
    if GROUND_DIRT[blockType] then return "dirt" end
    if GROUND_STONE[blockType] then return "stone" end
    if GROUND_SNOW[blockType] then return "snow" end
    return "other"
end

---@class MobManager
---@field scene Scene
---@field world World
---@field biome BiomeGenerator|table
---@field mobs Mob[]
---@field spawnTimer number
---@field lastNight boolean|nil
---@field onChunkLoaded function|nil
---@field onMobDeath fun(mob: Mob)|nil
local MobManager = {}
MobManager.__index = MobManager

---创建生物管理器
---@param scene Scene 场景
---@param world World 世界实例
---@param biome BiomeGenerator|nil 生物群系生成器（默认自建）
---@return MobManager
function MobManager.new(scene, world, biome)
    local self = setmetatable({}, MobManager)
    self.scene = scene
    self.world = world
    self.biome = biome or BiomeGenerator.new()
    self.mobs = {}
    self.spawnTimer = Config.MobSpawning.SPAWN_INTERVAL
    self.lastNight = nil
    return self
end

-- ====================================================================
-- 数量统计
-- ====================================================================

---按分类统计现存数量
---@return table<string, number>
function MobManager:countByCategory()
    local counts = { monster = 0, animal = 0 }
    for _, mob in ipairs(self.mobs) do
        local cat = mob.def.category
        if cat then
            counts[cat] = (counts[cat] or 0) + 1
        end
    end
    return counts
end

---该分类是否已达上限
---@param category string
---@param counts table<string, number>
---@return boolean
function MobManager:isCategoryFull(category, counts)
    local cap = Config.MobSpawning.CATEGORY_CAPS[category]
    if not cap then
        return false
    end
    return (counts[category] or 0) >= cap
end

-- ====================================================================
-- 环境查询与合法性校验
-- ====================================================================

---判断某地面/群系/光照是否允许该类型生成
---@param def table 生物定义
---@param bx number
---@param bz number
---@param gh number 地面高度（第一个空气格）
---@param isNight boolean
---@return boolean
function MobManager:isEnvironmentAllowed(def, bx, bz, gh, isNight)
    -- 昼夜要求
    if def.spawnTime == "night" and not isNight then
        return false
    end

    -- 生物群系要求
    if def.biomes then
        local biomeId = self.biome:getBiome(bx, bz)
        local key = BIOME_KEYS[biomeId]
        local ok = false
        for _, allowed in ipairs(def.biomes) do
            if allowed == key then
                ok = true
                break
            end
        end
        if not ok then
            return false
        end
    end

    -- 地面类型要求
    local groundBlock = self.world:getBlock(bx, gh - 1, bz)
    local kind = groundKind(groundBlock)
    if def.ground then
        local ok = false
        for _, allowed in ipairs(def.ground) do
            if allowed == "any" or allowed == kind then
                ok = true
                break
            end
        end
        if not ok then
            return false
        end
    end

    -- 光照要求：
    --   陆地动物需要露天（天光充足）
    --   敌对怪物需要处在暗处（夜晚或洞穴/背光处）
    local skyLight = self.world:getSkyLight(bx, gh, bz)
    if def.category == "animal" and skyLight < 12 then
        return false
    end
    if def.category == "monster" and def.spawnTime == "night" and skyLight >= 12 and not isNight then
        return false
    end

    return true
end

---校验某个具体位置能否生成该生物（空间、液体、玩家保护距离）
---@param def table
---@param bx number
---@param bz number
---@param playerPos Vector3|nil 玩家位置；传 nil 跳过玩家保护距离检查（新区块原生生成）
---@return number|nil spawnY 方块 Y（成功时）
function MobManager:validatePosition(def, bx, bz, playerPos)
    local gh = self.world:getGroundHeight(bx, bz)
    if gh <= Config.World.WATER_LEVEL + 1 then
        return nil   -- 水下 / 太低
    end

    if gh >= Config.World.WORLD_HEIGHT - 2 then
        return nil   -- 顶到世界高度
    end

    -- 地面必须可站立
    local groundBlock = self.world:getBlock(bx, gh - 1, bz)
    if not Blocks:isSolid(groundBlock) then
        return nil
    end
    if groundBlock == Blocks.WATER or groundBlock == Blocks.LAVA then
        return nil
    end

    -- 空间足够（按生物高度检查 1~3 格空气）
    local needHeight = 1
    if def.size and def.size[2] and def.size[2] > 1.3 then
        needHeight = 3
    elseif def.size and def.size[2] and def.size[2] > 0.8 then
        needHeight = 2
    end
    for dy = 0, needHeight - 1 do
        local b = self.world:getBlock(bx, gh + dy, bz)
        if b ~= Blocks.AIR then
            return nil   -- 有障碍 / 是液体
        end
    end

    -- 玩家保护距离（方块）
    if playerPos then
        local wx = bx * BLOCK_SIZE
        local wz = bz * BLOCK_SIZE
        local dx = wx - playerPos.x
        local dz = wz - playerPos.z
        local minDist = Config.MobSpawning.MIN_DISTANCE * BLOCK_SIZE
        if dx * dx + dz * dz < minDist * minDist then
            return nil
        end
    end

    return gh
end

---实际创建一只生物
---@param mobType string
---@param bx number
---@param gh number
---@param bz number
---@return Mob
function MobManager:spawnMobAt(mobType, bx, gh, bz)
    local pos = Vector3(bx * BLOCK_SIZE, gh * BLOCK_SIZE, bz * BLOCK_SIZE)
    local mob = Mob.new(self.scene, self.world, mobType, pos)
    self.mobs[#self.mobs + 1] = mob
    return mob
end

-- ====================================================================
-- 生成任务
-- ====================================================================

---收集候选区块（已加载、距离在 [MIN_CHUNK_DIST, MAX_CHUNK_DIST] 内）
---@param pcx number 玩家区块X
---@param pcz number 玩家区块Z
---@return { x: number, z: number }[]
function MobManager:collectCandidateChunks(pcx, pcz)
    local cfg = Config.MobSpawning
    local list = {}
    for cx = pcx - cfg.MAX_CHUNK_DIST, pcx + cfg.MAX_CHUNK_DIST do
        for cz = pcz - cfg.MAX_CHUNK_DIST, pcz + cfg.MAX_CHUNK_DIST do
            local d = math.max(math.abs(cx - pcx), math.abs(cz - pcz))
            if d >= cfg.MIN_CHUNK_DIST and d <= cfg.MAX_CHUNK_DIST then
                if self.world:getChunk(cx .. "," .. cz) then
                    list[#list + 1] = { x = cx, z = cz }
                end
            end
        end
    end
    return list
end

---按权重随机抽选一个生物类型
---@param candidates string[]
---@return string|nil
function MobManager:pickWeighted(candidates)
    local total = 0
    for _, t in ipairs(candidates) do
        total = total + (Config.Mobs[t].weight or 1)
    end
    if total <= 0 then
        return nil
    end
    local roll = math.random() * total
    local acc = 0
    for _, t in ipairs(candidates) do
        acc = acc + (Config.Mobs[t].weight or 1)
        if roll <= acc then
            return t
        end
    end
    return candidates[#candidates]
end

---执行一次生成任务（随机区块 → 随机中心 → 环境筛选 → 加权抽选 → 成群生成）
---@param player Player
---@param isNight boolean
---@param neutralOnly boolean|nil 只生成中立动物（开局用）
---@return number 生成数量
function MobManager:runSpawnTask(player, isNight, neutralOnly)
    local cfg = Config.MobSpawning
    if #self.mobs >= cfg.MAX_MOBS then
        return 0
    end

    local playerPos = player:getPosition()
    local pcx = math.floor(playerPos.x / (CHUNK_SIZE * BLOCK_SIZE))
    local pcz = math.floor(playerPos.z / (CHUNK_SIZE * BLOCK_SIZE))

    local chunks = self:collectCandidateChunks(pcx, pcz)
    if #chunks == 0 then
        return 0
    end

    local counts = self:countByCategory()

    -- 1) 随机区块 + 随机中心
    local chunk = chunks[math.random(#chunks)]
    local baseX = chunk.x * CHUNK_SIZE
    local baseZ = chunk.z * CHUNK_SIZE
    local centerX = baseX + math.random(0, CHUNK_SIZE - 1)
    local centerZ = baseZ + math.random(0, CHUNK_SIZE - 1)

    -- 2) 以中心位置的环境筛出可生成类型
    local gh = self.world:getGroundHeight(centerX, centerZ)
    ---@type string[]
    local candidates = {}
    for _, t in ipairs(MOB_TYPES) do
        local def = Config.Mobs[t]
        local cat = def.category
        if not (neutralOnly and cat == "monster") then
            if not self:isCategoryFull(cat, counts) then
                if self:isEnvironmentAllowed(def, centerX, centerZ, gh, isNight) then
                    candidates[#candidates + 1] = t
                end
            end
        end
    end
    if #candidates == 0 then
        return 0
    end

    -- 3) 按权重抽选种类，随机群体数量
    local chosen = self:pickWeighted(candidates)
    if not chosen then
        return 0
    end
    local def = Config.Mobs[chosen]
    local groupMin = def.group and def.group[1] or 1
    local groupMax = def.group and def.group[2] or 1
    local groupSize = math.random(groupMin, groupMax)

    -- 4) 在中心附近找合法位置，成群生成
    local spawned = 0
    local radius = math.floor(cfg.GROUP_RADIUS)
    local cap = cfg.CATEGORY_CAPS[def.category] or cfg.MAX_MOBS

    for _ = 1, groupSize do
        if #self.mobs >= cfg.MAX_MOBS then
            break
        end
        if (self:countByCategory()[def.category] or 0) >= cap then
            break
        end

        for _ = 1, cfg.GROUP_ATTEMPTS do
            local ox = centerX + math.random(-radius, radius)
            local oz = centerZ + math.random(-radius, radius)
            local y = self:validatePosition(def, ox, oz, playerPos)
            -- 每个位置独立校验：地形/空间/保护距离 + 群系/光照
            if y and self:isEnvironmentAllowed(def, ox, oz, y, isNight) then
                self:spawnMobAt(chosen, ox, y, oz)
                spawned = spawned + 1
                break
            end
        end
    end

    if spawned > 0 then
        print(string.format("[Mobs] spawn task: %s x%d at chunk(%d,%d) night=%s total=%d",
            chosen, spawned, chunk.x, chunk.z, tostring(isNight), #self.mobs))
    end
    return spawned
end

-- ====================================================================
-- 初期生成（开局 / 新加载区块）
-- ====================================================================

---新加载区块的原生动物生成（让探索新区域能看到环境里原本就有的动物）
---@param cx number 区块X
---@param cz number 区块Z
---@param isNight boolean
---@param playerPos Vector3|nil 玩家位置（用于跳过太远、注定会被自然消失的区块）
function MobManager:initialSpawnInChunk(cx, cz, isNight, playerPos)
    local cfg = Config.MobSpawning
    if #self.mobs >= cfg.MAX_MOBS then
        return
    end
    if math.random() > 0.35 then
        return   -- 不是每个区块都有动物
    end

    -- 太远的区块即使生成了也会立刻被自然消失，直接跳过
    if playerPos then
        local cwx = (cx * CHUNK_SIZE + CHUNK_SIZE * 0.5) * BLOCK_SIZE
        local cwz = (cz * CHUNK_SIZE + CHUNK_SIZE * 0.5) * BLOCK_SIZE
        local ddx = cwx - playerPos.x
        local ddz = cwz - playerPos.z
        if ddx * ddx + ddz * ddz > 70.0 * 70.0 then
            return
        end
    end

    local counts = self:countByCategory()
    if self:isCategoryFull("animal", counts) then
        return
    end

    local baseX = cx * CHUNK_SIZE
    local baseZ = cz * CHUNK_SIZE

    for _ = 1, 6 do
        local bx = baseX + math.random(0, CHUNK_SIZE - 1)
        local bz = baseZ + math.random(0, CHUNK_SIZE - 1)
        local gh = self.world:getGroundHeight(bx, bz)

        ---@type string[]
        local candidates = {}
        for _, t in ipairs(MOB_TYPES) do
            local def = Config.Mobs[t]
            if def.category == "animal" and self:isEnvironmentAllowed(def, bx, bz, gh, isNight) then
                candidates[#candidates + 1] = t
            end
        end
        if #candidates > 0 then
            local chosen = self:pickWeighted(candidates)
            -- 新区块原生生成：不做玩家保护距离检查（玩家此时不在这里）
            if chosen then
                local def = Config.Mobs[chosen]
                local y = self:validatePosition(def, bx, bz, nil)
                if y then
                    self:spawnMobAt(chosen, bx, y, bz)
                    print(string.format("[Mobs] new chunk native: %s at (%d,%d)", chosen, bx, bz))
                    return
                end
            end
        end
    end
end

---开局生成（玩家附近，只生成中立动物）
---@param player Player
---@param isNight boolean
---@param count number
function MobManager:spawnInitial(player, isNight, count)
    local spawned = 0
    for _ = 1, count do
        spawned = spawned + self:runSpawnTask(player, isNight, true)
    end
    print(string.format("[Mobs] initial spawn: %d", spawned))
    return spawned
end

-- ====================================================================
-- 查询与更新
-- ====================================================================

---查找玩家准星瞄准的生物（锥形瞄准）
---@param player Player 玩家实例
---@return Mob|nil
function MobManager:findTargetMob(player)
    local eye = player:getEyePosition()
    local look = player:getLookDirection()
    local reach = Config.Player.ATTACK_RANGE

    local bestMob = nil
    local bestScore = -1.0

    for _, mob in ipairs(self.mobs) do
        if not mob:isDead() then
            local toMob = mob:getPosition() - eye
            local dist = toMob:Length()
            if dist <= reach and dist > 0.0001 then
                local dir = toMob:Normalized()
                local dot = dir.x * look.x + dir.y * look.y + dir.z * look.z
                if dot > 0.5 then
                    local score = dot / dist
                    if score > bestScore then
                        bestScore = score
                        bestMob = mob
                    end
                end
            end
        end
    end

    return bestMob
end

---每帧更新：生物 AI、自然消失、周期性生成
---@param dt number 时间步长
---@param player Player
---@param isNight boolean
function MobManager:update(dt, player, isNight)
    local cfg = Config.MobSpawning
    local playerPos = player:getPosition()

    -- 更新所有生物 + 清理死亡/过远
    for i = #self.mobs, 1, -1 do
        local mob = self.mobs[i]
        mob:update(dt, player)

        local mp = mob:getPosition()
        local dx = mp.x - playerPos.x
        local dz = mp.z - playerPos.z
        local far = (dx * dx + dz * dz) > (cfg.DESPAWN_DISTANCE * cfg.DESPAWN_DISTANCE)

        if mob:isDead() then
            -- 生物死亡掉落（Design.md：生物死亡产生物品）
            if self.onMobDeath then
                self.onMobDeath(mob)
            end
            mob:destroy()
            table.remove(self.mobs, i)
        elseif far then
            print(string.format("[Mobs] %s despawned (far)", mob.mobType))
            mob:destroy()
            table.remove(self.mobs, i)
        end
    end

    -- 入夜补一波敌对生物
    if self.lastNight ~= nil and self.lastNight ~= isNight and isNight then
        self:runSpawnTask(player, isNight)
        self:runSpawnTask(player, isNight)
        print("[Mobs] night falls: hostile spawn wave")
    end
    self.lastNight = isNight

    -- 周期性生成任务
    self.spawnTimer = self.spawnTimer - dt
    if self.spawnTimer <= 0 then
        self.spawnTimer = cfg.SPAWN_INTERVAL
        self:runSpawnTask(player, isNight)
    end
end

---获取当前生物数量
---@return number
function MobManager:getMobCount()
    return #self.mobs
end

---销毁所有生物
function MobManager:destroy()
    for _, mob in ipairs(self.mobs) do
        mob:destroy()
    end
    self.mobs = {}
end

return MobManager
