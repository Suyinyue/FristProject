-- ====================================================================
-- save/SettingsManager.lua
-- 游戏设置：读取 / 保存 / 应用
--
--   - 文件：settings.json（引擎项目+用户隔离目录，与世界存档分开）
--   - 支持项：音量、FOV、渲染距离、全屏、画质、鼠标灵敏度、反转 Y、FPS、自动保存
--   - 暂不支持：分辨率（graphics:SetMode 在本引擎被禁用）
-- ====================================================================

local Config = require("config.GameConfig")

local SettingsManager = {}

local SETTINGS_FILE = "settings.json"

---@class GameSettings
local DEFAULTS = {
    audio = {
        master = 1.0,
        music = 0.8,
        sfx = 0.9,
    },
    video = {
        fov = 90,
        renderDistance = 6,
        fullscreen = false,
        quality = "high",
        resolution = "1600x900",   -- UI 展示；当前引擎不支持运行时改分辨率
    },
    game = {
        mouseSensitivity = 0.1,
        invertY = false,
        showFps = false,
        autosave = true,
        autosaveInterval = 300,
    },
}

local function deepCopy(src)
    local out = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            out[k] = deepCopy(v)
        else
            out[k] = v
        end
    end
    return out
end

local function mergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            if type(target[k]) ~= "table" then
                target[k] = deepCopy(v)
            else
                mergeDefaults(target[k], v)
            end
        elseif target[k] == nil then
            target[k] = v
        end
    end
end

---@type GameSettings
SettingsManager.data = deepCopy(DEFAULTS)

---@return GameSettings
function SettingsManager.get()
    return SettingsManager.data
end

function SettingsManager.resetDefaults()
    SettingsManager.data = deepCopy(DEFAULTS)
end

---读取设置文件（不存在则用默认值）
---@return boolean loaded
function SettingsManager.load()
    SettingsManager.data = deepCopy(DEFAULTS)
    if not fileSystem:FileExists(SETTINGS_FILE) then
        return false
    end
    local file = File(SETTINGS_FILE, FILE_READ)
    if not file or not file:IsOpen() then
        return false
    end
    local text = file:ReadString()
    file:Close()
    local ok, decoded = pcall(cjson.decode, text)
    if ok and type(decoded) == "table" then
        mergeDefaults(decoded, DEFAULTS)
        SettingsManager.data = decoded
        return true
    end
    print("[Settings] 设置文件解析失败，使用默认值")
    return false
end

---保存设置文件（临时文件 + 原子替换 + 备份）
---@return boolean ok
function SettingsManager.save()
    local tmp = SETTINGS_FILE .. ".tmp"
    local file = File(tmp, FILE_WRITE)
    if not file or not file:IsOpen() then
        print("[Settings] 无法写入设置文件")
        return false
    end
    file:WriteString(cjson.encode(SettingsManager.data))
    file:Close()

    if fileSystem:FileExists(SETTINGS_FILE) then
        fileSystem:Copy(SETTINGS_FILE, SETTINGS_FILE .. ".bak")
        fileSystem:Delete(SETTINGS_FILE)
    end
    if not fileSystem:Rename(tmp, SETTINGS_FILE, true) then
        fileSystem:Copy(tmp, SETTINGS_FILE)
        fileSystem:Delete(tmp)
    end
    return true
end

---应用设置到运行中的游戏
---@param ctx table { player, chunkStreamer, uiManager }
function SettingsManager.apply(ctx)
    local s = SettingsManager.data
    ctx = ctx or {}

    -- 音频
    if audio then
        pcall(function()
            audio:SetMasterGain(SOUND_MASTER, s.audio.master)
            audio:SetMasterGain(SOUND_MUSIC, s.audio.master * s.audio.music)
            audio:SetMasterGain(SOUND_EFFECT, s.audio.master * s.audio.sfx)
        end)
    end

    -- 相机 FOV
    local player = ctx.player
    if player and player.camera then
        player.camera.fov = s.video.fov
    end

    -- 渲染距离（ChunkStreamer 每帧读 Config.World.RENDER_DISTANCE）
    Config.World.RENDER_DISTANCE = s.video.renderDistance
    local streamer = ctx.chunkStreamer
    if streamer then
        streamer.lastCX = nil
        streamer.lastCZ = nil
        streamer.buildQueue = {}
    end

    -- 全屏（引擎允许 ToggleFullscreen；分辨率运行时修改被禁用）
    if graphics then
        pcall(function()
            if graphics:GetFullscreen() ~= s.video.fullscreen then
                graphics:ToggleFullscreen()
            end
        end)
    end

    -- 画质
    if renderer then
        pcall(function()
            if s.video.quality == "low" then
                renderer:SetTextureQuality(QUALITY_LOW)
                renderer:SetMaterialQuality(QUALITY_LOW)
                renderer:SetShadowQuality(QUALITY_LOW)
            elseif s.video.quality == "medium" then
                renderer:SetTextureQuality(QUALITY_MEDIUM)
                renderer:SetMaterialQuality(QUALITY_MEDIUM)
                renderer:SetShadowQuality(QUALITY_MEDIUM)
            else
                renderer:SetTextureQuality(QUALITY_HIGH)
                renderer:SetMaterialQuality(QUALITY_HIGH)
                renderer:SetShadowQuality(QUALITY_HIGH)
            end
        end)
    end

    -- 输入
    Config.Controls.MOUSE_SENSITIVITY = s.game.mouseSensitivity
    Config.Controls.INVERT_Y = s.game.invertY

    -- FPS 显示
    if ctx.uiManager then
        ctx.uiManager:setFpsVisible(s.game.showFps)
    end
end

return SettingsManager
