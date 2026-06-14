extends StaticBody3D

## Генератор (Этап 4.14): питает турели общим топливом (InventorySystem "fuel").
## Пока в сцене есть хотя бы один живой генератор и топливо > 0 — все турели
## (Турель/Мортира/Гатлинг, проверка в turret.gd: _has_power) наводятся и
## стреляют как обычно. Если топливо кончилось или генератор разрушен —
## турели простаивают (видна метка "нет питания").
## Сам генератор медленно расходует топливо со временем (fuel_consumption_rate
## в секунду). Как и другие постройки, входит в группу "building": зомби его
## ломают, игрок чинит на F.

@export var fuel_consumption_rate: float = 0.2  # топлива в секунду (1 за 5с)

@onready var health: HealthComponent = $HealthComponent
@onready var hp_label: Label3D = $HPLabel
@onready var fan: Node3D = $Fan

var _consume_timer: float = 0.0
var _was_powered: bool = true


func _ready() -> void:
	add_to_group("building")
	add_to_group("generator")
	health.died.connect(_on_died)
	health.health_changed.connect(_on_health_changed)
	_on_health_changed(health.current_health, health.max_health)
	_was_powered = InventorySystem.get_resource("fuel") > 0


func _process(delta: float) -> void:
	if is_instance_valid(fan):
		fan.rotate_y(delta * 6.0)

	_consume_timer += delta
	var interval := 1.0 / fuel_consumption_rate
	if _consume_timer >= interval:
		_consume_timer -= interval
		if InventorySystem.get_resource("fuel") > 0:
			InventorySystem.use_resource("fuel", 1)

	var powered := InventorySystem.get_resource("fuel") > 0
	if powered != _was_powered:
		_was_powered = powered
		if powered:
			EventBus.power_restored.emit()
		else:
			EventBus.power_lost.emit()


func take_damage(amount: float) -> void:
	health.take_damage(amount)
	EventBus.building_damaged.emit("Генератор")


## Восстановить HP (ремонт игроком, как у других построек).
func repair(amount: float) -> void:
	health.heal(amount)


func is_full_health() -> bool:
	return health.current_health >= health.max_health


func _on_died() -> void:
	EventBus.power_lost.emit()
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
