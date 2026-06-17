extends CanvasLayer

## Дерево навыков (Этап 4.40 — полные деревья оригинала, «ёлочка»). Сетка 3×4 как
## в оригинале: колонки-ветки Сражение/Выживание/Технология, ряды «Уровень 1..4».
## Ряд1 = tier1 (3 узла), ряд2 = [tier2[0], МАСТЕРСТВО(центр), tier2[1]],
## ряд3 = tier3 (3), ряд4 = ультимейт (центр). Гейты-ёлочка: открыл любой tier1 до
## макс. → мастерство (выбор класса); мастерство до макс. → tier2; любой tier2 →
## tier3; любой tier3 → ультимейт. Закрытые узлы — с замком. Узлы: glow + тёмный
## диск + заливка цветом по уровню + кольцо + иконка + pill-бейдж; путь к узлу
## горит цветом ветки, когда узел открыт. Заливка/glow анимируются.

const ICON_DIR := "res://assets/icons/"
const SMALL_D := 52
const BIG_D := 72
const SUB := 62                       # смещение колонок ветки от её центра
const COL_X := [150, 380, 610]
const ROW_Y := [150.0, 250.0, 350.0, 452.0]   # Уровень 1 (верх) .. 4 (низ)

const BG := Color(0.055, 0.063, 0.078)
const NODE_DARK := Color(0.115, 0.13, 0.157)
const PATH_GRAY := Color(0.165, 0.18, 0.212)
const RING_GRAY := Color(0.30, 0.32, 0.37)
const TXT := Color(0.91, 0.918, 0.93)
const TXT_MUTED := Color(0.54, 0.565, 0.61)
const BADGE_BG := Color(0.08, 0.09, 0.11)
const LOCK_RED := Color(0.90, 0.34, 0.36)

const BRANCH_COLOR := {
	"combat": Color(0.898, 0.282, 0.302),
	"gather": Color(0.275, 0.773, 0.416),
	"engineer": Color(0.949, 0.722, 0.161),
}

var _nodes: Dictionary = {}           # id → node-словарь
var _paths: Array = []                # [{line, upper}]
var _branch_subs: Array = []          # [{branch, sub_label}]
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

	var title := _make_label(tree, 0, 10, 760, 26)
	title.text = "ДЕРЕВО НАВЫКОВ"
	title.add_theme_font_size_override("font_size", 20)

	# Подписи уровней слева.
	for r in 4:
		var rl := _make_label(tree, 4, ROW_Y[r] - 9, 64, 18)
		rl.text = "Ур. %d" % (r + 1)
		rl.modulate = TXT_MUTED
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		rl.add_theme_font_size_override("font_size", 11)

	for ci in InventorySystem.BRANCH_ORDER.size():
		var branch: String = InventorySystem.BRANCH_ORDER[ci]
		var data: Dictionary = InventorySystem.TREE[branch]
		var color: Color = BRANCH_COLOR[branch]
		var x: float = COL_X[ci]
		var c0 := x - SUB
		var c2 := x + SUB

		var pos := {}
		pos[data.tier1[0]] = Vector2(c0, ROW_Y[0])
		pos[data.tier1[1]] = Vector2(x, ROW_Y[0])
		pos[data.tier1[2]] = Vector2(c2, ROW_Y[0])
		pos[data.tier2[0]] = Vector2(c0, ROW_Y[1])
		pos[data.mastery] = Vector2(x, ROW_Y[1])
		pos[data.tier2[1]] = Vector2(c2, ROW_Y[1])
		pos[data.tier3[0]] = Vector2(c0, ROW_Y[2])
		pos[data.tier3[1]] = Vector2(x, ROW_Y[2])
		pos[data.tier3[2]] = Vector2(c2, ROW_Y[2])
		pos[data.ultimate] = Vector2(x, ROW_Y[3])

		# Пути (вертикальные по колонкам; горят, когда узел-назначение открыт).
		_paths.append({"line": _make_line(tree, pos[data.tier1[0]], pos[data.tier2[0]]), "upper": data.tier2[0]})
		_paths.append({"line": _make_line(tree, pos[data.tier2[0]], pos[data.tier3[0]]), "upper": data.tier3[0]})
		_paths.append({"line": _make_line(tree, pos[data.tier1[1]], pos[data.mastery]), "upper": data.mastery})
		_paths.append({"line": _make_line(tree, pos[data.mastery], pos[data.tier3[1]]), "upper": data.tier3[1]})
		_paths.append({"line": _make_line(tree, pos[data.tier3[1]], pos[data.ultimate]), "upper": data.ultimate})
		_paths.append({"line": _make_line(tree, pos[data.tier1[2]], pos[data.tier2[1]]), "upper": data.tier2[1]})
		_paths.append({"line": _make_line(tree, pos[data.tier2[1]], pos[data.tier3[2]]), "upper": data.tier3[2]})

		# Заголовок ветки + счётчик вложенного.
		var head := _make_label(tree, x - 110, 42, 220, 22)
		head.text = data.title
		head.modulate = color
		head.add_theme_font_size_override("font_size", 19)
		var sub := _make_label(tree, x - 110, 70, 220, 16)
		sub.add_theme_font_size_override("font_size", 11)
		_branch_subs.append({"branch": branch, "sub": sub})

		for id in pos:
			_add_node(tree, id, pos[id], BIG_D if id == data.ultimate else SMALL_D, color)

	_free_label = _make_label(tree, 0, 512, 760, 24)
	var hint := _make_label(tree, 0, 538, 760, 20)
	hint.modulate = TXT_MUTED
	hint.add_theme_font_size_override("font_size", 12)
	hint.text = "клик — вложить очко · следующий узел открыт, когда нижний прокачан до конца · N — закрыть"


