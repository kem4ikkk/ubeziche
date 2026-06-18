extends Node3D

## Система строительства (Этап 3.5; расширена в 4.8.1).
## B — переключить режим постройки (показывает призрак-превью).
## V — сменить тип постройки (стена ↔ турель), пока режим включён.
## ЛКМ в режиме постройки — построить выбранное здание (если хватает ресурсов).
## Позиция привязывается к сетке GRID_SIZE x GRID_SIZE.

const GRID_SIZE := 1.0
const PLACE_DISTANCE := 3.0
const MAX_GENERATORS := 4  # лимит ставимых генераторов (Этап 4.16)

@export var wall_scene: PackedScene
@export var turret_scene: PackedScene
@export var infirmary_scene: PackedScene
@export var storage_scene: PackedScene
@export var mortar_scene: PackedScene
@export var gatling_scene: PackedScene
@export var generator_scene: PackedScene
@export var workshop_scene: PackedScene
@export var campfire_scene: PackedScene

var build_mode: bool = false
var _ghost: Node3D
# Доступные постройки: имя, сцена и стоимость в ресурсах.
var _buildables: Array[Dictionary] = []
var _current: int = 0

@onready var _player: Node3D = get_parent() as Node3D


func _ready() -> void:
	_buildables = [
		{"name": "Стена", "scene": wall_scene, "cost": {"wood": 2}, "min_tier": 1},
		{"name": "Мастерская", "scene": workshop_scene, "cost": {"wood": 10, "steel": 5}, "min_tier": 1},
		{"name": "Генератор", "scene": generator_scene, "cost": {"steel": 10, "wood": 5}, "min_tier": 1},
		{"name": "Турель", "scene": turret_scene, "cost": {"steel": 3, "wood": 2}, "min_tier": 1},
		{"name": "Лазарет", "scene": infirmary_scene, "cost": {"wood": 3, "steel": 3}, "min_tier": 1},
		{"name": "Костёр", "scene": campfire_scene, "cost": {"wood": 5}, "min_tier": 1},
		{"name": "Мортира", "scene": mortar_scene, "cost": {"steel": 8, "wood": 4}, "min_tier": 2},
		{"name": "Гатлинг", "scene": gatling_scene, "cost": {"steel": 12, "wood": 6}, "min_tier": 3},
	]
	_rebuild_ghost()


func _process(_delta: float) -> void:
	if not build_mode or not is_instance_valid(_ghost) or not _ghost.is_inside_tree():
		return
	_ghost.global_position = _get_target_position()


## Включить/выключить режим постройки.
func toggle() -> void:
	build_mode = not build_mode
	if is_instance_valid(_ghost):
		_ghost.visible = build_mode
		if build_mode and _ghost.is_inside_tree():
			_ghost.global_position = _get_target_position()


## Сменить выбранный тип постройки (по кругу), пока включён режим стройки.
func cycle_buildable() -> void:
	if not build_mode:
		return
	_current = (_current + 1) % _buildables.size()
	_rebuild_ghost()
	print("CLAUDE: выбрана постройка: ", current_buildable_name())


## Имя текущего выбранного здания (для HUD/тестов).
func current_buildable_name() -> String:
	return _buildables[_current].name


## Список доступных построек (имя/сцена/цена/min_tier) — для меню построек (4.26).
func get_buildables() -> Array[Dictionary]:
	return _buildables


## Выбрать здание по имени (для тестов / будущего меню постройки).
func select_buildable(building_name: String) -> bool:
	for i in _buildables.size():
		if _buildables[i].name == building_name:
			_current = i
			_rebuild_ghost()
			return true
	return false


## Построить выбранное здание в позиции призрака (если хватает ресурсов).
func try_place() -> bool:
	if not build_mode:
		return false

	var buildable: Dictionary = _buildables[_current]
	var min_tier: int = buildable.get("min_tier", 1)
	if InventorySystem.shelter_tier < min_tier:
		print("CLAUDE: '", buildable.name, "' требует Тир ", min_tier,
				" убежища (сейчас Тир ", InventorySystem.shelter_tier, ")")
		return false

	if buildable.name == "Генератор" \
			and get_tree().get_nodes_in_group("generator").size() >= MAX_GENERATORS:
		print("CLAUDE: достигнут лимит генераторов (", MAX_GENERATORS, ")")
		return false

	# Мастерская нужна одна — второй верстак ставить незачем (Этап 4.30).
	if buildable.name == "Мастерская" \
			and not get_tree().get_nodes_in_group("workshop").is_empty():
		print("CLAUDE: мастерская уже построена")
		return false

	# Нельзя ставить постройку на постройку/стену/периметр (Этап 4.31).
	if _is_spot_occupied(_ghost.global_position):
		print("CLAUDE: место занято — здесь нельзя строить")
		return false

	var cost: Dictionary = buildable.cost
	for resource_type in cost:
		if InventorySystem.get_resource(resource_type) < cost[resource_type]:
			print("CLAUDE: не хватает ресурсов для постройки (", buildable.name, ")")
			return false

	for resource_type in cost:
		InventorySystem.use_resource(resource_type, cost[resource_type])

	var scene: PackedScene = buildable.scene
	var building := scene.instantiate()
	get_tree().current_scene.add_child(building)
	building.global_position = _ghost.global_position
	return true


## Занята ли точка существующей постройкой/стеной/периметром (Этап 4.31): физ.
## оверлап сферой по слою 1. Призрак коллизий не имеет (collision_layer=0), так
## что себя не задевает; земля (WorldBoundary) сферой над полом не задевается.
func _is_spot_occupied(pos: Vector3) -> bool:
	if not is_inside_tree():
		return false
	var space := get_world_3d().direct_space_state
	if space == null:
		return false
	var shape := SphereShape3D.new()
	shape.radius = 0.45   # < половины клетки (1 м), чтобы не блокировать соседние
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), pos)
	params.collision_mask = 1
	params.collide_with_bodies = true
	params.collide_with_areas = false
	return not space.intersect_shape(params, 1).is_empty()


## Пересобрать призрак-превью под текущий выбранный тип постройки.
func _rebuild_ghost() -> void:
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	var scene: PackedScene = _buildables[_current].scene
	_ghost = scene.instantiate()
	_ghost.set_script(null)  # призрак не должен жить как настоящая постройка
	_make_ghost(_ghost)
	_ghost.visible = build_mode
	get_tree().current_scene.add_child.call_deferred(_ghost)


## Точка перед игроком (по направлению взгляда по горизонтали), привязанная к сетке.
func _get_target_position() -> Vector3:
	var forward := -_player.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = Vector3.FORWARD
	forward = forward.normalized()

	var base_pos := _player.global_position + forward * PLACE_DISTANCE
	var snapped_x := roundi(base_pos.x / GRID_SIZE) * GRID_SIZE
	var snapped_z := roundi(base_pos.z / GRID_SIZE) * GRID_SIZE
	return Vector3(snapped_x, 0.5, snapped_z)


## Делаем копию постройки полупрозрачной и убираем у неё столкновения/здоровье.
## Label3D-подсказку у призрака прячем (на превью не должно висеть «подойдите
## ближе»/HP). Не освобождаем — призрак ещё не в дереве (add_child отложен),
## а free до входа в дерево чреват гонкой; visible=false достаточно.
func _make_ghost(node: Node) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 1.0, 0.3, 0.4)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		(node as MeshInstance3D).material_override = mat
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	if node is Label3D:
		(node as Label3D).visible = false
	for child in node.get_children():
		_make_ghost(child)
