## Автозагрузка для управления инвентарём.
## Сигнал говорит HUD-у что нужно обновиться.

extends Node

signal inventory_changed(inventory: Dictionary)
signal money_changed(amount: int)  ## деньги — вторая валюта (Этап 4.7.2)
signal tier_changed(new_tier: int)  ## тир убежища (Этап 4.15)

## Лимит для собираемых стройматериалов оригинала (дерево/сталь) — Этап 4.16.
const RESOURCE_CAP := 40
const CAPPED_RESOURCES := ["wood", "steel"]

var inventory: Dictionary = {
	"wood": 0,
	"steel": 0,  # переименовано из "stone" — стройматериал, как в оригинале (Этап 4.16)
	"turret_ammo": 0,  # расходник для турелей (Этап 4.8.1)
	# Электричество (Этап 4.16, замена fuel): НЕ собирается на карте, а
	# производится генераторами (до 4 шт., generator.gd) и тратится турелями.
	"electricity": 0,
}

# Деньги (Этап 4.7.2): отдельная валюта, не входит в inventory.
# Ресурсы (дерево/камень) идут на крафт и постройку, деньги — на покупки
# в мастерской (стены, лечение). Деньги капают за убийство зомби.
var money: int = 0

# Тир убежища (Этап 4.15): прокачка через мастерскую открывает доступ
# к более продвинутым постройкам (Мортира — Тир 2, Гатлинг — Тир 3)
# и снижает расход топлива генератора на Тир 4.
const MAX_TIER := 4
var shelter_tier: int = 1


func _ready() -> void:
	pass


## Добавить ресурс в инвентарь.
func add_resource(resource_type: String, amount: int) -> void:
	if resource_type not in inventory:
		inventory[resource_type] = 0
	inventory[resource_type] += amount
	if resource_type in CAPPED_RESOURCES:
		inventory[resource_type] = mini(inventory[resource_type], RESOURCE_CAP)
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


## Поднять тир убежища на 1 (вызывается мастерской после оплаты апгрейда).
func set_tier(new_tier: int) -> void:
	shelter_tier = new_tier
	tier_changed.emit(shelter_tier)
