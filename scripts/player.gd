extends CharacterBody3D

## Простой контроллер игрока от первого лица.
## Управление:
##   WASD  — движение
##   Мышь  — обзор
##   Space — прыжок
##   ЛКМ   — выстрел (если курсор захвачен) / захватить курсор
##   R     — перезарядка оружия
##   F     — отремонтировать ближайшую постройку (1 дерево → +15 HP)
##   1-5   — переключить оружие (только купленное; в начале есть лишь пистолет)
##   Esc   — отпустить курсор
## Крафт и магазин (клавиши C / G / H / J) теперь работают только рядом с
## мастерской — см. scripts/workshop.gd (Этап 4.7.3). Оружие покупается там же.

signal ammo_changed(current: int, magazine: int)
signal weapon_changed(weapon_name: String)

# Параметры можно менять прямо в редакторе (значок справа от ноды).
@export var speed: float = 5.0            # скорость бега, м/с
@export var jump_velocity: float = 4.5    # сила прыжка
@export var mouse_sensitivity: float = 0.003

# Виды оружия (Этап 4.6.2): пистолет — сбалансирован, дробовик — несколько
# пуль с разбросом, больше урона вблизи, но короче дальность и меньше обойма.
var weapons: Array[Dictionary] = [
	{"name": "Пистолет",          "damage": 10.0, "magazine_size": 8,  "reload_time": 1.5, "range": 100.0, "pellets": 1, "spread": 0.0,  "price": 0},
	{"name": "Двойные пистолеты", "damage": 9.0,  "magazine_size": 16, "reload_time": 2.0, "range": 90.0,  "pellets": 1, "spread": 0.01, "price": 40},
	{"name": "Дробовик",          "damage": 6.0,  "magazine_size": 4,  "reload_time": 2.2, "range": 20.0,  "pellets": 5, "spread": 0.05, "price": 50},
	{"name": "Автомат",           "damage": 8.0,  "magazine_size": 30, "reload_time": 2.5, "range": 80.0,  "pellets": 1, "spread": 0.02, "price": 90},
	{"name": "Снайперка",         "damage": 40.0, "magazine_size": 5,  "reload_time": 3.0, "range": 300.0, "pellets": 1, "spread": 0.0,  "price": 120},
]
var current_weapon_index: int = 0
var _ammo_in_weapon: Array[int] = []
# Какое оружие уже куплено (Этап 4.7.2: деньги тратятся на оружие).
# В начале игры у игрока только пистолет (индекс 0), остальное — за деньги.
var _owned: Array[bool] = []

# Текущее оружие (заполняется из weapons при инициализации/переключении)
@export var damage: float = 10.0          # урон за выстрел (за пулю)
@export var shoot_range: float = 100.0    # дальность выстрела, м
@export var magazine_size: int = 8        # патронов в обойме
@export var reload_time: float = 1.5      # время перезарядки, с
var current_ammo: int = magazine_size
var _reloading: bool = false

# Ремонт построек
@export var repair_range: float = 4.0     # дистанция ремонта, м (с запасом на привязку к сетке)
@export var repair_amount: float = 15.0   # сколько HP восстанавливает ремонт
const REPAIR_COST := {"wood": 1}

# Ссылка на камеру от первого лица. @onready = «возьми этот узел, когда сцена готова».
@onready var camera: Camera3D = $Camera3D
@onready var health: HealthComponent = $HealthComponent
@onready var build_system: Node3D = $BuildSystem

# Берём гравитацию из настроек проекта (по умолчанию 9.8).
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# В режиме прогона (--capture) игнорируем реальный ввод, чтобы случайные
# нажатия не влияли на автоматическую проверку и не забирали курсор.
var _capture_mode: bool = false


func _ready() -> void:
	_capture_mode = OS.get_cmdline_user_args().has("--capture")
	# Захватываем курсор для управления камерой — но НЕ в режиме прогона.
	if not _capture_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Записываемся в группу "player" — так враги нас находят.
	add_to_group("player")
	health.died.connect(_on_died)

	# Инициализация оружия (Этап 4.6.2): у каждого оружия своя обойма.
	# Стартует только пистолет (индекс 0), остальное покупается за деньги.
	for i in weapons.size():
		_ammo_in_weapon.append(int(weapons[i].magazine_size))
		_owned.append(i == 0)
	_apply_weapon(current_weapon_index)

	ammo_changed.emit(current_ammo, magazine_size)


