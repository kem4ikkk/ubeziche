# -*- coding: utf-8 -*-
"""Генератор иконок дерева навыков «Убежище» (Этап 4.12h).

30 РАЗНЫХ иконок (по одной на навык) в едином монохромном стиле: белый силуэт +
равномерная ЧЁРНАЯ ОБВОДКА (по просьбе автора) + чёрные внутренние детали.

Как рисуется (чтобы не было «сплющенных»/мыльных, как у нарезанных с листа):
  • каждая фигура рисуется в высоком разрешении S=512 (белый слой);
  • обводка — дилатация маски белого (MaxFilter) → чёрный слой ПОД белым;
  • внутренние детали (дырки шестерёнки, глаза призрака, кладка, сетка чертежа)
    — отдельный ЧЁРНЫЙ слой ПОВЕРХ;
  • результат обрезается по содержимому и масштабируется к единому размеру
    (TARGET) на холсте OUT=128 → у всех иконок одинаковая «масса», смуглый LANCZOS.

Запуск:  python tools/gen_skill_icons.py
Иконки кладутся в assets/icons/<name>.png (потом импорт Godot и привязка в SKILLS).
"""

import math
from PIL import Image, ImageDraw, ImageFilter

S = 512                       # разрешение рендера (супер-сэмплинг)
OUT = 128                     # итоговый размер
TARGET = 112                  # к какому размеру вписываем (единая «масса» иконок)
OW = 14                       # толщина чёрной обводки (в S-пикселях)
W = (255, 255, 255, 255)
K = (0, 0, 0, 255)
ICON_DIR = "assets/icons"
C = 256                       # центр


# ---------- примитивы ----------
def stroke(d, pts, w, color=W):
    if len(pts) >= 2:
        d.line(pts, fill=color, width=w, joint="curve")
    r = w // 2
    for x, y in pts:
        d.ellipse([x - r, y - r, x + r, y + r], fill=color)


def disc(d, cx, cy, r, color=W):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)


def ring(d, cx, cy, r, wd, color=W):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=color, width=wd)


def poly(d, pts, color=W):
    d.polygon(pts, fill=color)


def rrect(d, box, rad, color=W):
    d.rounded_rectangle(box, radius=rad, fill=color)


def rot_paste(dst, src, deg):
    dst.alpha_composite(src.rotate(deg, resample=Image.BICUBIC, center=(C, C)))


# ======================= ИКОНКИ (рисуют белым; dk — чёрные детали) =======================
# Боевые
def i_pistol(im, d, dk):
    rrect(d, [70, 178, 442, 250], 16)                     # затвор/ствол
    poly(d, [(120, 250), (245, 250), (208, 408), (96, 408)])   # рукоять
    rrect(d, [58, 156, 96, 184], 6)                       # мушка
    dk.arc([175, 250, 290, 360], 5, 175, fill=K, width=20)     # скоба спуска


def i_rifle(im, d, dk):
    rrect(d, [60, 212, 452, 262], 12)                     # ствольная коробка
    poly(d, [(26, 210), (60, 210), (60, 286), (44, 300), (26, 300)])  # приклад
    poly(d, [(240, 262), (300, 262), (284, 356), (224, 356)])         # магазин
    poly(d, [(150, 262), (198, 262), (184, 340), (136, 340)])         # рукоять
    rrect(d, [452, 230, 500, 248], 5)                     # дуло
    rrect(d, [300, 188, 332, 214], 5)                     # прицел


def i_mg(im, d, dk):
    rrect(d, [70, 204, 448, 270], 12)                     # коробка
    disc(d, 250, 305, 62)                                 # барабан
    poly(d, [(28, 198), (70, 198), (70, 296), (50, 310), (28, 310)])  # приклад
    rrect(d, [448, 226, 506, 248], 5)                     # ствол
    stroke(d, [(120, 270), (92, 372)], 18)                # сошка
    stroke(d, [(184, 270), (212, 372)], 18)
    ring(dk, 250, 305, 30, 14, K)                         # центр барабана


