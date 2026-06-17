# -*- coding: utf-8 -*-
"""Обработка листа иконок автора + вспомогательные текстуры для дерева навыков.

1) Источник: лист 3x3 (Downloads/Gemini_Generated_Image_...png) — карточки с
   чёрным контуром на белом фоне, сама сетка на сером фоне. Для каждой ячейки:
   находим яркую (белую) карточку → обрезаем по ней → конвертируем контур в
   БЕЛЫЙ силуэт на прозрачном фоне (тёмная линия = непрозрачно, светлый фон =
   прозрачно) → центрируем в квадратном холсте. Результат — assets/icons/*.png
   (имена как раньше, так что skill_menu.gd не меняется).
2) Вспомогательные текстуры для круглых узлов дерева: circle_mask.png (сплошной
   круг — под радиальную заливку TextureProgressBar) и lock.png (замок —
   для недоступных узлов).

Запуск (разово): python tools/gen_icons.py
Инструмент сборки ассетов — в самой игре Python не используется.
"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "icons")
os.makedirs(OUT, exist_ok=True)

SRC = r"C:\Users\kemal\Downloads\Gemini_Generated_Image_d26rhed26rhed26r.png"

# Порядок ячеек 3x3 (слева-вправо, сверху-вниз) → имя файла иконки.
ORDER = [
    "backpack", "c4", "hammer",
    "heart", "pickaxe", "sprint",
    "sword", "turret", "airstrike",
]

CANVAS = 220        # итоговый квадратный холст под иконку
MARGIN = 0.13        # доля холста, оставляемая пустой по краям
BRIGHT_THRESHOLD = 200   # выше — считаем «карточка» (белый фон листа)
ALPHA_CUTOFF = 205       # выше — прозрачно; ниже — контур проявляется


def extract_icons():
    sheet = Image.open(SRC).convert("RGB")
    w, h = sheet.size
    cw, ch = w // 3, h // 3
    idx = 0
    for r in range(3):
        for c in range(3):
            cell = sheet.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch))
            gray = cell.convert("L")
            bright = gray.point(lambda p: 255 if p > BRIGHT_THRESHOLD else 0)
            bbox = bright.getbbox()
            if bbox:
                x0, y0, x1, y1 = bbox
                inset = 4
                x0, y0 = x0 + inset, y0 + inset
                x1, y1 = max(x0 + 1, x1 - inset), max(y0 + 1, y1 - inset)
                cell = cell.crop((x0, y0, x1, y1))
            L = cell.convert("L")

            def alpha_fn(p, cutoff=ALPHA_CUTOFF):
                v = cutoff - p
                if v < 0:
                    return 0
                v = int(v / cutoff * 255)
                return 255 if v > 255 else v

            alpha = L.point(alpha_fn)
            white = Image.new("RGBA", cell.size, (255, 255, 255, 0))
            white.putalpha(alpha)
            stroke_bbox = alpha.point(lambda p: 255 if p > 10 else 0).getbbox()
            if stroke_bbox:
                white = white.crop(stroke_bbox)

            max_dim = int(CANVAS * (1 - 2 * MARGIN))
            sw, sh = white.size
            scale = min(max_dim / sw, max_dim / sh)
            nw, nh = max(1, int(sw * scale)), max(1, int(sh * scale))
            resized = white.resize((nw, nh), Image.LANCZOS)
            canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
            canvas.alpha_composite(resized, ((CANVAS - nw) // 2, (CANVAS - nh) // 2))
            canvas.save(os.path.join(OUT, ORDER[idx] + ".png"))
            idx += 1


def gen_circle(size):
    # TextureProgressBar требует текстуру РОВНО нужного размера: похоже, она
    # навязывает минимальный размер control = размеру текстуры (в отличие от
    # TextureRect, у которого EXPAND_IGNORE_SIZE это игнорирует) — поэтому
    # генерируем круг под каждый диаметр узла отдельно, а не один большой.
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = max(1, size // 64)
    d.ellipse([pad, pad, size - pad, size - pad], fill=(255, 255, 255, 255))
    img.save(os.path.join(OUT, "circle_%d.png" % size))


def gen_lock():
    s = 256
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.arc([68, 38, 188, 168], start=180, end=360, fill=(255, 255, 255, 255), width=24)
    d.rounded_rectangle([54, 118, 202, 222], radius=20, fill=(255, 255, 255, 255))
    d.ellipse([113, 148, 143, 178], fill=(0, 0, 0, 0))
    d.rectangle([121, 168, 135, 202], fill=(0, 0, 0, 0))
    img.save(os.path.join(OUT, "lock.png"))


def main():
    extract_icons()
    gen_circle(84)
    gen_circle(104)
    gen_lock()
    print("Готово:", OUT)
    for f in sorted(os.listdir(OUT)):
        if f.endswith(".png"):
            print(" ", f)


if __name__ == "__main__":
    main()
