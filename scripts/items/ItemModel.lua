-- ====================================================================
-- items/ItemModel.lua
-- 非方块物品的 3D 模型（数据驱动 + 程序化网格）
--
--   - 每个物品由若干基本体（长方体 / 圆柱 / 八面体）拼出来
--   - 顶点色 + 受光材质（DiffVCol），和世界的方块光照一致
--   - 同一份模型数据供两处使用：
--       ItemEntity（地面掉落物）
--       FirstPersonArm（第一人称手持）
--
-- 局部坐标：Y 向上，[-1,1] 左右；物品整体约 1 单位高，
-- 显示时由 dropScale / held.scale 缩放到世界尺寸。
-- ====================================================================

---@class ItemPart
---@field kind string "box" | "cyl" | "octa"
---@field x number
---@field y number
---@field z number
---@field sx number
---@field sy number
---@field sz number
---@field r number
---@field h number
---@field sides number
---@field color number[]
---@field rx number
---@field ry number
---@field rz number

---@class ItemModelSpec
---@field parts ItemPart[]
---@field dropScale number|nil
---@field held table|nil

local ItemModel = {}

-- ====================================================================
-- 调色板
-- ====================================================================
local STEEL       = { 0.76, 0.80, 0.84 }
local STEEL_L     = { 0.92, 0.94, 0.97 }
local STEEL_D     = { 0.48, 0.52, 0.58 }
local GOLD        = { 0.94, 0.77, 0.28 }
local GOLD_D      = { 0.68, 0.50, 0.12 }
local WOOD        = { 0.54, 0.36, 0.19 }
local WOOD_D      = { 0.36, 0.23, 0.11 }
local WOOD_L      = { 0.68, 0.48, 0.28 }
local RED         = { 0.82, 0.24, 0.20 }
local RED_L       = { 0.94, 0.44, 0.38 }
local GREEN       = { 0.36, 0.64, 0.28 }
local WHITE       = { 0.94, 0.94, 0.91 }
local WHITE_D     = { 0.74, 0.76, 0.72 }
local DARK        = { 0.24, 0.23, 0.21 }
local DARK_L      = { 0.36, 0.35, 0.34 }
local BROWN       = { 0.50, 0.33, 0.20 }
local TAN         = { 0.85, 0.66, 0.38 }
local TAN_D       = { 0.65, 0.46, 0.22 }
local TAN_L       = { 0.93, 0.76, 0.48 }
local PINK        = { 0.92, 0.55, 0.52 }
local PINK_L      = { 0.96, 0.76, 0.72 }
local PALE        = { 0.93, 0.83, 0.66 }
local ROTTEN      = { 0.42, 0.46, 0.28 }
local ROTTEN_D    = { 0.28, 0.32, 0.18 }
local BLUE        = { 0.34, 0.65, 0.93 }
local BLUE_L      = { 0.62, 0.82, 0.97 }
local CYAN        = { 0.34, 0.85, 0.88 }
local CYAN_L      = { 0.62, 0.94, 0.96 }
local ORANGE      = { 0.93, 0.50, 0.20 }
local GLASS       = { 0.78, 0.86, 0.88 }
local GRAY        = { 0.60, 0.62, 0.66 }
local GRAY_L      = { 0.78, 0.80, 0.84 }
local GRAY_D      = { 0.38, 0.40, 0.44 }

-- ====================================================================
-- 基本体构造
-- ====================================================================

---@return ItemPart
local function B(x, y, z, sx, sy, sz, color, rx, ry, rz)
    return {
        kind = "box", x = x, y = y, z = z, sx = sx, sy = sy, sz = sz,
        r = 0, h = 0, sides = 0, color = color,
        rx = rx or 0, ry = ry or 0, rz = rz or 0,
    }
end

---@return ItemPart
local function CY(x, y, z, r, h, color, sides)
    return {
        kind = "cyl", x = x, y = y, z = z, sx = 0, sy = 0, sz = 0,
        r = r, h = h, sides = sides or 10, color = color,
        rx = 0, ry = 0, rz = 0,
    }
