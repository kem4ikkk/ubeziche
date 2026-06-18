# -*- coding: utf-8 -*-
"""Иконки из системного шрифта Segoe UI Symbol (Этап UI-4).

Автор отверг рисованные вручную иконки («уродские») и выбрал МОНОХРОМ. Segoe UI
Symbol даёт чистые профессиональные ЧЁРНО-БЕЛЫЕ глифы для массы игровых понятий
(оружие, ресурсы, постройки, способности). Рендерим нужные глифы в белые PNG
(нормализуем размер), в игре тонируются по цвету (деньги — зелёные, энергия —
оранжевая и т.п.). Диски/кольца/glow/lock берутся из gen_icons.py (не трогаем).

Запуск:  python tools/gen_font_icons.py
"""
import os
from PIL import Image, ImageDraw, ImageFont

FONT = r"C:\Windows\Fonts\seguisym.ttf"
ICON_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "icons")
BIG = 240          # размер рендера глифа (для чёткости)
PAD = 60
OUT = 128
TARGET = 108       # к какому размеру вписываем содержимое

# name -> список кандидатов-символов (берём первый, у кого есть глиф).
MAP = {
	# --- Бой ---
	"pistol": ["🔫"], "rifle": ["🔫"], "mg": ["🔫"], "magazine": ["📦", "🎯"],
	"swords": ["⚔"], "ghost": ["👁", "☠"], "heart": ["❤"], "shield": ["🛡"],
	"grenade": ["💣"], "jet": ["✈"],
	# --- Выживание ---
	"pickaxe": ["⛏"], "gem": ["💎"], "beartrap": ["🎯", "☣"], "speed": ["🏃"],
	"leaf": ["🌿"], "hourglass": ["⏳"], "compass": ["🎒", "🧭"], "campfire": ["🔥"],
	"moneybag": ["💰"], "leaves": ["🍃"],
	# --- Технология ---
	"wrench": ["🔧"], "gear": ["⚙"], "tower": ["📡"], "factory": ["🏭"],
	"toolcross": ["⚒"], "blueprint": ["📐"], "bolt": ["⚡"], "recycle": ["♻"],
	"bricks": ["🏗", "🏠"], "dynamite": ["💣"],
	# --- Постройки (меню B) ---
	"turret": ["🔫"], "mortar": ["💥"], "medkit": ["⚕", "✚"], "generator": ["🔋"],
	# --- Ресурсы (HUD) ---
	"wood": ["🌲", "🌳"], "steel": ["🔩"], "coin": ["💲", "💵"], "energy": ["⚡"],
}


def _render(font, ch):
	im = Image.new("RGBA", (BIG + PAD * 2, BIG + PAD * 2), (0, 0, 0, 0))
	d = ImageDraw.Draw(im)
	d.text(((BIG + PAD * 2) // 2, (BIG + PAD * 2) // 2), ch, font=font, anchor="mm", fill=(255, 255, 255, 255))
	return im


def main():
	font = ImageFont.truetype(FONT, BIG)
	notdef = _render(font, "￿").tobytes()
	for name, cands in MAP.items():
		chosen = None
		for ch in cands:
			im = _render(font, ch)
			if im.split()[3].getbbox() is not None and im.tobytes() != notdef:
				chosen = im
				break
		if chosen is None:
			print("!! нет глифа:", name, cands)
			continue
		bbox = chosen.split()[3].getbbox()
		crop = chosen.crop(bbox)
		w, h = crop.size
		scale = TARGET / float(max(w, h))
		nw, nh = max(1, round(w * scale)), max(1, round(h * scale))
		crop = crop.resize((nw, nh), Image.LANCZOS)
		out = Image.new("RGBA", (OUT, OUT), (0, 0, 0, 0))
		out.paste(crop, ((OUT - nw) // 2, (OUT - nh) // 2), crop)
		out.save(os.path.join(ICON_DIR, name + ".png"))
		print("ok", name)


if __name__ == "__main__":
	main()
