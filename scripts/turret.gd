extends StaticBody3D

## Турель (Этап 4.8.1): автоматическая оборонительная постройка.
## Сама наводится на ближайшего зомби в радиусе и стреляет по кулдауну.
## Боезапаса нет (убран в 4.25) — турель работает, пока есть питание
## (электричество от генератора, _has_power); без питания простаивает.
## Как и стена, входит в группу "building": зомби могут её разрушить,
## игрок — отремонтировать ударом топора.
##
## Питание (Этап 4.25, модель мощности): пока турель установлена, она ПОТРЕБЛЯЕТ
## power_cost мощности (постоянная нагрузка, как ватты — не запас и не за выстрел).
## Турель работает, если суммарной мощности генераторов хватает на неё с учётом
## всех турелей по порядку; если бюджет исчерпан — эта турель простаивает,
## а те, что влезли в бюджет, работают (см. _has_power).

@export var fire_range: float = 12.0      # радиус обнаружения цели, м
@export var fire_interval: float = 0.8    # пауза между выстрелами, с
@export var turret_damage: float = 12.0   # урон за выстрел
@export var power_cost: int = 30          # сколько мощности потребляет (Этап 4.25)

@onready var health: HealthComponent = $HealthComponent
@onready var hp_label: Label3D = $HPLabel
@onready var barrel: Node3D = $Barrel
@onready var power_label: Label3D = $PowerLabel

var _fire_timer: float = 0.0


func _ready() -> void:
	add_to_group("building")
	add_to_group("turret")
	health.died.connect(_on_died)
	health.health_changed.connect(_on_health_changed)
	_on_health_changed(health.current_health, health.max_health)
	power_label.visible = false


func _physics_process(delta: float) -> void:
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


## Стреляем по цели (Этап 4.25: без боезапаса, только при наличии питания —
## проверка _has_power уже сделана в _physics_process).
## Урон турели. Бонус к урону турелей даёт «Молот» (Техническое мастерство) —
## будет подключён отдельной стадией; пока базовый урон.
func _try_fire(target: Node3D) -> void:
	var dmg := turret_damage
	if target.has_method("take_damage"):
		target.take_damage(dmg)
	print("Турель стреляет (-", dmg, " HP)")


## Есть ли питание (Этап 4.25, модель мощности): суммируем отдачу всех живых
## генераторов и нарастающую нагрузку турелей по порядку группы "turret".
## Турель запитана, если суммарная нагрузка вплоть до неё включительно не
## превышает суммарную мощность; иначе — простаивает (бюджет исчерпан).
func _has_power() -> bool:
	var supply := 0
	for g in get_tree().get_nodes_in_group("generator"):
		if g.has_method("get_power_output"):
			supply += g.get_power_output()
	if supply <= 0:
		return false
	var used := 0
	for t in get_tree().get_nodes_in_group("turret"):
		used += int(t.power_cost) if "power_cost" in t else 30
		if t == self:
			break
	return used <= supply


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
