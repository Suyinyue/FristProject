-- ====================================================================
-- ui/InventoryUI.lua
-- 背包界面（参考 Minecraft 原版风格）
--
--   装备栏 4 格（头盔 / 胸甲 / 护腿 / 护臂）+ 副手 1 格
--   主背包 27 格 + 快捷栏 9 格
--   合成：2×2（背包内）/ 3×3（右键工作台）
--   创造页：方块 / 物品（方便测试与自由建造，取代旧的分页方块栏）
--
-- 交互（和 MC 一致）：
--   左键：拿起 / 放下整堆、交换
--   右键：拿起一半 / 放置单个
--   Shift+左键：快速转移（装备/主背包/快捷栏互转；合成结果一次做完）
--   E：打开 / 关闭
-- ====================================================================

local UI = require("urhox-libs/UI/init")
local Config = require("config.GameConfig")
local ItemRegistry = require("items.ItemRegistry")
local ItemStack = require("items.ItemStack")
local InventorySlot = require("items.InventorySlot")
local CraftingSystem = require("items.CraftingSystem")
local BlockPalette = require("data.BlockPalette")

local SLOT = 40
local GAP = 4

local COL_SLOT = { 64, 64, 74, 235 }
local COL_SLOT_DISABLED = { 38, 38, 44, 235 }
local COL_BORDER = { 22, 22, 26, 255 }
local COL_SELECTED = { 255, 210, 80, 255 }
local COL_PANEL = { 38, 38, 46, 248 }
local COL_TAB = { 55, 55, 66, 235 }
local COL_TAB_ACTIVE = { 92, 104, 140, 245 }

---@class InventoryUI
---@field player Player
---@field inventory Inventory
---@field crafting CraftingSystem
---@field dropSystem ItemDropSystem|nil
---@field playerController PlayerController|nil
---@field root Panel|nil
---@field isOpen_ boolean
---@field cursorWidget { root: Widget, icon: Label, count: Label }|nil
---@field tooltip { root: Widget, title: Label, desc: Label, stats: Label }|nil
---@field creativeGrid Widget|nil
---@field creativePager Widget|nil
---@field creativeHint Label|nil
---@field creativePagerLabel Label|nil
---@field outputWidget table|nil
---@field mainWidgets table<integer, table>
---@field hotbarWidgets table<integer, table>
---@field armorWidgets table<integer, table>
---@field craftWidgets table<integer, table>
---@field creativeWidgets table<integer, table>
---@field offhandWidget table|nil
local InventoryUI = {}
InventoryUI.__index = InventoryUI

-- ====================================================================
-- 小工具
-- ====================================================================

---0-1 颜色 → 0-255 RGBA
---@param c number[]
---@param alpha integer|nil
---@return integer[]
local function rgba(c, alpha)
    return {
        math.floor(math.min(1, math.max(0, c[1])) * 255),
        math.floor(math.min(1, math.max(0, c[2])) * 255),
        math.floor(math.min(1, math.max(0, c[3])) * 255),
        alpha or 255,
    }
end

---提亮颜色（物品图标用）
---@param c number[]
---@return integer[]
local function brighten(c)
    return rgba({
        math.min(1, c[1] * 1.25 + 0.20),
        math.min(1, c[2] * 1.25 + 0.20),
        math.min(1, c[3] * 1.25 + 0.20),
    })
end

---@param event PointerEvent|nil
local function stopEvent(event)
    if event and event.StopPropagation then
        event:StopPropagation()
    end
end

-- ====================================================================
-- 构造
-- ====================================================================

---@param player Player
---@param options table|nil { dropSystem = ItemDropSystem, projectiles = ProjectileManager }
---@return InventoryUI
function InventoryUI.new(player, options)
    local self = setmetatable({}, InventoryUI)
    options = options or {}

    self.player = player
    self.inventory = player:getInventory()
    self.crafting = CraftingSystem.new()
    self.dropSystem = options.dropSystem
    self.playerController = nil

    self.root = nil
    self.panel = nil
    self.isOpen_ = false

    -- 合成
    self.gridWidth = 2
    self.craftSlots = {}
    for i = 1, 9 do
        self.craftSlots[i] = InventorySlot.new(nil)
    end
    self.craftWidgets = {}
    self.outputWidget = nil
    self.resultStack = nil

    -- 槽位控件
    self.mainWidgets = {}
    self.hotbarWidgets = {}
    self.armorWidgets = {}
    self.offhandWidget = nil

    -- 拖动 / 悬停
    self.cursorStack = nil
    self.cursorWidget = nil
    self.pointerX = 0
    self.pointerY = 0
    self.pointerListenerId = nil
    self.pointerDownListenerId = nil
    self.tooltip = nil
    self.tooltipVisible = false
    self.hoverKind = nil
    self.hoverIndex = nil

    -- 创造页
    self.tab = "craft"
    self.palettePage = 1
    self.itemPage = 1
    self.creativeWidgets = {}
    self.creativeGrid = nil
    self.creativePager = nil
    self.creativeHint = nil
    self.tabButtons = {}

    return self
end

---@param controller PlayerController|nil
function InventoryUI:setPlayerController(controller)
    self.playerController = controller
end

-- ====================================================================
-- 槽位控件
-- ====================================================================

