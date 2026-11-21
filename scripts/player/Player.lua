-- ====================================================================
-- player/Player.lua
-- 玩家状态和属性
-- ====================================================================

local Config = require("config.GameConfig")
local Blocks = require("data.BlockRegistry")
local Inventory = require("items.Inventory")
local FirstPersonArm = require("player.FirstPersonArm")
local PlayerBody = require("player.PlayerBody")

---@class Player
---@field scene Scene
---@field node Node
---@field cameraNode Node
---@field camera Camera
---@field velocity Vector3
---@field yaw number
---@field pitch number
---@field isOnGround boolean
---@field selectedBlockType integer
---@field selectedBlockIndex integer
---@field firstPersonArm FirstPersonArm
---@field body PlayerBody
---@field isLocal boolean
---@field health number
---@field maxHealth number
---@field armor number
---@field attack number
---@field baseArmor number
---@field baseAttack number
---@field dead boolean
---@field attackCooldown number
---@field invulnTimer number
---@field inventory Inventory
---@field hunger number
---@field maxHunger number
---@field hungerTimer number
---@field starveTimer number
---@field effects table<string, { value: number, time: number }>
local Player = {}
Player.__index = Player

---创建新的玩家实例
---@param scene Scene 场景节点
---@return Player Player实例
function Player.new(scene)
    local self = setmetatable({}, Player)
    
    local BLOCK_SIZE = Config.World.BLOCK_SIZE
    local PLAYER_HEIGHT = Config.Player.HEIGHT
    
    -- 保存场景引用
    self.scene = scene
    
    -- 创建玩家节点
    self.node = scene:CreateChild("Player")
    self.node.position = Vector3(0, 100 * BLOCK_SIZE, 0)  -- 高处开始，会落到地面
    
    -- 创建相机节点（玩家子节点，位于眼睛高度）
    -- 加载景深（移动端不开启，节省性能）
    local platform = GetPlatform()
    if platform ~= "Android" and platform ~= "iOS" then
        self.cameraNode = scene:InstantiateXML("EngineRes/PostProcess/DOFPrefab.xml", Vector3.ZERO, Quaternion.IDENTITY, LOCAL)
        self.cameraNode.name = "Camera"
        self.cameraNode.parent = self.node
    else
        self.cameraNode = self.node:CreateChild("Camera", LOCAL)
    end
    -- 位置
    self.cameraNode.position = Vector3(0, (PLAYER_HEIGHT - 0.2) * BLOCK_SIZE, 0)
    
    -- 创建相机组件
    self.camera = self.cameraNode:CreateComponent("Camera", LOCAL)
    self.camera.farClip = Config.Camera.FAR_CLIP
    self.camera.fov = Config.Camera.FOV
    
    -- 状态
    self.velocity = Vector3(0, 0, 0)
    self.yaw = 0
    self.pitch = 0
    self.isOnGround = false
    self.selectedBlockType = Blocks.GRASS
    self.selectedBlockIndex = 1  -- 物品栏索引

    -- 战斗属性（护甲 / 攻击力由物品加成动态计算）
    self.health = Config.Player.HEALTH
    self.maxHealth = Config.Player.HEALTH
    self.baseArmor = Config.Player.ARMOR
    self.baseAttack = Config.Player.ATTACK
    self.armor = self.baseArmor
    self.attack = self.baseAttack
    self.dead = false
    self.attackCooldown = 0.0
    self.invulnTimer = Config.MobSpawning.SPAWN_GRACE

    -- 物品系统
    self.inventory = Inventory.new()
    self.hunger = Config.Items.HUNGER_MAX
    self.maxHunger = Config.Items.HUNGER_MAX
    self.hungerTimer = 0.0
    self.starveTimer = 0.0
    self.effects = {}

    -- 创建第一人称手臂
    self.firstPersonArm = FirstPersonArm.new(self, scene)
    
    -- 创建玩家身体（第三人称可见，联机时同步）
    self.body = PlayerBody.new(self)
    -- 初始状态隐藏身体（第一人称模式）
    self.body:setVisible(false)
    
    return self
end

---获取玩家位置
---@return Vector3 位置
function Player:getPosition()
    return self.node.position
end

---设置玩家位置
---@param pos Vector3 位置
function Player:setPosition(pos)
    self.node.position = pos
end

---获取眼睛位置（相机世界坐标）
---@return Vector3 眼睛位置
function Player:getEyePosition()
    if self.cameraNode then
        return self.cameraNode.worldPosition
    end
    -- 服务器/远程玩家：估算眼睛位置
    local BLOCK_SIZE = Config.World.BLOCK_SIZE
    local PLAYER_HEIGHT = Config.Player.HEIGHT
    return self.node.position + Vector3(0, (PLAYER_HEIGHT - 0.2) * BLOCK_SIZE, 0)
