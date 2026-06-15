extends StaticBody3D

## Генератор (Этап 4.14; модель питания переработана в 4.25). Даёт фиксированную
## МОЩНОСТЬ (power_output), пока стоит — это не запас, а постоянная отдача, как
## ватты. Турели потребляют мощность (turret.gd: power_cost); если суммарной
## мощности всех генераторов не хватает на турель — эта турель простаивает,
## а остальные (что влезли в бюджет) работают. Тир 4 (4.15) повышает отдачу.
## Как и другие постройки — в группе "building": зомби ломают, игрок чинит топором.

@export var power_output: int = 40  # базовая мощность (маленький 40 / средний 60 / большой 80)

@onready var health: HealthComponent = $HealthComponent
@onready var hp_label: Label3D = $HPLabel
@onready var fan: Node3D = $Fan


func _ready() -> void:
	add_to_group("building")
	add_to_group("generator")
	health.died.connect(_on_died)
	health.health_changed.connect(_on_health_changed)
	_on_health_changed(health.current_health, health.max_health)


func _process(delta: float) -> void:
	if is_instance_valid(fan):
		fan.rotate_y(delta * 6.0)


## Текущая отдаваемая мощность (Этап 4.25). Тир 4 (4.15) добавляет +20.
func get_power_output() -> int:
	return power_output + (20 if InventorySystem.shelter_tier >= 4 else 0)


func take_damage(amount: float) -> void:
	health.take_damage(amount)
	EventBus.building_damaged.emit("Генератор")


## Восстановить HP (ремонт игроком, как у других построек).
func repair(amount: float) -> void:
	health.heal(amount)


func is_full_health() -> bool:
	return health.current_health >= health.max_health


func _on_died() -> void:
	queue_free()


func _on_health_changed(current: float, maximum: float) -> void:
	hp_label.text = "Генератор %d / %d" % [current, maximum]
	var ratio := current / maximum
	if ratio > 0.6:
		hp_label.modulate = Color(0.4, 1.0, 0.4)
	elif ratio > 0.3:
		hp_label.modulate = Color(1.0, 0.85, 0.2)
	else:
		hp_label.modulate = Color(1.0, 0.3, 0.3)
