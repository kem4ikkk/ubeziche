extends Area3D

## Мастерская / точка крафта (Этап 4.7.3).
## Игрок должен стоять рядом (внутри Area3D), чтобы взаимодействовать:
##   C — скрафтить стену из ресурсов (2 дерева → 1 стена)   [ресурсная экономика]
##   G — купить стену за деньги                              [денежная экономика]
##   H — купить лечение за деньги (+HP)                      [денежная экономика]
##   J — купить следующее оружие из арсенала                 [денежная экономика]
##   K — купить боезапас турелей (расходник)                 [денежная экономика]
##
## Так замыкаются обе ветки экономики (Этап 4.7.2): дерево/камень тратятся
## на крафт, а деньги (капают за убийство зомби) — на покупки в мастерской.
## Оружие продаётся по порядку (по возрастанию цены): двойные пистолеты →
## дробовик → автомат → снайперка; список и цены живут в player.gd.

@export var buy_wall_cost: int = 25     # цена стены за деньги
@export var heal_cost: int = 30         # цена одной покупки лечения
@export var heal_amount: float = 25.0   # сколько HP даёт покупка лечения
@export var turret_ammo_cost: int = 20  # цена пачки боезапаса турелей
@export var turret_ammo_amount: int = 10  # сколько боезапаса даёт покупка
@export var fuel_cost: int = 15         # цена пачки топлива для генератора
@export var fuel_amount: int = 10       # сколько топлива даёт покупка

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
			KEY_J:
				buy_weapon()
			KEY_K:
				buy_turret_ammo()
			KEY_L:
				buy_fuel()


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


## Покупка топлива для генератора (Этап 4.14) — без топлива турели простаивают.
func buy_fuel() -> bool:
	if InventorySystem.spend_money(fuel_cost):
		InventorySystem.add_resource("fuel", fuel_amount)
		print("Мастерская: куплено топливо +", fuel_amount, " за ", fuel_cost, "$")
		return true
	print("Мастерская: не хватает денег на топливо (нужно ", fuel_cost, "$)")
	return false


## Покупка следующего оружия из арсенала — цену и владение считает игрок.
func buy_weapon() -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player) or not player.has_method("buy_weapon"):
		return false
	var index: int = player.next_unowned_weapon_index()
	if index < 0:
		print("Мастерская: всё оружие уже куплено")
		return false
	return player.buy_weapon(index)


## Подсказка над верстаком: ярче, когда игрок рядом.
func _update_prompt() -> void:
	if prompt == null:
		return
	if _player_inside:
		prompt.text = "МАСТЕРСКАЯ\n[C] стена (2 дерева)\n[G] стена (%d$)\n[H] лечение (%d$)\n[J] %s\n[K] боезапас турелей x%d (%d$)\n[L] топливо x%d (%d$)" % [
				buy_wall_cost, heal_cost, _weapon_offer_text(), turret_ammo_amount, turret_ammo_cost, fuel_amount, fuel_cost]
		prompt.modulate = Color(1, 1, 1)
	else:
		prompt.text = "Мастерская\n(подойдите ближе)"
		prompt.modulate = Color(0.7, 0.7, 0.7)


## Текст предложения оружия для подсказки: следующий ствол + цена.
func _weapon_offer_text() -> String:
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.has_method("next_unowned_weapon_index"):
		var index: int = player.next_unowned_weapon_index()
		if index < 0:
			return "всё куплено"
		var w: Dictionary = player.weapons[index]
		return "%s (%d$)" % [w.name, int(w.get("price", 0))]
	return "оружие"
