-- ====================================================================
-- network/Standalone.lua
-- 单机模式入口（无网络，本地运行）
-- ====================================================================
--
-- ⚠️ AI 注意：这是【单机模式专用】文件！
--
-- 共享的游戏子系统（UI、特效、输入等）已提取到 core/GameSystems.lua
-- 本文件只包含单机模式专用逻辑（本地世界生成、玩家物理、生物等）
--
-- ====================================================================

local Config = require("config.GameConfig")
local Blocks = require("data.BlockRegistry")
local World = require("world.World")
local WorldGenerator = require("world.WorldGenerator")
local ChunkStreamer = require("world.ChunkStreamer")
local ChunkMeshBuilder = require("world.ChunkMeshBuilder")
local TextureAtlas = require("rendering.TextureAtlas")
local TexturePackManager = require("rendering.texturepacks.TexturePackManager")
local LoadingScreen = require("ui.LoadingScreen")
local Player = require("player.Player")
local PlayerController = require("player.PlayerController")
local BlockInteraction = require("player.BlockInteraction")
local MobManager = require("entity.MobManager")
local Benchmark = require("devtools.Benchmark")
local GameSystems = require("core.GameSystems")
local ItemStack = require("items.ItemStack")
local ItemDropSystem = require("items.ItemDropSystem")
local ProjectileManager = require("items.ProjectileManager")
local ItemSaveSystem = require("items.ItemSaveSystem")
local TowerManager = require("building.TowerManager")

require "urhox-libs.UI.GameHUD"

local Standalone = {}

-- 全局状态
---@type Scene
local scene_ = nil
---@type World
local world_ = nil
---@type WorldGenerator
local worldGenerator_ = nil
---@type ChunkStreamer
local chunkStreamer_ = nil
---@type ChunkMeshBuilder
local chunkBuilder_ = nil
---@type Player|nil
local player_ = nil
---@type PlayerController
local playerController_ = nil
---@type BlockInteraction
local blockInteraction_ = nil
---@type MobManager
local mobManager_ = nil
---@type ItemDropSystem|nil
local itemDropSystem_ = nil
---@type ProjectileManager|nil
local projectileManager_ = nil
---@type TowerManager|nil
local towerManager_ = nil
---@type Node
local cameraNode_ = nil
---@type Camera
local camera_ = nil

-- 输入状态
local selectedBlockType_ = 1

-- 光照
local lightGroup_ = nil
local zone_ = nil
local sunLight_ = nil

-- 性能测试
local benchmark_ = nil

-- 加载状态
local loadingState_ = "init"
local loadingCoroutine_ = nil
local loadingProgress_ = { phase = "", current = 0, total = 1 }

-- 出生点 / 重生状态
local spawnPos_ = Vector3(0, 0, 0)
local respawnTimer_ = 0.0

-- UI 时间显示节流
local timeUiTimer_ = 0.0

-- 物品系统存档计时
local itemSaveTimer_ = 0.0

-- 炸弹人自爆的短暂闪光
---@type { node: Node, light: Light, life: number, maxLife: number }[]
local explosionFlashes_ = {}

-- ============================================================================
-- 初始化
-- ============================================================================

function Standalone.Start()
    print("=== Minecraft Standalone Starting ===")

    -- 创建场景
    Standalone.CreateScene()

    -- 创建世界（空）
    world_ = World.new()
    worldGenerator_ = WorldGenerator.new()

    -- 创建纹理和区块构建器
    TexturePackManager:setCurrent("classic")
    local textureAtlas = TextureAtlas:new()
    local textures = textureAtlas:generate()

    chunkBuilder_ = ChunkMeshBuilder.new(world_, scene_)
    chunkBuilder_:setTextures(textures)

    -- 创建区块流式加载器（无限地形）
    chunkStreamer_ = ChunkStreamer.new(world_, worldGenerator_, chunkBuilder_)

    -- 初始化 UI 框架
    GameSystems:initUIFramework()

    -- 显示加载画面
    LoadingScreen.show()

    -- 初始加载：生成出生点周围区块数据 + 构建网格
    loadingCoroutine_ = chunkStreamer_:loadInitial(0, 0, function(phase, current, total)
        loadingProgress_ = { phase = phase, current = current, total = total }
    end)
    loadingState_ = "generating"

    -- 订阅事件
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    SubscribeToEvent("MouseButtonDown", "HandleMouseButtonDown")

    print("[Standalone] Initial chunk loading started (async)...")
end