end

---获取视线方向
---@return Vector3 方向向量
function Player:getLookDirection()
    if self.cameraNode then
        return self.cameraNode.worldDirection
    end
    -- 服务器/远程玩家：从 yaw/pitch 计算
    return Quaternion(self.pitch, self.yaw, 0) * Vector3.FORWARD
end

---获取相机节点
---@return Node|nil 相机节点
function Player:getCameraNode()
    return self.cameraNode
end

---获取相机组件
---@return Camera|nil 相机组件
function Player:getCamera()
    return self.camera
end

---更新相机旋转
function Player:updateCamera()
    self.pitch = math.max(-89, math.min(89, self.pitch))
    if self.cameraNode then
        self.cameraNode.rotation = Quaternion(self.pitch, self.yaw, 0)
    end
end

---选择方块类型
---@param blockType number 方块类型
function Player:selectBlock(blockType)
    self.selectedBlockType = blockType
end

---选择快捷栏槽位（1-9）
---@param index number 槽位索引（1-9）
---@param _blockType number|nil 兼容旧调用（方块类型由背包里实际物品决定）
function Player:selectSlot(index, _blockType)
    index = math.max(1, math.min(9, math.floor(index or 1)))
    self.selectedBlockIndex = index
end

---兼容旧接口
---@param index number
function Player:selectHotbar(index)
    self:selectSlot(index)
end

---当前选中的物品堆
---@return ItemStack|nil
function Player:getSelectedStack()
    if not self.inventory then
        return nil
    end
    return self.inventory:getHotbarStack(self.selectedBlockIndex)
end

---获取当前选中的方块类型（选中的不是方块物品时返回 AIR）
---@return number 方块类型
function Player:getSelectedBlockType()
    local stack = self:getSelectedStack()
    local blockId = stack and stack:getBlockId()
    return blockId or Blocks.AIR
end

---获取当前选中的槽位索引（1-9）
---@return number 槽位索引
function Player:getSelectedSlotIndex()
    return self.selectedBlockIndex
end

---获取背包
---@return Inventory
function Player:getInventory()
    return self.inventory
end

---消耗当前选中的物品
---@param amount integer|nil
---@return boolean
function Player:consumeSelected(amount)
    if not self.inventory then
        return false
    end
    return self.inventory:consumeHotbar(self.selectedBlockIndex, amount or 1)
end

---消耗当前选中物品的耐久
---@param amount integer|nil
function Player:damageSelected(amount)
    if not self.inventory then
        return
    end
    local index = self.inventory:getHotbarIndex(self.selectedBlockIndex)
    self.inventory:damageSlot(index, amount or 1)
end

---设置速度
---@param velocity Vector3 速度向量
function Player:setVelocity(velocity)
    self.velocity = velocity
end

---获取速度
---@return Vector3 速度向量
function Player:getVelocity()
    return self.velocity
end

---设置是否在地面
---@param onGround boolean 是否在地面
function Player:setOnGround(onGround)
    self.isOnGround = onGround
end

---获取是否在地面
---@return boolean 是否在地面
function Player:getOnGround()
    return self.isOnGround
end

---设置偏航角
---@param yaw number 偏航角（度）
function Player:setYaw(yaw)
    self.yaw = yaw
end

---获取偏航角
---@return number 偏航角（度）
function Player:getYaw()
    return self.yaw
end

---设置俯仰角
---@param pitch number 俯仰角（度）
function Player:setPitch(pitch)
    self.pitch = pitch
end

---获取俯仰角
---@return number 俯仰角（度）
function Player:getPitch()
    return self.pitch
end

