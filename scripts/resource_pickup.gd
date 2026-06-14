## Ресурсная точка для сбора.
## Игрок (CharacterBody3D) входит в Area3D → получает ресурсы → узел исчезает.

extends Area3D

@export var resource_type: String = "wood"
@export var resource_amount: int = 10

# Цвет ресурса по типу — чтобы дерево и камень отличались визуально.
const COLOR_BY_TYPE := {
	"wood": Color(0.55, 0.35, 0.15),
	"stone": Color(0.6, 0.6, 0.6),
	"fuel": Color(0.95, 0.75, 0.1),
}


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if mesh_instance != null and resource_type in COLOR_BY_TYPE:
		var material := StandardMaterial3D.new()
		material.albedo_color = COLOR_BY_TYPE[resource_type]
		mesh_instance.material_override = material


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		InventorySystem.add_resource(resource_type, resource_amount)
		queue_free()
