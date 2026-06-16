extends Node3D

## Костёр — сигнатурная способность Добытчика (Этап 4.12b). Ставится клавишей F.
## Пока игрок в радиусе — лечит его (реген HP/с). Горит фиксированное время, затем
## гаснет. Одновременно — один костёр (новый заменяет старый, см. player._place_campfire).

@export var heal_per_sec: float = 6.0
@export var radius: float = 4.0
@export var lifetime: float = 20.0

var _age: float = 0.0


func _ready() -> void:
	add_to_group("campfire")


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	var p := get_tree().get_first_node_in_group("player")
	if is_instance_valid(p) and p is Node3D and p.has_method("heal") \
			and (p as Node3D).global_position.distance_to(global_position) <= radius:
		p.heal(heal_per_sec * delta)
