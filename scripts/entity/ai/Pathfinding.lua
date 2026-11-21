-- ====================================================================
-- entity/ai/Pathfinding.lua
-- 方块级 A* 寻路 + 视线检测（供生物 AI 使用）
--
-- 设计约束（Design.md「AI机制」）：
--   - 支持方块地形、绕障、上下台阶（≤ STEP_HEIGHT=1 格）、允许有限下落
--   - 不允许穿墙 / 进入无法容纳生物碰撞体的空间 / 进入液体
--   - 结果按目标移动 / 路径受阻时才重算，尽量缓存复用（由 AIController 决定重算时机）
--
-- 实现要点：
--   - 节点 = 方块坐标 (x, y, z)，y 是生物「脚」所在层（可站立层）
--   - 4 邻域水平移动；垂直方向用 resolveFootY 一次求出「可站立的新脚部层」，
--     天然支持登高 1 格、同层、下落（≤ MAX_FALL 格）
--   - 启发式用曼哈顿距离（XZ + 垂直），step 成本对垂直变化加权，让路径尽量贴地
--   - 二叉堆加速 open 表；搜索预算 PATH_MAX_NODES 防止卡死
-- ====================================================================

local Config = require("config.GameConfig")
local Blocks = require("data.BlockRegistry")

local BLOCK_SIZE = Config.World.BLOCK_SIZE
local WORLD_HEIGHT = Config.World.WORLD_HEIGHT

local Pathfinding = {}

-- 水平四邻域
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

---该格是否阻挡生物移动（固体或液体）
---@param world World
---@param bx integer
---@param by integer
---@param bz integer
---@return boolean
local function isBlocking(world, bx, by, bz)
    if by < 0 or by >= WORLD_HEIGHT then
        return true
    end
    local b = world:getBlock(bx, by, bz)
    return Blocks:isSolid(b) or Blocks:isLiquid(b)
end

---生物能否站在 (x, y, z)：脚下是固体，身体各格（含头部）都非固体非液体
---@param world World
---@param x integer
---@param y integer
---@param z integer
---@param height integer 生物占高（格）
---@return boolean
function Pathfinding.isStandable(world, x, y, z, height)
    if y < 1 or y >= WORLD_HEIGHT then
        return false
    end
    if not Blocks:isSolid(world:getBlock(x, y - 1, z)) then
        return false
    end
    for dy = 0, height - 1 do
        if y + dy >= WORLD_HEIGHT then
            return false
        end
        if isBlocking(world, x, y + dy, z) then
            return false
        end
    end
    return true
end

---从 (x,z) 的 fromY 出发，求该列「可站立的新脚部层」：
---先试登高 1 格，再同层，再下落最多 maxFall 格。找不到返回 nil。
---@param world World
---@param x integer
---@param z integer
---@param fromY integer
---@param height integer
---@param maxFall integer
---@return integer|nil
local function resolveFootY(world, x, z, fromY, height, maxFall)
    for dy = 1, -maxFall, -1 do
        local y = fromY + dy
        if Pathfinding.isStandable(world, x, y, z, height) then
            return y
        end
    end
    return nil
end

-- ====================================================================
-- 二叉最小堆（按 f 值排序）
-- ====================================================================

