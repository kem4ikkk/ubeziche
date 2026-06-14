extends CharacterBody3D

## Простой контроллер игрока от первого лица.
## Управление:
##   WASD  — движение
##   Мышь  — обзор
##   Space — прыжок
##   ЛКМ   — выстрел (если курсор захвачен) / захватить курсор
##   R     — перезарядка оружия
##   F     — отремонтировать ближайшую постройку (1 дерево → +15 HP)
##   Esc   — отпустить курсор

signal ammo_changed(current: int, magazine: int)

# Параметры можно менять прямо в редакторе (значок справа от ноды).
@export var speed: float = 5.0            # скорость бега, м/с
@export var jump_velocity: float = 4.5    # сила прыжка
@export var mouse_sensitivity: float = 0.003

# Стрельба
@export var damage: float = 10.0          # урон за выстрел
@export var shoot_range: float = 100.0    # дальность выстрела, м

# Патроны и перезарядка (Этап 4.6.1)
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

	# C — скрафтить стену (2 дерева → 1 стена).
	if event is InputEventKey and event.pressed and event.keycode == KEY_C:
		if CraftSystem.craft("wall"):
			print("Скрафтили стену")
		else:
			print("Не хватает ресурсов для крафта стены")

	# R — перезарядить оружие.
	if event is InputEventKey and event.pressed and event.keycode == KEY_R:
		reload()

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

	# Пускаем луч из камеры вперёд — туда, где прицел в центре экрана.
	var space_state := get_world_3d().direct_space_state
	var from := camera.global_position
	var to := from + (-camera.global_transform.basis.z) * shoot_range
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]   # не попадаем лучом в самого себя
	var result := space_state.intersect_ray(query)

	if result:
		var collider = result.collider
		# Если у объекта есть метод take_damage — наносим урон.
		if collider.has_method("take_damage"):
			collider.take_damage(damage)
		print("Попадание: ", collider.name)
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
	_reloading = false
	ammo_changed.emit(current_ammo, magazine_size)
	print("CLAUDE: перезарядка завершена")


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


## Текущее здоровье — удобно для HUD и для отладочного дампа состояния.
func get_health() -> float:
	return health.current_health


func _on_died() -> void:
	print("ИГРОК ПОГИБ")
	# Экран поражения и рестарт — обрабатывает GameStateManager (Этап 3.7).
