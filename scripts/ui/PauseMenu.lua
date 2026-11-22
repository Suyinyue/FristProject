-- ====================================================================
-- ui/PauseMenu.lua
-- ESC 暂停菜单 + 设置界面 + 加载/删除存档 + 主菜单入口
--
-- 所有按钮都连接真实逻辑：
--   返回游戏 / 设置 / 保存游戏 / 加载游戏 / 删除存档 / 返回主菜单 / 退出
-- 设置由 save/SettingsManager 持久化；存档由 save/SaveManager 读写。
-- ====================================================================

local UI = require("urhox-libs/UI/init")
local SettingsManager = require("save.SettingsManager")
local SaveManager = require("save.SaveManager")

local PANEL_BG = { 26, 30, 40, 245 }
local PANEL_BORDER = { 90, 105, 130, 200 }
local TITLE_COLOR = { 235, 240, 250, 255 }
local SUB_COLOR = { 170, 185, 205, 230 }
local STATUS_COLOR = { 255, 220, 120, 255 }

---@class PauseMenu
---@field ctx table
---@field root Panel|nil
---@field pausePanel Panel|nil
---@field settingsPanel Panel|nil
---@field loadPanel Panel|nil
---@field mainPanel Panel|nil
---@field statusLabel Label|nil
---@field loadListContent Panel|nil
---@field onVisibilityChanged fun(visible: boolean)|nil
---@field deleteArmed table<string, boolean>
---@field open_ boolean
local PauseMenu = {}
PauseMenu.__index = PauseMenu

---@param ctx table { player, chunkStreamer, uiManager, onExit, buildSaveContext }
---@return PauseMenu
function PauseMenu.new(ctx)
    local self = setmetatable({}, PauseMenu)
    self.ctx = ctx
    self.deleteArmed = {}
    self.open_ = false
    self:build()
    return self
end

-- ====================================================================
-- 小工具
-- ====================================================================

---@param text string
---@param onClick function|nil
---@param variant string|nil
---@return Button
local function button(text, onClick, variant)
    return UI.Button {
        text = text,
        width = 280,
        height = 42,
        variant = variant or "secondary",
        onClick = onClick or function() end,
    }
end

---@param text string
---@param size integer|nil
---@param color table|nil
---@return Label
local function label(text, size, color)
    return UI.Label {
        text = text,
        fontSize = size or 14,
        fontColor = color or TITLE_COLOR,
    }
end

---@param text string
---@param w integer|nil
---@return Label
local function rowLabel(text, w)
    return UI.Label {
        text = text,
        width = w or 150,
        fontSize = 13,
        fontColor = SUB_COLOR,
    }
end

---@param child Widget
---@return Panel
local function row(child)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        gap = 12,
        children = { child },
    }
end

---@param title string
---@param body Widget
---@return Panel
local function section(title, body)
    return UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 6,
        marginTop = 10,
        children = {
            label(title, 15, { 120, 200, 255, 255 }),
            body,
        },
    }
end

-- ====================================================================
-- 构建
-- ====================================================================