def i_magazine(im, d, dk):
    rrect(d, [186, 214, 318, 432], 16)                    # магазин
    for x in (214, 252, 290):                             # 3 патрона
        rrect(d, [x - 16, 150, x + 16, 214], 6)
        poly(d, [(x - 16, 150), (x + 16, 150), (x, 118)])
    for y in (262, 302, 342, 382):                        # рёбра (чёрные)
        stroke(dk, [(202, y), (302, y)], 9, K)


def _sword_img():
    s = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(s)
    poly(d, [(C - 22, 356), (C + 22, 356), (C + 22, 120), (C, 78), (C - 22, 120)])  # клинок
    rrect(d, [C - 72, 356, C + 72, 390], 10)              # гарда
    rrect(d, [C - 15, 390, C + 15, 452], 7)               # рукоять
    disc(d, C, 462, 22)                                   # навершие
    return s


def i_swords(im, d, dk):
    s = _sword_img()
    rot_paste(im, s, 35)
    rot_paste(im, s, -35)


def i_ghost(im, d, dk):
    d.pieslice([126, 108, 386, 368], 180, 360)            # широкий купол
    d.rectangle([126, 238, 386, 410])                     # тело (больше белого)
    for xc in (170, 256, 342):                            # плавный низ
        poly(d, [(xc - 50, 410), (xc + 50, 410), (xc, 464)])
    dk.ellipse([198, 250, 228, 290], fill=K)              # маленькие глаза
    dk.ellipse([284, 250, 314, 290], fill=K)


def i_heart(im, d, dk):
    # Сплошное белое сердце (без чёрного «+», который дробил его на грани).
    d.pieslice([124, 146, 266, 288], 180, 360)
    d.pieslice([246, 146, 388, 288], 180, 360)
    poly(d, [(132, 230), (380, 230), (256, 430)])


def i_shield(im, d, dk):
    poly(d, [(256, 112), (404, 168), (404, 286),
             (256, 442), (108, 286), (108, 168)])
    dk.line([(256, 150), (256, 410)], fill=K, width=16)   # ребро
    dk.line([(150, 230), (362, 230)], fill=K, width=16)


def i_grenade(im, d, dk):
    disc(d, 256, 312, 112)                                # корпус
    rrect(d, [214, 168, 298, 212], 8)                     # горловина
    rrect(d, [296, 174, 372, 196], 6)                     # рычаг
    ring(d, 384, 168, 24, 12)                             # кольцо чеки
    dk.line([(180, 290), (332, 290)], fill=K, width=12)   # шов


def i_jet(im, d, dk):
    rrect(d, [234, 110, 278, 420], 18)                    # фюзеляж
    poly(d, [(256, 74), (232, 132), (280, 132)])          # нос
    poly(d, [(256, 226), (104, 332), (408, 332)])         # крылья
    poly(d, [(256, 360), (188, 424), (324, 424)])         # хвост


# Выживание
def i_pickaxe(im, d, dk):
    stroke(d, [(158, 442), (352, 150)], 28)               # рукоять
    dw_pts = [(146, 206), (256, 112), (366, 206)]
    d.line(dw_pts, fill=W, width=26, joint="curve")       # голова (дуга)
    for x, y in dw_pts:
        disc(d, x, y, 13)
    poly(d, [(146, 206), (120, 230), (170, 224)])         # острия
    poly(d, [(366, 206), (392, 230), (342, 224)])


def i_gem(im, d, dk):
    poly(d, [(256, 132), (350, 214), (300, 410),
             (212, 410), (162, 214)])                     # бриллиант
    dk.line([(162, 214), (350, 214)], fill=K, width=12)   # грань-пояс
    dk.line([(256, 132), (256, 214)], fill=K, width=10)
    dk.line([(256, 214), (256, 410)], fill=K, width=10)
    for sx, sy in [(150, 150), (380, 300)]:               # блики
        stroke(d, [(sx - 22, sy), (sx + 22, sy)], 12)
        stroke(d, [(sx, sy - 22), (sx, sy + 22)], 12)


