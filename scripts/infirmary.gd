extends StaticBody3D

## Лазарет (Этап 4.8.2): лечит игрока, пока он стоит рядом (аура лечения).
## Бесплатно, но медленно — в отличие от платного лечения в мастерской.
## Как и другие постройки, входит в группу "building": зомби её ломают,
## игрок чинит на F.

@export var heal_range: float = 5.0   # радиус действия ауры, м
@export var heal_rate: float = 8.0    # сколько HP в секунду восстанавливает

@onready var health: HealthComponent = $HealthComponent
@onready var hp_label: Label3D = $HPLabel

var _player: Node3D = null


func _ready() -> void:
	add_to_group("building")
	add_to_group("infirmary")
	health.died.connect(_on_died)
	health.health_changed.connect(_on_health_changed)
	_on_health_changed(health.current_health, health.max_health)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if not is_instance_valid(_player):
			return
	if _player.global_position.distance_to(global_position) > heal_range:
		return
	if not _player.has_method("heal"):
		return
	if _player.has_method("is_full_health") and _player.is_full_health():
		return
	_player.heal(heal_rate * delta)


func take_damage(amount: float) -> void:
	health.take_damage(amount)
	EventBus.building_damaged.emit("Лазарет")


func repair(amount: float) -> void:
	health.heal(amount)


func is_full_health() -> bool:
	return health.current_health >= health.max_health


func _on_died() -> void:
	queue_free()


func _on_health_changed(current: float, maximum: float) -> void:
	hp_label.text = "Лазарет %d / %d" % [current, maximum]
	var ratio := current / maximum
	if ratio > 0.6:
		hp_label.modulate = Color(0.4, 1.0, 0.4)
	elif ratio > 0.3:
		hp_label.modulate = Color(1.0, 0.85, 0.2)
	else:
		hp_label.modulate = Color(1.0, 0.3, 0.3)