function Standalone.CreateScene()
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    -- 加载光照预设
    local lightGroupFile = cache:GetResource("XMLFile", "LightGroup/Daytime.xml")
    lightGroup_ = scene_:CreateChild("LightGroup", LOCAL)
    lightGroup_:LoadXML(lightGroupFile:GetRoot())

    zone_ = lightGroup_:GetComponent("Zone")
    local sunNode = lightGroup_:GetChild("Directional Light")
    if sunNode then
        sunLight_ = sunNode:GetComponent("Light")
    end

    if zone_ then
        zone_.depthFogStart = Config.Camera.FOG_START
        zone_.depthFogEnd = Config.Camera.FOG_END
    end
end

function Standalone.OnWorldReady()
    print("[Standalone] World ready!")
    loadingState_ = "ready"
    LoadingScreen.hide()

    -- 计算出生点
    local spawnBlockX, spawnBlockZ = 0, 0
    local spawnBlockY = world_:getGroundHeight(spawnBlockX, spawnBlockZ) + 1
    spawnPos_ = Vector3(
        spawnBlockX * Config.World.BLOCK_SIZE,
        spawnBlockY * Config.World.BLOCK_SIZE,
        spawnBlockZ * Config.World.BLOCK_SIZE
    )

    -- 创建本地玩家
    player_ = Player.new(scene_)
    player_:setPosition(spawnPos_)

    -- 创建玩家控制器
    playerController_ = PlayerController.new(player_, world_)

    -- 使用玩家自带的相机
    cameraNode_ = player_:getCameraNode()
    camera_ = player_:getCamera()

    -- 设置视口
    local viewport = Viewport:new(scene_, camera_)
    renderer:SetViewport(0, viewport)

    -- 初始化 GameSystems（共享子系统）
    local sunNode = lightGroup_ and lightGroup_:GetChild("Directional Light") or nil
    GameSystems:init(scene_, cameraNode_, world_, {
        chunkBuilder = chunkBuilder_,
        lightGroup = lightGroup_,
        zone = zone_,
        sunLight = sunLight_,
        sunNode = sunNode,
    })

    -- 创建方块交互（单机模式）
    blockInteraction_ = BlockInteraction.new(player_, world_, {
        isNetworkMode = false
    })
    blockInteraction_:setTorchDecorator(GameSystems:getTorchDecorator())
    blockInteraction_:setParticleSystem(GameSystems:getParticleSystem())

    -- 物品系统：世界掉落物 + 弓箭投射物
    itemDropSystem_ = ItemDropSystem.new(scene_, world_)
    projectileManager_ = ProjectileManager.new(scene_, world_)
    blockInteraction_:setItemSystems(itemDropSystem_, projectileManager_)
    blockInteraction_:setCraftingTableHandler(function()
        GameSystems:openCraftingTable()
    end)

    -- 防御塔：方块变化时重新检测基座
    towerManager_ = TowerManager.new(scene_, world_)
    blockInteraction_:setBlockChangedHandler(function(x, y, z, oldType, newType)
        if towerManager_ then
            towerManager_:onBlockChanged(x, y, z, oldType, newType)
        end
    end)

    -- 创建 UI
    GameSystems:createUI("Standalone", player_, function(blockType)
        selectedBlockType_ = blockType
    end)

    -- 背包界面 + 物品系统接线
    GameSystems:setPlayerController(playerController_)
    GameSystems:setItemDropSystem(itemDropSystem_)
    GameSystems:createInventoryUI(player_, {
        dropSystem = itemDropSystem_,
        projectiles = projectileManager_,
    })

    -- 读档；没有存档就给初始装备（生存模式开局）
    if not ItemSaveSystem.load(player_, itemDropSystem_) then
        Standalone.giveStartingItems()
    end
    local hotbar = GameSystems:getHotbar()
    if hotbar then
        hotbar:update()
    end

    -- 创建移动端输入
    GameSystems:createMobileInput({
        on_look = function(deltaYaw, deltaPitch)
            playerController_:applyLookDelta(deltaYaw, deltaPitch)
        end,
        -- 背包打开时，触摸/点击不触发挖掘和放置
        on_tap = function()
            if not GameSystems:isInventoryOpen() then
                blockInteraction_:onLeftClick()
            end
        end,
        on_place = function()
            if not GameSystems:isInventoryOpen() then
                blockInteraction_:onRightClick()
            end
        end,
        blockInteraction = blockInteraction_,
        playerController = playerController_,
        autoMouseLocking = true,
    })

    -- 设置摇杆
    local mobileInput = GameSystems:getMobileInput()
    if mobileInput then
        playerController_:setJoystick(mobileInput.joystick)
    end

    -- 创建生物管理器（共享世界生成器的群系数据，保证群系判断与地形一致）
    mobManager_ = MobManager.new(scene_, world_, worldGenerator_.biome)

    -- 生物死亡 → 掉落物品
    mobManager_.onMobDeath = function(mob)
        if itemDropSystem_ then
            itemDropSystem_:dropMobLoot(mob.mobType, mob:getPosition())
        end
    end

    -- 防御塔的索敌数据源
    towerManager_:setMobProvider(function()
        return mobManager_ and mobManager_.mobs or {}
    end)

    -- 炸弹人自爆：清掉方块后同步防御塔（可能炸掉基座/火焰石）
    mobManager_.onBlocksCleared = function(_cleared)
        if towerManager_ then
            towerManager_:rebuildTowers()
        end
    end
    mobManager_.onExplosionEffect = function(center, cleared)
        Standalone.spawnExplosionEffect(center, cleared)
    end

    -- 开局在出生点附近预置一座防御塔
    Standalone.buildSpawnTower()

    -- 新加载区块：额外尝试一次「环境原生动物」生成（Design.md）
    chunkStreamer_.onChunkLoaded = function(cx, cz)
        if mobManager_ and player_ then
            mobManager_:initialSpawnInChunk(cx, cz, GameSystems:isNight(), player_:getPosition())
        end
    end

    -- 开局只刷中立生物，避免出生即被围殴
    mobManager_:spawnInitial(player_, GameSystems:isNight(), Config.MobSpawning.INITIAL_COUNT)

    -- 初始血条
    local ui = GameSystems:getUIManager()
    if ui then
        ui:setPlayerHealth(player_:getHealth(), player_:getMaxHealth())
    end

    -- 创建性能测试工具
    benchmark_ = Benchmark.new(world_, blockInteraction_, chunkBuilder_, worldGenerator_)

    print("=== Minecraft Standalone Ready ===")
