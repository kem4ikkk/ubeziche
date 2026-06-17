extends CanvasLayer

## Дерево навыков (вид по референсу автора, правка 2026-06-17). Круглые узлы:
## тёмный диск + кольцо-обводка + сплошной белый силуэт-иконка + pill-бейдж
## уровня под кругом. Диск «заполняется» цветом ветки по уровню (прозрачность
## заливки = уровень/макс). Путь между узлами — как силовой кабель: серый, пока
## узел не открыт, и сплошной цвет ветки, когда открыт. Замок — на сигнатуре
## чужого класса. Три колонки: Бой / Добыча / Инженер; снизу вверх:
## выбор класса (большой) → 2 навыка (малые) → сигнатура (большой).
## Очки: 3 на старте + 1/ночь. На старте ничего не вкачано.

const ICON_DIR := "res://assets/icons/"
const BIG_D := 76
const SMALL_D := 58

# Палитра (тёмная тема, грим-выживание).
const BG := Color(0.055, 0.063, 0.078)
const NODE_DARK := Color(0.115, 0.13, 0.157)
const PATH_GRAY := Color(0.165, 0.18, 0.212)
const RING_GRAY := Color(0.30, 0.32, 0.37)
const TXT := Color(0.91, 0.918, 0.93)
const TXT_MUTED := Color(0.54, 0.565, 0.61)
const BADGE_BG := Color(0.08, 0.09, 0.11)
const LOCK_RED := Color(0.90, 0.34, 0.36)

