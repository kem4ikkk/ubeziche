extends "res://scripts/zombie.gd"

## Взрывной (Этап 4.13a): по бою как обычный зомби, но при СМЕРТИ взрывается —
## наносит AoE урон игроку и постройкам (группа "building") в радиусе explode_radius.
## Расширяет _on_died: сначала взрыв, затем штатная смерть (награда/дроп/queue_free).

@export var explode_radius: float = 4.0
@export var explode_damage: float = 30.0


func _on_died() -> void:
	_explode()
	super._on_died()


func _explode() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if is_instance_valid(p) and p is Node3D and p.has_method("take_damage") \
			and (p as Node3D).global_position.distance_to(global_position) <= explode_radius:
		p.take_damage(explode_damage)
	var hit_b := 0
	for b in get_tree().get_nodes_in_group("building"):
		if b is Node3D and b.has_method("take_damage") \
				and (b as Node3D).global_position.distance_to(global_position) <= explode_radius:
			b.take_damage(explode_damage)
			hit_b += 1
	print("Взрывной взорвался при смерти: AoE урон ", explode_damage, " (построек задето: ", hit_b, ")")
