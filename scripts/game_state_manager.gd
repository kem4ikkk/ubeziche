extends Node

## Состояния игры (Этап 3.7): победа/поражение + рестарт.
## Победа — игрок пережил `victory_waves` волн зомби.
## Поражение — у игрока закончилось здоровье.
## По достижении любого исхода игра ставится на паузу, HUD показывает
## экран итога, рестарт — клавишей R.

signal game_over(victory: bool)

@export var victory_waves: int = 5

@export var wave_manager_path: NodePath
@export var player_path: NodePath

var is_game_over: bool = false

@onready var _wave_manager: Node = get_node(wave_manager_path)
@onready var _player: Node = get_node(player_path)


func _ready() -> void:
	add_to_group("game_state_manager")
	process_mode = Node.PROCESS_MODE_ALWAYS

	if _wave_manager.has_signal("wave_cleared"):
		_wave_manager.wave_cleared.connect(_on_wave_cleared)

	var health: HealthComponent = _player.get_node("HealthComponent")
	health.died.connect(_on_player_died)


func _unhandled_input(event: InputEvent) -> void:
	if not is_game_over:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		get_tree().paused = false
		get_tree().call_deferred("reload_current_scene")


func _on_wave_cleared(wave_number: int) -> void:
	if is_game_over:
		return
	if wave_number >= victory_waves:
		_finish(true)


func _on_player_died() -> void:
	if is_game_over:
		return
	_finish(false)


func _finish(victory: bool) -> void:
	is_game_over = true
	get_tree().paused = true
	if victory:
		print("ПОБЕДА — пережито волн: ", victory_waves)
	else:
		print("ПОРАЖЕНИЕ")
	game_over.emit(victory)
