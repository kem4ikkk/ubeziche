extends StaticBody3D

## Склад (Этап 4.8.2). Раньше пополнял «боезапас турелей», но боезапас убран
## (Этап 4.25) — постройка временно выведена из меню постройки (build_system).
## Сам объект оставлен как обычная постройка (HP, ремонт) на случай ручного
## размещения; будущая роль — хранилище/лимит ресурсов (Warehouse), см. разд. 19.

@onready var health: HealthComponent = $HealthComponent
@onready var hp_label: Label3D = $HPLabel


func _ready() -> void:
	add_to_group("building")
	add_to_group("storage")
	health.died.connect(_on_died)
	health.health_changed.connect(_on_health_changed)
	_on_health_changed(health.current_health, health.max_health)


func take_damage(amount: float) -> void:
	health.take_damage(amount)
	EventBus.building_damaged.emit("Склад")


func repair(amount: float) -> void:
	health.heal(amount)


func is_full_health() -> bool:
	return health.current_health >= health.max_health


func _on_died() -> void:
	queue_free()


func _on_health_changed(current: float, maximum: float) -> void:
	hp_label.text = "Склад %d / %d" % [current, maximum]
	var ratio := current / maximum
	if ratio > 0.6:
		hp_label.modulate = Color(0.4, 1.0, 0.4)
	elif ratio > 0.3:
		hp_label.modulate = Color(1.0, 0.85, 0.2)
	else:
		hp_label.modulate = Color(1.0, 0.3, 0.3)
