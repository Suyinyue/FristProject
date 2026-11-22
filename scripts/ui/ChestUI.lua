-- ====================================================================
-- ui/ChestUI.lua
-- 箱子界面：箱子 27 格 + 玩家背包（主背包 + 快捷栏），支持拖拽 / Shift 转移
-- ====================================================================

local UI = require("urhox-libs/UI/init")
local ContainerSlots = require("ui.ContainerSlots")

local COL_PANEL = { 38, 38, 46, 248 }
local GAP = 4

---@class ChestUI
---@field manager ContainerManager
---@field player Player
---@field playerController table|nil
---@field root Panel|nil
---@field isOpen_ boolean
---@field coordKey string|nil
---@field chestWidgets table<integer, table>
---@field playerWidgets table<integer, table>
---@field cursor table
---@field pointerX number
---@field pointerY number
---@field pointerListenerId table|nil
---@field pointerDownListenerId table|nil
local ChestUI = {}
ChestUI.__index = ChestUI

---@param manager ContainerManager
---@param player Player
---@param options table|nil
---@return ChestUI
function ChestUI.new(manager, player, options)
    local self = setmetatable({}, ChestUI)
    options = options or {}
    self.manager = manager
    self.player = player
    self.playerController = options.playerController
    self.root = nil
    self.isOpen_ = false
    self.coordKey = nil
    self.chestWidgets = {}
    self.playerWidgets = {}
    self.cursor = { stack = nil, widget = nil }
    self.pointerX = 0
    self.pointerY = 0
    return self
end

---把物品堆放进箱子槽位（先合并再找空槽）
---@param stack ItemStack
---@param slots InventorySlot[]
---@return ItemStack|nil
local function addToSlots(stack, slots)
    for _, slot in ipairs(slots) do
        local cur = slot:get()
        if cur and cur:canMergeWith(stack) then
            cur:mergeFrom(stack)
            if stack.count <= 0 then return nil end
        end
    end
    for _, slot in ipairs(slots) do
        if slot:isEmpty() then
            slot:set(stack)
            return nil
        end
    end
    return stack
end