const COLUMNS := [
	{"branch": "combat", "title": "Бой", "color": Color(0.898, 0.282, 0.302),
		"skills": ["melee", "vigor"],
		"sig": {"name": "Авиаудар", "icon": "airstrike", "desc": "Авиаудар (F): AoE 80, радиус 5, кд 25 с"}},
	{"branch": "gather", "title": "Добыча", "color": Color(0.275, 0.773, 0.416),
		"skills": ["gather", "capacity"],
		"sig": {"name": "Ускорение", "icon": "sprint", "desc": "Ускорение (F): +25% скорости 5 с, кд 12 с"}},
	{"branch": "engineer", "title": "Инженер", "color": Color(0.949, 0.722, 0.161),
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

const COL_X := [150, 380, 610]
# Центры узлов по вертикали (снизу вверх по смыслу: класс внизу).
const CY_SIG := 104.0
const CY_SKILL_B := 206.0
const CY_SKILL_A := 300.0
const CY_CLASS := 402.0

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


func _tex(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		var path := ICON_DIR + name + ".png"
		_tex_cache[name] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[name]


func _build_tree() -> void:
	var tree: Control = $Panel/Tree
	var bg := ColorRect.new()
	bg.color = BG
	bg.size = Vector2(760, 600)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tree.add_child(bg)

	_free_label = Label.new()
	_free_label.position = Vector2(0, 524)
	_free_label.size = Vector2(760, 24)
	_free_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tree.add_child(_free_label)
	var hint := Label.new()
	hint.position = Vector2(0, 550)
	hint.size = Vector2(760, 20)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = TXT_MUTED
	hint.add_theme_font_size_override("font_size", 12)
	hint.text = "клик по узлу — вложить очко · наведи курсор для описания"
	tree.add_child(hint)

	for ci in COLUMNS.size():
		var col: Dictionary = COLUMNS[ci]
		var x: int = COL_X[ci]
		var title := _make_label(tree, x - 100, 10, 200, 22)
		title.text = col.title
		title.modulate = col.color
		title.add_theme_font_size_override("font_size", 24)
		var sub := _make_label(tree, x - 100, 42, 200, 18)
		sub.add_theme_font_size_override("font_size", 12)

		# Пути (за узлами): между краями кругов.
		var seg_sig := _make_path(tree, x, CY_SIG + BIG_D / 2.0, CY_SKILL_B - SMALL_D / 2.0)
		var seg_b := _make_path(tree, x, CY_SKILL_B + SMALL_D / 2.0, CY_SKILL_A - SMALL_D / 2.0)
		var seg_a := _make_path(tree, x, CY_SKILL_A + SMALL_D / 2.0, CY_CLASS - BIG_D / 2.0)

		var sig := _make_node(tree, x, CY_SIG, BIG_D)
		sig.btn.pressed.connect(_on_sig.bind(col.branch))
		var skill_nodes: Dictionary = {}
		var node_b := _make_node(tree, x, CY_SKILL_B, SMALL_D)
		node_b.btn.pressed.connect(_on_skill.bind(col.skills[1]))
		skill_nodes[col.skills[1]] = node_b
		var node_a := _make_node(tree, x, CY_SKILL_A, SMALL_D)
		node_a.btn.pressed.connect(_on_skill.bind(col.skills[0]))
		skill_nodes[col.skills[0]] = node_a
		var cls_node := _make_node(tree, x, CY_CLASS, BIG_D)
		cls_node.btn.pressed.connect(_on_pick.bind(col.branch))

		_cols.append({"col": col, "sub": sub, "sig": sig, "skills": skill_nodes,
				"cls": cls_node, "seg_sig": seg_sig, "seg_b": seg_b, "seg_a": seg_a})


func _make_path(parent: Control, cx: int, y_top: float, y_bottom: float) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = PATH_GRAY
	bar.position = Vector2(cx - 2.5, y_top - 1.0)
	bar.size = Vector2(5, maxf(0.0, y_bottom - y_top) + 2.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	return bar


## Узел: тёмный диск + заливка (по уровню) + кольцо + иконка/текст + замок + бейдж.
func _make_node(parent: Control, cx: int, cy: float, d: int) -> Dictionary:
	var root := Control.new()
	root.position = Vector2(cx - d / 2.0, cy - d / 2.0)
	root.size = Vector2(d, d)
	parent.add_child(root)

	var disc_tex := _tex("disc_%d" % d)
	var ring_tex := _tex("ring_%d" % d)
	var disc_bg := _add_tex(root, disc_tex, Vector2(d, d), Vector2.ZERO)
	disc_bg.modulate = NODE_DARK
	var disc_fill := _add_tex(root, disc_tex, Vector2(d, d), Vector2.ZERO)
	var ring := _add_tex(root, ring_tex, Vector2(d, d), Vector2.ZERO)

	var isz := d * 0.52
	var icon := _add_tex(root, null, Vector2(isz, isz), Vector2((d - isz) / 2.0, (d - isz) / 2.0))

	var center := Label.new()
	center.position = Vector2(2, 0)
	center.size = Vector2(d - 4, d)
	center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	center.add_theme_font_size_override("font_size", 14)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.visible = false
	root.add_child(center)

	var lsz := d * 0.36
	var lock := _add_tex(root, _tex("lock"), Vector2(lsz, lsz), Vector2(d - lsz * 0.92, -lsz * 0.08))
	lock.modulate = LOCK_RED
	lock.visible = false

	# Pill-бейдж уровня под кругом.
	var badge := Panel.new()
	var bw := 48.0
	badge.position = Vector2((d - bw) / 2.0, d + 3)
	badge.size = Vector2(bw, 20)
	var sb := StyleBoxFlat.new()
	sb.bg_color = BADGE_BG
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = RING_GRAY
	badge.add_theme_stylebox_override("panel", sb)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(badge)
	var badge_l := Label.new()
	badge_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_l.add_theme_font_size_override("font_size", 12)
	badge_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(badge_l)
	# Ярлык ВСЕГДА растянут на весь pill (anchors) → текст центрируется при любой
	# ширине бейджа (раньше при динамической ширине ярлык не совпадал с pill и
	# текст уходил влево).
	badge_l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Кнопка-клик (поверх, прозрачная).
	var btn := Button.new()
	btn.size = Vector2(d, d)
	btn.flat = true
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(st, empty)
	root.add_child(btn)

	return {"root": root, "btn": btn, "disc_fill": disc_fill, "ring": ring,
			"icon": icon, "center": center, "lock": lock, "sb": sb,
			"badge": badge, "badge_l": badge_l, "d": float(d)}


func _add_tex(parent: Control, tex: Texture2D, size: Vector2, pos: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.size = size
	t.position = pos
	if tex != null:
		t.texture = tex
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t


func _make_label(parent: Control, x: int, y: int, w: int, h: int) -> Label:
	var l := Label.new()
	l.position = Vector2(x, y)
	l.size = Vector2(w, h)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _on_pick(branch: String) -> void:
	InventorySystem.set_class(branch)


func _on_skill(skill_id: String) -> void:
	InventorySystem.upgrade_skill(skill_id)


func _on_sig(_branch: String) -> void:
	InventorySystem.unlock_ability()


## Раскраска узла: заливка диска по уровню, цвет кольца/бейджа, видимость замка.
func _style_node(node: Dictionary, color: Color, frac: float, ring_color: Color,
		badge_text: String, badge_color: Color, lock: bool) -> void:
	var fill: Color = color
	fill.a = clampf(frac, 0.0, 1.0)
	node.disc_fill.modulate = fill
	node.ring.modulate = ring_color
	node.lock.visible = lock
	node.sb.border_color = badge_color
	node.badge_l.text = badge_text
	node.badge_l.modulate = badge_color if frac <= 0.001 else Color(0.97, 0.97, 0.98)
	# Ширина pill-бейджа под текст (чтобы слова «выбрать»/«✓ выбран» влезали).
	var f: Font = ThemeDB.fallback_font
	var tw: float = f.get_string_size(badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x if f != null else 40.0
	var bw: float = clampf(tw + 24.0, 44.0, 132.0)
	var d: float = node.d
	node.badge.size.x = bw
	node.badge.position.x = (d - bw) / 2.0   # ярлык растянут anchors-ом — следует за pill


func _refresh() -> void:
	var cls: String = InventorySystem.player_class
	var maxl: int = InventorySystem.SKILL_MAX_LEVEL
	var have_pts: bool = InventorySystem.skill_points > 0
	_free_label.text = "Свободные очки: %d        Класс: %s" % [
			InventorySystem.skill_points, CLASS_NAMES.get(cls, cls)]
	_free_label.modulate = TXT
	for c in _cols:
		var branch: String = c.col.branch
		var color: Color = c.col.color
		var invested: int = InventorySystem.get_branch_level(branch)
		c.sub.text = "вложено очков: %d" % invested
		c.sub.modulate = TXT_MUTED

		# --- Обычные навыки (малые узлы) ---
		var lvl_a := 0
		var lvl_b := 0
		for i in c.col.skills.size():
			var sid: String = c.col.skills[i]
			var node: Dictionary = c.skills[sid]
			var lvl: int = InventorySystem.get_skill_level(sid)
			if i == 0: lvl_a = lvl
			else: lvl_b = lvl
			node.icon.texture = _tex(InventorySystem.SKILLS[sid].icon)
			node.icon.modulate = Color(1, 1, 1) if lvl > 0 else Color(0.78, 0.8, 0.84)
			node.btn.tooltip_text = "%s\n%s" % [InventorySystem.SKILLS[sid].name, DESC.get(sid, "")]
			node.btn.disabled = (lvl >= maxl) or (not have_pts)
			var rc: Color = color if (lvl > 0 or have_pts) else RING_GRAY
			_style_node(node, color, float(lvl) / float(maxl), rc,
					"%d/%d" % [lvl, maxl], color if lvl > 0 else RING_GRAY, false)

		# --- Сигнатура (большой узел сверху) ---
		var sig: Dictionary = c.sig
		var sigd: Dictionary = c.col.sig
		var unlocked: bool = (cls == branch and InventorySystem.ability_unlocked())
		var available: bool = (cls == branch and invested >= 1 and have_pts and not unlocked)
		sig.icon.texture = _tex(sigd.icon)
		sig.icon.modulate = Color(1, 1, 1) if unlocked else Color(0.78, 0.8, 0.84)
		sig.btn.tooltip_text = "%s\n%s" % [sigd.name, sigd.desc]
		sig.btn.disabled = not available
		if unlocked:
			_style_node(sig, color, 1.0, color, "★", color, false)
		elif available:
			_style_node(sig, color, 0.0, color, "0/1", color, false)
		elif cls == branch:
			_style_node(sig, color, 0.0, RING_GRAY, "0/1", RING_GRAY, false)
		else:
			_style_node(sig, color, 0.0, RING_GRAY, "класс", RING_GRAY, true)

		# --- Выбор класса (большой узел снизу) ---
		var cb: Dictionary = c.cls
		cb.icon.visible = false
		cb.center.visible = true
		cb.center.text = c.col.title
		cb.btn.tooltip_text = "Класс: %s — открывает сигнатуру ветки (F)" % CLASS_NAMES[branch]
		if cls == branch:
			cb.center.modulate = Color(0.07, 0.08, 0.1)
			cb.btn.disabled = true
			_style_node(cb, color, 1.0, color, "✓ выбран", color, false)
		elif cls == "":
			cb.center.modulate = TXT
			cb.btn.disabled = false
			_style_node(cb, color, 0.0, color, "выбрать", color, false)
		else:
			cb.center.modulate = TXT_MUTED
			cb.btn.disabled = true
			_style_node(cb, color, 0.0, RING_GRAY, "—", RING_GRAY, false)

		# --- Пути: горят цветом ветки, когда верхний узел открыт ---
		c.seg_a.color = color if lvl_a >= 1 else PATH_GRAY      # класс → навык A
		c.seg_b.color = color if lvl_b >= 1 else PATH_GRAY      # навык A → навык B
		c.seg_sig.color = color if unlocked else PATH_GRAY      # навык B → сигнатура


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
