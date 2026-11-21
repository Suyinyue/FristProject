-- ====================================================================
-- devtools/ItemUiCheck.lua
-- 物品系统验收脚本（只由 validate 的 -validate-test 加载，正常游戏不会执行）
--
-- 用法：
--   taptap-maker preview validate --mode both \
--     --validate-test devtools/ItemUiCheck.lua --validate-frames 1900 ...
--
-- 覆盖：
--   E 打开/关闭背包、槽位控件、初始装备、
--   创造页取物品 → 放进 2×2 合成格 → 取出木板 → 放进背包、
--   Q 丢弃后快捷栏清空。
-- ====================================================================

---validate 断言 API（引擎在加载本脚本前注入全局 V）
---@class ValidateAPI
---@field assert fun(cond: boolean, msg: string)
---@field fail fun(msg: string)
---@field atFrame fun(n: integer, fn: function)
---@field scene fun(): Scene
---@field assertNodeExists fun(name: string, compType: string?): Node?
---@field assertHasComponent fun(node: Node|string, compType: string)
---@field assertPosition fun(node: Node|string, pos: Vector3, tol: number)
---@field assertNear fun(actual: number, expected: number, tol: number, msg: string)
---@field assertInRange fun(v: number, lo: number, hi: number, msg: string)
---@field finish fun()

---@type ValidateAPI
local V = _G.V

local UI = require("urhox-libs/UI/init")

---模拟按键（调用游戏自己的全局按键处理）
---@param key integer
local function pressKey(key)
    local ed = VariantMap()
    ed["Key"] = Variant(key)
    HandleKeyDown("KeyDown", ed)
end

---模拟点击某个控件（直接调用 UI 的 pointerdown 处理）
---@param id string
---@param button integer|nil 0 左键 / 2 右键
---@return boolean found
local function clickWidget(id, button)
    local root = UI.GetRoot()
    local widget = root and root:FindById(id)
    if not widget then
        return false
    end
    local handler = widget.props and widget.props.onPointerDown
    if not handler then
        return false
    end
    handler({
        button = button or 0,
        x = 0,
        y = 0,
        StopPropagation = function() end,
    }, widget)
    return true
end

---点击带 onClick 的控件（页签 / 按钮）
---@param id string
---@return boolean found
local function clickButton(id)
    local root = UI.GetRoot()
    local widget = root and root:FindById(id)
    if not widget or not widget.props or not widget.props.onClick then
        return false
    end
    widget.props.onClick(widget, {})
    return true
end

-- 1. 打开背包
V.atFrame(1200, function()
    pressKey(KEY_E)
end)

-- 2. 创造「方块」页 → 取 64 个原木 → 放进合成格 → 合成木板 → 放进主背包
V.atFrame(1240, function()
    V.assert(clickButton("inv_tab_blocks"), "找不到「方块」页签")
end)

V.atFrame(1260, function()
    -- 第 5 个创造格是原木（BlockPalette 第 1 页顺序）
    V.assert(clickWidget("inv_creative_5"), "找不到创造页第 5 格")
end)

V.atFrame(1280, function()
    V.assert(clickWidget("inv_craft_1"), "找不到合成格 1")
end)

V.atFrame(1300, function()
    V.assert(clickWidget("inv_craft_output"), "找不到合成结果槽")
end)

V.atFrame(1320, function()
    V.assert(clickWidget("inv_main_20"), "找不到主背包第 20 格")
end)

-- 3. 检查界面、初始装备与合成结果
V.atFrame(1340, function()
    local root = UI.GetRoot()
    V.assert(root ~= nil, "UI 根为空")
    local inv = root and root:FindById("inventory_root")
    V.assert(inv ~= nil, "inventory_root 不存在")
    if inv then
        V.assert(inv:IsVisible(), "按 E 后背包界面没有显示")
    end
    V.assert(root and root:FindById("inv_main_1") ~= nil, "主背包第一格缺失")
    V.assert(root and root:FindById("inv_hotbar_9") ~= nil, "快捷栏第 9 格缺失")
    V.assert(root and root:FindById("inv_craft_output") ~= nil, "合成输出槽缺失")
    V.assert(root and root:FindById("inv_tab_items") ~= nil, "创造物品页签缺失")

    local icon = root and root:FindById("hotbar_icon_1") --[[@as Label]]
    if icon then
        V.assert(icon:GetText() == "剑", "快捷栏 1 应为剑，实际：" .. tostring(icon:GetText()))
    end
    local cnt = root and root:FindById("hotbar_count_7") --[[@as Label]]
    if cnt then
        V.assert(cnt:GetText() == "64", "快捷栏 7 数量应为 64，实际：" .. tostring(cnt:GetText()))
    end

    -- 合成：1 原木 → 4 木板，落在主背包第 20 格
    local planks = root and root:FindById("inv_main_20_count") --[[@as Label]]
    if planks then
        V.assert(planks:GetText() == "4", "合成木板数量应为 4，实际：" .. tostring(planks:GetText()))
    end
end)

-- 4. 再按 E 关闭
V.atFrame(1380, function()
    pressKey(KEY_E)
end)

V.atFrame(1450, function()
    local root = UI.GetRoot()
    local inv = root and root:FindById("inventory_root")
    if inv then
        V.assert(not inv:IsVisible(), "再按 E 后背包没有关闭")
    end
end)

-- 5. Q 丢弃第 1 格（剑）
V.atFrame(1520, function()
    pressKey(KEY_Q)
end)

-- 拾取冷却 0.5 秒内检查：槽位已清空
-- （再晚一点掉落物会被自动捡回，这是与 Minecraft 一致的行为）
V.atFrame(1545, function()
    local root = UI.GetRoot()
    local icon = root and root:FindById("hotbar_icon_1") --[[@as Label]]
    if icon then
        V.assert(icon:GetText() == "", "丢弃后快捷栏 1 应清空，实际：" .. tostring(icon:GetText()))
    end
end)

-- 6. 重新打开背包（截图帧展示完整界面）
V.atFrame(1600, function()
    pressKey(KEY_E)
end)
