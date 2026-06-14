extends StaticBody3D

## Генератор (Этап 4.14, переработан в 4.16): ПРОИЗВОДИТ электричество
## (InventorySystem "electricity") — общий запас, которым питаются турели.
## В отличие от дерева/стали электричество не собирается на карте: его дают
## только генераторы (build_system.gd ограничивает их число до MAX_GENERATORS).
## Каждый живой генератор раз в electricity_production_interval секунд
## добавляет electricity_per_tick электричества в общий запас, но не выше
## storage_capacity (на этот генератор) — итоговый лимит запаса равен сумме
## storage_capacity всех живых генераторов.
## Пока электричество в запасе > 0 и есть хотя бы один живой генератор — все
## турели (Турель/Мортира/Гатлинг, проверка в turret.gd: _has_power) наводятся
## и стреляют как обычно. Если запас опустел или генераторы разрушены —
## турели простаивают (видна метка "нет питания").
## Как и другие постройки, входит в группу "building": зомби его ломают,
## игрок чинит на F.

@export var electricity_production_interval: float = 4.0  # секунд на 1 ед. электричества
@export var electricity_per_tick: int = 1
@export var storage_capacity: int = 10  # вклад этого генератора в общий лимит запаса

@onready var health: HealthComponent = $HealthComponent
@onready var hp_label: Label3D = $HPLabel
@onready var fan: Node3D = $Fan

var _produce_timer: float = 0.0
var _was_powered: bool = true


func _ready() -> void:
	add_to_group("building")
	add_to_group("generator")
	health.died.connect(_on_died)
	health.health_changed.connect(_on_health_changed)
	_on_health_changed(health.current_health, health.max_health)
	_was_powered = InventorySystem.get_resource("electricity") > 0


func _process(delta: float) -> void:
	if is_instance_valid(fan):
		fan.rotate_y(delta * 6.0)

	_produce_timer += delta
	var interval := electricity_production_interval
	if InventorySystem.shelter_tier >= 4:
		interval *= 0.5  # Тир 4 (4.15): улучшенные генераторы производят электричество вдвое быстрее
	if _produce_timer >= interval:
		_produce_timer -= interval
		var total_capacity := _total_storage_capacity()
		if InventorySystem.get_resource("electricity") < total_capacity:
			InventorySystem.add_resource("electricity", electricity_per_tick)

	var powered := InventorySystem.get_resource("electricity") > 0
	if powered != _was_powered:
		_was_powered = powered
		if powered:
			EventBus.power_restored.emit()
		else:
			EventBus.power_lost.emit()


## Суммарный лимит запаса электричества по всем живым генераторам.
func _total_storage_capacity() -> int:
	var total := 0
	for g in get_tree().get_nodes_in_group("generator"):
		total += int(g.get("storage_capacity"))
	return total


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
