## Ресурсная точка для сбора.
## Игрок (CharacterBody3D) входит в Area3D → получает ресурсы → узел исчезает.

extends Area3D

@export var resource_type: String = "wood"
@export var resource_amount: int = 10


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		InventorySystem.add_resource(resource_type, resource_amount)
		queue_free()
