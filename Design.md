## 自动刷新周围方块，用用不会走到世界尽头，地形永远会自动生成
 区块加载：你靠近时，地形从硬盘读出来

世界是分成 16×16×16 的**区块段（section）**，一堆区段组成区块（16×256×16）。
玩家移动时，服务器持续判断哪些区块进入模拟范围：

- 不在范围内：区块休眠，**完全不运算**，庄稼不长、红石停住、水不流动
- 进入范围：从存档文件读取区块数据，加载到内存，渲染出来，同时开始接收 tick
- 离开范围：区块卸载，写入存档，停止一切模拟

> 
> 这个只是**加载已经生成好的地形**，不是动态刷新方块状态；地形生成只有第一次访问新区块的时候执行（生成洞穴、矿石、结构）。

## 添加血条
自己有血条，其他生物也有血条。
血没了之后会死亡
伤害=攻击力/护甲

## 生成生物
### 生成机制
系统以玩家为中心，在一定范围内的已加载区块中周期性执行生物生成任务。每次生成任务首先根据玩家位置筛选符合条件的区块，排除距离玩家过近或过远的区域，然后随机选择一个区块，并在区块内随机选择一个生成中心坐标。系统根据该坐标所在的生物群系、地形类型、环境光照、昼夜时间和周围环境，筛选出允许在当前位置生成的生物类型。

确定可生成的生物类型后，系统根据每种生物预设的生成权重进行加权随机抽选，权重越高，被选中的概率越大。选定生物后，系统随机确定本次生成的群体数量，并以生成中心为基准，在附近一定范围内随机寻找多个生成位置，使同类生物倾向于成群出现，而不是均匀分散在地图各处。

每个候选生成位置都必须独立进行合法性检查，包括地面是否满足生物的生成要求、空间是否足够、是否存在碰撞障碍、光照是否符合要求、生物群系是否允许生成，以及是否处于玩家禁止生成距离范围内。所有检查通过后，才正式创建生物实体；检查失败则放弃当前位置，继续尝试其他位置。

系统为不同类别的生物设置独立的数量上限，例如陆地动物、敌对怪物、水生生物等。当某一类别的现存数量达到上限时，暂停该类别的自然生成，直到数量下降后再恢复生成。同时，为每种生物设置最大群体数量、生成权重、允许生成的生物群系、光照条件和地面类型等参数，方便后续调整。

生物生成按照固定时间间隔循环执行，但每次生成都包含随机区块选择、随机坐标选择、随机生物抽选和随机群体数量。不同环境对生成结果产生不同影响，例如白天更容易生成动物，夜晚更容易生成敌对怪物，森林和草原更容易出现陆地动物，洞穴更容易出现地下怪物，水域则允许生成水生生物。

此外，系统需要处理生物的自然消失机制。当生物距离所有玩家过远、长时间未被观察或满足特定消失条件时，可以将其移除，避免世界中生物数量无限增长。

新生成的区块可以额外执行一次初始生物生成逻辑，使玩家探索新区域时能够发现原本就存在于环境中的动物。后续则通过周期性自然生成机制持续补充生物。

整个系统的核心原则是：以区块为生成单位，以玩家为生成范围参考，以环境条件决定生物种类，以权重决定随机概率，以群体机制控制分布，以数量上限控制生态规模，以自然消失机制维持世界平衡。

### AI机制
# 开发需求：实现 Minecraft 风格的生物 AI 系统

请在当前游戏项目中实现一套完整的生物 AI 系统，参考 Minecraft 的生物行为机制，重点实现普通生物随机游走，以及僵尸自动发现、追踪和攻击玩家的功能。

## 一、开发前要求

1. 首先分析当前项目架构，了解：
   - Entity / LivingEntity 实体系统
   - 生物生成和生命周期管理
   - 玩家位置及移动系统
   - 方块地图、碰撞检测和地形系统
   - 寻路系统（如果已经存在）
   - 生物动画和移动控制
   - 伤害、生命值和死亡系统

2. 尽量复用现有代码，不要重复开发已有功能。
3. 不要破坏现有生物的移动、碰撞和动画逻辑。
4. 先给出项目现状和实现方案，然后直接开始编码，不要只输出设计文档。

## 二、AI 系统整体架构

设计通用的生物 AI 框架，避免将所有 AI 逻辑直接写在 Zombie 类中。

建议包含以下模块：

- AIController：生物 AI 总控制器
- AIStateMachine：AI 状态机
- RandomWanderBehavior：随机游走行为
- TargetDetectionBehavior：目标检测
- TargetTrackingBehavior：目标追踪
- NavigationSystem：寻路和路径跟随
- MeleeAttackBehavior：近战攻击

如果项目已有类似模块，优先扩展现有模块。

## 三、普通生物随机游走

为牛、羊、猪等普通生物实现随机游走功能。

### 1. 行为规则

- 生物生成后默认处于 IDLE 状态。
- 每隔一段随机时间尝试选择新的游走目标。
- 以生物当前位置为中心，在一定范围内随机选择目标点。
- 随机目标应考虑水平距离和地形高度。
- 不允许选择无法站立、被方块阻挡或存在严重危险的目标位置。
- 如果目标位置不可达，则重新选择。
- 目标位置合法后，使用 NavigationSystem 计算移动路径。
- 生物沿路径移动，到达目标后停止。
- 等待一段随机时间，再次选择目标。
- 游走过程中应支持自然转向、移动动画和速度控制。

### 2. 建议初始参数

- 随机游走半径：10 格
- 最短游走距离：3 格
- 两次游走之间的等待时间：2～6 秒
- 普通生物移动速度：根据现有移动系统设置

以上参数应集中配置，不能散落在代码中。

## 四、僵尸自动发现玩家

僵尸应继承通用 AI 系统，并具备主动攻击玩家的能力。

### 1. 玩家检测

- 僵尸定期检测周围玩家。
- 默认检测半径：16 格。
- 检查玩家是否存活。
- 检查是否满足目标选择条件。
- 支持视线检测，避免僵尸隔着墙壁直接发现玩家（具体遵循项目现有碰撞和射线检测机制）。
- 如果存在多个玩家，默认选择距离最近的有效玩家。
- 一旦锁定目标，不要因为附近出现另一个距离相近的玩家就频繁切换目标。

### 2. 目标丢失

出现以下情况时，应放弃当前目标：

- 玩家死亡。
- 玩家离开设定的追踪范围。
- 玩家长时间无法被找到。
- 目标实体已经被销毁。

放弃目标后，僵尸恢复随机游走或待机状态。

建议设置目标保持范围，避免玩家刚好在检测半径边缘时，僵尸不断切换追踪和待机状态。

## 五、僵尸自动追踪玩家

当僵尸发现玩家后：

1. 将玩家设置为当前 Target。
2. AI 状态切换为 CHASING。
3. 获取玩家当前坐标。
4. 使用 NavigationSystem 计算到玩家的移动路径。
5. 沿路径移动，持续朝玩家靠近。
6. 玩家移动后，定期更新路径。
7. 如果路径被方块或其他障碍阻挡，尝试重新寻路。
8. 如果寻路失败，不允许直接穿过墙壁或方块。
9. 玩家进入攻击范围后，停止追踪移动并进入攻击状态。

注意：
- 玩家是动态目标，不能只在开始追踪时计算一次路径。
- 不要每帧执行 A* 寻路。
- 应当按照固定时间间隔重新计算路径，或在目标移动明显、路径被阻挡时重新计算。
- 追踪过程中需要考虑碰撞、地形高度和移动速度。

## 六、僵尸近战攻击

当玩家进入攻击范围时，僵尸切换到 ATTACKING 状态。

建议初始参数：

- 攻击距离：1.5 格
- 攻击间隔：1.5 秒
- 单次伤害：3 点

攻击逻辑：

1. 检查目标是否存在且存活。
2. 检查目标是否仍在攻击范围内。
3. 检查攻击冷却是否结束。
4. 播放攻击动画。
5. 调用项目现有伤害系统，对玩家造成伤害。
6. 重置攻击冷却。
7. 如果玩家离开攻击范围，重新进入 CHASING 状态。

不要绕过现有生命值和伤害系统直接修改玩家生命值。

## 七、AI 状态机

实现以下状态：

- IDLE：待机
- WANDERING：随机游走
- CHASING：追踪目标
- ATTACKING：攻击目标

状态转换：

- IDLE → WANDERING：随机游走条件满足。
- WANDERING → IDLE：到达目标位置。
- IDLE / WANDERING → CHASING：发现有效玩家。
- CHASING → ATTACKING：玩家进入攻击范围。
- ATTACKING → CHASING：玩家离开攻击范围。
- CHASING / ATTACKING → IDLE：目标丢失。
- 任意状态 → DEAD：生物死亡。

