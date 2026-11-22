-- ====================================================================
-- ui/FurnaceUI.lua
-- 熔炉界面：材料 / 燃料 / 成品 三槽 + 进度 + 火焰
-- ====================================================================

local UI = require("urhox-libs/UI/init")
local Config = require("config.GameConfig")
local ItemStack = require("items.ItemStack")
local ContainerSlots = require("ui.ContainerSlots")

local COL_PANEL = { 38, 38, 46, 248 }

---@class FurnaceUI
---@field manager FurnaceManager
---@field player Player
---@field playerController table|nil
---@field root Panel|nil
---@field isOpen_ boolean
---@field coordKey string|nil
---@field inputWidget table|nil
---@field fuelWidget table|nil
---@field outputWidget table|nil
---@field progressLabel Label|nil
---@field flameLabel Label|nil
---@field cursor table
---@field pointerX number
---@field pointerY number
---@field pointerListenerId table|nil
---@field pointerDownListenerId table|nil
local FurnaceUI = {}
FurnaceUI.__index = FurnaceUI

---@param manager FurnaceManager
---@param player Player
---@param options table|nil { playerController = PlayerController }
---@return FurnaceUI
function FurnaceUI.new(manager, player, options)
    local self = setmetatable({}, FurnaceUI)
    options = options or {}
    self.manager = manager
    self.player = player
    self.playerController = options.playerController
    self.root = nil
    self.isOpen_ = false
    self.coordKey = nil
    self.inputWidget = nil
    self.fuelWidget = nil
    self.outputWidget = nil
    self.progressLabel = nil
    self.flameLabel = nil
    self.cursor = { stack = nil, widget = nil }
    self.pointerX = 0
    self.pointerY = 0
    return self
end

---@return Panel
function FurnaceUI:build()
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

    self.inputWidget = ContainerSlots.createSlotWidget("furnace_input",
        function(event) self_:onInputClick(event) end)
    self.fuelWidget = ContainerSlots.createSlotWidget("furnace_fuel",
        function(event) self_:onFuelClick(event) end)
    self.outputWidget = ContainerSlots.createSlotWidget("furnace_output",
        function(event) self_:onOutputClick(event) end)

    self.progressLabel = UI.Label { text = "", fontSize = 11, fontColor = { 255, 220, 140, 255 } }
    self.flameLabel = UI.Label { text = "○", fontSize = 18, fontColor = { 160, 160, 170, 255 } }

    local panel = UI.Panel {
        id = "furnace_panel",
        width = 320,
        backgroundColor = COL_PANEL,
        borderRadius = 14,
        padding = 14,
        flexDirection = "column",
        gap = 10,
        children = {
            UI.Row {
                width = "100%",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label { text = "熔炉", fontSize = 18, fontColor = { 255, 255, 255, 255 } },
                    closeBtn,
                },
            },
            UI.Row {
                gap = 12,
                alignItems = "center",
                children = {
                    self.inputWidget.root,
                    UI.Label { text = "→", fontSize = 22, fontColor = { 230, 230, 240, 220 } },
                    self.outputWidget.root,
                },
            },
            self.progressLabel,
            UI.Row {
                gap = 8,
                alignItems = "center",
                children = {
                    self.fuelWidget.root,
                    self.flameLabel,
                    UI.Label { text = "燃料", fontSize = 12, fontColor = { 210, 210, 220, 230 } },
                },
            },
        },
    }

    self.cursor.widget = ContainerSlots.buildCursor("furnace_cursor")

    self.root = UI.Panel {
        id = "furnace_root",
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 140 },
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "auto",
        visible = false,
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
function FurnaceUI:open(x, y, z)
    if not self.root then
        return
    end
    self.coordKey = x .. "," .. y .. "," .. z
    self.root:SetVisible(true)
    self.isOpen_ = true
    ContainerSlots.applyMouseMode(self.playerController, true)
    self:refresh()
end

function FurnaceUI:close()
    if not self.root or not self.isOpen_ then
        return
    end
    self:returnCursor()
    self.root:SetVisible(false)
    self.isOpen_ = false
    self.coordKey = nil
    ContainerSlots.applyMouseMode(self.playerController, false)
end

---@return boolean
function FurnaceUI:isOpen()
    return self.isOpen_
end

---当前熔炉数据
---@return table|nil
function FurnaceUI:getFurnace()
    if not self.coordKey then
        return nil
    end
    local x, y, z = self.coordKey:match("(-?%d+),(-?%d+),(-?%d+)")
    return self.manager:getFurnace(tonumber(x), tonumber(y), tonumber(z))
end

function FurnaceUI:refresh()
    local f = self:getFurnace()
    if not f then
        self:close()
        return
    end
    ContainerSlots.refreshSlotWidget(self.inputWidget, f.input:get(), false, false)
    ContainerSlots.refreshSlotWidget(self.fuelWidget, f.fuel:get(), false, false)
    ContainerSlots.refreshSlotWidget(self.outputWidget, f.output:get(), false, false)

    local cfg = Config.Furnace
    local pct = math.min(100, math.floor((f.progress / cfg.COOK_TIME) * 100))
    self.progressLabel:SetText("进度 " .. pct .. "%")
    if f.burnTimeLeft > 0 then
        self.flameLabel:SetText("🔥")
    else
        self.flameLabel:SetText("○")
    end
    ContainerSlots.refreshCursor(self.cursor)
end

---@param event PointerEvent
function FurnaceUI:onInputClick(event)
    local f = self:getFurnace()
    if not f then return end
    local shift = input:GetQualifierDown(QUAL_SHIFT)
    if shift then
        self:transferToPlayer(f.input)
    else
        ContainerSlots.click(self.cursor, f.input, (event and event.button) or 0)
    end
    self:refresh()
end

---@param event PointerEvent
function FurnaceUI:onFuelClick(event)
    local f = self:getFurnace()
    if not f then return end
    local shift = input:GetQualifierDown(QUAL_SHIFT)
    if shift then
        self:transferToPlayer(f.fuel)
    else
        ContainerSlots.click(self.cursor, f.fuel, (event and event.button) or 0)
    end
    self:refresh()
end

---成品槽：点击取出（不可放入）
---@param event PointerEvent
function FurnaceUI:onOutputClick(event)
    local f = self:getFurnace()
    if not f then return end
    local stack = f.output:get()
    if not stack then
        return
    end
    -- 优先放进光标
    if not self.cursor.stack then
        self.cursor.stack = f.output:take(f.output:getCount())
    elseif self.cursor.stack:isSameInstance(stack) then
        local taken = f.output:take(self.cursor.stack:getRemainingSpace())
        if taken then
            self.cursor.stack:mergeFrom(taken)
        end
    else
        self:transferToPlayer(f.output)
    end
    self:refresh()
end

---把槽位内容转移到玩家背包
---@param slot InventorySlot
function FurnaceUI:transferToPlayer(slot)
    local stack = slot:take(slot:getCount())
    if not stack then return end
    local left = self.player:getInventory():addStack(stack)
    if left and left.count > 0 then
        slot:set(left)
    end
    self.player:getInventory():markDirty()
end

function FurnaceUI:returnCursor()
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
function FurnaceUI:update(_dt)
    if not self.isOpen_ then
        return
    end
    self:refresh()
    if self.cursor.stack and self.cursor.widget then
        self.cursor.widget.root:SetStyle({
            left = self.pointerX - ContainerSlots.SLOT * 0.5,
            top = self.pointerY - ContainerSlots.SLOT * 0.5,
        })
    end
end

function FurnaceUI:destroy()
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

return FurnaceUI
