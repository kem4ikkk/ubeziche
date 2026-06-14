extends StaticBody3D

## Турель (Этап 4.8.1): автоматическая оборонительная постройка.
## Сама наводится на ближайшего зомби в радиусе и стреляет по кулдауну,
## расходуя общий боезапас турелей (InventorySystem "turret_ammo") —
## это её «расходник» (Turret Component). Когда боезапас кончился — простаивает.
## Как и стена, входит в группу "building": зомби могут её разрушить,
## игрок — отремонтировать (клавиша F).
##
## Электричество (Этап 4.16): пока турель установлена, она постоянно тратит
## электричество из общего запаса — раз в electricity_drain_interval секунд
## расходуется 1 ед., независимо от того, стреляет ли турель в этот момент.
## Если запас опустел — турель простаивает (см. _has_power в generator.gd).

@export var fire_range: float = 12.0      # радиус обнаружения цели, м
@export var fire_interval: float = 0.8    # пауза между выстрелами, с
@export var turret_damage: float = 12.0   # урон за выстрел
@export var electricity_drain_interval: float = 10.0  # секунд на 1 ед. электричества (Этап 4.16)

@onready var health: HealthComponent = $HealthComponent
@onready var hp_label: Label3D = $HPLabel
@onready var barrel: Node3D = $Barrel
@onready var power_label: Label3D = $PowerLabel

var _fire_timer: float = 0.0
var _drain_timer: float = 0.0


func _ready() -> void:
	add_to_group("building")
	add_to_group("turret")
	health.died.connect(_on_died)
	health.health_changed.connect(_on_health_changed)
	_on_health_changed(health.current_health, health.max_health)
	power_label.visible = false


func _physics_process(delta: float) -> void:
	_drain_electricity(delta)

	power_label.visible = not _has_power()
	if power_label.visible:
		return

	var target := _find_target()
	if not is_instance_valid(target):
		return

	# Поворачиваем ствол к цели по горизонтали (-Z ствола смотрит на врага).
	var aim := target.global_position
	aim.y = barrel.global_position.y
	if barrel.global_position.distance_to(aim) > 0.05:
		barrel.look_at(aim, Vector3.UP)

	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = fire_interval
		_try_fire(target)


## Стреляем по цели, если есть боезапас (расходник). Иначе простаиваем.
func _try_fire(target: Node3D) -> void:
	if InventorySystem.get_resource("turret_ammo") <= 0:
		return
	InventorySystem.use_resource("turret_ammo", 1)
	if target.has_method("take_damage"):
		target.take_damage(turret_damage)
	print("Турель стреляет (-", turret_damage, " HP)")


## Постоянный расход электричества за то, что турель установлена (Этап 4.16).
func _drain_electricity(delta: float) -> void:
	_drain_timer += delta
	if _drain_timer >= electricity_drain_interval:
		_drain_timer -= electricity_drain_interval
		if InventorySystem.get_resource("electricity") > 0:
			InventorySystem.use_resource("electricity", 1)


## Есть ли питание (Этап 4.14, ресурс переименован в 4.16): нужен живой
## генератор (группа "generator") и электричество в общем запасе.
## Без питания турель не наводится и не стреляет.
func _has_power() -> bool:
	if InventorySystem.get_resource("electricity") <= 0:
		return false
	return not get_tree().get_nodes_in_group("generator").is_empty()


## Ближайший зомби (группа "enemy") в радиусе действия.
func _find_target() -> Node3D:
	var nearest: Node3D = null
	var nearest_dist := fire_range
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not (enemy is Node3D):
			continue
		var dist := (enemy as Node3D).global_position.distance_to(global_position)
		if dist <= nearest_dist:
			nearest = enemy
			nearest_dist = dist
	return nearest


func take_damage(amount: float) -> void:
	health.take_damage(amount)
	EventBus.building_damaged.emit("Турель")


## Восстановить HP (ремонт игроком, как у стены).
func repair(amount: float) -> void:
	health.heal(amount)


func is_full_health() -> bool:
	return health.current_health >= health.max_health


func _on_died() -> void:
	queue_free()


func _on_health_changed(current: float, maximum: float) -> void:
	hp_label.text = "Турель %d / %d" % [current, maximum]
	var ratio := current / maximum
	if ratio > 0.6:
		hp_label.modulate = Color(0.4, 1.0, 0.4)
	elif ratio > 0.3:
		hp_label.modulate = Color(1.0, 0.85, 0.2)
	else:
		hp_label.modulate = Color(1.0, 0.3, 0.3)
