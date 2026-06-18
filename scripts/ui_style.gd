class_name UiStyle
extends RefCounted

## Единый визуальный стиль UI (Этап UI-1). Тёмная тема в духе меню навыков:
## панели, кнопки, прогресс-бары, цвета, отступы — один Theme на весь HUD и меню.
## Ассетов извне нет: всё на StyleBoxFlat + дефолтный шрифт Godot (чистый Noto Sans).

const BG_PANEL := Color(0.058, 0.067, 0.085, 0.90)   # подложка панели (с альфой)
const BORDER := Color(0.24, 0.27, 0.34, 0.95)
const TEXT := Color(0.90, 0.915, 0.935)
const MUTED := Color(0.56, 0.59, 0.66)
const ACCENT := Color(0.96, 0.73, 0.18)              # золотой акцент (как ультимейт)
const GOOD := Color(0.32, 0.80, 0.46)
const WARN := Color(0.96, 0.62, 0.22)
const BAD := Color(0.93, 0.30, 0.30)
const BAR_BG := Color(0.07, 0.08, 0.10, 0.92)

static var _theme: Theme = null


## Стилбокс панели (тёмная скруглённая подложка с тонкой рамкой).
static func panel_box(bg: Color = BG_PANEL, radius: int = 12, border: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = BORDER
	s.set_content_margin_all(12)
	return s


static func _btn_box(c: Color, border_col: Color = BORDER, bw: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(7)
	s.set_border_width_all(bw)
	s.border_color = border_col
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


static func _bar_box(c: Color, radius: int = 5) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	return s


## Общий Theme (кэшируется). Применяется как `control.theme = UiStyle.theme()`.
static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 16

	var pbox := panel_box()
	t.set_stylebox("panel", "PanelContainer", pbox)
	t.set_stylebox("panel", "Panel", panel_box(BG_PANEL, 14, 1))

	t.set_stylebox("normal", "Button", _btn_box(Color(0.12, 0.135, 0.165, 0.96)))
	t.set_stylebox("hover", "Button", _btn_box(Color(0.17, 0.195, 0.235, 0.99)))
	t.set_stylebox("pressed", "Button", _btn_box(Color(0.20, 0.16, 0.06, 1.0), ACCENT))
	t.set_stylebox("disabled", "Button", _btn_box(Color(0.085, 0.095, 0.115, 0.7), Color(0.18, 0.20, 0.24, 0.6)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_color("font_disabled_color", "Button", MUTED)
	t.set_font_size("font_size", "Button", 16)

	t.set_color("font_color", "Label", TEXT)
	t.set_font_size("font_size", "Label", 16)

	t.set_stylebox("background", "ProgressBar", _bar_box(BAR_BG))
	t.set_stylebox("fill", "ProgressBar", _bar_box(GOOD))
	t.set_color("font_color", "ProgressBar", TEXT)

	_theme = t
	return t
