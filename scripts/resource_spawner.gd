extends Node3D

## Спавнер узлов добычи (правка после 4.22). Узлы дерева/стали НЕ стоят на
## фиксированных местах и НЕ восстанавливаются «там же» — они появляются в
## СЛУЧАЙНЫХ точках карты (кольцо вокруг базы). Каждый узел = случайный запас
## ударов (resource_pickup.gd: 5–7 HP); за удар топором выдаётся gather_level
## ресурса. Узел исчерпан (сигнал depleted) → исчезает, спавнер ставит новый
## в другой случайной точке. Так держим на карте постоянное число узлов.

@export var node_scene: PackedScene
@export var wood_count: int = 3          # сколько узлов дерева держим на карте
@export var steel_count: int = 3         # сколько узлов стали держим на карте
@export var min_radius: float = 6.0      # ближе к центру не спавним (там база)
@export var max_radius: float = 14.0     # дальше к стенам не спавним
@export var spawn_y: float = 0.9         # центр узла; короб (выс. 1.8) стоит на земле
@export var min_separation: float = 3.0  # минимальное расстояние между узлами


func _ready() -> void:
	add_to_group("resource_spawner")
	if node_scene == null:
		push_warning("ResourceSpawner: не задан node_scene")
		return
	for i in wood_count:
		_spawn("wood")
	for i in steel_count:
		_spawn("steel")


## Поставить новый узел добычи нужного типа в случайной точке.
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


## Случайная точка в кольце [min_radius, max_radius] вокруг центра, не ближе
## min_separation к другим узлам. Несколько попыток — иначе берём последнюю.
func _random_pos() -> Vector3:
	var p := Vector3.ZERO
	for attempt in 24:
		var ang := randf() * TAU
		var rad := randf_range(min_radius, max_radius)
		p = Vector3(cos(ang) * rad, spawn_y, sin(ang) * rad)
		var ok := true
		for n in get_tree().get_nodes_in_group("resource_node"):
			if is_instance_valid(n) and n is Node3D \
					and (n as Node3D).global_position.distance_to(p) < min_separation:
				ok = false
				break
		if ok:
			return p
	return p
