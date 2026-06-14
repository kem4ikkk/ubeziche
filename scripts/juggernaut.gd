extends "res://scripts/zombie.gd"

## Джаггернаут (Этап 4.10) — мини-босс, целящийся в постройки.
## В отличие от обычного зомби/танка (см. zombie.gd) его поведение особое:
##   • активно идёт к ближайшей постройке игрока (баррикаде/турели/зданию)
##     в любой точке карты и крушит её тяжёлыми ударами;
##   • но если игрок подходит близко (в радиусе aggro_radius) — переключается
##     на игрока (механика риск/выгода: можно отвести босса от баррикады,
##     встав рядом, но при этом самому получить тяжёлый урон);
##   • если построек игрока нет — просто преследует игрока, как обычный зомби.
## HP/урон/скорость/радиусы заданы в scenes/juggernaut.tscn.

## Радиус, в котором игрок «притягивает» джаггернаута на себя, отвлекая его
## от построек (Этап 4.10: механика риск/выгода).
@export var aggro_radius: float = 6.0


func _ready() -> void:
	super._ready()  # группа "enemy", подписка на смерть, поиск игрока
	add_to_group("juggernaut")
	# Оповещаем HUD о прорыве мини-босса (индикатор угрозы, см. Этап 4.9).
	EventBus.juggernaut_spawned.emit()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	# Сцена могла перезагрузиться (смерть игрока) в этом же кадре.
	if not is_inside_tree():
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	# Игрок ещё не найден, погиб или сцена перезагружается — стоим, ищем заново.
	if not is_instance_valid(_player) or not _player.is_inside_tree():
		_player = get_tree().get_first_node_in_group("player") as Node3D
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var player_dist := to_player.length()

	# Выбор цели: игрок рядом (или построек нет) → бьём игрока; иначе крушим
	# ближайшую постройку.
	var building := _find_nearest_building_anywhere()
	if player_dist <= aggro_radius or not is_instance_valid(building):
		_chase_and_attack(_player, to_player, player_dist, attack_range, attack_damage, false, delta)
	else:
		var to_building := building.global_position - global_position
		to_building.y = 0.0
		_chase_and_attack(building, to_building, to_building.length(), building_attack_range, building_attack_damage, true, delta)

	move_and_slide()


## Идём к цели и бьём по кулдауну, когда вошли в радиус удара.
func _chase_and_attack(target: Node3D, to_target: Vector3, dist: float, hit_range: float, hit_damage: float, is_building: bool, delta: float) -> void:
	if dist > hit_range:
		var dir := to_target.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		if dist > 0.01:
			look_at(global_position + dir, Vector3.UP)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_attack_timer = attack_cooldown
			if is_instance_valid(target) and target.has_method("take_damage"):
				target.take_damage(hit_damage)
				if is_building:
					print("Джаггернаут крушит постройку (-", hit_damage, " HP)")
				else:
					print("Джаггернаут атакует игрока (-", hit_damage, " HP)")


## Ближайшая постройка игрока (группа "building") в любой точке карты.
## Джаггернаут целенаправленно идёт её ломать — в отличие от обычного зомби,
## который атакует постройку, лишь упёршись в неё на пути к игроку.
func _find_nearest_building_anywhere() -> Node3D:
	var nearest: Node3D = null
	var nearest_dist := INF
	for node in get_tree().get_nodes_in_group("building"):
		if not (node is Node3D) or not node.has_method("take_damage"):
			continue
		var d: float = (node as Node3D).global_position.distance_to(global_position)
		if d < nearest_dist:
			nearest = node
			nearest_dist = d
	return nearest


func _on_died() -> void:
	_dead = true
	print("Джаггернаут повержен!")
	InventorySystem.add_money(money_reward)  # большая награда за мини-босса
	_drop_resource()
	EventBus.juggernaut_defeated.emit()
	queue_free()