end

---@return ItemPart
local function O(x, y, z, r, color)
    return {
        kind = "octa", x = x, y = y, z = z, sx = 0, sy = 0, sz = 0,
        r = r, h = 0, sides = 0, color = color,
        rx = 0, ry = 0, rz = 0,
    }
end

-- ====================================================================
-- 网格生成
-- ====================================================================
local rad = math.rad
local cos = math.cos
local sin = math.sin
local sqrt = math.sqrt
local PI2 = math.pi * 2

---欧拉旋转（Z → X → Y），返回旋转后的坐标
---@return number x
---@return number y
---@return number z
local function rotatePoint(x, y, z, rx, ry, rz)
    if rz ~= 0 then
        local a = rad(rz)
        local c, s = cos(a), sin(a)
        x, y = x * c - y * s, x * s + y * c
    end
    if rx ~= 0 then
        local a = rad(rx)
        local c, s = cos(a), sin(a)
        y, z = y * c - z * s, y * s + z * c
    end
    if ry ~= 0 then
        local a = rad(ry)
        local c, s = cos(a), sin(a)
        x, z = x * c + z * s, -x * s + z * c
    end
    return x, y, z
end

---发射一个三角形（法线由顶点绕序计算，保证与背面剔除一致）
---@param geom CustomGeometry
---@param p1 Vector3
---@param p2 Vector3
---@param p3 Vector3
---@param color Color
local function emitTri(geom, p1, p2, p3, color)
    local ux, uy, uz = p2.x - p1.x, p2.y - p1.y, p2.z - p1.z
    local vx, vy, vz = p3.x - p1.x, p3.y - p1.y, p3.z - p1.z
    local nx = uy * vz - uz * vy
    local ny = uz * vx - ux * vz
    local nz = ux * vy - uy * vx
    local len = sqrt(nx * nx + ny * ny + nz * nz)
    if len < 1e-6 then
        return
    end
    local normal = Vector3(nx / len, ny / len, nz / len)
    geom:DefineVertex(p1)
    geom:DefineNormal(normal)
    geom:DefineColor(color)
    geom:DefineVertex(p2)
    geom:DefineNormal(normal)
    geom:DefineColor(color)
    geom:DefineVertex(p3)
    geom:DefineNormal(normal)
    geom:DefineColor(color)
end

---长方体 6 个面的顶点索引（与 FirstPersonArm 的绕序一致）
local BOX_FACES = {
    { 2, 3, 7 }, { 2, 7, 6 },   -- +X
    { 5, 8, 4 }, { 5, 4, 1 },   -- -X
    { 4, 8, 7 }, { 4, 7, 3 },   -- +Y
    { 5, 1, 2 }, { 5, 2, 6 },   -- -Y
    { 5, 6, 7 }, { 5, 7, 8 },   -- +Z
    { 2, 1, 4 }, { 2, 4, 3 },   -- -Z
}

---@param geom CustomGeometry
---@param part ItemPart
---@param color Color
local function emitBox(geom, part, color)
    local hx, hy, hz = part.sx * 0.5, part.sy * 0.5, part.sz * 0.5
    -- 8 个角：索引 1..8 与 BOX_FACES 对应
    ---@type number[][]
    local raw = {
        { -hx, -hy, -hz }, { hx, -hy, -hz }, { hx, hy, -hz }, { -hx, hy, -hz },
        { -hx, -hy, hz }, { hx, -hy, hz }, { hx, hy, hz }, { -hx, hy, hz },
    }
    local pts = {}
    for i = 1, 8 do
        local p = raw[i]
        if p then
            local x, y, z = rotatePoint(p[1] or 0, p[2] or 0, p[3] or 0, part.rx, part.ry, part.rz)
            pts[i] = Vector3(part.x + x, part.y + y, part.z + z)
        end
    end
    for i = 1, #BOX_FACES do
        local f = BOX_FACES[i]
        emitTri(geom, pts[f[1]], pts[f[2]], pts[f[3]], color)
    end
end