状态切换时必须正确清理旧状态的移动目标、路径和计时器，避免多个行为同时控制生物。

## 八、寻路系统要求

优先使用项目已有寻路系统。

如果没有，则根据当前地图结构实现适合方块世界的寻路系统。

要求：

- 支持方块地形。
- 支持绕过障碍物。
- 支持地面移动、上下台阶。
- 不允许穿墙。
- 不允许进入无法容纳生物碰撞体的空间。
- 寻路失败时应有合理的重试和放弃机制。
- 对寻路结果进行缓存或复用，减少计算开销。

如果使用 A*，需要合理设计节点、邻居搜索规则、启发式函数和路径平滑机制。

## 九、性能要求

1. 不允许每帧遍历世界中的全部生物和玩家。
2. 使用空间分区或现有实体查询系统获取附近实体。
3. AI 决策更新频率与渲染帧率分离。
4. 目标检测、路径计算和攻击检测使用合理的更新间隔。
5. 避免重复创建大量临时对象。
6. 生物死亡、卸载或销毁时，正确清理 AI 状态和引用。
7. 多个僵尸同时追踪玩家时不能出现明显性能问题。

## 十、测试要求

至少完成以下测试：

1. 普通生物生成后可以随机游走。
2. 普通生物不会进入墙壁或无法站立的位置。
3. 普通生物到达目标后能够停止并重新选择目标。
4. 僵尸在检测范围外不会主动追踪玩家。
5. 玩家进入检测范围后，僵尸能够发现并追踪。
6. 玩家移动时，僵尸能够持续更新追踪路径。
7. 障碍物能够阻挡僵尸，僵尸能够尝试绕行。
8. 玩家进入攻击范围后，僵尸能够发动攻击。
9. 攻击间隔生效，不会每帧造成伤害。
10. 玩家离开攻击范围后，僵尸继续追踪。
11. 玩家死亡或目标丢失后，僵尸能够恢复正常行为。
12. 多个僵尸能够同时追踪同一个玩家。
13. 生物死亡或销毁后，不会遗留 AI 更新任务。

## 十一、开发交付要求

完成后请：

1. 列出新增和修改的文件。
2. 解释各 AI 模块的职责。
3. 说明 AI 状态转换逻辑。
4. 说明寻路算法和目标检测机制。
5. 列出可以调整的 AI 参数。
6. 编译项目并修复本次改动引入的错误。
7. 运行现有测试，并补充必要的 AI 测试。

特别注意：不要只实现一个简单的直线追踪功能。需要实现真正的目标检测、路径规划、动态追踪、碰撞避障和攻击状态切换。

最终目标是让普通生物表现出类似 Minecraft 的自然随机游走，让僵尸能够像 Minecraft 一样主动发现玩家、绕过障碍物追踪玩家，并在接近玩家时发动攻击。
### 敌对生物：会对主动攻击玩家，会对玩家造成伤害，在晚上敌对生物会直接全部追踪并攻击玩家，不管距离多远。生成权重每天为前一天的1.1倍
僵尸
攻击力：100
护甲：10
血量：100
特点：近战攻击
行动：行走
生成时间：夜间随机生成

幽灵
攻击力：50
护甲：10
血量：50
特点：近战攻击
行动：飞行
生成时间：夜间随机生成

炸弹人
攻击力：300
护甲：10
血量：30
特点：近战攻击,攻击时会爆炸，将周围2格内所有生物造成伤害，2格的的方块清楚掉，同时自己也会被炸死
行动：行走
生成时间：日夜随机生成

弓箭手
攻击力：100
护甲：10
血量：50
特点：远程攻击，攻击范围8格
行动：行走
生成时间：日夜随机生成

### 中立生物，不会主动攻击玩家
牛
护甲：10
血量：100
生成时间：日夜随机生成

羊
护甲：10
血量：80
生成时间：日夜随机生成

猪
护甲：10
血量：50
生成时间：日夜随机生成

鸡
护甲：10
血量：30
生成时间：日夜随机生成

## 物品
### 物品实现机制
请参考 Minecraft Java 版生存模式的物品系统，为当前游戏项目设计并实现一套完整的物品系统。

目标是尽可能复刻 Minecraft 的物品机制，包括物品定义、物品实例、背包、快捷栏、物品堆叠、拾取、掉落、使用、耐久度和存档。

一、开发前的要求

1. 首先分析当前项目的整体架构、使用的游戏引擎、编程语言和现有代码。
2. 检查是否已经存在背包、物品、角色、方块、交互和存档系统。
3. 优先复用现有架构，不要重复创建功能相同的模块。
4. 不要破坏现有游戏功能。
5. 将物品系统设计成独立、可扩展的模块。

二、物品定义系统（Item Registry）

建立统一的物品注册表。

每种物品具有以下属性：
- 唯一物品 ID
- 显示名称
- 物品图标
- 物品分类
- 最大堆叠数量
- 是否具有耐久度
- 最大耐久度
- 是否可以使用
- 对应的物品行为
- 物品描述

物品定义采用数据驱动方式管理，尽量使用 JSON 或项目适合的数据配置格式，不要将所有物品硬编码在业务逻辑中。

三、物品实例系统（ItemStack）

物品实例至少包含：
- Item ID
- 当前数量
- 当前耐久度
- 附魔数据
- 自定义组件数据

同一种物品可以存在多个 ItemStack。

实现完整的堆叠判断机制：
1. 检查物品 ID 是否相同。
2. 检查影响堆叠的实例数据是否相同。
3. 检查物品最大堆叠数量。
4. 计算剩余堆叠空间。
5. 自动拆分和合并物品。
6. 耐久度、附魔或其他关键数据不同的物品不能错误合并。

四、背包系统（Inventory）

参考 Minecraft Java 版生存模式背包结构：

- 主背包：27 格。
- 快捷栏：9 格。
- 装备栏：头盔、胸甲、护腿、靴子。
- 副手栏：1 格。

实现：
1. 物品放入和取出。
2. 物品拖拽。
3. 左键拿起和放置。
4. 右键拿起一半和放置单个物品。
5. Shift 快速转移。
6. 物品堆叠和拆分。
7. 快捷栏数字键 1～9 切换。
8. Q 键丢弃物品。
9. 背包满时正确处理无法拾取的物品。
10. 支持后续扩展箱子等容器。

五、物品掉落与拾取（Item Entity）

地面物品必须作为独立实体存在，而不是简单显示一个 UI 图标。

实现：
1. 物品掉落到世界中。
2. 掉落物受到重力和碰撞影响。
3. 掉落物具有旋转和悬浮动画。
4. 玩家进入拾取范围后自动拾取。
5. 掉落物具有拾取冷却时间。
6. 相同且可堆叠的掉落物可以合并。
7. 背包只能接收部分物品时，更新地面剩余数量。
8. 普通掉落物具有生命周期，默认参考 Minecraft 的 5 分钟。
9. 支持方块破坏、生物死亡和玩家主动丢弃产生物品。

六、物品使用系统（Item Behavior）

不同类型的物品使用不同的行为逻辑。

至少支持：
- 普通材料
- 食物
- 武器
- 工具
- 方块物品
- 药水
- 弓箭
- 桶类物品

实现对应行为：
1. 食物可以食用并恢复饥饿值。
2. 武器可以攻击生物。
3. 工具可以挖掘对应方块。
4. 方块物品可以放置到世界中。
5. 药水可以产生状态效果。
6. 桶可以与水等流体交互。
7. 可消耗物品使用后扣除数量。
8. 不同物品可以有不同使用动画和使用时间。

物品使用逻辑与物品 UI 分离，采用可扩展的行为接口或策略模式。

七、耐久度系统（Durability）

1. 支持工具和武器耐久度。
2. 不同物品具有不同最大耐久度。
3. 使用物品时按照规则扣除耐久。
4. 支持耐久度显示。
5. 耐久度为零时触发损坏逻辑。
6. 为后续附魔、耐久保护和修理系统预留接口。

八、合成系统（Crafting）

参考 Minecraft 合成机制：

1. 支持合成配方。
2. 支持 2×2 和 3×3 合成网格。
3. 根据材料组合匹配配方。
4. 正确扣除材料数量。
5. 生成合成结果。
6. 支持配方数据配置。
7. 支持后续增加熔炉、工作台等合成设备。

九、存档系统（Persistence）

实现物品数据持久化：
1. 保存玩家背包。
2. 保存快捷栏。
3. 保存装备栏和副手栏。
4. 保存物品数量、耐久度、附魔和自定义数据。
5. 保存箱子等容器中的物品。
6. 保存世界中尚未消失的掉落物。
7. 游戏重新加载后恢复原有数据。
8. 避免重复拾取、重复保存和物品丢失。

十、UI 显示

