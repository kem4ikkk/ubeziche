## Ресурс на карте. Два режима:
##  - harvestable = false (по умолчанию): ДРОП с зомби — подбирается ходьбой
##    (игрок входит в Area3D → +resource_amount → узел исчезает). Как было.
##  - harvestable = true: УЗЕЛ ДОБЫЧИ (дерево/сталь) — его ФИЗИЧЕСКИ бьют топором
##    (ЛКМ, player.swing_axe → hit()). У узла случайный запас УДАРОВ (HP) из
##    диапазона [min_hits, max_hits] (по умолчанию 5–7). За КАЖДЫЙ удар выдаётся
##    gather_level ресурса (навык «Добыча», 1/2/3): дерево с 6 ударами при добыче
##    1 даст 6 ресурса, при добыче 2 — 12, и т.д. Когда удары кончились — узел
##    ИСЧЕЗАЕТ (реген «на том же месте» убран). Новый узел спавнер
##    (resource_spawner.gd) ставит в СЛУЧАЙНОЙ точке карты.

extends Area3D

# Узел добычи исчерпан — спавнер (resource_spawner.gd) заменит его новым в другом месте.
signal depleted(node)

@export var resource_type: String = "wood"
@export var resource_amount: int = 10   # для дропа: сколько даёт за подбор ходьбой

## Узел добычи: бьётся топором. Запас — в УДАРАХ (HP), случайно из [min_hits, max_hits].
@export var harvestable: bool = false
@export var min_hits: int = 5
@export var max_hits: int = 7

# Физический слой для узлов добычи — чтобы их ловил луч топора (player.swing_axe),
# но НЕ задевали пули (shoot() этот слой исключает). Бит 4 = значение 16.
# ВАЖНО: НЕ слой 4 — там зомби (zombie.tscn collision_layer=4), иначе пули,
# исключая слой узлов, проходили бы и сквозь зомби (баг урона, исправлен 2026-06-16).
const HARVEST_LAYER := 16

var _hits_total: int = 0       # сколько ударов было у узла изначально
var _hits_remaining: int = 0   # сколько ударов осталось до истощения
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
		# Случайный запас ударов (HP) — каждый узел «толще» или «тоньше».
		_hits_total = randi_range(min_hits, max_hits)
		_hits_remaining = _hits_total
	else:
		# Дроп с зомби: подбор ходьбой (как раньше).
		collision_layer = 0
		collision_mask = 2
		body_entered.connect(_on_body_entered)


## Удар топором по узлу. Возвращает, сколько ресурса выдано за ЭТОТ удар.
## За удар = gather_level (навык «Добыча»). Удары кончились → узел исчерпан и
## шлёт сигнал depleted (спавнер ставит новый узел в случайном месте).
func hit() -> int:
	if not harvestable or _depleted:
		return 0
	var got: int = maxi(1, InventorySystem.gather_level)
	InventorySystem.add_resource(resource_type, got)
	_hits_remaining -= 1
	_update_visual()
	if _hits_remaining <= 0:
		_depleted = true
		depleted.emit(self)
	return got


## Дроп с зомби: игрок вошёл в зону — забираем ресурс и удаляем узел.
func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		InventorySystem.add_resource(resource_type, resource_amount)
		queue_free()


## Сжимаем узел по высоте по мере выработки — наглядная обратная связь по остатку
## ударов (дерево «срубается»). Чисто визуально, на коллизию/луч не влияет.
func _update_visual() -> void:
	var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if mesh_instance == null or _hits_total <= 0:
		return
	var frac := float(_hits_remaining) / float(_hits_total)
	mesh_instance.scale = Vector3(1.0, lerpf(0.4, 1.0, frac), 1.0)
