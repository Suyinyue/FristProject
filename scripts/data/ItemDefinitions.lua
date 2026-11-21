-- ====================================================================
-- data/ItemDefinitions.lua
-- 物品定义数据（数据驱动，业务逻辑里不硬编码物品）
--
-- 参考 Minecraft Java 生存模式物品系统（Design.md「物品」）：
--   - 每个物品有唯一 ID / 名称 / 图标 / 分类 / 最大堆叠 / 耐久 / 行为 / 描述
--   - 方块物品自动从 BlockRegistry 生成（id = "block:<方块ID>"），
--     不需要在下面逐个复述方块清单
--
-- 字段说明：
--   id            唯一 ID（字符串，存档与配方都用它）
--   name          显示名称
--   icon          图标字符（UI 里用一个汉字/符号表示；方块物品不需要，直接用颜色）
--   color         {r, g, b} 0-1，图标底色
--   category      material / food / weapon / tool / armor / block / potion / bow / bucket
--   maxStack      最大堆叠数量
--   durability    最大耐久（nil = 无耐久）
--   behavior      使用行为（对应 items/ItemBehaviors.lua 的策略名）
--   description   物品描述
--   attackBonus   攻击力加成（拿在手上生效）
--   armorBonus    护甲加成（穿在装备栏生效）
--   equipSlot     armor 的装备位置：head / chest / legs / arms
--   foodHunger    食物恢复的饥饿值
--   foodHeal      食物恢复的血量
--   toolType      pickaxe / axe / shovel（决定能正常采集哪些方块）
--   effect        药水效果 { kind = "heal"/"strength"/"speed", value = n, duration = 秒 }
--   blockId       方块物品对应的方块 ID
-- ====================================================================

local ItemDefinitions = {}

---方块中文名（未列出的回退到 BlockRegistry 的显示名）
---@type table<integer, string>
local BLOCK_NAMES_ZH = {
    [1] = "草方块", [2] = "泥土", [3] = "石头", [4] = "原木", [5] = "树叶",
    [6] = "沙子", [8] = "高草", [9] = "火把", [10] = "玫瑰", [11] = "黄花",
    [12] = "蓝花", [13] = "圆石", [14] = "苔石", [15] = "石砖", [16] = "砂岩",
    [17] = "黑曜石", [18] = "基岩", [19] = "木板", [20] = "砖块", [21] = "书架",
    [22] = "工作台", [23] = "熔炉", [24] = "煤矿石", [25] = "铁矿石", [26] = "金矿石",
    [27] = "钻石矿石", [28] = "红石矿石", [29] = "青金石矿石", [30] = "萤石",
    [31] = "砂砾", [32] = "黏土", [33] = "雪块", [34] = "雪地草方块", [35] = "冰",
    [37] = "仙人掌", [38] = "玻璃",
    [39] = "白色羊毛", [40] = "红色羊毛", [41] = "黄色羊毛",
    [42] = "绿色羊毛", [43] = "蓝色羊毛", [44] = "黑色羊毛",
    [45] = "树苗", [46] = "枯木", [47] = "红蘑菇", [48] = "棕蘑菇",
    [61] = "木栅栏", [62] = "圆石墙", [63] = "木门", [64] = "铁门", [65] = "活板门",
}

