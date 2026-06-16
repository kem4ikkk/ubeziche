extends CanvasLayer

## Дерево навыков (Этап 4.12d): графический вид по трём колонкам-веткам
## (Бой / Добыча / Инженер), как в референс-скрине. Открывается клавишей N.
## Каждая колонка — «спина» + узлы снизу вверх: выбор класса → ранги ветки
## (ур. 1..3) → сигнатурная способность (верхний узел). Механика прокачки
## прежняя (Этап 4.12): своя ветка до SKILL_MAX, чужая — на +1 сверх базы
## (get_skill_cap); сигнатура — только своего класса (unlock_ability).
## Очки: 3 на старте + 1/ночь (InventorySystem). Класс выбирается ЗДЕСЬ (стартовый
## попап убран в 4.12c); reset_run_progression на новый забег.

const COLUMNS := [
	{"key": "combat",   "title": "Бой",     "color": Color(0.90, 0.30, 0.30), "ability": "Авиаудар"},
	{"key": "gather",   "title": "Добыча",  "color": Color(0.30, 0.85, 0.40), "ability": "Ускорение"},
	{"key": "engineer", "title": "Инженер", "color": Color(0.95, 0.80, 0.20), "ability": "C4"},
]
const CLASS_NAMES := {"combat": "Боец", "gather": "Добытчик", "engineer": "Инженер", "": "не выбран"}

# Раскладка узлов внутри Control "Tree" (≈760×600).
const COL_X := [180, 380, 580]
const Y_TITLE := 40
const Y_PTS := 64
const Y_SIG := 96
const Y_RANK := [330, 248, 166]   # ранги 1,2,3 (снизу вверх)
const Y_CLASS := 430
const NODE_W := 112
const NODE_H := 54

var _cols: Array = []
var _free_label: Label
var _capture_mode := false


func _ready() -> void:
	add_to_group("skill_menu")
	_capture_mode = OS.get_cmdline_user_args().has("--capture")
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Новый забег: сброс класса/навыков (стартового попапа нет, 4.12c). В capture
	# не трогаем — класс/уровни задаёт тест.
	if not _capture_mode:
		InventorySystem.reset_run_progression()
	_build_tree()
	InventorySystem.skills_changed.connect(_refresh)
	InventorySystem.class_changed.connect(func(_c): _refresh())
	visible = false
	_refresh()


func _build_tree() -> void:
	var tree: Control = $Panel/Tree
	# Тёмный непрозрачный фон (чтобы 3D-сцена не просвечивала сквозь дерево).
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.09, 0.97)
	bg.position = Vector2(0, 0)
	bg.size = Vector2(760, 600)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tree.add_child(bg)
	# Подпись свободных очков и класса (внизу по центру).
	_free_label = Label.new()
	_free_label.position = Vector2(0, 470)
	_free_label.size = Vector2(760, 24)
	_free_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tree.add_child(_free_label)

	for ci in COLUMNS.size():
		var col: Dictionary = COLUMNS[ci]
		var x: int = COL_X[ci]
		# «Спина» колонки (полупрозрачная линия за узлами).
		var spine := ColorRect.new()
		spine.color = Color(col.color.r, col.color.g, col.color.b, 0.35)
		spine.position = Vector2(x - 2, Y_SIG + NODE_H / 2)
		spine.size = Vector2(4, Y_CLASS - Y_SIG)
		tree.add_child(spine)
		# Заголовок ветки + строка уровня.
		var title := _make_label(tree, x - 90, Y_TITLE, 180)
		title.text = col.title
		title.modulate = col.color
		title.add_theme_font_size_override("font_size", 18)
		var pts := _make_label(tree, x - 90, Y_PTS, 180)
		# Узлы: сигнатура (верх), ранги, выбор класса (низ).
		var sig := _make_node(tree, x, Y_SIG)
		sig.pressed.connect(_on_sig.bind(col.key))
		var ranks: Array = []
		for r in 3:
			var rb := _make_node(tree, x, Y_RANK[r])
			rb.pressed.connect(_on_rank.bind(col.key))
			ranks.append(rb)
		var cls_btn := _make_node(tree, x, Y_CLASS)
		cls_btn.pressed.connect(_on_pick.bind(col.key))
		_cols.append({"col": col, "pts": pts, "sig": sig, "ranks": ranks, "cls_btn": cls_btn})