---@param geom CustomGeometry
---@param part ItemPart
---@param color Color
local function emitCylinder(geom, part, color)
    local n = part.sides
    if n < 3 then n = 10 end
    local r, hh = part.r, part.h * 0.5
    local ringBot, ringTop = {}, {}
    for i = 1, n do
        local a = (i - 1) * PI2 / n
        local x, z = r * cos(a), r * sin(a)
        local bx, by, bz = rotatePoint(x, -hh, z, part.rx, part.ry, part.rz)
        local tx, ty, tz = rotatePoint(x, hh, z, part.rx, part.ry, part.rz)
        ringBot[i] = Vector3(part.x + bx, part.y + by, part.z + bz)
        ringTop[i] = Vector3(part.x + tx, part.y + ty, part.z + tz)
    end
    for i = 1, n do
        local j = i % n + 1
        emitTri(geom, ringBot[i], ringTop[i], ringTop[j], color)
        emitTri(geom, ringBot[i], ringTop[j], ringBot[j], color)
    end
    local cx, cy, cz = rotatePoint(0, hh, 0, part.rx, part.ry, part.rz)
    local centerTop = Vector3(part.x + cx, part.y + cy, part.z + cz)
    local bx2, by2, bz2 = rotatePoint(0, -hh, 0, part.rx, part.ry, part.rz)
    local centerBot = Vector3(part.x + bx2, part.y + by2, part.z + bz2)
    for i = 1, n do
        local j = i % n + 1
        emitTri(geom, centerTop, ringTop[i], ringTop[j], color)
        emitTri(geom, centerBot, ringBot[j], ringBot[i], color)
    end
end

---@param geom CustomGeometry
---@param part ItemPart
---@param color Color
local function emitOctahedron(geom, part, color)
    local r = part.r
    local top = Vector3(0, r, 0)
    local bot = Vector3(0, -r, 0)
    local eq = {
        Vector3(r, 0, 0),
        Vector3(0, 0, r),
        Vector3(-r, 0, 0),
        Vector3(0, 0, -r),
    }
    local function world(v)
        local x, y, z = rotatePoint(v.x, v.y, v.z, part.rx, part.ry, part.rz)
        return Vector3(part.x + x, part.y + y, part.z + z)
    end
    local wt, wb = world(top), world(bot)
    local we = {}
    for i = 1, 4 do we[i] = world(eq[i]) end
    for i = 1, 4 do
        local j = i % 4 + 1
        -- 上半：绕序反向（外法线朝上、朝外）
        emitTri(geom, wt, we[j], we[i], color)
        -- 下半：绕序正向
        emitTri(geom, wb, we[i], we[j], color)
    end
end

---@param geometry CustomGeometry
---@param spec ItemModelSpec
local function emitSpec(geometry, spec)
    for _, part in ipairs(spec.parts) do
        local c = part.color
        local color = Color(c[1] or 0, c[2] or 0, c[3] or 0, 1)
        if part.kind == "box" then
            emitBox(geometry, part, color)
        elseif part.kind == "cyl" then
            emitCylinder(geometry, part, color)
        elseif part.kind == "octa" then
            emitOctahedron(geometry, part, color)
        end
    end
end

-- ====================================================================
-- 物品模型数据
-- ====================================================================

