extends Area3D

## Мастерская / точка крафта (Этап 4.7.3; экономика — 4.25, UI-меню — 4.27).
## Игрок внутри Area3D + клавиша E открывает UI-меню (workshop_menu.gd), где за
## ресурсы: стена, апгрейд тира, классовые инструменты (нож/улучшенный топор/
## молот — гейт по ветке навыка). Деньги тратятся ТОЛЬКО на чёрном рынке (4.24).

## Стоимость апгрейда убежища до тира (Этап 4.15; деньги убраны в 4.25).
## Тир 2 открывает Мортиру, Тир 3 — Гатлинг, Тир 4 — генераторы мощнее.
## Цены ≤ кэпа ресурсов (RESOURCE_CAP=40), иначе тир был бы недостижим (4.25).
const TIER_UPGRADE_COST := {
	2: {"wood": 20, "steel": 15},
	3: {"wood": 30, "steel": 25},
	4: {"wood": 40, "steel": 35},
}

## Стоимость крафта классовых инструментов (Этап 4.27). Гейт по уровню ветки
## навыка: Молот — Инженер, Нож — Бой, Улучшенный топор — Добыча.
const HAMMER_COST := {"wood": 15, "steel": 10}
const KNIFE_COST := {"wood": 10, "steel": 10}
const IMPROVED_AXE_COST := {"wood": 15, "steel": 5}

var _player_inside: bool = false
var _capture_mode: bool = false

@onready var prompt: Label3D = $Prompt


func _ready() -> void:
	_capture_mode = OS.get_cmdline_user_args().has("--capture")
	add_to_group("workshop")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_update_prompt()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		_update_prompt()


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = false
		_update_prompt()


## E (рядом с мастерской) открывает/закрывает UI-меню крафта. Паузы в игре нет,
## поэтому ввод доходит штатно (в прогоне ввод выключен — тест дёргает методы).
func _unhandled_input(event: InputEvent) -> void:
	if _capture_mode or not _player_inside:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		var menu := get_tree().get_first_node_in_group("workshop_menu")
		if is_instance_valid(menu) and menu.has_method("toggle"):
			menu.toggle()


## Крафт стены из ресурсов (дерево). Возвращает true при успехе.
func craft_wall() -> bool:
	if CraftSystem.craft("wall"):
		print("Мастерская: скрафтили стену (2 дерева → 1 стена)")
		return true
	print("Мастерская: не хватает ресурсов для крафта стены")
	return false


## Апгрейд тира убежища (Этап 4.15; за ресурсы — деньги убраны в 4.25).
func upgrade_shelter_tier() -> bool:
	var current: int = InventorySystem.shelter_tier
	if current >= InventorySystem.MAX_TIER:
		print("Мастерская: убежище уже максимального тира (", current, ")")
		return false
	var next_tier: int = current + 1
	var cost: Dictionary = TIER_UPGRADE_COST[next_tier]
	if InventorySystem.get_total_resource("wood") < cost.wood \
			or InventorySystem.get_total_resource("steel") < cost.steel:
		print("Мастерская: не хватает ресурсов для апгрейда до Тир ", next_tier,
				" (нужно ", cost.wood, " дерева, ", cost.steel, " стали)")
		return false
	InventorySystem.use_resource("wood", cost.wood)
	InventorySystem.use_resource("steel", cost.steel)
	InventorySystem.set_tier(next_tier)
	print("Мастерская: убежище улучшено до Тир ", next_tier, "!")
	return true


## Ключи классовых инструментов для меню (Этап 4.27).
const TOOL_KEYS := ["knife", "improved_axe", "hammer"]

## C4 (Этап 4.12b): крафт заряда за ресурсы. Доступен только Инженеру с открытой
## способностью C4 (InventorySystem.has_c4). Каждый крафт даёт один заряд.
const C4_COST := {"wood": 10, "steel": 15}


## Крафт заряда C4 (Инженер). Возвращает true при успехе.
func craft_c4() -> bool:
	if not InventorySystem.has_c4:
		print("Мастерская: C4 недоступен (нужен класс Инженер и открытая способность C4)")
		return false
	if InventorySystem.get_total_resource("wood") < C4_COST.wood \
			or InventorySystem.get_total_resource("steel") < C4_COST.steel:
		print("Мастерская: не хватает ресурсов для C4 (нужно ",
				C4_COST.wood, " дерева, ", C4_COST.steel, " стали)")
		return false
	InventorySystem.use_resource("wood", C4_COST.wood)
	InventorySystem.use_resource("steel", C4_COST.steel)
	InventorySystem.c4_charges += 1
	print("Мастерская: скрафтили C4 (зарядов: ", InventorySystem.c4_charges, ")")
	return true


## Крафт Молота (Инженер): ремонт x2 HP + скорость атаки как у ножа.
func craft_hammer() -> bool:
	return _craft_tool("hammer")


## Крафт Ножа (Бой): +урон топора, выше скорость атаки.
func craft_knife() -> bool:
	return _craft_tool("knife")


## Крафт Улучшенного топора (Добыча): самая высокая скорость атаки.
func craft_improved_axe() -> bool:
	return _craft_tool("improved_axe")


## Крафт инструмента по ключу — для меню мастерской (Этап 4.27).
func craft_tool(tool: String) -> bool:
	return _craft_tool(tool)


## Публичное описание инструмента (для UI-меню).
func get_tool_spec(tool: String) -> Dictionary:
	return _tool_spec(tool)


## Общий крафт классового инструмента: проверка «уже есть», уровня ветки навыка
## и ресурсов; затем списание и выставление флага в InventorySystem (Этап 4.27).
func _craft_tool(tool: String) -> bool:
	var spec := _tool_spec(tool)
	if InventorySystem.get(spec.flag):
		print("Мастерская: «", spec.title, "» уже скрафчен")
		return false
	if InventorySystem.player_class != spec.branch:
		print("Мастерская: «", spec.title, "» требует мастерство ветки «", spec.branch, "»")
		return false
	var cost: Dictionary = spec.cost
	if InventorySystem.get_total_resource("wood") < cost.wood \
			or InventorySystem.get_total_resource("steel") < cost.steel:
		print("Мастерская: не хватает ресурсов для «", spec.title, "» (нужно ",
				cost.wood, " дерева, ", cost.steel, " стали)")
		return false
	InventorySystem.use_resource("wood", cost.wood)
	InventorySystem.use_resource("steel", cost.steel)
	InventorySystem.set(spec.flag, true)
	print("Мастерская: скрафтили «", spec.title, "»")
	return true


## Описание классового инструмента: флаг, ветка навыка, требуемый уровень, цена.
func _tool_spec(tool: String) -> Dictionary:
	match tool:
		"knife":
			return {"flag": "has_knife", "branch": "combat", "req_level": 1,
					"cost": KNIFE_COST, "title": "Мачете"}
		"improved_axe":
			return {"flag": "has_improved_axe", "branch": "gather", "req_level": 1,
					"cost": IMPROVED_AXE_COST, "title": "Лом"}
		_:
			return {"flag": "has_hammer", "branch": "engineer", "req_level": 1,
					"cost": HAMMER_COST, "title": "Молот"}


## Подсказка над верстаком: ярче, когда игрок рядом.
func _update_prompt() -> void:
	if prompt == null:
		return
	if _player_inside:
		prompt.text = "МАСТЕРСКАЯ\n[E] открыть меню крафта"
		prompt.modulate = Color(1, 1, 1)
	else:
		prompt.text = "Мастерская\n(подойдите ближе)"
		prompt.modulate = Color(0.7, 0.7, 0.7)
