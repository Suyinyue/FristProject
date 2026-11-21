# 工程说明（ARCHITECTURE.md）

> Minecraft 风格体素生存游戏 · TapTap Maker / UrhoX / Lua 5.4
>
> 本文档面向接手本工程的 AI 与开发者：说明**已实现内容、模块架构、数据流、约定与坑、测试方式**。
>
> 相关文档：
> - `AGENTS.md`：TapTap Maker / UrhoX 的引擎与资源工具链规则（**必须遵守**）
> - `Design.md`：玩法需求（体素世界、血条、生物生成、**AI 机制**、物品、**建筑/防御塔**）
> - `engine-docs/`、`examples/`、`urhox-libs/`、`.emmylua/`：引擎 API 与示例（以这些为准，不要凭 Urho3D 记忆写代码）

最后更新：2026-11-21（物品系统、防御塔、炸弹人自爆、出生点 5 层预置塔、生物 AI、矿石系统、夜晚全量追踪与权重增长已完成）

---

## 0. 给 AI 的最短阅读路径

1. 先读 `AGENTS.md`（引擎/资源/MCP/构建规则），再读本文件。
2. 玩法改动以 `Design.md` 为准；代码里已经实现的规则见本文对应章节。
3. 改动前先定位模块（见 §2 目录表、§13 快速定位表），只读需要的文件，不要整读大文件。
4. 涉及新引擎能力时，按 `AGENTS.md` 的「文档路由」打开 `engine-docs/` 对应文档；函数签名查 `.emmylua/`。
5. 改完运行本地验证（§12），确认 **0 Lua 运行时错误**；有对应验收脚本时一并跑。

---

## 1. 项目速览

| 项 | 内容 |
|---|---|
| 引擎 | UrhoX（Urho3D 深度定制，Lua 5.4 游戏逻辑） |
| 平台 | TapTap Maker 本地项目，Windows 开发，目标 Web / 移动端 |
| 入口 | `scripts/main.lua` → `Start()` |
| 当前模式 | **单机 Standalone**（`.project/settings.json` 中 `@runtime.multiplayer.enabled = false`） |
| 主循环 | 全局 `SubscribeToEvent("Update", "HandleUpdate")`，在 `network/Standalone.lua` |
| UI | `urhox-libs/UI`（Yoga + NanoVG），禁止用旧原生 UI / raw NanoVG 做菜单 HUD |
| 世界 | 无限地形（区块流式加载），区块 16×16 列，高度 80 |
| 方块尺寸 | `BLOCK_SIZE = 2.0` 世界单位（1 方块 = 2 米），Y 轴向上左手系 |
| 存档 | 物品系统写 `items_save.json`；**世界方块/建筑不持久化** |
| 运行 | `npx -y @taptap/maker preview start --target-dir <项目绝对路径> --json` |

### 坐标系与单位

- 方块坐标 `(bx, by, bz)`：整数，`by` 从 0（世界底部）到 `WORLD_HEIGHT-1`。
- 世界坐标：`x = bx * BLOCK_SIZE`，方块中心是 `(bx+0.5)*BLOCK_SIZE`。
- 生物 `node.position` 的原点在**脚下**；玩家 `node.position` 也是脚下，相机在眼睛高度。
- 玩家高度 1.8 方块 = 3.6 世界单位；交互距离 10 世界单位 = 5 方块。

### 单机 / 联机

`main.lua` 根据引擎全局判断：

```lua
IsServerMode()  -> network/Server.lua
IsNetworkMode() -> network/Client.lua
否则            -> network/Standalone.lua   -- 当前实际运行的分支
```

`network/Client.lua`、`Server.lua`、`Shared.lua` 是遗留的多人脚手架；**当前所有玩法改动都放在 `Standalone.lua` + 共享模块里**。不要为了联机去改 `.project` 的多人开关。

---

## 2. 目录与模块职责

```
scripts/
├── main.lua                入口：分流 Server / Client / Standalone
├── network/
│   ├── Standalone.lua      单机主流程：世界/玩家/生物/掉落/防御塔/存档接线 + HandleUpdate
│   ├── Client.lua/Server.lua/Shared.lua   多人脚手架（当前未启用）
├── core/
│   └── GameSystems.lua     共享子系统：UI、Hotbar、背包、特效、火把、昼夜、移动输入、按键
├── config/
│   ├── GameConfig.lua      全部玩法数值（世界/玩家/生物/物品/防御塔/流式加载/昼夜）
│   └── GameEvents.lua      本地事件名（方块破坏/放置）
├── world/
│   ├── World.lua           方块数据 + 光照 + 状态 + 脏区块标记
│   ├── WorldGenerator.lua  地形/群系/矿脉/水/岩浆/雪线
│   ├── ChunkStreamer.lua   无限地形流式加载（生成预算 + 异步网格 + 卸载）
│   ├── ChunkMeshBuilder.lua 区块网格异步切片构建（按渲染层分材质）
│   └── DayNightCycle.lua   昼夜时间、太阳角度、LightGroup 切换
├── terrain/
│   ├── NoiseGenerator.lua  噪声
│   ├── BiomeGenerator.lua  群系（PLAINS=2 / FOREST=3 / DESERT=4 / MOUNTAINS=5）
│   ├── TreeDecorator.lua / HouseGenerator.lua   预留装饰（默认关闭）
│   └── TorchDecorator.lua  火把独立节点与点光源
├── rendering/
│   ├── TextureAtlas.lua    纹理图集入口
│   ├── ParticleSystem.lua  方块破坏粒子
│   └── texturepacks/
│       ├── AtlasLayout.lua tile 名称 → {row,col} 的唯一真源
│       ├── ClassicPack.lua 256×256 / 16px 像素风
│       ├── HDPack.lua      512×512 / 32px PBR（漫反射+法线+高光）
│       └── TexturePackManager.lua
├── data/
│   ├── BlockRegistry.lua   方块注册表（ID 0~67，数据驱动）
│   ├── BlockShapes.lua     半砖/楼梯/栅栏/门/活板门的碰撞盒与网格
│   ├── BlockState.lua      方块状态（朝向/上下半/开关）打包
│   ├── BlockPalette.lua    创造模式「方块」页（分页）
│   ├── BlockHarvest.lua    方块工具要求 + 掉落表
│   ├── ItemDefinitions.lua 物品定义（非方块物品 + 自动生成方块物品）
│   └── CraftingRecipes.lua 合成配方（有序/无序）
├── items/                  物品系统（详见 §7）
├── building/
│   └── TowerManager.lua    防御塔结构检测 + 自动攻击（详见 §8）
├── player/
│   ├── Player.lua          玩家属性/背包/装备加成/饥饿/药水效果/攻击
│   ├── PlayerController.lua 移动、碰撞、自动上台阶、飞行、鼠标视角
│   ├── BlockInteraction.lua DDA 射线、破坏/放置/使用、工具/耐久/掉落回调
│   ├── FirstPersonArm.lua  第一人称手臂与手持方块
│   └── PlayerBody.lua      第三人称身体
├── entity/
│   ├── Mob.lua             生物实体：血量、朝向、飞行/悬浮、剔除；AI 委托给 ai/
│   ├── MobManager.lua      生成机制、死亡掉落、自爆结算
│   ├── MobModel.lua        多部件方块模型（biped/bomber/ghost/quadruped/bird）
│   ├── HealthBar.lua       生物头顶血条（朝向玩家）
│   └── ai/
│       ├── AIController.lua   AI 总控：状态机 + 游走/检测/追踪/攻击
│       ├── AIStateMachine.lua 状态机（IDLE/WANDERING/CHASING/ATTACKING）
│       └── Pathfinding.lua    方块级 A* 寻路 + 视线检测
├── ui/
│   ├── UIManager.lua       根 UI：准星、血条、饥饿、时间、背包按钮、Hotbar
│   ├── Hotbar.lua          9 格快捷栏（物品系统）
│   ├── InventoryUI.lua     背包/装备/2×2 或 3×3 合成/创造页
│   ├── MobileInputManager.lua 虚拟摇杆 + 触屏视角 + 挖掘/放置按钮
│   ├── LoadingScreen.lua / UnderwaterOverlay.lua / SuffocationBox.lua
│   └── DebugOverlay.lua
├── devtools/
│   ├── ItemUiCheck.lua     物品 UI/合成/丢弃验收脚本（仅 validate 加载）
│   ├── TowerCheck.lua      防御塔验收脚本
│   ├── BomberCheck.lua     炸弹人自爆验收脚本
│   ├── Benchmark.lua       性能测试（B/P/O 键）
│   └── ValidateBlocks.lua / DumpAtlas.lua / BlockShowcase.lua
└── utils/TempPool.lua
```