物品界面参考 Minecraft 原版风格：
- 每个格子显示物品图标。
- 右下角显示物品数量。
- 有耐久度的物品显示耐久条。
- 鼠标悬停显示物品名称和描述。
- 快捷栏显示当前选中的物品。
- 拖拽物品时显示对应图标和数量。
- 背包界面和游戏世界中的物品逻辑保持独立。

十一、代码架构要求

尽可能将系统拆分成以下模块：

ItemRegistry
ItemDefinition
ItemStack
Inventory
InventorySlot
ItemBehavior
ItemEntity
ItemPickupSystem
ItemDropSystem
ItemDurabilitySystem
CraftingSystem
ItemSaveSystem
InventoryUI

具体模块名称可以根据当前项目的代码规范调整。

十二、开发和测试要求

1. 先完成基础物品定义和 ItemStack。
2. 再完成背包和堆叠。
3. 再完成掉落和拾取。
4. 再完成物品使用和耐久度。
5. 最后完成合成、UI 和存档。
6. 每个阶段都进行编译和测试。
7. 不要只创建空类或接口，必须实现实际功能。
8. 不要使用大量临时模拟数据代替真实功能。
9. 对关键逻辑增加必要的错误处理。
10. 每个阶段完成后汇报修改的文件、实现的功能和测试结果。

最终目标：实现一套可以真正运行的 Minecraft 风格物品系统，具有完整的物品生命周期，从物品产生、掉落、拾取、存储、堆叠、使用、消耗到存档恢复，整个流程能够正常工作。

请先分析当前项目，然后制定实施计划并直接开始开发。不要只给我架构说明或示例代码。

### 物品内容
头盔
效果：+60护甲
胸甲
效果：+100护甲
护腿
效果：+30护甲
护臂
效果：+30护甲

剑
效果：+200攻击力

#### 矿石
# 开发需求：实现 Minecraft 风格的地下矿石随机生成系统

请在当前游戏项目中实现一套完整的矿石随机生成系统，参考 Minecraft 的矿石生成机制。

核心目标：在世界生成过程中，根据世界种子、地形高度、矿石生成概率和矿脉规则，在地下自然生成不同类型的矿石。

## 一、开发前要求

首先分析当前项目：

1. 世界生成系统。
2. 地形生成算法。
3. Chunk（区块）管理系统。
4. 方块类型和方块注册系统。
5. 世界种子及随机数系统。
6. 地下地层和方块替换机制。
7. 区块加载、卸载和保存机制。

优先复用已有系统，不要重复实现区块管理和方块注册功能。

先分析项目并给出实现方案，然后直接编码、编译和测试。

## 二、矿石种类

先实现以下矿石：

| 矿石 | 主要生成区域 | 稀有程度 |
|---|---|---|
| 煤矿 | 浅层至深层地下 | 常见 |
| 铁矿 | 浅层至深层地下 | 常见 |
| 金刚岩矿 | 浅层至深层地下 | 常见 |
| 铜矿 | 浅层至中层地下 | 较常见 |
| 金矿 | 中层至深层地下 | 稀有 |
| 红石矿 | 深层地下 | 稀有 |
| 青金石矿 | 地下多个高度区域 | 稀有 |
| 钻石矿 | 深层地下 | 极稀有 |
| 绿宝石矿 | 山地地下 | 极稀有 |
| 火焰石矿 | 山地地下 | 极稀有 |
具体高度和概率应通过配置文件管理，方便后续调整。

## 三、矿石生成机制

采用矿脉（Ore Vein）生成机制。

不要把每个矿石方块都当作独立随机事件生成，而是先随机选择矿脉中心，再围绕中心生成一簇矿石。

### 1. 确定生成位置

每个 Chunk 在生成阶段，根据世界种子计算独立随机数。

随机选择矿脉中心坐标：

- X：当前 Chunk 的水平范围。
- Z：当前 Chunk 的水平范围。
- Y：根据矿石对应的高度分布随机选择。

不同矿石具有不同的生成高度范围。

例如：

- 煤矿：Y = 0～200
- 铁矿：Y = -32～128
- 铜矿：Y = -16～112
- 金矿：Y = -64～32
- 红石矿：Y = -64～16
- 青金石矿：Y = -64～64
- 钻石矿：Y = -64～16
- 绿宝石矿：优先在山地生物群系生成

以上为示例配置，不要求完全复制 Minecraft 某个版本的实际分布。

### 2. 矿脉生成

每次生成矿脉时：

1. 随机确定矿脉中心。
2. 随机确定矿脉大小。
3. 随机确定矿脉方向。
4. 围绕中心生成多个矿石位置。
5. 对矿脉形状进行扰动，避免所有矿脉都呈规则球形。
6. 检查每个位置是否符合生成条件。
7. 符合条件时，将原有石头方块替换为对应矿石。

矿脉应该呈现不规则的团簇状，而不是整齐的方块或完美球体。

### 3. 矿脉大小

为每种矿石设置独立参数：

| 矿石 | 建议矿脉大小 |
|---|---:|
| 煤矿 | 8～17 |
| 铁矿 | 4～9 |
| 金刚岩矿 | 4～9 |
| 铜矿 | 6～12 |
| 金矿 | 2～5 |
| 红石矿 | 4～8 |
| 青金石矿 | 2～7 |
| 钻石矿 | 1～4 |
| 绿宝石矿 | 1～3 |
火焰石

矿脉大小表示一条矿脉最多尝试生成的矿石方块数量，而不是保证最终一定生成这么多方块。

## 四、矿石高度分布

不能只使用简单的固定高度范围，还要支持不同的高度概率分布。

例如：

- 煤矿：在较浅地下和较深地下都可以生成。
- 铁矿：在中低层较多，其他高度也可以生成。
- 铜矿：集中在中层。
- 金矿：主要集中在深层。
- 红石矿：越接近深层，生成概率越高。
- 钻石矿：集中在深层，极其稀少。
- 青金石：在某个中间高度附近概率最高。
- 绿宝石：受到山地生物群系影响。

建议实现统一的高度分布函数：

GetOreSpawnProbability(oreType, y, biome)

根据矿石类型、高度和生物群系返回生成权重。

可以使用三角分布、正态分布或分段概率曲线实现。

## 五、生成概率和矿脉数量

为每种矿石定义：

- MinY：最低生成高度。
- MaxY：最高生成高度。
- VeinsPerChunk：每个 Chunk 的矿脉生成尝试次数。
- MinVeinSize：最小矿脉大小。
- MaxVeinSize：最大矿脉大小。
- SpawnProbability：生成概率。
- BiomeRestriction：生物群系限制。

生成流程：

1. Chunk 完成基础地形生成。
2. 读取矿石生成配置。
3. 遍历允许生成的矿石类型。
4. 根据每种矿石的生成次数确定矿脉尝试次数。
5. 随机确定矿脉中心坐标。
6. 检查中心点高度和生物群系。
7. 计算该位置的生成概率。
8. 通过随机数判断是否生成矿脉。
9. 生成不规则矿脉。
10. 将符合条件的石头方块替换为矿石。
11. 完成 Chunk 生成并保存。

## 六、随机数与世界种子

这是非常重要的要求。

矿石生成必须具有确定性：

- 相同世界 Seed。
- 相同 Chunk 坐标。
- 相同世界生成配置。
- 相同游戏版本和生成算法。

以上条件下，生成的矿石位置必须一致。

建议采用独立的随机数生成器：

Seed + ChunkX + ChunkZ + OreType + GeneratorVersion

生成矿石专用随机种子。

不要直接使用全局随机数，否则不同 Chunk 的生成顺序可能影响矿石分布，造成相同 Seed 下生成结果不一致。

同时确保不同矿石类型的随机过程互相独立，增加或修改一种矿石时，不应无故改变其他矿石的生成结果。

## 七、区块边界处理

矿脉可能跨越 Chunk 边界。

必须避免以下问题：

- 相邻 Chunk 接缝处矿脉明显断裂。
- 同一矿脉重复生成。
- 区块加载顺序影响生成结果。
- 相邻 Chunk 生成结果不一致。

建议使用带边界缓冲的矿脉生成机制：

1. 生成矿脉时允许矿脉中心位于当前 Chunk 周围一定范围内。
2. 生成的矿石只写入当前正在生成的 Chunk。
3. 通过 Chunk 坐标和固定 Seed 保证生成一致性。
4. 必要时使用相邻 Chunk 的矿脉生成尝试，处理跨边界矿脉。

## 八、矿石替换规则

矿石只能替换符合条件的地层方块。

例如：

- 普通石头可以替换为煤矿、铁矿、金矿等。
- 深层石头可以替换为对应深层矿石。
- 不能替换空气、水、岩浆、木头和其他矿石。
- 如果项目支持不同地层，应为不同地层定义对应矿石类型。

建议实现统一接口：

CanReplaceBlock(blockType, oreType)

## 九、代码结构建议

