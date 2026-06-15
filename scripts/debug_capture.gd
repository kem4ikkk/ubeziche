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

	# 0) Электричество (Этап 4.16) не собирается на карте, а копится медленно
	# от генераторов — выдаём запас сразу, чтобы тесты турелей не зависели
	# от тайминга производства.
	InventorySystem.add_resource("electricity", 20)

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

	# 4.6) Арсенал + покупка оружия (Этап 4.6.2 / 4.7.2): в начале только
	# пистолет; остальное покупается в мастерской по возрастанию цены.
	if is_instance_valid(player) and player.has_method("switch_weapon"):
		print("CLAUDE: пробую переключиться на оружие №2 ДО покупки")
		player.switch_weapon(1)
		print("  текущее оружие (ожидается Пистолет): ", player.weapons[player.current_weapon_index].name)
		print("CLAUDE: покупаю весь арсенал в мастерской")
		InventorySystem.add_money(400)  # в тесте денег мало — добавим на весь арсенал
		var workshop_w := get_tree().get_first_node_in_group("workshop")
		while workshop_w != null:
			var money_before_w := InventorySystem.get_money()
			if not workshop_w.buy_weapon():
				break
			print("  куплено: ", player.weapons[player.current_weapon_index].name,
					" | деньги ", money_before_w, " → ", InventorySystem.get_money(), "$")
		print("CLAUDE: проверяю каждое оружие в арсенале")
		for wi in player.weapons.size():
			player.switch_weapon(wi)
			var w: Dictionary = player.weapons[wi]
			print("  [", wi + 1, "] ", w.name, " — урон ", player.damage,
					", обойма ", player.current_ammo, " / ", player.magazine_size,
					", дальность ", player.shoot_range, ", пуль ", w.get("pellets", 1))
		print("CLAUDE: возвращаюсь на пистолет")
		player.switch_weapon(0)

	# Перед проверкой остальных фич зачищаем оставшихся зомби волны и лечим
	# игрока — иначе он может случайно погибнуть, пока стоит на месте, и
	# проверки дропа/экономики/постройки пойдут на «мёртвой» паузе.
	for enemy in get_tree().get_nodes_in_group("enemy"):
		enemy.queue_free()
	if is_instance_valid(player) and player.has_method("heal"):
		player.heal(1000.0)
	await get_tree().create_timer(0.1).timeout

	# 4.7) Дроп ресурса с зомби (Этап 4.7.1): дроп случайный (drop_chance),
	# поэтому добиваем несколько зомби-танков подряд, пока не выпадет ресурс.
	if wave_manager != null and wave_manager.tank_zombie_scene != null:
		print("CLAUDE: проверяю случайный дроп ресурса (несколько зомби-танков)")
		var drops_found := 0
		for i in 6:
			var tank: Node = wave_manager.tank_zombie_scene.instantiate()
			get_tree().current_scene.add_child(tank)
			(tank as Node3D).global_position = Vector3(0, 1, -8 - i)
			tank.take_damage(1000.0)
			await get_tree().create_timer(0.1).timeout
		for node in get_tree().current_scene.get_children():
			if "resource_type" in node and "resource_amount" in node:
				print("  дроп: ", node.resource_type, " x", node.resource_amount)
				drops_found += 1
		print("  дропов выпало: ", drops_found, " из 6 (шанс 0.5)")

	# 4.8) Двойная экономика + мастерская (Этап 4.7.2 / 4.7.3): деньги капают
	# за убийство зомби, в мастерской их тратим. Методы дёргаем напрямую
	# (в прогоне реальный ввод и зоны не работают).
	print("CLAUDE: проверяю двойную экономику и мастерскую (4.7.2 / 4.7.3)")
	print("  текущий баланс денег: ", InventorySystem.get_money(), "$")
	var workshop := get_tree().get_first_node_in_group("workshop")
	if workshop != null:
		# Крафт стены из ресурсов (даём дерево, чтобы точно хватило).
		InventorySystem.add_resource("wood", 2)
		var wood_before := InventorySystem.get_resource("wood")
		var crafted: bool = workshop.craft_wall()
		print("  крафт стены (ресурсы): ", crafted, " | дерево ", wood_before, " → ",
				InventorySystem.get_resource("wood"), ", стен: ", InventorySystem.get_resource("wall"))
		# Покупка стены за деньги.
		var money_before := InventorySystem.get_money()
		var walls_before := InventorySystem.get_resource("wall")
		var bought: bool = workshop.buy_wall()
		print("  покупка стены за деньги: ", bought, " | деньги ", money_before, " → ",
				InventorySystem.get_money(), "$, стен ", walls_before, " → ", InventorySystem.get_resource("wall"))
		# Лечение за деньги: сначала раним игрока, потом лечим.
		if is_instance_valid(player) and player.has_method("take_damage"):
			player.take_damage(40.0)
		var hp_before: float = player.get_health() if is_instance_valid(player) else 0.0
		var money_before2 := InventorySystem.get_money()
		var healed: bool = workshop.buy_heal()
		var hp_after: float = player.get_health() if is_instance_valid(player) else 0.0
		print("  покупка лечения: ", healed, " | HP ", hp_before, " → ", hp_after,
				", деньги ", money_before2, " → ", InventorySystem.get_money(), "$")
		# Проверяем зону мастерской: подводим игрока вплотную к верстаку.
		if is_instance_valid(player) and player is Node3D:
			(player as Node3D).global_position = Vector3(-3, 1, 3)
			await get_tree().create_timer(0.2).timeout
			if "_player_inside" in workshop:
				print("  игрок в зоне мастерской: ", workshop._player_inside)
	else:
		print("  CLAUDE: мастерская не найдена!")

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

	# 6.55) Индикаторы угроз в HUD (Этап 4.9): повреждение постройки должно
	# показать тревожное сообщение, а волна — оповещения о начале/зачистке.
	var hud := get_tree().get_first_node_in_group("hud")
	if is_instance_valid(wall) and wall.has_method("take_damage") and is_instance_valid(hud):
		print("CLAUDE: проверяю индикатор «постройка под атакой» (4.9)")
		wall.take_damage(5.0)
		await get_tree().create_timer(0.1).timeout
		print("  alert_label.visible: ", hud.alert_label.visible, ", text: '", hud.alert_label.text, "'")
	if wave_manager != null and is_instance_valid(hud):
		print("CLAUDE: проверяю оповещения о волнах (4.9)")
		wave_manager.start_wave()
		await get_tree().create_timer(0.1).timeout
		print("  wave_started alert: '", hud.alert_label.text, "'")
		for enemy in get_tree().get_nodes_in_group("enemy"):
			enemy.queue_free()
		await get_tree().create_timer(0.5).timeout
		print("  wave_cleared alert: '", hud.alert_label.text, "'")

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

	# 6.7) Турель (Этап 4.8.1): выбираем турель в режиме постройки, строим её,
	# покупаем боезапас и проверяем, что она сама стреляет по зомби.
	if is_instance_valid(player) and player.has_node("BuildSystem") and player is Node3D:
		var bs := player.get_node("BuildSystem")
		print("CLAUDE: строю турель")
		InventorySystem.add_resource("wood", 5)
		InventorySystem.add_resource("steel", 5)
		(player as Node3D).global_position = Vector3(0, 1, 5)
		if not bs.build_mode:
			bs.toggle()
		bs.select_buildable("Турель")
		await get_tree().create_timer(0.3).timeout
		print("  выбранная постройка: ", bs.current_buildable_name())
		var placed_turret: bool = bs.try_place()
		print("  турель построена: ", placed_turret)
		if bs.build_mode:
			bs.toggle()
		# Покупаем боезапас турелей в мастерской.
		var workshop_t := get_tree().get_first_node_in_group("workshop")
		InventorySystem.add_money(50)
		if workshop_t != null:
			workshop_t.buy_turret_ammo()
		var ammo_before := InventorySystem.get_resource("turret_ammo")
		print("  боезапас турелей: ", ammo_before)
		# Спавним зомби в зоне действия турели и ждём авто-стрельбу.
		if wave_manager != null and wave_manager.zombie_scene != null:
			var z: Node = wave_manager.zombie_scene.instantiate()
			get_tree().current_scene.add_child(z)
			(z as Node3D).global_position = Vector3(0, 1, -3)
			var hp_before: float = z.get_health() if z.has_method("get_health") else 0.0
			await get_tree().create_timer(2.5).timeout
			var hp_after := -1.0
			if is_instance_valid(z) and z.has_method("get_health"):
				hp_after = z.get_health()
			print("  цель турели: HP ", hp_before, " → ", hp_after, " (-1 = уничтожена)")
		print("  боезапас после стрельбы: ", ammo_before, " → ", InventorySystem.get_resource("turret_ammo"))
		_dump_state("ПОСЛЕ турели")

	# 6.8) Лазарет и склад (Этап 4.8.2): строим оба и проверяем, что лазарет
	# лечит игрока рядом, а склад со временем пополняет боезапас турелей.
	if is_instance_valid(player) and player.has_node("BuildSystem") and player is Node3D:
		var bs2 := player.get_node("BuildSystem")
		# Чистим врагов, чтобы турель не тратила боезапас во время проверки склада.
		for enemy in get_tree().get_nodes_in_group("enemy"):
			enemy.queue_free()
		InventorySystem.add_resource("wood", 10)
		InventorySystem.add_resource("steel", 10)
		# --- Лазарет ---
		print("CLAUDE: строю лазарет")
		(player as Node3D).global_position = Vector3(6, 1, 5)
		if not bs2.build_mode:
			bs2.toggle()
		bs2.select_buildable("Лазарет")
		await get_tree().create_timer(0.3).timeout
		var placed_inf: bool = bs2.try_place()
		print("  лазарет построен: ", placed_inf, " (выбрано: ", bs2.current_buildable_name(), ")")
		# Раним игрока и ставим его вплотную к лазарету — должен лечить.
		if player.has_method("take_damage"):
			player.take_damage(40.0)
		var hp_before_heal: float = player.get_health()
		(player as Node3D).global_position = Vector3(6, 1, 3)
		await get_tree().create_timer(1.5).timeout
		print("  лазарет лечит: HP ", hp_before_heal, " → ", player.get_health())
		# --- Склад ---
		print("CLAUDE: строю склад боеприпасов")
		bs2.select_buildable("Склад")
		await get_tree().create_timer(0.3).timeout
		var placed_st: bool = bs2.try_place()
		print("  склад построен: ", placed_st, " (выбрано: ", bs2.current_buildable_name(), ")")
		if bs2.build_mode:
			bs2.toggle()
		# Убираем турели на время замера склада, чтобы они не тратили боезапас
		# (их работу уже проверили выше) — так виден чистый прирост от склада.
		for turret in get_tree().get_nodes_in_group("turret"):
			turret.queue_free()
		for enemy in get_tree().get_nodes_in_group("enemy"):
			enemy.queue_free()
		var ammo_before_storage := InventorySystem.get_resource("turret_ammo")
		await get_tree().create_timer(4.5).timeout  # ждём ~2 тика склада
		print("  склад пополняет боезапас: ", ammo_before_storage, " → ", InventorySystem.get_resource("turret_ammo"))
		_dump_state("ПОСЛЕ лазарета и склада")

	# 6.9) Джаггернаут (Этап 4.10): мини-босс с большим HP, целящийся в
	# постройки, но переключающийся на игрока в радиусе аггро (риск/выгода).
	if wave_manager != null and wave_manager.juggernaut_scene != null and is_instance_valid(player) and player is Node3D:
		print("CLAUDE: проверяю джаггернаута (4.10)")
		# Чистим сцену от прочих врагов и построек, лечим игрока — нужна
		# детерминированная проверка цели мини-босса.
		for enemy in get_tree().get_nodes_in_group("enemy"):
			enemy.queue_free()
		for b in get_tree().get_nodes_in_group("building"):
			b.queue_free()
		if player.has_method("heal"):
			player.heal(1000.0)
		await get_tree().create_timer(0.1).timeout
		# Игрока — далеко (вне радиуса аггро), чтобы босс целился в постройку.
		(player as Node3D).global_position = Vector3(-8, 1, 8)
		var jugg: Node = wave_manager.juggernaut_scene.instantiate()
		get_tree().current_scene.add_child(jugg)
		(jugg as Node3D).global_position = Vector3(6, 1, -6)
		await get_tree().create_timer(0.1).timeout
		print("  juggernaut_hp: ", jugg.get_health() if jugg.has_method("get_health") else -1.0)
		if is_instance_valid(hud):
			print("  HUD при спавне джаггернаута: '", hud.alert_label.text, "'")
		# Стена рядом с боссом (но далеко от игрока) — он должен её крушить.
		var wall_scene := load("res://scenes/wall.tscn")
		var jwall: Node = wall_scene.instantiate()
		get_tree().current_scene.add_child(jwall)
		(jwall as Node3D).global_position = Vector3(6, 0.5, -3)
		var jwall_hp_before := -1.0
		if jwall.has_node("HealthComponent"):
			jwall_hp_before = jwall.get_node("HealthComponent").current_health
		await get_tree().create_timer(3.0).timeout
		var jwall_hp_after := -1.0
		if is_instance_valid(jwall) and jwall.has_node("HealthComponent"):
			jwall_hp_after = jwall.get_node("HealthComponent").current_health
		print("  стена под атакой босса (игрок далеко): HP ", jwall_hp_before, " → ", jwall_hp_after)
		# Механика аггро: ставим игрока вплотную — босс переключается на него.
		var php_before: float = player.get_health()
		if is_instance_valid(jugg):
			(player as Node3D).global_position = (jugg as Node3D).global_position + Vector3(2, 0, 0)
			await get_tree().create_timer(2.0).timeout
		print("  игрок подошёл вплотную: HP ", php_before, " → ", player.get_health(), " (босс переключился на игрока)")
		# Добиваем мини-босса — проверяем награду и оповещение.
		var money_before_j := InventorySystem.get_money()
		if is_instance_valid(jugg) and jugg.has_method("take_damage"):
			jugg.take_damage(1000.0)
			await get_tree().create_timer(0.2).timeout
		print("  деньги за джаггернаута: ", money_before_j, " → ", InventorySystem.get_money(), "$")
		if is_instance_valid(hud):
			print("  HUD при гибели джаггернаута: '", hud.alert_label.text, "'")
		if player.has_method("heal"):
			player.heal(1000.0)  # лечим, чтобы игрок не погиб до снимка
		_dump_state("ПОСЛЕ джаггернаута")

	# 6.94) Тиры убежища (Этап 4.15): апгрейд через мастерскую открывает
	# доступ к более продвинутым турелям (Мортира — Тир 2, Гатлинг — Тир 3)
	# и улучшает генератор (Тир 4 — вдвое медленнее тратит топливо).
	if is_instance_valid(player) and player.has_node("BuildSystem") and player is Node3D:
		print("CLAUDE: проверяю систему тиров (4.15)")
		var bs_t := player.get_node("BuildSystem")
		var workshop_t := get_tree().get_first_node_in_group("workshop")
		print("  стартовый тир: ", InventorySystem.shelter_tier)

		for b in get_tree().get_nodes_in_group("building"):
			b.queue_free()
		InventorySystem.add_resource("wood", 200)
		InventorySystem.add_resource("steel", 200)
		InventorySystem.add_money(1000)
		(player as Node3D).global_position = Vector3(0, 1, 5)
		if not bs_t.build_mode:
			bs_t.toggle()

		bs_t.select_buildable("Мортира")
		await get_tree().create_timer(0.3).timeout
		var placed_t1: bool = bs_t.try_place()
		print("  мортира на Тир 1: ", placed_t1, " (ожидается false)")

		var up2: bool = workshop_t.upgrade_shelter_tier()
		print("  апгрейд до Тир 2: ", up2, ", текущий тир: ", InventorySystem.shelter_tier)

		var placed_t2: bool = bs_t.try_place()
		print("  мортира на Тир 2: ", placed_t2, " (ожидается true)")
		for m in get_tree().get_nodes_in_group("building"):
			m.queue_free()

		bs_t.select_buildable("Гатлинг")
		await get_tree().create_timer(0.3).timeout
		var placed_g2: bool = bs_t.try_place()
		print("  гатлинг на Тир 2: ", placed_g2, " (ожидается false)")

		var up3: bool = workshop_t.upgrade_shelter_tier()
		print("  апгрейд до Тир 3: ", up3, ", текущий тир: ", InventorySystem.shelter_tier)
		var placed_g3: bool = bs_t.try_place()
		print("  гатлинг на Тир 3: ", placed_g3, " (ожидается true)")
		for b in get_tree().get_nodes_in_group("building"):
			b.queue_free()

		var up4: bool = workshop_t.upgrade_shelter_tier()
		print("  апгрейд до Тир 4: ", up4, ", текущий тир: ", InventorySystem.shelter_tier)
		var up5: bool = workshop_t.upgrade_shelter_tier()
		print("  апгрейд за пределами максимума: ", up5, " (ожидается false), тир: ", InventorySystem.shelter_tier)
		if is_instance_valid(hud):
			print("  HUD: '", hud.tier_label.text, "', алерт: '", hud.alert_label.text, "'")

		if bs_t.build_mode:
			bs_t.toggle()
		_dump_state("ПОСЛЕ тиров")

	# 6.95) Мортирная турель (Этап 4.8.3): строим мортиру, спавним кучку
	# зомби рядом друг с другом — выстрел мортиры должен задеть всех
	# сплеш-уроном (по площади), а не только ближайшую цель.
	if is_instance_valid(player) and player.has_node("BuildSystem") and player is Node3D:
		print("CLAUDE: проверяю мортиру (4.8.3)")
		for enemy in get_tree().get_nodes_in_group("enemy"):
			enemy.queue_free()
		for b in get_tree().get_nodes_in_group("building"):
			b.queue_free()
		var bs3 := player.get_node("BuildSystem")
		InventorySystem.add_resource("wood", 10)
		InventorySystem.add_resource("steel", 10)
		InventorySystem.add_resource("turret_ammo", 10)
		(player as Node3D).global_position = Vector3(0, 1, 5)
		if not bs3.build_mode:
			bs3.toggle()
		bs3.select_buildable("Мортира")
		await get_tree().create_timer(0.3).timeout
		var placed_mortar: bool = bs3.try_place()
		print("  мортира построена: ", placed_mortar, " (выбрано: ", bs3.current_buildable_name(), ")")
		if bs3.build_mode:
			bs3.toggle()
		# Кучка зомби рядом друг с другом — все должны попасть в сплеш-радиус.
		var hp_list_before: Array = []
		var cluster: Array = []
		if wave_manager != null and wave_manager.zombie_scene != null:
			for offset in [Vector3(0, 1, -5), Vector3(1, 1, -5), Vector3(-1, 1, -5)]:
				var zc: Node = wave_manager.zombie_scene.instantiate()
				get_tree().current_scene.add_child(zc)
				(zc as Node3D).global_position = offset
				cluster.append(zc)
				hp_list_before.append(zc.get_health() if zc.has_method("get_health") else 0.0)
		print("  HP кучки до выстрела: ", hp_list_before)
		await get_tree().create_timer(3.0).timeout
		var hp_list_after: Array = []
		for zc in cluster:
			hp_list_after.append(zc.get_health() if is_instance_valid(zc) and zc.has_method("get_health") else -1.0)
		print("  HP кучки после мортиры: ", hp_list_after, " (-1 = уничтожен)")
		print("  боезапас после: ", InventorySystem.get_resource("turret_ammo"))
		_dump_state("ПОСЛЕ мортиры")

	# 6.96) Гатлинг-турель (Этап 4.8.4): разнообразие турелей — дешёвая ранняя
	# «Турель» против дорогой «Гатлинг» с намного более высокой скоростью
	# стрельбы (и расходом боезапаса). Сравниваем DPS по одной цели.
	if is_instance_valid(player) and player.has_node("BuildSystem") and player is Node3D:
		print("CLAUDE: проверяю гатлинг-турель (4.8.4)")
		for enemy in get_tree().get_nodes_in_group("enemy"):
			enemy.queue_free()
		for b in get_tree().get_nodes_in_group("building"):
			b.queue_free()
		var bs4 := player.get_node("BuildSystem")
		InventorySystem.add_resource("wood", 10)
		InventorySystem.add_resource("steel", 15)
		InventorySystem.add_resource("turret_ammo", 20)
		(player as Node3D).global_position = Vector3(0, 1, 5)
		if not bs4.build_mode:
			bs4.toggle()
		bs4.select_buildable("Гатлинг")
		await get_tree().create_timer(0.3).timeout
		var placed_gatling: bool = bs4.try_place()
		print("  гатлинг построен: ", placed_gatling, " (выбрано: ", bs4.current_buildable_name(), ")")
		if bs4.build_mode:
			bs4.toggle()
		var ammo_before_g := InventorySystem.get_resource("turret_ammo")
		# Одна цель в зоне действия — за 1 секунду гатлинг успевает выстрелить
		# заметно чаще, чем обычная турель (интервал 0.3с против 0.8с).
		if wave_manager != null and wave_manager.zombie_scene != null:
			var zg: Node = wave_manager.zombie_scene.instantiate()
			get_tree().current_scene.add_child(zg)
			(zg as Node3D).global_position = Vector3(0, 1, -5)
			var hp_before_g: float = zg.get_health() if zg.has_method("get_health") else 0.0
			await get_tree().create_timer(1.0).timeout
			var hp_after_g := -1.0
			if is_instance_valid(zg) and zg.has_method("get_health"):
				hp_after_g = zg.get_health()
			print("  цель гатлинга за 1с: HP ", hp_before_g, " → ", hp_after_g, " (-1 = уничтожена)")
		print("  боезапас: ", ammo_before_g, " → ", InventorySystem.get_resource("turret_ammo"))
		_dump_state("ПОСЛЕ гатлинга")

	# 6.97) Система питания (Этап 4.14, переработана в 4.16): генераторы
	# производят электричество (InventorySystem "electricity"), турели его
	# тратят за выстрел. Без электричества/генератора турели простаивают
	# (метка "нет питания"), при восстановлении питания — снова стреляют.
	if is_instance_valid(player) and player.has_node("BuildSystem") and player is Node3D \
			and wave_manager != null and wave_manager.zombie_scene != null:
		print("CLAUDE: проверяю систему питания (4.14)")
		for enemy in get_tree().get_nodes_in_group("enemy"):
			enemy.queue_free()
		for t in get_tree().get_nodes_in_group("turret"):
			t.queue_free()
		var bs5 := player.get_node("BuildSystem")
		InventorySystem.add_resource("wood", 10)
		InventorySystem.add_resource("steel", 10)
		InventorySystem.add_resource("turret_ammo", 20)
		(player as Node3D).global_position = Vector3(0, 1, 5)
		if not bs5.build_mode:
			bs5.toggle()
		bs5.select_buildable("Турель")
		await get_tree().create_timer(0.3).timeout
		var placed_turret2: bool = bs5.try_place()
		print("  турель построена: ", placed_turret2)
		if bs5.build_mode:
			bs5.toggle()
		var turret_node := get_tree().get_first_node_in_group("turret")

		# Предустановленный генератор могли снести в предыдущих тестах
		# (например, 6.9 чистит все "building") — отстраиваем заново.
		if get_tree().get_nodes_in_group("generator").is_empty():
			if not bs5.build_mode:
				bs5.toggle()
			bs5.select_buildable("Генератор")
			await get_tree().create_timer(0.3).timeout
			var placed_gen: bool = bs5.try_place()
			print("  генератор отстроен заново: ", placed_gen)
			if bs5.build_mode:
				bs5.toggle()
		# Электричество не собирается на карте — выдаём напрямую для теста.
		InventorySystem.add_resource("electricity", 20)
		print("  электричество: ", InventorySystem.get_resource("electricity"),
				", генераторов в сцене: ", get_tree().get_nodes_in_group("generator").size())

		# С питанием — турель должна навестись и стрелять.
		var zp: Node = wave_manager.zombie_scene.instantiate()
		get_tree().current_scene.add_child(zp)
		(zp as Node3D).global_position = Vector3(0, 1, -3)
		var hp_p_before: float = zp.get_health() if zp.has_method("get_health") else 0.0
		await get_tree().create_timer(1.0).timeout
		var hp_p_after: float = zp.get_health() if is_instance_valid(zp) and zp.has_method("get_health") else -1.0
		print("  с питанием: HP цели ", hp_p_before, " → ", hp_p_after,
				", power_label.visible: ", turret_node.power_label.visible if is_instance_valid(turret_node) else "?")
		if is_instance_valid(zp):
			zp.queue_free()

		# Отключаем питание: электричество в ноль.
		InventorySystem.inventory["electricity"] = 0
		InventorySystem.inventory_changed.emit(InventorySystem.inventory)
		var zn: Node = wave_manager.zombie_scene.instantiate()
		get_tree().current_scene.add_child(zn)
		(zn as Node3D).global_position = Vector3(0, 1, -3)
		var hp_n_before: float = zn.get_health() if zn.has_method("get_health") else 0.0
		await get_tree().create_timer(1.0).timeout
		var hp_n_after: float = zn.get_health() if is_instance_valid(zn) and zn.has_method("get_health") else -1.0
		print("  без электричества: HP цели ", hp_n_before, " → ", hp_n_after,
				", power_label.visible: ", turret_node.power_label.visible if is_instance_valid(turret_node) else "?")
		if is_instance_valid(hud):
			print("  HUD alert при отключении питания: '", hud.alert_label.text, "'")
		if is_instance_valid(zn):
			zn.queue_free()

		# Восстанавливаем электричество — турель снова должна стрелять.
		InventorySystem.add_resource("electricity", 20)
		var zr: Node = wave_manager.zombie_scene.instantiate()
		get_tree().current_scene.add_child(zr)
		(zr as Node3D).global_position = Vector3(0, 1, -3)
		var hp_r_before: float = zr.get_health() if zr.has_method("get_health") else 0.0
		await get_tree().create_timer(1.0).timeout
		var hp_r_after: float = zr.get_health() if is_instance_valid(zr) and zr.has_method("get_health") else -1.0
		print("  электричество восстановлено: HP цели ", hp_r_before, " → ", hp_r_after,
				", power_label.visible: ", turret_node.power_label.visible if is_instance_valid(turret_node) else "?")
		if is_instance_valid(hud):
			print("  HUD alert при восстановлении питания: '", hud.alert_label.text, "'")
		_dump_state("ПОСЛЕ системы питания")

	# 6.98) Молот (Этап 4.17): крафтится один раз в мастерской и удваивает
	# восстановление HP за ремонт (F). Проверяем крафт и эффект на стене.
	var workshop_h := get_tree().get_first_node_in_group("workshop")
	if is_instance_valid(player) and player is Node3D and is_instance_valid(workshop_h):
		print("CLAUDE: проверяю молот (4.17)")
		# Игрок мог погибнуть в предыдущих тестах — лечим и снимаем паузу,
		# иначе ремонт/постройка не сработают.
		if player.has_method("heal"):
			player.heal(1000.0)
		get_tree().paused = false
		InventorySystem.has_hammer = false
		InventorySystem.add_resource("wood", 20)
		InventorySystem.add_resource("steel", 20)
		InventorySystem.add_money(100)
		(player as Node3D).global_position = Vector3(-3, 1, 3)
		await get_tree().create_timer(0.2).timeout
		var crafted_hammer: bool = workshop_h.craft_hammer()
		print("  молот скрафчен: ", crafted_hammer, ", has_hammer: ", InventorySystem.has_hammer)

		# Строим стену рядом, ломаем её и проверяем ремонт x2.
		if player.has_node("BuildSystem"):
			var bs_h := player.get_node("BuildSystem")
			for b in get_tree().get_nodes_in_group("building"):
				b.queue_free()
			InventorySystem.add_resource("wall", 1)
			(player as Node3D).global_position = Vector3(0, 1, 5)
			if not bs_h.build_mode:
				bs_h.toggle()
			bs_h.select_buildable("Стена")
			await get_tree().create_timer(0.3).timeout
			bs_h.try_place()
			if bs_h.build_mode:
				bs_h.toggle()
			var wall_h := get_tree().get_first_node_in_group("building")
			if is_instance_valid(wall_h) and wall_h.has_method("take_damage"):
				wall_h.take_damage(40.0)
				await get_tree().create_timer(0.2).timeout
				var hp_before_h: float = wall_h.health.current_health
				InventorySystem.add_resource("wood", 1)
				player.repair_target()
				await get_tree().create_timer(0.1).timeout
				var hp_after_h: float = wall_h.health.current_health
				print("  ремонт с молотом: HP ", hp_before_h, " → ", hp_after_h,
						" (ожидается +", player.repair_amount * 2.0, ")")
		_dump_state("ПОСЛЕ молота")

	# 6.99) Топор как стартовый инструмент (Этап 4.21): ЛКМ с топором —
	# добыча/ремонт/ближний бой. Проверяем экипировку, бесплатный ремонт и
	# удар по зомби.
	if is_instance_valid(player) and player is Node3D:
		print("CLAUDE: проверяю топор (4.21)")
		if player.has_method("heal"):
			player.heal(1000.0)
		get_tree().paused = false
		# Убираем оставшихся зомби, чтобы они не добивали стену во время замера ремонта.
		for e0 in get_tree().get_nodes_in_group("enemy"):
			e0.queue_free()
		# Экипировка: на старте топор; берём ствол → топор убран; Q → снова топор.
		print("  axe_equipped на старте: ", player.axe_equipped)
		player.switch_weapon(0)
		print("  после взятия ствола axe_equipped: ", player.axe_equipped)
		player.equip_axe()
		print("  после Q axe_equipped: ", player.axe_equipped)
		# У топора нет патронов/перезарядки: R при топоре не восполняет патроны.
		player.current_ammo = 3
		player.reload()
		await get_tree().create_timer(0.1).timeout
		print("  reload с топором: патроны 3 → ", player.current_ammo, " (не должны восполниться)")

		# Бесплатный ремонт ударом топора: строим стену, ломаем, чиним.
		if player.has_node("BuildSystem"):
			var bs_a := player.get_node("BuildSystem")
			for b in get_tree().get_nodes_in_group("building"):
				b.queue_free()
			InventorySystem.has_hammer = false
			InventorySystem.add_resource("wall", 1)
			(player as Node3D).global_position = Vector3(0, 1, 5)
			if not bs_a.build_mode:
				bs_a.toggle()
			bs_a.select_buildable("Стена")
			await get_tree().create_timer(0.3).timeout
			bs_a.try_place()
			if bs_a.build_mode:
				bs_a.toggle()
			var wall_a := get_tree().get_first_node_in_group("building")
			if is_instance_valid(wall_a) and wall_a.has_method("take_damage"):
				wall_a.take_damage(40.0)
				await get_tree().create_timer(0.1).timeout
				var hp_a0: float = wall_a.health.current_health
				var wood_a0: int = InventorySystem.get_resource("wood")
				player.swing_axe()   # игрок рядом — чинит ближайшую постройку бесплатно
				await get_tree().create_timer(0.1).timeout
				print("  ремонт топором: HP ", hp_a0, " → ", wall_a.health.current_health,
						" (+", player.repair_amount, "); дерево ", wood_a0, " → ",
						InventorySystem.get_resource("wood"), " (не должно убавиться)")

		# Ближний бой топором: ставим свежего зомби прямо перед камерой (-Z).
		for e in get_tree().get_nodes_in_group("enemy"):
			e.queue_free()
		await get_tree().create_timer(0.1).timeout
		var zombie_scene: PackedScene = load("res://scenes/zombie.tscn")
		if zombie_scene != null:
			var z := zombie_scene.instantiate()
			get_tree().current_scene.add_child(z)
			(z as Node3D).global_position = (player as Node3D).global_position + Vector3(0, 0.6, -1.5)
			await get_tree().create_timer(0.1).timeout
			var zhp0: float = -1.0
			if z.has_node("HealthComponent"):
				zhp0 = (z.get_node("HealthComponent") as HealthComponent).current_health
			player.swing_axe()
			await get_tree().create_timer(0.1).timeout
			if is_instance_valid(z) and z.has_node("HealthComponent"):
				print("  удар топором по зомби: HP ", zhp0, " → ",
						(z.get_node("HealthComponent") as HealthComponent).current_health,
						" (урон топора ", player.axe_damage, ")")
			else:
				print("  удар топором по зомби: цель уничтожена (урон ", player.axe_damage, ")")
		_dump_state("ПОСЛЕ топора (4.21)")

	# 6.991) Добыча топором (Этап 4.22): узлы дерева/стали бьются топором,
	# за удар дают gather_level ресурса из запаса; запас кончился — истощены
	# до дневного регена.
	var rnode := get_tree().get_first_node_in_group("resource_node")
	if is_instance_valid(rnode) and rnode.has_method("hit"):
		print("CLAUDE: проверяю добычу топором (4.22)")
		get_tree().paused = false
		rnode.reserve = rnode.max_reserve
		rnode._set_depleted(false)
		var rtype: String = rnode.resource_type
		var before1: int = InventorySystem.get_resource(rtype)
		InventorySystem.gather_level = 1
		var got1: int = rnode.hit()
		print("  удар (навык 1): +", got1, " (", rtype, "), запас ", rnode.reserve, "/", rnode.max_reserve)
		InventorySystem.gather_level = 3
		var got3: int = rnode.hit()
		print("  удар (навык 3): +", got3, ", запас ", rnode.reserve)
		# Вычерпываем узел до истощения.
		var safety := 0
		while rnode.hit() > 0 and safety < 100:
			safety += 1
		print("  после вычерпывания: истощён=", rnode._depleted, ", запас ", rnode.reserve, ", hit()=", rnode.hit())
		# Дневной реген: эмулируем наступление дня.
		rnode._on_phase_changed(false)
		print("  после дневного регена: истощён=", rnode._depleted, ", запас ", rnode.reserve)
		print("  всего добыто ", rtype, ": ", before1, " → ", InventorySystem.get_resource(rtype))

		# Интеграция: swing_axe ловит узел лучом камеры и добывает.
		var cam := player.get_node_or_null("Camera3D")
		if player is Node3D and cam != null:
			rnode.reserve = rnode.max_reserve
			rnode._set_depleted(false)
			InventorySystem.gather_level = 2
			(player as Node3D).global_position = Vector3(20, 1, 20)
			player.equip_axe()
			await get_tree().create_timer(0.1).timeout
			# Ставим узел точно на луч камеры (вперёд по -Z от камеры), чтобы попасть.
			var cam3d := cam as Node3D
			(rnode as Node3D).global_position = cam3d.global_position + (-cam3d.global_transform.basis.z) * 1.5
			await get_tree().create_timer(0.1).timeout
			var rb: int = InventorySystem.get_resource(rnode.resource_type)
			player.swing_axe()
			await get_tree().create_timer(0.1).timeout
			print("  swing_axe по узлу (навык 2): +", InventorySystem.get_resource(rnode.resource_type) - rb)
		_dump_state("ПОСЛЕ добычи (4.22)")

	# 6.992) Навыки (Этап 4.23): очки (3 на старте, +1 за пережитую ночь),
	# ветки Добыча/Бой/Инженер; меню по клавише N.
	if true:
		print("CLAUDE: проверяю навыки (4.23)")
		get_tree().paused = false
		# Сброс к стартовому состоянию для чистоты замера.
		InventorySystem.skill_points = 3
		InventorySystem.gather_level = 1
		InventorySystem.combat_level = 0
		InventorySystem.engineer_level = 0
		print("  старт: очки=", InventorySystem.skill_points, " Добыча=", InventorySystem.gather_level)
		InventorySystem.upgrade_skill("gather")
		InventorySystem.upgrade_skill("combat")
		print("  после вложений: очки=", InventorySystem.skill_points,
				" Добыча=", InventorySystem.gather_level, " Бой=", InventorySystem.combat_level)
		# Третье вложение тратит последнее очко, четвёртое не должно пройти.
		InventorySystem.upgrade_skill("engineer")
		var up_fail: bool = InventorySystem.upgrade_skill("engineer")
		print("  очки=", InventorySystem.skill_points, " Инженер=", InventorySystem.engineer_level,
				" лишнее вложение прошло: ", up_fail)
		# Очко за пережитую ночь.
		EventBus.night_survived.emit()
		print("  после пережитой ночи: очки=", InventorySystem.skill_points)
		# Меню навыков (N) — переключение видимости.
		var sm := get_tree().get_first_node_in_group("skill_menu")
		if is_instance_valid(sm) and sm.has_method("toggle"):
			sm.toggle()
			print("  меню навыков открыто: ", sm.visible)
			sm.toggle()
			print("  меню навыков закрыто: ", sm.visible)
			# Оставляем открытым для финального скриншота (визуальная проверка UI).
			sm.toggle()
		_dump_state("ПОСЛЕ навыков (4.23)")

	# 6.10) Эвакуация как условие победы (Этап 4.11): после N волн вызывается
	# транспорт — игрок должен добежать до зоны эвакуации, иначе поражение.
	var game_state := get_tree().get_first_node_in_group("game_state_manager")
	var evac_zone := get_tree().get_first_node_in_group("evacuation_zone")
	if is_instance_valid(game_state) and is_instance_valid(evac_zone) and is_instance_valid(player) and player is Node3D and not game_state.is_game_over:
		print("CLAUDE: проверяю эвакуацию (4.11)")
		# Чистим врагов и лечим игрока, чтобы он не погиб во время теста.
		for enemy in get_tree().get_nodes_in_group("enemy"):
			enemy.queue_free()
		if player.has_method("heal"):
			player.heal(1000.0)
		# Симулируем зачистку финальной волны — должна начаться эвакуация.
		print("  зона до вызова транспорта видима: ", (evac_zone as Node3D).visible)
		game_state._on_wave_cleared(game_state.victory_waves)
		await get_tree().create_timer(0.1).timeout
		print("  evac_active: ", game_state.evac_active, ", осталось ", snappedf(game_state.get_evac_time_left(), 0.1), " c")
		print("  зона эвакуации видима: ", (evac_zone as Node3D).visible)
		if is_instance_valid(hud):
			print("  HUD alert при вызове транспорта: '", hud.alert_label.text, "'")
			print("  HUD evac_label: '", hud.evac_label.text, "', видим: ", hud.evac_label.visible)
		# Игрок добегает до зоны эвакуации — должна сработать победа.
		(player as Node3D).global_position = (evac_zone as Node3D).global_position + Vector3(0, 1, 0)
		await get_tree().create_timer(0.3).timeout
		var result_text: String = hud.result_label.text if is_instance_valid(hud) else "?"
		print("  после входа в зону: game_over=", game_state.is_game_over, ", HUD итог: '", result_text, "'")
		_dump_state("ПОСЛЕ эвакуации")

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
	print("  money: ", InventorySystem.money, "$")
	print("CLAUDE_STATE_END")
