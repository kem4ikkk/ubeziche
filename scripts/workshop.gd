extends Area3D

## Мастерская / точка крафта (Этап 4.7.3).
## Игрок должен стоять рядом (внутри Area3D), чтобы взаимодействовать:
##   C — скрафтить стену из ресурсов (2 дерева → 1 стена)   [ресурсная экономика]
##   G — купить стену за деньги                              [денежная экономика]
##   H — купить лечение за деньги (+HP)                      [денежная экономика]
##   K — купить боезапас турелей (расходник)                 [денежная экономика]
## Оружие теперь покупается НЕ здесь, а на чёрном рынке за деньги (Этап 4.24,
## scripts/black_market.gd).
##
## Так замыкаются обе ветки экономики (Этап 4.7.2): дерево/сталь тратятся
## на крафт, а деньги (капают за убийство зомби) — на покупки в мастерской.
## Оружие продаётся по порядку (по возрастанию цены): двойные пистолеты →
## дробовик → автомат → снайперка; список и цены живут в player.gd.

@export var buy_wall_cost: int = 25     # цена стены за деньги
@export var heal_cost: int = 30         # цена одной покупки лечения
@export var heal_amount: float = 25.0   # сколько HP даёт покупка лечения
@export var turret_ammo_cost: int = 20  # цена пачки боезапаса турелей
@export var turret_ammo_amount: int = 10  # сколько боезапаса даёт покупка

## Стоимость апгрейда убежища до указанного тира (Этап 4.15).
## Тир 2 открывает Мортиру, Тир 3 — Гатлинг, Тир 4 — генераторы производят
## электричество вдвое быстрее (generator.gd).
const TIER_UPGRADE_COST := {
	2: {"wood": 30, "steel": 20, "money": 80},
	3: {"wood": 50, "steel": 40, "money": 150},
	4: {"wood": 80, "steel": 60, "money": 250},
}

## Стоимость крафта Молота (Этап 4.17, инструмент крафтится один раз).
const HAMMER_COST := {"wood": 15, "steel": 10, "money": 50}

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
			KEY_G:
				buy_wall()
			KEY_H:
				buy_heal()
			KEY_K:
				buy_turret_ammo()
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


## Покупка стены за деньги — кладём 1 «wall» в инвентарь под постройку.
func buy_wall() -> bool:
	if InventorySystem.spend_money(buy_wall_cost):
		InventorySystem.add_resource("wall", 1)
		print("Мастерская: куплена стена за ", buy_wall_cost, "$")
		return true
	print("Мастерская: не хватает денег на стену (нужно ", buy_wall_cost, "$)")
	return false


## Покупка лечения за деньги — восстанавливает игроку heal_amount HP.
func buy_heal() -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player) or not player.has_method("heal"):
		return false
	if player.has_method("get_health") and player.get_health() <= 0.0:
		return false  # мёртвого не лечим — деньги не тратим
	if player.has_method("is_full_health") and player.is_full_health():
		print("Мастерская: у игрока полное здоровье — лечение не нужно")
		return false
	if InventorySystem.spend_money(heal_cost):
		player.heal(heal_amount)
		print("Мастерская: куплено лечение +", heal_amount, " HP за ", heal_cost, "$")
		return true
	print("Мастерская: не хватает денег на лечение (нужно ", heal_cost, "$)")
	return false


## Покупка боезапаса турелей (расходник для построенных турелей).
func buy_turret_ammo() -> bool:
	if InventorySystem.spend_money(turret_ammo_cost):
		InventorySystem.add_resource("turret_ammo", turret_ammo_amount)
		print("Мастерская: куплен боезапас турелей +", turret_ammo_amount, " за ", turret_ammo_cost, "$")
		return true
	print("Мастерская: не хватает денег на боезапас турелей (нужно ", turret_ammo_cost, "$)")
	return false