根据现有项目架构决定最终位置，建议拆分为：

OreGenerationManager
- 管理矿石生成流程。

OreGenerationConfig
- 管理每种矿石的生成参数。

OreVeinGenerator
- 负责生成不规则矿脉。

OreDistribution
- 负责高度、生物群系和概率计算。

WorldSeedRandom
- 负责确定性随机数。

OreRegistry
- 管理矿石类型及对应方块 ID。

ChunkGenerationPipeline
- 在正确的世界生成阶段调用矿石生成。

## 十、性能要求

1. 矿石只在 Chunk 首次生成时生成，不要在每帧或每次加载时重新生成。
2. 使用确定性随机数，避免保存大量随机状态。
3. 尽量批量处理方块修改。
4. 避免重复查询 Chunk 中相同位置的方块。
5. 不要在 Chunk 已经存在玩家修改记录的情况下重新生成矿石。
6. 支持 Chunk 卸载、重新加载后保持矿石位置不变。

## 十一、测试要求

至少完成以下测试：

1. 同一 Seed 下，相同 Chunk 生成结果完全一致。
2. 不同 Seed 下，矿石分布存在差异。
3. 不同矿石在对应高度范围内生成。
4. 超出高度范围时不生成对应矿石。
5. 矿脉由多个相邻矿石组成，形状不规则。
6. 不同矿石的稀有程度符合配置。
7. 矿石不会替换空气、水和非石质方块。
8. Chunk 边界不会出现明显生成断层。
9. Chunk 卸载和重新加载不会重新生成或覆盖玩家修改。
10. 多个 Chunk 以不同顺序生成时，结果仍然一致。

## 十二、最终交付

完成后：

1. 列出新增和修改的代码文件。
2. 说明矿石生成的完整执行流程。
3. 说明世界 Seed 如何影响矿石分布。
4. 说明每种矿石的高度概率曲线。
5. 说明矿脉形状生成算法。
6. 提供矿石生成配置的修改方式。
7. 编译项目并运行相关测试。
8. 如果项目有世界可视化或调试功能，增加矿石分布调试视图，方便检查地下矿脉生成效果。

最终目标：实现一套可扩展、可配置、确定性强、具有自然矿脉形态的 Minecraft 风格矿石生成系统。





## 建筑
### 防御塔
攻击力：100*防御塔层数
攻击范围会有一个光罩提示
请在当前游戏项目中实现一个完整的自动防御塔系统。

功能参考 Minecraft 的方块建造机制，但防御塔的具体规则按照以下需求实现。

一、系统组成

防御塔由两种方块构成：

1. 金刚岩：用于搭建防御塔基座。
2. 火焰石：用于构成防御塔攻击台，能够自动攻击范围内的敌对生物。

防御塔由玩家通过放置方块的方式建造，不是直接生成一个完整的防御塔实体。

二、基座建造规则

基座必须由多层金刚岩构成。

每层金刚岩的数量必须满足：

当前层金刚岩数量 = 3 × 当前层数。

例如：
- 第一层：3 个金刚岩。
- 第二层：6 个金刚岩。
- 第三层：9 个金刚岩。
- 第四层：12 个金刚岩。
- 第五层：15 个金刚岩。

累计数量分别为 3、9、18、30、45。

基座必须从下往上连续搭建，不能出现缺失的中间层。

必须检测每一层金刚岩的实际位置和结构，不能只通过统计附近金刚岩的数量判断是否合法。

基座的层数决定防御塔的攻击范围。

三、火焰石放置与激活

火焰石是防御塔的攻击部件。

实现以下规则：

1. 玩家可以在金刚岩基座顶部放置火焰石。
2. 火焰石下方必须存在符合规则的完整金刚岩基座。
3. 系统在火焰石放置后自动检测其下方基座。
4. 如果基座合法，计算基座层数和攻击范围。
5. 如果基座不合法，火焰石不能激活。
6. 一个基座允许存在多个火焰石。
7. 如果一个基座上存在多个符合激活条件的火焰石，只允许攻击范围最大的火焰石激活。
8. 其他火焰石保持休眠状态，不执行攻击。
9. 如果多个火焰石的攻击范围相同，采用固定坐标顺序选择唯一激活者，保证结果稳定。
10. 当金刚岩或火焰石被放置、破坏、移动时，重新检测受到影响的防御塔。

四、攻击范围计算

攻击范围公式：

R = 3 × n

其中 n 是基座层数。

例如：
- 1 层基座，攻击范围 3 格。
- 2 层基座，攻击范围 6 格。
- 3 层基座，攻击范围 9 格。
- 4 层基座，攻击范围 12 格。
- 5 层基座，攻击范围 15 格。

以激活火焰石的位置作为攻击中心。

使用三维空间距离判断敌对生物是否处于攻击范围内，不能只判断 X、Z 平面距离。

五、自动攻击机制

激活的火焰石需要自动攻击范围内的敌对生物。

实现以下流程：

1. 按固定时间间隔扫描攻击范围内的生物。
2. 只检测敌对生物，忽略玩家、中立生物和友好生物。
3. 发现多个目标时，优先攻击距离最近的敌对生物。
4. 锁定目标后朝目标方向发射火焰弹。
5. 火焰弹具有独立的运动轨迹。
6. 火焰弹命中敌对生物后造成伤害。
7. 目标死亡、离开攻击范围或失效时，重新选择目标。
8. 如果范围内没有敌对生物，火焰石保持待机状态。
9. 只有当前激活的火焰石可以攻击，休眠火焰石不能产生任何攻击行为。

初始攻击参数：
- 攻击间隔：2 秒。
- 攻击伤害：10。
- 火焰弹速度：10 格/秒。
- 攻击范围：基座层数 × 3。
- 同一时间只攻击一个目标。

这些参数需要集中配置，方便后续调整。

六、动态结构检测

这是非常重要的功能。

玩家可能在防御塔建成后继续修改结构，因此必须支持动态更新。

以下情况发生时，重新计算防御塔状态：

- 放置金刚岩。
- 破坏金刚岩。
- 放置火焰石。
- 破坏火焰石。
- 火焰石或金刚岩被其他系统移动。

如果基座不再满足规则：
- 防御塔失效。
- 火焰石停止攻击。
- 清除不再合法的激活状态。

如果基座重新满足规则：
- 自动重新检测。
- 重新计算攻击范围。
- 重新选择唯一激活的火焰石。

七、代码架构

请将防御塔系统设计成独立模块，尽量包含：

DefenseTowerManager：
管理所有防御塔及其状态。

DefenseTowerDetector：
检测金刚岩基座结构是否合法。

DefenseTowerController：
管理防御塔激活状态和火焰石选择。

FlameStoneController：
控制火焰石待机、瞄准和攻击。

FireProjectile：
管理火焰弹的运动和碰撞。

DefenseTowerConfig：
集中管理攻击间隔、伤害、攻击范围等参数。

具体类名可以按照当前项目架构调整。

八、性能要求

1. 不要每帧遍历整个世界寻找防御塔。
2. 优先采用方块变化事件触发结构重新检测。
3. 攻击扫描使用定时器，不要每帧执行。
4. 对附近敌对生物进行空间范围筛选。
5. 避免同一基座重复创建多个防御塔管理实例。
6. 防御塔失效或销毁后，正确清理相关引用和攻击任务。

九、测试要求

至少测试以下场景：

1. 正确搭建一层基座并放置火焰石，验证范围为 3 格。
2. 正确搭建三层基座并放置火焰石，验证范围为 9 格。
3. 缺少一块金刚岩时，防御塔不能激活。
4. 基座中间缺失一层时，防御塔不能激活。
5. 同一个基座放置两个火焰石时，只激活攻击范围最大的一个。
6. 两个火焰石攻击范围相同时，能够稳定选择一个。
7. 破坏金刚岩后，防御塔能够自动失效或重新计算。
8. 破坏激活火焰石后，其他合法火焰石能够接管。
9. 范围内有敌对生物时，能够正常发射火焰弹。
10. 范围外的敌对生物不会受到攻击。
11. 玩家和友好生物不会成为攻击目标。
12. 同一个基座不会出现多个火焰石同时攻击的情况。

十、开发要求

首先检查现有项目中的方块放置、方块破坏、生物管理、实体碰撞和伤害系统。

优先复用现有系统，不要重复开发已有功能。

先给出实现方案，然后直接修改项目代码，完成编译和测试。

不要只提供伪代码或空接口，必须实现可以在游戏中实际运行的功能。

---

# 附：Minecraft 未实现功能（本轮新增需求，待开发）

> **实现进度（2026-11-22）**：已实现 **天气（晴/雨/雷雨/雪）**、**饥饿与饱和度**、**经验与等级**、**日夜渐变**、**动物繁殖**；
> 矿石生成已确认有效（`devtools/OreCheck.lua`）。
> 仍待开发：熔炉烧炼、箱子容器、附魔、农业种植、钓鱼、红石。详见 `ARCHITECTURE.md` §14.3。

