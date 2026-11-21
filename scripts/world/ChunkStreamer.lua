-- ====================================================================
-- world/ChunkStreamer.lua
-- 区块流式加载管理器（无限地形）
--
-- 玩家移动时，持续判断哪些区块进入渲染范围：
--   - 进入范围：按需生成地形数据 + 构建网格
--   - 离开范围：卸载网格（数据保留，回程时重建网格）
--
-- 性能设计（避免卡顿）：
--   - 地形生成按「时间预算」推进（每帧最多 GEN_BUDGET_MS 毫秒）
--   - 网格构建不在这里同步做，而是把区块标记为脏，交给
--     ChunkMeshBuilder 的异步切片系统（每帧建一部分 Y 层）慢慢完成，
--     这样单帧不会因为一个高区块的完整构建而长时间阻塞
-- ====================================================================

local Config = require("config.GameConfig")

local CHUNK_SIZE = Config.World.CHUNK_SIZE
local BLOCK_SIZE = Config.World.BLOCK_SIZE

---@class ChunkStreamer
---@field world World
---@field generator WorldGenerator
---@field chunkBuilder ChunkMeshBuilder
---@field generated table<string, boolean>
---@field loaded table<string, boolean>
---@field pendingBuild table<string, boolean>
---@field genQueue { x: number, z: number }[]
---@field buildQueue { x: number, z: number }[]
---@field lastCX number|nil
---@field lastCZ number|nil
---@field onChunkLoaded function|nil 区块网格构建完成回调 function(cx, cz)
local ChunkStreamer = {}
ChunkStreamer.__index = ChunkStreamer

---创建流式加载器
---@param world World 世界实例
---@param generator WorldGenerator 世界生成器
---@param chunkBuilder ChunkMeshBuilder 区块网格构建器
---@return ChunkStreamer
function ChunkStreamer.new(world, generator, chunkBuilder)
    local self = setmetatable({}, ChunkStreamer)
    self.world = world
    self.generator = generator
    self.chunkBuilder = chunkBuilder
    self.generated = {}       -- [chunkKey] = true（数据已生成）
    self.loaded = {}          -- [chunkKey] = true（网格已构建）
    self.pendingBuild = {}    -- [chunkKey] = true（已排队等待异步构建）
    self.genQueue = {}        -- 待生成数据的区块 { x, z }
    self.buildQueue = {}      -- 待构建网格的区块 { x, z }
    self.lastCX = nil
    self.lastCZ = nil
    return self
end

---生成单个区块的数据（幂等）
---@param cx number 区块X
---@param cz number 区块Z
function ChunkStreamer:generateChunkData(cx, cz)
    local key = cx .. "," .. cz
    if self.generated[key] then
        return
    end
    self.generator:generateChunk(self.world, cx, cz)
    self.generated[key] = true
end

---把区块排进构建管线（标记为脏，由 ChunkMeshBuilder 异步切片构建）
---@param cx number 区块X
---@param cz number 区块Z
function ChunkStreamer:queueBuild(cx, cz)
    local key = cx .. "," .. cz
    if self.loaded[key] or self.pendingBuild[key] then
        return
    end
    self.pendingBuild[key] = true
    -- 与 World:markChunkDirty 使用同一份脏表，交给异步重建系统消费
    self.world.dirtyChunks[key] = { x = cx, z = cz }
end

---检查在途构建是否完成（区块节点出现即视为完成）
function ChunkStreamer:pollBuilds()
    for key in pairs(self.pendingBuild) do
        if self.world:getChunk(key) then
            self.pendingBuild[key] = nil
            self.loaded[key] = true
            if self.onChunkLoaded then
                local sx, sz = key:match("(-?%d+),(-?%d+)")
                local cx, cz = tonumber(sx), tonumber(sz)
                if cx and cz then
                    self.onChunkLoaded(cx, cz)
                end
            end
        end
    end
end

---卸载单个区块的网格（数据保留，回程时重建）
---@param cx number 区块X
---@param cz number 区块Z
function ChunkStreamer:unloadChunk(cx, cz)
    local key = cx .. "," .. cz
    if self.loaded[key] then
        self.world:removeChunk(key)
        self.loaded[key] = nil
    end
end

