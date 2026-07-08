extends CharacterBody3D

## Простой контроллер игрока от первого лица.
## Управление:
##   WASD  — движение
##   Мышь  — обзор
##   Space — прыжок
##   ЛКМ   — с топором: добыча/ремонт/ближний бой (swing_axe; можно ЗАЖАТЬ —
##           непрерывная рубка); со стволом: выстрел
##   Q     — взять топор (Этап 4.21, стартовый инструмент)
##   R     — перезарядка оружия
##   1-5   — переключить оружие (только купленное; берётся вместо топора)
##   B     — меню построек (Этап 4.26): выбрать постройку → ЛКМ ставит; B выходит
##   Esc   — отпустить курсор
## Топор (Этап 4.21) есть с начала игры: ремонт построек теперь бесплатным
## ударом топора (без траты дерева), им же добываем ресурсы (5.2) и бьём зомби.

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
	{"name": "Автомат",           "damage": 8.0,  "magazine_size": 30, "reload_time": 2.5, "range": 80.0,  "pellets": 1, "spread": 0.02, "price": 90, "auto": true},
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

# Ремонт построек — теперь бесплатным ударом топора (Этап 4.21), без траты дерева.
@export var repair_range: float = 1.5     # ремонт только в упор — надо стоять вплотную (м)
@export var repair_amount: float = 15.0   # сколько HP восстанавливает один удар
var _last_hit_pos: Vector3                # точка попадания луча топора (для ремонта в упор)

# Видимые модели оружия (вьюмодел, правка автора): простые примитивы под камерой,
# по одной на каждый ствол и на каждое оружие ближнего боя (топор/мачете/лом/молот).
var _viewmodel: Node3D
var _vm: Dictionary = {}

# Топор (Этап 4.21): стартовый инструмент. Им добываем ресурсы (4.22), чиним
# постройки и бьём зомби в ближнем бою. ЛКМ с топором → swing_axe().
@export var axe_damage: float = 25.0      # урон топором по зомби за удар
@export var axe_range: float = 3.0        # дальность удара/луча топора, м
var axe_equipped: bool = true             # на старте в руках топор, а не ствол

# Скорость атаки топора (Этап 4.27): кулдаун между ударами. Базовый топор
# медленный; классовые инструменты ускоряют (улучшенный топор — быстрее всех).
@export var axe_swing_interval: float = 0.6
var _swing_timer: float = 0.0

# Авто-огонь (Автомат и др. с "auto": true): зажатый ЛКМ стреляет очередью.
const AUTO_FIRE_INTERVAL := 0.12
var _fire_cd: float = 0.0

# Базовый максимум HP (из сцены) — к нему добавляется бонус класса Боец (4.12).
var _base_max_health: float = 100.0

# Сигнатурные способности классов (Этап 4.12b), активируются клавишей F.
# Авиаудар (Боец): по точке прицела с задержкой — AoE по зомби, затем кулдаун.
@export var airstrike_delay: float = 1.5
@export var airstrike_radius: float = 5.0
@export var airstrike_damage: float = 80.0
@export var airstrike_cooldown: float = 25.0
var _airstrike_cd: float = 0.0
# Ускорение (Добытчик, Этап 4.12c): +25% скорости на время, затем кулдаун.
@export var sprint_multiplier: float = 1.25
@export var sprint_duration: float = 5.0
@export var sprint_cooldown: float = 12.0
var _sprint_timer: float = 0.0
var _sprint_cd: float = 0.0
# Заряд C4 (Инженер) — сцена, которую ставит игрок (Костёр стал постройкой B).
@export var c4_scene: PackedScene
@export var c4_place_range: float = 8.0   # на какую дальность по прицелу кладём C4

# Психическое здоровье (Этап 1B) — «шкала холода» как в оригинале «Убежище».
# Падает вне тепла (быстрее ночью), растёт у костра или в «очаге» базы (центр
# карты). При нуле: −HP по тику + сужение обзора (туннельное зрение). Навык
# «Терпение» вдвое снижает расход и подлечивает при низком HP; костёр греет.
const SANITY_MAX := 100.0
const SANITY_RECOVER := 16.0          # /с, в тепле
const SANITY_DRAIN_DAY := 1.6         # /с, вне тепла днём
const SANITY_DRAIN_NIGHT := 3.6       # /с, вне тепла ночью
const HEARTH_RADIUS := 6.5            # радиус «очага» базы вокруг центра карты
const SANITY_EMPTY_TICK := 4.0        # период урона при нуле, с
const SANITY_EMPTY_DAMAGE := 5.0      # HP за тик при нуле
const SANITY_FOV_DROP := 20.0         # сужение FOV при нуле (туннельное зрение)
var sanity: float = SANITY_MAX
var _sanity_tick: float = 0.0
var _base_fov: float = 75.0
var _day_night: Node = null

