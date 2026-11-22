-- ====================================================================
-- config/GameConfig.lua
-- 游戏配置模块 - 集中管理所有常量
-- ====================================================================

local GameConfig = {}

-- ============================================
-- 世界大小预设 (修改这里切换世界大小)
-- ============================================
local WORLD_SIZE_PRESET = "medium" -- 可选: "tiny", "small", "medium", "large", "huge"

local WorldSizePresets = {
    tiny   = { distance = 2, height = 64 },   -- 64×64,   25 区块  (测试用)
    small  = { distance = 4, height = 64 },   -- 128×128, 81 区块  (轻量)
    medium = { distance = 6, height = 80 },   -- 192×192, 169 区块 (推荐)
    large  = { distance = 8, height = 96 },   -- 256×256, 289 区块 (较大)
    -- 不推荐更大的地图了， 再大内存会超过1G，在网页和手机上会很危险了
}

local preset = WorldSizePresets[WORLD_SIZE_PRESET] or WorldSizePresets.medium

-- 世界设置
GameConfig.World = {
    CHUNK_SIZE = 16,                      -- 区块宽度/深度（方块数）
    WORLD_HEIGHT = preset.height,         -- 世界高度（方块数）
    RENDER_DISTANCE = preset.distance,    -- 各方向渲染区块数
    BLOCK_SIZE = 2.0,                     -- 方块世界单位大小
    WATER_LEVEL = math.floor(preset.height * 0.47),  -- 水平面高度（约47%高度）
    MAX_CHUNK_REBUILDS_PER_FRAME = 1      -- 每帧最大区块重建数（避免挖地卡顿）
}

-- 玩家设置
GameConfig.Player = {
    HEIGHT = 1.8,                 -- 玩家高度（方块数）
    SPEED = 8.0,                  -- 移动速度
    FLY_SPEED = 16.0,             -- 飞行速度
    FLY_VERTICAL_SPEED = 12.0,    -- 飞行上下速度
    JUMP_SPEED = 12.0,            -- 跳跃速度
    GRAVITY = -25.0,              -- 重力加速度
    REACH_DISTANCE = 10.0,        -- 方块交互距离
    COLLISION_RADIUS = 0.3,       -- 碰撞半径

    -- 战斗属性（Design.md：伤害 = 攻击力 / 护甲）
    HEALTH = 100.0,               -- 血量
    ARMOR = 10.0,                 -- 护甲
    ATTACK = 100.0,               -- 攻击力
    ATTACK_RANGE = 6.0,           -- 近战攻击距离（世界单位）
    ATTACK_COOLDOWN = 0.4,        -- 攻击冷却（秒）
    DEATH_RESPAWN_DELAY = 2.0     -- 死亡后重生延迟（秒）
}