end

---自爆特效：碎块粒子 + 短暂点光源
---@param center Vector3
---@param cleared { x: integer, y: integer, z: integer, blockType: number }[]
function Standalone.spawnExplosionEffect(center, cleared)
    local ps = GameSystems:getParticleSystem()
    if ps and #cleared > 0 then
        local samples = math.min(8, #cleared)
        for i = 1, samples do
            local idx = math.floor((i - 1) * #cleared / samples) + 1
            local b = cleared[idx]
            ps:spawnBreakParticles(b.x, b.y, b.z, b.blockType)
        end
    end

    if not scene_ then
        return
    end

    local node = scene_:CreateChild("ExplosionFlash")
    node.position = center + Vector3(0, Config.World.BLOCK_SIZE * 0.8, 0)
    local light = node:CreateComponent("Light")
    light.lightType = LIGHT_POINT
    light.color = Color(1.0, 0.55, 0.15)
    light.range = 16.0
    light.brightness = 8.0
    light.castShadows = false

    explosionFlashes_[#explosionFlashes_ + 1] = {
        node = node, light = light, life = 0.3, maxLife = 0.3,
    }
end

---在出生点附近生成一座 5 层防御塔（范围 15 格）
function Standalone.buildSpawnTower()
    if not towerManager_ or not world_ then
        return
    end

    local spawnBX, spawnBZ = 0, 0
    local candidates = {
        { 6, 0 }, { -8, 0 }, { 0, 8 }, { 0, -8 },
        { 8, 8 }, { -8, -8 }, { 10, 0 }, { -10, 0 },
    }

    ---@type { bx: integer, bz: integer, y: integer }|nil
    local chosen = nil

    -- 5 层塔的基座脚印：X 宽 3、Z 深 5（顶层只有 Z 深 1，往下逐层加宽）
    for _, off in ipairs(candidates) do
        local bx = spawnBX + off[1]
        local bz = spawnBZ + off[2]
        local maxH, minH = -1, 999
        for dx = 0, 2 do
            for dz = 0, 4 do
                local h = world_:getGroundHeight(bx + dx, bz + dz)
                if h > maxH then maxH = h end
                if h < minH then minH = h end
            end
        end

        -- 塔高 6 格（5 层基座 + 火焰石），需要头顶留足高度
        if maxH > Config.World.WATER_LEVEL + 2
            and maxH + 6 < Config.World.WORLD_HEIGHT
            and (maxH - minH) <= 2 then
            chosen = { bx = bx, bz = bz, y = maxH }
            break
        end
    end

    if not chosen then
        local bx = spawnBX + 6
        chosen = { bx = bx, bz = spawnBZ, y = math.floor(world_:getGroundHeight(bx + 1, spawnBZ)) }
    end
    if not chosen then
        return
    end

    local bx, bz, y0 = chosen.bx, chosen.bz, chosen.y

    -- 清空脚印上方 6 格（5 层基座 + 火焰石，避免树/地形卡进塔里）
    for dx = 0, 2 do
        for dz = 0, 4 do
            for dy = 0, 5 do
                world_:setBlock(bx + dx, y0 + dy, bz + dz, Blocks.AIR)
            end
        end
    end

    -- 从下往上搭 5 层金刚岩：第 k 层（k=1 为顶层）正好 3*k 块。
    -- 每层是一条 X 宽 3、Z 深 k 的矩形：k=5(底)15 块 → k=1(顶)3 块。
    for k = 5, 1, -1 do
        local y = y0 + (5 - k)          -- k=5 → y0，k=1 → y0+4
        for dx = 0, 2 do
            for dz = 0, k - 1 do
                world_:setBlock(bx + dx, y, bz + dz, Blocks.ADAMANT)
            end
        end
    end

    -- 火焰石（攻击台）：放在顶层正中间
    local fx, fy, fz = bx + 1, y0 + 5, bz
    world_:setBlock(fx, fy, fz, Blocks.FLAME_STONE)
    towerManager_:trackFlameStone(fx, fy, fz)
    towerManager_:rebuildTowers()

    print(string.format("[Tower] 出生点附近已生成 5 层防御塔 (%d,%d,%d)，范围 15 格", fx, fy, fz))
end

---初始装备（没有物品存档时）
function Standalone.giveStartingItems()
    if not player_ then
        return
    end
    local inventory = player_:getInventory()
    if not inventory then
        return
    end

    -- 顺序即快捷栏顺序（前 9 件依次落在 1~9 格）
    ---@type table[]
    local items = {
        { "sword", 1 },
        { "pickaxe", 1 },
        { "axe", 1 },
        { "shovel", 1 },
        { "block:9", 32 },      -- 火把
        { "apple", 8 },
        { "block:1", 64 },      -- 草方块
        { "block:2", 64 },      -- 泥土
        { "block:3", 64 },      -- 石头
        { "bow", 1 },
        { "arrow", 16 },
        { "bucket", 1 },
        { "helmet", 1 },
        { "chestplate", 1 },
        { "leggings", 1 },
        { "armguards", 1 },
        { "block:19", 32 },     -- 木板
        { "stick", 16 },
        { "iron_ingot", 16 },
        { "block:67", 18 },     -- 金刚岩（防御塔基座，可搭 2 层）
        { "block:66", 2 },      -- 火焰石（防御塔攻击台）
    }

    for _, entry in ipairs(items) do
        local stack = ItemStack.new(entry[1], entry[2])
        if stack then
            inventory:addStack(stack)
        end
    end
    inventory:markDirty()
    print("[Standalone] 已发放初始装备")
end

---玩家重生
function Standalone.respawnPlayer()
    if not player_ then
        return
    end
    player_:respawn()
    player_:setPosition(spawnPos_)
    player_:setVelocity(Vector3(0, 0, 0))
    player_:setOnGround(false)
    respawnTimer_ = 0.0
    print("[Player] respawned at spawn")
end

-- ============================================================================
-- 每帧更新
-- ============================================================================

function HandleUpdate(eventType, eventData)
    local timeStep = eventData["TimeStep"]:GetFloat()

    -- 加载中：处理协程
    if loadingState_ == "generating" then
        LoadingScreen.setProgress(loadingProgress_)
        if loadingCoroutine_ then
            local ok, err = coroutine.resume(loadingCoroutine_)
            if not ok then print("[Error] Coroutine error: " .. tostring(err)) end
            if coroutine.status(loadingCoroutine_) == "dead" then
                loadingCoroutine_ = nil
                Standalone.OnWorldReady()
            end
        end
        return
    end

    -- 自爆闪光淡出
    for i = #explosionFlashes_, 1, -1 do
        local flash = explosionFlashes_[i]
        flash.life = flash.life - timeStep
        if flash.life <= 0 then
            flash.node:Remove()
            table.remove(explosionFlashes_, i)
        else
            flash.light.brightness = 8.0 * (flash.life / flash.maxLife)
        end
    end

    -- 死亡：等待重生
    if player_ and player_:isDead() then
        respawnTimer_ = respawnTimer_ + timeStep
        if respawnTimer_ >= Config.Player.DEATH_RESPAWN_DELAY then
            Standalone.respawnPlayer()
        end
        return
    end

    -- 正常游戏状态

    -- Standalone 专属：本地玩家更新
    if playerController_ then
        playerController_:updateMouseLook(timeStep)
        playerController_:updateMovement(timeStep)
    end
    if player_ then
        player_:update(timeStep)
    end

    -- 区块流式加载（无限地形）
    if chunkStreamer_ and player_ then
        chunkStreamer_:update(player_:getPosition(), timeStep)
    end

    -- 更新生物（按昼夜规则生成）
    if mobManager_ and player_ then
        mobManager_:update(timeStep, player_, GameSystems:isNight())
    end

    -- 防御塔自动攻击
    if towerManager_ then
        towerManager_:update(timeStep)
    end

    -- 掉落物 / 拾取 + 弓箭
    if itemDropSystem_ and player_ then
        itemDropSystem_:update(timeStep, player_)
    end
    if projectileManager_ and mobManager_ then
        projectileManager_:update(timeStep, mobManager_.mobs)
    end

    -- 更新玩家血条 / 饥饿 + 游戏时间（UI 文本节流到 4Hz，避免每帧触发布局）
    if player_ then
        local ui = GameSystems:getUIManager()
        if ui then
            ui:setPlayerHealth(player_:getHealth(), player_:getMaxHealth())
            ui:setPlayerHunger(player_:getHunger(), player_:getMaxHunger())
            timeUiTimer_ = timeUiTimer_ + timeStep
            if timeUiTimer_ >= 0.25 then
                timeUiTimer_ = 0.0
                ui:setGameTime(GameSystems:getTimeText())
            end
        end
    end

    -- 物品自动存档
    itemSaveTimer_ = itemSaveTimer_ + timeStep
    if itemSaveTimer_ >= Config.Items.SAVE_INTERVAL then
        itemSaveTimer_ = 0.0
        ItemSaveSystem.save(player_, itemDropSystem_)
    end

    -- 更新共享子系统
    GameSystems:update(timeStep)
end

-- ============================================================================
-- 事件处理
-- ============================================================================

function HandleKeyDown(eventType, eventData)
    local key = eventData["Key"]:GetInt()

    -- Standalone 专属：性能测试按键
    if key == KEY_B and benchmark_ then
        benchmark_:runChunkRebuildTest()
        return
    end
    if key == KEY_P and benchmark_ then
        benchmark_:runAll(false)
        return
    end
    if key == KEY_O and benchmark_ then
        benchmark_:runAll(true)
        return
    end

    -- 共享按键处理
    if GameSystems:handleKeyDown(key) then
        return
    end
end

function HandleMouseButtonDown(eventType, eventData)
    local button = eventData["Button"]:GetInt()

    -- 左键：优先攻击瞄准的生物，否则破坏方块
    if button == MOUSEB_LEFT and mobManager_ and player_ and not player_:isDead() then
        local target = mobManager_:findTargetMob(player_)
        if target then
            if player_:attackMob(target) then
                player_:swingArm()
                print(string.format("[Combat] hit %s, hp=%.1f", target.def.name, target:getHealth()))
            end
            return
        end
    end

    GameSystems:handleMouseButtonDown(button, blockInteraction_)
end

-- ============================================================================
-- 清理
-- ============================================================================

function Standalone.Stop()
    print("[Standalone] Shutting down...")

    -- 退出时保存物品（背包 + 地上的掉落物）
    if player_ then
        ItemSaveSystem.save(player_, itemDropSystem_)
    end

    for _, flash in ipairs(explosionFlashes_) do
        if flash.node then
            flash.node:Remove()
        end
    end
    explosionFlashes_ = {}

    if towerManager_ then
        towerManager_:destroy()
        towerManager_ = nil
    end
    if projectileManager_ then
        projectileManager_:destroy()
        projectileManager_ = nil
    end
    if itemDropSystem_ then
        itemDropSystem_:destroy()
        itemDropSystem_ = nil
    end
    if mobManager_ then
        mobManager_:destroy()
        mobManager_ = nil
    end
    GameSystems:destroy()
end

-- ============================================================================
-- 自动化验收接口（只被 -validate-test 脚本调用，正常玩法不使用）
-- ============================================================================

---@class DebugGameContext
---@field scene Scene
---@field world World
---@field player Player
---@field mobManager MobManager
---@field towerManager TowerManager

---获取当前单机局内对象（供 scripts/devtools/*.lua 断言）
---@return DebugGameContext
function GetDebugGameContext()
    return {
        scene = scene_,
        world = world_,
        player = player_,
        mobManager = mobManager_,
        towerManager = towerManager_,
    }
end

return Standalone