---更新玩家（每帧调用）
---@param timeStep number 时间步长
function Player:update(timeStep)
    -- 攻击冷却
    if self.attackCooldown > 0 then
        self.attackCooldown = self.attackCooldown - timeStep
    end

    -- 出生/重生无敌倒计时
    if self.invulnTimer > 0 then
        self.invulnTimer = self.invulnTimer - timeStep
        if self.invulnTimer < 0 then self.invulnTimer = 0 end
    end

    -- 饥饿值：缓慢下降；归零后持续掉血
    local itemCfg = Config.Items
    if not self.dead then
        self.hungerTimer = self.hungerTimer + timeStep
        if self.hungerTimer >= itemCfg.HUNGER_DRAIN_INTERVAL then
            self.hungerTimer = self.hungerTimer - itemCfg.HUNGER_DRAIN_INTERVAL
            if self.hunger > 0 then
                self.hunger = self.hunger - 1
            end
        end

        if self.hunger <= 0 then
            self.starveTimer = self.starveTimer + timeStep
            if self.starveTimer >= itemCfg.STARVE_DAMAGE_INTERVAL then
                self.starveTimer = self.starveTimer - itemCfg.STARVE_DAMAGE_INTERVAL
                self.health = self.health - itemCfg.STARVE_DAMAGE
                if self.health <= 0 then
                    self.health = 0
                    self.dead = true
                end
            end
        else
            self.starveTimer = 0.0
        end
    end

    -- 药水效果倒计时
    for kind, effect in pairs(self.effects) do
        effect.time = effect.time - timeStep
        if effect.time <= 0 then
            self.effects[kind] = nil
        end
    end

    -- 更新第一人称手臂动画
    if self.firstPersonArm then
        self.firstPersonArm:update(timeStep)
    end

    -- 更新玩家身体（行走动画等）
    if self.body then
        self.body:update(timeStep)
    end
end

---触发手臂挥动动画（攻击/放置方块时）
function Player:swingArm()
    -- 第一人称手臂动画
    if self.firstPersonArm then
        self.firstPersonArm:swing()
    end
    -- 第三人称身体手臂动画（联机时其他玩家可见）
    if self.body then
        self.body:swingArm()
    end
end

---设置第一人称手臂可见性
---@param visible boolean 是否可见
function Player:setArmVisible(visible)
    if self.firstPersonArm then
        self.firstPersonArm:setVisible(visible)
    end
end

---获取第一人称手臂实例
---@return table|nil FirstPersonArm实例
function Player:getFirstPersonArm()
    return self.firstPersonArm
end

---获取玩家身体实例
---@return table|nil PlayerBody实例
function Player:getBody()
    return self.body
end

---设置玩家身体可见性
---@param visible boolean 是否可见
function Player:setBodyVisible(visible)
    if self.body then
        self.body:setVisible(visible)
    end
end

-- ============================================
-- 战斗属性（Design.md：伤害 = 攻击力 / 护甲）
-- ============================================

---受击：伤害 = 攻击力 / 护甲（护甲 = 基础护甲 + 装备加成）
---@param rawAttack number 攻击者的攻击力
function Player:takeDamage(rawAttack)
    if self.dead or self.invulnTimer > 0 then
        return
    end
    local armor = math.max(1.0, self:getArmor())
    local damage = rawAttack / armor
    self.health = self.health - damage

    -- 护甲承受伤害时掉落耐久
    if self.inventory then
        self.inventory:damageEquippedArmor()
    end

    if self.health <= 0 then
        self.health = 0
        self.dead = true
    end
end

---当前护甲（基础 + 四件装备加成）
---@return number
function Player:getArmor()
    local bonus = self.inventory and self.inventory:getArmorBonus() or 0
    return self.baseArmor + bonus
end

---基础护甲
---@return number
function Player:getBaseArmor()
    return self.baseArmor
end

---回血
---@param amount number 回复量
function Player:heal(amount)
    self.health = self.health + amount
    if self.health > self.maxHealth then
        self.health = self.maxHealth
    end
    self.dead = false
end

---完全复活（重生），并给一段无敌时间
---@param grace number|nil 无敌秒数（默认取配置）
function Player:respawn(grace)
    self.health = self.maxHealth
    self.dead = false
    self.invulnTimer = grace or Config.MobSpawning.SPAWN_GRACE
end

---设置无敌时间
---@param seconds number
function Player:setInvulnerable(seconds)
    self.invulnTimer = seconds
end

---是否处于无敌状态
---@return boolean
function Player:isInvulnerable()
    return self.invulnTimer > 0
end

---获取血量
---@return number
function Player:getHealth()
    return self.health
end

---获取最大血量
---@return number
function Player:getMaxHealth()
    return self.maxHealth
end

---当前攻击力（基础 + 手上武器加成 + 力量药水）
---@return number
function Player:getAttack()
    local bonus = 0
    if self.inventory then
        bonus = self.inventory:getHeldAttackBonus(self.selectedBlockIndex)
    end
    local strength = self.effects["strength"]
    if strength then
        bonus = bonus + strength.value
    end
    return self.baseAttack + bonus
end

---是否死亡
---@return boolean
function Player:isDead()
    return self.dead
end

---攻击生物（带冷却，攻击会消耗武器耐久）
---@param mob Mob 目标生物
---@return boolean 是否成功攻击
function Player:attackMob(mob)
    if self.attackCooldown > 0 then
        return false
    end
    mob:takeDamage(self:getAttack())
    self.attackCooldown = Config.Player.ATTACK_COOLDOWN
    self:damageSelected(Config.Items.ATTACK_DURABILITY_COST)
    return true
