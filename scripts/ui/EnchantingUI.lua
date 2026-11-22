-- ====================================================================
-- ui/EnchantingUI.lua
-- 附魔台界面：物品槽 + 青金石槽 + 3 个随机附魔选项
-- ====================================================================

local UI = require("urhox-libs/UI/init")
local ItemStack = require("items.ItemStack")
local InventorySlot = require("items.InventorySlot")
local ContainerSlots = require("ui.ContainerSlots")

local COL_PANEL = { 38, 38, 46, 248 }
local COL_BTN = { 55, 55, 66, 235 }

---@class EnchantingUI
---@field manager EnchantingManager
---@field player Player
---@field playerController table|nil
---@field root Panel|nil
---@field isOpen_ boolean
---@field itemSlot InventorySlot
---@field lapisSlot InventorySlot
---@field itemWidget table|nil
---@field lapisWidget table|nil
---@field optionButtons Label[]
---@field options table[]
---@field hint Label|nil
---@field cursor table
---@field pointerX number
---@field pointerY number
---@field pointerListenerId table|nil
---@field pointerDownListenerId table|nil
local EnchantingUI = {}
EnchantingUI.__index = EnchantingUI

---@param manager EnchantingManager
---@param player Player
---@param options table|nil
---@return EnchantingUI
function EnchantingUI.new(manager, player, options)
    local self = setmetatable({}, EnchantingUI)
    options = options or {}
    self.manager = manager
    self.player = player
    self.playerController = options.playerController
    self.root = nil
    self.isOpen_ = false
    self.itemSlot = InventorySlot.new(nil)
    self.lapisSlot = InventorySlot.new(nil)
    self.itemWidget = nil
    self.lapisWidget = nil
    self.optionButtons = {}
    self.options = {}
    self.hint = nil
    self.cursor = { stack = nil, widget = nil }
    self.pointerX = 0
    self.pointerY = 0
    return self
end