function PauseMenu:build()
    local settings = SettingsManager.data

    self.statusLabel = label("", 12, STATUS_COLOR)

    -- ---------------- 暂停主面板 ----------------
    self.pausePanel = UI.Panel {
        width = 420,
        padding = 26,
        gap = 12,
        backgroundColor = PANEL_BG,
        borderColor = PANEL_BORDER,
        borderWidth = 1,
        borderRadius = 12,
        alignItems = "center",
        children = {
            label("游戏暂停", 26),
            label("ESC 返回游戏", 12, SUB_COLOR),
            button("返回游戏", function() self:hide() end, "primary"),
            button("设置", function() self:showSettings() end),
            button("保存游戏", function() self:onSave() end),
            button("加载游戏", function() self:showLoad() end),
            button("返回主菜单", function() self:showMainMenu() end),
            button("退出游戏", function()
                if self.ctx.onExit then self.ctx.onExit() end
            end),
        },
    }

    -- ---------------- 设置面板 ----------------
    local audioRows = UI.Panel {
        width = "100%", flexDirection = "column", gap = 8,
        children = {
            self:makeSliderRow("主音量", settings.audio.master * 100, 0, 100, 1, function(v)
                settings.audio.master = v / 100
                self:applySettings(false)
            end, function(v) return string.format("%d%%", math.floor(v + 0.5)) end),
            self:makeSliderRow("背景音乐", settings.audio.music * 100, 0, 100, 1, function(v)
                settings.audio.music = v / 100
                self:applySettings(false)
            end, function(v) return string.format("%d%%", math.floor(v + 0.5)) end),
            self:makeSliderRow("音效", settings.audio.sfx * 100, 0, 100, 1, function(v)
                settings.audio.sfx = v / 100
                self:applySettings(false)
            end, function(v) return string.format("%d%%", math.floor(v + 0.5)) end),
        },
    }

    local videoRows = UI.Panel {
        width = "100%", flexDirection = "column", gap = 8,
        children = {
            self:makeDropdownRow("分辨率（暂不支持运行时修改）", {
                { value = "1280x720", label = "1280 × 720" },
                { value = "1600x900", label = "1600 × 900" },
                { value = "1920x1080", label = "1920 × 1080" },
            }, settings.video.resolution, function(v)
                settings.video.resolution = v
            end),
            self:makeToggleRow("全屏", settings.video.fullscreen, function(v)
                settings.video.fullscreen = v
                self:applySettings(false)
            end),
            self:makeSliderRow("视野 FOV", settings.video.fov, 60, 110, 1, function(v)
                settings.video.fov = v
                self:applySettings(false)
            end, function(v) return string.format("%d", math.floor(v + 0.5)) end),
            self:makeSliderRow("渲染距离", settings.video.renderDistance, 2, 12, 1, function(v)
                settings.video.renderDistance = math.floor(v + 0.5)
                self:applySettings(false)
            end, function(v) return string.format("%d 区块", math.floor(v + 0.5)) end),
            self:makeDropdownRow("画面质量", {
                { value = "low", label = "低" },
                { value = "medium", label = "中" },
                { value = "high", label = "高" },
            }, settings.video.quality, function(v)
                settings.video.quality = v
                self:applySettings(false)
            end),
        },
    }

    local gameRows = UI.Panel {
        width = "100%", flexDirection = "column", gap = 8,
        children = {
            self:makeSliderRow("鼠标灵敏度", settings.game.mouseSensitivity * 100, 2, 40, 1, function(v)
                settings.game.mouseSensitivity = v / 100
                self:applySettings(false)
            end, function(v) return string.format("%.2f", v / 100) end),
            self:makeToggleRow("反转 Y 轴", settings.game.invertY, function(v)
                settings.game.invertY = v
                self:applySettings(false)
            end),
            self:makeToggleRow("显示 FPS", settings.game.showFps, function(v)
                settings.game.showFps = v
                self:applySettings(false)
            end),
            self:makeToggleRow("自动保存", settings.game.autosave, function(v)
                settings.game.autosave = v
                self:applySettings(false)
            end),
            self:makeSliderRow("自动保存间隔", settings.game.autosaveInterval, 60, 900, 30, function(v)
                settings.game.autosaveInterval = math.floor(v + 0.5)
                self:applySettings(false)
            end, function(v) return string.format("%d 秒", math.floor(v + 0.5)) end),
        },
    }

    local controlRows = UI.Panel {
        width = "100%", flexDirection = "column", gap = 4,
        children = {
            row(label("前进 / 后退 / 左移 / 右移：W / S / A / D", 12)),
            row(label("跳跃：Space    挖掘：鼠标左键    放置：鼠标右键", 12)),
            row(label("背包：E    菜单：ESC    丢弃：Q", 12)),
            row(label("（按键重绑定暂未开放）", 12, SUB_COLOR)),
        },
    }

    local settingsContent = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 4,
        padding = 4,
        children = {
            section("音频", audioRows),
            section("画面", videoRows),
            section("游戏", gameRows),
            section("控制", controlRows),
        },
    }

    local settingsScroll = UI.ScrollView {
        width = "100%",
        height = 440,
        scrollY = true,
        showScrollbar = true,
        scrollbarInteractive = true,
    }
    settingsScroll:AddChild(settingsContent)

    self.settingsPanel = UI.Panel {
        width = 620,
        padding = 22,
        gap = 10,
        backgroundColor = PANEL_BG,
        borderColor = PANEL_BORDER,
        borderWidth = 1,
        borderRadius = 12,
        children = {
            label("设置", 24),
            settingsScroll,
            label("分辨率在本引擎无法运行时修改；其余选项实时生效。", 11, SUB_COLOR),
            UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "space-between", gap = 10,
                children = {
                    button("应用并保存", function() self:onApplySettings() end, "primary"),
                    button("恢复默认", function() self:onResetSettings() end),
                    button("返回", function() self:showPause() end),
                },
            },
            self.statusLabel,
        },
    }

    -- ---------------- 加载面板 ----------------
    self.loadListContent = UI.Panel {
        width = "100%",
        flexDirection = "column",
        gap = 6,
    }
    local loadScroll = UI.ScrollView {
        width = "100%",
        height = 420,
        scrollY = true,
        showScrollbar = true,
        scrollbarInteractive = true,
    }
    loadScroll:AddChild(self.loadListContent)
    self.loadPanel = UI.Panel {
        width = 640,
        padding = 22,
        gap = 10,
        backgroundColor = PANEL_BG,
        borderColor = PANEL_BORDER,
        borderWidth = 1,
        borderRadius = 12,
        children = {
            label("加载世界", 24),
            loadScroll,
            UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "space-between", gap = 10,
                children = {
                    button("刷新列表", function() self:refreshLoadList() end),
                    button("返回", function() self:showPause() end),
                },
            },
            self.statusLabel,
        },
    }

    -- ---------------- 主菜单 ----------------
    self.mainPanel = UI.Panel {
        width = 420,
        padding = 26,
        gap = 12,
        backgroundColor = PANEL_BG,
        borderColor = PANEL_BORDER,
        borderWidth = 1,
        borderRadius = 12,
        alignItems = "center",
        children = {
            label("主菜单", 28),
            label("当前世界已暂停", 12, SUB_COLOR),
            button("继续游戏", function() self:hide() end, "primary"),
            button("加载存档", function() self:showLoad() end),
            button("退出游戏", function()
                if self.ctx.onExit then self.ctx.onExit() end
            end),
        },
    }

    self.root = UI.Panel {
        id = "pause_root",
        position = "absolute",
        left = 0,
        top = 0,
        width = "100%",
        height = "100%",
        backgroundColor = { 4, 6, 10, 190 },
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "auto",
        zIndex = 2000,
        visible = false,
        children = { self.pausePanel, self.settingsPanel, self.loadPanel, self.mainPanel },
    }
    self.settingsPanel:SetVisible(false)
    self.loadPanel:SetVisible(false)
    self.mainPanel:SetVisible(false)

    local rootWidget = self.ctx.uiManager and self.ctx.uiManager:getRoot()
    if rootWidget then
        rootWidget:AddChild(self.root)
    end
