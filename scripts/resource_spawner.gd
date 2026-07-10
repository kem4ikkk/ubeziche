extends Node3D

## Спавнер узлов добычи (правка после 4.22). Узлы дерева/стали НЕ стоят на
## фиксированных местах — они появляются в СЛУЧАЙНЫХ точках карты (кольцо ВНЕ
## периметра убежища). Каждый узел = случайный запас ударов (resource_pickup.gd:
## 5–7 HP); за удар топором выдаётся gather_level ресурса.
##
## Правка 2026-06-16 (модель спавна): исчерпанный узел НЕ заменяется мгновенно
## (1-в-1). На карте НЕ фиксированное число узлов — новые «дозревают» в случайные
## моменты времени (таймер с интервалом respawn_min..respawn_max) и только пока
## тип под лимитом (wood_max / steel_max), чтобы залежей было НЕ слишком много.
## Так число узлов плавает: убывает по мере сбора, изредка пополняется.
##
## Прочее: узлы НЕ спавнятся на стенах/постройках (физ. оверлап-чек) и НЕ на
## территории убежища (только вне периметра, радиус ≥ min_radius). Стартовое
## количество — СЛУЧАЙНОЕ (wood_min..wood_max / steel_min..steel_max).

@export var node_scene: PackedScene
# Случайное число узлов на старте (как в оригинале — залежи варьируются).
# wood_max / steel_max служат ОДНОВРЕМЕННО верхним лимитом узлов каждого типа
# (больше этого числа спавнер «дозревом» не наплодит).
@export var wood_min: int = 3
@export var wood_max: int = 5
@export var steel_min: int = 2
@export var steel_max: int = 4
# Интервал случайного «дозрева» нового узла (сек). Большой — чтобы залежи
# пополнялись изредка, а не сразу после сбора.
@export var respawn_min: float = 15.0
@export var respawn_max: float = 30.0
# Кольцо спавна ВНЕ периметра убежища (стены периметра на ~±8): ближе нельзя,
# чтобы ресурсы не оказались на территории базы.
@export var min_radius: float = 11.0
@export var max_radius: float = 22.0
@export var spawn_y: float = 0.9         # центр узла; короб (выс. 1.8) стоит на земле
@export var min_separation: float = 3.0  # минимальное расстояние между узлами
@export var clearance: float = 0.9       # радиус проверки «свободно ли место»

var _respawn_timer: Timer

# Маска препятствий для оверлап-чека: слой 1 — периметр убежища, стены и прочие
# постройки игрока (StaticBody). Земля (WorldBoundary) сферой над полом не задевается.
const OBSTACLE_MASK := 1


func _ready() -> void:
	add_to_group("resource_spawner")
	if node_scene == null:
		push_warning("ResourceSpawner: не задан node_scene")
		return
	# Ждём физический кадр — иначе direct_space_state ещё не готов для оверлап-чека.
	await get_tree().physics_frame
	for i in randi_range(wood_min, wood_max):
		_spawn("wood")
	for i in randi_range(steel_min, steel_max):
		_spawn("steel")

	# Таймер случайного «дозрева» новых узлов со временем (а не 1-в-1 после сбора).
	_respawn_timer = Timer.new()
	_respawn_timer.one_shot = true
	_respawn_timer.timeout.connect(_on_respawn_tick)
	add_child(_respawn_timer)
	_arm_respawn_timer()


## Поставить новый узел добычи нужного типа в случайной свободной точке.
func _spawn(type: String) -> void:
	if node_scene == null:
		return
	var node := node_scene.instantiate()
	node.resource_type = type
	node.harvestable = true               # запас/слой/группа выставит сам узел в _ready
	node.depleted.connect(_on_node_depleted)
	add_child(node)
	(node as Node3D).global_position = _random_pos()


## Узел исчерпан — просто убираем его. НОВЫЙ узел НЕ ставим сразу (правка
## 2026-06-16): замена приходит позже, в случайный момент, через _on_respawn_tick.
## Так число узлов на карте не фиксировано и не пополняется мгновенно после сбора.
func _on_node_depleted(node: Node) -> void:
	node.queue_free()


## Перезапустить таймер «дозрева» со случайным интервалом.
func _arm_respawn_timer() -> void:
	if is_instance_valid(_respawn_timer):
		# «Искатель приключений» (Этап 4.41): залежи дозревают быстрее (−20%/ур).
		var mult := maxf(0.3, 1.0 - 0.2 * _adventurer_level())
		_respawn_timer.start(randf_range(respawn_min, respawn_max) * mult)


## Уровень навыка «Искатель приключений» — ускоряет дозрев и поднимает лимит узлов.
func _adventurer_level() -> int:
	return InventorySystem.get_skill_level("adventurer")


## Тик «дозрева»: изредка добавляет ОДИН новый узел того типа, что под лимитом.
## Если оба типа на лимите — ничего не делаем (залежей не больше cap). Затем
## перезаряжаем таймер на новый случайный интервал.
func _on_respawn_tick() -> void:
	var candidates: Array[String] = []
	var adv := _adventurer_level()   # «Искатель приключений» поднимает лимит узлов
	if _count_of("wood") < wood_max + adv:
		candidates.append("wood")
	if _count_of("steel") < steel_max + adv:
		candidates.append("steel")
	if not candidates.is_empty():
		_spawn(candidates[randi() % candidates.size()])
	_arm_respawn_timer()


## Сколько живых узлов данного типа сейчас на карте.
func _count_of(type: String) -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("resource_node"):
		if is_instance_valid(node) and node.resource_type == type:
			n += 1
	return n


## Случайная СВОБОДНАЯ точка в кольце [min_radius, max_radius] вокруг центра:
## не на стене/постройке (физ. оверлап) и не ближе min_separation к другим узлам.
## Несколько попыток — иначе берём последнюю (лучше поставить, чем не поставить).
func _random_pos() -> Vector3:
	var p := Vector3.ZERO
	for attempt in 40:
		var ang := randf() * TAU
		var rad := randf_range(min_radius, max_radius)
		p = Vector3(cos(ang) * rad, spawn_y, sin(ang) * rad)
		if _too_close_to_nodes(p):
			continue
		if _point_blocked(p):
			continue
		return p
	return p


## Есть ли рядом другой узел добычи (чтобы не лепить вплотную).
func _too_close_to_nodes(p: Vector3) -> bool:
	for n in get_tree().get_nodes_in_group("resource_node"):
		if is_instance_valid(n) and n is Node3D \
				and (n as Node3D).global_position.distance_to(p) < min_separation:
			return true
	return false


## Занята ли точка стеной/постройкой/периметром (физический оверлап сферой).
func _point_blocked(p: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var shape := SphereShape3D.new()
	shape.radius = clearance
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), p)
	params.collision_mask = OBSTACLE_MASK
	params.collide_with_bodies = true
	params.collide_with_areas = false
	return not space.intersect_shape(params, 1).is_empty()