def i_beartrap(im, d, dk):
    ring(d, 256, 256, 116, 30)
    n = 12
    for i in range(n):
        a = 2 * math.pi * i / n
        ix, iy = 256 + 88 * math.cos(a), 256 + 88 * math.sin(a)
        bx, by = 256 + 116 * math.cos(a), 256 + 116 * math.sin(a)
        px, py = -math.sin(a), math.cos(a)
        poly(d, [(bx + px * 24, by + py * 24),
                 (bx - px * 24, by - py * 24), (ix, iy)])  # зуб внутрь
    disc(d, 256, 256, 26)                                 # пластина


def i_speed(im, d, dk):
    stroke(d, [(196, 150), (358, 256), (196, 362)], 42)   # шеврон-стрелка
    for y in (200, 256, 312):                             # линии движения
        stroke(d, [(86, y), (162, y)], 22)


def i_leaf(im, d, dk):
    poly(d, [(256, 108), (372, 214), (256, 424), (140, 214)])  # лист
    dk.line([(256, 150), (256, 392)], fill=K, width=14)        # центр. жилка
    for y in (230, 290, 350):                                  # боковые жилки
        dk.line([(256, y), (210, y - 34)], fill=K, width=9)
        dk.line([(256, y), (302, y - 34)], fill=K, width=9)


def i_hourglass(im, d, dk):
    rrect(d, [156, 116, 356, 150], 10)                    # верх
    rrect(d, [156, 380, 356, 414], 10)                    # низ
    poly(d, [(180, 150), (332, 150), (256, 266)])         # верх. колба
    poly(d, [(256, 266), (180, 380), (332, 380)])         # ниж. колба
    dk.polygon([(212, 175), (300, 175), (256, 245)], fill=K)   # песок


def i_compass(im, d, dk):
    ring(d, 256, 256, 128, 26)
    poly(d, [(256, 142), (296, 256), (256, 256)])         # стрелка N
    poly(d, [(256, 370), (216, 256), (256, 256)])         # стрелка S
    dk.ellipse([240, 240, 272, 272], fill=K)              # ось


def i_campfire(im, d, dk):
    poly(d, [(256, 110), (332, 270), (300, 348),
             (256, 372), (212, 348), (180, 270)])         # пламя
    stroke(d, [(150, 392), (362, 440)], 26)               # поленья
    stroke(d, [(150, 440), (362, 392)], 26)
    dk.polygon([(256, 200), (292, 290), (256, 340), (220, 290)], fill=K)  # ядро


def i_moneybag(im, d, dk):
    disc(d, 256, 314, 122)                                # мешок
    poly(d, [(206, 158), (306, 158), (332, 198), (180, 198)])  # горловина
    dk.line([(180, 198), (332, 198)], fill=K, width=12)
    stroke(dk, [(256, 268), (256, 360)], 22, K)           # знак валюты $
    stroke(dk, [(228, 290), (284, 290)], 18, K)
    stroke(dk, [(228, 338), (284, 338)], 18, K)


def _smallleaf():
    s = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(s)
    poly(d, [(256, 150), (322, 230), (256, 372), (190, 230)])
    return s


def i_leaves(im, d, dk):
    leaf = _smallleaf()
    for dx, dy, deg in [(-44, 30, 24), (50, 18, -28), (0, -52, 0)]:
        sub = leaf.rotate(deg, resample=Image.BICUBIC, center=(C, C))
        im.alpha_composite(sub, (dx, dy))


# Технология
def i_wrench(im, d, dk):
    stroke(d, [(196, 372), (320, 212)], 40)               # ручка
    ring(d, 348, 184, 56, 32)                             # верхний зев
    dk.polygon([(348, 128), (392, 150), (348, 184), (310, 156)], fill=K)  # вырез зева
    ring(d, 188, 372, 50, 30)                             # нижнее кольцо
    dk.ellipse([166, 350, 210, 394], fill=K)


