extends Area3D

## Чёрный рынок (Этап 4.24 → 4.44). Открывается каждый день в одной из точек.
## Появляется только при навыке «Мастер оружия (нач.)» ≥ 1. Рядом с прилавком
## [F] открывает CS-меню покупки (market_menu.gd): категории пистолеты/основное,
## покупка заменяет ствол в слоте. Деньги тратятся только здесь.

@export var spawn_points: Array[Vector3] = [
	Vector3(12, 0, 0),
	Vector3(-12, 0, -8),
	Vector3(0, 0, -14),
]

var _player_inside: bool = false
var _capture_mode: bool = false
var _current_point: int = -1
var _unlocked: bool = false

@onready var prompt: Label3D = $Prompt


func _ready() -> void:
	_capture_mode = OS.get_cmdline_user_args().has("--capture")
	add_to_group("black_market")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_relocate()
	_connect_day_cycle.call_deferred()
	InventorySystem.skills_changed.connect(_refresh_unlock)
	# Игрок может ещё не быть в группе в момент _ready — обновим на следующем кадре.
	_refresh_unlock.call_deferred()


func _connect_day_cycle() -> void:
	var cycle := get_tree().get_first_node_in_group("day_night_cycle")
	if is_instance_valid(cycle) and cycle.has_signal("phase_changed"):
		cycle.phase_changed.connect(_on_phase_changed)


func _on_phase_changed(is_night: bool) -> void:
	if not is_night:
		_relocate()
		_refresh_unlock()


## Переставить рынок в случайную из точек (Этап 4.24).
func _relocate() -> void:
	if spawn_points.is_empty():
		return
	var idx := randi() % spawn_points.size()
	if spawn_points.size() > 1 and idx == _current_point:
		idx = (idx + 1) % spawn_points.size()
	_current_point = idx
	global_position = spawn_points[idx]
	print("Чёрный рынок открылся в точке ", idx, " ", spawn_points[idx])


## Рынок виден только при weapon_basic ≥ 1 (Этап 4.44).
func _refresh_unlock() -> void:
	var p := get_tree().get_first_node_in_group("player")
	_unlocked = is_instance_valid(p) and p.has_method("can_see_black_market") \
			and p.can_see_black_market()
	visible = _unlocked
	monitoring = _unlocked
	if not _unlocked:
		_player_inside = false
		var menu := get_tree().get_first_node_in_group("market_menu")
		if is_instance_valid(menu) and menu.has_method("close"):
			menu.close()
	_update_prompt()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		_update_prompt()


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = false
		_update_prompt()
		var menu := get_tree().get_first_node_in_group("market_menu")
		if is_instance_valid(menu) and menu.has_method("close"):
			menu.close()


func _unhandled_input(event: InputEvent) -> void:
	if _capture_mode or not _unlocked or not _player_inside:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		var menu := get_tree().get_first_node_in_group("market_menu")
		if is_instance_valid(menu) and menu.has_method("toggle"):
			menu.toggle()
			get_viewport().set_input_as_handled()


## Совместимость с тестами: купить следующий доступный ствол (без UI).
func buy_weapon() -> bool:
	if not _unlocked:
		print("Чёрный рынок: закрыт (нужен навык «Мастер оружия (нач.)»)")
		return false
	var player := get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player) or not player.has_method("buy_weapon"):
		return false
	var index: int = player.next_unowned_weapon_index()
	if index < 0:
		print("Чёрный рынок: нечего покупать (всё доступное уже в слотах или закрыто навыком)")
		return false
	var ok: bool = player.buy_weapon(index)
	_update_prompt()
	return ok


func _update_prompt() -> void:
	if prompt == null:
		return
	prompt.visible = _unlocked
	if not _unlocked:
		return
	if _player_inside:
		prompt.text = "ЧЁРНЫЙ РЫНОК\n[F] меню покупки"
		prompt.modulate = Color(1, 0.45, 0.45)
	else:
		prompt.text = "Чёрный рынок\n(подойдите ближе)"
		prompt.modulate = Color(0.7, 0.45, 0.45)