工程根还包含：`assets/`（用户资源）、`engine-docs/`、`.emmylua/`、`urhox-libs/`、`templates/`、`examples/`、`.project/`、`.cache/`、`.maker-preview/`（预览缓存，gitignored）。

---

## 3. 启动时序

```
main.lua Start()
└─ Standalone.Start()
   ├─ Scene + LightGroup(Daytime.xml) + Zone + 平行光
   ├─ World.new() / WorldGenerator.new()
   ├─ TexturePackManager:setCurrent("classic")
   ├─ TextureAtlas:generate() -> ChunkMeshBuilder:setTextures()
   ├─ ChunkStreamer.new(world, generator, chunkBuilder)
   ├─ GameSystems:initUIFramework()   -- UI.Init（整个进程一次）
   ├─ LoadingScreen.show()
   ├─ loadingCoroutine = chunkStreamer:loadInitial(0, 0)
   └─ SubscribeToEvent("Update"/"KeyDown"/"MouseButtonDown")

HandleUpdate（每帧）
└─ 加载中：resume(loadingCoroutine)，进度写 LoadingScreen
   └─ 协程结束后 → OnWorldReady()（只执行一次）

OnWorldReady()
├─ 计算出生点（方块 0,0 的 getGroundHeight）
├─ Player.new(scene) / PlayerController.new(player, world)
├─ Viewport(scene, player.camera) -> renderer
├─ GameSystems:init(scene, cameraNode, world, {chunkBuilder, lightGroup, zone, sunLight, sunNode})
├─ BlockInteraction.new(player, world, {isNetworkMode=false})
│  ├─ setTorchDecorator / setParticleSystem
│  ├─ ItemDropSystem.new / ProjectileManager.new / setItemSystems
│  └─ setCraftingTableHandler / setBlockChangedHandler
├─ TowerManager.new(scene, world)
├─ GameSystems:setPlayerController / setItemDropSystem
├─ GameSystems:createUI("Standalone", player)
├─ GameSystems:createInventoryUI(player, {dropSystem, projectiles})
├─ ItemSaveSystem.load(...) 或 giveStartingItems()
├─ GameSystems:createMobileInput(...)
├─ MobManager.new(scene, world, worldGenerator.biome)
│  ├─ onMobDeath -> dropMobLoot
│  ├─ onBlocksCleared -> towerManager:rebuildTowers()
│  ├─ onExplosionEffect -> 粒子 + 闪光
│  ├─ setMobProvider(mobManager.mobs)
│  ├─ buildSpawnTower()           -- 出生点附近预置 2 层防御塔
│  ├─ chunkStreamer.onChunkLoaded -> initialSpawnInChunk
│  └─ spawnInitial(player, isNight, 4)
└─ Benchmark.new(...)

正常每帧 HandleUpdate 顺序：
玩家死亡/重生 → 玩家控制器移动 → Player.update → ChunkStreamer.update
→ MobManager.update → TowerManager.update → ItemDropSystem.update
→ ProjectileManager.update → HUD（血/饥饿/时间）→ 自动存档计时 → GameSystems.update
```

`GameSystems:update` 内部还会更新：昼夜、火把、脏区块网格、粒子、UI、窒息盒、水下效果、背包界面、背包脏标记刷新。

---

## 4. 世界、地形与渲染

### 4.1 World 数据结构

- 区块字典：`world.chunkData[chunkX * 65536 + chunkZ]`（数值键），字符串键 `"cx,cz"` 用于节点/网格登记。
- 每个区块存**整列**（不是 16×16×16 section）：
  - `blocks`：扁平数组，索引 `y * 256 + localZ * 16 + localX`
  - `skyLight` / `blockLight`：与 blocks 同形的稀疏数组（0 存 nil），值 0~15
  - `blockState`：门/楼梯/半砖的朝向、上下半、开关
  - `minY/maxY`：非空气方块的高度范围（网格构建优化）
- `World:getBlock(x,y,z)` 越界或无数据返回 `AIR`。
- `World:setBlock(x,y,z,type,state)`：玩家编辑入口，负责写方块、状态、光照增量、脏区块标记；`setBlockRaw` 只写数据，不更新光照/网格。
- `World:markChunkDirty` 与 `ChunkMeshBuilder` 配合；一个方块变化可能让相邻区块变脏。
- 光照：
  - 天空光按列向下灌注，水平 BFS 传播；
  - 方块光从 `hasLight` 方块（火把/萤石/岩浆/火焰石）BFS 衰减；
  - 性能注意：方块光只允许在**已生成数据的区块**间传播，否则会灌满未生成区域（曾经是加载卡顿的根因）。
- 方块形状：`data/BlockShapes.lua` 用 AABB 盒子描述半砖、楼梯、栅栏、墙、门、活板门；`World:getShapeBoxes` / `getSurfaceTopY` / `isSolidAtPoint` 供碰撞与相机使用。

### 4.2 地形生成（WorldGenerator）

- 种子：`Config.Noise.SEED = 12345`。
- 群系：`PLAINS=2 / FOREST=3 / DESERT=4 / MOUNTAINS=5`（`terrain/BiomeGenerator.lua`）。
- 世界：`CHUNK_SIZE=16`，`WORLD_HEIGHT=80`，`WATER_LEVEL=37`，`RENDER_DISTANCE=6`。
- 已实现的地质特征（`Features.RICH_TERRAIN=true`）：基岩地板、按深度分布的矿脉、砂砾团、黏土、高山雪线、深层岩浆池。
- **矿石生成（Design.md「矿石」）**：`WorldGenerator` 里的 `GEO_FEATURES` 是矿石配置的唯一真源，含 10 种矿石（煤/铁/金/青金/红石/钻石 + 新增铜/绿宝石/金刚岩矿/火焰石矿）。每条矿脉用「空间格哈希 + 确定性随机游走」生成（同种子必复现、天然跨区块连贯、只替换石头）。参数：`minY/maxY`（高度范围）、`peakY`（三角分布峰值，缺省均匀）、`chance`（峰值概率）、`sizeMin/sizeMax`（矿脉大小）、`biomes`（群系限制，绿宝石/火焰石只出山地）。
- `Features.GENERATE_TREES / GENERATE_VEGETATION / SPAWN_HOUSE` 目前为 **false**（装饰器存在但默认关闭）。
- 生成顺序：地形 → 水 → 矿脉/地质特征 → 天光灌注 → 光源方块补 blockLight。