---@type table<string, ItemModelSpec>
local SPECS = {
    -- ==================== 材料 ====================
    stick = {
        parts = { B(0, 0, 0, 0.08, 0.95, 0.08, WOOD, 0, 0, 20), B(0.01, 0.22, 0, 0.03, 0.34, 0.03, WOOD_L, 0, 0, 20) },
        held = { scale = 0.62, ry = 30, rz = -25 },
    },
    coal = {
        parts = {
            B(0, 0, 0, 0.34, 0.32, 0.32, DARK, 8, 18, 6),
            B(0.17, -0.12, 0.05, 0.18, 0.17, 0.18, DARK_L, 0, 22, 0),
            B(-0.16, 0.08, -0.05, 0.16, 0.15, 0.16, DARK_L, 0, -16, 0),
        },
        held = { scale = 0.66, ry = 30, rz = -15 },
    },
    iron_ingot = {
        parts = {
            B(0, 0.02, 0, 0.62, 0.16, 0.34, STEEL_L, 0, 0, 0),
            B(0, -0.10, 0, 0.56, 0.10, 0.30, STEEL, 0, 0, 0),
            B(0, 0.11, 0, 0.44, 0.04, 0.24, STEEL_D, 0, 0, 0),
        },
        held = { scale = 0.75, ry = 30, rz = -10 },
    },
    gold_ingot = {
        parts = {
            B(0, 0.02, 0, 0.62, 0.16, 0.34, { 0.99, 0.88, 0.44 }, 0, 0, 0),
            B(0, -0.10, 0, 0.56, 0.10, 0.30, GOLD, 0, 0, 0),
            B(0, 0.11, 0, 0.44, 0.04, 0.24, GOLD_D, 0, 0, 0),
        },
        held = { scale = 0.75, ry = 30, rz = -10 },
    },
    diamond = {
        parts = {
            O(0, 0, 0, 0.46, CYAN),
            O(0, 0.02, 0, 0.26, CYAN_L),
        },
        held = { scale = 0.62, ry = 30, rz = -8 },
    },
    leather = {
        parts = {
            B(0, 0, 0, 0.72, 0.10, 0.56, BROWN, 0, 0, 4),
            B(0, 0.07, 0.10, 0.50, 0.035, 0.07, { 0.72, 0.52, 0.34 }, 0, 0, 4),
            B(0, 0.07, -0.12, 0.42, 0.035, 0.06, { 0.72, 0.52, 0.34 }, 0, 0, 4),
        },
        held = { scale = 0.72, ry = 30, rz = -5 },
    },
    feather = {
        parts = {
            B(0, 0, 0, 0.05, 0.98, 0.05, WHITE_D, 0, 0, 24),
            B(0.05, 0.14, 0, 0.24, 0.62, 0.04, WHITE, 0, 0, 24),
            B(-0.02, 0.46, 0, 0.14, 0.20, 0.04, WHITE, 0, 0, 24),
        },
        held = { scale = 0.66, ry = 30, rz = -20 },
    },
    string = {
        parts = {
            B(0, 0, 0, 0.50, 0.06, 0.06, WHITE, 0, 0, 0),
            B(0, 0.20, 0, 0.42, 0.06, 0.06, WHITE, 0, 0, 12),
            B(0, -0.20, 0, 0.42, 0.06, 0.06, WHITE, 0, 0, -12),
            B(0, 0.33, 0, 0.14, 0.08, 0.06, WHITE, 0, 0, 0),
        },
        held = { scale = 0.62, ry = 30, rz = -10 },
    },
    gunpowder = {
        parts = {
            B(0, -0.08, 0, 0.52, 0.46, 0.46, DARK, 0, 0, 0),
            B(0, 0.20, 0, 0.24, 0.16, 0.24, DARK_L, 0, 0, 0),
            B(0, 0.32, 0, 0.16, 0.12, 0.16, BROWN, 0, 0, 0),
            B(0, 0.41, 0, 0.24, 0.06, 0.12, BROWN, 0, 0, 0),
        },
        held = { scale = 0.62, ry = 30, rz = -10 },
    },
    ectoplasm = {
        parts = {
            O(0, 0, 0, 0.46, { 0.62, 0.82, 0.94 }),
            O(0.20, 0.22, 0.10, 0.20, { 0.76, 0.92, 0.98 }),
            O(-0.22, -0.18, 0.04, 0.14, { 0.76, 0.92, 0.98 }),
        },
        held = { scale = 0.62, ry = 30, rz = -8 },
    },
    wheat = {
        parts = {
            B(-0.16, 0, 0, 0.05, 0.95, 0.05, { 0.58, 0.42, 0.18 }, 0, 0, -5),
            B(0.00, 0, 0, 0.05, 0.98, 0.05, { 0.58, 0.42, 0.18 }, 0, 0, 0),
            B(0.16, 0, 0, 0.05, 0.95, 0.05, { 0.58, 0.42, 0.18 }, 0, 0, 5),
            B(-0.16, 0.40, 0, 0.13, 0.24, 0.13, GOLD, 0, 0, -5),
            B(0.00, 0.44, 0, 0.13, 0.24, 0.13, GOLD, 0, 0, 0),
            B(0.16, 0.40, 0, 0.13, 0.24, 0.13, GOLD, 0, 0, 5),
            B(0, -0.44, 0, 0.40, 0.08, 0.10, BROWN, 0, 0, 0),
        },
        held = { scale = 0.62, ry = 30, rz = -12 },
    },
    arrow = {
        parts = {
            B(0, 0, 0, 0.06, 0.98, 0.06, WOOD, 0, 0, 22),
            B(0, 0.50, 0, 0.13, 0.20, 0.05, STEEL, 0, 0, 22),
            B(0, -0.42, 0, 0.20, 0.18, 0.04, WHITE, 0, 0, 22),
            B(0, -0.32, 0, 0.22, 0.08, 0.04, RED, 0, 0, 22),
        },
        held = { scale = 0.62, ry = 30, rz = -25 },
    },

    -- ==================== 食物 ====================
    apple = {
        parts = {
            O(0, 0, 0, 0.44, RED),
            O(0.04, 0.06, 0.04, 0.26, RED_L),
            B(0, 0.48, 0, 0.05, 0.16, 0.05, WOOD_D),
            B(0.13, 0.52, 0.02, 0.22, 0.05, 0.12, GREEN, 0, 0, 18),
        },
        held = { scale = 0.60, ry = 30, rz = -10 },
    },
    bread = {
        parts = {
            B(0, 0, 0, 0.82, 0.36, 0.42, TAN, 0, 0, 0),
            B(0, 0.17, 0, 0.70, 0.08, 0.32, TAN_L, 0, 0, 0),
            B(-0.20, 0.22, 0, 0.05, 0.03, 0.30, TAN_D, 0, 0, 12),
            B(0.00, 0.22, 0, 0.05, 0.03, 0.30, TAN_D, 0, 0, 12),
            B(0.20, 0.22, 0, 0.05, 0.03, 0.30, TAN_D, 0, 0, 12),
        },
        held = { scale = 0.66, ry = 30, rz = -10 },
    },
    beef = {
        parts = {
            B(0, 0, 0, 0.78, 0.16, 0.56, RED, 0, 0, 5),
            B(0.10, 0.08, 0.08, 0.28, 0.03, 0.08, RED_L, 0, 0, 25),
            B(-0.16, 0.08, -0.10, 0.24, 0.03, 0.07, RED_L, 0, 0, 40),
            B(0.20, 0.08, -0.14, 0.16, 0.03, 0.06, RED_L, 0, 0, 10),
        },
        held = { scale = 0.66, ry = 30, rz = -8 },
    },
    porkchop = {
        parts = {
            B(0, 0, 0, 0.66, 0.18, 0.50, PINK, 0, 0, 6),
            B(0.18, 0.09, 0.06, 0.24, 0.03, 0.10, PINK_L, 0, 0, 15),
            B(-0.30, 0.06, 0, 0.18, 0.10, 0.14, WHITE, 0, 0, 10),
        },
        held = { scale = 0.66, ry = 30, rz = -8 },
    },
    chicken_meat = {
        parts = {
            B(0, 0, 0, 0.42, 0.36, 0.32, PALE, 0, 0, 8),
            B(0.30, 0.04, 0, 0.34, 0.08, 0.08, WHITE, 0, 0, -20),
            B(0.47, 0.10, 0, 0.12, 0.12, 0.10, WHITE, 0, 0, -20),
        },
        held = { scale = 0.66, ry = 30, rz = -10 },
    },
    rotten_flesh = {
        parts = {
            B(0, 0, 0, 0.72, 0.16, 0.52, ROTTEN, 0, 0, 4),
            B(0.08, 0.08, 0.02, 0.14, 0.04, 0.12, ROTTEN_D, 0, 0, 20),
            B(-0.18, 0.08, -0.06, 0.10, 0.04, 0.10, ROTTEN_D, 0, 0, 0),
            B(0.22, 0.08, -0.08, 0.08, 0.04, 0.08, ROTTEN_D, 0, 0, 0),
        },
        held = { scale = 0.66, ry = 30, rz = -8 },
    },

    -- ==================== 武器 / 工具 ====================
    sword = {
        parts = {
            B(0, 0.18, 0, 0.11, 0.84, 0.035, STEEL, 0, 0, 0),
            B(0, 0.64, 0, 0.07, 0.14, 0.03, STEEL_L, 0, 0, 0),
            B(0, -0.20, 0, 0.44, 0.08, 0.12, GOLD, 0, 0, 0),
            B(0, -0.38, 0, 0.10, 0.30, 0.10, WOOD_D, 0, 0, 0),
            B(0, -0.56, 0, 0.16, 0.10, 0.13, GOLD, 0, 0, 0),
        },
        held = { scale = 0.64, ry = 35, rz = -18, y = 0.02 },
    },
    bow = {
        parts = {
            B(-0.16, 0.30, 0, 0.08, 0.46, 0.08, WOOD, 0, 0, -24),
            B(-0.235, 0.155, 0, 0.08, 0.22, 0.08, WOOD, 0, 0, -12),
            B(-0.28, 0.00, 0, 0.08, 0.42, 0.08, WOOD, 0, 0, 0),
            B(-0.235, -0.155, 0, 0.08, 0.22, 0.08, WOOD, 0, 0, 12),
            B(-0.16, -0.30, 0, 0.08, 0.46, 0.08, WOOD, 0, 0, 24),
            B(-0.06, 0, 0, 0.03, 0.98, 0.03, WHITE, 0, 0, 0),
            B(-0.28, 0, 0, 0.11, 0.14, 0.11, WOOD_D, 0, 0, 0),
        },
        held = { scale = 0.62, ry = 60, rz = -10 },
    },
    pickaxe = {
        parts = {
            B(0, 0, 0, 0.08, 0.98, 0.08, WOOD, 0, 0, 0),
            B(0, 0.42, 0, 0.78, 0.14, 0.12, STEEL, 0, 0, 0),
            B(-0.42, 0.30, 0, 0.16, 0.12, 0.10, STEEL, 0, 0, 28),
            B(0.42, 0.30, 0, 0.16, 0.12, 0.10, STEEL, 0, 0, -28),
        },
        held = { scale = 0.64, ry = 35, rz = -15 },
    },
    axe = {
        parts = {
            B(0, 0, 0, 0.08, 0.98, 0.08, WOOD, 0, 0, 0),
            B(0.20, 0.40, 0, 0.38, 0.36, 0.12, STEEL, 0, 0, 0),
            B(0.40, 0.34, 0, 0.16, 0.42, 0.08, STEEL_L, 0, 0, -8),
        },
        held = { scale = 0.64, ry = 35, rz = -15 },
    },
    shovel = {
        parts = {
            B(0, 0, 0, 0.08, 0.98, 0.08, WOOD, 0, 0, 0),
            B(0, -0.46, 0, 0.32, 0.36, 0.06, STEEL, 0, 0, 0),
            B(0, -0.64, 0, 0.20, 0.10, 0.06, STEEL_L, 0, 0, 0),
        },
        held = { scale = 0.64, ry = 35, rz = -15 },
    },

    -- ==================== 护甲 ====================
    helmet = {
        parts = {
            B(0, 0.06, 0, 0.58, 0.34, 0.54, STEEL, 0, 0, 0),
            B(0, 0.27, 0, 0.42, 0.16, 0.40, STEEL_L, 0, 0, 0),
            B(0, -0.02, 0.26, 0.40, 0.22, 0.06, DARK, 0, 0, 0),
            B(0, -0.16, 0.22, 0.46, 0.08, 0.10, STEEL_D, 0, 0, 0),
        },
        held = { scale = 0.64, ry = 30, rz = -8 },
    },
    chestplate = {
        parts = {
            B(0, 0, 0, 0.58, 0.60, 0.32, STEEL, 0, 0, 0),
            B(-0.38, 0.22, 0, 0.24, 0.20, 0.30, STEEL_L, 0, 0, 0),
            B(0.38, 0.22, 0, 0.24, 0.20, 0.30, STEEL_L, 0, 0, 0),
            B(0, 0.33, 0, 0.22, 0.10, 0.18, DARK, 0, 0, 0),
        },
        held = { scale = 0.62, ry = 30, rz = -8 },
    },
    leggings = {
        parts = {
            B(0, 0.28, 0, 0.60, 0.18, 0.34, STEEL, 0, 0, 0),
            B(-0.15, -0.12, 0, 0.24, 0.64, 0.28, STEEL, 0, 0, 0),
            B(0.15, -0.12, 0, 0.24, 0.64, 0.28, STEEL, 0, 0, 0),
            B(0, 0.22, 0.02, 0.56, 0.05, 0.30, STEEL_L, 0, 0, 0),
        },
        held = { scale = 0.62, ry = 30, rz = -8 },
    },
    armguards = {
        parts = {
            B(-0.20, 0, 0, 0.28, 0.56, 0.26, STEEL, 0, 0, 0),
            B(0.20, 0, 0, 0.28, 0.56, 0.26, STEEL, 0, 0, 0),
            B(-0.20, -0.20, 0, 0.30, 0.08, 0.28, STEEL_D, 0, 0, 0),
            B(0.20, -0.20, 0, 0.30, 0.08, 0.28, STEEL_D, 0, 0, 0),
        },
        held = { scale = 0.62, ry = 30, rz = -8 },
    },

    -- ==================== 药水 / 桶 ====================
    potion_heal = {
        parts = {
            CY(0, -0.16, 0, 0.24, 0.34, RED, 10),
            CY(0, 0.06, 0, 0.26, 0.12, GLASS, 10),
            B(0, 0.20, 0, 0.14, 0.16, 0.14, GLASS, 0, 0, 0),
            B(0, 0.32, 0, 0.18, 0.10, 0.18, BROWN, 0, 0, 0),
            B(-0.09, -0.12, 0.235, 0.05, 0.16, 0.02, { 0.98, 0.86, 0.86 }, 0, 0, 0),
        },
        held = { scale = 0.62, ry = 30, rz = -8 },
    },
    potion_strength = {
        parts = {
            CY(0, -0.16, 0, 0.24, 0.34, ORANGE, 10),
            CY(0, 0.06, 0, 0.26, 0.12, GLASS, 10),
            B(0, 0.20, 0, 0.14, 0.16, 0.14, GLASS, 0, 0, 0),
            B(0, 0.32, 0, 0.18, 0.10, 0.18, BROWN, 0, 0, 0),
            B(-0.09, -0.12, 0.235, 0.05, 0.16, 0.02, { 0.99, 0.90, 0.82 }, 0, 0, 0),
        },
        held = { scale = 0.62, ry = 30, rz = -8 },
    },
    potion_speed = {
        parts = {
            CY(0, -0.16, 0, 0.24, 0.34, BLUE, 10),
            CY(0, 0.06, 0, 0.26, 0.12, GLASS, 10),
            B(0, 0.20, 0, 0.14, 0.16, 0.14, GLASS, 0, 0, 0),
            B(0, 0.32, 0, 0.18, 0.10, 0.18, BROWN, 0, 0, 0),
            B(-0.09, -0.12, 0.235, 0.05, 0.16, 0.02, { 0.86, 0.94, 1.0 }, 0, 0, 0),
        },
        held = { scale = 0.62, ry = 30, rz = -8 },
    },
    bucket = {
        parts = {
            CY(0, 0, 0, 0.30, 0.54, GRAY, 10),
            CY(0, 0.25, 0, 0.32, 0.06, GRAY_L, 10),
            CY(0, 0.27, 0, 0.24, 0.04, DARK, 10),
            B(0, 0.52, 0, 0.60, 0.05, 0.05, GRAY_D, 0, 0, 0),
            B(-0.28, 0.40, 0, 0.05, 0.24, 0.05, GRAY_D, 0, 0, 0),
            B(0.28, 0.40, 0, 0.05, 0.24, 0.05, GRAY_D, 0, 0, 0),
        },
        held = { scale = 0.62, ry = 30, rz = -8 },
    },
    water_bucket = {
        parts = {
            CY(0, 0, 0, 0.30, 0.54, GRAY, 10),
            CY(0, 0.25, 0, 0.32, 0.06, GRAY_L, 10),
            -- 水面放在桶沿之上，否则会被不透明的桶口盖住
            CY(0, 0.30, 0, 0.27, 0.05, BLUE_L, 10),
            B(0, 0.52, 0, 0.60, 0.05, 0.05, GRAY_D, 0, 0, 0),
            B(-0.28, 0.40, 0, 0.05, 0.24, 0.05, GRAY_D, 0, 0, 0),
            B(0.28, 0.40, 0, 0.05, 0.24, 0.05, GRAY_D, 0, 0, 0),
        },
        held = { scale = 0.62, ry = 30, rz = -8 },
    },
}

