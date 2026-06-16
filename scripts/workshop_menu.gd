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
	# Стена за ресурсы.
	_add_button("Стена (2 дерева)", false, func() -> void: ws.craft_wall(); _rebuild())
	# Апгрейд тира за ресурсы.
	var tier: int = InventorySystem.shelter_tier
	if tier >= InventorySystem.MAX_TIER:
		_add_button("Убежище: Тир %d (максимум)" % tier, true, Callable())
	else:
		var tc: Dictionary = ws.TIER_UPGRADE_COST[tier + 1]
		_add_button("Тир %d → %d (%d дерева, %d стали)" % [tier, tier + 1, tc.wood, tc.steel],
				false, func() -> void: ws.upgrade_shelter_tier(); _rebuild())
	# Классовые инструменты (гейт по ветке навыка).
	for key in ws.TOOL_KEYS:
		var spec: Dictionary = ws.get_tool_spec(key)
		var owned: bool = InventorySystem.get(spec.flag)
		var locked: bool = InventorySystem.get_skill_level(spec.branch) < spec.req_level
		var label: String
		if owned:
			label = "%s — скрафчен ✓" % spec.title
		else:
			label = "%s (%d дерева, %d стали) — навык «%s» ур.%d%s" % [
					spec.title, spec.cost.wood, spec.cost.steel,
					BRANCH_NAME.get(spec.branch, spec.branch), spec.req_level,
					"  🔒" if locked else ""]
		_add_button(label, owned or locked, func() -> void: ws.craft_tool(key); _rebuild())
	# C4 (Этап 4.12b) — только Инженеру с открытой способностью C4.
	if InventorySystem.has_c4:
		_add_button("C4 (%d дерева, %d стали) — заряд (есть: %d)" % [
				ws.C4_COST.wood, ws.C4_COST.steel, InventorySystem.c4_charges],
				false, func() -> void: ws.craft_c4(); _rebuild())


func _add_button(text: String, disabled: bool, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.disabled = disabled
	if not disabled and cb.is_valid():
		btn.pressed.connect(cb)
	_list.add_child(btn)