### 4.3 无限地形流式加载（ChunkStreamer）

- 以玩家所在区块为中心，按 `RENDER_DISTANCE` 扫描需要的数据；玩家移动时重扫。
- **地形生成按时间预算**：每帧最多 `GEN_BUDGET_MS=3ms`；初始加载 `INITIAL_RADIUS=3` 区块、`INITIAL_CHUNKS_PER_FRAME=3`。
- **网格构建异步**：区块标记脏 → `ChunkMeshBuilder` 每帧最多 `BUILD_BUDGET_MS=4ms`，最多 `BUILD_MAX_INFLIGHT=4` 个区块同时在管线中；构建按 Y 行切片，避免单帧长时间阻塞。
- 超出渲染距离 `UNLOAD_PADDING=2` 的区块卸载网格；**方块数据保留**，回程只重建网格。
- 网格构建完成回调 `onChunkLoaded(cx,cz)`：Standalone 用它触发「新区块原生动物生成」。

### 4.4 纹理与图集

- `AtlasLayout.ROWS` 是 tile 名称 → `{row,col}` 的**唯一真源**；两个材质包都按 `AtlasLayout.order` 生成。
- Classic：256×256，16px/tile，`FILTER_NEAREST`；HD：512×512，32px/tile，PBR（diffuse/normal/specular）。
- 新增方块纹理需要三步：
  1. `AtlasLayout.ROWS` 加 tile 名（注意每行最多 16 个）
  2. `ClassicPack.tileGenerators` 与 `HDPack.tileGenerators` 各加生成器
  3. `BlockRegistry:register` 引用 `T.<tile>`

### 4.5 方块注册表与关键 ID

`scripts/data/BlockRegistry.lua` 数据驱动注册。当前 ID：

| 区段 | ID | 说明 |
|---|---|---|
| 空气/自然 | 0–12 | 空气、草、土、石、原木、树叶、沙、水、高草、火把、花 |
| 石制建材 | 13–23 | 圆石、苔石、石砖、砂岩、黑曜石、基岩、木板、砖、书架、工作台、熔炉 |
| 矿石/发光 | 24–30 | 煤/铁/金/钻石/红石/青金石矿、萤石 |
| 自然 | 31–37 | 砂砾、黏土、雪块、雪地草、冰、岩浆、仙人掌 |
| 透明/羊毛/植物 | 38–48 | 玻璃、6 色羊毛、树苗、枯木、蘑菇 |
| 半砖/楼梯 | 49–60 | 6 种材质的半砖与楼梯（循环注册） |
| 门窗栅栏 | 61–65 | 木栅栏、圆石墙、木门、铁门、活板门 |
| **建筑** | **66–67** | **火焰石（发光）、金刚岩** |
| **新增矿石** | **68–71** | **铜矿、绿宝石矿、金刚岩矿、火焰石矿** |

常用 API：

```lua
Blocks:get(id) / getByName(name)
Blocks:isSolid / isTransparent / isLiquid / isItem / isCrossMesh
Blocks:hasLight / getShape / isInteractive / isUnbreakable
Blocks:getColor(id) / getDisplayName(id) / getPlaceableBlocks()
```

> 方块 ID 已写入方块数据与物品 ID（`block:<id>`），**新增方块请顺延 ID，不要重排已有 ID**。

---

## 5. 玩家、战斗与方块交互

### 5.1 Player

关键字段/方法（`player/Player.lua`）：

- 属性：`health/maxHealth`、`baseArmor/baseAttack`、`hunger/maxHunger`、`effects`、`dead`、`attackCooldown`、`invulnTimer`
- 背包：`inventory`（`items/Inventory.lua`）、`selectedBlockIndex`（1~9）
- 相机：`cameraNode`、`camera`（眼睛高度 `HEIGHT-0.2` 方块）
- 战斗：
  - `getArmor()` = `baseArmor(10)` + 四件装备护甲加成
  - `getAttack()` = `baseAttack(100)` + 手持武器加成（剑 +200）+ 力量药水
  - `takeDamage(rawAttack)`：`damage = rawAttack / max(1, getArmor())`；非无敌/未死亡才结算；受击消耗护甲耐久
  - `attackMob(mob)`：冷却 0.4s，造成 `getAttack()` 伤害，消耗手持武器耐久
- 饥饿：每 30 秒 -1；为 0 时每 4 秒 -1 血；食物恢复
- 药水效果：`strength`（攻击加成）、`speed`（移动倍率，`PlayerController` 读取）
- 选中的物品：`getSelectedStack()`；`getSelectedBlockType()` 返回方块 ID 或 `AIR`
- `consumeSelected(n)` / `damageSelected(n)` → 快捷栏槽位

### 5.2 PlayerController

- 移动：WASD + 虚拟摇杆；速度 `SPEED=8`（乘药水倍率），飞行 `FLY_SPEED=16`。
- 碰撞：按方块形状（半砖/楼梯/栅栏/门）测点；自动上台阶（≤0.65 方块，且只在地面）。
- 跳跃/重力/飞行（F 切换）；鼠标视角需 `mouseLocked`。
- 背包打开时 `setMouseLocked(false)`，关闭恢复；移动端始终关闭鼠标视角。

### 5.3 BlockInteraction

- DDA 射线（无临时 Vector3），交互距离 `REACH_DISTANCE=10`。
- 左键：
  1. 挥臂；2. 优先尝试破坏火把（独立节点）；3. 射线找到方块；4. 基岩拒绝；
  5. 本地/联机破坏。
- 右键：
  1. 挥臂；2. 门/活板门 → 开关；3. 工作台 → 打开 3×3 合成；
  4. 手持物品不是方块 → `ItemBehaviors.use(ctx)`；
  5. 方块物品 → 放置并消耗 1。
- 工具/掉落：
  - `data/BlockHarvest.lua` 定义每类方块需要的工具（镐/斧/铲）与掉落物
  - 工具不对仍能破坏，但**不掉落**（MC 规则）
  - 破坏方块消耗工具耐久；放置/破坏后调用 `onBlockChanged`（防御塔检测）
- 门：上下两格同步破坏/开关；半砖/楼梯/活板门按玩家朝向推断放置状态。
- 回调注入（由 Standalone 设置）：`setItemSystems`、`setCraftingTableHandler`、`setBlockChangedHandler`。

### 5.4 操作键位

| 操作 | 键 |
|---|---|
| 移动 / 跳跃 | WASD / 空格 |
| 视角 | 鼠标（移动端右半屏拖动） |
| 左键 | 攻击生物 / 挖掘方块 |
| 右键 | 使用物品 / 放置方块 / 开关门 |
| 背包 | `E`（或右上角「背包」按钮） |
| 快捷栏 | `1`~`9` |
| 丢弃 | `Q`（`Shift+Q` 丢整堆） |
| 飞行模式 | `F` |
| 时间：正午/午夜/加速 | `Y` / `N` / `L` |
| 性能测试 | `B` / `P` / `O` |
| 退出 | `ESC` |

---

## 6. 生物系统

### 6.1 生物定义（当前数值）

配置在 `GameConfig.Mobs`；伤害公式仍是 `攻击力 / 目标护甲`。

