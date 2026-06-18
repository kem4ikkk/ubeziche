## Управление HUD элементами.

extends CanvasLayer

@onready var inventory_label: Label = $InventoryLabel
@onready var money_label: Label = $MoneyLabel
@onready var health_label: Label = $HealthLabel
@onready var ammo_label: Label = $AmmoLabel
@onready var phase_label: Label = $PhaseLabel
@onready var tier_label: Label = $TierLabel
@onready var result_screen: ColorRect = $ResultScreen
@onready var result_label: Label = $ResultScreen/ResultLabel
@onready var alert_label: Label = $AlertLabel
@onready var evac_label: Label = $EvacLabel
@onready var power_label: Label = $PowerLabel
@onready var ability_label: Label = $AbilityLabel

# HUD-панели (Этап UI-1/UI-3) — строятся кодом в _ready (единый стиль, полосы,
# иконки ресурсов, прицел, баннеры тревог, экран итога, виньетка).
var _sanity_label: Label
var _sanity_fill: ColorRect
var _hp_fill: ColorRect
var _vignette: TextureRect
var _wood_val: Label
var _steel_val: Label
var _alert_panel: PanelContainer
var _evac_panel: PanelContainer
var _hp_cur: float = 100.0
var _hp_max: float = 100.0
const BAR_W := 230.0

const ALERT_DURATION := 2.5  ## сколько секунд держим тревожное сообщение (Этап 4.9)

var _day_night_cycle: Node
var _game_state_manager: Node
var _wave_manager: Node
var _weapon_name: String = "Пистолет"
var _alert_timer: float = 0.0
var _power_short: bool = false  ## была ли нехватка питания в прошлый кадр (Этап 4.25)

# Понятные русские названия ресурсов для HUD.
const RESOURCE_NAMES := {
	"wood": "Дерево",
	"steel": "Сталь",
	"wall": "Стена",
}


func _ready() -> void:
	add_to_group("hud")
	process_mode = Node.PROCESS_MODE_ALWAYS
	InventorySystem.inventory_changed.connect(_on_inventory_changed)
	_on_inventory_changed(InventorySystem.inventory)
	InventorySystem.money_changed.connect(_on_money_changed)
	_on_money_changed(InventorySystem.money)

	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.has_node("HealthComponent"):
		var health: HealthComponent = player.get_node("HealthComponent")
		health.health_changed.connect(_on_health_changed)
		_on_health_changed(health.current_health, health.max_health)
	if is_instance_valid(player) and player.has_signal("ammo_changed"):
		player.ammo_changed.connect(_on_ammo_changed)
		_on_ammo_changed(player.current_ammo, player.magazine_size)
	if is_instance_valid(player) and player.has_signal("weapon_changed"):
		player.weapon_changed.connect(_on_weapon_changed)
		_on_weapon_changed(player.weapons[player.current_weapon_index].name)

	EventBus.building_damaged.connect(_on_building_damaged)
	EventBus.juggernaut_spawned.connect(_on_juggernaut_spawned)
	EventBus.juggernaut_defeated.connect(_on_juggernaut_defeated)
	EventBus.evacuation_started.connect(_on_evacuation_started)
	EventBus.power_lost.connect(_on_power_lost)
	EventBus.power_restored.connect(_on_power_restored)
	EventBus.screamer_called.connect(_on_screamer_called)
	EventBus.special_wave.connect(_on_special_wave)
	EventBus.boss_spawned.connect(_on_boss_spawned)
	EventBus.boss_defeated.connect(_on_boss_defeated)

	InventorySystem.tier_changed.connect(_on_tier_changed)
	tier_label.text = "Тир убежища: %d" % InventorySystem.shelter_tier

	_build_hud_panels()


