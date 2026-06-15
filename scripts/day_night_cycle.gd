extends Node

## Цикл день/ночь (Этап 3.6).
## Чередует фазы "день" и "ночь": плавно меняет освещение и запускает
## волну зомби с наступлением ночи.

signal phase_changed(is_night: bool)

@export var day_duration: float = 20.0
@export var night_duration: float = 15.0
@export var transition_duration: float = 2.0

@export var directional_light_path: NodePath
@export var world_environment_path: NodePath
@export var wave_manager_path: NodePath

const DAY_LIGHT_ENERGY := 1.0
const NIGHT_LIGHT_ENERGY := 0.1
const DAY_LIGHT_COLOR := Color(1.0, 1.0, 1.0)
const NIGHT_LIGHT_COLOR := Color(0.4, 0.45, 0.7)
const DAY_AMBIENT_COLOR := Color(0.6, 0.7, 0.85)
const NIGHT_AMBIENT_COLOR := Color(0.05, 0.05, 0.15)
const DAY_AMBIENT_ENERGY := 1.0
const NIGHT_AMBIENT_ENERGY := 0.2

var is_night: bool = false

var _phase_time: float = 0.0
var _transition_t: float = 1.0  # 0..1 — прогресс перехода освещения

@onready var _light: DirectionalLight3D = get_node(directional_light_path)
@onready var _env: Environment = (get_node(world_environment_path) as WorldEnvironment).environment
@onready var _wave_manager: Node = get_node(wave_manager_path)


func _ready() -> void:
	add_to_group("day_night_cycle")
	_apply_phase(false, true)


func _process(delta: float) -> void:
	_phase_time += delta

	if _transition_t < 1.0:
		_transition_t = minf(_transition_t + delta / transition_duration, 1.0)
		_update_lighting()

	var duration := night_duration if is_night else day_duration
	if _phase_time >= duration:
		_phase_time = 0.0
		_apply_phase(not is_night, false)


## Сколько секунд осталось до конца текущей фазы.
func get_phase_time_left() -> float:
	var duration := night_duration if is_night else day_duration
	return duration - _phase_time


func _apply_phase(night: bool, instant: bool) -> void:
	is_night = night
	_transition_t = 1.0 if instant else 0.0
	if instant:
		_update_lighting()
	phase_changed.emit(is_night)

	if is_night:
		print("Наступила ночь — волна зомби!")
		if _wave_manager.has_method("start_wave"):
			_wave_manager.start_wave()
	else:
		print("Наступил день")
		# Переход ночь→день (не стартовая установка) = пережита ночь (Этап 4.23):
		# начисляем очко навыка через шину событий.
		if not instant:
			EventBus.night_survived.emit()


func _update_lighting() -> void:
	var t := _transition_t
	# Интерполируем от значений предыдущей фазы к значениям новой (is_night) фазы.
	var from_light_energy := DAY_LIGHT_ENERGY if is_night else NIGHT_LIGHT_ENERGY
	var to_light_energy := NIGHT_LIGHT_ENERGY if is_night else DAY_LIGHT_ENERGY
	var from_light_color := DAY_LIGHT_COLOR if is_night else NIGHT_LIGHT_COLOR
	var to_light_color := NIGHT_LIGHT_COLOR if is_night else DAY_LIGHT_COLOR
	var from_ambient_color := DAY_AMBIENT_COLOR if is_night else NIGHT_AMBIENT_COLOR
	var to_ambient_color := NIGHT_AMBIENT_COLOR if is_night else DAY_AMBIENT_COLOR
	var from_ambient_energy := DAY_AMBIENT_ENERGY if is_night else NIGHT_AMBIENT_ENERGY
	var to_ambient_energy := NIGHT_AMBIENT_ENERGY if is_night else DAY_AMBIENT_ENERGY

	_light.light_energy = lerpf(from_light_energy, to_light_energy, t)
	_light.light_color = from_light_color.lerp(to_light_color, t)
	_env.ambient_light_color = from_ambient_color.lerp(to_ambient_color, t)
	_env.ambient_light_energy = lerpf(from_ambient_energy, to_ambient_energy, t)
