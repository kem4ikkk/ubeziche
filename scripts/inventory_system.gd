## Автозагрузка для управления инвентарём.
## Сигнал говорит HUD-у что нужно обновиться.

extends Node

signal inventory_changed(inventory: Dictionary)

var inventory: Dictionary = {
	"wood": 0,
	"stone": 0,
}


func _ready() -> void:
	pass


## Добавить ресурс в инвентарь.
func add_resource(resource_type: String, amount: int) -> void:
	if resource_type not in inventory:
		inventory[resource_type] = 0
	inventory[resource_type] += amount
	inventory_changed.emit(inventory)


## Использовать ресурсы для крафта (возвращает true если достаточно).
func use_resource(resource_type: String, amount: int) -> bool:
	if inventory.get(resource_type, 0) >= amount:
		inventory[resource_type] -= amount
		inventory_changed.emit(inventory)
		return true
	return false


## Получить количество ресурса.
func get_resource(resource_type: String) -> int:
	return inventory.get(resource_type, 0)
