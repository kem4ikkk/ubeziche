extends "res://scripts/turret.gd"

## Мортирная турель (Этап 4.8.3): навесной огонь по площади.
## В отличие от обычной турели — стреляет реже и тратит больше боезапаса
## за выстрел, но наносит урон всем врагам в радиусе splash_radius вокруг
## цели. Эффективна против скоплений зомби и (как и обычная турель —
## без проверки линии видимости) бьёт даже из-за стен/построек.

@export var splash_radius: float = 3.0
@export var splash_damage: float = 10.0
@export var ammo_cost: int = 2


func _ready() -> void:
	super._ready()
	add_to_group("mortar")


## Залп по площади: центральная цель получает turret_damage,
## остальные враги в splash_radius — splash_damage.
func _try_fire(target: Node3D) -> void:
	if InventorySystem.get_resource("turret_ammo") < ammo_cost:
		return
	InventorySystem.use_resource("turret_ammo", ammo_cost)
	var impact := target.global_position
	var hit_count := 0
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not (enemy is Node3D) or not enemy.has_method("take_damage"):
			continue
		var e := enemy as Node3D
		if e.global_position.distance_to(impact) > splash_radius:
			continue
		e.take_damage(turret_damage if e == target else splash_damage)
		hit_count += 1
	print("Мортира бьёт по площади (накрыто целей: ", hit_count, ")")


func take_damage(amount: float) -> void:
	health.take_damage(amount)
	EventBus.building_damaged.emit("Мортира")


func _on_health_changed(current: float, maximum: float) -> void:
	hp_label.text = "Мортира %d / %d" % [current, maximum]
	var ratio := current / maximum
	if ratio > 0.6:
		hp_label.modulate = Color(0.4, 1.0, 0.4)
	elif ratio > 0.3:
		hp_label.modulate = Color(1.0, 0.85, 0.2)
	else:
		hp_label.modulate = Color(1.0, 0.3, 0.3)
