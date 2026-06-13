extends Node3D
## Менеджер волн: спавнит зомби волнами с нарастающей сложностью.
## Волна запускается извне (см. `start_wave`) — в игре её вызывает
## `DayNightCycle` с наступлением ночи (Этап 3.6).
##
## Точки спавна — дочерние узлы Marker3D под узлом "SpawnPoints".

signal wave_cleared(wave_number: int)

@export var zombie_scene: PackedScene
@export var first_wave_count: int = 3        # зомби в 1-й волне
@export var count_increment: int = 2         # +N зомби каждую следующую волну
@export var spawn_interval: float = 0.5      # пауза между появлением зомби в волне

# Танк (Этап 4.4): больше HP, медленнее, сильнее бьёт по постройкам.
@export var tank_zombie_scene: PackedScene
@export var tank_starting_wave: int = 2      # с какой волны появляются танки
@export var tanks_per_wave: int = 1          # сколько танков добавляется к волне

var current_wave: int = 0
var _zombies_alive: int = 0
var _spawning: bool = false

@onready var _spawn_points: Array[Node] = $SpawnPoints.get_children()


## Запустить следующую волну. Если предыдущая ещё не зачищена — ничего не делает.
func start_wave() -> void:
	if _spawning or _zombies_alive > 0:
		print("Волна уже идёт — пропускаем запуск новой")
		return
	current_wave += 1
	var count := first_wave_count + (current_wave - 1) * count_increment
	var tank_count := 0
	if tank_zombie_scene != null and current_wave >= tank_starting_wave:
		tank_count = tanks_per_wave
	print("Волна ", current_wave, " — зомби: ", count, ", танков: ", tank_count)
	_spawning = true
	for i in count:
		_spawn_zombie(zombie_scene)
		await get_tree().create_timer(spawn_interval).timeout
	for i in tank_count:
		_spawn_zombie(tank_zombie_scene)
		await get_tree().create_timer(spawn_interval).timeout
	_spawning = false
	# Если игрок успел перебить всех ещё во время спавна.
	if _zombies_alive <= 0:
		_on_wave_cleared()


func _spawn_zombie(scene: PackedScene) -> void:
	if scene == null or _spawn_points.is_empty():
		return
	var zombie := scene.instantiate()
	get_parent().add_child(zombie)
	var point := _spawn_points[randi() % _spawn_points.size()] as Node3D
	(zombie as Node3D).global_position = point.global_position
	_zombies_alive += 1
	# О смерти зомби узнаём по выходу из дерева (queue_free при гибели).
	zombie.tree_exited.connect(_on_zombie_removed)


func _on_zombie_removed() -> void:
	if not is_inside_tree():
		return  # сцена выгружается — игнорируем
	_zombies_alive -= 1
	if not _spawning and _zombies_alive <= 0:
		_on_wave_cleared()


func _on_wave_cleared() -> void:
	print("Волна ", current_wave, " зачищена! Следующая начнётся ночью")
	wave_cleared.emit(current_wave)