# Ссылка на камеру от первого лица. @onready = «возьми этот узел, когда сцена готова».
@onready var camera: Camera3D = $Camera3D
@onready var health: HealthComponent = $HealthComponent
@onready var build_system: Node3D = $BuildSystem

# Берём гравитацию из настроек проекта (по умолчанию 9.8).
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# В режиме прогона (--capture) игнорируем реальный ввод, чтобы случайные
# нажатия не влияли на автоматическую проверку и не забирали курсор.
var _capture_mode: bool = false

# Смерть/возрождение (Этап 5.x): смерть НЕ заканчивает игру — игрок переходит в
# режим НАБЛЮДАТЕЛЯ (свободный полёт, без действий) и возрождается через таймер.
# Время возрождения 20–30 c: базово 20, +1 c за каждую смерть (с потолком 30).
@export var fly_speed: float = 12.0
var _dead: bool = false
var _deaths: int = 0
var _respawn_timer: float = 0.0
var _respawn_total: float = 0.0
var _spawn_pos: Vector3
var _orig_layer: int = 1
var _orig_mask: int = 1


func _ready() -> void:
	_capture_mode = OS.get_cmdline_user_args().has("--capture")
	# Захватываем курсор для управления камерой — но НЕ в режиме прогона.
	if not _capture_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Записываемся в группу "player" — так враги нас находят.
	add_to_group("player")
	health.died.connect(_on_died)
	_base_fov = camera.fov                    # запомним обзор для эффекта психздоровья
	_spawn_pos = global_position              # точка возрождения (Этап 5.x)
	_orig_layer = collision_layer
	_orig_mask = collision_mask
	_build_viewmodels()                       # видимые модели оружия

	# Класс Боец (Этап 4.12): +макс HP за уровень ветки «Бой». Базовый максимум
	# берём из сцены один раз, бонус пересчитываем при смене навыков/класса.
	_base_max_health = health.max_health
	InventorySystem.skills_changed.connect(_apply_combat_hp)
	InventorySystem.class_changed.connect(func(_c): _apply_combat_hp())
	_apply_combat_hp()

	# Инициализация оружия (Этап 4.6.2): у каждого оружия своя обойма.
	# Стартует только пистолет (индекс 0), остальное покупается за деньги.
	for i in weapons.size():
		_ammo_in_weapon.append(int(weapons[i].magazine_size))
		_owned.append(i == 0)
	_apply_weapon(current_weapon_index)

	ammo_changed.emit(current_ammo, magazine_size)
	# На старте в руках топор — сообщаем HUD после готовности всей сцены.
	weapon_changed.emit.call_deferred("Топор")


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

	# В режиме наблюдателя (мёртв) разрешён только обзор мышью — никаких действий/меню.
	if _dead:
		return

	# Левая кнопка мыши. Если открыто меню (курсор свободен для кликов по кнопкам) —
	# ЛКМ не стреляет и НЕ перехватывает курсор (клики по кнопкам ловит GUI).
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _any_menu_open():
			pass
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if build_system.build_mode:
				build_system.try_place()                  # в режиме постройки — строим
			elif axe_equipped:
				swing_axe()                                # топор: добыча/ремонт/ближний бой
			else:
				shoot()                                    # ствол: стреляем
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # заново захватываем курсор

	# B — открыть/закрыть меню построек (Этап 4.26). В режиме постройки B
	# просто выходит из него. Само меню (build_menu.gd) выбирает постройку.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		if build_system.build_mode:
			build_system.toggle()
		else:
			var menu := get_tree().get_first_node_in_group("build_menu")
			if is_instance_valid(menu) and menu.has_method("toggle"):
				menu.toggle()

	# R — перезарядить оружие.
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		reload()

	# 1-5 — переключить оружие (Этап 4.6.2; арсенал расширен).
	if event is InputEventKey and event.pressed and event.keycode >= KEY_1 and event.keycode <= KEY_5:
		switch_weapon(event.keycode - KEY_1)

	# Q — взять топор (снимает ствол). Стволы берутся клавишами 1-5.
	if event is InputEventKey and event.pressed and event.keycode == KEY_Q:
		equip_axe()

	# F — сигнатурная способность класса (Этап 4.12b): Авиаудар/Костёр/C4.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F:
		use_class_ability()

	# N — открыть/закрыть меню навыков (Этап 4.23).
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_N:
		var menu := get_tree().get_first_node_in_group("skill_menu")
		if is_instance_valid(menu) and menu.has_method("toggle"):
			menu.toggle()

	# Esc — сначала закрывает любое открытое меню, иначе отпускает курсор.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _any_menu_open():
			_close_all_menus()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Открыто ли какое-либо UI-меню (навыки/постройки/мастерская). Пока меню открыто,