| 类型 | 名称 | 敌对 | 攻击 | 护甲 | 血量 | 特点 | 生成 |
|---|---|---|---|---|---|---|---|
| ZOMBIE | 僵尸 | 是 | 100 | 10 | 100 | 近战、行走 | 夜间 |
| GHOST | 幽灵 | 是 | 50 | 10 | 50 | 近战、飞行悬浮 | 夜间 |
| BOMBER | 炸弹人 | 是 | 300 | 10 | 30 | 近战、**攻击时自爆**、行走 | 日夜 |
| ARCHER | 弓箭手 | 是 | 100 | 10 | 50 | 远程（8 格，直接结算伤害） | 日夜 |
| COW | 牛 | 否 | 0 | 10 | 100 | 漫游 | 日夜 |
| SHEEP | 羊 | 否 | 0 | 10 | 80 | 漫游 | 日夜 |
| PIG | 猪 | 否 | 0 | 10 | 50 | 漫游 | 日夜 |
| CHICKEN | 鸡 | 否 | 0 | 10 | 30 | 漫游 | 日夜 |

> 弓箭手当前是「在 8 格内直接造成 100 攻击力伤害」，没有箭矢投射物；玩家弓才有 `ProjectileManager` 箭矢。

> AI 已按 `Design.md`「AI机制」实现：`entity/ai/` 提供通用状态机（IDLE→WANDERING→CHASING→ATTACKING）、方块级 A* 寻路、视线检测与目标保持，参数集中在 `GameConfig.MobAI`。详见 §6.3、§14.1。

### 6.2 生成机制（MobManager，按 Design.md）

每 `SPAWN_INTERVAL=2.5s` 执行一次生成任务：

1. 以玩家区块为中心，收集距离 `MIN_CHUNK_DIST=2` ~ `MAX_CHUNK_DIST=4` 的**已加载**区块。
2. 随机选一个区块 → 随机生成中心坐标。
3. 环境筛选：群系（`biomes`）、地面类型（`ground`）、天空光、昼夜（`spawnTime`）。
4. 按 `weight` 加权抽选生物类型。
5. 随机群体数量 `group={min,max}`，在中心 `GROUP_RADIUS=4` 内尝试 `GROUP_ATTEMPTS=10` 个位置。
6. 每个位置独立校验：地面可站立、非水/岩浆、空间高度、距玩家 ≥ `MIN_DISTANCE=12`、群系/光照。
7. 分类上限：`monster=12`、`animal=16`；总数 `MAX_MOBS=32`。
8. 距玩家 `DESPAWN_DISTANCE=220` 自然消失。
9. 新加载区块额外执行一次「原生动物」生成（35% 概率，太远的区块跳过）。
10. 开局 `spawnInitial` 只生成中立动物（避免出生即被围殴）。

### 6.3 Mob AI 与表现（entity/ai/）

AI 由 `entity/ai/` 的通用框架驱动（参数集中在 `GameConfig.MobAI`），不针对单一生物硬编码：

- **状态机**：`IDLE`（待机）→ `WANDERING`（随机游走）→ `CHASING`（追踪）→ `ATTACKING`（攻击）。敌对生物在 IDLE/WANDERING 期间持续检测目标，发现即转入 CHASING；中立生物只在 IDLE/WANDERING 之间循环。
- **目标检测**：`DETECT_RANGE=16` 格内且视线通畅（`REQUIRE_LOS`，隔墙不发现）才锁定；目标超出 `LOSE_RANGE=24` 格、死亡，或长时间不可见/不可达（`LOSE_TIME=10s`）则放弃，避免在检测边缘来回切换。**夜晚特殊规则（Design.md「敌对生物」）：敌对生物无视距离与视线，全部锁定玩家并追踪攻击。**
- **生成权重随时间增长（Design.md「敌对生物」）**：每过一天（夜晚→天亮），敌对怪物的生成权重 ×1.1（`MobManager.dayCount` → `getSpawnWeight`）。
- **寻路**：地面生物走方块级 A*（`Pathfinding.lua`，支持绕障、登高 1 格、有限下落 ≤3 格、不穿墙不进液体）；路径按「目标移动超阈值 / 到重算间隔 / 路径走完」才重算。飞行生物（幽灵）直线追击。
- **近战攻击**：进入 `ATTACK_RANGE=1.5` 格后站定面向目标，`ATTACK_INTERVAL=1.5s` 冷却后走玩家伤害系统；远程（弓箭手）与自爆（炸弹人）沿用各自 `def.range` 与 `def.explodes`。
- **性能**：重决策（检测/状态切换/重算路径）按 `TICK_INTERVAL=0.2s` 节流，逐帧只做沿路径移动；超过 `RENDER_CULL_DISTANCE=72` 的生物跳过 AI 更新。
- 其它表现不变：朝向 = 移动方向（攻击时面向目标）、幽灵悬浮 `player.y+0.6`、每 0.25s 贴地、`MobModel` 拼装模型、`HealthBar` 朝向玩家。

### 6.4 炸弹人自爆（BOMBER）

触发：进入近战距离（`range=2` 格）且冷却结束 → 立即自爆（不是普通近战）。

`MobManager:explodeMob(mob, player)` 结算：

1. **玩家**：3D 距离 ≤ `explosionRadius(2 格) * BLOCK_SIZE` → `player:takeDamage(300)`（实际伤害 = 300 / 护甲）。
2. **其它生物**：同样半径内 → `mob:takeDamage(300)`；可炸死其他怪物。
3. **方块**：以炸弹人脚下为球心、半径 2 格，清除所有非空气、非基岩方块（`world:setBlock(...,AIR)`）。
4. **自身**：`mob:kill()`，血量归零，正常走死亡流程（掉火药）。
5. **特效**：前 8 个被炸方块生成碎块粒子 + 0.3s 橙色点光源闪光。
6. **结构同步**：`onBlocksCleared` → `TowerManager:rebuildTowers()`（炸掉基座/火焰石会让塔失效）。

> 注意：被炸方块**不产生掉落物**；自爆会伤到玩家和所有怪物（不区分阵营）。

### 6.5 死亡掉落

`GameConfig.Loot` 定义每种生物的掉落（ID + 数量范围）：

- 僵尸：腐肉；幽灵：灵质 + 线；炸弹人：火药；弓箭手：箭 + 木棍
- 牛：牛肉 + 皮革；羊：白色羊毛 + 牛肉；猪：生猪肉；鸡：生鸡肉 + 羽毛

死亡后在 `MobManager:update` 中调用 `onMobDeath`，由 `ItemDropSystem:dropMobLoot` 生成世界掉落物。

### 6.6 新增生物步骤

1. `GameConfig.Mobs` 加定义（`hostile/attack/armor/health/speed/range/spawnTime/category/weight/group/biomes/ground/color/size`）。
2. `MobManager.MOB_TYPES` 加类型键。
3. 如外形特殊：`MobModel` 的 `KINDS` 里加映射或新 builder。
4. 如需自爆/特殊行为：在 `Mob:update` 增加分支（参考 `def.explodes`）。
5. 掉落：`GameConfig.Loot` 加条目。

---

## 7. 物品系统

### 7.1 模块职责

