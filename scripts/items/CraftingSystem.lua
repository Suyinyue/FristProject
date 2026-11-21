-- ====================================================================
-- items/CraftingSystem.lua
-- 合成系统（参考 Minecraft 2×2 / 3×3 合成）
--
--   - 配方来自 data/CraftingRecipes.lua（有序 + 无序两种）
--   - 匹配前会裁掉网格四周的空行 / 空列，所以同一配方在工作台的
--     不同位置都成立（和 MC 一致）
--   - 只负责"匹配 / 计算结果 / 扣材料"，不负责 UI
-- ====================================================================

local ItemStack = require("items.ItemStack")
local CraftingRecipes = require("data.CraftingRecipes")

---@class CraftingRecipe
---@field id string
---@field w integer
---@field h integer
---@field rows (string|false)[][]
---@field shapeless string[]|nil
---@field result { id: string, count: integer }

---@class CraftingSystem
---@field recipes CraftingRecipe[]
local CraftingSystem = {}
CraftingSystem.__index = CraftingSystem

---把一行 pattern 解码成物品 ID 数组
---空格用 false 占位（不能用 nil，否则表被截断、#row 失真，
---带前导空格的配方会被误判成空配方）
---@param row string
---@param key table<string, string>
---@return (string|false)[]
local function decodeRow(row, key)
    local cells = {}
    for i = 1, #row do
        local ch = row:sub(i, i)
        if ch == " " or ch == "." then
            cells[i] = false
        else
            local itemId = key[ch]
            if not itemId then
                print("[Crafting] 配方字符没有对应的 key：" .. ch)
                cells[i] = false
            else
                cells[i] = itemId
            end
        end
    end
    return cells
end

---裁掉四周的空行 / 空列
---@param rows (string|false)[][]
---@return (string|false)[][], integer w, integer h
local function trimRows(rows)
    local h = #rows
    local w = 0
    for _, row in ipairs(rows) do
        w = math.max(w, #row)
    end

    local top, bottom = 1, h
    local left, right = 1, w

    -- 上
    while top <= bottom do
        local row = rows[top]
        local empty = true
        if row then
            for c = 1, w do
                if row[c] then empty = false; break end
            end
        end
        if not empty then break end
        top = top + 1
    end
    -- 下
    while bottom >= top do
        local row = rows[bottom]
        local empty = true
        if row then
            for c = 1, w do
                if row[c] then empty = false; break end
            end
        end
        if not empty then break end
        bottom = bottom - 1
    end
    -- 左
    while left <= right do
        local empty = true
        for r = top, bottom do
            local row = rows[r]
            if row and row[left] then empty = false; break end
        end
        if not empty then break end
        left = left + 1
    end
    -- 右
    while right >= left do
        local empty = true
        for r = top, bottom do
            local row = rows[r]
            if row and row[right] then empty = false; break end
        end
        if not empty then break end
        right = right - 1
    end

    if top > bottom or left > right then
        return {}, 0, 0
    end

    local out = {}
    for r = top, bottom do
        local src = rows[r]
        local row = {}
        for c = left, right do
            row[#row + 1] = src and src[c] or false
        end
        out[#out + 1] = row
    end
    return out, right - left + 1, bottom - top + 1
end

---创建合成系统
---@return CraftingSystem
function CraftingSystem.new()
    local self = setmetatable({}, CraftingSystem)
    self.recipes = {}

    for _, raw in ipairs(CraftingRecipes.recipes) do
        ---@type CraftingRecipe
        local recipe = {
            id = raw.id,
            result = raw.result,
            w = 0,
            h = 0,
            rows = {},
            shapeless = raw.shapeless,
        }

        if raw.shape then
            local decoded = {}
            for r, line in ipairs(raw.shape) do
                decoded[r] = decodeRow(line, raw.key or {})
            end
            local trimmed, w, h = trimRows(decoded)
            recipe.rows = trimmed
            recipe.w = w
            recipe.h = h
        end

        if (recipe.w == 0 and not recipe.shapeless) then
            print("[Crafting] 跳过空配方：" .. tostring(recipe.id))
        else
            self.recipes[#self.recipes + 1] = recipe
        end
    end

    print(string.format("[Crafting] 已加载 %d 条配方", #self.recipes))
    return self
end

---把 UI 网格整理成二维物品 ID（并裁掉空边）
---@param stacks (ItemStack|nil)[] 行优先排列
---@param width integer
---@param height integer
---@return (string|false)[][], integer w, integer h
local function gridToMatrix(stacks, width, height)
    local rows = {}
    for r = 1, height do
        local row = {}
        for c = 1, width do
            local stack = stacks[(r - 1) * width + c]
            row[c] = (stack and stack.count > 0 and stack.id) or false
        end
        rows[r] = row
    end
    return trimRows(rows)
end

---匹配当前网格
---@param stacks (ItemStack|nil)[] 行优先排列（长度 = width*height）
---@param width integer
---@param height integer
---@return CraftingRecipe|nil recipe
---@return ItemStack|nil resultStack
function CraftingSystem:match(stacks, width, height)
    local matrix, w, h = gridToMatrix(stacks, width, height)
    if w == 0 or h == 0 then
        return nil, nil
    end

    -- 有序配方
    for _, recipe in ipairs(self.recipes) do
        if recipe.shapeless then
            -- 无序：比较物品 ID 集合（每个材料消耗 1 个）
            local used = {}
            local ok = true
            for _, id in ipairs(recipe.shapeless) do
                used[id] = (used[id] or 0) + 1
            end
            local counts = {}
            for r = 1, h do
                local row = matrix[r]
                if row then
                    for c = 1, w do
                        local id = row[c]
                        if id then
                            counts[id] = (counts[id] or 0) + 1
                        end
                    end
                end
            end
            for id, need in pairs(used) do
                if (counts[id] or 0) < need then
                    ok = false
                    break
                end
            end
            -- 网格里不能多出配方以外的物品
            if ok then
                for id, have in pairs(counts) do
                    if (used[id] or 0) ~= have then
                        ok = false
                        break
                    end
                end
            end
            if ok then
                return recipe, ItemStack.new(recipe.result.id, recipe.result.count)
            end
        else
            if recipe.w == w and recipe.h == h then
                local ok = true
                for r = 1, h do
                    local needRow = recipe.rows[r]
                    local haveRow = matrix[r]
                    for c = 1, w do
                        local need = needRow and needRow[c] or false
                        local have = haveRow and haveRow[c] or false
                        if need ~= have then
                            ok = false
                            break
                        end
                    end
                    if not ok then break end
                end
                if ok then
                    return recipe, ItemStack.new(recipe.result.id, recipe.result.count)
                end
            end
        end
    end

    return nil, nil
end

---扣掉一次合成的材料（每个非空格子取 1 个）
---@param slots InventorySlot[]
function CraftingSystem.consume(slots)
    for _, slot in ipairs(slots) do
        if slot and not slot:isEmpty() then
            slot:take(1)
        end
    end
end

---配方总数
---@return integer
function CraftingSystem:getRecipeCount()
    return #self.recipes
end

return CraftingSystem