end

-- ====================================================================
-- 设置行构造
-- ====================================================================

---@param text string
---@param value number
---@param min number
---@param max number
---@param step number
---@param onChange fun(v: number)
---@param format fun(v: number): string
---@return Panel
function PauseMenu:makeSliderRow(text, value, min, max, step, onChange, format)
    local valueLabel = label(format(value), 12, TITLE_COLOR)
    local slider
    slider = UI.Slider {
        width = 220,
        min = min,
        max = max,
        step = step,
        value = value,
        onChange = function(_, v)
            valueLabel:SetText(format(v))
            onChange(v)
        end,
    }
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 12,
        children = {
            rowLabel(text, 160),
            slider,
            valueLabel,
        },
    }
end

---@param text string
---@param value boolean
---@param onChange fun(v: boolean)
---@return Panel
function PauseMenu:makeToggleRow(text, value, onChange)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 12,
        children = {
            rowLabel(text, 160),
            UI.Toggle {
                value = value,
                onChange = function(_, v) onChange(v) end,
            },
        },
    }
end

---@param text string
---@param options table[]
---@param value string
---@param onChange fun(v: any)
---@return Panel
function PauseMenu:makeDropdownRow(text, options, value, onChange)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 12,
        children = {
            rowLabel(text, 200),
            UI.Dropdown {
                width = 220,
                options = options,
                value = value,
                onChange = function(_, v) onChange(v) end,
            },
        },
    }
end

-- ====================================================================
-- 显示 / 隐藏
-- ====================================================================

---@return boolean
function PauseMenu:isOpen()
    return self.open_ == true
end

function PauseMenu:notify(visible)
    if self.onVisibilityChanged then
        self.onVisibilityChanged(visible)
    end
end

function PauseMenu:showPause()
    self.pausePanel:SetVisible(true)
    self.settingsPanel:SetVisible(false)
    self.loadPanel:SetVisible(false)
    self.mainPanel:SetVisible(false)
    self.statusLabel:SetText("")
end

function PauseMenu:showSettings()
    self.pausePanel:SetVisible(false)
    self.settingsPanel:SetVisible(true)
    self.loadPanel:SetVisible(false)
    self.mainPanel:SetVisible(false)
    self.statusLabel:SetText("")
end

function PauseMenu:showLoad()
    self.pausePanel:SetVisible(false)
    self.settingsPanel:SetVisible(false)
    self.loadPanel:SetVisible(true)
    self.mainPanel:SetVisible(false)
    self.statusLabel:SetText("")
    self:refreshLoadList()
