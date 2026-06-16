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
		if _alert_timer <= 0.0:
			alert_label.visible = false

	# Финальная фаза эвакуации (Этап 4.11): обратный отсчёт до зоны.
	if is_instance_valid(_game_state_manager) and _game_state_manager.evac_active:
		var t := int(ceil(_game_state_manager.get_evac_time_left()))
		evac_label.text = "🚁 Эвакуация: %d с — к зелёному лучу!" % t
		evac_label.modulate = Color(0.3, 1.0, 0.7) if t > 10 else Color(1.0, 0.5, 0.2)
		evac_label.visible = true
	else:
		evac_label.visible = false

	_update_power()
	_update_ability()


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
			var pg := get_tree().get_first_node_in_group("player")
			var scd: float = pg._sprint_cd if is_instance_valid(pg) and "_sprint_cd" in pg else 0.0
			var st: float = pg._sprint_timer if is_instance_valid(pg) and "_sprint_timer" in pg else 0.0
			if st > 0.0:
				ability_label.text = "Ускорение (F): активно"
			else:
				ability_label.text = "Ускорение (F): %s" % ("готов" if scd <= 0.0 else "%d c" % ceili(scd))
		"engineer":
			ability_label.text = "C4 (F): %d" % InventorySystem.c4_charges


func _on_game_over(victory: bool) -> void:
	result_label.text = "ПОБЕДА!\nНажмите R для рестарта" if victory else "ПОРАЖЕНИЕ\nНажмите R для рестарта"
	result_screen.visible = true


func _on_inventory_changed(inventory: Dictionary) -> void:
	var text = ""
	for resource_type in inventory:
		var label_name: String = RESOURCE_NAMES.get(resource_type, resource_type.capitalize())
		text += "%s: %d\n" % [label_name, inventory[resource_type]]
	inventory_label.text = text.strip_edges()


func _on_money_changed(amount: int) -> void:
	money_label.text = "Деньги: %d$" % amount


func _on_health_changed(current: float, maximum: float) -> void:
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
	alert_label.visible = true
	_alert_timer = ALERT_DURATION
