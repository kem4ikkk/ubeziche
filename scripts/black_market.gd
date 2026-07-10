extends Area3D

## Чёрный рынок (Этап 4.24). Как в оригинале (New Zombie Shelter): открывается
## каждый день в ОДНОЙ ИЗ НЕСКОЛЬКИХ точек. Рядом с ним за ДЕНЬГИ покупается
## оружие (player.weapons по возрастанию цены). Деньги тратятся только здесь —
## постройки/крафт/ремонт идут за ресурсы.
##   Игрок внутри зоны + [F] — купить следующий ствол.

@export var spawn_points: Array[Vector3] = [
	Vector3(12, 0, 0),
	Vector3(-12, 0, -8),
	Vector3(0, 0, -14),
]

var _player_inside: bool = false
var _capture_mode: bool = false
var _current_point: int = -1

@onready var prompt: Label3D = $Prompt


func _ready() -> void:
	_capture_mode = OS.get_cmdline_user_args().has("--capture")
	add_to_group("black_market")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_relocate()
	# Каждый новый день рынок переезжает в случайную точку — подключаемся
	# отложенно, когда цикл день/ночь уже в группе.
	_connect_day_cycle.call_deferred()
	_update_prompt()


func _connect_day_cycle() -> void:
	var cycle := get_tree().get_first_node_in_group("day_night_cycle")
	if is_instance_valid(cycle) and cycle.has_signal("phase_changed"):
		cycle.phase_changed.connect(_on_phase_changed)


func _on_phase_changed(is_night: bool) -> void:
	if not is_night:
		_relocate()  # наступил день — рынок открывается в новой случайной точке


## Переставить рынок в случайную из точек (Этап 4.24).
func _relocate() -> void:
	if spawn_points.is_empty():
		return
	# По возможности выбираем точку, отличную от текущей.
	var idx := randi() % spawn_points.size()
	if spawn_points.size() > 1 and idx == _current_point:
		idx = (idx + 1) % spawn_points.size()
	_current_point = idx
	global_position = spawn_points[idx]
	print("Чёрный рынок открылся в точке ", idx, " ", spawn_points[idx])


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		_update_prompt()


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = false
		_update_prompt()


func _unhandled_input(event: InputEvent) -> void:
	if _capture_mode or not _player_inside:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		buy_weapon()


## Покупка следующего оружия за деньги (Этап 4.24): логика/цены — в player.gd.
func buy_weapon() -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player) or not player.has_method("buy_weapon"):
		return false
	var index: int = player.next_unowned_weapon_index()
	if index < 0:
		print("Чёрный рынок: всё оружие уже куплено")
		return false
	var ok: bool = player.buy_weapon(index)
	_update_prompt()
	return ok


## Подсказка над прилавком: ярче, когда игрок рядом.
func _update_prompt() -> void:
	if prompt == null:
		return
	if _player_inside:
		prompt.text = "ЧЁРНЫЙ РЫНОК\n[F] купить: %s" % _weapon_offer_text()
		prompt.modulate = Color(1, 0.45, 0.45)
	else:
		prompt.text = "Чёрный рынок\n(подойдите ближе)"
		prompt.modulate = Color(0.7, 0.45, 0.45)


## Текст предложения оружия: следующий ствол + цена.
func _weapon_offer_text() -> String:
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.has_method("next_unowned_weapon_index"):
		var index: int = player.next_unowned_weapon_index()
		if index < 0:
			return "всё куплено"
		var w: Dictionary = player.weapons[index]
		return "%s (%d$)" % [w.name, player.get_weapon_price(index)]
	return "оружие"