| 模块 | 职责 |
|---|---|
| `data/ItemDefinitions.lua` | 物品定义数据（32 个非方块物品） |
| `items/ItemRegistry.lua` | 注册/校验/查询；自动生成方块物品（`block:<blockId>`） |
| `items/ItemStack.lua` | 物品实例：ID、数量、耐久、附魔、组件；堆叠规则 |
| `items/InventorySlot.lua` | 槽位（装备栏过滤） |
| `items/Inventory.lua` | 41 格背包：放入/取出/转移/护甲/武器加成/存档序列化 |
| `items/ItemBehaviors.lua` | 物品使用策略：食物/药水/护甲/桶/弓 |
| `items/ItemEntity.lua` | 世界掉落物 3D 实体（重力/悬浮/旋转） |
| `items/ItemDropSystem.lua` | 掉落、合并、拾取、生命周期、存档 |
| `items/ProjectileManager.lua` | 玩家弓箭投射物 |
| `data/CraftingRecipes.lua` | 20 条配方 |
| `items/CraftingSystem.lua` | 2×2 / 3×3 匹配、扣材料 |
| `items/ItemSaveSystem.lua` | 物品本地存档 |
| `ui/InventoryUI.lua` | 背包/装备/合成/创造页 UI 与交互 |
| `ui/Hotbar.lua` | 9 格快捷栏 HUD |

当前共 **97 个物品定义**：32 个非方块物品 + 65 个方块物品（ID 1~65 除去水/岩浆，再加 66/67）。

### 7.2 物品定义字段

```lua
id, name, icon, color, category, maxStack,
durability, behavior, description,
attackBonus, armorBonus, equipSlot,
foodHunger, foodHeal, toolType,
effect = { kind, value, duration },
blockId
```

- `behavior`：`material / food / weapon / tool / armor / block / potion / bow / bucket / water_bucket`
- 护甲：头盔 +60、胸甲 +100、护腿 +30、护臂 +30
- 剑：攻击 +200，耐久 250；镐/斧/铲：耐久 250；弓：耐久 384
- 药水：治疗（+50 生命）、力量（+100 攻击 60s）、迅捷（+60% 速度 60s）

### 7.3 ItemStack 与堆叠

- 同一物品 ID + 相同耐久 + 相同附魔 + 相同组件 → 才可合并。
- 不同耐久/附魔/组件的物品**不会错误合并**。
- 支持 `copy / split / mergeFrom / damage / getDurabilityFraction / serialize / deserialize`。
- 最大堆叠：一般 64；工具/武器/护甲/药水/桶按定义（多为 1 或 16）。

### 7.4 Inventory 槽位布局

| 下标 | 内容 |
|---|---|
| 1–27 | 主背包（3 行 × 9） |
| 28–36 | 快捷栏（9 格） |
| 37 | 头盔 |
| 38 | 胸甲 |
| 39 | 护腿 |
| 40 | 护臂 |
| 41 | 副手 |

- 拾取优先放快捷栏，再放主背包。
- 装备槽有过滤：只能放对应部位的护甲。
- 护甲加成/手持攻击加成在 `getArmorBonus / getHeldAttackBonus` 动态计算。

### 7.5 掉落与拾取

- 方块破坏、生物死亡、玩家 `Q` 丢弃 → `ItemDropSystem`。
- 掉落物拾取冷却 0.5s；拾取半径 3.0；同类可堆叠掉落物 1.8 内自动合并。
- 生命周期 300s（5 分钟）。
- 背包只能接收一部分时，地面保留剩余数量；背包满则留在地上。
- 掉落物是独立 3D 节点（不是 UI 图标），有重力、悬浮、旋转。

### 7.6 使用行为

| 行为 | 说明 |
|---|---|
| 食物 | 恢复饥饿值/生命；饥饿和血量都满时不吃 |
| 药水 | 治疗立即生效；力量/迅捷持续 60s |
| 护甲 | 右键直接穿上（同部位换下旧装备） |
| 桶 | 空桶右键水源装水；水桶右键空地放水 |
| 弓 | 右键发射箭，消耗背包箭矢和弓耐久；伤害 = 玩家当前攻击力 |
| 方块 | 右键放置并消耗 1（火把走 TorchDecorator） |
| 材料/武器/工具 | 右键无行为；武器左键攻击，工具决定采集掉落 |

### 7.7 耐久度

- 武器攻击：每次 -1
- 工具破坏方块：每次 -1
- 护甲受击：每件 -1
- 耐久归零：物品损坏并从槽位移除
- UI 快捷栏/背包显示耐久条（绿→黄→红）

### 7.8 合成

- 背包内 2×2；右键**工作台**打开 3×3。
- 配方支持有序（`shape` + `key`）与无序（`shapeless`）。
- 匹配前裁掉网格四周空行/空列；有序配方可放在网格任意位置。
- 每次合成每个非空格子消耗 1 个。
- 例：原木 → 4 木板；2 木板 → 4 木棍；4 木板 → 工作台；煤 + 木棍 → 4 火把；3 小麦 → 面包；铁锭 → 剑/镐/斧/铲/护甲；4 黑曜石 + 1 钻石 → 金刚岩；1 萤石 + 3 煤 → 火焰石。

### 7.9 存档

- 文件：`items_save.json`（引擎做项目 + 用户隔离）。
- 内容：41 格背包（ID/数量/耐久/附魔/组件）、选中快捷栏、饥饿值、世界掉落物。
- 每 10 秒自动保存；`Standalone.Stop()` 再保存一次。
- 启动时 `ItemSaveSystem.load`；没有存档 → 发初始装备。
- **不保存**：世界方块、防御塔结构、生物。
- 服务端模式下文件 API 被引擎禁用，`ItemSaveSystem` 会用 `IsServerMode()` 短路。

### 7.10 背包 UI

- `E` 打开/关闭；右上角「背包 (E)」按钮（移动端）。
- 左键拿起/放下整堆、右键拿一半/放单个、Shift 快速转移、光标跟随显示图标与数量。
- 悬停显示名称、描述、攻击/护甲/饥饿加成、耐久。
- 底部快捷栏高亮当前选中格；点击快捷栏格也会切换手持。
- 「合成说明 / 方块 / 物品」页签：
  - 方块页：分页的创造方块（含「建筑」页：金刚岩/火焰石）
  - 物品页：全部非方块物品
  - 点击放入光标，Shift+点击直接放入背包
- 关闭时把合成格和光标里的物品还回背包；塞不下就丢到玩家脚下。

### 7.11 初始装备（无存档时）

快捷栏：剑、铁镐、铁斧、铁铲、火把×32、苹果×8、草方块×64、泥土×64、石头×64。

主背包：弓、箭×16、铁桶、头盔、胸甲、护腿、护臂、木板×32、木棍×16、铁锭×16、**金刚岩×18、火焰石×2**。

### 7.12 新增物品 / 配方 / 行为

- **普通物品**：在 `ItemDefinitions.items` 加定义；如需新行为，在 `ItemBehaviors` 加策略并在 `use()` 分派。
- **方块物品**：不需要手写，注册方块后自动生成 `block:<id>`；需在 `ItemDefinitions.BLOCK_NAMES_ZH` 加中文名。
- **配方**：在 `CraftingRecipes.recipes` 加条目；方块物品用 `"block:<id>"`。
- **掉落**：`BlockHarvest.dropFor`（方块）/ `GameConfig.Loot`（生物）。
- **工具要求**：`BlockHarvest.REQUIRED_TOOL`。

---

## 8. 防御塔（建筑）

### 8.1 规则（Design.md）