func _unhandled_input(event: InputEvent) -> void:
	if _capture_mode:
		return  # в режиме прогона реальный ввод игнорируем
	# Поворот камеры движением мыши.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Поворот тела влево/вправо (рыскание).
		rotate_y(-event.relative.x * mouse_sensitivity)
		# Наклон камеры вверх/вниз (тангаж).
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		# Не даём камере перевернуться (смотрим почти вертикально вверх/вниз).
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-89), deg_to_rad(89))

	# Левая кнопка мыши.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if build_system.build_mode:
				build_system.try_place()                  # в режиме постройки — строим стену
			else:
				shoot()                                    # иначе — стреляем
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # заново захватываем курсор

	# B — переключить режим постройки.
	if event is InputEventKey and event.pressed and event.keycode == KEY_B:
		build_system.toggle()

	# R — перезарядить оружие.
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		reload()

	# 1-5 — переключить оружие (Этап 4.6.2; арсенал расширен).
	if event is InputEventKey and event.pressed and event.keycode >= KEY_1 and event.keycode <= KEY_5:
		switch_weapon(event.keycode - KEY_1)

	# F — отремонтировать постройку, на которую смотрим.
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		repair_target()

	# Esc — отпустить курсор.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	# Притяжение к земле, пока не на полу.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# В режиме прогона ввод не читаем — двигаемся только по скрипту проверки.
	var input_dir := Vector3.ZERO
	if not _capture_mode:
		# Прыжок.
		if Input.is_physical_key_pressed(KEY_SPACE) and is_on_floor():
			velocity.y = jump_velocity

		# Считываем нажатые клавиши движения.
		if Input.is_physical_key_pressed(KEY_W):
			input_dir.z -= 1.0   # вперёд (в Godot «вперёд» это -Z)
		if Input.is_physical_key_pressed(KEY_S):
			input_dir.z += 1.0   # назад
		if Input.is_physical_key_pressed(KEY_A):
			input_dir.x -= 1.0   # влево
		if Input.is_physical_key_pressed(KEY_D):
			input_dir.x += 1.0   # вправо

	# Переводим направление в мировые координаты (с учётом поворота тела).
	var direction := (transform.basis * input_dir).normalized()

	if direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		# Плавно останавливаемся, когда клавиши отпущены.
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	# Встроенная функция: двигает тело и обрабатывает столкновения.
	move_and_slide()


func shoot() -> void:
	if _reloading:
		print("CLAUDE: идёт перезарядка")
		return
	if current_ammo <= 0:
		print("CLAUDE: патроны закончились — нажмите R для перезарядки")
		return

	current_ammo -= 1
	ammo_changed.emit(current_ammo, magazine_size)

	var weapon: Dictionary = weapons[current_weapon_index]
	var pellets: int = weapon.get("pellets", 1)
	var spread: float = weapon.get("spread", 0.0)
	var space_state := get_world_3d().direct_space_state
	var hits := 0

	for i in pellets:
		# Пускаем луч из камеры вперёд — туда, где прицел в центре экрана,
		# с небольшим случайным разбросом для оружий типа дробовика.
		var direction := -camera.global_transform.basis.z
		if spread > 0.0:
			direction = direction.rotated(camera.global_transform.basis.x, randf_range(-spread, spread))
			direction = direction.rotated(camera.global_transform.basis.y, randf_range(-spread, spread))

		var from := camera.global_position
		var to := from + direction * shoot_range
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = [get_rid()]   # не попадаем лучом в самого себя
		var result := space_state.intersect_ray(query)

		if result:
			var collider = result.collider
			# Если у объекта есть метод take_damage — наносим урон.
			if collider.has_method("take_damage"):
				collider.take_damage(damage)
			hits += 1

	if hits > 0:
		print("Попадание: ", hits, " / ", pellets)
	else:
		print("Мимо")


## Перезарядка оружия (Этап 4.6.1): занимает reload_time секунд.
func reload() -> void:
	if _reloading or current_ammo == magazine_size:
		return
	_reloading = true
	print("CLAUDE: перезарядка...")
	await get_tree().create_timer(reload_time).timeout
	current_ammo = magazine_size
	_ammo_in_weapon[current_weapon_index] = current_ammo
	_reloading = false
	ammo_changed.emit(current_ammo, magazine_size)
	print("CLAUDE: перезарядка завершена")