-- ============================================
-- 生物配置（Design.md）
-- 敌对生物：会主动攻击玩家；中立生物：不会攻击
-- 伤害公式：伤害 = 攻击力 / 目标护甲
-- ============================================
-- 生物定义
-- spawnTime: "night" 只夜间生成 / "any" 日夜都生成
-- category:  "monster" 敌对怪物 / "animal" 陆地动物（各自有独立数量上限）
-- weight:    生成权重（越高越容易被抽中）
-- group:     {最小, 最大} 每次生成成群出现的数量
-- biomes:    允许生成的生物群系（"plains"/"forest"/"desert"/"mountains"；不填=不限）
-- ground:    允许的地面类型（"grass"/"sand"/"dirt"/"stone"/"snow"/"any"）
GameConfig.Mobs = {
    -- 敌对生物
    ZOMBIE  = { name = "僵尸",   hostile = true,  attack = 100, armor = 10, health = 100, ranged = false, fly = false, speed = 3.0, range = 2.0, spawnTime = "night", category = "monster", weight = 10, group = {1, 3}, biomes = {"plains", "forest", "desert"}, ground = {"grass", "dirt", "sand", "stone", "snow"}, color = {0.35, 0.55, 0.25}, size = {0.8, 1.8, 0.6} },
    GHOST   = { name = "幽灵",   hostile = true,  attack = 50,  armor = 10, health = 50,  ranged = false, fly = true,  speed = 4.0, range = 2.0, spawnTime = "night", category = "monster", weight = 5,  group = {1, 2}, biomes = {"plains", "forest", "desert"}, ground = {"any"}, color = {0.82, 0.82, 0.95}, size = {0.8, 1.6, 0.6} },
    -- 炸弹人：Design.md「近战攻击，攻击时会爆炸，将周围2格内所有生物造成伤害，
    -- 2格的方块清除掉，同时自己也会被炸死」「行动：行走」
    -- explodes / explosionRadius 让 MobManager 执行自爆结算
    BOMBER  = { name = "炸弹人", hostile = true,  attack = 300, armor = 10, health = 30,  ranged = false, fly = false, speed = 3.5, range = 2.0, explodes = true, explosionRadius = 2.0, spawnTime = "any", category = "monster", weight = 4, group = {1, 2}, biomes = {"plains", "forest", "desert"}, ground = {"grass", "dirt", "sand", "stone"}, color = {0.20, 0.20, 0.24}, size = {0.9, 1.6, 0.9} },
    ARCHER  = { name = "弓箭手", hostile = true,  attack = 100, armor = 10, health = 50,  ranged = true,  fly = false, speed = 3.0, range = 8.0, spawnTime = "any",   category = "monster", weight = 4,  group = {1, 2}, biomes = {"plains", "forest"}, ground = {"grass", "dirt", "stone"}, color = {0.55, 0.35, 0.20}, size = {0.8, 1.7, 0.6} },

    -- 中立生物
    COW     = { name = "牛",     hostile = false, attack = 0,   armor = 10, health = 100, ranged = false, fly = false, speed = 1.5, range = 0.0, spawnTime = "any", category = "animal", weight = 6, group = {2, 4}, biomes = {"plains", "forest"}, ground = {"grass"}, color = {0.92, 0.92, 0.92}, size = {1.1, 1.2, 0.9} },
    SHEEP   = { name = "羊",     hostile = false, attack = 0,   armor = 10, health = 80,  ranged = false, fly = false, speed = 1.5, range = 0.0, spawnTime = "any", category = "animal", weight = 8, group = {2, 4}, biomes = {"plains", "forest", "mountains"}, ground = {"grass", "snow"}, color = {0.95, 0.95, 0.95}, size = {1.0, 1.1, 0.8} },
    PIG     = { name = "猪",     hostile = false, attack = 0,   armor = 10, health = 50,  ranged = false, fly = false, speed = 1.5, range = 0.0, spawnTime = "any", category = "animal", weight = 6, group = {2, 3}, biomes = {"plains", "forest"}, ground = {"grass"}, color = {0.96, 0.70, 0.75}, size = {0.9, 0.9, 0.9} },
    CHICKEN = { name = "鸡",     hostile = false, attack = 0,   armor = 10, health = 30,  ranged = false, fly = false, speed = 1.5, range = 0.0, spawnTime = "any", category = "animal", weight = 8, group = {2, 4}, biomes = {"plains", "forest", "desert"}, ground = {"grass", "sand"}, color = {0.96, 0.90, 0.70}, size = {0.5, 0.7, 0.4} },
}

-- 生物生成配置（Design.md：以区块为单位、以玩家为范围、环境决定种类、权重决定概率）
GameConfig.MobSpawning = {
    INITIAL_COUNT = 4,           -- 开局生成任务次数（每次成群 1~4 只）
    INITIAL_NEUTRAL_ONLY = true, -- 开局不刷敌对生物，避免出生即被围殴

    SPAWN_INTERVAL = 2.5,        -- 生成任务间隔（秒）
    MIN_CHUNK_DIST = 2,          -- 候选区块距玩家最近区块数（过近排除）
    MAX_CHUNK_DIST = 4,          -- 候选区块距玩家最远区块数（过远排除）
    MIN_DISTANCE = 12.0,         -- 距玩家小于该距离（方块）的格子禁止生成
    GROUP_RADIUS = 4.0,          -- 群体生成时的散布半径（方块）
    GROUP_ATTEMPTS = 10,         -- 每只生物最多尝试的位置数

    -- 分类数量上限（达到上限时暂停该类别自然生成）
    CATEGORY_CAPS = {
        monster = 12,            -- 敌对怪物
        animal = 16,             -- 陆地动物
    },
    MAX_MOBS = 32,               -- 绝对总数上限（性能兜底）

    DESPAWN_DISTANCE = 220.0,    -- 超过该距离（世界单位）的生物自然消失（须大于最远生成距离）
    SPAWN_GRACE = 3.0,           -- 出生/重生后的无敌时间（秒）
    RENDER_CULL_DISTANCE = 72.0  -- 超过该距离生物节点整体禁用（省渲染开销）
}