- 基座由**金刚岩**构成；从塔顶往下第 k 层必须正好有 **3×k** 块：顶层 3、第二层 6、第三层 9……
- 每层必须是同一 y 平面上的**连通块**，且上一层每块正下方必须有金刚岩（不能悬空）。
- 塔顶攻击台 = **火焰石**，必须放在基座顶层上。
- 基座 n 层 → 攻击范围 **3n 格**（世界单位 = `3n * BLOCK_SIZE`）。
- 同一基座放多个火焰石：**只激活层数最多（范围最大）的火焰石**；同层数按坐标固定选一个。

> ⚠️ **与最新 Design.md 的差距**：`Design.md` 最新版要求「攻击间隔 2 秒 / 伤害 10 / 火焰弹速度 10 格每秒 / 独立火焰弹轨迹」，并要求「基座中间缺失一层时不能激活」。当前实现是 **500 伤害 / 1 秒间隔 / 瞬时光束**；检测从火焰石向下逐层进行，遇到缺层会**在当前层数处停止并按较短塔激活**，而不是判定整个基座不合法。其余规则（3k 块/层、3n 范围、多火焰石只激活范围最大者、动态重算）已实现。详见 §14.2。

### 8.2 结构检测（TowerManager）

- 维护已放置火焰石的集合（放置/破坏方块时更新）。
- `detectBase(fx,fy,fz)`：
  1. 火焰石下方必须是金刚岩。
  2. 第 1 层：从下方方块做 4 邻域连通块，大小必须 = 3。
  3. 第 k 层（k≥2）：上一层每块正下方必须是金刚岩（全支撑）；从这些位置做连通块，大小必须 = 3k，且所有种子在同一连通块内。
  4. 遇到缺块/数量不符 → 停止，层数 = 已通过层数。
- 同一基座用「顶层连通块坐标 + 顶层 y」做 key 分组。
- `rebuildTowers()`：重新检测所有已知火焰石 → 按基座分组 → 每组选层数最大者 → 生成激活塔、点光源。

### 8.3 攻击

- 每 `ATTACK_INTERVAL=1s`：找范围内**最近敌对生物**（3D 距离 ≤ `range * BLOCK_SIZE`）。
- 造成 **`层数 × ATTACK_PER_LAYER(100)`** 攻击力伤害（`mob:takeDamage`，按护甲结算；Design.md「防御塔」）。
- 视觉：火焰石到目标的橙色射线光束（0.18s 淡出）+ 塔顶点光源呼吸 + **半透明光罩**（`Sphere.mdl`，半径 = 攻击范围，`SHIELD_ALPHA` 调透明度）。
- 火焰石方块本身也发光（blockLight 半径 12）。
- 防御塔重建触发：
  - 玩家放置/破坏金刚岩或火焰石（`BlockInteraction` → `onBlockChanged`）
  - 炸弹人自爆清方块（`MobManager.onBlocksCleared` → `rebuildTowers`）

### 8.4 出生点预置塔

`Standalone.buildSpawnTower()` 在 `OnWorldReady` 调用：

- 在候选偏移 `(6,0), (-8,0), (0,8), (0,-8), (8,8), (-8,-8), (10,0), (-10,0)` 里选第一个满足：最高地面 > 水位 +2、坡度 ≤2、头顶高度足够（塔高 6 格）。
- 建 5 层塔：第 k 层（k=1 顶层）3×k 块金刚岩，底层 15 → 顶层 3，累计 45 块 + 火焰石；范围 15 格。
- 清空脚印（X 宽 3、Z 深 5）上方 6 格，避免树/地形卡进塔里。
- 本次实测出生塔位置 `(-7,45,0)`（火焰石，基座 5 层范围 15）。

### 8.5 建造示例

**1 层塔（范围 3 格）**

```
[火]          <- 火焰石
[金][金][金]  <- 3 块金刚岩（同 y）
```

**2 层塔（范围 6 格）**

```
      [火]
   [金][金][金]      <- 顶层 3 块
[金][金][金]         <- 底层 6 块（3×2，z 方向两排）
[金][金][金]
```

---

## 9. 昼夜、HUD 与 UI

### 9.1 昼夜循环（DayNightCycle）

- 1 游戏天 = `DAY_DURATION=480` 秒；开始时间 `6.2`；阶段 `dawn/day/dusk/night`。
- 通过切换 `LightGroup/Daytime.xml` / `Night.xml` 与太阳角度实现。
- 生物生成依赖 `GameSystems:isNight()`（僵尸/幽灵夜间）。
- 调试键：`Y` 正午、`N` 午夜、`L` 60 倍速。

### 9.2 HUD

- 左上：血条 `player_health_label/bar`、饥饿 `player_hunger_label/bar`、时间 `game_time_label`
- 中央：准星
- 右上：操作说明 + 「背包 (E)」按钮
- 底部：9 格快捷栏（选中高亮、名称、数量、耐久）
- 移动端：虚拟摇杆、视角区、跳跃/挖掘/放置按钮（`urhox-libs/UI.VirtualControls`）

### 9.3 UI 约定

- 必须 `UI.Init(...)` 一次，然后 `UI.SetRoot(root)`。
- `UI.Label` 默认 `pointerEvents="none"`；**可点击的 Label 要显式设置 `pointerEvents="auto"`**（背包页签、关闭按钮等已处理）。
- 根容器 `pointerEvents="box-none"`，全屏遮罩才用 `"auto"`。
- Yoga 默认 `flexShrink=0`；隐藏控件用 `SetVisible(false)`（不占布局）。
- 背包打开时：桌面切 `MM_ABSOLUTE` + 鼠标可见；关闭恢复 `MM_RELATIVE`。移动端不切鼠标模式。
- 游戏层点击前可用 `GameSystems:isInventoryOpen()` 屏蔽挖掘/放置/攻击。

---

## 10. 配置速查（GameConfig）

| 表 | 关键值 |
|---|---|
| `World` | CHUNK_SIZE 16、WORLD_HEIGHT 80、RENDER_DISTANCE 6、BLOCK_SIZE 2.0、WATER_LEVEL 37 |
| `Player` | 血 100、护甲 10、攻击 100、攻击范围 6、攻击冷却 0.4、重生 2s |
| `Mobs` | 见 §6.1 |
| `MobSpawning` | 间隔 2.5s、区块 2~4、最小距离 12、群半径 4、上限 monster12/animal16/总32、消失 220、索敌 20 |
| `Items` | 拾取 3.0 / 0.5s、合并 1.8、寿命 300s、存档 10s、饥饿 20（30s -1） |
| `Tower` | 攻击 500、间隔 1s、每层 3 格、3k 块/层、光束 0.18s |
| `Streaming` | 生成 3ms/帧、构建 4ms/帧、4 个并行、初始半径 3 |
| `DayNight` | 1 天 480s、开始 6.2、启用 |
| `Camera` | FOV 90、远裁剪 500、雾 50~300 |
| `Features` | 树/植被/小屋默认关闭；RICH_TERRAIN 开启 |

---

## 11. 关键约定与坑（写代码前必看）

### Lua / 引擎

- Lua 5.4：没有 `+=`/`++`；`table.unpack`；`math.atan2` 不存在，用 `math.atan(dx, dz)`。
- `Vector2/Vector3` 是**值类型**：`node.position.x = 1` 不生效，要取出、改、整体写回。
- `SetEnabled(false)` 不会影响子节点；隐藏整棵树用 `SetDeepEnabled(false)`。
- 全局 `SubscribeToEvent` 同一事件只保留最后一个处理函数；多模块每帧更新要由入口统一调用（本工程 `Standalone.HandleUpdate` 统一驱动）。
- 节点 ID 用 `node.ID`；`node.id` 不报错但为 nil。