> 以下功能是「我的世界」里有、但当前工程尚未实现的内容。实现逻辑全部按现有代码约定书写：
> 方块 ID 从 **72** 顺延（0–71 已占用，禁止重排）；方块物品自动生成 `block:<id>`；物品 ID 用字符串；
> 配置集中到 `config/GameConfig.lua`；方块实体数据用「坐标 → 数据」的旁路表（参照 `building/TowerManager.lua`），
> 因为 `World` 只存方块/光照/状态，不存方块实体（箱子内容、熔炉进度等）。
>
> 这些系统都接入 `Standalone.HandleUpdate`（单机主循环）与 `OnWorldReady`（初始化），不碰多人脚手架。

## 一、熔炉与烧炼系统（Furnace & Smelting）

**现状缺口**：`FURNACE`（方块 ID 23）已注册且有贴图，但右键无行为；矿石（煤/铁/金/钻石/红石/青金石/铜/绿宝石）只能当方块挖走，无法烧成锭/宝石；生肉无法烤熟。这是当前物品链最大的断点（铁锭、金锭只能靠初始装备和刷怪掉落获取）。

### 1.1 数据与配置

在 `GameConfig` 增加：

```lua
GameConfig.Furnace = {
    COOK_TIME = 8.0,          -- 每烧一件成品耗时（秒）
    MAX_INPUT = 64,           -- 材料槽最大堆叠（按物品自身 maxStack 为准，这里只兜底）
    MAX_FUEL  = 64,
    MAX_OUTPUT = 64,
    UPDATE_BUDGET = 16,       -- 每帧最多推进多少台熔炉的进度（性能兜底）
}

-- 燃料：物品 ID → 可烧炼的「成品件数」（1 件 = 1 个 COOK_TIME）
GameConfig.Fuel = {
    coal = 8,                 -- 煤炭 8 件
    block = { [4] = 2, [19] = 1.5, [23] = 8 },   -- 原木 2 / 木板 1.5 / 熔炉 8（简化，允许小数按比例折算燃烧时间）
    stick = 0.5,
}

-- 烧炼配方：输入物品 ID → 输出 { id, count }
GameConfig.Smelting = {
    ["block:25"] = { id = "iron_ingot",    count = 1 },  -- 铁矿石 → 铁锭
    ["block:26"] = { id = "gold_ingot",    count = 1 },  -- 金矿石 → 金锭
    ["block:68"] = { id = "copper_ingot",  count = 1 },  -- 铜矿石 → 铜锭
    ["block:27"] = { id = "diamond",       count = 1 },  -- 钻石矿石 → 钻石
    ["block:24"] = { id = "coal",          count = 1 },  -- 煤矿石 → 煤炭
    ["block:28"] = { id = "redstone",      count = 4 },  -- 红石矿石 → 红石粉
    ["block:29"] = { id = "lapis_lazuli",  count = 4 },  -- 青金石矿石 → 青金石
    ["block:69"] = { id = "emerald",       count = 1 },  -- 绿宝石矿石 → 绿宝石
    ["block:6"]  = { id = "block:38",      count = 1 },  -- 沙 → 玻璃
    ["block:13"] = { id = "block:3",       count = 1 },  -- 圆石 → 石头
    ["block:32"] = { id = "block:20",      count = 1 },  -- 黏土 → 砖块
    ["block:4"]  = { id = "charcoal",      count = 1 },  -- 原木 → 木炭
    ["beef"]        = { id = "cooked_beef",     count = 1 },  -- 生牛肉 → 熟牛肉
    ["porkchop"]    = { id = "cooked_porkchop", count = 1 },  -- 生猪肉 → 熟猪肉
    ["chicken_meat"]= { id = "cooked_chicken",  count = 1 },  -- 生鸡肉 → 熟鸡肉
    ["raw_fish"]    = { id = "cooked_fish",     count = 1 },  -- 生鱼 → 熟鱼
}
```

新增物品（`data/ItemDefinitions.lua` 追加）：`copper_ingot`（铜锭）、`emerald`（绿宝石）、`redstone`（红石粉）、`lapis_lazuli`（青金石）、`charcoal`（木炭）、`cooked_beef` / `cooked_porkchop` / `cooked_chicken` / `raw_fish` / `cooked_fish`（食物，写 `foodHunger/foodSaturation`，见「饥饿饱和度」一节）。

新增方块：`LIT_FURNACE`（燃烧态熔炉，ID 72）——为了省状态位，燃烧与否用**独立方块**表示（与门用 blockState 不同）：燃烧时把方块从 `FURNACE`(23) 换成 `LIT_FURNACE`(72)，`LIT_FURNACE` 设 `hasLight=true, lightRadius=13`，熄灭换回。`AtlasLayout.ROWS` 加 `furnace_lit_side`，两套材质包各加生成器，`BlockRegistry:register(72, "lit_furnace", {...})`。

### 1.2 模块划分

| 模块 | 职责 |
|---|---|
| `items/FurnaceManager.lua` | 方块实体注册表 + 每帧烧炼推进 + 放置/破坏时的登记/销毁 |
| `ui/FurnaceUI.lua` | 熔炉界面：3 槽（材料/燃料/成品）+ 进度条 + 火焰动画 |
| `data/SmeltingRecipes.lua`（或并入 `GameConfig.Smelting`） | 烧炼配方查询 |

### 1.3 方块实体数据结构

`FurnaceManager` 内部维护：

```lua
furnaces = {}  -- key = "x,y,z" 字符串 → {
--   input  = ItemStack|nil    材料槽
--   fuel   = ItemStack|nil    燃料槽
--   output = ItemStack|nil    成品槽
--   burnTimeLeft = 0          当前燃料还能烧的剩余秒数
--   progress = 0              当前这一件的烧炼进度（0..COOK_TIME）
-- }
```

放置 `FURNACE` 方块时 `registerFurnace(x,y,z)`；破坏时 `unregisterFurnace` 并把 3 个槽的物品作为掉落物 `ItemDropSystem:drop` 掉出。

### 1.4 核心烧炼逻辑（`FurnaceManager:update(timeStep)`）

每帧对所有**燃烧中**的熔炉推进，受 `UPDATE_BUDGET` 限制（超出则本帧留到下帧，避免大量熔炉卡帧）：

1. 若 `burnTimeLeft > 0`：`burnTimeLeft -= timeStep`；`progress += timeStep`。
2. `progress >= COOK_TIME` 时：检查 `input` 是否可烧（`GameConfig.Smelting` 有该 ID）且 `output` 能容纳（同 ID 可合并或为空槽）→ 消耗 1 个 `input`，产出 1 件 `output`；`progress -= COOK_TIME`（余量保留）。若 `input` 烧空则停止推进。
3. 若 `burnTimeLeft <= 0`：尝试从 `fuel` 槽消耗 1 个燃料，按 `GameConfig.Fuel` 换算 `burnTimeLeft += 件数 * COOK_TIME`。若 `fuel` 空，则熄火（方块换回 `FURNACE`）。
4. 燃烧态变化（刚点燃 / 刚熄灭）时：`world:setBlock(x,y,z, LIT_FURNACE or FURNACE)` 触发光照与网格更新。

### 1.5 UI 与交互

- `BlockInteraction` 右键命中 `FURNACE`/`LIT_FURNACE` → `FurnaceUI:open(coord)`（参照工作台右键打开 3×3 合成的 `setCraftingTableHandler` 注入点，在 `Standalone.OnWorldReady` 里 `blockInteraction_:setFurnaceHandler(...)`）。
- UI：三个格子（左材料、下燃料、右成品）+ 中央箭头进度条（`progress/COOK_TIME`）+ 底部燃料火焰。格子用 `InventorySlot` 复刻，鼠标左键拿整堆/右键拿一半、Shift 快转移（复用背包 UI 的槽位交互）。
- 关闭时把 UI 中悬停/合成区物品还回对应槽，塞不下则掉落玩家脚下。

### 1.6 存档

熔炉内容属于方块实体数据，随世界不持久化（与现有「世界不持久化」限制一致）。若要保存，把 `furnaces` 序列化进 `items_save.json`（键为坐标），并在读档时恢复——但**熔炉方块本身也会随世界消失**，因此推荐的做法是：存档里同时保存熔炉坐标列表，读档后用 `world:setBlock` 把 `FURNACE` 放回去再恢复内容（与箱子一节同策略，见下）。

---

## 二、箱子与容器存储系统（Chest & Container）

**现状缺口**：`Inventory` 底层可复用到容器，但没有任何箱子/容器方块（`ARCHITECTURE.md` §14.2 明确列为 TODO）。

### 2.1 数据与配置