## ЛКМ не действует в мире, а Esc закрывает меню (паузы в игре нет).
func _any_menu_open() -> bool:
	for grp in ["skill_menu", "build_menu", "workshop_menu"]:
		var m := get_tree().get_first_node_in_group(grp)
		if is_instance_valid(m) and m.visible:
			return true
	return false


## Закрыть все открытые меню (Esc).
func _close_all_menus() -> void:
	for grp in ["skill_menu", "build_menu", "workshop_menu"]:
		var m := get_tree().get_first_node_in_group(grp)
		if is_instance_valid(m) and m.has_method("close"):
			m.close()


func _physics_process(delta: float) -> void:
	# Режим наблюдателя после смерти (Этап 5.x): свободный полёт + отсчёт возрождения.
	if _dead:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		else:
			_fly(delta)
		return

	# Кулдаун удара топором (Этап 4.27).
	if _swing_timer > 0.0:
		_swing_timer -= delta

	# Кулдаун авиаудара (Этап 4.12b).
	if _airstrike_cd > 0.0:
		_airstrike_cd -= delta

	# Таймеры ускорения Добытчика (Этап 4.12c).
	if _sprint_timer > 0.0:
		_sprint_timer -= delta
	if _sprint_cd > 0.0:
		_sprint_cd -= delta

	# Психическое здоровье (Этап 1B).
	_update_sanity(delta)

	# Зажатая ЛКМ с топором — НЕПРЕРЫВНАЯ добыча/ремонт/бой (правка 2026-06-16):
	# можно зажать кнопку и рубить, темп задаёт кулдаун в swing_axe(). Для стволов
	# авто-огня нет (стрельба — по одиночному клику в _unhandled_input). Не трогаем
	# при открытом меню, в режиме постройки и без захвата курсора.
	if not _capture_mode and axe_equipped \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and not build_system.build_mode and not _any_menu_open() \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		swing_axe()

	# Авто-огонь: со стволом, у которого "auto": true (Автомат), зажатый ЛКМ стреляет
	# очередью с интервалом AUTO_FIRE_INTERVAL (правка автора — «это же автомат»).
	if _fire_cd > 0.0:
		_fire_cd -= delta
	if not _capture_mode and not axe_equipped \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and not build_system.build_mode and not _any_menu_open() \
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
			and bool(weapons[current_weapon_index].get("auto", false)) and _fire_cd <= 0.0:
		shoot()

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

	# Эффективная скорость: пассивный навык «Повышение скорости» (+5/+10/+20%, Этап
	# 4.40) × временное ускорение (если активно).
	var sb_mult: float = [1.0, 1.05, 1.10, 1.20][clampi(InventorySystem.get_skill_level("speed_boost"), 0, 3)]
	var cur_speed := speed * sb_mult * (sprint_multiplier if _sprint_timer > 0.0 else 1.0)
	if direction != Vector3.ZERO:
		velocity.x = direction.x * cur_speed
		velocity.z = direction.z * cur_speed
	else:
		# Плавно останавливаемся, когда клавиши отпущены.
		velocity.x = move_toward(velocity.x, 0.0, cur_speed)
		velocity.z = move_toward(velocity.z, 0.0, cur_speed)

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
		# Пули проходят сквозь узлы добычи (Этап 4.22): исключаем ИХ слой (бит 4 = 16).
		# НЕ слой 4 — там зомби, иначе пули проходили бы сквозь врагов (баг до 2026-06-16).
		query.collision_mask = 0xFFFFFFEF
		var result := space_state.intersect_ray(query)

		if result:
			var collider = result.collider
			# Засчитываем попадание ТОЛЬКО если есть по чему наносить урон (враг/
			# постройка). Раньше hits++ стоял безусловно → ложное «Попадание» при
			# выстреле в землю/стену, хотя зомби невредим.
			if collider.has_method("take_damage"):
				collider.take_damage(damage)
				hits += 1

	if hits > 0:
		print("Попадание: ", hits, " / ", pellets)
	else:
		print("Мимо")

	# Темп автоматического огня (Автомат): следующий выстрел очереди — через интервал.
	if bool(weapons[current_weapon_index].get("auto", false)):
		_fire_cd = AUTO_FIRE_INTERVAL