-- ============================================
-- 生物 AI 配置（Design.md「AI机制」）
-- 状态机：IDLE → WANDERING → CHASING → ATTACKING；索敌/追踪/近战参数集中在这里
-- 单位说明：带 _RANGE / _DIST / _RADIUS / _FALL 的都是「格」，运行时乘 BLOCK_SIZE 换算世界单位
-- ============================================
GameConfig.MobAI = {
    TICK_INTERVAL = 0.2,         -- AI 重决策间隔（秒），与渲染帧解耦

    -- 随机游走（中立生物 + 未索敌的敌对生物）
    WANDER_RADIUS = 10.0,        -- 游走半径（格）
    WANDER_MIN_DIST = 3.0,       -- 最短游走距离（格）
    WANDER_WAIT_MIN = 2.0,       -- 两次游走间等待最短（秒）
    WANDER_WAIT_MAX = 6.0,       -- 两次游走间等待最长（秒）
    WANDER_TRY = 8,              -- 每次挑选游走目标点的尝试次数

    -- 目标检测
    DETECT_RANGE = 16.0,         -- 检测半径（格）
    REQUIRE_LOS = true,          -- 需要视线（隔墙不发现）
    LOS_STEP = 0.4,              -- 视线检测采样步长（格）

    -- 目标保持与丢失
    LOSE_RANGE = 24.0,           -- 目标超过该距离（格）判定丢失
    LOSE_TIME = 10.0,            -- 长时间不可见 / 无法接近判定丢失（秒）

    -- 追踪 / 寻路
    REPATH_INTERVAL = 0.5,       -- 重算路径间隔（秒）
    REPATH_DIST = 2.0,           -- 目标移动超过该距离（格）才重算
    PATH_MAX_NODES = 256,        -- A* 搜索节点预算
    MAX_FALL = 3,                -- 允许下落的最大高度（格）
    STEP_HEIGHT = 1,             -- 允许登上的台阶高度（格）

    -- 近战攻击
    ATTACK_RANGE = 1.5,          -- 近战攻击距离（格）
    ATTACK_INTERVAL = 1.5,       -- 攻击间隔（秒）
}

-- ============================================
-- 物品系统配置（Design.md「物品」）
-- ============================================
GameConfig.Items = {
    PICKUP_RADIUS = 3.0,          -- 掉落物拾取半径（世界单位）
    PICKUP_DELAY = 0.5,           -- 掉落后的拾取冷却（秒）
    DESPAWN_TIME = 300.0,         -- 掉落物生命周期（秒，MC 默认 5 分钟）
    MERGE_RADIUS = 1.8,           -- 同类掉落物自动合并半径
    SAVE_INTERVAL = 10.0,         -- 自动存档间隔（秒）
    SAVE_FILE = "items_save.json",-- 存档文件名（引擎自动做项目/用户隔离）
    DROP_THROW_SPEED = 5.0,       -- 玩家丢弃物品时的初速度

    -- 饥饿值（食物行为需要）
    HUNGER_MAX = 20,              -- 饥饿值上限
    HUNGER_DRAIN_INTERVAL = 30.0, -- 每多少秒消耗 1 点饥饿值
    STARVE_DAMAGE_INTERVAL = 4.0, -- 饥饿值为 0 时每隔多少秒掉 1 血
    STARVE_DAMAGE = 1.0,

    -- 耐久
    ATTACK_DURABILITY_COST = 1,   -- 每次攻击消耗的武器耐久
    BLOCK_DURABILITY_COST = 1,    -- 每破坏一个方块消耗的工具耐久

    -- 饱和度（Design.md「自然生命回复与饥饿饱和度」）
    SATURATION_MAX = 20,          -- 饱和度上限
    SATURATION_START = 10,        -- 开局饱和度
    REGEN_INTERVAL = 4.0,         -- 自然回血间隔（秒）
    REGEN_AMOUNT = 1,             -- 每次自然回血量
    REGEN_MIN_HUNGER = 17,        -- 饥饿值达到该值才自然回血
}

-- 生肉/熟肉/食物的饱和度（吃下去先填饱和度，再缓慢回血）
GameConfig.FoodSaturation = {
    apple = 4, bread = 6, beef = 2, porkchop = 2, chicken_meat = 2, rotten_flesh = 0,
    cooked_beef = 8, cooked_porkchop = 8, cooked_chicken = 6,
}

-- 经验值（Design.md「经验值与等级」）
GameConfig.XP = {
    BASE_NEXT = 7,                -- 1 级升 2 级所需经验
    PER_LEVEL = 1.2,              -- 每级线性增量
    PER_LEVEL2 = 0.15,            -- 每级二次增量
    MAX_LEVEL = 100,
}

