extends Node
## Режим «прогон для Claude»: сценарий действий + авто-скриншот + дамп состояния.
##
## Включается ТОЛЬКО при запуске с пользовательским аргументом --capture:
##   Godot_..._console.exe --path . -- --capture        (длительность по умолчанию 3 c)
##   Godot_..._console.exe --path . -- --capture 4       (общая длительность 4 c)
##
## Что делает: ждёт инициализацию → логирует состояние → имитирует выстрелы
## вперёд → даёт врагам подойти → снова логирует → делает скриншот → выходит.
## При обычном запуске игры ничего не делает.
## Результат: файл debug/last_run.png + строки "CLAUDE..." в консоли.

const OUT_DIR := "res://debug"
const OUT_FILE := "last_run.png"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--capture"):
		return  # обычный запуск — режим выключен
	await _run_capture(args)


func _run_capture(args: PackedStringArray) -> void:
	var total := 3.0
	var idx := args.find("--capture")
	if idx != -1 and idx + 1 < args.size() and args[idx + 1].is_valid_float():
		total = args[idx + 1].to_float()

	print("CLAUDE: прогон активен (", total, " c): действия + снимок")

	# 1) Даём сцене инициализироваться.
	await get_tree().create_timer(0.5).timeout
	_dump_state("ДО действий")

	# 1.5) Запускаем волну вручную (Этап 3.6: волны теперь стартуют ночью,
	# но в коротком прогоне ждать наступления ночи не успеваем).
	var wave_manager := get_tree().current_scene.get_node_or_null("WaveManager")
	if wave_manager != null and wave_manager.has_method("start_wave"):
		wave_manager.start_wave()

	# 2) Имитируем стрельбу вперёд — проверяем урон и смерть врага.
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.has_method("shoot"):
		print("CLAUDE: имитирую 5 выстрелов вперёд")
		for i in 5:
			player.shoot()
			await get_tree().create_timer(0.2).timeout

	# 3) Даём врагам подойти/поатаковать + ресурсам собраться.
	var rest: float = maxf(total - 2.5, 0.5)
	await get_tree().create_timer(rest).timeout
	_dump_state("ПОСЛЕ выстрелов (враги приближаются)")

	# 4) Телепортируем игрока к ресурсам (для тестирования).
	if is_instance_valid(player) and player is Node3D:
		print("CLAUDE: телепортирую игрока к ресурсам")
		(player as Node3D).global_position = Vector3(5, 1, 5)
		await get_tree().create_timer(0.5).timeout
		_dump_state("ПОСЛЕ телепорта (собираю ресурсы)")

	# 4.5) Патроны и перезарядка (Этап 4.6.1): расстреливаем обойму и
	# проверяем перезарядку — делаем это здесь, в стороне от зомби.
	if is_instance_valid(player) and player.has_method("reload"):
		print("CLAUDE: расстреливаю обойму до конца")
		while player.current_ammo > 0:
			player.shoot()
			await get_tree().create_timer(0.1).timeout
		print("CLAUDE: выстрел при пустой обойме")
		player.shoot()
		print("CLAUDE: перезаряжаюсь")
		player.reload()
		await get_tree().create_timer(player.reload_time + 0.2).timeout
		print("  player_ammo после перезарядки: ", player.current_ammo, " / ", player.magazine_size)

	# 4.6) Виды оружия (Этап 4.6.2): переключаемся на дробовик и проверяем
	# его параметры/обойму, затем возвращаемся на пистолет.
	if is_instance_valid(player) and player.has_method("switch_weapon"):
		print("CLAUDE: переключаюсь на дробовик")
		player.switch_weapon(1)
		print("  оружие: ", player.weapons[player.current_weapon_index].name,
				", урон: ", player.damage, ", обойма: ", player.current_ammo, " / ", player.magazine_size,
				", дальность: ", player.shoot_range)
		print("CLAUDE: выстрел из дробовика")
		player.shoot()
		await get_tree().create_timer(0.1).timeout
		print("  обойма дробовика после выстрела: ", player.current_ammo, " / ", player.magazine_size)
		print("CLAUDE: переключаюсь обратно на пистолет")
		player.switch_weapon(0)
		print("  оружие: ", player.weapons[player.current_weapon_index].name,
				", обойма: ", player.current_ammo, " / ", player.magazine_size)

	# 5) Попробуем скрафтить если достаточно ресурсов.
	if InventorySystem.get_resource("wood") >= 2:
		print("CLAUDE: крафтим стену (2 дерева → 1 стена)")
		CraftSystem.craft("wall")

	_dump_state("ПОСЛЕ крафта")

	# 6) Строим стену (Этап 3.5): включаем режим постройки и ставим стену.
	if is_instance_valid(player) and player.has_node("BuildSystem"):
		var build_system := player.get_node("BuildSystem")
		print("CLAUDE: включаю режим постройки")
		build_system.toggle()
		await get_tree().create_timer(0.3).timeout  # ждём кадр для луча/призрака
		var placed: bool = build_system.try_place()
		print("CLAUDE: построена стена: ", placed)
		await get_tree().create_timer(0.2).timeout

	_dump_state("ПОСЛЕ постройки")

	# 6.5) Повреждаем и ремонтируем стену (Этап 4.3).
	var wall := get_tree().get_first_node_in_group("building")
	if is_instance_valid(wall) and wall.has_method("take_damage"):
		print("CLAUDE: повреждаю стену (-20 HP)")
		wall.take_damage(20.0)
		await get_tree().create_timer(0.2).timeout
		print("CLAUDE: ремонтирую стену")
		if is_instance_valid(player) and player.has_method("repair_target"):
			player.repair_target()
		await get_tree().create_timer(0.2).timeout

	_dump_state("ПОСЛЕ ремонта стены")

	# 6.6) Спавним зомби-танка вручную для проверки (Этап 4.4) — обычно
	# танки появляются с волны 2, но в коротком прогоне до неё не доходит.
	if wave_manager != null and wave_manager.tank_zombie_scene != null:
		print("CLAUDE: спавню зомби-танка для проверки")
		var tank: Node = wave_manager.tank_zombie_scene.instantiate()
		get_tree().current_scene.add_child(tank)
		(tank as Node3D).global_position = Vector3(0, 1, -5)
		await get_tree().create_timer(0.2).timeout
		if tank.has_method("get_health"):
			print("  tank_hp: ", tank.get_health())

	_dump_state("ПОСЛЕ спавна танка")

	# 7) Снимок экрана (ждём отрисовку кадра).
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var abs_path := abs_dir.path_join(OUT_FILE)
	if image.save_png(abs_path) == OK:
		print("CLAUDE_SCREENSHOT: ", abs_path)
	else:
		print("CLAUDE: не удалось сохранить скриншот")

	get_tree().quit()