def i_gear(im, d, dk):
    n = 8
    for i in range(n):
        a = 2 * math.pi * i / n
        ox, oy = math.cos(a), math.sin(a)
        px, py = -math.sin(a), math.cos(a)
        cx, cy = 256 + 126 * ox, 256 + 126 * oy
        w, ln = 34, 42
        poly(d, [(cx + px * w, cy + py * w), (cx - px * w, cy - py * w),
                 (cx - px * w + ox * ln, cy - py * w + oy * ln),
                 (cx + px * w + ox * ln, cy + py * w + oy * ln)])
    disc(d, 256, 256, 120)
    dk.ellipse([208, 208, 304, 304], fill=K)              # ось


def i_tower(im, d, dk):
    stroke(d, [(256, 170), (172, 430)], 26)               # ноги (толще)
    stroke(d, [(256, 170), (340, 430)], 26)
    for y in (252, 332, 412):                             # перемычки (толще)
        f = (y - 170) * (84.0 / 260)
        stroke(d, [(256 - f, y), (256 + f, y)], 18)
    stroke(d, [(256, 170), (256, 108)], 16)               # мачта
    disc(d, 256, 98, 20)                                  # антенна
    for r in (60, 98):                                    # сигнал — БЕЛЫМ по бокам
        d.arc([256 - r, 98 - r, 256 + r, 98 + r], 198, 252, fill=W, width=15)
        d.arc([256 - r, 98 - r, 256 + r, 98 + r], 288, 342, fill=W, width=15)


def i_factory(im, d, dk):
    d.rectangle([118, 286, 408, 432])                     # корпус (белый)
    rrect(d, [150, 198, 198, 286], 4)                     # трубы
    rrect(d, [232, 176, 280, 286], 4)
    rrect(d, [312, 220, 360, 286], 4)
    for cx, cy in [(174, 166), (256, 144), (336, 188)]:   # белый дым (узнаваемо)
        disc(d, cx, cy, 24)
        disc(d, cx + 30, cy - 16, 17)
    for x in (168, 256, 344):                             # лёгкие окна (тонкие)
        dk.rectangle([x - 11, 344, x + 11, 396], fill=K)


def _hammer_img():
    s = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(s)
    rrect(d, [C - 90, 110, C + 90, 196], 14)              # боёк
    rrect(d, [C - 18, 196, C + 18, 452], 10)              # рукоять
    return s


def _wrench_img():
    s = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(s)
    rrect(d, [C - 17, 150, C + 17, 452], 10)              # тело
    ring(d, C, 150, 50, 28)                               # зев
    d.polygon([(C - 50, 110), (C + 50, 110), (C, 158)], fill=(0, 0, 0, 0))
    return s


def i_toolcross(im, d, dk):
    rot_paste(im, _hammer_img(), 40)
    rot_paste(im, _wrench_img(), -40)


def i_blueprint(im, d, dk):
    poly(d, [(150, 132), (350, 132), (392, 174),
             (392, 420), (150, 420)])                     # лист с загибом
    poly(d, [(350, 132), (350, 174), (392, 174)], color=(220, 220, 220, 255))
    for x in (210, 270, 330):                             # сетка чертежа
        dk.line([(x, 150), (x, 408)], fill=K, width=8)
    for y in (210, 270, 330):
        dk.line([(166, y), (388, y)], fill=K, width=8)


def i_bolt(im, d, dk):
    poly(d, [(286, 104), (164, 286), (248, 286),
             (210, 420), (358, 232), (272, 232)])         # молния


def i_recycle(im, d, dk):
    R = 118
    bb = [256 - R, 256 - R, 256 + R, 256 + R]
    for k in range(3):
        base = k * 120 - 86
        d.arc(bb, base + 6, base + 92, fill=W, width=34)
        a = math.radians(base + 96)
        ex, ey = 256 + R * math.cos(a), 256 + R * math.sin(a)
        tx, ty = -math.sin(a), math.cos(a)
        rx, ry = math.cos(a), math.sin(a)
        poly(d, [(ex + rx * 42, ey + ry * 42),
                 (ex - rx * 42, ey - ry * 42),
                 (ex + tx * 60, ey + ty * 60)])           # наконечник


