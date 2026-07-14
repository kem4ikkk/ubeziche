extends StaticBody3D

## Склад (Warehouse, Этап 4.43). Домашнее хранилище дерева/стали: пока построен,
## повышает ЁМКОСТЬ склада (InventorySystem.storage_capacity) на capacity_bonus.
## Склад НЕ увеличивает переноску в рюкзаке — это отдельный запас. Игрок подходит
## вплотную и по клавише E открывает меню склада (Сдать/Забрать), как у мастерской.
## Бонус ёмкости снимается при сносе/разрушении (лишний запас сверх новой ёмкости
## теряется — см. InventorySystem.remove_storage_capacity).

@onready var health: HealthComponent = $HealthComponent
@onready var hp_label: Label3D = $HPLabel
@onready var prompt: Label3D = $Prompt

## Насколько эта постройка «Склад» повышает ёмкость домашнего хранилища.
@export var capacity_bonus: int = 100
## Радиус, в котором можно открыть меню склада клавишей E.
@export var interact_range: float = 3.2

var _bonus_applied: bool = false
var _capture_mode: bool = false
var _player_near: bool = false


func _ready() -> void:
	_capture_mode = OS.get_cmdline_user_args().has("--capture")
	add_to_group("building")
	add_to_group("storage")
	health.died.connect(_on_died)
	health.health_changed.connect(_on_health_changed)
	_on_health_changed(health.current_health, health.max_health)
	InventorySystem.add_storage_capacity(capacity_bonus)
	_bonus_applied = true
	_update_prompt()


func take_damage(amount: float) -> void:
	health.take_damage(amount)
	EventBus.building_damaged.emit("Склад")


func repair(amount: float) -> void:
	health.heal(amount)


func is_full_health() -> bool:
	return health.current_health >= health.max_health


## Близость игрока считаем каждый кадр (постройка — StaticBody, Area нет).
func _process(_delta: float) -> void:
	var p := get_tree().get_first_node_in_group("player")
	var near: bool = is_instance_valid(p) \
			and global_position.distance_to((p as Node3D).global_position) <= interact_range
	if near != _player_near:
		_player_near = near
		_update_prompt()


## E (рядом со складом) открывает/закрывает меню склада. В прогоне ввод выключен —
## тест дёргает InventorySystem.deposit/withdraw напрямую.
func _unhandled_input(event: InputEvent) -> void:
	if _capture_mode or not _player_near:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		var menu := get_tree().get_first_node_in_group("warehouse_menu")
		if is_instance_valid(menu) and menu.has_method("toggle"):
			menu.toggle()


func _on_died() -> void:
	_release_capacity()
	queue_free()


## Снять бонус ёмкости при разрушении/сносе склада (один раз).
func _release_capacity() -> void:
	if _bonus_applied:
		_bonus_applied = false
		InventorySystem.remove_storage_capacity(capacity_bonus)


func _on_health_changed(current: float, maximum: float) -> void:
	hp_label.text = "Склад %d / %d" % [current, maximum]
	var ratio := current / maximum
	hp_label.visible = ratio < 0.9   # надпись над постройкой — только при <90% HP
	if ratio > 0.6:
		hp_label.modulate = Color(0.4, 1.0, 0.4)
	elif ratio > 0.3:
		hp_label.modulate = Color(1.0, 0.85, 0.2)
	else:
		hp_label.modulate = Color(1.0, 0.3, 0.3)


## Подсказка над складом: ярче, когда игрок рядом.
func _update_prompt() -> void:
	if prompt == null:
		return
	if _player_near:
		prompt.text = "СКЛАД\n[E] открыть хранилище"
		prompt.modulate = Color(1, 1, 1)
	else:
		prompt.text = "Склад\n(подойдите ближе)"
		prompt.modulate = Color(0.7, 0.7, 0.7)
