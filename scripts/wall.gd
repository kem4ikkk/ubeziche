extends StaticBody3D

## Простая стена для строительства. Имеет здоровье — зомби (или игрок)
## могут её разрушить. Игрок может её отремонтировать (Этап 4.3).

@onready var health: HealthComponent = $HealthComponent
@onready var hp_label: Label3D = $HPLabel


func _ready() -> void:
	add_to_group("building")
	health.died.connect(_on_died)
	health.health_changed.connect(_on_health_changed)
	_on_health_changed(health.current_health, health.max_health)


func take_damage(amount: float) -> void:
	health.take_damage(amount)


## Восстановить HP (например, при ремонте игроком).
func repair(amount: float) -> void:
	health.heal(amount)


## HP при максимуме — ремонт не нужен.
func is_full_health() -> bool:
	return health.current_health >= health.max_health


func _on_died() -> void:
	queue_free()


func _on_health_changed(current: float, maximum: float) -> void:
	hp_label.text = "%d / %d" % [current, maximum]
	var ratio := current / maximum
	if ratio > 0.6:
		hp_label.modulate = Color(0.4, 1.0, 0.4)
	elif ratio > 0.3:
		hp_label.modulate = Color(1.0, 0.85, 0.2)
	else:
		hp_label.modulate = Color(1.0, 0.3, 0.3)
