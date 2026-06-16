extends "res://scripts/zombie.gd"

## Крикун (Этап 4.13a): по бою как обычный зомби (наследует zombie.gd), но при
## ПЕРВОМ обнаружении игрока в радиусе scream_range один раз «кричит» — просит
## WaveManager доспавнить группу зомби (summon_extra). HUD показывает алерт
## (EventBus.screamer_called). Кричит только однажды за свою жизнь.

@export var scream_range: float = 14.0
@export var summon_count: int = 3
var _screamed: bool = false


func _physics_process(delta: float) -> void:
	if not _screamed and not _dead and is_instance_valid(_player) and _player.is_inside_tree():
		if global_position.distance_to(_player.global_position) <= scream_range:
			_scream()
	super._physics_process(delta)


func _scream() -> void:
	_screamed = true
	print("Крикун кричит — зовёт подмогу!")
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if is_instance_valid(wm) and wm.has_method("summon_extra"):
		wm.summon_extra(summon_count)
	EventBus.screamer_called.emit()