---创建通用槽位控件
---@param id string
---@param onDown function|nil
---@param onEnter function|nil
---@param onLeave function|nil
---@return table
function InventoryUI:createSlotWidget(id, onDown, onEnter, onLeave)
    local icon = UI.Label {
        id = id .. "_icon",
        text = "",
        width = 30,
        height = 30,
        borderRadius = 4,
        textAlign = "center",
        fontSize = 20,
        fontColor = { 255, 255, 255, 255 },
        backgroundColor = { 0, 0, 0, 0 },
        pointerEvents = "none",
    }

    local count = UI.Label {
        id = id .. "_count",
        text = "",
        position = "absolute",
        right = 4,
        bottom = 1,
        fontSize = 11,
        fontColor = { 255, 255, 255, 255 },
        pointerEvents = "none",
    }

    local dur = UI.Panel {
        id = id .. "_dur",
        position = "absolute",
        left = 4,
        bottom = 3,
        width = 32,
        height = 3,
        borderRadius = 1,
        backgroundColor = { 80, 220, 80, 255 },
        pointerEvents = "none",
        visible = false,
    }

    local root = UI.Panel {
        id = id,
        width = SLOT,
        height = SLOT,
        borderRadius = 6,
        backgroundColor = COL_SLOT,
        borderWidth = 1,
        borderColor = COL_BORDER,
        alignItems = "center",
        justifyContent = "center",
        children = { icon, count, dur },
    }

    root.props.onPointerDown = onDown
    root.props.onPointerEnter = onEnter
    root.props.onPointerLeave = onLeave

    return { root = root, icon = icon, count = count, dur = dur }
end

---刷新槽位显示
---@param widget table
---@param stack ItemStack|nil
---@param selected boolean|nil
---@param disabled boolean|nil
function InventoryUI:refreshSlotWidget(widget, stack, selected, disabled)
    if not widget then
        return
    end

    if disabled then
        widget.root:SetStyle({ backgroundColor = COL_SLOT_DISABLED, borderColor = COL_BORDER, borderWidth = 1 })
    else
        widget.root:SetStyle({
            backgroundColor = COL_SLOT,
            borderColor = selected and COL_SELECTED or COL_BORDER,
            borderWidth = selected and 2 or 1,
        })
    end

    if not stack or stack.count <= 0 then
        widget.icon:SetText("")
        widget.icon:SetStyle({ backgroundColor = { 0, 0, 0, 0 }, backgroundImage = false,
            fontColor = { 255, 255, 255, 255 } })
        widget.count:SetText("")
        widget.dur:SetVisible(false)
        return
    end

    local def = ItemRegistry:get(stack.id)
    if def and def.iconTexture then
        -- 非方块物品：显示贴图图标
        widget.icon:SetText("")
        widget.icon:SetStyle({
            backgroundColor = { 0, 0, 0, 0 },
            backgroundImage = def.iconTexture,
            backgroundFit = "contain",
            fontColor = { 255, 255, 255, 255 },
        })
    elseif stack:isBlock() then
        widget.icon:SetText("")
        widget.icon:SetStyle({
            backgroundColor = def and rgba(def.color) or { 150, 150, 150, 255 },
            backgroundImage = false,
            fontColor = { 255, 255, 255, 255 },
        })
    else
        widget.icon:SetText(def and def.icon or "?")
        widget.icon:SetStyle({
            backgroundColor = { 0, 0, 0, 0 },
            backgroundImage = false,
            fontColor = def and brighten(def.color) or { 255, 255, 255, 255 },
        })
    end

    widget.count:SetText(stack.count > 1 and tostring(stack.count) or "")

    if stack:hasDurability() then
        local frac = stack:getDurabilityFraction()
        widget.dur:SetVisible(frac < 0.999)
        local w = math.max(2, math.floor((SLOT - 8) * frac))
        local color = { 80, 220, 80, 255 }
        if frac < 0.25 then color = { 230, 70, 60, 255 }
        elseif frac < 0.5 then color = { 240, 200, 60, 255 } end
        widget.dur:SetStyle({ width = w, backgroundColor = color })
    else
        widget.dur:SetVisible(false)
    end
end

-- ====================================================================
-- 构建界面
-- ====================================================================