func _make_node(parent: Control, cx: int, y: int) -> Button:
	var b := Button.new()
	b.size = Vector2(NODE_W, NODE_H)
	b.position = Vector2(cx - NODE_W / 2, y)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD
	parent.add_child(b)
	return b


func _make_label(parent: Control, x: int, y: int, w: int) -> Label:
	var l := Label.new()
	l.position = Vector2(x, y)
	l.size = Vector2(w, 22)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _on_pick(key: String) -> void:
	InventorySystem.set_class(key)


func _on_rank(key: String) -> void:
	InventorySystem.upgrade_skill(key)


func _on_sig(_key: String) -> void:
	InventorySystem.unlock_ability()


func _refresh() -> void:
	var cls: String = InventorySystem.player_class
	_free_label.text = "Свободные очки: %d    ·    Класс: %s    ·    клик по узлу — вложить очко" % [
			InventorySystem.skill_points, CLASS_NAMES.get(cls, cls)]
	for c in _cols:
		var key: String = c.col.key
		var color: Color = c.col.color
		var lvl: int = InventorySystem.get_skill_level(key)
		var cap: int = InventorySystem.get_skill_cap(key)
		var maxl: int = InventorySystem.SKILL_MAX[key]
		c.pts.text = "ур. %d / %d" % [lvl, maxl]
		c.pts.modulate = color
		# Узел выбора класса (низ).
		var cb: Button = c.cls_btn
		if cls == key:
			cb.text = "✓ " + c.col.title
			cb.disabled = true
			cb.modulate = color
		elif cls == "":
			cb.text = "Выбрать\n" + c.col.title
			cb.disabled = false
			cb.modulate = Color(1, 1, 1)
		else:
			cb.text = c.col.title
			cb.disabled = true
			cb.modulate = Color(0.4, 0.4, 0.4)
		# Ранги ветки (ур. 1..3).
		for r in 3:
			var l_lvl: int = r + 1
			var rb: Button = c.ranks[r]
			if lvl >= l_lvl:
				rb.text = "ур.%d\n[1/1] ✓" % l_lvl
				rb.disabled = true
				rb.modulate = color
			elif lvl == l_lvl - 1 and l_lvl <= cap and InventorySystem.skill_points > 0:
				rb.text = "ур.%d\n[0/1] +" % l_lvl
				rb.disabled = false
				rb.modulate = Color(1, 1, 1)
			elif l_lvl > cap:
				rb.text = "ур.%d\n✕ закр." % l_lvl
				rb.disabled = true
				rb.modulate = Color(0.35, 0.35, 0.35)
			else:
				rb.text = "ур.%d\n[0/1]" % l_lvl
				rb.disabled = true
				rb.modulate = Color(0.55, 0.55, 0.55)
		# Сигнатурная способность (верх): только своего класса.
		var ab: String = c.col.ability
		var sig: Button = c.sig
		if cls == key and InventorySystem.ability_unlocked():
			sig.text = "★ " + ab
			sig.disabled = true
			sig.modulate = color
		elif cls == key and lvl >= 1 and InventorySystem.skill_points > 0:
			sig.text = "↑ " + ab + "\n[открыть]"
			sig.disabled = false
			sig.modulate = Color(1, 1, 1)
		else:
			sig.text = ab + "\n✕"
			sig.disabled = true
			sig.modulate = Color(0.4, 0.4, 0.4)


## Открыть/закрыть меню (вызывается из player.gd по клавише N).
func toggle() -> void:
	visible = not visible
	# Паузы в игре НЕТ (4.31): меню открыто — игра идёт. Только курсор для кликов.
	if not _capture_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	if visible:
		_refresh()


## Закрыть меню, если открыто (для Esc из player.gd).
func close() -> void:
	if visible:
		toggle()
