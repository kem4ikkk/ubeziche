extends StaticBody3D

## Склад боеприпасов (Этап 4.8.2): со временем пополняет общий боезапас
## турелей (хранимые припасы кормят оборону) — пассивный источник расходника
## для турелей в дополнение к покупке в мастерской.
## Как и другие постройки, входит в группу "building": зомби её ломают,
## игрок чинит на F.

@export var supply_interval: float = 2.0  # как часто пополнять, с
@export var supply_amount: int = 1        # сколько боезапаса за тик

@onready var health: HealthComponent = $HealthComponent
@onready var hp_label: Label3D = $HPLabel

var _timer: float = 0.0


func _ready() -> void:
	add_to_group("building")
	add_to_group("storage")
	health.died.connect(_on_died)
	health.health_changed.connect(_on_health_changed)
	_on_health_changed(health.current_health, health.max_health)


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= supply_interval:
		_timer -= supply_interval
		InventorySystem.add_resource("turret_ammo", supply_amount)
		print("Склад: +", supply_amount, " боезапаса турелей")


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
