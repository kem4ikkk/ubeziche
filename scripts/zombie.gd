extends CharacterBody3D

## Простой зомби: преследует игрока, вблизи атакует, умирает от урона.
## Навигацию (NavMesh) пока не используем — идём напрямую к игроку.
## Если на пути встаёт постройка (баррикада/стена) и зомби не может
## до неё дотянуться до игрока — атакует постройку (Этап 4.2).
## Этот же скрипт используется и для зомби-танка (Этап 4.4) — отличия
## задаются экспортами в сцене (scenes/zombie_tank.tscn): больше HP,
## меньше скорость, сильнее урон по постройкам, больше радиус их атаки.

@export var speed: float = 2.5            # скорость зомби (медленнее игрока)
@export var attack_damage: float = 8.0    # урон за удар по игроку
@export var attack_range: float = 1.8     # дистанция, с которой бьёт
@export var attack_cooldown: float = 1.0  # пауза между ударами, с
@export var building_attack_range: float = 2.0  # дистанция атаки построек
@export var building_attack_damage: float = 8.0  # урон за удар по постройке (Этап 4.4: танк бьёт сильнее)

# Дроп ресурса при смерти (Этап 4.7.1): редкий случайный бонус, основные
# залежи ресурсов (дерево/сталь) разбросаны по карте отдельно.
@export var drop_chance: float = 0.25     # шанс дропа (0..1)
@export var drop_resource_types: PackedStringArray = ["wood", "steel"]
@export var drop_amount_min: int = 1
@export var drop_amount_max: int = 2
@export var drop_scene: PackedScene = preload("res://scenes/resource_pickup.tscn")

# Деньги за убийство (Этап 4.7.2): вторая валюта, идёт на покупки в мастерской.
# Танк даёт больше (задаётся в его сцене).
@export var money_reward: int = 10

@onready var health: HealthComponent = $HealthComponent

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _player: Node3D = null
var _attack_timer: float = 0.0
var _dead: bool = false


func _ready() -> void:
	add_to_group("enemy")
	health.died.connect(_on_died)
	# Игрок записывает себя в группу "player" в своём _ready().
	_player = get_tree().get_first_node_in_group("player") as Node3D


func _physics_process(delta: float) -> void:
	if _dead:
		return

	# Сцена могла перезагрузиться (смерть игрока) в этом же кадре —
	# не трогаем физику, иначе move_and_slide() упадёт с ошибкой.
	if not is_inside_tree():
		return

	# Гравитация — чтобы зомби «прилипал» к земле.
	if not is_on_floor():
		velocity.y -= gravity * delta

	if not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = get_tree().get_first_node_in_group("player") as Node3D

	# ЦЕЛЬ зомби: ЖИВОЙ игрок (агрятся и гонятся за ним); если игрок мёртв/отсутствует
	# — идут к ближайшей СТЕНЕ убежища, чтобы ломать его. По пути в обоих случаях
	# бьют постройки/стены, которые им мешают (это и снимает HP убежища).
	var player_alive: bool = is_instance_valid(_player) and _player.is_inside_tree() \
			and not (_player.has_method("is_dead") and _player.is_dead())
	var target_pos: Vector3
	if player_alive:
		target_pos = _player.global_position
	else:
		var seg := _nearest_shelter_segment()
		target_pos = seg.global_position if is_instance_valid(seg) else global_position

	# Постройка на пути (стена/баррикада/стена убежища) — приоритет: бьём её.
	var blocker := _find_nearby_building()
	if is_instance_valid(blocker):
		var to_blocker := blocker.global_position - global_position
		to_blocker.y = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		if to_blocker.length() > 0.01:
			look_at(global_position + to_blocker.normalized(), Vector3.UP)
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_attack_timer = attack_cooldown
			blocker.take_damage(building_attack_damage)
		move_and_slide()
		return

	# Живой игрок в упор — кусаем его.
	if player_alive:
		var to_player := _player.global_position - global_position
		to_player.y = 0.0
		if to_player.length() <= attack_range:
			velocity.x = 0.0
			velocity.z = 0.0
			if to_player.length() > 0.01:
				look_at(global_position + to_player.normalized(), Vector3.UP)
			_attack_timer -= delta
			if _attack_timer <= 0.0:
				_attack_timer = attack_cooldown
				if _player.has_method("take_damage"):
					_player.take_damage(attack_damage)
			move_and_slide()
			return

	# Преследование цели (игрок / стена убежища).
	var to_t := target_pos - global_position
	to_t.y = 0.0
	if to_t.length() > 0.6:
		var dir := to_t.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		look_at(global_position + dir, Vector3.UP)
	else:
		velocity.x = 0.0
		velocity.z = 0.0

	move_and_slide()


## Ищем ближайшую постройку (группа "building") в радиусе атаки —
## она блокирует путь к игроку, поэтому приоритетнее.
func _find_nearby_building() -> Node3D:
	var nearest: Node3D = null
	var nearest_dist := building_attack_range
	for node in get_tree().get_nodes_in_group("building"):
		if not (node is Node3D) or not node.has_method("take_damage"):
			continue
		var to_node: Vector3 = (node as Node3D).global_position - global_position
		to_node.y = 0.0
		var dist := to_node.length()
		if dist <= nearest_dist:
			nearest = node
			nearest_dist = dist
	return nearest


## Ближайшая стена убежища (группа "shelter_segment") — цель, когда игрок мёртв.
func _nearest_shelter_segment() -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for s in get_tree().get_nodes_in_group("shelter_segment"):
		if s is Node3D:
			var d: float = global_position.distance_to((s as Node3D).global_position)
			if d < best_dist:
				best_dist = d
				best = s
	return best


## Урон по зомби (например, от выстрела игрока) — тот же интерфейс, что у мишени.
func take_damage(amount: float) -> void:
	health.take_damage(amount)


func get_health() -> float:
	return health.current_health


func _on_died() -> void:
	_dead = true
	print("Зомби уничтожен")
	InventorySystem.add_money(money_reward)   # деньги за убийство (Этап 4.7.2)
	_drop_resource()
	queue_free()


## Дроп ресурса (Этап 4.7.1): с небольшим шансом создаём подбираемый
## ресурс случайного типа и количества на месте смерти.
func _drop_resource() -> void:
	if drop_scene == null or drop_resource_types.is_empty():
		return
	if randf() > drop_chance:
		return
	var pickup := drop_scene.instantiate()
	get_tree().current_scene.add_child(pickup)
	pickup.global_position = global_position
	if "resource_type" in pickup:
		pickup.resource_type = drop_resource_types[randi() % drop_resource_types.size()]
	if "resource_amount" in pickup:
		pickup.resource_amount = randi_range(drop_amount_min, drop_amount_max)