### 资源与 UI

- 资源路径从资源根写：`Textures/x.png`、`Fonts/MiSans-Regular.ttf`、`Models/Box.mdl`。
- 纯色材质用 `Techniques/NoTexture.xml`；无光照光束用 `Techniques/NoTextureUnlit.xml`。
- UI 只使用 `urhox-libs/UI`；不要引入旧 `ui.root`/`Text()`。
- 原生 UI 的 Label 默认不接收点击；需要交互必须 `pointerEvents="auto"`。

### 世界与方块

- 玩家编辑用 `World:setBlock`（会更新光照并标记脏区块）；批量/底层写用 `setBlockRaw` 但需自己补光照与脏标记。
- 破坏方块后要通知依赖结构的系统：`BlockInteraction:notifyBlockChanged`（防御塔）。
- 新方块必须走「AtlasLayout → 两个材质包 → BlockRegistry」三步；物品会自动生成，但中文名和创造页要手动加。
- 方块 ID 不要重排；存档/物品 ID 依赖它。

### 物品与存档

- 方块物品 ID 固定为 `block:<数字>`。
- `addToRange` 找到空槽后必须**立即 return**（否则同一个 ItemStack 表会被放进所有空槽——已修复，勿回退）。
- 叠加判断必须比较耐久/附魔/组件；否则会错误合并。
- 存档只能用 `File`/`fileSystem`（`io` 已被移除）；服务端模式先 `IsServerMode()` 短路。
- 不要用 `os.execute/remove/rename`。

### 验证与调试

- 验收脚本必须放在 `scripts/` 下，`--validate-test` 参数写**相对 scripts 的路径**（如 `devtools/TowerCheck.lua`）。
- `GetDebugGameContext()`（Standalone 全局）返回 `{scene, world, player, mobManager, towerManager}`，仅供验收脚本读取。
- 本地 `preview validate` 需要预览处于 stopped；不要自动 stop 用户正在跑的会话。
- 验证报告里的 `result: FAIL` 可能只是既有资源缺失/帧尖峰；看 `test_result`、`lua_errors` 和 `test_issues`。

### 自动化 Git

- 项目配置了 Claude Code Stop Hook：`.claude/hooks/auto-commit-push.ps1`
- 每轮对话结束后自动提交并推送到 `github/dev`；`main/master` 只提交不推送；敏感文件过滤；日志在 `.git/auto-commit-hook.log`。
- `.claude/` 被 `.gitignore` 忽略，hook 文件不入库。

---

## 12. 运行与自动化验收

### 12.1 启动 / 停止

```bash
# 状态
npx -y @taptap/maker preview status --target-dir "E:/Work/Game/taptap/FristPorject" --json

# 启动本地窗口
npx -y @taptap/maker preview start --target-dir "E:/Work/Game/taptap/FristPorject" --json

# 停止
npx -y @taptap/maker preview stop --target-dir "E:/Work/Game/taptap/FristPorject"
```

启动后控制台地址通常为 `http://127.0.0.1:53215`。

### 12.2 验收命令

```bash
# 物品系统：17 条断言
npx -y @taptap/maker preview validate --mode validate \
  --target-dir "E:/Work/Game/taptap/FristPorject" \
  --validate-frames 1800 --validate-timeout 170 \
  --validate-test devtools/ItemUiCheck.lua --json

# 防御塔：12 条断言
npx -y @taptap/maker preview validate --mode both \
  --target-dir "E:/Work/Game/taptap/FristPorject" \
  --validate-frames 1900 --validate-timeout 180 \
  --validate-test devtools/TowerCheck.lua --screenshot-frame 1500 --json

# 炸弹人自爆：7 条断言
npx -y @taptap/maker preview validate --mode both \
  --target-dir "E:/Work/Game/taptap/FristPorject" \
  --validate-frames 1500 --validate-timeout 150 \
  --validate-test devtools/BomberCheck.lua --screenshot-frame 1160 --json

# 生物 AI：9 条断言
npx -y @taptap/maker preview validate --mode validate \
  --target-dir "E:/Work/Game/taptap/FristPorject" \
  --validate-frames 1600 --validate-timeout 170 \
  --validate-test devtools/MobAiCheck.lua --json
```

### 12.3 验收脚本覆盖

| 脚本 | 覆盖 |
|---|---|
| `ItemUiCheck.lua` | E 打开/关闭背包、初始装备、创造页取原木 → 2×2 合成 4 木板 → 放入背包、Q 丢弃后快捷栏清空 |
| `TowerCheck.lua` | 出生点预置塔存在、2 层塔范围 6、同基座 2 火焰石只激活 1 个、塔击杀僵尸、2 块基座不成塔、破坏顶层后失效 |
| `BomberCheck.lua` | 玩家受到自爆伤害、2 格内僵尸受伤、2 格内方块被清除、炸弹人死亡 |
| `MobAiCheck.lua` | 中立生物不追击、检测范围外僵尸不追击、检测范围内僵尸进入追击、近身僵尸攻击掉血（状态机 + 检测 + 攻击接线） |
| `OreCheck.lua` | 扫描出生点地下，常见矿石（煤/铁/铜/金刚岩）必须生成；稀有矿石只统计 |

### 12.4 已知噪音

- `Cube/Day/DaySpecularHDR.dds` / `Cube/Night/NightSpecularHDR.dds` 缺失（引擎内置天空资源，非本工程）
- 加载/大范围方块变化时偶发 >100ms 帧尖峰（报告会标 `Frame time spike`）
- `Can not load themis_x64.dll`（可选语音组件）
- 公共资源索引偶发网络失败，重试同一命令即可；不要切换 npm 版本或改用直接 Runtime 绕过

---

## 13. 快速定位表（想改什么 → 看哪里）

| 需求 | 文件 / 入口 |
|---|---|
| 调世界大小、高度、水位 | `config/GameConfig.lua` `World` / `WORLD_SIZE_PRESET` |
| 调移动/跳跃/重力 | `GameConfig.Player` + `player/PlayerController.lua` |
| 调伤害/血量/护甲 | `GameConfig.Player`、`Player:getArmor/getAttack/takeDamage` |
| 调生物数值/生成规则 | `GameConfig.Mobs` / `GameConfig.MobSpawning` |
| 改生物 AI（状态机/寻路/检测/攻击） | `entity/ai/AIController.lua`、`entity/ai/Pathfinding.lua`、`entity/ai/AIStateMachine.lua` |
| 调生物 AI 数值 | `GameConfig.MobAI` |
| 改生物朝向/飞行/剔除/贴地 | `entity/Mob.lua` |
| 改炸弹人自爆 | `GameConfig.Mobs.BOMBER` + `entity/Mob.lua` 攻击分支 + `MobManager:explodeMob` |
| 加方块 | `rendering/texturepacks/AtlasLayout.lua` → 两个 Pack → `data/BlockRegistry.lua` |
| 加物品 | `data/ItemDefinitions.lua`（方块物品自动生成） |
| 加配方 | `data/CraftingRecipes.lua` |
| 改背包/装备栏/存档 | `items/Inventory.lua`、`items/ItemSaveSystem.lua` |
| 改背包 UI/交互 | `ui/InventoryUI.lua` |
| 改快捷栏 | `ui/Hotbar.lua` |
| 改合成规则 | `items/CraftingSystem.lua` |
| 改掉落/拾取 | `items/ItemDropSystem.lua`、`data/BlockHarvest.lua`、`GameConfig.Loot` |
| 改防御塔规则/攻击 | `building/TowerManager.lua`、`GameConfig.Tower` |
| 改出生塔 | `network/Standalone.lua` `buildSpawnTower()` |
| 改 HUD/准星/按钮 | `ui/UIManager.lua` |
| 改时间/昼夜 | `world/DayNightCycle.lua`、`GameConfig.DayNight` |
| 改区块加载/卡顿 | `world/ChunkStreamer.lua`、`world/ChunkMeshBuilder.lua`、`GameConfig.Streaming` |
| 加验收脚本 | `scripts/devtools/*.lua`（用 `GetDebugGameContext()`） |

