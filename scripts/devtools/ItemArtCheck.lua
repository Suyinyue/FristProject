-- ====================================================================
-- devtools/ItemArtCheck.lua
-- 临时视觉验收：把非方块物品的 3D 模型摆到相机前方，并切换手持物品。
-- 用 preview validate --mode both --validate-test devtools/ItemArtCheck.lua 截图查看。
-- ====================================================================

local ItemModel = require("items.ItemModel")
local V = _G.V

---模拟按键（调用游戏自己的全局按键处理）
---@param key integer
local function pressKey(key)
    local ed = VariantMap()
    ed["Key"] = Variant(key)
    HandleKeyDown("KeyDown", ed)
end

local IDS = {
    "sword", "pickaxe", "axe", "shovel",
    "bow", "apple", "potion_heal", "helmet",
    "bucket", "wheat", "diamond", "bread",
}

V.atFrame(300, function()
    local ctx = GetDebugGameContext()
    if not ctx or not ctx.scene or not ctx.player then
        V.fail("GetDebugGameContext 不可用")
        return
    end

    local player = ctx.player
    local eye = player:getEyePosition()
    local dir = player:getLookDirection():Normalized()
    local right = dir:CrossProduct(Vector3(0, 1, 0)):Normalized()
    local up = Vector3(0, 1, 0)
    print(string.format("[ItemArtCheck] eye=(%.2f,%.2f,%.2f) dir=(%.2f,%.2f,%.2f)",
        eye.x, eye.y, eye.z, dir.x, dir.y, dir.z))

    local created = 0
    for i, id in ipairs(IDS) do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        local offset = dir * 6
            + right * ((col - 1.5) * 1.35)
            + up * (2.2 - row * 1.15)
        local parent = ctx.scene:CreateChild("ItemArt_" .. id)
        parent.position = eye + offset
        parent.scale = Vector3(1.4, 1.4, 1.4)
        local node = ItemModel.createDroppedNode(parent, id)
        if node then
            node.rotation = Quaternion(0, 25, 0)
            created = created + 1
        end
    end

    -- 手持物品：切到第 2 格（铁镐）
    player:selectSlot(2)
    print("[ItemArtCheck] models created:", created, "slot:", player:getSelectedSlotIndex())
end)

-- 打开背包，确认格子里的物品贴图图标
V.atFrame(500, function()
    pressKey(KEY_E)
end)

V.atFrame(900, function()
    V.finish()
end)
