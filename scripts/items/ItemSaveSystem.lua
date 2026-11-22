-- ====================================================================
-- items/ItemSaveSystem.lua
-- 物品存档（本地文件持久化）
--
-- 保存内容：
--   - 背包 41 格（含快捷栏 / 装备栏 / 副手）的物品 ID、数量、耐久、附魔、组件
--   - 当前快捷栏选中格
--   - 饥饿值
--   - 世界中尚未消失的掉落物（位置 + 物品）
--
-- 引擎自动做项目 + 用户隔离（见 engine-docs/recipes/file-storage.md）；
-- 服务端模式下文件 API 会被禁用，这里先 IsServerMode() 短路。
-- ====================================================================

local Config = require("config.GameConfig")

local ItemSaveSystem = {}

---存档是否存在
---@return boolean
function ItemSaveSystem.exists()
    if IsServerMode() then
        return false
    end
    return fileSystem:FileExists(Config.Items.SAVE_FILE) == true
end

---保存玩家物品数据
---@param player Player
---@param dropSystem ItemDropSystem|nil
---@return boolean
function ItemSaveSystem.save(player, dropSystem)
    if IsServerMode() or not player then
        return false
    end

    local inventory = player:getInventory()
    if not inventory then
        return false
    end

    local data = {
        version = 1,
        inventory = inventory:toData(),
        hotbar = player:getSelectedSlotIndex(),
        hunger = player:getHunger(),
        saturation = player:getSaturation(),
        level = player:getLevel(),
        xp = player:getXp(),
        xpTotal = player:getXpTotal(),
        drops = dropSystem and dropSystem:serialize() or {},
    }

    local ok, encoded = pcall(cjson.encode, data)
    if not ok then
        print("[ItemSave] 序列化失败：" .. tostring(encoded))
        return false
    end

    local file = File(Config.Items.SAVE_FILE, FILE_WRITE)
    if not file or not file:IsOpen() then
        print("[ItemSave] 无法写入存档：" .. Config.Items.SAVE_FILE)
        return false
    end

    file:WriteString(encoded)
    file:Close()
    return true
end

---读取存档
---@param player Player
---@param dropSystem ItemDropSystem|nil
---@return boolean loaded 是否成功读取（没有存档 / 解析失败返回 false）
function ItemSaveSystem.load(player, dropSystem)
    if IsServerMode() or not player then
        return false
    end
    if not fileSystem:FileExists(Config.Items.SAVE_FILE) then
        return false
    end

    local file = File(Config.Items.SAVE_FILE, FILE_READ)
    if not file or not file:IsOpen() then
        return false
    end
    local text = file:ReadString()
    file:Close()

    local ok, data = pcall(cjson.decode, text)
    if not ok or type(data) ~= "table" then
        print("[ItemSave] 存档解析失败，按新存档处理（不覆盖原文件）")
        return false
    end

    local inventory = player:getInventory()
    if inventory and type(data.inventory) == "table" then
        inventory:fromData(data.inventory)
    end

    if type(data.hotbar) == "number" then
        player:selectSlot(data.hotbar)
    end
    if type(data.hunger) == "number" then
        player:setHunger(data.hunger)
    end
    if type(data.saturation) == "number" then
        player:setSaturation(data.saturation)
    end
    if type(data.level) == "number" then
        player:setXp(data.level, type(data.xp) == "number" and data.xp or 0,
            type(data.xpTotal) == "number" and data.xpTotal or 0)
    end
    if dropSystem and type(data.drops) == "table" then
        dropSystem:restore(data.drops)
    end

    print("[ItemSave] 物品存档已恢复")
    return true
end

---删除存档（调试用）
---@return boolean
function ItemSaveSystem.delete()
    if IsServerMode() then
        return false
    end
    return fileSystem:Delete(Config.Items.SAVE_FILE) == true
end

return ItemSaveSystem