## Перезарядка оружия (Этап 4.6.1): занимает reload_time секунд.
func reload() -> void:
	if axe_equipped:
		return  # у топора нет патронов и перезарядки (Этап 4.21)
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
	if index < 0 or index >= weapons.size():
		return
	# Если в руках топор — даём взять даже текущий по индексу ствол.
	if not axe_equipped and index == current_weapon_index:
		return
	if _reloading:
		print("CLAUDE: нельзя переключить оружие во время перезарядки")
		return
	if not _owned[index]:
		print("CLAUDE: оружие ", weapons[index].name, " ещё не куплено")
		return

	axe_equipped = false   # взяли ствол — топор убран
	_ammo_in_weapon[current_weapon_index] = current_ammo
	_apply_weapon(index)
	ammo_changed.emit(current_ammo, magazine_size)
	weapon_changed.emit(weapons[current_weapon_index].name)
	print("CLAUDE: оружие переключено на ", weapons[current_weapon_index].name)


## Взять топор (Этап 4.21): снимает ствол, ЛКМ начинает бить топором.
func equip_axe() -> void:
	if axe_equipped:
		return
	if _reloading:
		print("CLAUDE: нельзя сменить инструмент во время перезарядки")
		return
	axe_equipped = true
	weapon_changed.emit("Топор")
	print("CLAUDE: в руках топор")


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


## Удар топором (Этап 4.21): луч из камеры — действуем по тому, на что смотрим.
## Приоритет: узел ресурса (добыча, 4.22) → зомби (ближний бой) → постройка
## (ремонт). Стены низкие (1 м), камера на 1.6 м — если луч прошёл мимо,
## чиним ближайшую постройку в радиусе repair_range.
## Кулдаун между ударами зависит от инструмента (Этап 4.27, _axe_swing_interval).
func swing_axe() -> void:
	if _swing_timer > 0.0:
		return  # ещё не отошли от прошлого удара (скорость атаки)
	_swing_timer = _axe_swing_interval()

	var target := _axe_raycast_target()
	if target != null:
		if target.is_in_group("resource_node") and target.has_method("hit"):
			var got: int = target.hit()          # добыча (этап 4.22, только от навыка)
			if got > 0:
				print("Добыто ресурса: +", got)
			else:
				print("CLAUDE: узел истощён")
			return
		if target.is_in_group("enemy") and target.has_method("take_damage"):
			# Урон = база + ветка «Бой» + Нож. Бонус «Боя» снижен с ×10 до ×4
			# (правка 2026-06-16): на ×10 ближний бой стал слишком сильным —
			# на бое 3 топор сносил обычного зомби с одного удара, танка за два.
			var dmg := axe_damage + InventorySystem.get_skill_level("special_weapon") * 4.0
			if InventorySystem.has_knife:
				dmg += 10.0
			target.take_damage(dmg)
			print("Удар топором по зомби: -", dmg, " HP")
			return
		if target.is_in_group("building") and target.has_method("repair"):
			# Ремонт только В УПОР: точка попадания должна быть близко к игроку.
			if global_position.distance_to(_last_hit_pos) <= repair_range:
				_repair_building(target)
			else:
				print("CLAUDE: для ремонта нужно подойти вплотную к постройке")
			return
	# Луч мимо (стены низкие) — чиним ближайшую постройку в радиусе.
	var nearest := _nearest_building()
	if nearest != null:
		_repair_building(nearest)
	else:
		print("CLAUDE: топор бьёт по воздуху")


## Интервал между ударами топора (Этап 4.27). Инструменты ускоряют атаку:
## улучшенный топор — быстрее всех; нож/молот — быстрее обычного топора.
func _axe_swing_interval() -> float:
	if InventorySystem.has_improved_axe:
		return axe_swing_interval * 0.5    # самый быстрый
	if InventorySystem.has_knife or InventorySystem.has_hammer:
		return axe_swing_interval * 0.75
	return axe_swing_interval


## Луч из камеры вперёд (учитывает Area3D — узлы ресурсов это Area3D).
func _axe_raycast_target() -> Node:
	var space_state := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from + (-camera.global_transform.basis.z) * axe_range
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var result := space_state.intersect_ray(query)
	if result:
		_last_hit_pos = result.position     # точка попадания (для проверки «в упор» при ремонте)
		return result.collider
	return null