新增方块 `CHEST`（ID 73），整格实体方块，贴图 `chest_side/chest_top`。`GameConfig.Container = { CHEST_SLOTS = 27 }`。

### 2.2 模块划分

| 模块 | 职责 |
|---|---|
| `items/ContainerManager.lua` | 箱子方块实体注册表 + 打开/关闭协调 |
| `ui/ChestUI.lua` | 箱子界面：箱子 27 格 + 玩家背包 + 快捷栏，支持拖拽/转移 |
| `items/ContainerInventory.lua` | 可选的轻量容器背包（直接复用 `Inventory.new()` 亦可） |

### 2.3 核心逻辑

1. **容器数据**：`ContainerManager.containers = { [coordKey] = { inventory = Inventory 风格 27 槽 } }`。箱子槽位无装备过滤，可直接复用 `Inventory` 的数据结构但槽位数改为 27（或写一个不带装备槽的简单容器）。
2. **放置/破坏**：放置 `CHEST` → `registerContainer`；破坏 → 内容全量掉落（`ItemDropSystem:drop`），再 `unregisterContainer`。
3. **打开**：右键箱子 → `ChestUI:open(coord)`。界面左侧箱子 27 格、右侧玩家背包（主背包 + 快捷栏）。左右互传：Shift 点击快速在箱子与玩家背包间转移整堆；左键拿起/放下、右键拿半/放单个。
4. **互斥**：单机只有一个玩家，但需保证「背包 UI 与箱子 UI 同时打开时，光标物品不串槽」。做法：箱子 UI 与背包 UI 共享同一光标槽（`ui/InventoryUI.lua` 里的 cursor stack），打开箱子时复用背包 UI 的交互组件，只是把 27 个格子绑定到箱子数据。
5. **方块变化钩子**：箱子被炸弹人自爆等清方块时，`ContainerManager` 需要监听 `onBlocksCleared`（参照 `TowerManager:rebuildTowers` 的接线）→ 掉落内容并移除容器。

### 2.4 存档

箱子内容 + 箱子坐标写入 `items_save.json`（新增字段 `containers = { [coordKey] = {inventory data} }`）。读档时：因为世界方块不持久化，需要把保存的坐标用 `world:setBlock` 重新放回 `CHEST`，再恢复内容（这是让容器跨会话可用的前提，代价是第一次补世界持久化的子集）。

---

## 三、经验值与等级系统（Experience & Levels）

**现状缺口**：玩家没有经验/等级；附魔（见下）需要一个消耗经验的成长资源。

### 3.1 数据与配置

`GameConfig.XP = { ORB_LIFETIME = 60, ORB_MAGNET_DIST = 6, ORB_MAGNET_SPEED = 8, DEATH_DROP_FRACTION = 0.5 }`。

玩家新增字段（`player/Player.lua`）：`xp`（当前等级内经验）、`level`、`xpTotal`（累计，便于死亡掉落计算）。

经验等级曲线（升到下一级所需经验，MC 近似公式）：

```
xpForLevel(level) = level >= 16 and (2.5*level*level - 40.5*level + 360)
                    or (level >= 31 and ... )
```

建议实现为查表或简单公式：`xpForNext(level) = math.floor(7 + level*1.2 + level*level*0.15)`，`addXp(n)` 累加并循环升级，满级溢出。

### 3.2 核心逻辑

1. **经验来源**：生物死亡按类型给经验（`GameConfig.MobXP`，如僵尸 5、幽灵 3、炸弹人 8、弓箭手 5、动物 1–2）。在 `MobManager.onMobDeath` 接线处：若存在唯一玩家（单机），直接 `player:addXp(xp)`；也可生成经验球实体。
2. **经验球**（可选 v1 直接结算）：小实体（复用 `ItemEntity` 的悬浮/磁吸/拾取写法），玩家靠近 `ORB_MAGNET_DIST` 内飞向玩家并加经验。为控制成本，同类经验球可合并（参照掉落物合并）。
3. **死亡惩罚**：玩家死亡时按 `xpTotal * DEATH_DROP_FRACTION` 掉落对应经验球在死亡点（可选，v1 可只扣不落球）。
4. **HUD**：`ui/UIManager.lua` 加经验条（`player_xp_bar`），`setPlayerXp(cur, next)`；升级时短暂提示（"等级提升到 Lv.X"）。

---

## 四、附魔系统（Enchanting）

**现状缺口**：物品系统预留了 `ItemStack.enchantments` 字段与「附魔数据」判断（堆叠比较时会比较附魔），但没有附魔来源，也没有任何附魔效果。

### 4.1 数据与配置

新增方块 `ENCHANTING_TABLE`（附魔台，ID 74），非整格（占半格高，参照半砖的 `shape` 或直接用整格简化）。`书架`（ID 21）已存在，可作为「提高附魔等级」的加成来源。

新增物品 `lapis_lazuli`（青金石，见烧炼一节）。

`GameConfig.Enchanting = { MAX_BOOKSHELF_RANGE = 2, BOOKSHELF_PER_LEVEL = 15, BASE_COST = 1, MAX_COST = 30, LAPIS_MAX = 3 }`。

附魔定义表（数据驱动，`data/Enchantments.lua`）：

```lua
-- name / maxLevel / 作用描述 / apply(item, level) 效果
{
  sharpness  = { max = 5, apply = 攻击力 +10*level },          -- 锋利
  protection = { max = 4, apply = 护甲 +10*level },            -- 保护
  efficiency = { max = 5, apply = 挖掘速度 / 工具耐久消耗 },    -- 效率（本游戏工具无挖掘速度，简化为降低耐久消耗概率）
  unbreaking = { max = 3, apply = 有 1/(level+1) 概率不消耗耐久 }, -- 耐久
  fire_aspect = { max = 2, apply = 攻击附加燃烧 },              -- 火焰附加（可选）
}
```

### 4.2 核心逻辑

1. **放置/破坏**：同箱子/熔炉，`EnchantingManager` 维护坐标集合；附魔台本身无内容槽，只有位置。
2. **打开界面**：右键附魔台 → `EnchantingUI`：
   - 放入一件**可附魔**物品（剑/弓/工具/护甲，即 `durability` 非空或 `attackBonus/armorBonus/toolType` 存在）到物品槽；
   - 放入 1–3 个青金石到青金石槽；
   - 展示 1–3 个随机附魔选项（每个选项 = 一个附魔名 + 等级 + 经验消耗）。
3. **随机附魔**：消耗的等级 `cost = BASE_COST + 随机0..(2*附魔台等级)`；附魔台等级 = 周围 `MAX_BOOKSHELF_RANGE` 范围内书架数 / `BOOKSHELF_PER_LEVEL`（向上取整，封顶 30 级）。附魔种类与等级从玩家可负担的候选中加权随机。
4. **执行附魔**：点击选项 → 校验玩家 `level >= cost` 且青金石足够 → `player.level -= cost`，`stack.enchantments[附魔名] = 等级`，消耗青金石，物品 `dirty`。
5. **效果接入**（关键）：
   - `Inventory:getHeldAttackBonus` / `Player:getAttack`：读取手上 `stack.enchantments.sharpness`，加 `10*level`。
   - `Inventory:getArmorBonus`：每件装备的 `protection` 加 `10*level`。
   - `Inventory:damageSlot`：`unbreaking` 概率跳过扣耐久。
   - 附魔后物品「不可与未附魔同种物品合并」——现有 `ItemStack:canMergeWith` 已比较 `enchantments`，无需改动，但要保证 `enchantments` 序列化进存档（`ItemStack:serialize/deserialize` 已含该字段）。

### 4.3 存档

附魔信息随 `ItemStack` 序列化进 `items_save.json`（已具备）；附魔台方块本身随世界不持久化。

---

## 五、农业种植系统（Farming / Crops）

**现状缺口**：`wheat`（小麦）已有「3 小麦 → 面包」合成配方，但没有获得小麦的途径（既不在掉落表、也没有种植）。MC 的「种地→收获→合成食物」循环是生存核心。

### 5.1 数据与配置

新增方块：
- `FARMLAND`（耕地，ID 75）：由锄头右键泥土/草方块得到；非整格（顶面略低于整格，参照半砖 `shape` 或整格简化）；湿度用 blockState 存（0/1，附近有水=湿润，湿润生长更快）。
- `WHEAT_CROP`（小麦作物，ID 76）：交叉网格（`crossMesh=true`，参照高草/花），生长阶段 0–7 存 blockState。

新增物品：`wheat_seed`（小麦种子）、`hoe`（锄头，`toolType="hoe"`）。

`GameConfig.Farming = { STAGES = 7, GROW_MIN = 20, GROW_MAX = 60, WATER_RANGE = 4, NEED_LIGHT = 8, MATURE_STAGE = 7 }`。

### 5.2 核心逻辑

