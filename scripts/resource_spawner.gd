extends Node3D

## Спавнер узлов добычи (правка после 4.22). Узлы дерева/стали НЕ стоят на
## фиксированных местах и НЕ восстанавливаются «там же» — они появляются в
## СЛУЧАЙНЫХ точках карты (кольцо ВНЕ периметра убежища). Каждый узел = случайный
## запас ударов (resource_pickup.gd: 5–7 HP); за удар топором выдаётся gather_level
## ресурса. Узел исчерпан (сигнал depleted) → исчезает, спавнер ставит новый в
## другой случайной точке. Так держим на карте постоянное число узлов.
##
## Правки 2026-06-16: узлы НЕ спавнятся на стенах/постройках (физ. оверлап-чек) и
## НЕ на территории убежища (только вне периметра, радиус ≥ min_radius). Стартовое
## количество узлов — СЛУЧАЙНОЕ (в диапазонах wood_min..wood_max / steel_min..steel_max).

@export var node_scene: PackedScene
# Случайное число узлов на старте (как в оригинале — залежи варьируются).
@export var wood_min: int = 3
@export var wood_max: int = 5
@export var steel_min: int = 2
@export var steel_max: int = 4
# Кольцо спавна ВНЕ периметра убежища (стены периметра на ~±8): ближе нельзя,
# чтобы ресурсы не оказались на территории базы.
@export var min_radius: float = 11.0
@export var max_radius: float = 22.0
@export var spawn_y: float = 0.9         # центр узла; короб (выс. 1.8) стоит на земле
@export var min_separation: float = 3.0  # минимальное расстояние между узлами
@export var clearance: float = 0.9       # радиус проверки «свободно ли место»

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


## Узел исчерпан — убираем его и сразу ставим новый того же типа в другом месте
## (без «регена на том же месте»: точка всегда новая).
func _on_node_depleted(node: Node) -> void:
	var type: String = node.resource_type
	node.queue_free()
	_spawn(type)


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