## Ближайшая постройка в радиусе repair_range (стены низкие — луч их минует).
func _nearest_building() -> Node3D:
	var nearest: Node3D = null
	var nearest_dist := repair_range
	for node in get_tree().get_nodes_in_group("building"):
		if not (node is Node3D) or not node.has_method("repair"):
			continue
		var dist := (node as Node3D).global_position.distance_to(global_position)
		if dist <= nearest_dist:
			nearest = node
			nearest_dist = dist
	return nearest


## Бесплатный ремонт постройки ударом топора (Этап 4.21: без траты дерева).
## С молотом (has_hammer) восстанавливаем вдвое больше HP за удар.
func _repair_building(node: Node) -> void:
	if node.has_method("is_full_health") and node.is_full_health():
		print("CLAUDE: постройка уже на максимум HP")
		return
	# Навык «Ремонт» (Инженер) добавляет +5% HP за уровень, молот удваивает итог.
	var amount := repair_amount * (1.0 + 0.05 * InventorySystem.get_skill_level("field_repair"))
	if InventorySystem.has_hammer:
		amount *= 2.0
	node.repair(amount)
	print("Постройка отремонтирована (+", amount, " HP)")


## Совместимость с тестами/старым кодом: чинит ближайшую постройку (бесплатно).
func repair_target() -> void:
	var nearest := _nearest_building()
	if nearest == null:
		print("CLAUDE: нечего ремонтировать")
		return
	_repair_building(nearest)


## Урон по игроку (например, от зомби).
func take_damage(amount: float) -> void:
	health.take_damage(amount)


## Лечение игрока (Этап 4.7.3: покупка лечения в мастерской за деньги).
func heal(amount: float) -> void:
	health.heal(amount)


## Психическое здоровье (Этап 1B): расход/восстановление, урон при нуле, обзор.
func _update_sanity(delta: float) -> void:
	var warm := _is_in_hearth() or _near_campfire()
	if warm:
		sanity = minf(sanity + SANITY_RECOVER * delta, SANITY_MAX)
	else:
		var drain: float = SANITY_DRAIN_NIGHT if _is_night() else SANITY_DRAIN_DAY
		if InventorySystem.get_skill_level("patience") > 0:
			drain *= 0.5                          # «Терпение» — вдвое медленнее
		sanity = maxf(sanity - drain * delta, 0.0)

	# При полном опустошении — периодический урон HP (как «замерзание»).
	if sanity <= 0.0:
		_sanity_tick += delta
		if _sanity_tick >= SANITY_EMPTY_TICK:
			_sanity_tick = 0.0
			health.take_damage(SANITY_EMPTY_DAMAGE)
	else:
		_sanity_tick = 0.0

	# «Терпение»: медленно лечит, пока HP не выше половины.
	if InventorySystem.get_skill_level("patience") > 0 \
			and health.current_health > 0.0 \
			and health.current_health <= health.max_health * 0.5:
		health.heal(health.max_health * 0.01 * delta)   # +1%/с

	# Туннельное зрение: ниже 30 рассудка обзор плавно сужается.
	var t := clampf(sanity / 30.0, 0.0, 1.0)
	camera.fov = lerpf(_base_fov - SANITY_FOV_DROP, _base_fov, t)


## В радиусе «очага» базы (вокруг центра карты, по горизонтали)?
func _is_in_hearth() -> bool:
	var p := global_position
	return Vector2(p.x, p.z).length() <= HEARTH_RADIUS


## Рядом ли горящий костёр (постройка), греющий игрока?
func _near_campfire() -> bool:
	for c in get_tree().get_nodes_in_group("campfire"):
		if c is Node3D:
			var rad: float = c.radius if "radius" in c else 4.0
			if global_position.distance_to((c as Node3D).global_position) <= rad:
				return true
	return false


## Сейчас ночь? (лениво ищем DayNightCycle.)
func _is_night() -> bool:
	if not is_instance_valid(_day_night):
		_day_night = get_tree().get_first_node_in_group("day_night_cycle")
	return is_instance_valid(_day_night) and _day_night.is_night


## Добавить/снять психздоровье (костёр греет; вызывается из campfire.gd).
func add_sanity(amount: float) -> void:
	sanity = clampf(sanity + amount, 0.0, SANITY_MAX)


func get_sanity() -> float:
	return sanity


func get_sanity_ratio() -> float:
	return sanity / SANITY_MAX


