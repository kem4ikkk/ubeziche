extends StaticBody3D

## Сегмент убежища — серая стена периметра (Этап 5.x). Сам HP не хранит: урон от
## зомби перенаправляется в ОБЩИЙ запас HP убежища (родитель ShelterPerimeter со
## скриптом shelter.gd). В группе "building" — чтобы зомби атаковали его на пути.

func _ready() -> void:
	add_to_group("building")
	add_to_group("shelter_segment")


func take_damage(amount: float) -> void:
	var s := get_parent()
	if is_instance_valid(s) and s.has_method("take_damage"):
		s.take_damage(amount)


func repair(amount: float) -> void:
	var s := get_parent()
	if is_instance_valid(s) and s.has_method("repair"):
		s.repair(amount)


## HP убежища — для показа в HUD при наведении на сегмент.
func get_health() -> float:
	var s := get_parent()
	return s.get_health() if is_instance_valid(s) and s.has_method("get_health") else 0.0


func is_full_health() -> bool:
	var s := get_parent()
	return s.is_full_health() if is_instance_valid(s) and s.has_method("is_full_health") else true
