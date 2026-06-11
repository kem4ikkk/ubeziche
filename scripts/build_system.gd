extends Node3D

## Система строительства-минимума (Этап 3.5).
## B — переключить режим постройки (показывает призрак-превью).
## ЛКМ в режиме постройки — построить стену (если хватает ресурса "wall").
## Позиция привязывается к сетке GRID_SIZE x GRID_SIZE.

const GRID_SIZE := 1.0
const PLACE_DISTANCE := 3.0
const BUILD_COST := {"wall": 1}

@export var wall_scene: PackedScene

var build_mode: bool = false
var _ghost: Node3D

@onready var _player: Node3D = get_parent() as Node3D


func _ready() -> void:
	_ghost = wall_scene.instantiate()
	_ghost.set_script(null)  # призрак не должен жить как настоящая стена
	_make_ghost(_ghost)
	_ghost.visible = false
	get_tree().current_scene.add_child.call_deferred(_ghost)


func _process(_delta: float) -> void:
	if not build_mode:
		return
	_ghost.global_position = _get_target_position()


## Включить/выключить режим постройки.
func toggle() -> void:
	build_mode = not build_mode
	_ghost.visible = build_mode
	if build_mode:
		_ghost.global_position = _get_target_position()


## Построить стену в позиции призрака (если хватает ресурсов).
func try_place() -> bool:
	if not build_mode:
		return false

	for resource_type in BUILD_COST:
		if InventorySystem.get_resource(resource_type) < BUILD_COST[resource_type]:
			print("CLAUDE: не хватает ресурсов для постройки")
			return false

	for resource_type in BUILD_COST:
		InventorySystem.use_resource(resource_type, BUILD_COST[resource_type])

	var wall := wall_scene.instantiate()
	get_tree().current_scene.add_child(wall)
	wall.global_position = _ghost.global_position
	return true


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


## Делаем копию стены полупрозрачной и убираем у неё столкновения/здоровье.
func _make_ghost(node: Node) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 1.0, 0.3, 0.4)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		(node as MeshInstance3D).material_override = mat
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	for child in node.get_children():
		_make_ghost(child)
