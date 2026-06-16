extends CanvasLayer

## Экран выбора класса (Этап 4.12): показывается один раз в начале забега.
## Кнопки выбирают класс (InventorySystem.set_class) → панель скрывается, курсор
## возвращается в игру (паузы в игре нет, поэтому день идёт — но угроз ещё нет).
## В capture-режиме скрыт: класс задаёт тест программно (InventorySystem.set_class).
## InventorySystem — автозагрузка и переживает reload_current_scene, поэтому при
## старте сцены сбрасываем прогрессию забега, чтобы класс выбирался заново.

var _capture_mode := false


func _ready() -> void:
	add_to_group("class_select")
	_capture_mode = OS.get_cmdline_user_args().has("--capture")
	$Panel/VBox/Combat.pressed.connect(_on_pick.bind("combat"))
	$Panel/VBox/Gather.pressed.connect(_on_pick.bind("gather"))
	$Panel/VBox/Engineer.pressed.connect(_on_pick.bind("engineer"))
	if _capture_mode:
		visible = false
		return
	# Новый забег — сбрасываем класс/навыки и показываем выбор.
	InventorySystem.reset_run_progression()
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_pick(c: String) -> void:
	InventorySystem.set_class(c)
	visible = false
	if not _capture_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
