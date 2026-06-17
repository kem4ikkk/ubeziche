extends CanvasLayer

## Дерево навыков (правка 2026-06-17, вид — по референсу автора): КРУГЛЫЕ узлы с
## радиальной заливкой (TextureProgressBar) — кружок заполняется цветом ветки
## пропорционально вложенному уровню, путь между узлами горит серым, пока
## следующий узел не вкачан, и цветом ветки, когда «пройден». Иконки — из
## набора автора (assets/icons/*.png, контур, фон убран — tools/gen_icons.py).
## Три колонки-ветки (Бой / Добыча / Инженер), снизу вверх: выбор класса
## (большой кружок) → два обычных навыка (малые кружки, ур. 1..3) →
## сигнатурная способность (большой кружок, только своего класса).
## Очки: 3 на старте + 1/ночь. На старте ничего не вкачано (reset_run_progression).

const ICON_DIR := "res://assets/icons/"

const COLUMNS := [
	{"branch": "combat", "title": "Бой", "color": Color(0.90, 0.32, 0.32),
		"skills": ["melee", "vigor"],
		"sig": {"name": "Авиаудар", "icon": "airstrike", "desc": "Авиаудар (F): AoE 80, радиус 5, кд 25 с"}},
	{"branch": "gather", "title": "Добыча", "color": Color(0.34, 0.85, 0.42),
		"skills": ["gather", "capacity"],
		"sig": {"name": "Ускорение", "icon": "sprint", "desc": "Ускорение (F): +25% скорости 5 с, кд 12 с"}},
	{"branch": "engineer", "title": "Инженер", "color": Color(0.95, 0.80, 0.22),
		"skills": ["repair", "turret"],
		"sig": {"name": "C4", "icon": "c4", "desc": "C4 (F): крафт в мастерской, AoE 120"}},
]
const CLASS_NAMES := {"combat": "Боец", "gather": "Добытчик", "engineer": "Инженер", "": "не выбран"}

const DESC := {
	"melee": "Урон топора по зомби: +4 / +8 / +12",
	"vigor": "Макс. здоровье: +15 / +30 / +45",
	"gather": "Ресурса за удар: 2 / 3 / 4",
	"capacity": "Лимит ресурсов: +20 / +40 / +60",
	"repair": "Ремонт построек: +5% / +10% / +15%",
	"turret": "Урон турелей: +5% / +10% / +15%",
}

# Раскладка внутри Control "Tree" (760×600). Большие узлы — класс/сигнатура,
# малые — обычные навыки. Зазор между краями соседних узлов везде 24 px.
const COL_X := [150, 380, 610]
const BIG_D := 104.0
const SMALL_D := 84.0
const Y_TITLE := 4
const Y_SUB := 26
const CY_SIG := 110.0
const CY_SKILL_B := 228.0
const CY_SKILL_A := 336.0
const CY_CLASS := 454.0

const GRAY := Color(0.30, 0.31, 0.34)
const UNDER_GRAY := Color(0.20, 0.21, 0.24)

var _cols: Array = []
var _free_label: Label
var _tex_cache: Dictionary = {}
var _capture_mode := false


func _ready() -> void:
	add_to_group("skill_menu")
	_capture_mode = OS.get_cmdline_user_args().has("--capture")
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _capture_mode:
		InventorySystem.reset_run_progression()
	_build_tree()
	InventorySystem.skills_changed.connect(_refresh)
	InventorySystem.class_changed.connect(func(_c): _refresh())
	visible = false
	_refresh()


