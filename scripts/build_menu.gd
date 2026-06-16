extends CanvasLayer

## Меню построек (Этап 4.26): открывается клавишей B (как в оригинале CS:NZ,
## вместо прежних toggle+V). Показывает список доступных построек с ценой в
## ресурсах и гейтом по тиру убежища. Клик по постройке — выбрать её и войти
## в режим постройки (дальше ЛКМ ставит призрак). Есть кнопка выхода из режима.

@onready var _list: VBoxContainer = $Panel/VBox/List

var _capture_mode := false
var _build_system: Node
var _close_key_was_down := false   # для фронта нажатия клавиши закрытия (см. _process)


func _ready() -> void:
	add_to_group("build_menu")
	_capture_mode = OS.get_cmdline_user_args().has("--capture")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


## Ссылка на BuildSystem игрока (ленивый поиск — игрок есть не сразу).
func _resolve_build_system() -> Node:
	if is_instance_valid(_build_system):
		return _build_system
	var p := get_tree().get_first_node_in_group("player")
	if is_instance_valid(p) and p.has_node("BuildSystem"):
		_build_system = p.get_node("BuildSystem")
	return _build_system


## Открыть/закрыть меню (вызывается из player.gd по клавише B).
func toggle() -> void:
	visible = not visible
	if visible:
		_close_key_was_down = true   # клавишу открытия не считаем закрытием
		_rebuild()
	if not _capture_mode:
		get_tree().paused = visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED


## Пока меню открыто, игра на паузе и player.gd ввод не получает. Закрытие (B или
## Esc) ловим ОПРОСОМ клавиш в _process (process_mode=ALWAYS работает на паузе).
## Опрос вместо _unhandled_input специально: виртуал ввода на CanvasLayer при
## выходе из дерева цепляет get_viewport()==null и роняет завершение прогона.
func _process(_delta: float) -> void:
	if _capture_mode or not visible:
		_close_key_was_down = false
		return
	var down := Input.is_key_pressed(KEY_B) or Input.is_key_pressed(KEY_ESCAPE)
	if down and not _close_key_was_down:
		toggle()  # повторное нажатие B (или Esc) — закрыть
	_close_key_was_down = down


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var bs := _resolve_build_system()
	if bs == null:
		return
	for b in bs.get_buildables():
		var b_name: String = b.name
		var min_tier: int = int(b.get("min_tier", 1))
		var locked: bool = InventorySystem.shelter_tier < min_tier
		var btn := Button.new()
		btn.text = "%s — %s%s" % [
				b_name, _cost_text(b.cost),
				("  (нужен Тир %d)" % min_tier) if locked else ""]
		btn.disabled = locked
		btn.pressed.connect(_on_pick.bind(b_name))
		_list.add_child(btn)
	# Кнопка выхода из режима постройки.
	var exit_btn := Button.new()
	exit_btn.text = "Выйти из режима постройки"
	exit_btn.pressed.connect(_on_exit_build)
	_list.add_child(exit_btn)


## Выбрать постройку: входим в режим постройки и закрываем меню (ЛКМ ставит).
func _on_pick(building_name: String) -> void:
	var bs := _resolve_build_system()
	if bs == null:
		return
	bs.select_buildable(building_name)
	if not bs.build_mode:
		bs.toggle()
	toggle()


func _on_exit_build() -> void:
	var bs := _resolve_build_system()
	if bs != null and bs.build_mode:
		bs.toggle()
	toggle()


func _cost_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for r in cost:
		parts.append("%s %d" % [_res_name(r), int(cost[r])])
	return ", ".join(parts)


func _res_name(r: String) -> String:
	match r:
		"wood": return "дерево"
		"steel": return "сталь"
		"wall": return "стена"
	return r