## Реструктуризация HUD (Этап UI-1): единый Theme + три сгруппированные тёмные
## панели (ресурсы ↖, статус ↗, витальное ↙ с полосами HP/рассудка) + виньетка.
## Существующие лейблы переносим в контейнеры (ссылки @onready остаются валидны).
func _build_hud_panels() -> void:
	var th := UiStyle.theme()

	# Виньетка — самым нижним слоем HUD (над миром, под текстом).
	_vignette = TextureRect.new()
	_vignette.texture = _make_vignette_tex()
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate = Color(1, 1, 1, 0.0)
	add_child(_vignette)
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	move_child(_vignette, 0)

	# ↖ Ресурсы (строки с иконками).
	var rv := _panel_vbox(_make_panel(th, 0, 0, Vector2(12, 12)))
	inventory_label.visible = false                    # старый мультилейбл не нужен
	var wr := _icon_row(rv, "wood"); _wood_val = Label.new(); _tune_label(_wood_val, 19, UiStyle.TEXT); wr.add_child(_wood_val)
	var sr := _icon_row(rv, "steel"); _steel_val = Label.new(); _tune_label(_steel_val, 19, UiStyle.TEXT); sr.add_child(_steel_val)
	var mr := _icon_row(rv, "coin"); _reparent(money_label, mr); _tune_label(money_label, 19, UiStyle.ACCENT)
	var pr := _icon_row(rv, "bolt"); _reparent(power_label, pr); _tune_label(power_label, 15, UiStyle.MUTED)

	# ↗ Статус (день/ночь, тир).
	var sv := _panel_vbox(_make_panel(th, 1, 0, Vector2(-12, 12)))
	_reparent(phase_label, sv); _tune_label(phase_label, 19, UiStyle.TEXT)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_reparent(tier_label, sv); _tune_label(tier_label, 15, UiStyle.MUTED)
	tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# ↙ Витальное: HP-полоса, рассудок-полоса, способность, патроны.
	var vv := _panel_vbox(_make_panel(th, 0, 1, Vector2(12, -12)))
	var hp := _make_bar(UiStyle.GOOD)
	vv.add_child(hp.root)
	_hp_fill = hp.fill
	_reparent(health_label, hp.root)
	health_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	health_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tune_label(health_label, 14, Color(1, 1, 1))
	var san := _make_bar(Color(0.38, 0.78, 0.92))
	vv.add_child(san.root)
	_sanity_fill = san.fill
	_sanity_label = Label.new()
	san.root.add_child(_sanity_label)
	_sanity_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sanity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sanity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tune_label(_sanity_label, 14, Color(1, 1, 1))
	_reparent(ability_label, vv); _tune_label(ability_label, 16, UiStyle.WARN)
	_reparent(ammo_label, vv); _tune_label(ammo_label, 16, UiStyle.TEXT)

	_build_crosshair()
	_alert_panel = _wrap_banner(alert_label, 12.0, 28)     # тревоги волн/босса
	_evac_panel = _wrap_banner(evac_label, 64.0, 24)       # отсчёт эвакуации
	_wrap_result(th)                                       # экран победы/поражения

	# Начальное заполнение значений (контейнеры уже созданы).
	_on_inventory_changed(InventorySystem.inventory)
	_on_money_changed(InventorySystem.money)


