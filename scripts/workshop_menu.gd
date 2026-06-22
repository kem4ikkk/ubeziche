extends CanvasLayer

## UI-меню Мастерской (Этап 4.27): открывается клавишей E рядом с мастерской
## (workshop.gd). За РЕСУРСЫ: стена, апгрейд тира, классовые инструменты
## (нож/улучшенный топор/молот — гейт по уровню соответствующей ветки навыка).
## Деньги здесь не тратятся (только на чёрном рынке, Этап 4.24).

@onready var _list: VBoxContainer = $Panel/VBox/List

const BRANCH_NAME := {"combat": "Бой", "gather": "Добыча", "engineer": "Инженер"}

var _capture_mode := false
var _workshop: Node


func _ready() -> void:
	add_to_group("workshop_menu")
	_capture_mode = OS.get_cmdline_user_args().has("--capture")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_apply_style()


## Единый стиль (Этап UI-1): тёмная панель + кнопки в стиле меню навыков.
func _apply_style() -> void:
	($Panel as Panel).theme = UiStyle.theme()
	var title := $Panel/VBox/TitleLabel as Label
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UiStyle.ACCENT)


func _resolve_workshop() -> Node:
	if not is_instance_valid(_workshop):
		_workshop = get_tree().get_first_node_in_group("workshop")
	return _workshop


## Открыть/закрыть меню (вызывается из workshop.gd по клавише E).
func toggle() -> void:
	visible = not visible
	if visible:
		_rebuild()
	# Паузы в игре НЕТ (решение автора 2026-06-16) — только курсор для кликов.
	if not _capture_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED


## Закрыть меню, если открыто (для Esc из player.gd).
func close() -> void:
	if visible:
		toggle()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var ws := _resolve_workshop()
	if ws == null:
		return
	# Стена строится в МЕНЮ ПОСТРОЕК (B), а не здесь (правка автора).
	# Апгрейд тира за ресурсы.
	var tier: int = InventorySystem.shelter_tier
	if tier >= InventorySystem.MAX_TIER:
		_add_button("Убежище: Тир %d (максимум)" % tier, true, Callable())
	else:
		var tc: Dictionary = ws.TIER_UPGRADE_COST[tier + 1]
		var tcost := {"wood": int(tc.wood), "steel": int(tc.steel)}
		var poor: bool = not _can_afford(tcost)
		_add_button("Тир %d → %d (%d дерева, %d стали)" % [tier, tier + 1, tc.wood, tc.steel],
				poor, func() -> void: ws.upgrade_shelter_tier(); _rebuild())
		if poor:
			_add_deficit(tcost)
	# Классовые инструменты (гейт по ветке навыка).
	for key in ws.TOOL_KEYS:
		var spec: Dictionary = ws.get_tool_spec(key)
		var owned: bool = InventorySystem.get(spec.flag)
		var locked: bool = InventorySystem.player_class != spec.branch
		var tcost := {"wood": int(spec.cost.wood), "steel": int(spec.cost.steel)}
		var poor: bool = not owned and not locked and not _can_afford(tcost)
		var label: String
		if owned:
			label = "%s — скрафчен ✓" % spec.title
		else:
			label = "%s (%d дерева, %d стали) — мастерство «%s»%s" % [
					spec.title, spec.cost.wood, spec.cost.steel,
					BRANCH_NAME.get(spec.branch, spec.branch),
					"  🔒" if locked else ""]
		_add_button(label, owned or locked or poor, func() -> void: ws.craft_tool(key); _rebuild())
		if poor:
			_add_deficit(tcost)
	# C4 (Этап 4.12b) — только Инженеру с открытой способностью C4.
	if InventorySystem.has_c4:
		var c4cost := {"wood": int(ws.C4_COST.wood), "steel": int(ws.C4_COST.steel)}
		var poor: bool = not _can_afford(c4cost)
		_add_button("C4 (%d дерева, %d стали) — заряд (есть: %d)" % [
				ws.C4_COST.wood, ws.C4_COST.steel, InventorySystem.c4_charges],
				poor, func() -> void: ws.craft_c4(); _rebuild())
		if poor:
			_add_deficit(c4cost)


func _can_afford(cost: Dictionary) -> bool:
	for r in cost:
		if InventorySystem.get_resource(r) < int(cost[r]):
			return false
	return true


## Красная строка-подсказка под кнопкой: чего и сколько не хватает (Этап UI-5).
func _add_deficit(cost: Dictionary) -> void:
	var parts: Array[String] = []
	for r in cost:
		var miss: int = int(cost[r]) - InventorySystem.get_resource(r)
		if miss > 0:
			parts.append("%d %s" % [miss, _res_name(r)])
	if parts.is_empty():
		return
	var l := Label.new()
	l.text = "    ↳ не хватает: " + ", ".join(parts)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", UiStyle.BAD)
	_list.add_child(l)


func _res_name(r: String) -> String:
	match r:
		"wood": return "дерева"
		"steel": return "стали"
	return r


func _add_button(text: String, disabled: bool, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.disabled = disabled
	if not disabled and cb.is_valid():
		btn.pressed.connect(cb)
	_list.add_child(btn)
