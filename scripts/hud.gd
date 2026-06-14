## Управление HUD элементами.

extends CanvasLayer

@onready var inventory_label: Label = $InventoryLabel
@onready var health_label: Label = $HealthLabel
@onready var ammo_label: Label = $AmmoLabel
@onready var phase_label: Label = $PhaseLabel
@onready var result_screen: ColorRect = $ResultScreen
@onready var result_label: Label = $ResultScreen/ResultLabel

var _day_night_cycle: Node
var _game_state_manager: Node
var _weapon_name: String = "Пистолет"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	InventorySystem.inventory_changed.connect(_on_inventory_changed)
	_on_inventory_changed(InventorySystem.inventory)

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


func _process(_delta: float) -> void:
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


func _on_game_over(victory: bool) -> void:
	result_label.text = "ПОБЕДА!\nНажмите R для рестарта" if victory else "ПОРАЖЕНИЕ\nНажмите R для рестарта"
	result_screen.visible = true


func _on_inventory_changed(inventory: Dictionary) -> void:
	var text = ""
	for resource_type in inventory:
		text += "%s: %d\n" % [resource_type.capitalize(), inventory[resource_type]]
	inventory_label.text = text.strip_edges()


func _on_health_changed(current: float, maximum: float) -> void:
	health_label.text = "HP: %d / %d" % [current, maximum]


func _on_ammo_changed(current: int, magazine: int) -> void:
	ammo_label.text = "%s — Патроны: %d / %d" % [_weapon_name, current, magazine]


func _on_weapon_changed(weapon_name: String) -> void:
	_weapon_name = weapon_name
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player):
		_on_ammo_changed(player.current_ammo, player.magazine_size)