---

## 14. 当前限制 / 已知 TODO

1. **世界不持久化**：方块修改、防御塔、生物状态重启后丢失；只有物品背包/掉落物写 `items_save.json`。
2. **没有箱子/容器方块**：`Inventory` 底层可复用到容器，但当前没有箱子 UI/存档。
3. **没有熔炉/工作台外的合成设备**：3×3 只通过右键工作台打开。
4. **弓箭手是「远程直接结算伤害」**，没有箭矢飞行体；玩家的弓才有 `ProjectileManager`。
5. **炸弹人自爆**不产生方块掉落，也不会引发其它炸弹人连锁爆炸。
6. **护甲只有一套铁甲**；没有木质/石质/钻石工具分级；没有附魔/修理。
7. **食物只有饥饿值**，没有饱和度和生命恢复机制。
8. **第一人称手持模型**只对方块物品显示；非方块物品（剑/食物等）只显示手臂。
9. **多人模式未启用**：Client/Server/Shared 是脚手架；所有新玩法按 Standalone 实现。
10. **物品图标**是色块/汉字字符，不是图集切图；追求原版图标需要引入图片资源。
11. **背包面板固定 800×500**，极窄屏幕上可能偏大；UI 缩放依赖 `UI.Scale.DEFAULT`。
12. **合成「使用时间/动画」**只有挥臂，没有按物品区分的读条时间。

### 14.1 生物 AI（已实现，Design.md「AI机制」）

`entity/ai/` 已实现通用状态机 + A* 寻路 + 视线检测，`Mob:update` 委托给 `AIController`。已落地：

- 状态机 IDLE / WANDERING / CHASING / ATTACKING（`AIStateMachine`）
- 随机游走（半径 10 格、最短 3 格、间隔 2~6 秒、目标点合法性校验）
- 方块级 A*（绕障、登高 1 格、有限下落、不穿墙不进液体），路径缓存 / 按需重算
- 16 格检测 + 视线遮挡 + 目标保持/丢失
- 近战 1.5 格 / 1.5s 攻击间隔；远程与自爆沿用各自配置
- AI 重决策按 0.2s 节流，与渲染帧解耦

仍存在的取舍/限制：

1. **伤害数值沿用攻击力/护甲模型**（僵尸攻击 100/护甲 10 → 实际 10 伤害），未采用 AI 需求里的「单次 3 点」示例值（Design.md 两处互相矛盾，见下）。
2. **无空间分区**：附近实体仍遍历 `mobManager.mobs`（上限 32，暂未成瓶颈）。
3. **飞行生物（幽灵）直线追击**，不做 A*，可能穿过地形——幽灵「飞行/穿墙」表现的有意简化。
4. **生物不跳跃**，仅登高 1 格；2 格以上高台无法攀登（与 MC 僵尸行为一致）。
5. **多玩家目标选择**未实现（单机只有一个玩家，检测直接取传入的 player）。

> Design.md「AI机制」§六写「单次伤害 3 点」，§四的僵尸表写「攻击力 100 / 护甲 10」（按公式 = 10 伤害），两者冲突。实现遵循后者（沿用既有伤害系统与生物表）；如需改成 3 点，把僵尸 `attack` 调为 30 即可。

### 14.2 防御塔待实现/待对齐（Design.md 最新版）

> 已对齐（2026-11-21）：攻击力改为 **层数 × 100**（原固定 500）、增加**攻击范围半透明光罩**。
> 仍待对齐的点：

| 需求（最新 Design.md） | 当前实现 |
|---|---|
| 攻击间隔 **2 秒** | `Config.Tower.ATTACK_INTERVAL = 1.0` |
| 攻击伤害 **10**（§五 初始参数） | 攻击力 = 层数 × 100（`ATTACK_PER_LAYER`），按护甲结算；与「攻击力 100×层数」新要求一致，未单独对齐「伤害 10」 |
| 发射**独立火焰弹**（速度 10 格/秒，命中结算） | 瞬时光束（`spawnBeam`）+ 立即 `mob:takeDamage` |
| 基座中间缺一层 → **整个基座不合法、不能激活** | 自上而下检测，遇缺层会在当前层数停止，可能按较短的塔激活 |
| 模块：DefenseTowerManager / Detector / Controller / FlameStoneController / FireProjectile | 目前集中在 `building/TowerManager.lua` 一个模块 |
| 测试：1 层范围 3、3 层范围 9、缺一块、中间缺层、双火焰石、等范围稳定选择、破坏基座/激活火焰石、范围外不攻击、玩家/友好生物不被攻击、不重复攻击 | 已覆盖：2 层范围 6、双火焰石只激活 1 个、击杀范围内僵尸、2 块基座不成塔、破坏顶层失效；**未测试**：1/3 层、范围外、玩家/友好生物、破坏激活火焰石后的接管（代码上有重选逻辑，但没有验收用例）；**未满足**：中间缺层判定、火焰弹 |

可以直接修改的位置：
- 参数：`config/GameConfig.lua` `Tower`
- 结构检测/激活：`building/TowerManager.lua`（`detectBase / rebuildTowers`）
- 火焰弹：可复用/扩展 `items/ProjectileManager.lua`，或新增 `building/FireProjectile.lua`
- 测试：扩展 `devtools/TowerCheck.lua`，覆盖上表未覆盖场景

> 在实现这些新需求前，不要把本文档 §8 的 500/1s/光束描述当作最新设计；它以**当前代码**为准，最新设计以 `Design.md` 为准。

---

## 15. 最近实现记录（2026-11-21）

- 无限地形流式加载 + 光照 BFS 范围修复，解决加载/行走卡顿
- 生物多部件模型、朝向 = 移动方向、血条朝向玩家
- 完整生物生成机制（区块候选、环境筛选、权重、群体、上限、消失、新区块原生生成）
- 生物 AI：`entity/ai/` 状态机 + 方块级 A* 寻路 + 视线检测 + 目标保持，重决策与渲染帧解耦
- 完整物品系统（定义/实例/背包/掉落/使用/耐久/合成/UI/存档）
- 防御塔建筑系统 + 出生点 5 层预置塔
- 炸弹人改为 300/10/30、行走、攻击自爆（范围伤害 + 清方块 + 自爆死亡）
- 矿石系统扩展：新增铜/绿宝石/金刚岩矿/火焰石矿 4 种方块，矿石生成加高度三角分布 + 群系限制
- 敌对生物夜晚无视距离全量追踪；敌对生成权重每天 ×1.1
- 防御塔攻击力改为 层数 × 100，新增攻击范围半透明光罩
- 自动化验收：ItemUiCheck / TowerCheck / BomberCheck / MobAiCheck / OreCheck
- Git Stop Hook 自动提交/推送（github/dev）

---

*本文档由当前代码整理；如代码与文档冲突，以代码和 `Design.md` 为准，并在改动后同步更新本文件。*
