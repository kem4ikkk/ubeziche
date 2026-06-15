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

const ALERT_DURATION := 2.5  ## сколько секунд держим тревожное сообщение (Этап 4.9)

var _day_night_cycle: Node
var _game_state_manager: Node
var _wave_manager: Node
var _weapon_name: String = "Пистолет"
var _alert_timer: float = 0.0

# Понятные русские названия ресурсов для HUD.
const RESOURCE_NAMES := {
	"wood": "Дерево",
	"steel": "Сталь",
	"wall": "Стена",
	"turret_ammo": "Патроны турелей",
	"electricity": "Электричество",
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