func _icon(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		var path := ICON_DIR + name + ".png"
		_tex_cache[name] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[name]


func _build_tree() -> void:
	var tree: Control = $Panel/Tree
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.09, 0.97)
	bg.size = Vector2(760, 600)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tree.add_child(bg)

	_free_label = Label.new()
	_free_label.position = Vector2(0, 520)
	_free_label.size = Vector2(760, 24)
	_free_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tree.add_child(_free_label)
	var hint := Label.new()
	hint.position = Vector2(0, 546)
	hint.size = Vector2(760, 22)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(0.6, 0.6, 0.66)
	hint.text = "клик по узлу — вложить очко · наведи курсор для описания эффекта"
	tree.add_child(hint)

	for ci in COLUMNS.size():
		var col: Dictionary = COLUMNS[ci]
		var x: int = COL_X[ci]
		var title := _make_label(tree, x - 90, Y_TITLE, 180)
		title.text = col.title
		title.modulate = col.color
		title.add_theme_font_size_override("font_size", 17)
		var sub := _make_label(tree, x - 90, Y_SUB, 180)
		sub.add_theme_font_size_override("font_size", 11)

		# Пути между узлами (рисуются ДО узлов — лежат позади).
		var seg_sig := _make_path(tree, x, CY_SIG + BIG_D / 2.0, CY_SKILL_B - SMALL_D / 2.0)
		var seg_b := _make_path(tree, x, CY_SKILL_B + SMALL_D / 2.0, CY_SKILL_A - SMALL_D / 2.0)
		var seg_a := _make_path(tree, x, CY_SKILL_A + SMALL_D / 2.0, CY_CLASS - BIG_D / 2.0)

		var sig := _make_circle_node(tree, x, CY_SIG, BIG_D)
		sig.btn.pressed.connect(_on_sig.bind(col.branch))
		var skill_nodes: Dictionary = {}
		var node_b := _make_circle_node(tree, x, CY_SKILL_B, SMALL_D)
		node_b.btn.pressed.connect(_on_skill.bind(col.skills[1]))
		skill_nodes[col.skills[1]] = node_b
		var node_a := _make_circle_node(tree, x, CY_SKILL_A, SMALL_D)
		node_a.btn.pressed.connect(_on_skill.bind(col.skills[0]))
		skill_nodes[col.skills[0]] = node_a
		var cls_node := _make_circle_node(tree, x, CY_CLASS, BIG_D)
		cls_node.btn.pressed.connect(_on_pick.bind(col.branch))

		_cols.append({"col": col, "sub": sub, "sig": sig, "skills": skill_nodes,
				"cls": cls_node, "seg_sig": seg_sig, "seg_b": seg_b, "seg_a": seg_a})


## Вертикальная полоса-путь между двумя узлами (серая по умолчанию, загорается
## цветом ветки в _refresh, когда нижний узел пройден).
func _make_path(parent: Control, cx: int, y_top: float, y_bottom: float) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = GRAY
	bar.position = Vector2(cx - 3, y_top)
	bar.size = Vector2(6, maxf(0.0, y_bottom - y_top))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	return bar


