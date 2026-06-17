# -*- coding: utf-8 -*-
"""Ассеты дерева навыков: СПЛОШНЫЕ белые силуэты-иконки из листа автора +
круглые диски/кольца/замок для узлов (вид по референсу автора).

Иконки: лист 3x3 (Downloads/Gemini_Generated_Image_...png) — чёрный контур на
белой карточке, карточки на сером фоне. Для каждой ячейки: находим белую
карточку по яркости и обрезаем по ней → строим СПЛОШНОЙ силуэт: утолщаем
контур (замыкая разрывы), заливаем фон от краёв (flood fill), всё, что не фон,
= силуэт (контур + внутренняя область) → белый силуэт на прозрачном фоне.
Сплошная заливка читается чётче тонкого контура и совпадает со стилем
референса (белые глифы на цветных кружках).

Круги/кольца/замок — для круглых узлов: диск (сплошной) тонируется цветом
ветки через modulate, кольцо — обводка, замок — бейдж недоступности.

Запуск (разово): python tools/gen_icons.py
Инструмент сборки ассетов — в самой игре Python не используется.
"""
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "icons")
os.makedirs(OUT, exist_ok=True)

SRC = r"C:\Users\kemal\Downloads\Gemini_Generated_Image_d26rhed26rhed26r.png"

ORDER = [
    "backpack", "c4", "hammer",
    "heart", "pickaxe", "sprint",
    "sword", "turret", "airstrike",
]

CANVAS = 224
MARGIN = 0.14
BRIGHT = 200       # выше — «белая карточка»
DARK = 120         # ниже — линия контура


def _ramp(p):
    """Мягкий порог: превращает размытую маску в анти-алиас край (~ленту 40 ед.)."""
    lo, hi = 108, 150
    if p <= lo:
        return 0
    if p >= hi:
        return 255
    return int((p - lo) / (hi - lo) * 255)


def _solid_silhouette(tile):
    """RGB-плитка карточки → L-маска сплошного белого силуэта с гладким краем.

    Качество (борьба с «углами» от грубого ИИ-контура): работаем на ×2, контур
    замыкаем морфологическим ЗАКРЫТИЕМ (Max→Min, без квадратного раздувания),
    заливаем фон от краёв, затем размываем маску и прогоняем через мягкий порог
    — край получается сглаженным, а не ступенчатым.
    """
    UP = 2
    L = tile.convert("L")
    w, h = L.size[0] * UP, L.size[1] * UP
    L = L.resize((w, h), Image.LANCZOS)
    # Контур (тёмные пиксели) → морфологическое закрытие (замкнуть разрывы,
    # не утолщая силуэт и не «обрубая» углы квадратами).
    outline = L.point(lambda p: 255 if p < DARK else 0)
    outline = outline.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.MinFilter(3))
    base = Image.new("RGB", (w, h), (255, 255, 255))
    base.paste((0, 0, 0), mask=outline)
    seeds = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1),
             (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]
    for s in seeds:
        try:
            ImageDraw.floodfill(base, s, (255, 0, 60), thresh=40)
        except Exception:
            pass
    px = base.load()
    sil = Image.new("L", (w, h), 0)
    sp = sil.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if not (r > 200 and g < 80 and b < 110):
                sp[x, y] = 255
    # Сглаживание края: размытие + мягкий порог (анти-алиас лента).
    sil = sil.filter(ImageFilter.GaussianBlur(2.4)).point(_ramp)
    return sil


def extract_icons():
    sheet = Image.open(SRC).convert("RGB")
    w, h = sheet.size
    cw, ch = w // 3, h // 3
    idx = 0
    for r in range(3):
        for c in range(3):
            cell = sheet.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch))
            gray = cell.convert("L")
            bright = gray.point(lambda p: 255 if p > BRIGHT else 0)
            bbox = bright.getbbox()
            if bbox:
                x0, y0, x1, y1 = bbox
                ins = 6
                cell = cell.crop((x0 + ins, y0 + ins, max(x0 + 7, x1 - ins), max(y0 + 7, y1 - ins)))
            sil = _solid_silhouette(cell)
            sbox = sil.point(lambda p: 255 if p > 30 else 0).getbbox()
            if sbox:
                sil = sil.crop(sbox)
            # Белый силуэт по маске альфы.
            icon = Image.new("RGBA", sil.size, (255, 255, 255, 0))
            icon.putalpha(sil)
            max_dim = int(CANVAS * (1 - 2 * MARGIN))
            sw, sh = icon.size
            scale = min(max_dim / sw, max_dim / sh)
            nw, nh = max(1, int(sw * scale)), max(1, int(sh * scale))
            icon = icon.resize((nw, nh), Image.LANCZOS)
            canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
            canvas.alpha_composite(icon, ((CANVAS - nw) // 2, (CANVAS - nh) // 2))
            canvas.save(os.path.join(OUT, ORDER[idx] + ".png"))
            idx += 1


def _disc(size):
    S = 4
    n = size * S
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ImageDraw.Draw(img).ellipse([0, 0, n - 1, n - 1], fill=(255, 255, 255, 255))
    img.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, "disc_%d.png" % size))


def _ring(size, thick):
    S = 4
    n = size * S
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([0, 0, n - 1, n - 1], fill=(255, 255, 255, 255))
    t = thick * S
    d.ellipse([t, t, n - 1 - t, n - 1 - t], fill=(0, 0, 0, 0))
    img.resize((size, size), Image.LANCZOS).save(os.path.join(OUT, "ring_%d.png" % size))


def _lock():
    S = 4
    s = 64 * S
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.arc([18 * S, 8 * S, 46 * S, 40 * S], 180, 360, fill=(255, 255, 255, 255), width=6 * S)
    d.rounded_rectangle([13 * S, 28 * S, 51 * S, 56 * S], radius=6 * S, fill=(255, 255, 255, 255))
    d.ellipse([28 * S, 36 * S, 36 * S, 44 * S], fill=(0, 0, 0, 0))
    d.rectangle([30 * S, 40 * S, 34 * S, 50 * S], fill=(0, 0, 0, 0))
    img.resize((64, 64), Image.LANCZOS).save(os.path.join(OUT, "lock.png"))


def main():
    extract_icons()
    for sz in (58, 76):
        _disc(sz)
        _ring(sz, 4)
    _lock()
    print("Готово:", OUT)
    for f in sorted(os.listdir(OUT)):
        if f.endswith(".png"):
            print(" ", f)


if __name__ == "__main__":
    main()
