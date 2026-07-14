extends CanvasLayer

## UI-меню Склада (Warehouse, Этап 4.43): открывается клавишей E рядом со складом
## (storage.gd). Здесь игрок перекладывает дерево/сталь между РЮКЗАКОМ (лимит
## переноски) и домашним ХРАНИЛИЩЕМ (ёмкость от построенных складов). В поле
## собираешь в рюкзак, дома сдаёшь излишки на склад; тратить на крафт/постройку
## можно из общего запаса (рюкзак + склад).

@onready var _list: VBoxContainer = $Panel/VBox/List

const RES := ["wood", "steel"]
const RES_NAME := {"wood": "Дерево", "steel": "Сталь"}

var _capture_mode := false


func _ready() -> void:
	add_to_group("warehouse_menu")
	_capture_mode = OS.get_cmdline_user_args().has("--capture")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_apply_style()
	# Пока меню открыто — обновляем цифры при любом изменении рюкзака/склада.
	InventorySystem.inventory_changed.connect(func(_i: Dictionary) -> void: _refresh())
	InventorySystem.storage_changed.connect(func(_s: Dictionary, _c: int) -> void: _refresh())


func _apply_style() -> void:
	($Panel as Panel).theme = UiStyle.theme()
	var title := $Panel/VBox/TitleLabel as Label
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UiStyle.ACCENT)


## Открыть/закрыть меню (вызывается из storage.gd по клавише E).
func toggle() -> void:
	visible = not visible
	if visible:
		_rebuild()
	# Паузы в игре НЕТ — только курсор для кликов (как у мастерской).
	if not _capture_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED


## Закрыть меню, если открыто (для Esc из player.gd).
func close() -> void:
	if visible:
		toggle()


## Перестроить список только при открытии/действии.
func _refresh() -> void:
	if visible:
		_rebuild()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var cap: int = InventorySystem.get_resource_cap()
	var scap: int = InventorySystem.get_storage_capacity()

	# Сводка: сколько в рюкзаке и на складе.
	for r in RES:
		var bag: int = InventorySystem.get_resource(r)
		var st: int = InventorySystem.get_stored(r)
		_add_info("%s — рюкзак %d/%d · склад %d/%d" % [RES_NAME[r], bag, cap, st, scap])

	if scap <= 0:
		_add_info("Склад не построен — негде хранить (ёмкость 0).")
		return

	# Массовые действия.
	var can_dep_any := false
	var can_wd_any := false
	for r in RES:
		if _dep_room(r) > 0: can_dep_any = true
		if _wd_room(r) > 0: can_wd_any = true
	_add_button("Сдать всё на склад", not can_dep_any,
			func() -> void: InventorySystem.deposit_all(); _rebuild())
	_add_button("Забрать всё со склада", not can_wd_any,
			func() -> void: InventorySystem.withdraw_all(); _rebuild())

	# Пер-ресурсные кнопки (сдать/забрать всё по ресурсу).
	for r in RES:
		var dep: int = _dep_room(r)
		var wd: int = _wd_room(r)
		_add_button("Сдать %s (%d)" % [RES_NAME[r].to_lower(), dep], dep <= 0,
				func() -> void: InventorySystem.deposit(r, dep); _rebuild())
		_add_button("Забрать %s (%d)" % [RES_NAME[r].to_lower(), wd], wd <= 0,
				func() -> void: InventorySystem.withdraw(r, wd); _rebuild())


## Сколько можно сдать ресурса (ограничение: что в рюкзаке и свободное место склада).
func _dep_room(r: String) -> int:
	var free: int = InventorySystem.get_storage_capacity() - InventorySystem.get_stored(r)
	return maxi(0, mini(InventorySystem.get_resource(r), free))


## Сколько можно забрать ресурса (ограничение: что на складе и свободное место рюкзака).
func _wd_room(r: String) -> int:
	var free: int = InventorySystem.get_resource_cap() - InventorySystem.get_resource(r)
	return maxi(0, mini(InventorySystem.get_stored(r), free))


func _add_info(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", UiStyle.MUTED)
	_list.add_child(l)


func _add_button(text: String, disabled: bool, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.disabled = disabled
	if not disabled and cb.is_valid():
		btn.pressed.connect(cb)
	_list.add_child(btn)