## Сигнатурная способность класса (Этап 4.12b), клавиша F. Ветвится по классу и
## наличию открытой способности (InventorySystem). В capture-режиме F не читается —
## тест дёргает _call_airstrike/_sprint/_place_c4 напрямую.
func use_class_ability() -> void:
	match InventorySystem.player_class:
		"combat":
			if InventorySystem.has_airstrike:
				_call_airstrike()
		"gather":
			if InventorySystem.has_camouflage:
				_camouflage()
		"engineer":
			if InventorySystem.has_c4:
				_place_c4()


## Маскировка (Добытчик, ультимейт ветки «Выживание») — эффект будет добавлен
## позже (Этап 4.40+); пока заглушка.
func _camouflage() -> void:
	print("Маскировка: эффект скоро (невидимость для врагов 15 с)")


## Авиаудар (Боец): по точке прицела, с задержкой — AoE урон по зомби, кулдаун.
func _call_airstrike() -> void:
	if _airstrike_cd > 0.0:
		print("CLAUDE: авиаудар на кулдауне (", ceili(_airstrike_cd), " c)")
		return
	var target := _aim_ground_point(30.0)
	_airstrike_cd = airstrike_cooldown
	print("Авиаудар вызван по точке ", target)
	_resolve_airstrike(target)


func _resolve_airstrike(target: Vector3) -> void:
	await get_tree().create_timer(airstrike_delay).timeout
	if not is_inside_tree():
		return
	var hits := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Node3D and (e as Node3D).global_position.distance_to(target) <= airstrike_radius \
				and e.has_method("take_damage"):
			e.take_damage(airstrike_damage)
			hits += 1
	print("Авиаудар: попал по ", hits, " врагам (радиус ", airstrike_radius, ", урон ", airstrike_damage, ")")


## Ускорение (Добытчик, Этап 4.12c): +sprint_multiplier к скорости на sprint_duration
## секунд, затем кулдаун. Эффект применяется в _physics_process (cur_speed).
func _sprint() -> void:
	if _sprint_cd > 0.0:
		print("CLAUDE: ускорение на кулдауне (", ceili(_sprint_cd), " c)")
		return
	_sprint_timer = sprint_duration
	_sprint_cd = sprint_cooldown
	print("Ускорение активно (+", int((sprint_multiplier - 1.0) * 100.0), "% скорости на ", sprint_duration, " c)")


## C4 (Инженер): тратит заряд, ставит C4 в точку прицела (взрыв через таймер в c4.gd).
func _place_c4() -> void:
	if c4_scene == null:
		return
	if InventorySystem.c4_charges <= 0:
		print("CLAUDE: нет зарядов C4 (крафт в мастерской)")
		return
	InventorySystem.c4_charges -= 1
	var target := _aim_ground_point(c4_place_range)
	var charge := c4_scene.instantiate()
	get_tree().current_scene.add_child(charge)
	(charge as Node3D).global_position = target
	print("C4 установлен (осталось зарядов ", InventorySystem.c4_charges, ")")


## Точка на земле, куда смотрит игрок: луч из камеры; если ни во что не попал —
## проецируем дальнюю точку на уровень земли (y≈0).
func _aim_ground_point(max_dist: float) -> Vector3:
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var to := from + dir * max_dist
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r:
		return r.position
	to.y = 0.0
	return to


## Макс HP = база + 15 за уровень навыка «Закалка» (vigor). При росте максимума
## подлечиваем на дельту.
func _apply_combat_hp() -> void:
	if not is_instance_valid(health):
		return
	var bonus: float = 15.0 * InventorySystem.get_skill_level("health_boost")
	var new_max: float = _base_max_health + bonus
	var delta: float = new_max - health.max_health
	health.max_health = new_max
	if delta > 0.0 and health.current_health > 0.0:
		health.current_health += delta            # рост максимума — подлечиваем
	health.current_health = minf(health.current_health, new_max)  # максимум упал — не выше него
	health.health_changed.emit(health.current_health, health.max_health)


## Полное ли здоровье — чтобы мастерская не продавала бесполезное лечение.
func is_full_health() -> bool:
	return health.current_health >= health.max_health


## Текущее здоровье — удобно для HUD и для отладочного дампа состояния.
func get_health() -> float:
	return health.current_health


## Смерть игрока (Этап 5.x): НЕ конец игры. Уходим в режим наблюдателя — проходим
## сквозь всё, прячем оружие/действия, считаем таймер возрождения. Игру проигрываем
## только при разрушении убежища (game_state_manager).
func _on_died() -> void:
	if _dead:
		return
	_dead = true
	_deaths += 1
	_respawn_timer = clampf(19.0 + float(_deaths), 20.0, 30.0)   # 20..30 c, +1 за смерть
	_respawn_total = _respawn_timer
	collision_layer = 0                                          # наблюдатель: noclip
	collision_mask = 0
	velocity = Vector3.ZERO
	camera.fov = _base_fov                                       # сбросить туннельное зрение
	EventBus.player_died.emit()
	print("Игрок погиб — наблюдатель, возрождение через ", int(_respawn_timer), " c (смерть #", _deaths, ")")


