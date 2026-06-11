## Управление HUD элементами.

extends CanvasLayer

@onready var inventory_label: Label = $InventoryLabel
@onready var health_label: Label = $HealthLabel


func _ready() -> void:
	InventorySystem.inventory_changed.connect(_on_inventory_changed)
	_on_inventory_changed(InventorySystem.inventory)

	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.has_node("HealthComponent"):
		var health: HealthComponent = player.get_node("HealthComponent")
		health.health_changed.connect(_on_health_changed)
		_on_health_changed(health.current_health, health.max_health)


func _on_inventory_changed(inventory: Dictionary) -> void:
	var text = ""
	for resource_type in inventory:
		text += "%s: %d\n" % [resource_type.capitalize(), inventory[resource_type]]
	inventory_label.text = text.strip_edges()


func _on_health_changed(current: float, maximum: float) -> void:
	health_label.text = "HP: %d / %d" % [current, maximum]
