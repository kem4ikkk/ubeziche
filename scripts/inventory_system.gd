## Автозагрузка для управления инвентарём.
## Сигнал говорит HUD-у что нужно обновиться.

extends Node

signal inventory_changed(inventory: Dictionary)
signal money_changed(amount: int)  ## деньги — вторая валюта (Этап 4.7.2)

var inventory: Dictionary = {
	"wood": 0,
	"stone": 0,
	"turret_ammo": 0,  # расходник для турелей (Этап 4.8.1)
	"fuel": 30,  # топливо генератора — без него турели не питаются (Этап 4.14)
}

# Деньги (Этап 4.7.2): отдельная валюта, не входит в inventory.
# Ресурсы (дерево/камень) идут на крафт и постройку, деньги — на покупки
# в мастерской (стены, лечение). Деньги капают за убийство зомби.
var money: int = 0


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


## Начислить деньги (Этап 4.7.2): например, за убийство зомби.
func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)


## Потратить деньги (возвращает true, если хватило).
func spend_money(amount: int) -> bool:
	if money >= amount:
		money -= amount
		money_changed.emit(money)
		return true
	return false


## Получить текущее количество денег.
func get_money() -> int:
	return money