## Переключение оружия (Этап 4.6.2): сохраняет патроны текущего оружия
## и подгружает параметры/патроны нового. Во время перезарядки не даём
## переключиться, чтобы не было путаницы со временем перезарядки.
func switch_weapon(index: int) -> void:
	if index == current_weapon_index or index < 0 or index >= weapons.size():
		return
	if _reloading:
		print("CLAUDE: нельзя переключить оружие во время перезарядки")
		return
	if not _owned[index]:
		print("CLAUDE: оружие ", weapons[index].name, " ещё не куплено")
		return

	_ammo_in_weapon[current_weapon_index] = current_ammo
	_apply_weapon(index)
	ammo_changed.emit(current_ammo, magazine_size)
	weapon_changed.emit(weapons[current_weapon_index].name)
	print("CLAUDE: оружие переключено на ", weapons[current_weapon_index].name)


## Куплено ли оружие с индексом index (Этап 4.7.2).
func owns_weapon(index: int) -> bool:
	return index >= 0 and index < _owned.size() and _owned[index]


## Индекс следующего ещё не купленного оружия (по порядку/цене) или -1,
## если всё куплено. Мастерская продаёт оружие именно в этом порядке.
func next_unowned_weapon_index() -> int:
	for i in weapons.size():
		if not _owned[i]:
			return i
	return -1


## Покупка оружия за деньги (Этап 4.7.2): доступно в мастерской.
## Возвращает true при успешной покупке; купленное сразу делаем активным.
func buy_weapon(index: int) -> bool:
	if index < 0 or index >= weapons.size():
		return false
	if _owned[index]:
		print("CLAUDE: оружие ", weapons[index].name, " уже куплено")
		return false
	var price: int = int(weapons[index].get("price", 0))
	if not InventorySystem.spend_money(price):
		print("CLAUDE: не хватает денег на ", weapons[index].name, " (нужно ", price, "$)")
		return false
	_owned[index] = true
	print("Куплено оружие: ", weapons[index].name, " за ", price, "$")
	switch_weapon(index)
	return true


## Применяет параметры оружия с индексом index как текущие.
func _apply_weapon(index: int) -> void:
	current_weapon_index = index
	var weapon: Dictionary = weapons[index]
	damage = weapon.damage
	shoot_range = weapon.range
	magazine_size = weapon.magazine_size
	reload_time = weapon.reload_time
	current_ammo = _ammo_in_weapon[index]


## Ремонт ближайшей постройки (стены) рядом с игроком (Этап 4.3).
## Стены низкие (1 м), а камера на высоте 1.6 м — горизонтальный луч
## по ним не попадает, поэтому ищем по дистанции, а не по лучу.
## Стоит 1 дерево, восстанавливает repair_amount HP.
func repair_target() -> void:
	var nearest: Node3D = null
	var nearest_dist := repair_range
	for node in get_tree().get_nodes_in_group("building"):
		if not (node is Node3D) or not node.has_method("repair"):
			continue
		var dist := (node as Node3D).global_position.distance_to(global_position)
		if dist <= nearest_dist:
			nearest = node
			nearest_dist = dist

	if not is_instance_valid(nearest):
		print("CLAUDE: нечего ремонтировать")
		return

	if nearest.has_method("is_full_health") and nearest.is_full_health():
		print("CLAUDE: постройка уже на максимум HP")
		return

	for resource_type in REPAIR_COST:
		if InventorySystem.get_resource(resource_type) < REPAIR_COST[resource_type]:
			print("CLAUDE: не хватает ресурсов для ремонта")
			return

	for resource_type in REPAIR_COST:
		InventorySystem.use_resource(resource_type, REPAIR_COST[resource_type])

	nearest.repair(repair_amount)
	print("Постройка отремонтирована (+", repair_amount, " HP)")


## Урон по игроку (например, от зомби).
func take_damage(amount: float) -> void:
	health.take_damage(amount)


## Лечение игрока (Этап 4.7.3: покупка лечения в мастерской за деньги).
func heal(amount: float) -> void:
	health.heal(amount)


## Полное ли здоровье — чтобы мастерская не продавала бесполезное лечение.
func is_full_health() -> bool:
	return health.current_health >= health.max_health


## Текущее здоровье — удобно для HUD и для отладочного дампа состояния.
func get_health() -> float:
	return health.current_health


func _on_died() -> void:
	print("ИГРОК ПОГИБ")
	# Экран поражения и рестарт — обрабатывает GameStateManager (Этап 3.7).
