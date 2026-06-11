extends CharacterBody3D

## Простой зомби: преследует игрока, вблизи атакует, умирает от урона.
## Навигацию (NavMesh) пока не используем — арена плоская, без препятствий,
## поэтому идём напрямую к игроку. Подключим NavigationAgent3D позже,
## когда появятся стены базы и препятствия (Этап 4/3.5).

@export var speed: float = 2.5            # скорость зомби (медленнее игрока)
@export var attack_damage: float = 8.0    # урон за удар
@export var attack_range: float = 1.8     # дистанция, с которой бьёт
@export var attack_cooldown: float = 1.0  # пауза между ударами, с

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

	# Гравитация — чтобы зомби «прилипал» к земле.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Если игрок ещё не найден или погиб — стоим и пробуем найти заново.
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	# Вектор до игрока по горизонтали.
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var distance := to_player.length()

	if distance > attack_range:
		# Преследование: идём к игроку и поворачиваемся к нему лицом.
		var dir := to_player.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		look_at(global_position + dir, Vector3.UP)
	else:
		# В зоне атаки: стоим и бьём по кулдауну.
		velocity.x = 0.0
		velocity.z = 0.0
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_attack_timer = attack_cooldown
			if _player.has_method("take_damage"):
				_player.take_damage(attack_damage)
				print("Зомби атакует игрока (-", attack_damage, " HP)")

	move_and_slide()


## Урон по зомби (например, от выстрела игрока) — тот же интерфейс, что у мишени.
func take_damage(amount: float) -> void:
	health.take_damage(amount)


func get_health() -> float:
	return health.current_health


func _on_died() -> void:
	_dead = true
	print("Зомби уничтожен")
	# TODO (Этап 3.2.4): здесь будет дроп ресурса.
	queue_free()