---@return Panel
function EnchantingUI:build()
    if self.root then return self.root end
    local self_ = self

    local closeBtn = UI.Label {
        text = "关闭", fontSize = 12, fontColor = { 255, 255, 255, 235 },
        backgroundColor = { 80, 70, 70, 235 }, borderRadius = 6,
        paddingHorizontal = 10, paddingVertical = 5, pointerEvents = "auto",
        onClick = function() self_:close() end,
    }

    self.itemWidget = ContainerSlots.createSlotWidget("enchant_item",
        function(event) self_:onItemClick(event) end)
    self.lapisWidget = ContainerSlots.createSlotWidget("enchant_lapis",
        function(event) self_:onLapisClick(event) end)

    local optButtons = {}
    for i = 1, 3 do
        local btn = UI.Label {
            text = "",
            fontSize = 12,
            fontColor = { 235, 235, 245, 235 },
            backgroundColor = COL_BTN,
            borderRadius = 6,
            paddingHorizontal = 10,
            paddingVertical = 8,
            textAlign = "center",
            pointerEvents = "auto",
            onClick = function() self_:onOptionClick(i) end,
        }
        self.optionButtons[i] = btn
        optButtons[#optButtons + 1] = btn
    end

    self.hint = UI.Label { text = "", fontSize = 10, fontColor = { 200, 200, 210, 220 } }

    local panel = UI.Panel {
        id = "enchant_panel",
        width = 340,
        backgroundColor = COL_PANEL,
        borderRadius = 14,
        padding = 14,
        flexDirection = "column",
        gap = 10,
        children = {
            UI.Row {
                width = "100%", justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Label { text = "附魔台", fontSize = 18, fontColor = { 255, 255, 255, 255 } },
                    closeBtn,
                },
            },
            UI.Row {
                gap = 8, alignItems = "center",
                children = {
                    self.itemWidget.root,
                    UI.Label { text = "物品", fontSize = 12, fontColor = { 210, 210, 220, 230 } },
                    self.lapisWidget.root,
                    UI.Label { text = "青金石", fontSize = 12, fontColor = { 210, 210, 220, 230 } },
                },
            },
            UI.Column { gap = 6, children = optButtons },
            self.hint,
        },
    }

    self.cursor.widget = ContainerSlots.buildCursor("enchant_cursor")

    self.root = UI.Panel {
        id = "enchant_root",
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
function EnchantingUI:open(x, y, z)
    if not self.root then return end
    self.coordX, self.coordY, self.coordZ = x, y, z
    self.root:SetVisible(true)
    self.isOpen_ = true
    ContainerSlots.applyMouseMode(self.playerController, true)
    self:refresh()
end

function EnchantingUI:close()
    if not self.root or not self.isOpen_ then return end
    self:returnSlot(self.itemSlot)
    self:returnSlot(self.lapisSlot)
    self:returnCursor()
    self.root:SetVisible(false)
    self.isOpen_ = false
    ContainerSlots.applyMouseMode(self.playerController, false)
end

---@return boolean
function EnchantingUI:isOpen()
    return self.isOpen_
end

function EnchantingUI:refresh()
    local item = self.itemSlot:get()
    ContainerSlots.refreshSlotWidget(self.itemWidget, item, false, false)
    ContainerSlots.refreshSlotWidget(self.lapisWidget, self.lapisSlot:get(), false, false)

    -- 重新掷选项
    self.options = {}
    local lvl = self.manager:tableLevel(self.coordX or 0, self.coordY or 0, self.coordZ or 0)
    if item then
        for _ = 1, 3 do
            self.options[#self.options + 1] = self.manager:rollOption(item, lvl)
        end
    end

    for i = 1, 3 do
        local opt = self.options[i]
        local btn = self.optionButtons[i]
        if opt then
            btn:SetText(string.format("%s %s（%d 级）", opt.name,
                self:levelText(opt.level), opt.cost))
        else
            btn:SetText("—")
        end
    end

    self.hint:SetText("当前附魔台等级 Lv." .. lvl .. "，需要消耗等级和青金石")
    ContainerSlots.refreshCursor(self.cursor)
end

---@param level integer
---@return string
function EnchantingUI:levelText(level)
    local roman = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }
    return roman[level] or tostring(level)
end

---@param event PointerEvent
function EnchantingUI:onItemClick(event)
    ContainerSlots.click(self.cursor, self.itemSlot, (event and event.button) or 0)
    self:refresh()
end

---@param event PointerEvent
function EnchantingUI:onLapisClick(event)
    ContainerSlots.click(self.cursor, self.lapisSlot, (event and event.button) or 0)
    self:refresh()
end

---@param i integer
function EnchantingUI:onOptionClick(i)
    local opt = self.options[i]
    if not opt then return end
    local item = self.itemSlot:get()
    local lapis = self.lapisSlot:get()
    if not item or not lapis or lapis.count <= 0 then
        self.hint:SetText("需要放入物品和青金石")
        return
    end
    if not self.player:spendLevels(opt.cost) then
        self.hint:SetText("经验等级不足")
        return
    end
    lapis.count = lapis.count - 1
    if lapis.count <= 0 then self.lapisSlot:clear() end
    self.manager:apply(item, opt.id, opt.level)
    self.player:getInventory():markDirty()
    self:refresh()
    self.hint:SetText(string.format("附魔成功：%s %s", opt.name, self:levelText(opt.level)))
end

---把槽位内容还回玩家背包
---@param slot InventorySlot
function EnchantingUI:returnSlot(slot)
    local stack = slot:take(slot:getCount())
    if not stack then return end
    local left = self.player:getInventory():addStack(stack)
    if left and left.count > 0 then
        local drop = self.manager.dropSystem
        if drop then
            drop:spawn(left, self.player:getPosition() + Vector3(0, 2, 0))
        end
    end
    self.player:getInventory():markDirty()
end

function EnchantingUI:returnCursor()
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
function EnchantingUI:update(_dt)
    if not self.isOpen_ then return end
    if self.cursor.stack and self.cursor.widget then
        self.cursor.widget.root:SetStyle({
            left = self.pointerX - ContainerSlots.SLOT * 0.5,
            top = self.pointerY - ContainerSlots.SLOT * 0.5,
        })
    end
end

function EnchantingUI:destroy()
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

return EnchantingUI