-- ====================================================================
-- 材质 / 对外接口
-- ====================================================================

---@type Material|nil
local sharedMaterial = nil

---共享的受光顶点色材质（地面掉落物 / 第一人称手持共用）
---@return Material
function ItemModel.getMaterial()
    if sharedMaterial then
        return sharedMaterial
    end
    local technique = cache:GetResource("Technique", "Techniques/DiffVCol.xml")
    if not technique then
        technique = cache:GetResource("Technique", "Techniques/NoTexture.xml")
    end
    local material = Material:new()
    material:SetTechnique(0, technique)
    material:SetShaderParameter("MatDiffColor", Variant(Color(1, 1, 1, 1)))
    sharedMaterial = material
    return material
end

---物品是否有 3D 模型
---@param itemId string|nil
---@return boolean
function ItemModel.hasModel(itemId)
    return itemId ~= nil and SPECS[itemId] ~= nil
end

---把物品模型写进 CustomGeometry（需要调用方已 SetNumGeometries(1)）
---@param geometry CustomGeometry
---@param itemId string
---@return boolean ok
function ItemModel.buildGeometry(geometry, itemId)
    local spec = SPECS[itemId]
    if not spec then
        return false
    end
    geometry:BeginGeometry(0, TRIANGLE_LIST)
    emitSpec(geometry, spec)
    geometry:Commit()
    return true
