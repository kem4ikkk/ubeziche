## Ресурс на карте. Два режима (Этап 4.22):
##  - harvestable = false (по умолчанию): ДРОП с зомби — подбирается ходьбой
##    (игрок входит в Area3D → +resource_amount → узел исчезает). Как было.
##  - harvestable = true: УЗЕЛ ДОБЫЧИ (дерево/сталь у базы) — бьём топором
##    (ЛКМ, player.swing_axe → hit()): за удар получаем gather_level ресурса
##    из запаса reserve; запас кончился → узел истощён до дневного регена.

extends Area3D

@export var resource_type: String = "wood"
@export var resource_amount: int = 10   # для дропа: сколько даёт за подбор ходьбой

## Узел добычи (Этап 4.22): бьётся топором, имеет запас и дневной реген.
@export var harvestable: bool = false
@export var max_reserve: int = 10       # сколько всего ресурса в узле до истощения

# Физический слой для узлов добычи — чтобы их ловил луч топора (player.swing_axe),
# но НЕ задевали пули (shoot() этот слой исключает). Бит 2 = значение 4.
const HARVEST_LAYER := 4

var reserve: int = 0
var _depleted: bool = false
var _material: StandardMaterial3D

# Цвет ресурса по типу — чтобы дерево и сталь отличались визуально.
const COLOR_BY_TYPE := {
	"wood": Color(0.55, 0.35, 0.15),
	"steel": Color(0.6, 0.6, 0.6),
}


func _ready() -> void:
	var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if mesh_instance != null and resource_type in COLOR_BY_TYPE:
		_material = StandardMaterial3D.new()
		_material.albedo_color = COLOR_BY_TYPE[resource_type]
		mesh_instance.material_override = _material

	if harvestable:
		# Узел добычи: ловится лучом топора, не подбирается ходьбой.
		add_to_group("resource_node")
		collision_layer = HARVEST_LAYER
		collision_mask = 0
		reserve = max_reserve
		# Реген привязываем к дню — подключаемся отложенно, когда цикл уже в группе.
		_connect_day_cycle.call_deferred()
	else:
		# Дроп с зомби: подбор ходьбой (как раньше).
		collision_layer = 0
		collision_mask = 2
		body_entered.connect(_on_body_entered)


## Удар топором по узлу (Этап 4.22). Возвращает, сколько ресурса выдано.
func hit() -> int:
	if not harvestable or _depleted:
		return 0
	var per_hit: int = maxi(1, InventorySystem.gather_level)
	var got: int = mini(per_hit, reserve)
	if got <= 0:
		return 0
	InventorySystem.add_resource(resource_type, got)
	reserve -= got
	if reserve <= 0:
		_set_depleted(true)
	return got


## Дроп с зомби: игрок вошёл в зону — забираем ресурс и удаляем узел.
func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		InventorySystem.add_resource(resource_type, resource_amount)
		queue_free()


## Подключение к циклу день/ночь для дневного регена узла.
func _connect_day_cycle() -> void:
	var cycle := get_tree().get_first_node_in_group("day_night_cycle")
	if is_instance_valid(cycle) and cycle.has_signal("phase_changed"):
		cycle.phase_changed.connect(_on_phase_changed)


## Наступил день — узел восстанавливает запас (как в оригинале: реген за день).
func _on_phase_changed(is_night: bool) -> void:
	if not is_night and _depleted:
		reserve = max_reserve
		_set_depleted(false)


## Визуально гасим/возвращаем узел при истощении/регене.
func _set_depleted(depleted: bool) -> void:
	_depleted = depleted
	if _material == null:
		return
	if depleted:
		_material.albedo_color = COLOR_BY_TYPE.get(resource_type, Color.WHITE) * 0.3
	else:
		_material.albedo_color = COLOR_BY_TYPE.get(resource_type, Color.WHITE)
