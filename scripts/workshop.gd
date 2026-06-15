extends Area3D

## Мастерская / точка крафта (Этап 4.7.3; экономика пересмотрена в 4.25).
## Игрок внутри Area3D взаимодействует клавишами:
##   C — скрафтить стену из ресурсов (2 дерева → 1 стена)
##   T — апгрейд тира убежища за ресурсы (дерево + сталь)
##   M — скрафтить Молот за ресурсы (один раз; ремонт x2 HP)
## Деньги тратятся ТОЛЬКО на чёрном рынке (оружие, Этап 4.24). Постройки/крафт/
## апгрейды — за ресурсы. Боезапаса турелей больше нет (Этап 4.25).
## В Этапе 4.26 это меню переедет в полноценный UI по клавише E.

## Стоимость апгрейда убежища до тира (Этап 4.15; деньги убраны в 4.25).
## Тир 2 открывает Мортиру, Тир 3 — Гатлинг, Тир 4 — генераторы мощнее.
## Цены ≤ кэпа ресурсов (RESOURCE_CAP=40), иначе тир был бы недостижим (4.25).
const TIER_UPGRADE_COST := {
	2: {"wood": 20, "steel": 15},
	3: {"wood": 30, "steel": 25},
	4: {"wood": 40, "steel": 35},
}

## Стоимость крафта Молота (Этап 4.17; деньги убраны в 4.25).
const HAMMER_COST := {"wood": 15, "steel": 10}

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


func _unhandled_input(event: InputEvent) -> void:
	# В режиме прогона ввод не читаем (тест дёргает методы напрямую),
	# вне зоны мастерской клавиши тоже не действуют.
	if _capture_mode or not _player_inside:
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_C:
				craft_wall()
			KEY_T:
				upgrade_shelter_tier()
			KEY_M:
				craft_hammer()


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
	if InventorySystem.get_resource("wood") < cost.wood \
			or InventorySystem.get_resource("steel") < cost.steel:
		print("Мастерская: не хватает ресурсов для апгрейда до Тир ", next_tier,
				" (нужно ", cost.wood, " дерева, ", cost.steel, " стали)")
		return false
	InventorySystem.use_resource("wood", cost.wood)
	InventorySystem.use_resource("steel", cost.steel)
	InventorySystem.set_tier(next_tier)
	print("Мастерская: убежище улучшено до Тир ", next_tier, "!")
	return true


## Крафт Молота (Этап 4.17; за ресурсы — деньги убраны в 4.25): постоянный
## инструмент, делается один раз. С Молотом ремонт топором восстанавливает x2 HP.
func craft_hammer() -> bool:
	if InventorySystem.has_hammer:
		print("Мастерская: молот уже скрафчен")
		return false
	if InventorySystem.get_resource("wood") < HAMMER_COST.wood \
			or InventorySystem.get_resource("steel") < HAMMER_COST.steel:
		print("Мастерская: не хватает ресурсов для молота (нужно ",
				HAMMER_COST.wood, " дерева, ", HAMMER_COST.steel, " стали)")
		return false
	InventorySystem.use_resource("wood", HAMMER_COST.wood)
	InventorySystem.use_resource("steel", HAMMER_COST.steel)
	InventorySystem.has_hammer = true
	_update_prompt()
	print("Мастерская: скрафтили молот — ремонт теперь восстанавливает вдвое больше HP")
	return true


## Подсказка над верстаком: ярче, когда игрок рядом.
func _update_prompt() -> void:
	if prompt == null:
		return
	if _player_inside:
		prompt.text = "МАСТЕРСКАЯ\n[C] стена (2 дерева)\n[T] %s\n[M] %s" % [
				_tier_offer_text(), _hammer_offer_text()]
		prompt.modulate = Color(1, 1, 1)
	else:
		prompt.text = "Мастерская\n(подойдите ближе)"
		prompt.modulate = Color(0.7, 0.7, 0.7)


## Текст апгрейда тира для подсказки: следующий тир + цена (ресурсы).
func _tier_offer_text() -> String:
	var current: int = InventorySystem.shelter_tier
	if current >= InventorySystem.MAX_TIER:
		return "Убежище: Тир %d (максимум)" % current
	var cost: Dictionary = TIER_UPGRADE_COST[current + 1]
	return "Тир %d → Тир %d (%d дерева, %d стали)" % [
			current, current + 1, cost.wood, cost.steel]


## Текст предложения молота для подсказки (Этап 4.17).
func _hammer_offer_text() -> String:
	if InventorySystem.has_hammer:
		return "молот скрафчен (ремонт x2 HP)"
	return "молот (%d дерева, %d стали)" % [HAMMER_COST.wood, HAMMER_COST.steel]
