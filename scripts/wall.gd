extends StaticBody3D

## Простая стена для строительства. Имеет здоровье — зомби (или игрок)
## могут её разрушить.

@onready var health: HealthComponent = $HealthComponent


func _ready() -> void:
	add_to_group("building")
	health.died.connect(_on_died)


func take_damage(amount: float) -> void:
	health.take_damage(amount)


func _on_died() -> void:
	queue_free()