end

function PauseMenu:showMainMenu()
    self.pausePanel:SetVisible(false)
    self.settingsPanel:SetVisible(false)
    self.loadPanel:SetVisible(false)
    self.mainPanel:SetVisible(true)
    self.statusLabel:SetText("")
end

function PauseMenu:open()
    self.open_ = true
    self.root:SetVisible(true)
    self:showPause()
    if input then
        input.mouseMode = MM_ABSOLUTE
        input:SetMouseVisible(true)
    end
    self:notify(true)
end

function PauseMenu:hide()
    self.open_ = false
    self.root:SetVisible(false)
    if input then
        input.mouseMode = MM_RELATIVE
        input:SetMouseVisible(false)
    end
    self:notify(false)
end

---ESC：子页面返回暂停面板；暂停面板则关闭菜单
function PauseMenu:back()
    if not self.open_ then
        self:open()
        return
    end
    local onSubPage = (self.settingsPanel and self.settingsPanel:IsVisible())
        or (self.loadPanel and self.loadPanel:IsVisible())
        or (self.mainPanel and self.mainPanel:IsVisible())
    if onSubPage then
        self:showPause()
    else
        self:hide()
    end
end

-- ====================================================================
-- 设置逻辑
-- ====================================================================

function PauseMenu:applySettings(save)
    SettingsManager.apply(self.ctx)
    if save then
        SettingsManager.save()
    end
end

function PauseMenu:onApplySettings()
    SettingsManager.save()
    self:applySettings(false)
    self.statusLabel:SetText("设置已保存到 settings.json")
end

function PauseMenu:onResetSettings()
    SettingsManager.resetDefaults()
    SettingsManager.save()
    self:applySettings(false)
    self.statusLabel:SetText("已恢复默认设置（部分控件需重新打开界面刷新）")
end

-- ====================================================================
-- 保存 / 加载 / 删除
-- ====================================================================

function PauseMenu:onSave()
    local ctx = self.ctx.buildSaveContext and self.ctx.buildSaveContext() or self.ctx
    local ok, msg = SaveManager.saveWorld(ctx, SaveManager.getCurrentSlot())
    self.statusLabel:SetText(msg or (ok and "保存成功" or "保存失败"))
end

function PauseMenu:refreshLoadList()
    local content = self.loadListContent
    for _, child in ipairs(content.children or {}) do
        child:Destroy()
    end
    content.children = {}

    local worlds = SaveManager.listWorlds()
    if #worlds == 0 then
        content:AddChild(label("暂无存档（在暂停菜单里点「保存游戏」创建）", 13, SUB_COLOR))
        return
    end

    for _, meta in ipairs(worlds) do
        local slot = meta.slot
        local info = string.format("%s\nSeed %s · %s · 最后保存 %s",
            meta.name or slot,
            tostring(meta.seed or "?"),
            os.date("%Y-%m-%d %H:%M", meta.created_at or 0),
            os.date("%Y-%m-%d %H:%M", meta.saved_at or 0))

        local loadBtn = UI.Button {
            text = "加载",
            width = 76,
            height = 34,
            variant = "primary",
            onClick = function()
                local ctx = self.ctx.buildSaveContext and self.ctx.buildSaveContext() or self.ctx
                local ok, msg = SaveManager.loadWorld(ctx, slot)
                self.statusLabel:SetText(msg)
                if ok then
                    self:hide()
                end
            end,
        }

        local deleteBtn = UI.Button {
            text = "删除",
            width = 76,
            height = 34,
            variant = "outlined",
            onClick = function(btn)
                if not self.deleteArmed[slot] then
                    self.deleteArmed[slot] = true
                    btn:SetText("确认删除")
                    self.statusLabel:SetText("再次点击「确认删除」将永久删除该存档")
                    return
                end
                self.deleteArmed[slot] = nil
                local ok, msg = SaveManager.deleteWorld(slot)
                self.statusLabel:SetText(msg)
                if ok then
                    self:refreshLoadList()
                end
            end,
        }

        content:AddChild(UI.Panel {
            width = "100%",
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            gap = 12,
            padding = 8,
            backgroundColor = { 40, 46, 58, 220 },
            borderRadius = 8,
            children = {
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    flexDirection = "column",
                    gap = 2,
                    children = {
                        label(meta.name or slot, 14),
                        label(info:gsub("^[^\n]*\n", ""), 11, SUB_COLOR),
                    },
                },
                loadBtn,
                deleteBtn,
            },
        })
    end
end

return PauseMenu
