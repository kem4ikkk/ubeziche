extends Node3D

## Костёр (Этап 4.12c): ПОСТРОЙКА — ставится через меню построек B (build_system),
## а не способностью. Пока игрок в радиусе — лечит его (реген HP/с). По умолчанию
## постоянный (lifetime <= 0). Если lifetime > 0 — гаснет через это время.

@export var heal_per_sec: float = 6.0
@export var radius: float = 4.0
@export var lifetime: float = 0.0   # 0 = постоянный (постройка)
@export var sanity_per_sec: float = 8.0   # бонус психздоровья у костра (Этап 1B)

var _age: float = 0.0


func _ready() -> void:
	add_to_group("campfire")


func _process(delta: float) -> void:
	if lifetime > 0.0:
		_age += delta
		if _age >= lifetime:
			queue_free()
			return
	var p := get_tree().get_first_node_in_group("player")
	if is_instance_valid(p) and p is Node3D and p.has_method("heal") \
			and (p as Node3D).global_position.distance_to(global_position) <= radius:
		# Навык «Походный костёр» усиливает костёр (HP и психздоровье), Этап 1B/4.40.
		var mult: float = 1.6 if InventorySystem.get_skill_level("campfire_skill") > 0 else 1.0
		p.heal(heal_per_sec * mult * delta)
		# Костёр греет (психздоровье). Игрок уже считает костёр «теплом», это —
		# дополнительный бонус восстановления (а с навыком — ещё быстрее).
		if p.has_method("add_sanity"):
			p.add_sanity(sanity_per_sec * mult * delta)