## Свободный полёт наблюдателя (по направлению камеры; пробел/Shift — выше/ниже).
func _fly(delta: float) -> void:
	var fwd := 0.0
	var strafe := 0.0
	var rise := 0.0
	if not _capture_mode:
		if Input.is_physical_key_pressed(KEY_W): fwd -= 1.0
		if Input.is_physical_key_pressed(KEY_S): fwd += 1.0
		if Input.is_physical_key_pressed(KEY_A): strafe -= 1.0
		if Input.is_physical_key_pressed(KEY_D): strafe += 1.0
		if Input.is_physical_key_pressed(KEY_SPACE): rise += 1.0
		if Input.is_physical_key_pressed(KEY_SHIFT): rise -= 1.0
	var basis := camera.global_transform.basis
	var dir := (basis.z * fwd + basis.x * strafe)
	dir.y = 0.0
	var vel := Vector3.ZERO
	if dir.length() > 0.01:
		vel = dir.normalized() * fly_speed
	vel.y = rise * fly_speed
	velocity = vel
	move_and_slide()


## Возрождение у точки старта с полным HP (Этап 5.x).
func _respawn() -> void:
	_dead = false
	collision_layer = _orig_layer
	collision_mask = _orig_mask
	global_position = _spawn_pos
	velocity = Vector3.ZERO
	health.current_health = health.max_health
	health.health_changed.emit(health.current_health, health.max_health)
	EventBus.player_respawned.emit()
	print("Игрок возродился у базы")


## Для HUD: в режиме наблюдателя и сколько секунд до возрождения.
func is_dead() -> bool:
	return _dead


func get_respawn_left() -> float:
	return _respawn_timer


func get_respawn_total() -> float:
	return _respawn_total


# ==================== Видимые модели оружия (вьюмодел) ====================
const _VM_GUN := Color(0.16, 0.17, 0.20)
const _VM_METAL := Color(0.34, 0.35, 0.40)
const _VM_WOOD := Color(0.44, 0.29, 0.15)
const _VM_BLADE := Color(0.72, 0.74, 0.80)


func _process(_dt: float) -> void:
	_update_viewmodel()


## Собираем по одной простой модели на каждый ствол и оружие ближнего боя.
func _build_viewmodels() -> void:
	_viewmodel = Node3D.new()
	camera.add_child(_viewmodel)
	_viewmodel.position = Vector3(0.30, -0.27, -0.48)
	_viewmodel.rotation_degrees = Vector3(0, 3, 0)
	_vm = {
		"pistol": _vm_pistol(), "dual": _vm_dual(), "shotgun": _vm_shotgun(),
		"rifle": _vm_rifle(), "sniper": _vm_sniper(),
		"axe": _vm_axe(), "machete": _vm_machete(), "crowbar": _vm_crowbar(), "hammer": _vm_hammer(),
	}
	for k in _vm:
		_viewmodel.add_child(_vm[k])
		_vm[k].visible = false
	_update_viewmodel()


## Показываем модель активного оружия (топор/инструмент — если в руках ближний бой,
## иначе текущий ствол). В режиме наблюдателя не показываем ничего.
func _update_viewmodel() -> void:
	if _viewmodel == null:
		return
	var key := ""
	if _dead:
		key = ""
	elif axe_equipped:
		if InventorySystem.has_hammer: key = "hammer"
		elif InventorySystem.has_improved_axe: key = "crowbar"
		elif InventorySystem.has_knife: key = "machete"
		else: key = "axe"
	else:
		key = ["pistol", "dual", "shotgun", "rifle", "sniper"][clampi(current_weapon_index, 0, 4)]
	for k in _vm:
		_vm[k].visible = (k == key)


func _vm_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = rot
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.4
	mat.roughness = 0.55
	mi.material_override = mat
	parent.add_child(mi)


func _vm_pistol() -> Node3D:
	var n := Node3D.new()
	_vm_box(n, Vector3(0.05, 0.085, 0.20), Vector3(0, 0, -0.03), _VM_GUN)
	_vm_box(n, Vector3(0.045, 0.11, 0.06), Vector3(0, -0.09, 0.05), _VM_GUN, Vector3(18, 0, 0))
	return n