## Печатает ключевое состояние сцены — это я читаю из консоли.
func _dump_state(label: String) -> void:
	print("CLAUDE_STATE_BEGIN [", label, "]")
	print("  fps: ", Engine.get_frames_per_second())
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		if player is Node3D:
			print("  player_pos: ", (player as Node3D).global_position)
		if player.has_method("get_health"):
			print("  player_hp: ", player.get_health())
		if "current_ammo" in player:
			print("  player_ammo: ", player.current_ammo, " / ", player.magazine_size)
		if "current_weapon_index" in player:
			print("  player_weapon: ", player.weapons[player.current_weapon_index].name)
	else:
		print("  player: (нет)")
	print("  enemies: ", get_tree().get_nodes_in_group("enemy").size())
	print("  buildings: ", get_tree().get_nodes_in_group("building").size())
	var wall := get_tree().get_first_node_in_group("building")
	if is_instance_valid(wall) and wall.has_node("HealthComponent"):
		var wall_health: HealthComponent = wall.get_node("HealthComponent")
		print("  wall_hp: ", wall_health.current_health, " / ", wall_health.max_health)
	var day_night := get_tree().get_first_node_in_group("day_night_cycle")
	if is_instance_valid(day_night):
		var phase: String = "ночь" if day_night.is_night else "день"
		print("  phase: ", phase, " (осталось ", snappedf(day_night.get_phase_time_left(), 0.1), " c)")
	var game_state := get_tree().get_first_node_in_group("game_state_manager")
	if is_instance_valid(game_state):
		print("  game_over: ", game_state.is_game_over, ", paused: ", get_tree().paused)
	# Показываем инвентарь
	for resource_type in InventorySystem.inventory:
		var amount = InventorySystem.inventory[resource_type]
		print("  inventory[%s]: %d" % [resource_type, amount])
	print("CLAUDE_STATE_END")
