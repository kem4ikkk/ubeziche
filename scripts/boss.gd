extends "res://scripts/zombie.gd"

## Босс «Колосс» (Этап 4.13b): приходит в босс-ночи (каждые boss_every, WaveManager).
## Большой HP, медленный; уникальная атака — СЛЭМ по площади: телеграф-предупреждение,
## затем AoE урон игроку и постройкам в радиусе. Шлёт EventBus boss_spawned/
## boss_health_changed/boss_defeated — для HP-бара сверху и алертов HUD.

@export var boss_name: String = "Колосс"
@export var slam_range: float = 5.0      # на какой дистанции до игрока начинает слэм
@export var slam_radius: float = 4.5     # радиус поражения слэма
@export var slam_damage: float = 35.0
@export var slam_cooldown: float = 4.0
@export var slam_telegraph: float = 1.0  # задержка-предупреждение перед ударом

var _slam_timer: float = 0.0
var _slamming: bool = false


func _ready() -> void:
	super._ready()
	add_to_group("boss")
	EventBus.boss_spawned.emit(boss_name, health.max_health)
	health.health_changed.connect(func(hp, mx): EventBus.boss_health_changed.emit(hp, mx))


func _physics_process(delta: float) -> void:
	if _dead or not is_inside_tree():
		return
	if _slam_timer > 0.0:
		_slam_timer -= delta
	# Во время телеграфа/удара стоим на месте (но держимся на земле).
	if _slamming:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return
	# Слэм, когда игрок близко и кулдаун готов.
	if _slam_timer <= 0.0 and is_instance_valid(_player) and _player.is_inside_tree() \
			and global_position.distance_to(_player.global_position) <= slam_range:
		_do_slam()
		return
	super._physics_process(delta)


## Слэм по площади: телеграф → AoE урон игроку и постройкам в радиусе.
func _do_slam() -> void:
	_slamming = true
	_slam_timer = slam_cooldown
	print("Колосс готовит слэм!")
	await get_tree().create_timer(slam_telegraph).timeout
	if not is_inside_tree() or _dead:
		_slamming = false
		return
	var hits := 0
	for n in get_tree().get_nodes_in_group("player") + get_tree().get_nodes_in_group("building"):
		if n is Node3D and n.has_method("take_damage") \
				and (n as Node3D).global_position.distance_to(global_position) <= slam_radius:
			n.take_damage(slam_damage)
			hits += 1
	print("Колосс бьёт слэмом: задето целей ", hits, " (урон ", slam_damage, ")")
	_slamming = false


func _on_died() -> void:
	EventBus.boss_defeated.emit()
	print("Босс «", boss_name, "» повержен!")
	super._on_died()