func _vm_dual() -> Node3D:
	var n := Node3D.new()
	for sx in [-0.10, 0.10]:
		_vm_box(n, Vector3(0.045, 0.075, 0.17), Vector3(sx, 0, -0.03), _VM_GUN)
		_vm_box(n, Vector3(0.04, 0.095, 0.05), Vector3(sx, -0.08, 0.04), _VM_GUN, Vector3(18, 0, 0))
	return n


func _vm_shotgun() -> Node3D:
	var n := Node3D.new()
	_vm_box(n, Vector3(0.055, 0.075, 0.44), Vector3(0, 0, -0.10), _VM_GUN)
	_vm_box(n, Vector3(0.05, 0.05, 0.12), Vector3(0, -0.055, -0.06), _VM_METAL)
	_vm_box(n, Vector3(0.04, 0.09, 0.05), Vector3(0, -0.07, 0.13), _VM_WOOD, Vector3(20, 0, 0))
	_vm_box(n, Vector3(0.04, 0.06, 0.14), Vector3(0, 0, 0.22), _VM_WOOD)
	return n


func _vm_rifle() -> Node3D:
	var n := Node3D.new()
	_vm_box(n, Vector3(0.05, 0.08, 0.5), Vector3(0, 0, -0.12), _VM_GUN)
	_vm_box(n, Vector3(0.04, 0.13, 0.06), Vector3(0, -0.10, 0.0), _VM_METAL, Vector3(-12, 0, 0))
	_vm_box(n, Vector3(0.04, 0.09, 0.05), Vector3(0, -0.07, 0.12), _VM_GUN, Vector3(20, 0, 0))
	_vm_box(n, Vector3(0.04, 0.07, 0.14), Vector3(0, 0, 0.22), _VM_GUN)
	_vm_box(n, Vector3(0.02, 0.02, 0.12), Vector3(0, 0.02, -0.42), _VM_METAL)
	return n


func _vm_sniper() -> Node3D:
	var n := Node3D.new()
	_vm_box(n, Vector3(0.045, 0.07, 0.62), Vector3(0, 0, -0.16), _VM_GUN)
	_vm_box(n, Vector3(0.036, 0.036, 0.16), Vector3(0, 0.065, -0.06), _VM_METAL)
	_vm_box(n, Vector3(0.04, 0.09, 0.05), Vector3(0, -0.07, 0.14), _VM_GUN, Vector3(20, 0, 0))
	_vm_box(n, Vector3(0.04, 0.07, 0.16), Vector3(0, 0, 0.26), _VM_WOOD)
	_vm_box(n, Vector3(0.018, 0.018, 0.16), Vector3(0, 0.01, -0.5), _VM_METAL)
	return n


func _vm_axe() -> Node3D:
	var n := Node3D.new()
	_vm_box(n, Vector3(0.028, 0.5, 0.028), Vector3(0, 0, 0), _VM_WOOD)
	_vm_box(n, Vector3(0.16, 0.11, 0.03), Vector3(0.06, 0.22, 0), _VM_METAL)
	n.position = Vector3(0.02, 0.04, -0.06)
	n.rotation_degrees = Vector3(-8, 0, 20)
	return n


func _vm_machete() -> Node3D:
	var n := Node3D.new()
	_vm_box(n, Vector3(0.02, 0.055, 0.42), Vector3(0, 0.02, -0.18), _VM_BLADE)
	_vm_box(n, Vector3(0.032, 0.032, 0.12), Vector3(0, 0, 0.06), _VM_WOOD)
	n.rotation_degrees = Vector3(-6, 0, 8)
	return n


func _vm_crowbar() -> Node3D:
	var n := Node3D.new()
	_vm_box(n, Vector3(0.028, 0.028, 0.5), Vector3(0, 0, -0.06), _VM_METAL)
	_vm_box(n, Vector3(0.028, 0.10, 0.028), Vector3(0, 0.05, -0.30), _VM_METAL, Vector3(35, 0, 0))
	n.rotation_degrees = Vector3(-6, 0, 14)
	return n


func _vm_hammer() -> Node3D:
	var n := Node3D.new()
	_vm_box(n, Vector3(0.028, 0.36, 0.028), Vector3(0, 0, 0), _VM_WOOD)
	_vm_box(n, Vector3(0.10, 0.085, 0.10), Vector3(0, 0.18, 0), _VM_METAL)
	n.position = Vector3(0.02, 0.04, -0.06)
	n.rotation_degrees = Vector3(-8, 0, 20)
	return n