## Апгрейд тира убежища (Этап 4.15): открывает доступ к более продвинутым
## турелям (Мортира — Тир 2, Гатлинг — Тир 3) и улучшает генератор (Тир 4).
func upgrade_shelter_tier() -> bool:
	var current: int = InventorySystem.shelter_tier
	if current >= InventorySystem.MAX_TIER:
		print("Мастерская: убежище уже максимального тира (", current, ")")
		return false
	var next_tier: int = current + 1
	var cost: Dictionary = TIER_UPGRADE_COST[next_tier]
	if InventorySystem.get_resource("wood") < cost.wood \
			or InventorySystem.get_resource("steel") < cost.steel \
			or InventorySystem.get_money() < cost.money:
		print("Мастерская: не хватает ресурсов для апгрейда до Тир ", next_tier,
				" (нужно ", cost.wood, " дерева, ", cost.steel, " стали, ", cost.money, "$)")
		return false
	InventorySystem.use_resource("wood", cost.wood)
	InventorySystem.use_resource("steel", cost.steel)
	InventorySystem.spend_money(cost.money)
	InventorySystem.set_tier(next_tier)
	print("Мастерская: убежище улучшено до Тир ", next_tier, "!")
	return true


## Крафт Молота (Этап 4.17): постоянный инструмент, делается один раз.
## Пока есть — ремонт построек (F) восстанавливает вдвое больше HP за удар.
func craft_hammer() -> bool:
	if InventorySystem.has_hammer:
		print("Мастерская: молот уже скрафчен")
		return false
	if InventorySystem.get_resource("wood") < HAMMER_COST.wood \
			or InventorySystem.get_resource("steel") < HAMMER_COST.steel \
			or InventorySystem.get_money() < HAMMER_COST.money:
		print("Мастерская: не хватает ресурсов для молота (нужно ",
				HAMMER_COST.wood, " дерева, ", HAMMER_COST.steel, " стали, ", HAMMER_COST.money, "$)")
		return false
	InventorySystem.use_resource("wood", HAMMER_COST.wood)
	InventorySystem.use_resource("steel", HAMMER_COST.steel)
	InventorySystem.spend_money(HAMMER_COST.money)
	InventorySystem.has_hammer = true
	_update_prompt()
	print("Мастерская: скрафтили молот — ремонт теперь восстанавливает вдвое больше HP")
	return true


## Подсказка над верстаком: ярче, когда игрок рядом.
func _update_prompt() -> void:
	if prompt == null:
		return
	if _player_inside:
		prompt.text = "МАСТЕРСКАЯ\n[C] стена (2 дерева)\n[G] стена (%d$)\n[H] лечение (%d$)\n[K] боезапас турелей x%d (%d$)\n[T] %s\n[M] %s" % [
				buy_wall_cost, heal_cost, turret_ammo_amount, turret_ammo_cost, _tier_offer_text(), _hammer_offer_text()]
		prompt.modulate = Color(1, 1, 1)
	else:
		prompt.text = "Мастерская\n(подойдите ближе)"
		prompt.modulate = Color(0.7, 0.7, 0.7)


## Текст апгрейда тира убежища для подсказки: следующий тир + цена.
func _tier_offer_text() -> String:
	var current: int = InventorySystem.shelter_tier
	if current >= InventorySystem.MAX_TIER:
		return "Убежище: Тир %d (максимум)" % current
	var cost: Dictionary = TIER_UPGRADE_COST[current + 1]
	return "Тир %d → Тир %d (%d дерева, %d стали, %d$)" % [
			current, current + 1, cost.wood, cost.steel, cost.money]


## Текст предложения молота для подсказки (Этап 4.17).
func _hammer_offer_text() -> String:
	if InventorySystem.has_hammer:
		return "молот скрафчен (ремонт x2 HP)"
	return "молот (%d дерева, %d стали, %d$)" % [HAMMER_COST.wood, HAMMER_COST.steel, HAMMER_COST.money]
