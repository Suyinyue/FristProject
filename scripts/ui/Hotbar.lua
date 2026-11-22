-- ====================================================================
-- ui/Hotbar.lua
-- 快捷栏 UI（物品系统）
--
-- 旧版是"创造模式方块调色板"（11 格分页）；现在改为真正读取背包的
-- 9 格快捷栏，和 Minecraft 生存模式一致：
--   - 数字键 1~9 / 点击切换
--   - 显示物品图标、数量、耐久条
--   - 创造模式的全部方块与物品移到了背包界面的"方块 / 物品"页
-- ====================================================================

local UI = require("urhox-libs/UI/init")
local ItemRegistry = require("items.ItemRegistry")

local SLOT_SIZE = 48
local SLOT_GAP = 6

---@class Hotbar
---@field player Player|nil
---@field root Panel|nil
---@field slots table[]
---@field selectedIndex integer
---@field onBlockSelected function|nil
local Hotbar = {}
Hotbar.__index = Hotbar

local COL_SLOT = { 58, 58, 68, 220 }
local COL_BORDER = { 10, 10, 14, 200 }
local COL_SELECTED = { 255, 210, 80, 255 }

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

---创建快捷栏
---@param player Player|nil
---@return Hotbar
function Hotbar.new(player)
    local self = setmetatable({}, Hotbar)
    self.player = player
    self.root = nil
    self.slots = {}
    self.selectedIndex = 1
    self.onBlockSelected = nil
    return self
end

---创建单个槽位
---@param n integer 1..9
---@return table
function Hotbar:createSlot(n)
    local icon = UI.Label {
        id = "hotbar_icon_" .. n,
        text = "",
        width = 34,
        height = 34,
        borderRadius = 4,
        textAlign = "center",
        fontSize = 22,
        fontColor = { 255, 255, 255, 255 },
        backgroundColor = { 0, 0, 0, 0 },
        pointerEvents = "none",
    }
    local count = UI.Label {
        id = "hotbar_count_" .. n,
        text = "",
        position = "absolute",
        right = 4,
        bottom = 2,
        fontSize = 11,
        fontColor = { 255, 255, 255, 255 },
        pointerEvents = "none",
    }
    local keyLabel = UI.Label {
        id = "hotbar_key_" .. n,
        text = tostring(n),
        position = "absolute",
        right = 5,
        top = 1,
        fontSize = 9,
        fontColor = { 255, 255, 255, 120 },
        pointerEvents = "none",
    }
    local dur = UI.Panel {
        id = "hotbar_dur_" .. n,
        position = "absolute",
        left = 5,
        bottom = 4,
        width = 34,
        height = 3,
        borderRadius = 1,
        backgroundColor = { 80, 220, 80, 255 },
        pointerEvents = "none",
        visible = false,
    }

    local root = UI.Panel {
        id = "hotbar_slot_" .. n,
        width = SLOT_SIZE,
        height = SLOT_SIZE,
        borderRadius = 6,
        backgroundColor = COL_SLOT,
        borderWidth = 1,
        borderColor = COL_BORDER,
        alignItems = "center",
        justifyContent = "center",
        children = { icon, count, keyLabel, dur },
        onPointerDown = function()
            self:selectSlot(n)
            return true
        end,
    }

    return { root = root, icon = icon, count = count, dur = dur }
end

