extends Node

## Состояния игры (Этап 3.7 + 4.11): победа/поражение + рестарт.
## Поражение — у игрока закончилось здоровье.
## Победа теперь оформлена как ЭВАКУАЦИЯ (Этап 4.11): пережив `victory_waves`
## волн, игрок не побеждает сразу — вызывается транспорт, появляется зона
## эвакуации, и нужно добежать до неё за `evac_time_limit` секунд. Успел —
## победа; не успел (транспорт улетел) — поражение.
## По достижении любого исхода игра ставится на паузу, HUD показывает
## экран итога, рестарт — клавишей R.

signal game_over(victory: bool)

@export var victory_waves: int = 5
@export var evac_time_limit: float = 45.0  ## секунд на эвакуацию после вызова транспорта

@export var wave_manager_path: NodePath
@export var player_path: NodePath
@export var evac_zone_path: NodePath

var is_game_over: bool = false
var evac_active: bool = false       ## идёт ли финальная фаза эвакуации
var _evac_time_left: float = 0.0

@onready var _wave_manager: Node = get_node(wave_manager_path)
@onready var _player: Node = get_node(player_path)
@onready var _evac_zone: Node = get_node_or_null(evac_zone_path)


func _ready() -> void:
	add_to_group("game_state_manager")
	process_mode = Node.PROCESS_MODE_ALWAYS

	if _wave_manager.has_signal("wave_cleared"):
		_wave_manager.wave_cleared.connect(_on_wave_cleared)

	# Поражение теперь — РАЗРУШЕНИЕ УБЕЖИЩА (Этап 5.x), а не смерть игрока: смерть
	# ведёт к возрождению (player.gd), а игру проигрываем, только если пало убежище.
	EventBus.shelter_destroyed.connect(_on_shelter_destroyed)


func _process(delta: float) -> void:
	if not evac_active or is_game_over:
		return
	# Игрок успел в зону эвакуации — транспорт забирает его, победа.
	if is_instance_valid(_evac_zone) and _evac_zone.has_method("is_player_inside") and _evac_zone.is_player_inside():
		print("Эвакуация успешна — транспорт забрал игрока!")
		_finish(true)
		return
	# Время вышло, а игрок не в зоне — транспорт улетает без него.
	_evac_time_left -= delta
	if _evac_time_left <= 0.0:
		_evac_time_left = 0.0
		print("Транспорт улетел без вас!")
		_finish(false)


func _unhandled_input(event: InputEvent) -> void:
	if not is_game_over:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		get_tree().paused = false
		get_tree().call_deferred("reload_current_scene")


func _on_wave_cleared(wave_number: int) -> void:
	if is_game_over or evac_active:
		return
	if wave_number >= victory_waves:
		_start_evacuation()


func _on_shelter_destroyed() -> void:
	if is_game_over:
		return
	print("УБЕЖИЩЕ РАЗРУШЕНО — поражение")
	_finish(false)


## Запуск финальной фазы эвакуации (Этап 4.11): вместо мгновенной победы за
## «пережито N волн» вызываем транспорт — игрок должен добежать до зоны
## эвакуации за evac_time_limit секунд, иначе транспорт улетит без него.
func _start_evacuation() -> void:
	evac_active = true
	_evac_time_left = evac_time_limit
	if is_instance_valid(_evac_zone) and _evac_zone.has_method("activate"):
		_evac_zone.activate()
	print("Пережито волн: ", victory_waves, " — вызван транспорт! Эвакуация за ", evac_time_limit, " c")
	EventBus.evacuation_started.emit()


## Сколько секунд осталось до отлёта транспорта (для HUD).
func get_evac_time_left() -> float:
	return _evac_time_left


func _finish(victory: bool) -> void:
	is_game_over = true
	evac_active = false
	get_tree().paused = true
	print("ПОБЕДА" if victory else "ПОРАЖЕНИЕ")
	game_over.emit(victory)
