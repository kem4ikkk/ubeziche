extends Node3D

## C4 — сигнатурная способность Инженера (Этап 4.12b). Ставится клавишей F при
## наличии заряда (крафт в мастерской). Через fuse секунд взрывается:
##  - AoE урон по всем зомби (группа "enemy") в радиусе;
##  - сносит ТОЛЬКО размеченные разрушаемые сегменты (группа "blastable") в радиусе,
##    открывая проход. Обычные постройки/базу (группа "building") НЕ трогает.

@export var fuse: float = 3.0
@export var radius: float = 4.0
@export var damage: float = 120.0


func _ready() -> void:
	add_to_group("c4")
	_tick()


func _tick() -> void:
	await get_tree().create_timer(fuse).timeout
	if not is_inside_tree():
		return
	_explode()


func _explode() -> void:
	var hit := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Node3D and (e as Node3D).global_position.distance_to(global_position) <= radius \
				and e.has_method("take_damage"):
			e.take_damage(damage)
			hit += 1
	var segments := 0
	for seg in get_tree().get_nodes_in_group("blastable"):
		if seg is Node3D and (seg as Node3D).global_position.distance_to(global_position) <= radius:
			if seg.has_method("blast"):
				seg.blast()
			else:
				seg.queue_free()
			segments += 1
	# Обычные постройки (группа "building") НАМЕРЕННО не трогаем — базу не снести.
	print("C4 взорвался: урон по ", hit, " зомби, снесено сегментов ", segments)
	queue_free()