1. **耕地**：锄头右键泥土/草方块 → `FARMLAND`；破坏耕地掉落泥土。耕地若上方被非透明方块覆盖或长时间无水，会退化为泥土（简化：仅支持手动重耕，v1 不做退化）。
2. **种植**：手持 `wheat_seed` 右键耕地 → 放置 `WHEAT_CROP`（stage=0），消耗 1 种子。
3. **生长**（随机 tick，非每帧）：`FarmingManager` 维护所有作物坐标集合（放置时加入、破坏时移除），每隔 `CROP_TICK_INTERVAL` 秒随机抽一批作物：
   - 检查上方有光照（`world:getSkyLight(x,y+1,z) >= NEED_LIGHT` 或方块光足够）；
   - 湿润（耕地 state 为湿，或 4 格内有水）→ 生长加速；
   - `stage += 1`，写回 blockState，`world:markChunkDirty`（或仅当 stage 变化导致贴图/形状变化时标脏）。
4. **收获**：破坏 `WHEAT_CROP`：
   - stage < MATURE：掉 1 个 `wheat_seed`；
   - stage == MATURE：掉 1 个 `wheat` + 1–3 个 `wheat_seed`（`data/BlockHarvest.lua` 加掉落表）。
   - 收割后耕地保留，可再次播种。
5. **生长阶段贴图**：`AtlasLayout.ROWS` 加 `wheat_stage_0..7`（可复用同一 tile 用 blockState 换 UV，但为简单按阶段建 tile）。

### 5.3 接入

`FarmingManager:update` 挂进 `Standalone.HandleUpdate`；`BlockInteraction` 右键逻辑加「锄头耕地 / 种子种植」分支（放在放置方块之前，参照门/活板门的 `interactive` 分支）。

---

## 六、动物繁殖系统（Animal Breeding）

**现状缺口**：中立动物只会漫游和掉肉，没有繁殖；MC 的「喂食→繁殖→扩充养殖」循环缺失。

### 6.1 数据与配置

`GameConfig.Breeding = { LOVE_MODE_DURATION = 5, BREED_RADIUS = 4, BABY_SCALE = 0.5, GROW_TIME = 240, BREED_COOLDOWN = 60 }`。

繁殖饲料映射（物品 ID → 生物类型列表）：

```lua
GameConfig.BreedFood = {
    wheat      = { "COW", "SHEEP" },   -- 小麦
    apple      = { "PIG" },            -- 苹果
    wheat_seed = { "CHICKEN" },        -- 小麦种子
}
```

### 6.2 核心逻辑

1. **喂食**：玩家手持饲料右键中立生物（在 `BlockInteraction` 或 `MobManager` 的右键命中生物逻辑里，新增「命中生物 → 尝试喂食」分支，优先于攻击）。生物进入「求偶态」`loveMode = true`，头顶爱心特效（粒子/UI），`loveTimer = LOVE_MODE_DURATION` 倒计时。
2. **繁殖**：两只同种、都处于求偶态、距离 ≤ `BREED_RADIUS` 的动物，周期性检查（`MobManager:update` 内，用时间节流）→ 两只各进入 `BREED_COOLDOWN` 冷却，在两者中点生成一只幼体（`MobManager:spawnMob(type, pos)`，`baby = true`）。
3. **幼体成长**：幼体 `scale = BABY_SCALE`（`MobModel` 拼装时按 `baby` 缩放），`GROW_TIME` 秒后长成成年（scale 还原为 1，不再视为幼体）。幼体不掉落物品。
4. **限制**：生物类型数量上限仍受 `MobSpawning.CATEGORY_CAPS.animal` 约束，接近上限时暂停繁殖，避免刷爆。
5. **数据**：`entity/Mob.lua` 增加 `baby`、`loveMode`、`loveTimer`、`breedCooldown` 字段；`MobManager` 增加 `tryBreed(mobA, mobB)` 与 `spawnBaby`。

### 6.3 接入

`MobManager:update` 内加繁殖检查（与生成/消失同一节流循环）；`BlockInteraction` 右键命中生物加喂食分支。

---

## 七、自然生命回复与饥饿饱和度（Hunger & Saturation）

**现状缺口**：饥饿系统只有「30 秒 -1 饥饿、饥饿归零掉血」；食物直接 `foodHeal` 回血，没有 MC 的「饱和度 + 满饥饿自然回血」机制（`ARCHITECTURE.md` §14.7 已列）。

### 7.1 数据与配置

`GameConfig.Hunger = { SATURATION_MAX = 20, REGEN_INTERVAL = 4.0, REGEN_AMOUNT = 1, REGEN_MIN_HUNGER = 17 }`。

`Player` 新增 `saturation`（饱和度，0–20），`foodSaturation` 字段加到所有食物物品定义。

### 7.2 核心逻辑

1. **进食**：`Player:eat(hunger, heal, saturation)` 三参数化：先填饥饿、再填饱和度（食物 `foodHeal` 保留为「少量即时回血」，也可改为只在饥饿满时才回血——按 MC，回血来自饱和度，建议把 `foodHeal` 语义改为 `foodSaturation` 为主，`foodHeal` 仅作急救药/金苹果类）。
2. **消耗顺序**（每 30 秒一次结算，替换现有 `hungerTimer` 逻辑）：
   - `saturation > 0` → `saturation -= 1`；
   - 否则 `hunger > 0` → `hunger -= 1`；
   - 否则 `starveTimer` 累积 → 每 4 秒掉 1 血（现有逻辑保留）。
3. **自然回血**：当 `hunger >= REGEN_MIN_HUNGER`（17）且 `saturation > 0` 且 `health < maxHealth` 时，每 `REGEN_INTERVAL` 秒 `health += REGEN_AMOUNT`，同时 `saturation -= 1`。饥饿/饱和度不足则停止回血。
4. **HUD**：饥饿条仍显示 `hunger/maxHunger`；饱和度用饥饿条上的「鸡腿光泽/高亮」表示（`ui/UIManager.lua` 可选），v1 可只在数值上体现。

### 7.3 接入

改造 `Player:update` 里的饥饿结算分支与 `ItemBehaviors.useFood`（读取 `foodSaturation` 传入 `eat`）；食物定义补 `foodSaturation`（苹果 4、面包 6、熟肉更高、生肉较低等）。

---

## 八、天气系统（Weather：晴 / 雨 / 雷雨 / 雪）

**现状缺口**：世界只有昼夜，没有天气；MC 的雨/雪/雷暴影响光照、氛围与战斗。

### 8.1 数据与配置

`GameConfig.Weather = { ENABLED = true, CLEAR_MIN = 240, CLEAR_MAX = 600, RAIN_MIN = 120, RAIN_MAX = 360, THUNDER_CHANCE = 0.25, LIGHTNING_INTERVAL_MIN = 15, LIGHTNING_INTERVAL_MAX = 60 }`。

### 8.2 模块划分

`world/WeatherManager.lua`：天气状态机 + 随机切换 + 降水粒子/音效 + 雷电。

### 8.3 核心逻辑

1. **状态机**：`CLEAR → RAIN(含雷雨) → CLEAR` 随机循环。`isRaining / isThunder / isSnowing(基于群系)`。
2. **降水**：`RAIN` 时，玩家周围生成下落粒子（复用/扩展 `rendering/ParticleSystem.lua`，或雨用独立粒子层），降低天空光照（`world` 光照系统加一个全局 `weatherLightPenalty`，或在渲染层压暗）。`MOUNTAINS`（雪线以上）落雪而非雨。
3. **雷雨**：`isThunder` 时每隔随机间隔在玩家附近（或随机已加载区块）生成一次闪电：闪光点光源（参照炸弹人自爆的 `spawnExplosionEffect` 写法）+ 雷声（`engine-docs/api/audio.md`）。闪电命中生物 → 造成伤害（`mob:takeDamage(大量攻击力)`）；命中可燃物可选点火（v1 仅伤害 + 闪光）。
4. **影响**：下雨时露天怪物在白天也可生成（可选，MC 规则）；下雨让天空变暗（视觉氛围）。
5. **接入**：`WeatherManager:update(timeStep)` 挂进 `HandleUpdate`；`GameSystems:isNight()` 之外新增 `WeatherManager:isRaining()` 供生物生成/生长判断使用。

---

## 九、钓鱼系统（Fishing）

**现状缺口**：没有钓鱼竿、没有鱼、也没有钓鱼行为；水目前只能装桶，不能钓鱼。

### 9.1 数据与配置

新增物品：`fishing_rod`（钓鱼竿，`behavior="fishing_rod"`，耐久 64）、`raw_fish`（生鱼）、`cooked_fish`（熟鱼，见烧炼）。

