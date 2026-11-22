-- ====================================================================
-- core/AudioManager.lua
-- 音频管理：背景音乐（BGM）+ 一次性音效（SFX）
--
--   资源位于 assets/music/audio/（音效）与 assets/music/back_music/（BGM）。
--   资源路径从资源根写起（不带 assets 前缀），即 assets/music 下的相对路径。
--
--   音量模型（见 engine-docs/api/audio.md）：
--     - BGM 用独立长期 SoundSource，类型 SOUND_MUSIC
--     - SFX 用一次性 SoundSource（默认类型 SOUND_EFFECT）
--     - 两类音量由 save/SettingsManager.lua 通过 audio:SetMasterGain 统一控制
-- ====================================================================

local Blocks = require("data.BlockRegistry")

local AudioManager = {}

-- 逻辑音效名 → 资源路径（相对资源根）
local SOUNDS = {
    footsteps_grass = "music/audio/sfx_01_footsteps_grass.mp3",
    player_hurt     = "music/audio/sfx_05_player_hurt.mp3",
    player_defeat   = "music/audio/sfx_06_player_defeat.mp3",
    dig_dirt        = "music/audio/sfx_07_dig_dirt.mp3",
    dig_grass       = "music/audio/sfx_08_dig_grass_block.mp3",
    mine_stone      = "music/audio/sfx_09_mine_stone.mp3",
    mine_ore        = "music/audio/sfx_10_mine_ore.mp3",
    break_wood      = "music/audio/sfx_11_break_wood.mp3",
    break_sand      = "music/audio/sfx_12_break_sand.mp3",
    sword_swing     = "music/audio/sfx_44_sword_swing.mp3",
    sword_hit       = "music/audio/sfx_45_sword_hit.mp3",
    bow_draw        = "music/audio/sfx_47_bow_draw.mp3",
    bow_release     = "music/audio/sfx_48_bow_release.mp3",
    critical_hit    = "music/audio/sfx_53_critical_hit.mp3",
    enemy_defeat    = "music/audio/sfx_54_enemy_defeat.mp3",
    zombie_idle     = "music/audio/sfx_55_zombie_idle.mp3",
    zombie_walk     = "music/audio/sfx_56_zombie_walk.mp3",
    zombie_alert    = "music/audio/sfx_57_zombie_alert.mp3",
    zombie_attack   = "music/audio/sfx_58_zombie_attack.mp3",
    zombie_hurt     = "music/audio/sfx_59_zombie_hurt.mp3",
}

-- 背景音乐（循环播放）
local MUSIC_PATH = "music/back_music/music_1795321901868.ogg"

---@type Scene|nil
local scene_ = nil
---@type Node|nil
local sfxNode_ = nil
---@type SoundSource|nil
local musicSource_ = nil
---@type Sound|nil
local musicSound_ = nil
---@type table<string, Sound>
local soundCache_ = {}

local initialized_ = false

-- ============================================================================
-- 内部：方块类型 → 破坏音效
-- ============================================================================

---@param blockType integer
---@return string
local function blockBreakSound_(blockType)
    -- 矿石 → 金属敲击声
    if blockType == Blocks.COAL_ORE or blockType == Blocks.IRON_ORE
        or blockType == Blocks.GOLD_ORE or blockType == Blocks.DIAMOND_ORE
        or blockType == Blocks.REDSTONE_ORE or blockType == Blocks.LAPIS_ORE
        or blockType == Blocks.COPPER_ORE or blockType == Blocks.EMERALD_ORE
        or blockType == Blocks.ADAMANT_ORE or blockType == Blocks.FLAME_STONE_ORE then
        return "mine_ore"
    end
    -- 草类
    if blockType == Blocks.GRASS or blockType == Blocks.SNOWY_GRASS
        or blockType == Blocks.TALL_GRASS then
        return "dig_grass"
    end
    -- 木质
    if blockType == Blocks.WOOD or blockType == Blocks.PLANKS
        or blockType == Blocks.LEAVES then
        return "break_wood"
    end
    -- 沙 / 砾 / 砂岩
    if blockType == Blocks.SAND or blockType == Blocks.GRAVEL
        or blockType == Blocks.SANDSTONE or blockType == Blocks.CLAY then
        return "break_sand"
    end
    -- 石质
    if blockType == Blocks.STONE or blockType == Blocks.COBBLESTONE
        or blockType == Blocks.MOSSY_COBBLESTONE or blockType == Blocks.STONE_BRICKS
        or blockType == Blocks.OBSIDIAN or blockType == Blocks.BRICKS
        or blockType == Blocks.GLOWSTONE then
        return "mine_stone"
    end
    -- 泥土及未归类方块
    return "dig_dirt"
end

-- ============================================================================
-- 初始化
-- ============================================================================

---初始化音频管理器（在场景就绪、设置应用后调用一次）
---@param scene Scene
function AudioManager.init(scene)
    if initialized_ then
        return
    end
    scene_ = scene
    sfxNode_ = scene_:CreateChild("Audio_SFX")
    initialized_ = true
    AudioManager.startMusic()
end

---开始播放背景音乐（循环）
function AudioManager.startMusic()
    if not scene_ or (musicSource_ and musicSound_) then
        return
    end
    musicSound_ = cache:GetResource("Sound", MUSIC_PATH)
    if not musicSound_ then
        print("[Audio] BGM 加载失败：" .. MUSIC_PATH)
        return
    end
    musicSound_.looped = true

    local node = scene_:CreateChild("Audio_BGM")
    local source = node:CreateComponent("SoundSource")
    source:SetSoundType(SOUND_MUSIC)
    source:Play(musicSound_, 0, 1.0)
    musicSource_ = source
end

---停止背景音乐
function AudioManager.stopMusic()
    if musicSource_ then
        musicSource_:Stop()
        musicSource_ = nil
        musicSound_ = nil
    end
end

-- ============================================================================
-- 播放音效
-- ============================================================================

---播放一次性音效（播完自动销毁组件）
---@param name string 逻辑音效名（见 SOUNDS 表）
---@param gain number|nil 音量 0~1，默认 0.8
function AudioManager.play(name, gain)
    if not initialized_ or not scene_ then
        return
    end
    local node = sfxNode_
    if not node then
        return
    end
    local path = SOUNDS[name]
    if not path then
        return
    end

    local sound = soundCache_[path]
    if not sound then
        sound = cache:GetResource("Sound", path)
        if not sound then
            return
        end
        soundCache_[path] = sound
    end

    local source = node:CreateComponent("SoundSource")
    source.autoRemoveMode = REMOVE_COMPONENT
    -- 轻微随机音高（0.95~1.05），连续播放同类音效时不显单调
    local pitch = 0.95 + math.random() * 0.1
    source:Play(sound, sound:GetFrequency() * pitch, gain or 0.8)
end

---按方块类型播放破坏音效
---@param blockType integer
function AudioManager.playBlockBreak(blockType)
    AudioManager.play(blockBreakSound_(blockType))
end

return AudioManager