end

---第一人称手持变换
---@param itemId string
---@return table { scale:number, rx:number, ry:number, rz:number, x:number, y:number, z:number }
function ItemModel.getHeldTransform(itemId)
    local spec = SPECS[itemId]
    local held = spec and spec.held or nil
    if not held then
        return { scale = 0.62, rx = 0, ry = 30, rz = -10, x = 0, y = 0, z = 0 }
    end
    return {
        scale = held.scale or 0.62,
        rx = held.rx or 0,
        ry = held.ry or 30,
        rz = held.rz or 0,
        x = held.x or 0,
        y = held.y or 0,
        z = held.z or 0,
    }
end

---创建地面掉落物模型节点（物品局部单位 → 世界尺寸）
---@param parent Node
---@param itemId string
---@return Node|nil
function ItemModel.createDroppedNode(parent, itemId)
    local spec = SPECS[itemId]
    if not spec then
        return nil
    end
    local node = parent:CreateChild("ItemModel")
    local s = spec.dropScale or 0.70
    node.scale = Vector3(s, s, s)
    local geometry = node:CreateComponent("CustomGeometry")
    geometry:SetNumGeometries(1)
    ItemModel.buildGeometry(geometry, itemId)
    geometry:SetMaterial(0, ItemModel.getMaterial())
    return node
end

return ItemModel
