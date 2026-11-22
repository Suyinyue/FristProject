-- ====================================================================
-- save/SaveManager.lua
-- 世界存档：元数据 / 玩家 / 全部已生成区块 / 生物 / 掉落物 / 时间 / 天气
--
-- 存档目录（引擎项目+用户隔离）：saves/<World_xxx>/
--   world.json        世界元数据（名称/Seed/版本/时间/天气）
--   player.json       玩家位置、朝向、生命、饥饿、饱和度、经验、背包
--   entities.json     生物 + 地面掉落物
--   chunks/*.json     每个已生成区块的方块 RLE + blockState
--
-- 加载时先恢复区块数据并标记为已生成，ChunkStreamer 不会重新生成这些区块，
-- 因此被挖掉的矿石不会复活；未保存过的区块继续用原 Seed 生成。
-- ====================================================================

local Config = require("config.GameConfig")
local Blocks = require("data.BlockRegistry")

local SaveManager = {}

local SAVE_ROOT = "saves"
local WORLD_VERSION = 1
local GAME_VERSION = "1.0.0"
local CHUNK_VOLUME = 16 * 80 * 16

---@type string|nil
local currentSlot_ = nil
---@type integer|nil
local currentCreatedAt_ = nil

-- ====================================================================
-- 文件辅助
-- ====================================================================

---@param path string
---@param data table
---@return boolean ok, string|nil err
local function writeJsonAtomic(path, data)
    local ok, encoded = pcall(cjson.encode, data)
    if not ok then
        return false, "encode: " .. tostring(encoded)
    end
    local tmp = path .. ".tmp"
    local file = File(tmp, FILE_WRITE)
    if not file or not file:IsOpen() then
        return false, "open: " .. path
    end
    file:WriteString(encoded)
    file:Close()

    if fileSystem:FileExists(path) then
        fileSystem:Copy(path, path .. ".bak")
        fileSystem:Delete(path)
    end
    if not fileSystem:Rename(tmp, path, true) then
        fileSystem:Copy(tmp, path)
        fileSystem:Delete(tmp)
    end
    return true
end

---@param path string
---@return table|nil
local function readJson(path)
    if not fileSystem:FileExists(path) then
        return nil
    end
    local file = File(path, FILE_READ)
    if not file or not file:IsOpen() then
        return nil
    end
    local text = file:ReadString()
    file:Close()
    local ok, decoded = pcall(cjson.decode, text)
    if ok and type(decoded) == "table" then
        return decoded
    end
    return nil
end

---@param slot string
---@return string
local function slotRoot(slot)
    return SAVE_ROOT .. "/" .. slot
end

---@param slot string
local function ensureDirs(slot)
    fileSystem:CreateDir(SAVE_ROOT, true)
    fileSystem:CreateDir(slotRoot(slot), true)
    fileSystem:CreateDir(slotRoot(slot) .. "/chunks", true)
end

---@param key integer
---@return integer cx, integer cz
local function decodeChunkKey(key)
    local shifted = key + 32768
    local cx = math.floor(shifted / 65536)
    local cz = (shifted % 65536) - 32768
    return cx, cz
end

-- ====================================================================
-- 区块序列化
-- ====================================================================

---@param blockId integer
---@return integer
local function safeBlock(blockId)
    return blockId or 0
end

---@param blocks table
---@return table runs
local function encodeBlocksRLE(blocks)
    local runs = {}
    local last = safeBlock(blocks[0])
    local count = 1
    for i = 1, CHUNK_VOLUME - 1 do
        local v = safeBlock(blocks[i])
        if v == last then
            count = count + 1
        else
            runs[#runs + 1] = last
            runs[#runs + 1] = count
            last = v
            count = 1
        end
    end
    runs[#runs + 1] = last
    runs[#runs + 1] = count
    return runs
end

---@param runs table
---@param chunkData table
local function decodeBlocksRLE(runs, chunkData)
    local blocks = {}
    local idx = 0
    for i = 1, #runs, 2 do
        local value = runs[i]
        local count = runs[i + 1] or 0
        for _ = 1, count do
            if value ~= 0 then
                blocks[idx] = value
            end
            idx = idx + 1
        end
    end
    chunkData.blocks = blocks
end

---@param chunkData table
---@return table states
local function encodeBlockStates(chunkData)
    local out = {}
    local states = chunkData.blockState
    if states then
        for idx, value in pairs(states) do
            out[#out + 1] = idx
            out[#out + 1] = value
        end
    end
    return out
end

---@param flat table
---@param chunkData table
local function decodeBlockStates(flat, chunkData)
    local states = nil
    for i = 1, #flat, 2 do
        local idx = flat[i]
        local value = flat[i + 1]
        if idx and value then
            states = states or {}
            states[idx] = value
        end
    end
    chunkData.blockState = states
end

-- ====================================================================
-- 对外：槽位管理
-- ====================================================================

---@return string|nil
function SaveManager.getCurrentSlot()
    return currentSlot_
end

---@param slot string|nil
function SaveManager.setCurrentSlot(slot)
    currentSlot_ = slot
end

---生成一个新的槽位 ID
---@return string slot, string displayName
function SaveManager.newSlot()
    local stamp = os.date("%Y%m%d_%H%M%S")
    return "World_" .. stamp, "世界 " .. os.date("%Y-%m-%d %H:%M:%S")
end

---列出所有存档（按最后保存时间倒序）
---@return table[]
function SaveManager.listWorlds()
    local list = {}
    if not fileSystem:DirExists(SAVE_ROOT) then
        return list
    end
    local dirs = fileSystem:ScanDir(SAVE_ROOT, "*", SCAN_DIRS, false)
    for _, name in ipairs(dirs) do
        local meta = readJson(SAVE_ROOT .. "/" .. name .. "/world.json")
        if meta then
            meta.slot = name
            list[#list + 1] = meta
        end
    end
    table.sort(list, function(a, b)
        return (a.saved_at or 0) > (b.saved_at or 0)
    end)
    return list
end

-- ====================================================================
-- 保存
-- ====================================================================

---@param mob Mob
---@return table
local function serializeMob(mob)
    local p = mob:getPosition()
    return {
        type = mob.mobType,
        x = p.x, y = p.y, z = p.z,
        health = mob.health,
        baby = mob.baby or false,
        love_mode = mob.loveMode or false,
        love_timer = mob.loveTimer or 0,
        breed_cooldown = mob.breedCooldown or 0,
        grow_timer = mob.growTimer or 0,
    }
end

---保存当前世界
---@param ctx table
---@param slot string|nil
---@param name string|nil
---@return boolean ok, string message
function SaveManager.saveWorld(ctx, slot, name)
    if not ctx or not ctx.world or not ctx.player then
        return false, "当前世界不可保存"
    end

    local isNew = false
    if not slot or slot == "" then
        slot = currentSlot_
        if not slot then
            slot, name = SaveManager.newSlot()
            isNew = true
        end
    end
    name = name or slot

    ensureDirs(slot)

    local oldMeta = readJson(slotRoot(slot) .. "/world.json")
    local createdAt = oldMeta and oldMeta.created_at or os.time()
    currentCreatedAt_ = createdAt

    -- 1) 区块
    local chunkCount = 0
    for numericKey, chunkData in pairs(ctx.world.chunkData) do
        if chunkData and chunkData.blocks then
            local cx, cz = decodeChunkKey(numericKey)
            local payload = {
                cx = cx,
                cz = cz,
                blocks = encodeBlocksRLE(chunkData.blocks),
                states = encodeBlockStates(chunkData),
            }
            local path = string.format("%s/chunks/%d_%d.json", slotRoot(slot), cx, cz)
            local ok, err = writeJsonAtomic(path, payload)
            if not ok then
                return false, "区块保存失败: " .. tostring(err)
            end
            chunkCount = chunkCount + 1
        end
    end

    -- 2) 玩家
    local player = ctx.player
    local inventory = player:getInventory()
    local p = player:getPosition()
    local playerData = {
        x = p.x, y = p.y, z = p.z,
        yaw = player.yaw,
        pitch = player.pitch,
        health = player:getHealth(),
        hunger = player:getHunger(),
        saturation = player:getSaturation(),
        level = player:getLevel(),
        xp = player:getXp(),
        xpTotal = player:getXpTotal(),
        hotbar = player:getSelectedSlotIndex(),
        inventory = inventory and inventory:toData() or nil,
    }
    local ok, err = writeJsonAtomic(slotRoot(slot) .. "/player.json", playerData)
    if not ok then
        return false, "玩家保存失败: " .. tostring(err)
    end

    -- 3) 生物 + 掉落物
    local mobs = {}
    if ctx.mobManager then
        for _, mob in ipairs(ctx.mobManager.mobs) do
            if not mob:isDead() then
                mobs[#mobs + 1] = serializeMob(mob)
            end
        end
    end
    local entities = {
        mobs = mobs,
        drops = ctx.itemDropSystem and ctx.itemDropSystem:serialize() or {},
    }
    ok, err = writeJsonAtomic(slotRoot(slot) .. "/entities.json", entities)
    if not ok then
        return false, "实体保存失败: " .. tostring(err)
    end

    -- 4) 元数据（最后写，作为提交点）
    local cycle = ctx.dayNightCycle
    local weather = ctx.weatherManager
    local meta = {
        version = WORLD_VERSION,
        game_version = GAME_VERSION,
        name = (oldMeta and oldMeta.name) or name,
        seed = Config.Noise.SEED,
        created_at = createdAt,
        saved_at = os.time(),
        time = cycle and cycle:getTime() or 6.2,
        weather = {
            state = weather and weather:getState() or "clear",
            timer = weather and weather.timer or 120,
            darkness = weather and weather.darkness or 0,
        },
        chunk_count = chunkCount,
        player_x = p.x,
        player_z = p.z,
    }
    ok, err = writeJsonAtomic(slotRoot(slot) .. "/world.json", meta)
    if not ok then
        return false, "元数据保存失败: " .. tostring(err)
    end

    currentSlot_ = slot
    if isNew then
        print("[Save] 新建存档: " .. slot)
    end
    return true, "已保存：" .. meta.name .. (isNew and "（新存档）" or "")
end

-- ====================================================================
-- 加载
-- ====================================================================

---@param ctx table
local function clearCurrentWorld(ctx)
    local world = ctx.world
    for _, node in pairs(world.chunks) do
        node:Remove()
    end
    world.chunks = {}
    world.chunkData = {}
    world.dirtyChunks = {}

    local streamer = ctx.chunkStreamer
    if streamer then
        streamer.generated = {}
        streamer.loaded = {}
        streamer.pendingBuild = {}
        streamer.genQueue = {}
        streamer.buildQueue = {}
        streamer.lastCX = nil
        streamer.lastCZ = nil
    end

    if ctx.mobManager then ctx.mobManager:destroy() end
    if ctx.itemDropSystem then ctx.itemDropSystem:destroy() end
    if ctx.towerManager then ctx.towerManager:destroy() end
    if ctx.torchDecorator then ctx.torchDecorator:destroy() end
    if ctx.miningSystem then ctx.miningSystem:stopMining() end
end

---@param ctx table
---@param chunksDir string
---@return integer count
local function restoreChunks(ctx, chunksDir)
    local world = ctx.world
    local streamer = ctx.chunkStreamer
    local names = fileSystem:ScanDir(chunksDir, "*.json", SCAN_FILES, false)
    local count = 0

    for _, fileName in ipairs(names) do
        local payload = readJson(chunksDir .. "/" .. fileName)
        if payload and payload.cx and payload.cz and payload.blocks then
            local cx, cz = payload.cx, payload.cz
            local numericKey = cx * 65536 + cz
            local chunkData = world:ensureChunkData(numericKey)
            decodeBlocksRLE(payload.blocks, chunkData)
            decodeBlockStates(payload.states or {}, chunkData)
            chunkData.minY, chunkData.maxY = world:computeHeightRange(chunkData)
            world:propagateSkyLightChunk(chunkData)
            if streamer then
                streamer.generated[cx .. "," .. cz] = true
            end
            count = count + 1
        end
    end

    -- 方块光：扫描所有光源方块重新注入
    for numericKey, chunkData in pairs(world.chunkData) do
        local cx, cz = decodeChunkKey(numericKey)
        local baseX, baseZ = cx * 16, cz * 16
        for idx, blockId in pairs(chunkData.blocks) do
            local block = Blocks:get(blockId)
            if block and block.hasLight then
                local localX = idx % 16
                local rest = math.floor(idx / 16)
                local localZ = rest % 16
                local y = math.floor(rest / 16)
                world:addBlockLight(baseX + localX, y, baseZ + localZ,
                    block.lightRadius or 8)
            end
        end
    end

    -- 重建火把独立节点
    if ctx.torchDecorator then
        for numericKey, chunkData in pairs(world.chunkData) do
            local cx, cz = decodeChunkKey(numericKey)
            local baseX, baseZ = cx * 16, cz * 16
            for idx, blockId in pairs(chunkData.blocks) do
                if blockId == Blocks.TORCH then
                    local localX = idx % 16
                    local rest = math.floor(idx / 16)
                    local localZ = rest % 16
                    local y = math.floor(rest / 16)
                    ctx.torchDecorator:addTorch(baseX + localX, y, baseZ + localZ)
                end
            end
        end
    end

    -- 重新登记防御塔火焰石
    if ctx.towerManager then
        for numericKey, chunkData in pairs(world.chunkData) do
            local cx, cz = decodeChunkKey(numericKey)
            local baseX, baseZ = cx * 16, cz * 16
            for idx, blockId in pairs(chunkData.blocks) do
                if blockId == Blocks.FLAME_STONE then
                    local localX = idx % 16
                    local rest = math.floor(idx / 16)
                    local localZ = rest % 16
                    local y = math.floor(rest / 16)
                    ctx.towerManager:trackFlameStone(baseX + localX, y, baseZ + localZ)
                end
            end
        end
        ctx.towerManager:rebuildTowers()
    end

    -- 清掉恢复期间产生的脏标记，交给流式系统按玩家位置排队构建
    world.dirtyChunks = {}
    if streamer then
        streamer.lastCX = nil
        streamer.lastCZ = nil
    end
    return count
end

---加载世界
---@param ctx table
---@param slot string
---@return boolean ok, string message
function SaveManager.loadWorld(ctx, slot)
    if not ctx or not ctx.world or not ctx.player then
        return false, "当前环境不可加载"
    end
    local root = slotRoot(slot)
    local meta = readJson(root .. "/world.json")
    local playerData = readJson(root .. "/player.json")
    if not meta or not playerData then
        return false, "存档不完整或已损坏"
    end

    clearCurrentWorld(ctx)
    local chunkCount = restoreChunks(ctx, root .. "/chunks")

    -- 玩家
    local player = ctx.player
    player:setPosition(Vector3(playerData.x or 0, playerData.y or 0, playerData.z or 0))
    player.yaw = playerData.yaw or 0
    player.pitch = playerData.pitch or 0
    player:updateCamera()
    player.health = playerData.health or player.health
    player:setHunger(playerData.hunger or player:getMaxHunger())
    player:setSaturation(playerData.saturation or 0)
    player:setXp(playerData.level or 1, playerData.xp or 0, playerData.xpTotal or 0)
    local inventory = player:getInventory()
    if inventory and type(playerData.inventory) == "table" then
        inventory:fromData(playerData.inventory)
        inventory:markDirty()
    end
    if type(playerData.hotbar) == "number" then
        player:selectSlot(playerData.hotbar)
        if ctx.uiManager and ctx.uiManager.hotbar then
            ctx.uiManager.hotbar.selectedIndex = playerData.hotbar
            ctx.uiManager.hotbar:update()
        end
    end

    -- 生物 + 掉落物
    local entities = readJson(root .. "/entities.json") or {}
    if ctx.mobManager and type(entities.mobs) == "table" then
        for _, m in ipairs(entities.mobs) do
            local bx = math.floor((m.x or 0) / Config.World.BLOCK_SIZE)
            local bz = math.floor((m.z or 0) / Config.World.BLOCK_SIZE)
            local gh = math.floor((m.y or 0) / Config.World.BLOCK_SIZE)
            local mob = ctx.mobManager:spawnMobAt(m.type, bx, gh, bz)
            if mob then
                mob.node.position = Vector3(m.x or 0, m.y or 0, m.z or 0)
                mob.health = m.health or mob.maxHealth
                mob.healthBar:setHealth(mob.health, mob.maxHealth)
                if m.baby then mob:setBaby(true) end
                mob.loveMode = m.love_mode or false
                mob.loveTimer = m.love_timer or 0
                mob.breedCooldown = m.breed_cooldown or 0
                mob.growTimer = m.grow_timer or 0
            end
        end
    end
    if ctx.itemDropSystem and type(entities.drops) == "table" then
        ctx.itemDropSystem:restore(entities.drops)
    end

    -- 时间 / 天气
    if ctx.dayNightCycle and meta.time then
        ctx.dayNightCycle:setTime(meta.time)
    end
    if ctx.weatherManager and meta.weather then
        ctx.weatherManager:setState(meta.weather.state or "clear", meta.weather.timer or 120)
        ctx.weatherManager.darkness = meta.weather.darkness or 0
    end

    currentSlot_ = slot
    currentCreatedAt_ = meta.created_at
    print(string.format("[Save] 已加载 %s（%d 个区块）", slot, chunkCount))
    return true, string.format("已加载：%s（%d 个区块）", meta.name or slot, chunkCount)
end

-- ====================================================================
-- 删除
-- ====================================================================

---删除存档
---@param slot string
---@return boolean ok, string message
function SaveManager.deleteWorld(slot)
    local root = slotRoot(slot)
    if not fileSystem:DirExists(root) then
        return false, "存档不存在"
    end

    local chunkDir = root .. "/chunks"
    if fileSystem:DirExists(chunkDir) then
        local names = fileSystem:ScanDir(chunkDir, "*.json", SCAN_FILES, false)
        for _, name in ipairs(names) do
            fileSystem:Delete(chunkDir .. "/" .. name)
        end
    end
    for _, name in ipairs({ "world.json", "world.json.bak", "player.json", "player.json.bak",
        "entities.json", "entities.json.bak" }) do
        fileSystem:Delete(root .. "/" .. name)
    end
    fileSystem:Delete(chunkDir)
    fileSystem:Delete(root)

    if currentSlot_ == slot then
        currentSlot_ = nil
    end
    return true, "存档已删除"
end

return SaveManager