end

-- ============================================
-- 饥饿 / 食物 / 药水效果
-- ============================================

---进食：恢复饥饿值和生命
---@param hunger number 恢复的饥饿值
---@param healAmount number|nil 恢复的生命
function Player:eat(hunger, healAmount)
    self.hunger = math.min(self.maxHunger, self.hunger + (hunger or 0))
    if healAmount and healAmount > 0 then
        self:heal(healAmount)
    end
end

---@return number
function Player:getHunger()
    return self.hunger
end

---@return number
function Player:getMaxHunger()
    return self.maxHunger
end

---设置饥饿值（存档恢复用）
---@param value number
function Player:setHunger(value)
    self.hunger = math.max(0, math.min(self.maxHunger, value))
end

---施加药水效果
---@param kind string "strength"/"speed"
---@param value number
---@param duration number 秒
function Player:applyEffect(kind, value, duration)
    self.effects[kind] = { value = value, time = duration or 30 }
end

---当前某种效果的数值（没有则 0）
---@param kind string
---@return number
function Player:getEffectValue(kind)
    local effect = self.effects[kind]
    return effect and effect.value or 0
end

---移动速度倍率（迅捷药水）
---@return number
function Player:getSpeedMultiplier()
    return 1.0 + self:getEffectValue("speed")
end

-- ============================================
-- 网络模式支持
-- ============================================

---从已有节点创建玩家（联机/单机通用）
---@param node Node 玩家节点
---@param isLocal boolean 是否为本地玩家
---@return Player Player实例
function Player.fromNode(node, isLocal)
    local self = setmetatable({}, Player)

    self.node = node
    self.scene = node.scene
    self.isLocal = isLocal

    -- 状态初始化
    self.velocity = Vector3(0, 0, 0)
    self.yaw = 0
    self.pitch = 0
    self.isOnGround = false
    self.selectedBlockType = Blocks.GRASS
    self.selectedBlockIndex = 1

    -- 战斗属性（护甲 / 攻击力由物品加成动态计算）
    self.health = Config.Player.HEALTH
    self.maxHealth = Config.Player.HEALTH
    self.baseArmor = Config.Player.ARMOR
    self.baseAttack = Config.Player.ATTACK
    self.armor = self.baseArmor
    self.attack = self.baseAttack
    self.dead = false
    self.attackCooldown = 0.0
    self.invulnTimer = Config.MobSpawning.SPAWN_GRACE

    -- 物品系统
    self.inventory = Inventory.new()
    self.hunger = Config.Items.HUNGER_MAX
    self.maxHunger = Config.Items.HUNGER_MAX
    self.hungerTimer = 0.0
    self.starveTimer = 0.0
    self.effects = {}

    -- 服务器：不创建任何渲染组件
    if IsServerMode() then
        self.cameraNode = nil
        self.camera = nil
        self.firstPersonArm = nil
        self.body = nil
        return self
    end

    -- 本地玩家：创建相机和手臂
    if isLocal then
        self:createCamera()
        self.firstPersonArm = FirstPersonArm.new(self, self.scene)
        self.body = PlayerBody.new(self)
        self.body:setVisible(false)
    else
        -- 远程玩家：只创建可见的身体
        self.cameraNode = nil
        self.camera = nil
        self.firstPersonArm = nil
        self.body = PlayerBody.new(self)
        self.body:setVisible(true)
    end

    return self
end

---创建相机（内部方法）
function Player:createCamera()
    local BLOCK_SIZE = Config.World.BLOCK_SIZE
    local PLAYER_HEIGHT = Config.Player.HEIGHT

    -- 创建相机节点（LOCAL 模式，不同步）
    local mode = IsNetworkMode() and LOCAL or nil
    -- 加载景深（移动端不开启，节省性能）
    local platform = GetPlatform()
    if platform ~= "Android" and platform ~= "iOS" then
        self.cameraNode = self.scene:InstantiateXML("EngineRes/PostProcess/DOFPrefab.xml", Vector3.ZERO, Quaternion.IDENTITY, mode)
        self.cameraNode.name = "Camera"
        self.cameraNode.parent = self.node
    else
        self.cameraNode = self.node:CreateChild("Camera", mode)
    end
    self.cameraNode.position = Vector3(0, (PLAYER_HEIGHT - 0.2) * BLOCK_SIZE, 0)

    -- 创建相机组件
    self.camera = self.cameraNode:CreateComponent("Camera", mode)
    self.camera.farClip = Config.Camera.FAR_CLIP
    self.camera.fov = Config.Camera.FOV
end

return Player