-- 生物死亡经验（按 mobType）
GameConfig.MobXP = {
    ZOMBIE = 5, GHOST = 3, BOMBER = 8, ARCHER = 5,
    COW = 2, SHEEP = 2, PIG = 2, CHICKEN = 1,
}

-- 动物繁殖（Design.md「动物繁殖系统」）
GameConfig.Breeding = {
    LOVE_MODE_DURATION = 5.0,     -- 求偶状态持续（秒）
    BREED_RADIUS = 4.0,           -- 配对距离（格）
    BABY_SCALE = 0.5,             -- 幼体缩放
    GROW_TIME = 240.0,            -- 幼体成长时间（秒）
    BREED_COOLDOWN = 60.0,        -- 繁殖后冷却（秒）
    CHECK_INTERVAL = 1.0,         -- 配对检查间隔（秒）
}

-- 繁殖饲料：物品 ID → 可喂养的生物类型
GameConfig.BreedFood = {
    wheat = { "COW", "SHEEP" },
    apple = { "PIG" },
    wheat_seed = { "CHICKEN" },
}

-- 天气（Design.md「天气系统」）
GameConfig.Weather = {
    ENABLED = true,
    CLEAR_MIN = 240.0, CLEAR_MAX = 600.0,   -- 晴天持续（秒）
    RAIN_MIN = 120.0, RAIN_MAX = 360.0,     -- 雨天持续（秒）
    THUNDER_CHANCE = 0.25,                  -- 下雨时转雷雨的概率
    LIGHTNING_INTERVAL_MIN = 15.0,
    LIGHTNING_INTERVAL_MAX = 60.0,
    DARKNESS_CLEAR = 0.0,
    DARKNESS_RAIN = 0.35,
    DARKNESS_THUNDER = 0.55,
    DARKNESS_SNOW = 0.28,
    FADE_SPEED = 0.35,                      -- 天气明暗过渡速度（每秒）
    LIGHTNING_DAMAGE = 1000.0,
    LIGHTNING_RADIUS = 12.0,                -- 闪电命中判定半径（世界单位）
}

-- 生物掉落物（Design.md：生物死亡产生物品）
-- id 为物品 ID，min/max 为掉落数量范围
GameConfig.Loot = {
    ZOMBIE  = { { id = "rotten_flesh", min = 1, max = 2 } },
    GHOST   = { { id = "ectoplasm", min = 1, max = 2 }, { id = "string", min = 1, max = 2 } },
    BOMBER  = { { id = "gunpowder", min = 1, max = 3 } },
    ARCHER  = { { id = "arrow", min = 2, max = 4 }, { id = "stick", min = 1, max = 2 } },
    COW     = { { id = "beef", min = 1, max = 2 }, { id = "leather", min = 1, max = 2 } },
    SHEEP   = { { id = "block:39", min = 1, max = 2 }, { id = "beef", min = 1, max = 1 } },
    PIG     = { { id = "porkchop", min = 1, max = 2 } },
    CHICKEN = { { id = "chicken_meat", min = 1, max = 1 }, { id = "feather", min = 1, max = 2 } },
}

-- ============================================
-- 防御塔（Design.md「建筑」）
-- ============================================
GameConfig.Tower = {
    ATTACK_PER_LAYER = 100.0,   -- 每层基座提供的攻击力（Design.md：攻击力 = 100 × 层数）
    ATTACK_INTERVAL = 1.0,      -- 攻击间隔（秒）
    RANGE_PER_LAYER = 3.0,      -- 基座每层提供 3 格攻击范围
    LAYER_BLOCK_BASE = 3,       -- 第 k 层（从塔顶往下）需要 3*k 块金刚岩
    MAX_LAYERS = 32,            -- 结构检测上限（防御异常结构无限扫描）
    NO_TARGET_RETRY = 0.25,     -- 没有目标时的重试间隔
    BEAM_LIFE = 0.18,           -- 攻击光束存在时间（秒）
    LIGHT_BASE_RANGE = 8.0,     -- 激活的防御塔火焰石点光源基础范围（世界单位）
    SHIELD_ALPHA = 0.10,        -- 光罩透明度（攻击范围提示）
}

