#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成非方块物品的 UI 图标（64x64 PNG，透明背景）。

输出: assets/Textures/items/<item_id>.png
运行: python tools/gen_item_icons.py
"""
from PIL import Image, ImageDraw
import math
import os

SIZE = 64          # 最终尺寸
SS = 4             # 超采样倍数（先画 256x256 再缩小）
S = SIZE * SS

OUT = (38, 28, 22, 255)
OUT_SOFT = (38, 28, 22, 200)
STEEL = (198, 206, 216, 255)
STEEL_D = (128, 140, 156, 255)
STEEL_L = (236, 242, 248, 255)
GOLD = (238, 196, 72, 255)
GOLD_D = (176, 132, 28, 255)
WOOD = (138, 92, 48, 255)
WOOD_D = (92, 58, 28, 255)
WOOD_L = (176, 124, 70, 255)
RED = (208, 62, 52, 255)
RED_D = (146, 36, 30, 255)
RED_L = (240, 112, 96, 255)
GREEN = (92, 164, 72, 255)
GREEN_D = (56, 112, 44, 255)
GREEN_L = (140, 202, 96, 255)
BROWN = (128, 84, 50, 255)
TAN = (216, 168, 98, 255)
TAN_D = (166, 118, 58, 255)
WHITE = (240, 240, 232, 255)
WHITE_D = (188, 190, 184, 255)
BLUE = (88, 166, 236, 255)
BLUE_D = (40, 104, 172, 255)
BLUE_L = (156, 214, 250, 255)
PINK = (234, 140, 132, 255)
PINK_D = (184, 94, 90, 255)
DARK = (62, 58, 54, 255)
GRAY = (146, 148, 152, 255)
CYAN = (86, 216, 224, 255)
CYAN_D = (40, 150, 168, 255)
ORANGE = (236, 128, 52, 255)


def sc(v):
    """坐标缩放"""
    if isinstance(v, (list, tuple)):
        return [sc(x) for x in v]
    return v * SS


def canvas():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def poly(d, pts, fill, outline=None, width=3, closed=True):
    pts = [tuple(sc(p)) for p in pts]
    d.polygon(pts, fill=fill, outline=outline, width=sc(width))
    if closed and outline and width > 0:
        d.line(pts + [pts[0]], fill=outline, width=sc(width), joint="curve")


def rect(d, x0, y0, x1, y1, fill, outline=None, width=3, radius=0):
    if radius > 0:
        d.rounded_rectangle(sc([x0, y0, x1, y1]), radius=sc(radius), fill=fill,
                            outline=outline, width=sc(width))
    else:
        d.rectangle(sc([x0, y0, x1, y1]), fill=fill, outline=outline, width=sc(width))


def ellipse(d, x0, y0, x1, y1, fill, outline=None, width=3):
    d.ellipse(sc([x0, y0, x1, y1]), fill=fill, outline=outline, width=sc(width))


def line(d, pts, fill, width=3, joint="curve"):
    d.line([tuple(sc(p)) for p in pts], fill=fill, width=sc(width), joint=joint)


def arc(d, box, start, end, fill, width=4):
    d.arc(sc(box), start, end, fill=fill, width=sc(width))


def rot_rect(cx, cy, w, h, ang):
    a = math.radians(ang)
    ca, sa = math.cos(a), math.sin(a)
    pts = []
    for dx, dy in ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)):
        pts.append((cx + dx * ca - dy * sa, cy + dx * sa + dy * ca))
    return pts


def save(name, draw_fn):
    im, d = canvas()
    draw_fn(d)
    im = im.resize((SIZE, SIZE), Image.LANCZOS)
    out = os.path.join("assets", "Textures", "items", name + ".png")
    im.save(out)
    print("wrote", out)


# ======================================================================
# 材料
# ======================================================================
def stick(d):
    poly(d, rot_rect(32, 33, 9, 46, 32), WOOD, OUT)
    poly(d, rot_rect(31, 30, 3, 36, 32), WOOD_L)


def coal(d):
    poly(d, [(18, 38), (22, 22), (34, 16), (46, 22), (49, 36), (42, 49), (28, 52), (18, 45)], DARK, OUT)
    poly(d, [(24, 30), (32, 24), (40, 28), (36, 36), (27, 37)], (92, 88, 84, 255))
    poly(d, [(37, 41), (45, 38), (47, 45), (40, 49)], (84, 80, 78, 255))


def iron_ingot(d):
    poly(d, [(14, 40), (20, 26), (48, 26), (54, 40)], STEEL_L, OUT)
    poly(d, [(14, 40), (54, 40), (50, 50), (18, 50)], STEEL, OUT)
    line(d, [(22, 32), (44, 32)], STEEL_D, 2)
    line(d, [(19, 44), (49, 44)], STEEL_D, 2)


def gold_ingot(d):
    poly(d, [(14, 40), (20, 26), (48, 26), (54, 40)], (250, 220, 110, 255), OUT)
    poly(d, [(14, 40), (54, 40), (50, 50), (18, 50)], GOLD, OUT)
    line(d, [(22, 32), (44, 32)], GOLD_D, 2)


def diamond(d):
    poly(d, [(32, 6), (50, 24), (32, 58), (14, 24)], CYAN, OUT)
    poly(d, [(32, 6), (38, 24), (32, 40), (26, 24)], (160, 240, 246, 255))
    line(d, [(14, 24), (50, 24)], CYAN_D, 2)
    line(d, [(26, 24), (32, 58)], CYAN_D, 2)
    line(d, [(38, 24), (32, 58)], CYAN_D, 2)


def leather(d):
    poly(d, [(12, 26), (24, 18), (40, 20), (52, 28), (50, 44), (38, 52), (20, 50), (12, 40)], BROWN, OUT)
    line(d, [(18, 26), (34, 23), (46, 28)], (176, 128, 80, 255), 2)
    for x, y in ((20, 38), (30, 34), (40, 36), (46, 42), (26, 45), (36, 46)):
        line(d, [(x, y), (x + 3, y - 2)], (222, 186, 138, 255), 2)


def feather(d):
    poly(d, [(44, 8), (30, 22), (22, 40), (20, 52), (24, 54), (34, 44), (44, 28), (50, 14)], WHITE, OUT)
    line(d, [(48, 10), (22, 56)], WHITE_D, 2)
    for i in range(4):
        x = 36 - i * 4
        y = 18 + i * 7
        line(d, [(x, y), (x - 5, y + 4)], WHITE_D, 1)


def string_icon(d):
    for i, (x0, y0, x1, y1) in enumerate(((14, 22, 50, 42), (18, 32, 46, 50), (14, 12, 50, 30))):
        d.ellipse(sc([x0, y0, x1, y1]), outline=WHITE, width=sc(4))
    line(d, [(32, 12), (32, 6), (38, 4)], WHITE, 3)


def gunpowder(d):
    poly(d, [(20, 22), (44, 20), (52, 38), (46, 52), (20, 52), (14, 38)], (74, 72, 78, 255), OUT)
    poly(d, [(20, 22), (28, 14), (36, 14), (44, 20)], (100, 98, 104, 255), OUT)
    line(d, [(14, 36), (50, 36)], OUT, 2)
    for x, y in ((24, 42), (34, 44), (42, 40), (28, 48), (40, 48)):
        ellipse(d, x - 2, y - 2, x + 2, y + 2, (42, 40, 44, 255))


def ectoplasm(d):
    poly(d, [(32, 10), (44, 20), (50, 34), (44, 48), (32, 55), (20, 48), (14, 34), (20, 20)], (156, 216, 240, 220), OUT_SOFT)
    ellipse(d, 24, 24, 36, 36, (210, 244, 252, 220))
    for x, y in ((22, 40), (42, 42), (32, 48)):
        ellipse(d, x - 3, y - 3, x + 3, y + 3, (200, 240, 250, 200))


def wheat(d):
    for x, off in ((22, 0), (32, 4), (42, -2)):
        line(d, [(x, 52), (x + off * 0.3, 20)], (156, 112, 44, 255), 3)
        for i in range(3):
            y = 18 + i * 7
            poly(d, [(x - 5, y + 4), (x, y - 3), (x + 5, y + 4)], GOLD, OUT, 1)
    poly(d, [(20, 40), (44, 40), (42, 46), (22, 46)], BROWN, OUT, 1)


def arrow(d):
    poly(d, rot_rect(34, 34, 5, 46, 36), WOOD, OUT, 1)
    poly(d, [(46, 8), (54, 18), (46, 22), (42, 15)], STEEL, OUT, 1)
    poly(d, [(24, 44), (16, 58), (28, 52)], WHITE, OUT, 1)
    poly(d, [(20, 40), (10, 50), (22, 48)], RED, OUT, 1)


# ======================================================================
# 食物
# ======================================================================
def apple(d):
    ellipse(d, 12, 20, 52, 56, RED, OUT)
    ellipse(d, 14, 22, 30, 40, RED_L)
    rect(d, 30, 8, 35, 22, WOOD, OUT, 2, 2)
    poly(d, [(35, 14), (46, 8), (50, 16), (40, 20)], GREEN, OUT, 1)


def bread(d):
    ellipse(d, 8, 22, 56, 50, TAN, OUT)
    ellipse(d, 12, 24, 52, 40, (236, 192, 122, 255))
    for x in (20, 31, 42):
        line(d, [(x, 27), (x + 6, 41)], TAN_D, 3)


def beef(d):
    poly(d, [(12, 26), (26, 16), (44, 18), (54, 30), (48, 46), (30, 52), (16, 44)], RED, OUT)
    # 油花：短而错落的曲线，避免看起来像五官
    line(d, [(21, 28), (27, 33), (26, 39)], (244, 196, 186, 255), 2)
    line(d, [(35, 21), (38, 27), (35, 32)], (244, 196, 186, 255), 2)
    line(d, [(40, 36), (44, 40), (42, 45)], (244, 196, 186, 255), 2)
    line(d, [(30, 44), (35, 46)], (244, 196, 186, 255), 2)


def porkchop(d):
    poly(d, [(16, 20), (34, 14), (50, 26), (50, 42), (34, 52), (18, 44), (12, 32)], PINK, OUT)
    ellipse(d, 36, 34, 48, 46, (246, 218, 210, 255), OUT, 1)
    line(d, [(20, 28), (28, 26), (32, 32)], PINK_D, 2)


def chicken_meat(d):
    ellipse(d, 14, 18, 44, 40, (238, 212, 168, 255), OUT)
    rect(d, 38, 36, 54, 44, WHITE, OUT, 2, 3)
    ellipse(d, 46, 40, 58, 50, WHITE, OUT, 1)
    line(d, [(20, 24), (30, 26)], (214, 184, 138, 255), 2)


def rotten_flesh(d):
    poly(d, [(12, 30), (22, 18), (38, 20), (52, 26), (50, 42), (38, 50), (22, 48), (12, 40)], (108, 116, 72, 255), OUT)
    for x, y, r in ((24, 30, 3), (38, 34, 4), (30, 42, 3), (44, 44, 2), (18, 38, 2)):
        ellipse(d, x - r, y - r, x + r, y + r, (72, 82, 52, 255))


# ======================================================================
# 武器 / 工具
# ======================================================================
def sword(d):
    poly(d, [(32, 4), (39, 20), (39, 42), (32, 48), (25, 42), (25, 20)], STEEL, OUT)
    poly(d, [(32, 6), (34, 20), (34, 40), (32, 44), (30, 40), (30, 20)], STEEL_L)
    rect(d, 14, 46, 50, 52, GOLD, OUT, 2, 2)
    rect(d, 28, 52, 36, 62, WOOD, OUT, 2, 2)
    ellipse(d, 26, 58, 38, 64, GOLD, OUT, 1)


def bow(d):
    arc(d, (18, 6, 66, 58), 130, 230, WOOD, 6)
    line(d, [(28, 12), (28, 52)], (232, 226, 210, 255), 2)
    line(d, [(28, 31), (50, 31)], WOOD_D, 2)
    poly(d, [(28, 31), (36, 28), (36, 34)], STEEL, OUT, 1)


def pickaxe(d):
    poly(d, rot_rect(35, 36, 6, 46, 28), WOOD, OUT, 2)
    poly(d, [(10, 30), (22, 16), (42, 10), (56, 18), (48, 25), (34, 22), (22, 29), (14, 35)], STEEL, OUT)
    poly(d, [(18, 24), (34, 18), (46, 18), (40, 22), (26, 25), (20, 29)], STEEL_L)


def axe(d):
    poly(d, rot_rect(34, 36, 6, 46, 24), WOOD, OUT, 2)
    # 斧头：靠右的弧形斧刃，左侧留出斧背
    poly(d, [(33, 12), (48, 13), (57, 22), (55, 34), (45, 43), (35, 39),
             (39, 31), (35, 25), (31, 18)], STEEL, OUT)
    line(d, [(49, 17), (54, 24), (52, 33), (45, 39)], STEEL_L, 3)
    line(d, [(36, 20), (42, 23)], STEEL_D, 2)


def shovel(d):
    poly(d, rot_rect(35, 30, 6, 42, 30), WOOD, OUT, 2)
    # 铲头：与手柄同轴，底部收成尖
    poly(d, [(23, 40), (37, 35), (45, 44), (41, 57), (31, 63), (20, 55), (16, 47)], STEEL, OUT)
    poly(d, [(27, 44), (36, 40), (39, 47), (35, 56), (29, 58), (23, 52)], STEEL_L)
    line(d, [(31, 41), (31, 58)], STEEL_D, 2)


# ======================================================================
# 护甲
# ======================================================================
def helmet(d):
    poly(d, [(12, 40), (14, 22), (24, 10), (40, 10), (50, 22), (52, 40), (44, 50), (20, 50)], STEEL, OUT)
    poly(d, [(20, 24), (32, 16), (44, 24), (44, 38), (32, 42), (20, 38)], (90, 98, 110, 255))
    line(d, [(16, 34), (48, 34)], STEEL_D, 2)
    line(d, [(20, 46), (44, 46)], STEEL_D, 2)


def chestplate(d):
    poly(d, [(14, 20), (26, 16), (38, 16), (50, 20), (54, 34), (46, 40), (46, 54), (18, 54), (18, 40), (10, 34)], STEEL, OUT)
    poly(d, [(28, 16), (36, 16), (38, 24), (32, 28), (26, 24)], (90, 98, 110, 255))
    line(d, [(20, 34), (44, 34)], STEEL_D, 2)
    line(d, [(32, 28), (32, 50)], STEEL_D, 2)


def leggings(d):
    rect(d, 16, 12, 48, 22, STEEL, OUT, 3, 3)
    poly(d, [(18, 20), (31, 20), (30, 58), (18, 58)], STEEL, OUT)
    poly(d, [(33, 20), (46, 20), (46, 58), (34, 58)], STEEL, OUT)
    line(d, [(22, 28), (22, 50)], STEEL_D, 2)
    line(d, [(42, 28), (42, 50)], STEEL_D, 2)


def armguards(d):
    for x0 in (13, 35):
        poly(d, [(x0, 18), (x0 + 14, 14), (x0 + 16, 46), (x0 + 4, 52)], STEEL, OUT)
        # 上沿高光 + 下沿深色束带 + 铆钉
        line(d, [(x0 + 3, 24), (x0 + 11, 21)], STEEL_L, 2)
        poly(d, [(x0 + 4, 42), (x0 + 15, 38), (x0 + 15, 45), (x0 + 4, 49)], STEEL_D, OUT, 1)
        ellipse(d, x0 + 8, 29, x0 + 12, 33, STEEL_L, OUT, 1)


# ======================================================================
# 药水 / 桶
# ======================================================================
def potion(d, liquid):
    # 瓶身
    ellipse(d, 14, 24, 50, 58, (222, 238, 244, 210), OUT)
    # 液体（下半部）
    d.pieslice(sc([17, 28, 47, 55]), 0, 180, fill=liquid)
    line(d, [(17, 41), (47, 41)], liquid)
    # 瓶颈/软木塞
    rect(d, 27, 10, 37, 28, (222, 238, 244, 210), OUT, 2, 2)
    rect(d, 25, 6, 39, 13, BROWN, OUT, 2, 2)
    # 高光
    ellipse(d, 21, 30, 26, 42, (250, 252, 252, 190))


def potion_heal(d):
    potion(d, (222, 66, 62, 255))


def potion_strength(d):
    potion(d, ORANGE)


def potion_speed(d):
    potion(d, BLUE)


def bucket(d, liquid=None):
    poly(d, [(16, 22), (48, 22), (44, 56), (20, 56)], (170, 176, 184, 255), OUT)
    ellipse(d, 16, 18, 48, 28, (196, 202, 210, 255), OUT)
    if liquid is not None:
        ellipse(d, 20, 21, 44, 28, liquid)
    else:
        ellipse(d, 20, 21, 44, 28, (100, 104, 112, 255))
    arc(d, (12, 6, 52, 44), 180, 360, (150, 156, 164, 255), 3)
    line(d, [(20, 33), (44, 33)], (130, 136, 144, 255), 2)


def water_bucket(d):
    bucket(d, BLUE)


# ======================================================================
# 输出
# ======================================================================
ICONS = {
    "stick": stick, "coal": coal, "iron_ingot": iron_ingot, "gold_ingot": gold_ingot,
    "diamond": diamond, "leather": leather, "feather": feather, "string": string_icon,
    "gunpowder": gunpowder, "ectoplasm": ectoplasm, "wheat": wheat, "arrow": arrow,
    "apple": apple, "bread": bread, "beef": beef, "porkchop": porkchop,
    "chicken_meat": chicken_meat, "rotten_flesh": rotten_flesh,
    "sword": sword, "bow": bow, "pickaxe": pickaxe, "axe": axe, "shovel": shovel,
    "helmet": helmet, "chestplate": chestplate, "leggings": leggings, "armguards": armguards,
    "potion_heal": potion_heal, "potion_strength": potion_strength, "potion_speed": potion_speed,
    "bucket": bucket, "water_bucket": water_bucket,
}

if __name__ == "__main__":
    os.makedirs(os.path.join("assets", "Textures", "items"), exist_ok=True)
    for name, fn in ICONS.items():
        save(name, fn)
    print("done:", len(ICONS), "icons")