---根据玩家所在区块重新扫描队列
---@param pcx number 玩家区块X
---@param pcz number 玩家区块Z
function ChunkStreamer:rescan(pcx, pcz)
    local RD = Config.World.RENDER_DISTANCE
    self.genQueue = {}
    self.buildQueue = {}

    for cx = pcx - RD, pcx + RD do
        for cz = pcz - RD, pcz + RD do
            local key = cx .. "," .. cz
            if not self.generated[key] then
                self.genQueue[#self.genQueue + 1] = { x = cx, z = cz }
            elseif not self.loaded[key] then
                self.buildQueue[#self.buildQueue + 1] = { x = cx, z = cz }
            end
        end
    end
end

---卸载远离玩家的区块网格
---@param pcx number 玩家区块X
---@param pcz number 玩家区块Z
function ChunkStreamer:unloadFar(pcx, pcz)
    local RD = Config.World.RENDER_DISTANCE
    local limit = RD + Config.Streaming.UNLOAD_PADDING

    for key, _ in pairs(self.loaded) do
        local sx, sz = key:match("(-?%d+),(-?%d+)")
        local cx, cz = tonumber(sx), tonumber(sz)
        if cx and cz then
            if math.abs(cx - pcx) > limit or math.abs(cz - pcz) > limit then
                self:unloadChunk(cx, cz)
            end
        end
    end
end

---在途构建数量
---@return number
function ChunkStreamer:countPendingBuilds()
    local n = 0
    for _ in pairs(self.pendingBuild) do
        n = n + 1
    end
    return n
end

---维持构建管线：补足在途构建名额
function ChunkStreamer:topUpBuilds()
    local maxInflight = Config.Streaming.BUILD_MAX_INFLIGHT
    local inflight = self:countPendingBuilds()
    while inflight < maxInflight and #self.buildQueue > 0 do
        local c = table.remove(self.buildQueue, 1)
        self:queueBuild(c.x, c.z)
        inflight = self:countPendingBuilds()
    end
end

---初始加载：生成出生点周围区块数据 + 构建网格（协程，分帧）
---@param spawnX number 出生点世界X（方块坐标）
---@param spawnZ number 出生点世界Z（方块坐标）
---@param onProgress function|nil 进度回调 function(phase, current, total)
---@return thread 协程对象
function ChunkStreamer:loadInitial(spawnX, spawnZ, onProgress)
    return coroutine.create(function()
        local RD = math.min(Config.World.RENDER_DISTANCE, Config.Streaming.INITIAL_RADIUS)
        local pcx = math.floor(spawnX / CHUNK_SIZE)
        local pcz = math.floor(spawnZ / CHUNK_SIZE)

        -- 收集初始范围内的区块
        ---@type { x: number, z: number }[]
        local chunks = {}
        for cx = pcx - RD, pcx + RD do
            for cz = pcz - RD, pcz + RD do
                chunks[#chunks + 1] = { x = cx, z = cz }
            end
        end
        local total = #chunks
        local genPerFrame = Config.Streaming.INITIAL_CHUNKS_PER_FRAME

        -- 阶段 1：生成地形数据
        local done = 0
        for _, c in ipairs(chunks) do
            self:generateChunkData(c.x, c.z)
            done = done + 1
            if done % genPerFrame == 0 then
                if onProgress then onProgress("terrain", done, total) end
                coroutine.yield()
            end
        end
        if onProgress then onProgress("terrain", total, total) end
        coroutine.yield()

        -- 过渡：高度范围与天光已在地形阶段完成（进度条 50% → 70%，避免跳变）
        if onProgress then onProgress("heights", 1, 1) end
        coroutine.yield()

        -- 阶段 2：异步切片构建网格（每帧只建一部分 Y 层，不阻塞）
        -- 初始区块全部排进构建队列，由 topUpBuilds 按在途上限分批送进构建管线
        self.buildQueue = {}
        for _, c in ipairs(chunks) do
            self.buildQueue[#self.buildQueue + 1] = { x = c.x, z = c.z }
        end

        while true do
            -- 每帧按时间预算推进异步构建（每次调用只处理 16 层切片，很快返回）
            local buildDeadline = os.clock() + Config.Streaming.BUILD_BUDGET_MS / 1000
            while os.clock() < buildDeadline do
                self:pollBuilds()
                self:topUpBuilds()
                self.chunkBuilder:rebuildDirtyChunks()
                if self:countPendingBuilds() == 0 and #self.buildQueue == 0 then
                    break
                end
            end

            local built = 0
            for _, c in ipairs(chunks) do
                if self.loaded[c.x .. "," .. c.z] then
                    built = built + 1
                end
            end
            if onProgress then onProgress("chunks", built, total) end
            if built >= total then
                break
            end
            coroutine.yield()
        end

        self.lastCX = pcx
        self.lastCZ = pcz

        -- 初始只加载了近处；把剩余渲染范围内的区块排进队列，由 update() 逐帧补齐
        self:rescan(pcx, pcz)

        if onProgress then onProgress("complete", 1, 1) end
    end)
end

---每帧更新：按时间预算生成、按异步管线构建、卸载远处区块
---@param playerPos Vector3 玩家世界坐标
---@param _timeStep number 时间步长
function ChunkStreamer:update(playerPos, _timeStep)
    local pcx = math.floor(playerPos.x / (CHUNK_SIZE * BLOCK_SIZE))
    local pcz = math.floor(playerPos.z / (CHUNK_SIZE * BLOCK_SIZE))

    -- 玩家跨区块时重扫队列
    if pcx ~= self.lastCX or pcz ~= self.lastCZ then
        self.lastCX = pcx
        self.lastCZ = pcz
        self:rescan(pcx, pcz)
    end

    -- 1) 地形生成：按时间预算推进
    local genDeadline = os.clock() + Config.Streaming.GEN_BUDGET_MS / 1000
    while #self.genQueue > 0 and os.clock() < genDeadline do
        local c = table.remove(self.genQueue, 1)
        self:generateChunkData(c.x, c.z)
    end

    -- 2) 网格构建：检查在途完成情况，并补足在途名额（真正构建由异步系统推进）
    self:pollBuilds()
    self:topUpBuilds()

    -- 3) 卸载远处网格
    self:unloadFar(pcx, pcz)
end

return ChunkStreamer