func _add_node(parent: Control, id: String, center: Vector2, d: int, color: Color) -> void:
	var node := _make_node(parent, center, d, color)
	node.btn.pressed.connect(_on_node.bind(id))
	_nodes[id] = node


func _make_line(parent: Control, a: Vector2, b: Vector2) -> Line2D:
	var ln := Line2D.new()
	ln.points = PackedVector2Array([a, b])
	ln.width = 5.0
	ln.default_color = PATH_GRAY
	ln.antialiased = true
	ln.begin_cap_mode = Line2D.LINE_CAP_ROUND
	ln.end_cap_mode = Line2D.LINE_CAP_ROUND
	parent.add_child(ln)
	return ln


func _make_node(parent: Control, center: Vector2, d: int, color: Color) -> Dictionary:
	var root := Control.new()
	root.position = center - Vector2(d, d) / 2.0
	root.size = Vector2(d, d)
	parent.add_child(root)

	var gsz := d * 2.0
	var glow := _add_tex(root, _tex("glow"), Vector2(gsz, gsz), Vector2((d - gsz) / 2.0, (d - gsz) / 2.0))
	glow.modulate = Color(color.r, color.g, color.b, 0.0)

	var disc_tex := _tex("disc_%d" % d)
	var ring_tex := _tex("ring_%d" % d)
	var disc_bg := _add_tex(root, disc_tex, Vector2(d, d), Vector2.ZERO)
	disc_bg.modulate = NODE_DARK
	var disc_fill := _add_tex(root, disc_tex, Vector2(d, d), Vector2.ZERO)
	disc_fill.modulate = Color(color.r, color.g, color.b, 0.0)
	var ring := _add_tex(root, ring_tex, Vector2(d, d), Vector2.ZERO)

	var isz := d * 0.5
	var icon := _add_tex(root, null, Vector2(isz, isz), Vector2((d - isz) / 2.0, (d - isz) / 2.0))

	var lsz := d * 0.38
	var lock := _add_tex(root, _tex("lock"), Vector2(lsz, lsz), Vector2(d - lsz * 0.92, -lsz * 0.08))
	lock.modulate = LOCK_RED
	lock.visible = false

	var badge := Panel.new()
	badge.position = Vector2((d - 44.0) / 2.0, d + 2)
	badge.size = Vector2(44, 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = BADGE_BG
	sb.set_corner_radius_all(9)
	sb.set_border_width_all(2)
	sb.border_color = RING_GRAY
	badge.add_theme_stylebox_override("panel", sb)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(badge)
	var badge_l := Label.new()
	badge_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_l.add_theme_font_size_override("font_size", 11)
	badge_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(badge_l)
	badge_l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var btn := Button.new()
	btn.size = Vector2(d, d)
	btn.flat = true
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.add_theme_stylebox_override(st, empty)
	root.add_child(btn)

	return {"root": root, "btn": btn, "glow": glow, "disc_fill": disc_fill, "ring": ring,
			"icon": icon, "lock": lock, "sb": sb, "badge": badge, "badge_l": badge_l,
			"d": float(d), "color": color, "target_a": 0.0, "glow_t": 0.0, "pulse": false}


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


func _make_label(parent: Control, x: float, y: float, w: float, h: float) -> Label:
	var l := Label.new()
	l.position = Vector2(x, y)
	l.size = Vector2(w, h)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _on_node(id: String) -> void:
	InventorySystem.upgrade_skill(id)


func _style(node: Dictionary, frac: float, ring_color: Color, glow_t: float,
		pulse: bool, badge_text: String, badge_color: Color, lock: bool) -> void:
	var color: Color = node.color
	node.disc_fill.modulate = Color(color.r, color.g, color.b, node.disc_fill.modulate.a)
	node.glow.modulate = Color(color.r, color.g, color.b, node.glow.modulate.a)
	node.ring.modulate = ring_color
	node.lock.visible = lock
	node.target_a = clampf(frac, 0.0, 1.0)
	node.glow_t = glow_t
	node.pulse = pulse
	node.sb.border_color = badge_color
	node.badge_l.text = badge_text
	node.badge_l.modulate = badge_color if frac <= 0.001 else Color(0.97, 0.97, 0.98)
	var f: Font = ThemeDB.fallback_font
	var tw: float = f.get_string_size(badge_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x if f != null else 36.0
	var bw: float = clampf(tw + 20.0, 40.0, 120.0)
	node.badge.size.x = bw
	node.badge.position.x = (node.d - bw) / 2.0


func _refresh() -> void:
	var have_pts: bool = InventorySystem.skill_points > 0
	_free_label.text = "Накопленные очки: %d        Класс: %s" % [
			InventorySystem.skill_points, _class_title(InventorySystem.player_class)]
	_free_label.modulate = TXT

	for bs in _branch_subs:
		bs.sub.text = "вложено: %d" % InventorySystem.get_branch_level(bs.branch)
		bs.sub.modulate = TXT_MUTED

	for id in _nodes:
		var node: Dictionary = _nodes[id]
		var meta: Dictionary = InventorySystem.SKILLS[id]
		var color: Color = node.color
		var lvl: int = InventorySystem.get_skill_level(id)
		var maxv: int = InventorySystem.get_skill_max(id)
		var unlocked: bool = InventorySystem.is_skill_unlocked(id)
		var maxed: bool = lvl >= maxv
		var can: bool = unlocked and not maxed and have_pts
		node.icon.texture = _tex(meta.icon)
		node.icon.visible = true
		node.icon.modulate = Color(1, 1, 1) if lvl > 0 else Color(0.72, 0.74, 0.78)
		var note := "" if meta.get("ready", true) else "\n(эффект скоро)"
		node.btn.tooltip_text = "%s\n%s%s" % [meta.name, meta.get("desc", ""), note]
		node.btn.disabled = not can

		var ring: Color = color if (lvl > 0 or can) else RING_GRAY
		var glow_t: float = (0.18 + 0.34 * float(lvl) / float(maxv)) if lvl > 0 else 0.0
		var badge_text := "%d/%d" % [lvl, maxv]
		if meta.kind == "signature" and lvl > 0:
			badge_text = "★"
		elif meta.kind == "mastery" and lvl > 0:
			badge_text = "✓ класс"
		var badge_color: Color = color if lvl > 0 else RING_GRAY
		_style(node, float(lvl) / float(maxv), ring, glow_t, can and lvl == 0,
				badge_text, badge_color, not unlocked)

	for p in _paths:
		var br: String = InventorySystem.SKILLS[p.upper].branch
		p.line.default_color = BRANCH_COLOR[br] if InventorySystem.is_skill_unlocked(p.upper) else PATH_GRAY


func _class_title(branch: String) -> String:
	match branch:
		"combat": return "Боец"
		"gather": return "Добытчик"
		"engineer": return "Инженер"
	return "не выбран"


func _process(_dt: float) -> void:
	if not visible:
		return
	var dt := get_process_delta_time()
	var k := clampf(dt * 9.0, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 3.5)
	for id in _nodes:
		var n: Dictionary = _nodes[id]
		var df: Color = n.disc_fill.modulate
		df.a = lerpf(df.a, n.target_a, k)
		n.disc_fill.modulate = df
		var gt: float = n.glow_t + (0.22 * pulse if n.pulse else 0.0)
		var gc: Color = n.glow.modulate
		gc.a = lerpf(gc.a, gt, k)
		n.glow.modulate = gc


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