---@param heap {f:number,x:integer,y:integer,z:integer}[]
---@param node {f:number,x:integer,y:integer,z:integer}
local function heapPush(heap, node)
    heap[#heap + 1] = node
    local i = #heap
    while i > 1 do
        local p = math.floor(i / 2)
        if heap[p].f <= node.f then
            break
        end
        heap[i], heap[p] = heap[p], heap[i]
        i = p
    end
end

---@param heap {f:number,x:integer,y:integer,z:integer}[]
---@return {f:number,x:integer,y:integer,z:integer}|nil
local function heapPop(heap)
    local top = heap[1]
    if not top then
        return nil
    end
    local last = heap[#heap]
    heap[1] = last
    heap[#heap] = nil
    local n = #heap
    if n > 0 then
        local i = 1
        while true do
            local l = i * 2
            local r = l + 1
            local smallest = i
            if l <= n and heap[l].f < heap[smallest].f then smallest = l end
            if r <= n and heap[r].f < heap[smallest].f then smallest = r end
            if smallest == i then break end
            heap[i], heap[smallest] = heap[smallest], heap[i]
            i = smallest
        end
    end
    return top
end

---删除路径中同一直线上（水平方向不变且高度不变）的冗余中间点，减少锯齿
---@param path {x:integer,y:integer,z:integer}[]
---@return {x:integer,y:integer,z:integer}[]
local function smoothPath(path)
    if not path or #path <= 2 then
        return path
    end
    local out = { path[1] }
    for i = 2, #path - 1 do
        local prev = out[#out]
        local cur = path[i]
        local next = path[i + 1]
        local sameX = (cur.x - prev.x) == (next.x - cur.x)
        local sameZ = (cur.z - prev.z) == (next.z - cur.z)
        local sameY = cur.y == prev.y and next.y == cur.y
        if not (sameX and sameZ and sameY) then
            out[#out + 1] = cur
        end
    end
    out[#out + 1] = path[#path]
    return out
end

---方块级 A* 寻路
---@param world World
---@param startX integer
---@param startY integer
---@param startZ integer
---@param goalX integer
---@param goalZ integer
---@param height integer 生物占高（格）
---@return {x:integer,y:integer,z:integer}[]|nil 从起点到终点的方块路径（含起点）
function Pathfinding.findPath(world, startX, startY, startZ, goalX, goalZ, height)
    local maxNodes = Config.MobAI.PATH_MAX_NODES
    local maxFall = Config.MobAI.MAX_FALL

    if startX == goalX and startZ == goalZ then
        return { { x = startX, y = startY, z = startZ } }
    end

    local function key(x, y, z)
        return x .. "," .. y .. "," .. z
    end

    local gScore = {}
    local cameFrom = {}
    local closed = {}
    local open = {}

    local startKey = key(startX, startY, startZ)
    gScore[startKey] = 0
    heapPush(open, {
        f = math.abs(startX - goalX) + math.abs(startZ - goalZ),
        x = startX, y = startY, z = startZ,
    })

    local found = nil
    local visited = 0

    while #open > 0 and visited < maxNodes do
        local cur = heapPop(open)
        local ck = key(cur.x, cur.y, cur.z)
        if not closed[ck] then
            closed[ck] = true
            visited = visited + 1

            if cur.x == goalX and cur.z == goalZ then
                found = cur
                break
            end

            for _, d in ipairs(DIRS) do
                local nx = cur.x + d[1]
                local nz = cur.z + d[2]
                local ny = resolveFootY(world, nx, nz, cur.y, height, maxFall)
                if ny then
                    local nk = key(nx, ny, nz)
                    if not closed[nk] then
                        local stepCost = 1.0 + math.abs(ny - cur.y) * 0.5
                        local ng = gScore[ck] + stepCost
                        if ng < (gScore[nk] or math.huge) then
                            gScore[nk] = ng
                            cameFrom[nk] = { x = cur.x, y = cur.y, z = cur.z }
                            heapPush(open, {
                                f = ng + math.abs(nx - goalX) + math.abs(nz - goalZ) + math.abs(ny - startY),
                                x = nx, y = ny, z = nz,
                            })
                        end
                    end
                end
            end
        end
    end

    if not found then
        return nil
    end

    -- 回溯重建路径
    local path = {}
    local node = found
    while node do
        path[#path + 1] = node
        node = cameFrom[key(node.x, node.y, node.z)]
    end
    for i = 1, math.floor(#path / 2) do
        path[i], path[#path - i + 1] = path[#path - i + 1], path[i]
    end

    return smoothPath(path)
end

---视线检测：从 from 到 to 的世界坐标连线是否被固体方块遮挡
---@param world World
---@param from Vector3
---@param to Vector3
---@return boolean true = 无遮挡（看得见）
function Pathfinding.hasLineOfSight(world, from, to)
    local dx = to.x - from.x
    local dy = to.y - from.y
    local dz = to.z - from.z
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist < 1e-4 then
        return true
    end

    local step = Config.MobAI.LOS_STEP * BLOCK_SIZE
    local steps = math.max(1, math.floor(dist / step))
    for i = 1, steps - 1 do
        local t = i / steps
        local px = from.x + dx * t
        local py = from.y + dy * t
        local pz = from.z + dz * t
        local bx = math.floor(px / BLOCK_SIZE)
        local by = math.floor(py / BLOCK_SIZE)
        local bz = math.floor(pz / BLOCK_SIZE)
        if Blocks:isSolid(world:getBlock(bx, by, bz)) then
            return false
        end
    end
    return true
end

return Pathfinding