`GameConfig.Fishing = { CAST_REQUIRES_WATER = true, BITE_MIN = 5, BITE_MAX = 15, REEL_WINDOW = 2.0, ROD_DURABILITY_COST = 1, BOB_DISTANCE = 6 }`。

### 9.2 核心逻辑

1. **抛竿**：手持钓鱼竿右键水面（`BlockInteraction` 射线命中 `WATER` 或水面）→ 生成浮漂实体（`FishingBobber`，小节点 + 悬浮/下沉动画，参照 `ItemEntity` 的节点管理）。
2. **等待咬钩**：浮漂入水后 `BITE_MIN..BITE_MAX` 秒随机咬钩，浮漂下坠（视觉 + 音效），进入 `REEL_WINDOW` 秒的可收杆窗口。
3. **收杆**：窗口内右键再次使用钓鱼竿 → 结算钓获（从 `GameConfig.FishingLoot` 加权抽 1 件），生成掉落物（或直接进背包），消耗鱼竿耐久；窗口错过则浮漂消失、无收获。
4. **钓获表**：`GameConfig.FishingLoot = { {id="raw_fish", weight=50}, {id="stick", weight=10}, {id="leather", weight=5}, ... 稀有宝藏 }`。
5. **接入**：`ItemBehaviors` 加 `fishing_rod` 策略；`FishingManager:update` 挂 `HandleUpdate`；`ProjectileManager` 之外的独立小系统，或复用其投射物框架。

---

## 十、红石系统（Redstone，简化版）

**现状缺口**：`Design.md` 开头提到「红石停住」作为区块模拟的类比，但没有任何红石方块或信号逻辑；`redstone_ore` 挖掉也只会掉矿石方块，没有「红石粉」概念。MC 的「拉杆→红石线→灯/门」是标志性玩法。

### 10.1 数据与配置

新增方块（顺延 ID）：

| ID | 方块 | 说明 |
|---|---|---|
| 77 | `redstone_dust` | 红石粉（平铺，非整格，信号强度 0–15 存 blockState） |
| 78 | `redstone_torch` | 红石火把（非整格 `isItem` 或 `crossMesh`，反向输出） |
| 79 | `redstone_block` | 红石块（恒为强信号源，无状态） |
| 80 | `lever` | 拉杆（开关输入，blockState 存 on/off + facing） |
| 81 | `stone_button` | 石按钮（脉冲输入，按下短暂激活后复位） |
| 82 | `redstone_lamp` | 红石灯（受信号点亮，`hasLight=true`，亮/灭用 blockState） |

新增物品 `redstone`（红石粉，材料，`block:77` 由方块物品自动生成；同时红石粉也是烧炼产物，见烧炼一节）。

`GameConfig.Redstone = { MAX_SIGNAL = 15, UPDATE_BUDGET = 64, BUTTON_PULSE = 1.0 }`。

### 10.2 核心逻辑（简化信号传播）

1. **信号源**：拉杆（持续 on/off）、按钮（按下 1 秒后复位）、红石块（恒 15）、红石火把（自身 on，被输入时 off → 反向）。
2. **传播**：红石粉向 4 邻（水平）传播，每格衰减 1（信号 15 → 0）；可上/下一格连通（简化：仅支持同层 4 邻 + 向上/下 1 格台阶，参照 A* 的 STEP_HEIGHT 思路）。遇不透明方块阻断；穿过红石粉继续衰减。
3. **更新方式**：**事件驱动 + BFS**，不是每帧全图扫描。放置/破坏拉杆、按钮、红石粉、红石火把、红石块时，触发 `RedstoneManager:recomputeFrom(x,y,z)`：BFS 计算受影响区域每格信号强度，写入 `world:setBlockState`（存信号值），并更新输出方块（灯亮/灭、门/活板门开关）。受 `UPDATE_BUDGET` 限制，超出分帧处理。
4. **输出**：
   - `redstone_lamp`：信号 ≥ 1 时亮（blockState `lit=1`，`world:setBlockLight` 注入光源），0 时灭。
   - 门/活板门：信号变化时切换 `open` 状态（复用现有 `interactive` 开关逻辑）。
5. **红石火把**：默认点亮（作为 15 级信号源）；若其所在方块被红石信号充能 → 熄灭（反向）。熄灭/点亮同样触发重算。
6. **性能**：只在方块变化时重算，且 BFS 限制在「已加载区块」内（参照光照 BFS 的「只在已生成区块间传播」教训）。

### 10.3 接入

`BlockInteraction` 放置/破坏方块后，若方块是红石类 → 调 `RedstoneManager:onBlockChanged`（与 `TowerManager:onBlockChanged` 同一条 `setBlockChangedHandler` 链）。`RedstoneManager:update` 处理按钮复位等定时器。

---

## 十一、统一接入清单（Standalone 接线）

在 `network/Standalone.lua` 的 `OnWorldReady` 中新增：

```lua
-- 方块实体与玩法系统
furnaceManager_   = FurnaceManager.new(scene_, world_)    -- 熔炉
containerManager_ = ContainerManager.new(scene_, world_)  -- 箱子
enchantingManager_= EnchantingManager.new(scene_, world_) -- 附魔台
farmingManager_   = FarmingManager.new(world_)            -- 农业
weatherManager_   = WeatherManager.new(scene_, world_)    -- 天气
fishingManager_   = FishingManager.new(scene_, world_)    -- 钓鱼
redstoneManager_  = RedstoneManager.new(world_)           -- 红石

-- 方块变化分发：TowerManager 之后追加
blockInteraction_:setBlockChangedHandler(function(x, y, z, oldType, newType)
    if towerManager_       then towerManager_:onBlockChanged(x, y, z, oldType, newType) end
    if containerManager_   then containerManager_:onBlockChanged(x, y, z, oldType, newType) end
    if enchantingManager_  then enchantingManager_:onBlockChanged(x, y, z, oldType, newType) end
    if farmingManager_     then farmingManager_:onBlockChanged(x, y, z, oldType, newType) end
    if redstoneManager_    then redstoneManager_:onBlockChanged(x, y, z, oldType, newType) end
end)

-- 右键交互注入（工作台之外）
blockInteraction_:setFurnaceHandler(function(coord) furnaceManager_:open(coord) end)
blockInteraction_:setChestHandler(function(coord) containerManager_:open(coord) end)
blockInteraction_:setEnchantingHandler(function(coord) enchantingManager_:open(coord) end)

-- 生物死亡 → 经验（挂到 mobManager_.onMobDeath 现有函数之后）
```

在 `HandleUpdate` 中新增（按依赖顺序，放在 `TowerManager.update` 之后）：

```lua
if furnaceManager_    then furnaceManager_:update(timeStep) end
if containerManager_  then containerManager_:update(timeStep) end
if enchantingManager_ then enchantingManager_:update(timeStep) end
if farmingManager_    then farmingManager_:update(timeStep) end
if weatherManager_    then weatherManager_:update(timeStep) end
if fishingManager_    then fishingManager_:update(timeStep) end
if redstoneManager_   then redstoneManager_:update(timeStep) end
```

`Standalone.Stop()` 里对应加 `:destroy()` 与置 nil（参照 `towerManager_`）。

---

## 十二、验收要点（建议自动化脚本）

| 系统 | 关键断言 |
|---|---|
| 熔炉 | 放铁矿+煤炭 → 燃烧态方块（LIT_FURNACE）→ 8 秒后产出铁锭、消耗 1 矿 1 煤；熄火后换回 FURNACE |
| 箱子 | 放箱子 → 放入物品 → 破坏箱子掉落内容；重新打开内容一致 |
| 经验/附魔 | 击杀生物加经验；附魔台消耗等级+青金石后 `stack.enchantments` 非空；锋利剑攻击力提升 |
| 农业 | 耕地方块放置 → 种小麦 → 随机 tick 后 stage 增长 → 成熟收割掉小麦+种子 |
| 繁殖 | 喂两只牛小麦 → 求偶态 → 生成幼体 → 幼体长大后不掉落物品 |
| 饥饿 | 饥饿满 + 饱和度 > 0 时血量缓慢回升；饥饿归零仍掉血 |
| 天气 | 切换到 RAIN 后天空变暗、粒子出现；雷雨有闪电闪光 |
| 钓鱼 | 水面抛竿 → 浮漂入水 → 收杆得鱼/杂物、消耗鱼竿耐久 |
| 红石 | 放拉杆+红石线+红石灯 → 拉杆 on 灯亮、off 灯灭；红石火把被充能后熄灭 |

> 这些系统与现有代码的关键衔接点（方块 ID 顺延、物品 ID 字符串、`World:setBlock/setBlockState`、`Inventory` 复用、
> `ItemStack.enchantments`、`blockInteraction_` 回调注入、`HandleUpdate` 主循环、`ItemSaveSystem` 存档）均已按当前工程约定给出，
> 实现时无需改动既有方块 ID 与既有玩法逻辑。