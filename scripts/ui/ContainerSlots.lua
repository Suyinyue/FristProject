-- ====================================================================
-- ui/ContainerSlots.lua
-- 容器类 UI（箱子 / 熔炉 / 附魔台）共用的槽位控件与交互逻辑。
--
-- 从 ui/InventoryUI.lua 的槽位逻辑抽出，供多个容器界面复用：
--   - createSlotWidget  槽位控件（图标 + 数量 + 耐久条）
--   - refreshSlotWidget 按 ItemStack 刷新显示
--   - click             MC 风格点击（左键整堆 / 右键一半或单个）
--   - buildCursor       拖拽光标控件
--   - refreshCursor     按光标堆刷新光标显示
-- ====================================================================

local UI = require("urhox-libs/UI/init")
local ItemRegistry = require("items.ItemRegistry")

local ContainerSlots = {}

ContainerSlots.SLOT = 40

local COL_SLOT = { 64, 64, 74, 235 }
local COL_SLOT_DISABLED = { 38, 38, 44, 235 }
local COL_BORDER = { 22, 22, 26, 255 }
local COL_SELECTED = { 255, 210, 80, 255 }

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

---@param id string
---@param onDown function|nil
---@param onEnter function|nil
---@param onLeave function|nil
---@return table { root, icon, count, dur }
function ContainerSlots.createSlotWidget(id, onDown, onEnter, onLeave)
    local icon = UI.Label {
        id = id .. "_icon",
        text = "",
        width = 30, height = 30,
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
        right = 4, bottom = 1,
        fontSize = 11,
        fontColor = { 255, 255, 255, 255 },
        pointerEvents = "none",
    }
    local dur = UI.Panel {
        id = id .. "_dur",
        position = "absolute",
        left = 4, bottom = 3,
        width = 32, height = 3,
        borderRadius = 1,
        backgroundColor = { 80, 220, 80, 255 },
        pointerEvents = "none",
        visible = false,
    }
    local root = UI.Panel {
        id = id,
        width = ContainerSlots.SLOT,
        height = ContainerSlots.SLOT,
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

---@param widget table
---@param stack table|nil ItemStack
---@param selected boolean|nil
---@param disabled boolean|nil
function ContainerSlots.refreshSlotWidget(widget, stack, selected, disabled)
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
        widget.icon:SetStyle({ backgroundColor = { 0, 0, 0, 0 }, backgroundImage = false, fontColor = { 255, 255, 255, 255 } })
        widget.count:SetText("")
        widget.dur:SetVisible(false)
        return
    end

    local def = ItemRegistry:get(stack.id)
    if def and def.iconTexture then
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
        local w = math.max(2, math.floor((ContainerSlots.SLOT - 8) * frac))
        local color = { 80, 220, 80, 255 }
        if frac < 0.25 then color = { 230, 70, 60, 255 }
        elseif frac < 0.5 then color = { 240, 200, 60, 255 } end
        widget.dur:SetStyle({ width = w, backgroundColor = color })
    else
        widget.dur:SetVisible(false)
    end
end

---MC 风格点击：左键整堆 / 右键一半或单个。
---cursor 是一个 { stack = ItemStack|nil } 的持有者表（调用方维护），slot 是 InventorySlot。
---@param cursor table
---@param slot table|nil InventorySlot
---@param button integer 0 左键 / 2 右键
function ContainerSlots.click(cursor, slot, button)
    if not slot then
        return
    end
    local cur = cursor.stack
    local current = slot:get()

    if button == 2 then
        if not cur then
            if current and current.count > 0 then
                cursor.stack = slot:take(math.ceil(current.count / 2))
            end
        else
            if not current then
                if slot:canAccept(cur) then
                    slot:set(cur:split(1))
                end
            elseif current:isSameInstance(cur) and current:getRemainingSpace() > 0 then
                local one = cur:split(1)
                if one then
                    slot:add(one)
                end
            end
        end
    else
        if not cur then
            cursor.stack = slot:take(slot:getCount())
        elseif not current then
            if slot:canAccept(cur) then
                slot:set(cur)
                cursor.stack = nil
            end
        elseif current:isSameInstance(cur) then
            current:mergeFrom(cur)
            if cur.count <= 0 then
                cursor.stack = nil
            end
        else
            if slot:canAccept(cur) then
                slot:set(cur)
                cursor.stack = current
            end
        end
    end

    if cursor.stack and cursor.stack.count <= 0 then
        cursor.stack = nil
    end
end

---构建拖拽光标控件
---@param id string
---@return table { root, icon, count }
function ContainerSlots.buildCursor(id)
    local icon = UI.Label {
        id = id .. "_icon",
        text = "",
        width = 32, height = 32,
        borderRadius = 4,
        textAlign = "center",
        fontSize = 22,
        fontColor = { 255, 255, 255, 255 },
        backgroundColor = { 0, 0, 0, 0 },
        pointerEvents = "none",
    }
    local count = UI.Label {
        id = id .. "_count",
        text = "",
        position = "absolute",
        right = 3, bottom = 1,
        fontSize = 11,
        fontColor = { 255, 255, 255, 255 },
        pointerEvents = "none",
    }
    local root = UI.Panel {
        id = id,
        position = "absolute",
        left = 0, top = 0,
        width = ContainerSlots.SLOT,
        height = ContainerSlots.SLOT,
        backgroundColor = { 70, 70, 82, 245 },
        borderRadius = 6,
        borderWidth = 1,
        borderColor = { 255, 255, 255, 200 },
        alignItems = "center",
        justifyContent = "center",
        pointerEvents = "none",
        visible = false,
        children = { icon, count },
    }
    return { root = root, icon = icon, count = count }
end

---按光标堆刷新光标显示
---@param cursor table { stack, widget }
function ContainerSlots.refreshCursor(cursor)
    local stack = cursor.stack
    local widget = cursor.widget
    if not widget then
        return
    end
    if not stack or stack.count <= 0 then
        cursor.stack = nil
        widget.root:SetVisible(false)
        return
    end
    widget.root:SetVisible(true)
    local def = ItemRegistry:get(stack.id)
    if def and def.iconTexture then
        widget.icon:SetText("")
        widget.icon:SetStyle({ backgroundColor = { 0, 0, 0, 0 }, backgroundImage = def.iconTexture, backgroundFit = "contain" })
    elseif stack:isBlock() then
        widget.icon:SetText("")
        widget.icon:SetStyle({ backgroundColor = def and rgba(def.color) or { 150, 150, 150, 255 }, backgroundImage = false })
    else
        widget.icon:SetText(def and def.icon or "?")
        widget.icon:SetStyle({ backgroundColor = { 0, 0, 0, 0 }, backgroundImage = false, fontColor = def and brighten(def.color) or { 255, 255, 255, 255 } })
    end
    widget.count:SetText(stack.count > 1 and tostring(stack.count) or "")
end

---容器界面打开/关闭时切换鼠标模式（与背包一致）
---@param playerController table|nil
---@param open boolean
function ContainerSlots.applyMouseMode(playerController, open)
    local platform = GetPlatform()
    local isMobile = platform == "Android" or platform == "iOS"
    if playerController then
        playerController:setMouseLocked(isMobile and false or not open)
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

return ContainerSlots