---构建快捷栏 UI
---@return Panel
function Hotbar:build()
    local children = {}
    for n = 1, 9 do
        local widget = self:createSlot(n)
        self.slots[n] = widget
        children[#children + 1] = widget.root
    end

    self.root = UI.Panel {
        id = "hotbar_container",
        position = "absolute",
        bottom = 20,
        left = 0,
        right = 0,
        flexDirection = "column",
        alignItems = "center",
        gap = 6,

        -- 选中物品名称
        UI.Label {
            id = "hotbar_selected_name",
            text = "",
            fontSize = 13,
            fontColor = { 255, 255, 255, 240 },
            textAlign = "center",
            backgroundColor = { 25, 25, 30, 210 },
            borderRadius = 8,
            paddingHorizontal = 16,
            paddingVertical = 5,
        },

        -- 槽位行
        UI.Row {
            id = "hotbar_row",
            gap = SLOT_GAP,
            alignItems = "center",
            justifyContent = "center",
            backgroundColor = { 0, 0, 0, 150 },
            borderRadius = 10,
            padding = 8,
            children = children,
        },
    }

    self:update()
    return self.root
end

---刷新单个槽位
---@param widget table
---@param stack ItemStack|nil
---@param selected boolean
function Hotbar:refreshSlot(widget, stack, selected)
    widget.root:SetStyle({
        borderColor = selected and COL_SELECTED or COL_BORDER,
        borderWidth = selected and 3 or 1,
    })

    if not stack or stack.count <= 0 then
        widget.icon:SetText("")
        widget.icon:SetStyle({ backgroundColor = { 0, 0, 0, 0 }, backgroundImage = false })
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
        })
    elseif stack:isBlock() then
        widget.icon:SetText("")
        widget.icon:SetStyle({
            backgroundColor = def and rgba(def.color) or { 150, 150, 150, 255 },
            backgroundImage = false,
        })
    else
        widget.icon:SetText(def and def.icon or "?")
        widget.icon:SetStyle({
            backgroundColor = { 0, 0, 0, 0 },
            backgroundImage = false,
            fontColor = def and rgba({
                math.min(1, def.color[1] * 1.25 + 0.20),
                math.min(1, def.color[2] * 1.25 + 0.20),
                math.min(1, def.color[3] * 1.25 + 0.20),
            }) or { 255, 255, 255, 255 },
        })
    end

    widget.count:SetText(stack.count > 1 and tostring(stack.count) or "")

    if stack:hasDurability() and stack:getDurabilityFraction() < 0.999 then
        local frac = stack:getDurabilityFraction()
        widget.dur:SetVisible(true)
        local w = math.max(2, math.floor((SLOT_SIZE - 10) * frac))
        local color = { 80, 220, 80, 255 }
        if frac < 0.25 then color = { 230, 70, 60, 255 }
        elseif frac < 0.5 then color = { 240, 200, 60, 255 } end
        widget.dur:SetStyle({ width = w, backgroundColor = color })
    else
        widget.dur:SetVisible(false)
    end
end

---刷新整个快捷栏
function Hotbar:update()
    if not self.root then
        return
    end

    local inventory = self.player and self.player:getInventory() or nil
    local selected = self.player and self.player:getSelectedSlotIndex() or self.selectedIndex

    for n = 1, 9 do
        local stack = inventory and inventory:getHotbarStack(n) or nil
        self:refreshSlot(self.slots[n], stack, n == selected)
    end

    local nameLabel = self.root:FindById("hotbar_selected_name")
    if nameLabel then
        local stack = inventory and inventory:getHotbarStack(selected) or nil
        nameLabel:SetText(stack and stack:getName() or "空")
    end
end

---每帧轻量检查：背包有变化才刷新
function Hotbar:tick()
    if not self.player or not self.player.getInventory then
        return
    end
    local inventory = self.player:getInventory()
    if inventory and inventory:isDirty() then
        self:update()
    end
end

---选择槽位
---@param index integer 1..9
function Hotbar:selectSlot(index)
    index = math.max(1, math.min(9, math.floor(index or 1)))
    self.selectedIndex = index

    if self.player then
        self.player:selectSlot(index)
    end
    if self.onBlockSelected and self.player then
        self.onBlockSelected(self.player:getSelectedBlockType())
    end

    self:update()
end

---兼容旧接口（旧版分页）
function Hotbar:nextPage() end
function Hotbar:prevPage() end

---获取当前选中的方块类型（不是方块物品时返回 nil 或 AIR，由 player 决定）
---@return number|nil
function Hotbar:getSelectedBlock()
    if self.player then
        return self.player:getSelectedBlockType()
    end
    return nil
end

---@return Panel|nil
function Hotbar:getRoot()
    return self.root
end

return Hotbar