---@return Panel
function ChestUI:build()
    if self.root then
        return self.root
    end
    local self_ = self

    local closeBtn = UI.Label {
        text = "关闭", fontSize = 12, fontColor = { 255, 255, 255, 235 },
        backgroundColor = { 80, 70, 70, 235 }, borderRadius = 6,
        paddingHorizontal = 10, paddingVertical = 5, pointerEvents = "auto",
        onClick = function() self_:close() end,
    }

    -- 箱子 27 格
    local chestRows = {}
    for row = 1, 3 do
        local children = {}
        for col = 1, 9 do
            local i = (row - 1) * 9 + col
            local w = ContainerSlots.createSlotWidget("chest_" .. i,
                function(event) self_:onChestClick(i, event) end)
            self.chestWidgets[i] = w
            children[#children + 1] = w.root
        end
        chestRows[#chestRows + 1] = UI.Row { gap = GAP, children = children }
    end

    -- 玩家背包（主 27 + 快捷 9）
    local playerRows = {}
    for row = 1, 4 do
        local children = {}
        for col = 1, 9 do
            local n = (row - 1) * 9 + col
            local index = (row == 4) and (28 + col - 1) or n
            local w = ContainerSlots.createSlotWidget("chest_player_" .. n,
                function(event) self_:onPlayerClick(index, event) end)
            self.playerWidgets[index] = w
            children[#children + 1] = w.root
        end
        playerRows[#playerRows + 1] = UI.Row { gap = GAP, children = children }
    end

    local panel = UI.Panel {
        id = "chest_panel",
        width = 430,
        backgroundColor = COL_PANEL,
        borderRadius = 14,
        padding = 14,
        flexDirection = "column",
        gap = 8,
        children = {
            UI.Row {
                width = "100%", justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Label { text = "箱子", fontSize = 18, fontColor = { 255, 255, 255, 255 } },
                    closeBtn,
                },
            },
            UI.Column { gap = GAP, children = chestRows },
            UI.Label { text = "玩家背包", fontSize = 12, fontColor = { 210, 210, 220, 230 } },
            UI.Column { gap = GAP, children = playerRows },
        },
    }

    self.cursor.widget = ContainerSlots.buildCursor("chest_cursor")

    self.root = UI.Panel {
        id = "chest_root",
        position = "absolute", left = 0, top = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 140 },
        justifyContent = "center", alignItems = "center",
        pointerEvents = "auto", visible = false,
        children = { panel, self.cursor.widget.root },
    }

    self.pointerListenerId = UI.Input.On("PointerMove", function(event)
        self_.pointerX = event.x
        self_.pointerY = event.y
    end)
    self.pointerDownListenerId = UI.Input.On("PointerDown", function(event)
        self_.pointerX = event.x
        self_.pointerY = event.y
    end)

    return self.root
end

---@param x integer
---@param y integer
---@param z integer
function ChestUI:open(x, y, z)
    if not self.root then return end
    self.coordKey = x .. "," .. y .. "," .. z
    self.root:SetVisible(true)
    self.isOpen_ = true
    ContainerSlots.applyMouseMode(self.playerController, true)
    self:refresh()
end

function ChestUI:close()
    if not self.root or not self.isOpen_ then return end
    self:returnCursor()
    self.root:SetVisible(false)
    self.isOpen_ = false
    self.coordKey = nil
    ContainerSlots.applyMouseMode(self.playerController, false)
end

---@return boolean
function ChestUI:isOpen()
    return self.isOpen_
end

---当前箱子数据
---@return table|nil
function ChestUI:getContainer()
    if not self.coordKey then return nil end
    local x, y, z = self.coordKey:match("(-?%d+),(-?%d+),(-?%d+)")
    return self.manager:getContainer(tonumber(x), tonumber(y), tonumber(z))
end

function ChestUI:refresh()
    local c = self:getContainer()
    if not c then
        self:close()
        return
    end
    for i = 1, 27 do
        ContainerSlots.refreshSlotWidget(self.chestWidgets[i], c.slots[i]:get(), false, false)
    end
    local inv = self.player:getInventory()
    for i = 1, 27 do
        ContainerSlots.refreshSlotWidget(self.playerWidgets[i], inv:getStack(i), false, false)
    end
    for n = 1, 9 do
        local index = inv:getHotbarIndex(n)
        ContainerSlots.refreshSlotWidget(self.playerWidgets[index], inv:getStack(index), false, false)
    end
    ContainerSlots.refreshCursor(self.cursor)
end

---@param i integer
---@param event PointerEvent
function ChestUI:onChestClick(i, event)
    local c = self:getContainer()
    if not c then return end
    if input:GetQualifierDown(QUAL_SHIFT) then
        local stack = c.slots[i]:take(c.slots[i]:getCount())
        if stack then
            local left = self.player:getInventory():addStack(stack)
            if left then c.slots[i]:set(left) end
            self.player:getInventory():markDirty()
        end
    else
        ContainerSlots.click(self.cursor, c.slots[i], (event and event.button) or 0)
    end
    self:refresh()
end

---@param index integer 玩家背包槽位
---@param event PointerEvent
function ChestUI:onPlayerClick(index, event)
    local c = self:getContainer()
    if not c then return end
    local inv = self.player:getInventory()
    if input:GetQualifierDown(QUAL_SHIFT) then
        local stack = inv:getStack(index)
        if stack then
            inv:setStack(index, nil)
            local left = addToSlots(stack, c.slots)
            if left then inv:setStack(index, left) end
            inv:markDirty()
        end
    else
        ContainerSlots.click(self.cursor, inv:getSlot(index), (event and event.button) or 0)
        inv:markDirty()
    end
    self:refresh()
end

function ChestUI:returnCursor()
    local stack = self.cursor.stack
    self.cursor.stack = nil
    if stack then
        local left = self.player:getInventory():addStack(stack)
        if left and left.count > 0 then
            local drop = self.manager.dropSystem
            if drop then
                drop:spawn(left, self.player:getPosition() + Vector3(0, 2, 0))
            end
        end
        self.player:getInventory():markDirty()
    end
end

---@param _dt number
function ChestUI:update(_dt)
    if not self.isOpen_ then return end
    self:refresh()
    if self.cursor.stack and self.cursor.widget then
        self.cursor.widget.root:SetStyle({
            left = self.pointerX - ContainerSlots.SLOT * 0.5,
            top = self.pointerY - ContainerSlots.SLOT * 0.5,
        })
    end
end

function ChestUI:destroy()
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

return ChestUI