## Тёмная панель-контейнер, прижатая к углу (ax/ay — 0/1 левый/правый, верх/низ).
func _make_panel(th: Theme, ax: int, ay: int, off: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme = th
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.anchor_left = ax; p.anchor_right = ax
	p.anchor_top = ay; p.anchor_bottom = ay
	p.grow_horizontal = Control.GROW_DIRECTION_END if ax == 0 else Control.GROW_DIRECTION_BEGIN
	p.grow_vertical = Control.GROW_DIRECTION_END if ay == 0 else Control.GROW_DIRECTION_BEGIN
	add_child(p)
	if ax == 0: p.offset_left = off.x
	else: p.offset_right = off.x
	if ay == 0: p.offset_top = off.y
	else: p.offset_bottom = off.y
	return p


func _panel_vbox(p: PanelContainer) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	return v


## Полоса (фон + заливка) фикс. ширины; ширину заливки задаёт код по доле.
func _make_bar(fill_color: Color) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = Vector2(BAR_W, 22)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = UiStyle.BAR_BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fill := ColorRect.new()
	fill.color = fill_color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.position = Vector2(2, 2)
	fill.size = Vector2(BAR_W - 4, 18)
	root.add_child(fill)
	return {"root": root, "fill": fill}


func _reparent(n: Node, p: Node) -> void:
	if n.get_parent() != null:
		n.get_parent().remove_child(n)
	p.add_child(n)


func _tune_label(l: Label, size: int, col: Color) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _icon_rect(icon_name: String, sz: int) -> TextureRect:
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(sz, sz)
	var path := "res://assets/icons/%s.png" % icon_name
	if ResourceLoader.exists(path):
		t.texture = load(path)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Строка «иконка + (значение)» для панели ресурсов; значение-лейбл добавляет вызвавший.
func _icon_row(parent: Control, icon_name: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(h)
	h.add_child(_icon_rect(icon_name, 24))
	return h


## Прицел-крест с зазором по центру (вместо точки), Этап UI-3.
func _build_crosshair() -> void:
	var ch := get_node_or_null("Crosshair")
	if ch is CanvasItem:
		(ch as CanvasItem).visible = false
	var col := Color(1, 1, 1, 0.85)
	var segs := [Rect2(-12, -1.5, 8, 3), Rect2(4, -1.5, 8, 3),
			Rect2(-1.5, -12, 3, 8), Rect2(-1.5, 4, 3, 8), Rect2(-1.5, -1.5, 3, 3)]
	for r in segs:
		var c := ColorRect.new()
		c.color = col
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.anchor_left = 0.5; c.anchor_top = 0.5; c.anchor_right = 0.5; c.anchor_bottom = 0.5
		c.offset_left = r.position.x; c.offset_top = r.position.y
		c.offset_right = r.position.x + r.size.x; c.offset_bottom = r.position.y + r.size.y
		add_child(c)


## Обёртка-баннер вокруг тревожного/эвакуационного лейбла (хаггит текст, тёмный фон).
func _wrap_banner(label: Label, top_off: float, fsize: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiStyle.panel_box(Color(0.07, 0.08, 0.10, 0.92), 8, 1))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.anchor_left = 0.5; p.anchor_right = 0.5; p.anchor_top = 0.0; p.anchor_bottom = 0.0
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_END
	add_child(p)
	p.offset_top = top_off
	_reparent(label, p)
	label.visible = true
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.add_theme_font_size_override("font_size", fsize)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	return p


## Экран победы/поражения: затемнение (есть) + центральная панель с крупным текстом.
func _wrap_result(th: Theme) -> void:
	var wrap := PanelContainer.new()
	wrap.theme = th
	wrap.add_theme_stylebox_override("panel", UiStyle.panel_box(Color(0.06, 0.07, 0.09, 0.97), 18, 2))
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.anchor_left = 0.5; wrap.anchor_right = 0.5; wrap.anchor_top = 0.5; wrap.anchor_bottom = 0.5
	wrap.grow_horizontal = Control.GROW_DIRECTION_BOTH
	wrap.grow_vertical = Control.GROW_DIRECTION_BOTH
	result_screen.add_child(wrap)
	var m := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		m.add_theme_constant_override(side, 48)
	for side in ["margin_top", "margin_bottom"]:
		m.add_theme_constant_override(side, 32)
	wrap.add_child(m)
	_reparent(result_label, m)
	result_label.add_theme_font_size_override("font_size", 44)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


## Радиальная виньетка (прозрачный центр → чёрные края) через GradientTexture2D.
func _make_vignette_tex() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 1)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 320
	t.height = 320
	return t


func _process(delta: float) -> void:
	# DayNightCycle может ещё не быть готов в момент _ready() HUD-а — ищем лениво.
	if not is_instance_valid(_day_night_cycle):
		_day_night_cycle = get_tree().get_first_node_in_group("day_night_cycle")

	if is_instance_valid(_day_night_cycle):
		var phase_name := "Ночь" if _day_night_cycle.is_night else "День"
		var time_left := ceili(_day_night_cycle.get_phase_time_left())
		phase_label.text = "%s: %d" % [phase_name, time_left]

	# GameStateManager тоже может быть готов позже HUD-а — ищем лениво.
	if not is_instance_valid(_game_state_manager):
		_game_state_manager = get_tree().get_first_node_in_group("game_state_manager")
		if is_instance_valid(_game_state_manager):
			_game_state_manager.game_over.connect(_on_game_over)

	# WaveManager тоже может появиться позже HUD-а — ищем лениво (Этап 4.9).
	if not is_instance_valid(_wave_manager):
		_wave_manager = get_tree().get_first_node_in_group("wave_manager")
		if is_instance_valid(_wave_manager):
			_wave_manager.wave_started.connect(_on_wave_started)
			_wave_manager.wave_cleared.connect(_on_wave_cleared)

	# Тревожное сообщение гаснет само через ALERT_DURATION секунд (Этап 4.9).
	if _alert_timer > 0.0:
		_alert_timer -= delta
		if _alert_timer <= 0.0 and _alert_panel != null:
			_alert_panel.visible = false

	# Финальная фаза эвакуации (Этап 4.11): обратный отсчёт до зоны.
	if is_instance_valid(_game_state_manager) and _game_state_manager.evac_active:
		var t := int(ceil(_game_state_manager.get_evac_time_left()))
		evac_label.text = "🚁 Эвакуация: %d с — к зелёному лучу!" % t
		evac_label.modulate = Color(0.3, 1.0, 0.7) if t > 10 else Color(1.0, 0.5, 0.2)
		if _evac_panel != null: _evac_panel.visible = true
	elif _evac_panel != null:
		_evac_panel.visible = false

	_update_power()
	_update_ability()
	_update_vitals()


## Полосы HP и рассудка + виньетка (Этап UI-1/1B). Ширину заливки берём от
## фактической ширины полосы (контейнер раскладывается уже после _ready).
func _update_vitals() -> void:
	# HP-полоса (красный → зелёный по доле).
	if _hp_fill != null and _hp_fill.get_parent() != null:
		var w: float = _hp_fill.get_parent().size.x - 4.0
		var hr: float = (_hp_cur / _hp_max) if _hp_max > 0.0 else 0.0
		_hp_fill.size.x = maxf(0.0, w * hr)
		_hp_fill.size.y = _hp_fill.get_parent().size.y - 4.0
		_hp_fill.color = Color(0.93, 0.30, 0.30) if hr < 0.3 else (Color(0.95, 0.72, 0.20) if hr < 0.6 else UiStyle.GOOD)

	# Полоса рассудка + виньетка.
	if _sanity_fill == null:
		return
	var p := get_tree().get_first_node_in_group("player")
	if not is_instance_valid(p) or not p.has_method("get_sanity_ratio"):
		return
	var r: float = p.get_sanity_ratio()
	var sw: float = _sanity_fill.get_parent().size.x - 4.0
	_sanity_fill.size.x = maxf(0.0, sw * r)
	_sanity_fill.size.y = _sanity_fill.get_parent().size.y - 4.0
	if r > 0.4:
		_sanity_fill.color = Color(0.38, 0.78, 0.92)
	elif r > 0.15:
		_sanity_fill.color = Color(0.95, 0.62, 0.22)
	else:
		_sanity_fill.color = Color(0.95, 0.28, 0.28)
	_sanity_label.text = "Рассудок: %d%%" % roundi(r * 100.0)
	# Затемнение краёв нарастает, когда рассудок ниже 40%.
	_vignette.modulate.a = clampf((0.4 - r) / 0.4, 0.0, 1.0) * 0.72


## Строка питания (Этап 4.25): бюджет мощности генераторов vs потребление
## турелей. Красным, если нагрузка превышает мощность (часть турелей стоит).
func _update_power() -> void:
	var supply := 0
	for g in get_tree().get_nodes_in_group("generator"):
		if g.has_method("get_power_output"):
			supply += g.get_power_output()
	var demand := 0
	for t in get_tree().get_nodes_in_group("turret"):
		demand += int(t.power_cost) if "power_cost" in t else 30
	power_label.text = "Питание: %d / %d" % [demand, supply]
	power_label.modulate = Color(1.0, 0.4, 0.4) if demand > supply else Color(1, 1, 1)
	# Оповещение при появлении/снятии нехватки питания.
	var short: bool = demand > supply
	if short != _power_short:
		_power_short = short
		if short:
			_on_power_lost()
		else:
			_on_power_restored()


## Индикатор сигнатурной способности класса (Этап 4.12b): статус Авиаудара,
## наличие Костра или число зарядов C4. Пусто, если класс/способность не выбраны.
func _update_ability() -> void:
	var cls: String = InventorySystem.player_class
	if cls == "" or not InventorySystem.ability_unlocked():
		ability_label.text = ""
		return
	match cls:
		"combat":
			var p := get_tree().get_first_node_in_group("player")
			var cd: float = p._airstrike_cd if is_instance_valid(p) and "_airstrike_cd" in p else 0.0
			ability_label.text = "Авиаудар (F): %s" % ("готов" if cd <= 0.0 else "%d c" % ceili(cd))
		"gather":
			ability_label.text = "Маскировка (F): готов"
		"engineer":
			ability_label.text = "C4 (F): %d" % InventorySystem.c4_charges


func _on_game_over(victory: bool) -> void:
	result_label.text = "ПОБЕДА!\nНажмите R для рестарта" if victory else "ПОРАЖЕНИЕ\nНажмите R для рестарта"
	result_label.modulate = Color(0.4, 1.0, 0.5) if victory else Color(1.0, 0.42, 0.42)
	result_screen.visible = true


func _on_inventory_changed(inventory: Dictionary) -> void:
	# Показываем только собираемые ресурсы (дерево/сталь) — строками с иконками.
	# «Стена» — это постройка (ставится в B-меню), в HUD не выводится.
	if _wood_val == null:
		return
	_wood_val.text = "Дерево: %d" % int(inventory.get("wood", 0))
	_steel_val.text = "Сталь: %d" % int(inventory.get("steel", 0))


func _on_money_changed(amount: int) -> void:
	money_label.text = "Деньги: %d$" % amount


func _on_health_changed(current: float, maximum: float) -> void:
	_hp_cur = current
	_hp_max = maximum
	health_label.text = "HP: %d / %d" % [current, maximum]


func _on_ammo_changed(current: int, magazine: int) -> void:
	# Топор (Этап 4.21): magazine < 0 — оружие ближнего боя, патронов нет.
	if magazine < 0:
		ammo_label.text = "%s — ближний бой" % _weapon_name
	else:
		ammo_label.text = "%s — Патроны: %d / %d" % [_weapon_name, current, magazine]


func _on_weapon_changed(weapon_name: String) -> void:
	_weapon_name = weapon_name
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		# С топором патроны не показываем (Этап 4.21).
		if "axe_equipped" in player and player.axe_equipped:
			_on_ammo_changed(-1, -1)
		else:
			_on_ammo_changed(player.current_ammo, player.magazine_size)


## Индикаторы угроз (Этап 4.9).
func _on_building_damaged(building_name: String) -> void:
	_show_alert("⚠ Атакована постройка: %s!" % building_name, Color(1.0, 0.3, 0.3))


func _on_wave_started(wave_number: int) -> void:
	_show_alert("⚠ Волна %d: зомби приближаются!" % wave_number, Color(1.0, 0.85, 0.2))


func _on_wave_cleared(wave_number: int) -> void:
	_show_alert("Волна %d зачищена!" % wave_number, Color(0.4, 1.0, 0.4))


## Мини-босс (Этап 4.10).
func _on_juggernaut_spawned() -> void:
	_show_alert("⚠ ДЖАГГЕРНАУТ ПРОРЫВАЕТСЯ!", Color(0.8, 0.3, 1.0))


func _on_juggernaut_defeated() -> void:
	_show_alert("Джаггернаут повержен!", Color(0.4, 1.0, 0.4))


## Крикун позвал подмогу (Этап 4.13a).
func _on_screamer_called() -> void:
	_show_alert("⚠ Крикун зовёт орду!", Color(1.0, 0.85, 0.2))


## Спецволна (Этап 4.13b): объявление типа ночи.
func _on_special_wave(label: String) -> void:
	_show_alert("⚠ %s" % label, Color(1.0, 0.5, 0.2))


## Босс (Этап 4.13b): появление и гибель.
func _on_boss_spawned(boss_name: String, _max_hp: float) -> void:
	_show_alert("☠ БОСС: %s!" % boss_name, Color(1.0, 0.3, 0.3))


func _on_boss_defeated() -> void:
	_show_alert("Босс повержен!", Color(0.4, 1.0, 0.4))


## Финальная фаза эвакуации (Этап 4.11).
func _on_evacuation_started() -> void:
	_show_alert("🚁 ВЫЗВАН ТРАНСПОРТ! Бегите к зоне эвакуации!", Color(0.3, 1.0, 0.7))


## Система питания (Этап 4.14).
func _on_power_lost() -> void:
	_show_alert("⚡ НЕТ ПИТАНИЯ — турели простаивают!", Color(1.0, 0.3, 0.3))


func _on_power_restored() -> void:
	_show_alert("⚡ Питание восстановлено — турели снова работают", Color(0.4, 1.0, 0.4))


## Тиры убежища (Этап 4.15).
func _on_tier_changed(new_tier: int) -> void:
	tier_label.text = "Тир убежища: %d" % new_tier
	_show_alert("🔧 Убежище улучшено до Тир %d!" % new_tier, Color(0.4, 1.0, 0.4))


func _show_alert(text: String, color: Color) -> void:
	alert_label.text = text
	alert_label.modulate = color
	if _alert_panel != null:
		_alert_panel.visible = true
	_alert_timer = ALERT_DURATION