-- 非方块物品（顺序 = 创造模式「物品」页的顺序）
---@type table[]
ItemDefinitions.items = {
    -- ==================== 材料 ====================
    { id = "stick", name = "木棍", icon = "棍", color = { 0.55, 0.38, 0.22 }, category = "material", maxStack = 64,
      behavior = "material", description = "合成工具和火把的基础材料" },
    { id = "coal", name = "煤炭", icon = "煤", color = { 0.16, 0.16, 0.18 }, category = "material", maxStack = 64,
      behavior = "material", description = "燃料，也能做火把" },
    { id = "iron_ingot", name = "铁锭", icon = "铁", color = { 0.78, 0.79, 0.82 }, category = "material", maxStack = 64,
      behavior = "material", description = "制作武器、工具和护甲" },
    { id = "gold_ingot", name = "金锭", icon = "金", color = { 0.95, 0.80, 0.25 }, category = "material", maxStack = 64,
      behavior = "material", description = "珍贵的金属" },
    { id = "diamond", name = "钻石", icon = "钻", color = { 0.25, 0.85, 0.88 }, category = "material", maxStack = 64,
      behavior = "material", description = "最坚硬的宝石" },
    { id = "leather", name = "皮革", icon = "皮", color = { 0.62, 0.42, 0.22 }, category = "material", maxStack = 64,
      behavior = "material", description = "动物皮毛，可做护甲" },
    { id = "feather", name = "羽毛", icon = "羽", color = { 0.96, 0.96, 0.90 }, category = "material", maxStack = 64,
      behavior = "material", description = "鸡的羽毛，可以做箭" },
    { id = "string", name = "线", icon = "线", color = { 0.90, 0.90, 0.85 }, category = "material", maxStack = 64,
      behavior = "material", description = "柔韧的丝线，可以做弓" },
    { id = "gunpowder", name = "火药", icon = "药", color = { 0.42, 0.42, 0.45 }, category = "material", maxStack = 64,
      behavior = "material", description = "炸弹人留下的易爆粉末" },
    { id = "ectoplasm", name = "灵质", icon = "灵", color = { 0.70, 0.85, 0.95 }, category = "material", maxStack = 64,
      behavior = "material", description = "幽灵残留的半透明物质" },
    { id = "wheat", name = "小麦", icon = "麦", color = { 0.86, 0.74, 0.32 }, category = "material", maxStack = 64,
      behavior = "material", description = "可以做面包" },
    { id = "arrow", name = "箭", icon = "箭", color = { 0.72, 0.66, 0.55 }, category = "material", maxStack = 64,
      behavior = "material", description = "弓箭手的弹药" },

    -- ==================== 食物 ====================
    { id = "apple", name = "苹果", icon = "苹", color = { 0.82, 0.18, 0.16 }, category = "food", maxStack = 64,
      behavior = "food", description = "恢复饥饿值和少量生命", foodHunger = 4, foodHeal = 4 },
    { id = "bread", name = "面包", icon = "包", color = { 0.80, 0.58, 0.28 }, category = "food", maxStack = 64,
      behavior = "food", description = "恢复饥饿值", foodHunger = 6, foodHeal = 2 },
    { id = "beef", name = "生牛肉", icon = "牛", color = { 0.75, 0.30, 0.32 }, category = "food", maxStack = 64,
      behavior = "food", description = "生肉，恢复少量饥饿值", foodHunger = 3, foodHeal = 1 },
    { id = "porkchop", name = "生猪肉", icon = "猪", color = { 0.88, 0.58, 0.60 }, category = "food", maxStack = 64,
      behavior = "food", description = "生肉，恢复少量饥饿值", foodHunger = 3, foodHeal = 1 },
    { id = "chicken_meat", name = "生鸡肉", icon = "鸡", color = { 0.92, 0.78, 0.60 }, category = "food", maxStack = 64,
      behavior = "food", description = "生肉，恢复少量饥饿值", foodHunger = 2, foodHeal = 1 },
    { id = "rotten_flesh", name = "腐肉", icon = "腐", color = { 0.52, 0.42, 0.32 }, category = "food", maxStack = 64,
      behavior = "food", description = "僵尸掉的肉，勉强能吃", foodHunger = 1, foodHeal = 0 },

    -- ==================== 武器 ====================
    { id = "sword", name = "剑", icon = "剑", color = { 0.85, 0.86, 0.90 }, category = "weapon", maxStack = 1,
      durability = 250, behavior = "weapon", attackBonus = 200,
      description = "攻击力 +200。左键攻击生物会消耗耐久" },
    { id = "bow", name = "弓", icon = "弓", color = { 0.62, 0.45, 0.26 }, category = "bow", maxStack = 1,
      durability = 384, behavior = "bow", attackBonus = 0,
      description = "远程武器。右键射箭（消耗背包里的箭）" },

    -- ==================== 工具 ====================
    { id = "pickaxe", name = "铁镐", icon = "镐", color = { 0.72, 0.74, 0.78 }, category = "tool", maxStack = 1,
      durability = 250, behavior = "tool", toolType = "pickaxe", attackBonus = 50,
      description = "可以正常开采石质方块" },
    { id = "axe", name = "铁斧", icon = "斧", color = { 0.72, 0.74, 0.78 }, category = "tool", maxStack = 1,
      durability = 250, behavior = "tool", toolType = "axe", attackBonus = 40,
      description = "可以正常采集木质方块" },
    { id = "shovel", name = "铁铲", icon = "铲", color = { 0.72, 0.74, 0.78 }, category = "tool", maxStack = 1,
      durability = 250, behavior = "tool", toolType = "shovel", attackBonus = 20,
      description = "可以正常采集泥土/沙砾类方块" },

    -- ==================== 护甲（Design.md 数值）====================
    { id = "helmet", name = "头盔", icon = "盔", color = { 0.60, 0.62, 0.68 }, category = "armor", maxStack = 1,
      durability = 200, behavior = "armor", equipSlot = "head", armorBonus = 60,
      description = "护甲 +60" },
    { id = "chestplate", name = "胸甲", icon = "胸", color = { 0.60, 0.62, 0.68 }, category = "armor", maxStack = 1,
      durability = 200, behavior = "armor", equipSlot = "chest", armorBonus = 100,
      description = "护甲 +100" },
    { id = "leggings", name = "护腿", icon = "腿", color = { 0.60, 0.62, 0.68 }, category = "armor", maxStack = 1,
      durability = 200, behavior = "armor", equipSlot = "legs", armorBonus = 30,
      description = "护甲 +30" },
    { id = "armguards", name = "护臂", icon = "臂", color = { 0.60, 0.62, 0.68 }, category = "armor", maxStack = 1,
      durability = 200, behavior = "armor", equipSlot = "arms", armorBonus = 30,
      description = "护甲 +30" },

    -- ==================== 药水 ====================
    { id = "potion_heal", name = "治疗药水", icon = "药", color = { 0.90, 0.25, 0.30 }, category = "potion", maxStack = 16,
      behavior = "potion", description = "立刻恢复 50 点生命",
      effect = { kind = "heal", value = 50, duration = 0 } },
    { id = "potion_strength", name = "力量药水", icon = "力", color = { 0.80, 0.30, 0.20 }, category = "potion", maxStack = 1,
      behavior = "potion", description = "60 秒内攻击力 +100",
      effect = { kind = "strength", value = 100, duration = 60 } },
    { id = "potion_speed", name = "迅捷药水", icon = "速", color = { 0.30, 0.75, 0.90 }, category = "potion", maxStack = 1,
      behavior = "potion", description = "60 秒内移动速度 +60%",
      effect = { kind = "speed", value = 0.6, duration = 60 } },

    -- ==================== 桶 ====================
    { id = "bucket", name = "铁桶", icon = "桶", color = { 0.70, 0.72, 0.76 }, category = "bucket", maxStack = 1,
      behavior = "bucket", description = "右键水源可以装满水" },
    { id = "water_bucket", name = "水桶", icon = "水", color = { 0.25, 0.55, 0.90 }, category = "bucket", maxStack = 1,
      behavior = "water_bucket", description = "右键地面放置水源" },
}

-- ====================================================================
-- 方块物品（从方块注册表自动生成，不用手工维护）
-- ====================================================================

---生成方块物品定义并追加到 items
---@param Blocks table BlockRegistry
function ItemDefinitions.buildBlockItems(Blocks)
    local list = Blocks:getPlaceableBlocks()
    for _, blockId in ipairs(list) do
        -- 水/岩浆只能通过桶交互，不做成普通方块物品
        if blockId ~= Blocks.WATER and blockId ~= Blocks.LAVA then
            local color = Blocks:getColor(blockId)
            local name = BLOCK_NAMES_ZH[blockId] or Blocks:getDisplayName(blockId)
            ItemDefinitions.items[#ItemDefinitions.items + 1] = {
                id = "block:" .. blockId,
                name = name,
                icon = nil,                 -- 方块用颜色块表示
                color = { color.r, color.g, color.b },
                category = "block",
                maxStack = 64,
                behavior = "block",
                blockId = blockId,
                description = "可放置方块",
            }
        end
    end
end

return ItemDefinitions