def i_bricks(im, d, dk):
    rrect(d, [116, 178, 396, 394], 8)                     # белая стена
    for y in (250, 322):                                  # тонкий горизонт. шов
        dk.line([(120, y), (392, y)], fill=K, width=7)
    rows = [(178, 250, [256]), (250, 322, [187, 325]), (322, 394, [256])]
    for y0, y1, xs in rows:                               # тонкие вертик. швы вразбежку
        for x in xs:
            dk.line([(x, y0), (x, y1)], fill=K, width=7)


def i_dynamite(im, d, dk):
    for x in (188, 234, 280):                             # 3 шашки
        rrect(d, [x - 22, 212, x + 22, 402], 10)
    rrect(d, [160, 286, 308, 332], 6)                     # обвязка
    for x in (211, 257):                                  # разделители шашек
        dk.line([(x, 212), (x, 402)], fill=K, width=10)
    stroke(d, [(280, 212), (322, 156), (366, 178)], 12)   # фитиль
    disc(d, 372, 176, 18)                                 # искра


ICONS = {
    # Сражение
    "pistol": i_pistol, "rifle": i_rifle, "mg": i_mg, "magazine": i_magazine,
    "swords": i_swords, "ghost": i_ghost, "heart": i_heart, "shield": i_shield,
    "grenade": i_grenade, "jet": i_jet,
    # Выживание
    "pickaxe": i_pickaxe, "gem": i_gem, "beartrap": i_beartrap, "speed": i_speed,
    "leaf": i_leaf, "hourglass": i_hourglass, "compass": i_compass,
    "campfire": i_campfire, "moneybag": i_moneybag, "leaves": i_leaves,
    # Технология
    "wrench": i_wrench, "gear": i_gear, "tower": i_tower, "factory": i_factory,
    "toolcross": i_toolcross, "blueprint": i_blueprint, "bolt": i_bolt,
    "recycle": i_recycle, "bricks": i_bricks, "dynamite": i_dynamite,
}


def render(fn):
    wimg = Image.new("RGBA", (S, S), (0, 0, 0, 0)); dw = ImageDraw.Draw(wimg)
    kimg = Image.new("RGBA", (S, S), (0, 0, 0, 0)); dk = ImageDraw.Draw(kimg)
    fn(wimg, dw, dk)
    grown = wimg.split()[3].filter(ImageFilter.MaxFilter(2 * OW + 1))
    ol = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ol.paste((0, 0, 0, 255), (0, 0, S, S), grown)         # чёрная обводка под белым
    res = Image.alpha_composite(ol, wimg)
    res = Image.alpha_composite(res, kimg)                # чёрные детали поверх
    return res


def finish(res, name):
    bbox = res.split()[3].getbbox()
    cropped = res.crop(bbox)
    w, h = cropped.size
    scale = TARGET / float(max(w, h))
    nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
    cropped = cropped.resize((nw, nh), Image.LANCZOS)
    out = Image.new("RGBA", (OUT, OUT), (0, 0, 0, 0))
    out.paste(cropped, ((OUT - nw) // 2, (OUT - nh) // 2), cropped)
    out.save(f"{ICON_DIR}/{name}.png")


def main():
    for name, fn in ICONS.items():
        finish(render(fn), name)
        print("ok", name)
    # Контактный лист для визуальной проверки (на тёмных кругах, как в игре).
    cols = 6
    rows = (len(ICONS) + cols - 1) // cols
    cell = 96
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (14, 16, 20, 255))
    sd = ImageDraw.Draw(sheet)
    for i, name in enumerate(ICONS):
        cx = (i % cols) * cell + cell // 2
        cy = (i // cols) * cell + cell // 2
        sd.ellipse([cx - 38, cy - 38, cx + 38, cy + 38], fill=(40, 45, 55, 255))
        ic = Image.open(f"{ICON_DIR}/{name}.png").resize((58, 58), Image.LANCZOS)
        sheet.alpha_composite(ic, (cx - 29, cy - 29))
        sd.text((cx - 40, cy + 34), name, fill=(180, 185, 195, 255))
    sheet.save("debug/skill_icons_sheet.png")
    print("CONTACT SHEET: debug/skill_icons_sheet.png")


if __name__ == "__main__":
    main()
