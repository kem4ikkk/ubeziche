extends CanvasLayer

## Меню построек (Этап 4.26): открывается клавишей B (как в оригинале CS:NZ,
## вместо прежних toggle+V). Показывает список доступных построек с ценой в
## ресурсах и гейтом по тиру убежища. Клик по постройке — выбрать её и войти
## в режим постройки (дальше ЛКМ ставит призрак). Есть кнопка выхода из режима.

@onready var _list: VBoxContainer = $Panel/VBox/List

var _capture_mode := false
var _build_system: Node

## Иконка-«фотка» для каждой постройки (файлы в assets/icons, рисует gen_font_icons.py).
## «Склад» → factory (склад-здание): иконки warehouse нет, был пустой блок.
const ICON := {
	"Стена": "bricks", "Мастерская": "toolcross", "Генератор": "generator",
	"Турель": "turret", "Лазарет": "medkit", "Костёр": "campfire",
	"Мортира": "mortar", "Гатлинг": "mg", "Склад": "factory",
}

## Иконка ресурса для строки стоимости (иконка + количество).
const RES_ICON := {"wood": "wood", "steel": "steel", "wall": "bricks"}


func _ready() -> void:
	add_to_group("build_menu")
	_capture_mode = OS.get_cmdline_user_args().has("--capture")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_apply_style()


## Единый стиль (Этап UI-1): тёмная панель + кнопки в стиле меню навыков.
func _apply_style() -> void:
	var panel := $Panel as Panel
	panel.theme = UiStyle.theme()
	# Шире/выше — под сетку карточек (Этап UI-2).
	panel.offset_left = -300.0
	panel.offset_right = 300.0
	panel.offset_top = -235.0
	panel.offset_bottom = 235.0
	var title := $Panel/VBox/TitleLabel as Label
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UiStyle.ACCENT)


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
		_rebuild()
	# Паузы в игре НЕТ (решение автора 2026-06-16) — только курсор для кликов.
	if not _capture_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED


## Закрыть меню, если открыто (для Esc из player.gd).
func close() -> void:
	if visible:
		toggle()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var bs := _resolve_build_system()
	if bs == null:
		return
	# Сетка карточек-построек (Этап UI-2): иконка + название + стоимость + доступность.
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_list.add_child(grid)
	for b in bs.get_buildables():
		grid.add_child(_make_card(b))
	# Кнопка выхода из режима постройки (во всю ширину).
	var exit_btn := Button.new()
	exit_btn.text = "Выйти из режима постройки"
	exit_btn.pressed.connect(_on_exit_build)
	_list.add_child(exit_btn)


## Карточка постройки: название (верх) + иконка (центр) + стоимость иконками
## (иконка ресурса + число, низ). Доступные — яркие; недоступные (тир/ресурсы) —
## затемнены. Кнопка ВСЕГДА активна: у недоступной клик не строит, а показывает
## маленькую подсказку-причину (Этап UI-6, правка автора).
func _make_card(b: Dictionary) -> Control:
	var available: bool = _is_available(b)

	var card := Button.new()
	card.custom_minimum_size = Vector2(130, 122)
	# Яркость: доступные — во всю яркость, недоступные — приглушены.
	card.modulate = Color(1, 1, 1, 1.0) if available else Color(1, 1, 1, 0.4)

	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 6; v.offset_right = -6; v.offset_top = 6; v.offset_bottom = -6

	var nm := Label.new()
	nm.text = b.name
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", 14)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nm)

	var ic := TextureRect.new()
	ic.texture = _icon_for(b.name)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.custom_minimum_size = Vector2(44, 44)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ic)

	# Стоимость: иконка ресурса + количество (вместо текстовой строки).
	v.add_child(_cost_row(b.cost))

	# Скрытая подсказка-причина — «высвечивается» по клику на недоступную карточку.
	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", UiStyle.BAD)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.visible = false
	v.add_child(hint)

	card.pressed.connect(_on_card_pressed.bind(b, hint))
	return card


## Строка стоимости: для каждого ресурса — [иконка + число]. Фиксированный порядок
## дерево→сталь, чтобы карточки выглядели единообразно.
func _cost_row(cost: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for r in ["wood", "steel", "wall"]:
		if not cost.has(r):
			continue
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(_res_icon_rect(r, 18))
		var amount := Label.new()
		amount.text = str(int(cost[r]))
		amount.add_theme_font_size_override("font_size", 14)
		amount.add_theme_color_override("font_color", UiStyle.TEXT)
		amount.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(amount)
		row.add_child(cell)
	return row


## Иконка ресурса (белый монохром-глиф; тонируется цветом при желании).
func _res_icon_rect(r: String, sz: int) -> TextureRect:
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(sz, sz)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var path := "res://assets/icons/%s.png" % RES_ICON.get(r, r)
	if ResourceLoader.exists(path):
		t.texture = load(path)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Текстура-иконка постройки (или null, если не задана/не найдена).
func _icon_for(building_name: String) -> Texture2D:
	var key: String = ICON.get(building_name, "")
	var path := "res://assets/icons/%s.png" % key
	return load(path) if key != "" and ResourceLoader.exists(path) else null


## Доступна ли постройка сейчас (открыт тир И хватает ресурсов рюкзак+склад).
func _is_available(b: Dictionary) -> bool:
	if InventorySystem.shelter_tier < int(b.get("min_tier", 1)):
		return false
	return _can_afford(b.cost)


## Клик по карточке: доступную — строим и закрываем меню; недоступную — не строим,
## а «высвечиваем» маленькую подсказку с причиной (тир/ресурсы).
func _on_card_pressed(b: Dictionary, hint: Label) -> void:
	var min_tier: int = int(b.get("min_tier", 1))
	if InventorySystem.shelter_tier < min_tier:
		hint.text = "нужен Тир %d" % min_tier
		hint.visible = true
		return
	if not _can_afford(b.cost):
		hint.text = "не хватает ресурсов"
		hint.visible = true
		return
	_on_pick(b.name)


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


## Хватает ли ресурсов (рюкзак + склад) на постройку.
func _can_afford(cost: Dictionary) -> bool:
	for r in cost:
		if InventorySystem.get_total_resource(r) < int(cost[r]):
			return false
	return true
