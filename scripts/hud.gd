## Управление HUD элементами.

extends CanvasLayer

@onready var inventory_label: Label = $InventoryLabel


func _ready() -> void:
	InventorySystem.inventory_changed.connect(_on_inventory_changed)
	_on_inventory_changed(InventorySystem.inventory)


func _on_inventory_changed(inventory: Dictionary) -> void:
	var text = ""
	for resource_type in inventory:
		text += "%s: %d\n" % [resource_type.capitalize(), inventory[resource_type]]
	inventory_label.text = text.strip_edges()
