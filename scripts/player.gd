extends CharacterBody3D

## Простой контроллер игрока от первого лица.
## Управление:
##   WASD  — движение
##   Мышь  — обзор
##   Space — прыжок
##   ЛКМ   — выстрел (если курсор захвачен) / захватить курсор
##   Esc   — отпустить курсор

# Параметры можно менять прямо в редакторе (значок справа от ноды).
@export var speed: float = 5.0            # скорость бега, м/с
@export var jump_velocity: float = 4.5    # сила прыжка
@export var mouse_sensitivity: float = 0.003

# Стрельба
@export var damage: float = 10.0          # урон за выстрел
@export var shoot_range: float = 100.0    # дальность выстрела, м

# Ссылка на камеру от первого лица. @onready = «возьми этот узел, когда сцена готова».
@onready var camera: Camera3D = $Camera3D

# Берём гравитацию из настроек проекта (по умолчанию 9.8).
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	# Прячем и захватываем курсор, чтобы крутить камеру мышью.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
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
			shoot()                                       # курсор захвачен → стреляем
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # иначе — заново захватываем курсор

	# Esc — отпустить курсор.
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	# Притяжение к земле, пока не на полу.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Прыжок.
	if Input.is_physical_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = jump_velocity

	# Считываем нажатые клавиши движения.
	var input_dir := Vector3.ZERO
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