-- ============================================
-- 区块流式加载配置（无限地形）
-- ============================================
GameConfig.Streaming = {
    -- 性能预算：按「时间」而不是「个数」限量，避免单个区块耗时突增时卡一帧
    GEN_BUDGET_MS = 3.0,         -- 每帧最多花多少毫秒生成地形数据
    BUILD_BUDGET_MS = 4.0,       -- 每帧最多花多少毫秒推进网格构建
    BUILD_MAX_INFLIGHT = 4,      -- 同时在构建管线里的区块数
    UNLOAD_PADDING = 2,          -- 超出渲染距离多少格后卸载网格
    INITIAL_CHUNKS_PER_FRAME = 3, -- 初始加载每帧生成区块数
    INITIAL_RADIUS = 3           -- 初始加载半径（区块数），其余由流式加载补齐
}

-- 控制设置
GameConfig.Controls = {
    MOUSE_SENSITIVITY = 0.1,          -- 鼠标灵敏度
    TOUCH_LOOK_SENSITIVITY = 0.15,    -- 触摸视角灵敏度
    TOUCH_TAP_MAX_DISTANCE = 10,      -- Tap 判定最大移动距离（设计像素）
    TOUCH_TAP_MAX_DURATION = 300,     -- Tap 判定最大时长（毫秒）
}

-- 粒子效果设置
GameConfig.Particles = {
    GRAVITY = -20.0,              -- 粒子重力
    LIFETIME = 1.5,               -- 粒子生命周期（秒）
    COUNT_MIN = 8,                -- 最小粒子数
    COUNT_MAX = 12                -- 最大粒子数
}

-- 纹理图集设置
GameConfig.Texture = {
    ATLAS_SIZE = 16,              -- 图集大小（16x16格）
    TILE_SIZE = 1.0 / 16          -- 每格UV大小
}

-- 噪声生成设置
GameConfig.Noise = {
    SEED = 12345                  -- 世界生成种子
}

-- 相机设置
GameConfig.Camera = {
    FAR_CLIP = 500.0,             -- 远裁剪面
    FOV = 90.0,                   -- 视野角度
    FOG_START = 50.0,             -- 雾效起始距离
    FOG_END = 300.0,              -- 雾效结束距离
    -- 第三人称相机设置
    THIRD_PERSON_DISTANCE = 4.0,  -- 第三人称相机距离（方块数）
    THIRD_PERSON_HEIGHT = 0.8,    -- 第三人称相机高度偏移（相机比眼睛高1.5方块，角色在屏幕下方）
    THIRD_PERSON_COLLISION = true -- 第三人称相机碰撞检测
}

-- 昼夜循环设置
-- 生物生成规则依赖昼夜（Design.md：僵尸/幽灵夜间生成），必须开启
GameConfig.DayNight = {
    ENABLED = true,               -- 是否启用昼夜循环
    DAY_DURATION = 480,           -- 1 游戏天 = 480 真实秒 (8分钟)
    START_TIME = 6.2,             -- 游戏开始时间 (清晨)
    TIME_SCALE = 1.0,             -- 时间流速倍率 (1.0 = 正常)
}

-- ============================================
-- 功能开关（渐进式功能，让 AI 帮你实现！）
-- ============================================
-- 提示：这些功能的代码框架已搭好，但实现是 TODO
-- 打开开关后，告诉 AI "帮我实现树木生成" 即可！
-- 
GameConfig.Features = {
    -- 世界装饰（需要 AI 实现 WorldGenerator.lua 中的 TODO）
    GENERATE_TREES = false,       -- 树木生成 → tryPlaceTree()
    GENERATE_VEGETATION = false,  -- 花草生成 → tryPlaceVegetation()
    SPAWN_HOUSE = false,          -- 出生小屋 → self.house:generateAtSpawn()

    -- ⚠️ 下面这个不是 TODO，是**已实现**的功能，默认开启
    -- 地质特征：基岩地板 / 按深度分布的矿脉 / 砂砾团 / 黏土 / 高山雪线 / 深层岩浆池
    -- 关掉它世界会退回"只有石头土沙草水"的形态（新方块仍可手动放置）
    RICH_TERRAIN = true,
}

-- 地质特征参数（Features.RICH_TERRAIN = true 时生效）
GameConfig.Terrain = {
    SNOW_LINE_RATIO = 0.70,   -- 超过 WORLD_HEIGHT * 此比例的山顶开始积雪
    SNOW_BLOCK_EXTRA = 6,     -- 再高这么多格，顶层直接是雪块
    FEATURE_CELL = 8,          -- 地质特征的空间格大小（每格最多投放一条矿脉）
}

-- 视觉效果设置
GameConfig.Effects = {
    -- 窒息盒子：相机穿入固体方块时显示方块内部视图（穿墙保护）
    SUFFOCATION_BOX_ENABLED = false,
}

return GameConfig
