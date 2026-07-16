extends CanvasLayer

## Меню покупки оружия чёрного рынка в стиле CS (Этап 4.44).
## Открывается по F рядом с рынком (black_market.gd). Категории: пистолеты /
## основное; недоступные по навыку — тусклые; покупка заменяет ствол в слоте.

@onready var _list: VBoxContainer = $Panel/VBox/List

var _capture_mode := false
var _player: Node


func _ready() -> void:
	add_to_group("market_menu")
	_capture_mode = OS.get_cmdline_user_args().has("--capture")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_apply_style()


func _apply_style() -> void:
	($Panel as Panel).theme = UiStyle.theme()
	var title := $Panel/VBox/TitleLabel as Label
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UiStyle.ACCENT)


func _resolve_player() -> Node:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	return _player


## Открыть/закрыть (F у рынка). Паузы нет — только курсор.
func toggle() -> void:
	visible = not visible
	if visible:
		_rebuild()
	if not _capture_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED


func close() -> void:
	if visible:
		toggle()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	var p := _resolve_player()
	if p == null:
		return

	_add_info("Деньги: %d$" % InventorySystem.get_money())
	_add_section("ПИСТОЛЕТЫ (слот 2)")
	_add_weapons(p, "pistol")
	_add_section("ОСНОВНОЕ (слот 1)")
	_add_weapons(p, "primary")
	_add_info("Покупка заменяет оружие в слоте. Esc / F — закрыть.")


func _add_weapons(p: Node, slot_name: String) -> void:
	var n := 0
	for i in p.weapons.size():
		var w: Dictionary = p.weapons[i]
		if w.get("slot", "") != slot_name:
			continue
		if int(w.get("price", 0)) <= 0 and slot_name == "pistol":
			# Стартовый пистолет в меню не продаём (уже есть в слоте 2).
			continue
		n += 1
		var unlocked: bool = p.is_weapon_unlocked(i)
		var price: int = p.get_weapon_price(i)
		var owned: bool = p.owns_weapon(i)
		var can_pay: bool = InventorySystem.get_money() >= price
		var label := "%d. %s — %d$" % [n, w.name, price]
		if owned:
			label += " (в слоте — дозарядка)"
		var locked_hint := ""
		if not unlocked:
			locked_hint = _skill_hint(w.get("skill", ""))
			label += "  🔒"
		var btn := Button.new()
		btn.text = label
		# Кнопка всегда кликабельна: недоступные — тусклые, по клику — причина.
		if not unlocked:
			btn.modulate = Color(1, 1, 1, 0.35)
			btn.pressed.connect(_flash_hint.bind(locked_hint))
		elif not can_pay:
			btn.modulate = Color(1, 1, 1, 0.45)
			btn.pressed.connect(_flash_hint.bind("не хватает денег (%d$)" % price))
		else:
			btn.modulate = Color(1, 1, 1, 1.0)
			btn.pressed.connect(_on_buy.bind(i))
		_list.add_child(btn)
	if n == 0:
		_add_info("  (пусто)")


func _skill_hint(skill_id: String) -> String:
	match skill_id:
		"weapon_basic": return "нужен навык «Мастер оружия (нач.)»"
		"weapon_mid": return "нужен навык «Мастер оружия (средн.)»"
		"weapon_adv": return "нужен навык «Мастер оружия (продв.)»"
	return "закрыто навыком"


func _on_buy(index: int) -> void:
	var p := _resolve_player()
	if p == null:
		return
	if p.buy_weapon(index):
		_rebuild()


func _flash_hint(text: String) -> void:
	print("Чёрный рынок: ", text)


func _add_section(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", UiStyle.WARN)
	_list.add_child(l)


func _add_info(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", UiStyle.MUTED)
	_list.add_child(l)