## Круглый узел: Button (клик, без видимого фона) + TextureProgressBar (радиальная
## заливка по уровню) + иконка навыка + бейдж-замок (недоступен) + подпись уровня.
func _make_circle_node(parent: Control, cx: int, cy: float, d: float) -> Dictionary:
	var root := Control.new()
	root.position = Vector2(cx - d / 2.0, cy - d / 2.0)
	root.size = Vector2(d, d + 22)
	parent.add_child(root)

	var btn := Button.new()
	btn.size = Vector2(d, d)
	btn.flat = true
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(state, empty)
	root.add_child(btn)

	var fill := TextureProgressBar.new()
	var circle_tex := _icon("circle_%d" % int(d))
	fill.texture_under = circle_tex
	fill.texture_progress = circle_tex
	fill.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	fill.radial_initial_angle = -90.0
	fill.tint_under = UNDER_GRAY
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.size = Vector2(d, d)               # после текстур — точный размер текстуры, конфликта по минимуму нет
	root.add_child(fill)

	var isz := d * 0.46
	var icon := TextureRect.new()
	icon.size = Vector2(isz, isz)
	icon.position = Vector2((d - isz) / 2.0, (d - isz) / 2.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(icon)

	var center_label := Label.new()
	center_label.position = Vector2(2, 0)
	center_label.size = Vector2(d - 4, d)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	center_label.add_theme_font_size_override("font_size", 13)
	center_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_label.visible = false
	root.add_child(center_label)

	var lsz := d * 0.32
	var lock := TextureRect.new()
	# ВАЖНО: expand_mode/stretch_mode/size — ДО texture (иначе при назначении
	# текстуры с дефолтным expand_mode размер «залипает» на исходных 256px,
	# как было с этим узлом до правки — см. icon выше, где texture всегда
	# назначается позже, в _refresh, когда expand_mode уже выставлен).
	lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lock.size = Vector2(lsz, lsz)
	lock.position = Vector2(d - lsz * 0.85, -lsz * 0.1)
	lock.texture = _icon("lock")
	lock.modulate = Color(0.95, 0.35, 0.35)
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock.visible = false
	root.add_child(lock)

	var pip := Label.new()
	pip.position = Vector2(0, d + 1)
	pip.size = Vector2(d, 20)
	pip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pip.add_theme_font_size_override("font_size", 13)
	root.add_child(pip)

	return {"root": root, "btn": btn, "fill": fill, "icon": icon, "lock": lock,
			"pip": pip, "center_label": center_label}


func _make_label(parent: Control, x: int, y: int, w: int) -> Label:
	var l := Label.new()
	l.position = Vector2(x, y)
	l.size = Vector2(w, 22)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _on_pick(branch: String) -> void:
	InventorySystem.set_class(branch)


func _on_skill(skill_id: String) -> void:
	InventorySystem.upgrade_skill(skill_id)


func _on_sig(_branch: String) -> void:
	InventorySystem.unlock_ability()


func _refresh() -> void:
	var cls: String = InventorySystem.player_class
	var maxl: int = InventorySystem.SKILL_MAX_LEVEL
	_free_label.text = "Свободные очки: %d    ·    Класс: %s" % [
			InventorySystem.skill_points, CLASS_NAMES.get(cls, cls)]
	for c in _cols:
		var branch: String = c.col.branch
		var color: Color = c.col.color
		var invested: int = InventorySystem.get_branch_level(branch)
		c.sub.text = "вложено очков: %d" % invested
		c.sub.modulate = color

		# --- Обычные навыки (малые узлы) ---
		var skill_a_lvl := 0
		var skill_b_lvl := 0
		for i in c.col.skills.size():
			var sid: String = c.col.skills[i]
			var node: Dictionary = c.skills[sid]
			var lvl: int = InventorySystem.get_skill_level(sid)
			if i == 0:
				skill_a_lvl = lvl
			else:
				skill_b_lvl = lvl
			node.icon.texture = _icon(InventorySystem.SKILLS[sid].icon)
			node.btn.tooltip_text = "%s\n%s" % [InventorySystem.SKILLS[sid].name, DESC.get(sid, "")]
			node.fill.max_value = maxl
			node.fill.value = lvl
			node.fill.tint_progress = color
			node.pip.text = "%d/%d" % [lvl, maxl]
			node.pip.modulate = color if lvl > 0 else Color(0.75, 0.75, 0.8)
			node.btn.disabled = (lvl >= maxl) or (InventorySystem.skill_points <= 0)

		# --- Сигнатура (большой узел сверху): только своего класса ---
		var sig: Dictionary = c.sig
		var sigd: Dictionary = c.col.sig
		var unlocked: bool = (cls == branch and InventorySystem.ability_unlocked())
		var available: bool = (cls == branch and invested >= 1 and InventorySystem.skill_points > 0 and not unlocked)
		sig.icon.texture = _icon(sigd.icon)
		sig.btn.tooltip_text = "%s\n%s" % [sigd.name, sigd.desc]
		sig.fill.max_value = 1
		sig.fill.value = 1 if unlocked else 0
		sig.fill.tint_progress = color
		sig.lock.visible = not (unlocked or available)
		sig.btn.disabled = not available
		if unlocked:
			sig.pip.text = "★ открыто"
			sig.pip.modulate = color
		elif available:
			sig.pip.text = "＋ открыть"
			sig.pip.modulate = Color(1, 1, 1)
		elif cls == branch:
			sig.pip.text = "нужен ур.1"
			sig.pip.modulate = Color(0.7, 0.7, 0.75)
		else:
			sig.pip.text = "свой класс"
			sig.pip.modulate = Color(0.6, 0.6, 0.65)

		# --- Выбор класса (большой узел снизу) ---
		var cb: Dictionary = c.cls
		cb.icon.visible = false
		cb.center_label.visible = true
		cb.center_label.text = c.col.title
		cb.fill.max_value = 1
		cb.fill.tint_progress = color
		if cls == branch:
			cb.fill.value = 1
			cb.center_label.modulate = Color(0.08, 0.08, 0.1)
			cb.pip.text = "✓ выбран"
			cb.pip.modulate = color
			cb.btn.disabled = true
		elif cls == "":
			cb.fill.value = 0
			cb.center_label.modulate = Color(1, 1, 1)
			cb.pip.text = "выбрать"
			cb.pip.modulate = Color(1, 1, 1)
			cb.btn.disabled = false
		else:
			cb.fill.value = 0
			cb.center_label.modulate = Color(0.55, 0.55, 0.6)
			cb.pip.text = "—"
			cb.pip.modulate = Color(0.5, 0.5, 0.55)
			cb.btn.disabled = true

		# --- Пути: горят цветом ветки, когда нижний узел «пройден», иначе серые ---
		c.seg_a.color = color if cls == branch else GRAY                 # класс → навык A
		c.seg_b.color = color if skill_a_lvl >= 1 else GRAY               # навык A → навык B
		c.seg_sig.color = color if skill_b_lvl >= 1 else GRAY             # навык B → сигнатура


## Открыть/закрыть меню (вызывается из player.gd по клавише N).
func toggle() -> void:
	visible = not visible
	if not _capture_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	if visible:
		_refresh()


## Закрыть меню, если открыто (для Esc из player.gd).
func close() -> void:
	if visible:
		toggle()