---构建根控件（默认隐藏）
---@return Panel
function InventoryUI:build()
    if self.root then
        return self.root
    end

    local self_ = self

    -- ---------- 标题栏 ----------
    local closeBtn = UI.Label {
        id = "inv_close",
        text = "关闭 (E)",
        fontSize = 12,
        fontColor = { 255, 255, 255, 235 },
        backgroundColor = { 80, 70, 70, 235 },
        borderRadius = 6,
        paddingHorizontal = 10,
        paddingVertical = 5,
        pointerEvents = "auto",
        onClick = function() self_:close() end,
    }

    local titleRow = UI.Row {
        width = "100%",
        justifyContent = "space-between",
        alignItems = "center",
        children = {
            UI.Label { text = "背包", fontSize = 18, fontColor = { 255, 255, 255, 255 } },
            closeBtn,
        },
    }

    -- ---------- 装备栏 ----------
    for n, equip in ipairs({ "head", "chest", "legs", "arms" }) do
        local index = self.inventory.ARMOR_SLOTS[equip]
        local widget = self:createSlotWidget(
            "inv_armor_" .. n,
            function(event) self_:onInventorySlotClick(index, event) end,
            function() self_:showTooltip(index) end,
            function() self_:hideTooltip() end)
        self.armorWidgets[n] = widget
    end

    self.offhandWidget = self:createSlotWidget(
        "inv_offhand",
        function(event) self_:onInventorySlotClick(self.inventory.OFFHAND, event) end,
        function() self_:showTooltip(self.inventory.OFFHAND) end,
        function() self_:hideTooltip() end)

    local armorColumn = UI.Column {
        width = 210,
        gap = 6,
        alignItems = "center",
        children = {
            UI.Label { text = "装备", fontSize = 13, fontColor = { 220, 220, 230, 235 } },
            UI.Row {
                gap = GAP,
                children = {
                    self.armorWidgets[1].root,
                    self.armorWidgets[2].root,
                    self.armorWidgets[3].root,
                    self.armorWidgets[4].root,
                },
            },
            UI.Row {
                gap = GAP,
                alignItems = "center",
                children = {
                    UI.Label { text = "副手", fontSize = 11, fontColor = { 200, 200, 210, 220 } },
                    self.offhandWidget.root,
                },
            },
        },
    }

    -- ---------- 合成 ----------
    for i = 1, 9 do
        local widget = self:createSlotWidget(
            "inv_craft_" .. i,
            function(event) self_:onCraftSlotClick(i, event) end,
            function() self_:showCraftTooltip(i) end,
            function() self_:hideTooltip() end)
        self.craftWidgets[i] = widget
    end

    local craftRows = {}
    for r = 0, 2 do
        craftRows[#craftRows + 1] = UI.Row {
            gap = GAP,
            children = {
                self.craftWidgets[r * 3 + 1].root,
                self.craftWidgets[r * 3 + 2].root,
                self.craftWidgets[r * 3 + 3].root,
            },
        }
    end

    self.outputWidget = self:createSlotWidget(
        "inv_craft_output",
        function(event) self_:onOutputClick(event) end,
        function() self_:showOutputTooltip() end,
        function() self_:hideTooltip() end)

    local craftColumn = UI.Column {
        width = 210,
        gap = 6,
        alignItems = "center",
        children = {
            UI.Label { text = "合成", fontSize = 13, fontColor = { 220, 220, 230, 235 } },
            UI.Row {
                gap = 8,
                alignItems = "center",
                children = {
                    UI.Column { gap = GAP, children = craftRows },
                    UI.Label { text = "→", fontSize = 22, fontColor = { 230, 230, 240, 220 } },
                    self.outputWidget.root,
                },
            },
            UI.Label {
                id = "inv_craft_hint",
                text = "2×2 合成（右键工作台可 3×3）",
                fontSize = 10,
                fontColor = { 190, 190, 200, 220 },
            },
        },
    }

    -- ---------- 创造页 ----------
    local function tabButton(id, text, tab)
        local btn = UI.Label {
            id = id,
            text = text,
            fontSize = 12,
            fontColor = { 235, 235, 245, 235 },
            backgroundColor = COL_TAB,
            borderRadius = 6,
            paddingHorizontal = 10,
            paddingVertical = 5,
            pointerEvents = "auto",
            onClick = function() self_:setTab(tab) end,
        }
        self.tabButtons[tab] = btn
        return btn
    end

    local creativeRows = {}
    for row = 1, 2 do
        local children = {}
        for col = 1, 6 do
            local n = (row - 1) * 6 + col
            if n <= 11 then
                local widget = self:createSlotWidget(
                    "inv_creative_" .. n,
                    function(event) self_:onCreativeSlotClick(n, event) end,
                    function() self_:showCreativeTooltip(n) end,
                    function() self_:hideTooltip() end)
                self.creativeWidgets[n] = widget
                children[#children + 1] = widget.root
            end
        end
        creativeRows[#creativeRows + 1] = UI.Row { gap = GAP, children = children }
    end

    self.creativeGrid = UI.Column { gap = GAP, children = creativeRows }

    local pagerLabel = UI.Label {
        id = "inv_creative_page",
        text = "1/1",
        fontSize = 11,
        fontColor = { 220, 220, 230, 230 },
        textAlign = "center",
        paddingHorizontal = 8,
    }
    self.creativePagerLabel = pagerLabel

    self.creativePager = UI.Row {
        gap = 6,
        alignItems = "center",
        justifyContent = "center",
        children = {
            UI.Label {
                text = "◀", fontSize = 14, fontColor = { 255, 255, 255, 235 },
                backgroundColor = COL_TAB, borderRadius = 6, paddingHorizontal = 10, paddingVertical = 3,
                pointerEvents = "auto",
                onClick = function() self_:changeCreativePage(-1) end,
            },
            pagerLabel,
            UI.Label {
                text = "▶", fontSize = 14, fontColor = { 255, 255, 255, 235 },
                backgroundColor = COL_TAB, borderRadius = 6, paddingHorizontal = 10, paddingVertical = 3,
                pointerEvents = "auto",
                onClick = function() self_:changeCreativePage(1) end,
            },
        },
    }

    self.creativeHint = UI.Label {
        id = "inv_creative_hint",
        text = "点击物品放入光标，Shift+点击直接放入背包",
        fontSize = 10,
        fontColor = { 190, 190, 200, 220 },
        textAlign = "center",
    }

    local creativeColumn = UI.Column {
        width = 300,
        gap = 6,
        alignItems = "center",
        children = {
            UI.Row {
                gap = 6,
                children = {
                    tabButton("inv_tab_craft", "合成说明", "craft"),
                    tabButton("inv_tab_blocks", "方块", "blocks"),
                    tabButton("inv_tab_items", "物品", "items"),
                },
            },
            self.creativeHint,
            self.creativeGrid,
            self.creativePager,
            UI.Label {
                text = "Shift+点击：快速转移",
                fontSize = 10,
                fontColor = { 170, 170, 180, 200 },
            },
        },
    }

    local contentRow = UI.Row {
        gap = 10,
        width = "100%",
        justifyContent = "space-between",
        alignItems = "flex-start",
        children = { armorColumn, craftColumn, creativeColumn },
    }

    -- ---------- 主背包 27 格 ----------
    local mainRows = {}
    for row = 0, 2 do
        local children = {}
        for col = 1, 9 do
            local index = row * 9 + col
            local widget = self:createSlotWidget(
                "inv_main_" .. index,
                function(event) self_:onInventorySlotClick(index, event) end,
                function() self_:showTooltip(index) end,
                function() self_:hideTooltip() end)
            self.mainWidgets[index] = widget
            children[#children + 1] = widget.root
        end
        mainRows[#mainRows + 1] = UI.Row { gap = GAP, children = children }
    end

    local mainGrid = UI.Column {
        gap = GAP,
        alignItems = "center",
        width = "100%",
        children = mainRows,
    }

    -- ---------- 快捷栏 ----------
    local hotbarChildren = {}
    for n = 1, 9 do
        local index = self.inventory:getHotbarIndex(n)
        local widget = self:createSlotWidget(
            "inv_hotbar_" .. n,
            function(event) self_:onHotbarSlotClick(n, event) end,
            function() self_:showTooltip(index) end,
            function() self_:hideTooltip() end)
        self.hotbarWidgets[n] = widget
        hotbarChildren[#hotbarChildren + 1] = widget.root
    end

    local hotbarRow = UI.Row {
        gap = GAP,
        justifyContent = "center",
        width = "100%",
        children = hotbarChildren,
    }

    -- ---------- 主面板 ----------
    self.panel = UI.Panel {
        id = "inventory_panel",
        width = 800,
        height = 500,
        backgroundColor = COL_PANEL,
        borderRadius = 14,
        padding = 14,
        flexDirection = "column",
        gap = 10,
        children = { titleRow, contentRow, mainGrid, hotbarRow },
    }

    -- ---------- 拖拽光标 ----------
    local cursorIcon = UI.Label {
        id = "inv_cursor_icon",
        text = "",
        width = 32, height = 32,
        borderRadius = 4,
        textAlign = "center",
        fontSize = 22,
        fontColor = { 255, 255, 255, 255 },
        backgroundColor = { 0, 0, 0, 0 },
        pointerEvents = "none",
    }
    local cursorCount = UI.Label {
        id = "inv_cursor_count",
        text = "",
        position = "absolute",
        right = 3, bottom = 1,
        fontSize = 11,
        fontColor = { 255, 255, 255, 255 },
        pointerEvents = "none",
    }
    self.cursorWidget = {
        icon = cursorIcon,
        count = cursorCount,
        root = UI.Panel {
            id = "inv_cursor",
            position = "absolute",
            left = 0, top = 0,
            width = SLOT, height = SLOT,
            backgroundColor = { 70, 70, 82, 245 },
            borderRadius = 6,
            borderWidth = 1,
            borderColor = { 255, 255, 255, 200 },
            alignItems = "center",
            justifyContent = "center",
            pointerEvents = "none",
            visible = false,
            children = { cursorIcon, cursorCount },
        },
    }

    -- ---------- 悬停提示 ----------
    local tipTitle = UI.Label { id = "inv_tip_title", text = "", fontSize = 13, fontColor = { 255, 255, 255, 255 } }
    local tipDesc = UI.Label { id = "inv_tip_desc", text = "", fontSize = 10, fontColor = { 210, 210, 220, 230 } }
    local tipStats = UI.Label { id = "inv_tip_stats", text = "", fontSize = 10, fontColor = { 160, 220, 255, 235 } }
    self.tooltip = {
        title = tipTitle,
        desc = tipDesc,
        stats = tipStats,
        root = UI.Panel {
            id = "inv_tooltip",
            position = "absolute",
            left = 0, top = 0,
            width = 220,
            backgroundColor = { 18, 18, 24, 245 },
            borderRadius = 8,
            padding = 8,
            gap = 3,
            visible = false,
            pointerEvents = "none",
            children = { tipTitle, tipDesc, tipStats },
        },
    }

    -- ---------- 全屏遮罩 ----------
    self.root = UI.Panel {
        id = "inventory_root",
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 140 },
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "auto",
        visible = false,
        children = { self.panel, self.tooltip.root, self.cursorWidget.root },
    }

    -- 全局指针位置（拖动光标 / 提示框跟随）
    self.pointerListenerId = UI.Input.On("PointerMove", function(event)
        self.pointerX = event.x
        self.pointerY = event.y
    end)
    self.pointerDownListenerId = UI.Input.On("PointerDown", function(event)
        self.pointerX = event.x
        self.pointerY = event.y
    end)

    self:setTab("craft")
    return self.root
end

-- ====================================================================
-- 打开 / 关闭
-- ====================================================================

---@param gridWidth integer|nil 2 或 3
function InventoryUI:open(gridWidth)
    if not self.root then
        return
    end

    local newWidth = (gridWidth == 3) and 3 or 2
    if newWidth ~= self.gridWidth then
        -- 切到 2×2 时，3×3 里被禁用的格子中的物品还回背包
        self.gridWidth = newWidth
        if newWidth == 2 then
            self:returnInactiveCraftItems()
        end
    end

    self.root:SetVisible(true)
    self.isOpen_ = true
    self:applyMouseMode(true)
    self:refresh()
end

function InventoryUI:close()
    if not self.root or not self.isOpen_ then
        return
    end

    self:returnCraftingItems()
    self:returnCursorToInventory()
    self.root:SetVisible(false)
    self.isOpen_ = false
    if self.tooltip then
        self.tooltip.root:SetVisible(false)
    end
    self:applyMouseMode(false)
end

function InventoryUI:toggle()
    if self.isOpen_ then
        self:close()
    else
        self:open(2)
    end
end

---右键工作台：打开 3×3 合成
function InventoryUI:openCraftingTable()
    self:open(3)
    self:setTab("craft")
end

---@return boolean
function InventoryUI:isOpen()
    return self.isOpen_
end

---切换鼠标模式
---@param open boolean
function InventoryUI:applyMouseMode(open)
    local platform = GetPlatform()
    local isMobile = platform == "Android" or platform == "iOS"

    if self.playerController then
        -- 移动端始终关闭鼠标视角（触摸区域另管）
        self.playerController:setMouseLocked(isMobile and false or not open)
    end

    if isMobile then
        return
    end

    if open then
        input.mouseMode = MM_ABSOLUTE
        input:SetMouseVisible(true)
    else
        input.mouseMode = MM_RELATIVE
        input:SetMouseVisible(false)
    end
end

-- ====================================================================
-- 刷新
-- ====================================================================

function InventoryUI:refresh()
    if not self.root then
        return
    end

    local inv = self.inventory
    local selected = self.player:getSelectedSlotIndex()

    -- 主背包
    for i = 1, 27 do
        self:refreshSlotWidget(self.mainWidgets[i], inv:getStack(i), false, false)
    end

    -- 快捷栏（高亮当前选中）
    for n = 1, 9 do
        local index = inv:getHotbarIndex(n)
        self:refreshSlotWidget(self.hotbarWidgets[n], inv:getStack(index), n == selected, false)
    end

    -- 装备 / 副手
    local armorOrder = { "head", "chest", "legs", "arms" }
    for n, equip in ipairs(armorOrder) do
        local index = inv.ARMOR_SLOTS[equip]
        self:refreshSlotWidget(self.armorWidgets[n], inv:getStack(index), false, false)
    end
    self:refreshSlotWidget(self.offhandWidget, inv:getStack(inv.OFFHAND), false, false)

    self:refreshCraft()
    self:refreshCreative()
    self:refreshCursor()
end

---刷新合成格 + 结果
function InventoryUI:refreshCraft()
    if not self.isOpen_ then
        return
    end

    local active = {}
    if self.gridWidth == 3 then
        for i = 1, 9 do active[i] = true end
    else
        active[1] = true; active[2] = true
        active[4] = true; active[5] = true
    end

    for i = 1, 9 do
        self:refreshSlotWidget(self.craftWidgets[i], self.craftSlots[i]:get(), false, not active[i])
    end

    local hint = self.root and self.root:FindById("inv_craft_hint")
    if hint then
        hint:SetText(self.gridWidth == 3 and "3×3 合成（工作台）" or "2×2 合成（右键工作台可 3×3）")
    end

    self:updateCraftResult()
end

---计算并刷新合成结果
function InventoryUI:updateCraftResult()
    local _, result = self:getCraftResult()
    self.resultStack = result
    self:refreshSlotWidget(self.outputWidget, result, false, false)
end

---当前合成网格（行优先的 stacks / slots）
---@return (ItemStack|nil)[] stacks
---@return InventorySlot[] slots
function InventoryUI:getActiveGrid()
    local stacks = {}
    local slots = {}
    if self.gridWidth == 3 then
        for i = 1, 9 do
            stacks[i] = self.craftSlots[i]:get()
            slots[i] = self.craftSlots[i]
        end
    else
        local indices = { 1, 2, 4, 5 }
        for k, i in ipairs(indices) do
            stacks[k] = self.craftSlots[i]:get()
            slots[k] = self.craftSlots[i]
        end
    end
    return stacks, slots
end

---@return CraftingRecipe|nil, ItemStack|nil
function InventoryUI:getCraftResult()
    local stacks = self:getActiveGrid()
    return self.crafting:match(stacks, self.gridWidth, self.gridWidth)
end

function InventoryUI:refreshCursor()
    if not self.cursorWidget then
        return
    end

    local stack = self.cursorStack
    if not stack or stack.count <= 0 then
        self.cursorStack = nil
        self.cursorWidget.root:SetVisible(false)
        return
    end

    self.cursorWidget.root:SetVisible(true)
    local def = ItemRegistry:get(stack.id)
    if def and def.iconTexture then
        self.cursorWidget.icon:SetText("")
        self.cursorWidget.icon:SetStyle({
            backgroundColor = { 0, 0, 0, 0 },
            backgroundImage = def.iconTexture,
            backgroundFit = "contain",
            fontColor = { 255, 255, 255, 255 },
        })
    elseif stack:isBlock() then
        self.cursorWidget.icon:SetText("")
        self.cursorWidget.icon:SetStyle({
            backgroundColor = def and rgba(def.color) or { 150, 150, 150, 255 },
            backgroundImage = false,
        })
    else
        self.cursorWidget.icon:SetText(def and def.icon or "?")
        self.cursorWidget.icon:SetStyle({
            backgroundColor = { 0, 0, 0, 0 },
            backgroundImage = false,
            fontColor = def and brighten(def.color) or { 255, 255, 255, 255 },
        })
    end
    self.cursorWidget.count:SetText(stack.count > 1 and tostring(stack.count) or "")
end

-- ====================================================================
-- 点击处理：背包 / 快捷栏 / 装备
-- ====================================================================

---@param index integer
---@param event PointerEvent
function InventoryUI:onInventorySlotClick(index, event)
    stopEvent(event)
    if not self.isOpen_ then
        return
    end

    local button = (event and event.button) or 0
    local shift = input:GetQualifierDown(QUAL_SHIFT)

    if shift then
        self:quickMoveInventorySlot(index)
        return
    end

    self:clickSlot(self.inventory:getSlot(index), button)
    self.inventory:markDirty()
    self:refresh()
end

---快捷栏点击：左键选为当前手持，Shift 则快速转移
---@param n integer 1..9
---@param event PointerEvent
function InventoryUI:onHotbarSlotClick(n, event)
    stopEvent(event)
    if not self.isOpen_ then
        return
    end
    local shift = input:GetQualifierDown(QUAL_SHIFT)
    if shift then
        self:onInventorySlotClick(self.inventory:getHotbarIndex(n), event)
        return
    end
    self.player:selectSlot(n)
    self.inventory:markDirty()
    self:refresh()
end

---MC 风格点击：左键整堆 / 右键一半或单个
---@param slot InventorySlot|nil
---@param button integer 0 左键 / 2 右键
function InventoryUI:clickSlot(slot, button)
    if not slot then
        return
    end

    local cursor = self.cursorStack
    local current = slot:get()

    if button == 2 then
        -- 右键
        if not cursor then
            if current and current.count > 0 then
                local half = math.ceil(current.count / 2)
                self.cursorStack = slot:take(half)
            end
        else
            if not current then
                if slot:canAccept(cursor) then
                    slot:set(cursor:split(1))
                end
            elseif current:isSameInstance(cursor) and current:getRemainingSpace() > 0 then
                local one = cursor:split(1)
                if one then
                    slot:add(one)
                end
            end
        end
    else
        -- 左键
        if not cursor then
            self.cursorStack = slot:take(slot:getCount())
        elseif not current then
            if slot:canAccept(cursor) then
                slot:set(cursor)
                self.cursorStack = nil
            end
        elseif current:isSameInstance(cursor) then
            current:mergeFrom(cursor)
            if cursor.count <= 0 then
                self.cursorStack = nil
            end
        else
            if slot:canAccept(cursor) then
                slot:set(cursor)
                self.cursorStack = current
            end
        end
    end

    if self.cursorStack and self.cursorStack.count <= 0 then
        self.cursorStack = nil
    end
end

-- ====================================================================
-- Shift 快速转移
-- ====================================================================

---@param index integer
function InventoryUI:quickMoveInventorySlot(index)
    local inv = self.inventory
    local stack = inv:getStack(index)
    if not stack then
        return
    end

    local def = ItemRegistry:get(stack.id)
    -- 护甲 → 直接穿上
    if def and def.behavior == "armor" and def.equipSlot then
        local targetIndex = inv.ARMOR_SLOTS[def.equipSlot]
        if targetIndex and not inv:getStack(targetIndex) then
            inv:setStack(targetIndex, stack)
            inv:setStack(index, nil)
            inv:markDirty()
            self:refresh()
            return
        end
    end

    if index >= inv.HOTBAR_START and index <= inv.HOTBAR_END then
        inv:transferSlot(index, inv.MAIN_START, inv.MAIN_END)
    elseif index >= inv.MAIN_START and index <= inv.MAIN_END then
        inv:transferSlot(index, inv.HOTBAR_START, inv.HOTBAR_END)
    else
        -- 装备 / 副手 → 快捷栏，再主背包
        inv:transferSlot(index, inv.HOTBAR_START, inv.HOTBAR_END)
        if inv:getStack(index) then
            inv:transferSlot(index, inv.MAIN_START, inv.MAIN_END)
        end
    end

    inv:markDirty()
    self:refresh()
end

-- ====================================================================
-- 合成格 / 结果
-- ====================================================================

---@param i integer 1..9
---@param event PointerEvent
function InventoryUI:onCraftSlotClick(i, event)
    stopEvent(event)
    if not self.isOpen_ then
        return
    end
    if self.gridWidth == 2 and not (i == 1 or i == 2 or i == 4 or i == 5) then
        return
    end

    local button = (event and event.button) or 0
    local shift = input:GetQualifierDown(QUAL_SHIFT)
    if shift then
        -- 合成格 Shift：把这一格还回背包
        local slot = self.craftSlots[i]
        local stack = slot:take(slot:getCount())
        if stack then
            local left = self.inventory:addStack(stack)
            if left and self.dropSystem then
                self.dropSystem:spawn(left, self.player:getPosition() + Vector3(0, 2, 0))
            end
        end
    else
        self:clickSlot(self.craftSlots[i], button)
    end

    self:updateCraftResult()
    self.inventory:markDirty()
    self:refresh()
end

---@param event PointerEvent
function InventoryUI:onOutputClick(event)
    stopEvent(event)
    if not self.isOpen_ then
        return
    end

    local shift = input:GetQualifierDown(QUAL_SHIFT)
    if shift then
        self:craftAll()
    else
        self:craftOnce()
    end
end

---取一次合成结果
---@return boolean
function InventoryUI:craftOnce()
    local _, result = self:getCraftResult()
    if not result then
        return false
    end

    -- 优先放进光标；光标已有物品时必须能合并
    if self.cursorStack then
        if not self.cursorStack:isSameInstance(result) then
            return false
        end
        if self.cursorStack:getRemainingSpace() < result.count then
            return false
        end
        self.cursorStack:mergeFrom(result)
    else
        self.cursorStack = result
    end

    local _, slots = self:getActiveGrid()
    self.crafting.consume(slots)
    self:updateCraftResult()
    self.inventory:markDirty()
    self:refresh()
    return true
end

---Shift 连续合成，直到材料不够或背包满
function InventoryUI:craftAll()
    local crafted = 0
    while crafted < 64 do
        local _, result = self:getCraftResult()
        if not result then
            break
        end

        local wanted = result.count
        local leftover = self.inventory:addStack(result)
        local added = wanted - (leftover and leftover.count or 0)
        if added <= 0 then
            break
        end

        local _, slots = self:getActiveGrid()
        self.crafting.consume(slots)
        crafted = crafted + 1

        if leftover then
            -- 背包只装下一部分：剩下的放地上，不吞掉
            if self.dropSystem then
                self.dropSystem:spawn(leftover, self.player:getPosition() + Vector3(0, 2, 0))
            end
            break
        end
    end

    if crafted > 0 then
        self:updateCraftResult()
        self.inventory:markDirty()
        self:refresh()
    end
end

-- ====================================================================
-- 创造页
-- ====================================================================

---@param tab string "craft"/"blocks"/"items"
function InventoryUI:setTab(tab)
    self.tab = tab
    self.palettePage = 1
    self.itemPage = 1

    for key, btn in pairs(self.tabButtons) do
        btn:SetStyle({ backgroundColor = (key == tab) and COL_TAB_ACTIVE or COL_TAB })
    end

    if self.creativeGrid and self.creativePager and self.creativeHint then
        self.creativeGrid:SetVisible(tab ~= "craft")
        self.creativePager:SetVisible(tab ~= "craft")
        self.creativeHint:SetText(tab == "craft"
            and "把材料摆进左侧网格即可合成"
            or "点击物品放入光标，Shift+点击直接放入背包")
    end

    self:refreshCreative()
end

---@param delta integer
function InventoryUI:changeCreativePage(delta)
    if self.tab == "blocks" then
        self.palettePage = BlockPalette:wrapPage(self.palettePage + delta)
    elseif self.tab == "items" then
        self.itemPage = math.max(1, self.itemPage + delta)
    end
    self:refreshCreative()
end

---创造页当前展示的物品 ID
---@return string[]
function InventoryUI:getCreativeItems()
    if self.tab == "blocks" then
        local blocks = BlockPalette:getBlocks(self.palettePage)
        local ids = {}
        for _, blockId in ipairs(blocks) do
            local itemId = "block:" .. blockId
            if ItemRegistry:get(itemId) then
                ids[#ids + 1] = itemId
            end
        end
        return ids
    elseif self.tab == "items" then
        local defs = {}
        for _, def in ipairs(ItemRegistry:getAll()) do
            if def.category ~= "block" then
                defs[#defs + 1] = def.id
            end
        end
        local perPage = 11
        local pageCount = math.max(1, math.ceil(#defs / perPage))
        if self.itemPage > pageCount then
            self.itemPage = pageCount
        end
        local ids = {}
        local startIdx = (self.itemPage - 1) * perPage + 1
        for i = startIdx, math.min(#defs, startIdx + perPage - 1) do
            ids[#ids + 1] = defs[i]
        end
        return ids
    end
    return {}
end

function InventoryUI:refreshCreative()
    if not self.isOpen_ or not self.creativeGrid or not self.creativePagerLabel then
        return
    end

    local ids = self:getCreativeItems()
    for n = 1, 11 do
        local id = ids[n]
        local widget = self.creativeWidgets[n]
        if widget then
            if id then
                local stack = ItemStack.new(id, 1)
                self:refreshSlotWidget(widget, stack, false, false)
                widget.root:SetStyle({ backgroundColor = COL_SLOT })
            else
                self:refreshSlotWidget(widget, nil, false, true)
            end
        end
    end

    if self.creativePagerLabel then
        local pageText = ""
        if self.tab == "blocks" then
            pageText = string.format("%d/%d  %s", self.palettePage, BlockPalette:pageCount(),
                BlockPalette:getPageName(self.palettePage))
        elseif self.tab == "items" then
            local count = 0
            for _, def in ipairs(ItemRegistry:getAll()) do
                if def.category ~= "block" then
                    count = count + 1
                end
            end
            local pages = math.max(1, math.ceil(count / 11))
            pageText = string.format("%d/%d  物品", self.itemPage, pages)
        end
        self.creativePagerLabel:SetText(pageText)
    end
end

---@param n integer 1..11
---@param event PointerEvent
function InventoryUI:onCreativeSlotClick(n, event)
    stopEvent(event)
    if not self.isOpen_ then
        return
    end

    local ids = self:getCreativeItems()
    local id = ids[n]
    if not id then
        return
    end

    local def = ItemRegistry:get(id)
    if not def then
        return
    end

    local count = math.min(def.maxStack, 64)
    local shift = input:GetQualifierDown(QUAL_SHIFT)

    if shift then
        local stack = ItemStack.new(id, count)
        if stack then
            local left = self.inventory:addStack(stack)
            if left and self.dropSystem then
                self.dropSystem:spawn(left, self.player:getPosition() + Vector3(0, 2, 0))
            end
        end
    else
        if self.cursorStack then
            if self.cursorStack.id == id then
                self.cursorStack.count = math.min(self.cursorStack:getMaxStack(), self.cursorStack.count + count)
            else
                self:returnCursorToInventory()
                self.cursorStack = ItemStack.new(id, count)
            end
        else
            self.cursorStack = ItemStack.new(id, count)
        end
    end

    self.inventory:markDirty()
    self:refresh()
end

-- ====================================================================
-- 光标物品归还 / 合成格清空
-- ====================================================================

function InventoryUI:returnCursorToInventory()
    local stack = self.cursorStack
    if not stack then
        return
    end
    self.cursorStack = nil

    local left = self.inventory:addStack(stack)
    if left and self.dropSystem then
        self.dropSystem:spawn(left, self.player:getPosition() + Vector3(0, 2, 0))
    end
    self.inventory:markDirty()
end

function InventoryUI:returnCraftingItems()
    for i = 1, 9 do
        self:returnCraftSlot(i)
    end
    self:updateCraftResult()
end

---把 2×2 模式下不可用的格子（3/6/7/8/9）中的物品还回背包
function InventoryUI:returnInactiveCraftItems()
    for _, i in ipairs({ 3, 6, 7, 8, 9 }) do
        self:returnCraftSlot(i)
    end
end

---@param i integer
function InventoryUI:returnCraftSlot(i)
    local slot = self.craftSlots[i]
    local stack = slot:take(slot:getCount())
    if stack then
        local left = self.inventory:addStack(stack)
        if left and self.dropSystem then
            self.dropSystem:spawn(left, self.player:getPosition() + Vector3(0, 2, 0))
        end
    end
end

-- ====================================================================
-- 悬停提示
-- ====================================================================

---@param stack ItemStack|nil
function InventoryUI:showTooltipForStack(stack)
    if not self.tooltip then
        return
    end
    if not stack or stack.count <= 0 then
        self.tooltip.root:SetVisible(false)
        self.tooltipVisible = false
        return
    end

    local def = ItemRegistry:get(stack.id)
    if not def then
        return
    end

    self.tooltip.title:SetText((stack.count > 1 and (def.name .. " ×" .. stack.count)) or def.name)
    self.tooltip.desc:SetText(def.description or "")

    local stats = {}
    if def.attackBonus and def.attackBonus > 0 then
        stats[#stats + 1] = "攻击 +" .. math.floor(def.attackBonus + 0.5)
    end
    if def.armorBonus and def.armorBonus > 0 then
        stats[#stats + 1] = "护甲 +" .. math.floor(def.armorBonus + 0.5)
    end
    if def.foodHunger and def.foodHunger > 0 then
        stats[#stats + 1] = "饥饿 +" .. math.floor(def.foodHunger + 0.5)
    end
    if stack:hasDurability() then
        stats[#stats + 1] = string.format("耐久 %d/%d", math.floor((stack.durability or 0) + 0.5),
            math.floor((def.durability or 0) + 0.5))
    end
    self.tooltip.stats:SetText(table.concat(stats, "  "))

    self.tooltip.root:SetVisible(true)
    self.tooltipVisible = true
    self:updateTooltipPosition()
end

---@param index integer
function InventoryUI:showTooltip(index)
    self:showTooltipForStack(self.inventory:getStack(index))
end

---@param i integer
function InventoryUI:showCraftTooltip(i)
    self:showTooltipForStack(self.craftSlots[i]:get())
end

function InventoryUI:showOutputTooltip()
    local _, result = self:getCraftResult()
    self:showTooltipForStack(result)
end

---@param n integer
function InventoryUI:showCreativeTooltip(n)
    local ids = self:getCreativeItems()
    local id = ids[n]
    if not id then
        self.tooltip.root:SetVisible(false)
        return
    end
    self:showTooltipForStack(ItemStack.new(id, 1))
end

function InventoryUI:hideTooltip()
    self.tooltip.root:SetVisible(false)
    self.tooltipVisible = false
end

-- ====================================================================
-- 每帧更新
-- ====================================================================

---@param _dt number
function InventoryUI:update(_dt)
    if not self.isOpen_ then
        return
    end

    if self.cursorStack and self.cursorWidget then
        self.cursorWidget.root:SetStyle({
            left = self.pointerX - SLOT * 0.5,
            top = self.pointerY - SLOT * 0.5,
        })
    end

    if self.tooltipVisible then
        self:updateTooltipPosition()
    end
end

function InventoryUI:updateTooltipPosition()
    self.tooltip.root:SetStyle({
        left = self.pointerX + 16,
        top = self.pointerY + 16,
    })
end

-- ====================================================================
-- 销毁
-- ====================================================================

function InventoryUI:destroy()
    if self.pointerListenerId then
        UI.Input.Off("PointerMove", self.pointerListenerId)
        self.pointerListenerId = nil
    end
    if self.pointerDownListenerId then
        UI.Input.Off("PointerDown", self.pointerDownListenerId)
        self.pointerDownListenerId = nil
    end
    if self.root then
        self.root:Destroy()
        self.root = nil
    end
end

return InventoryUI
