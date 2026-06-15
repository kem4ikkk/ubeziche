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

# Молот (Этап 4.17): постоянный инструмент, крафтится один раз в мастерской.
# Пока есть — ремонт построек (player.gd: repair_target) восстанавливает
# вдвое больше HP за один удар, как в оригинале ("чинит конструкции быстрее").
var has_hammer: bool = false

# Навыки (Этап 4.23): очки и уровни веток. Как в оригинале (New Zombie Shelter,
# меню по N): на старте 3 очка, +1 за каждую пережитую ночь. Очко тратится на
# повышение уровня одной из веток в меню навыков (scenes/skill_menu.tscn).
signal skills_changed()

var skill_points: int = 3

# Ветка «Добыча» (Этап 4.22): сколько ресурса даёт один удар топором по узлу
# (resource_pickup.gd: hit). База 1, прокачка 1→2→3. Выше навык — больше за удар.
var gather_level: int = 1
# Ветка «Бой»: бонус к урону топором в ближнем бою (player.gd: swing_axe).
var combat_level: int = 0
# Ветка «Инженер»: бонус к ремонту построек топором; открывает крафт
# инструментов в мастерской (Этап 4.26).
var engineer_level: int = 0

# Максимальные уровни веток (стоимость уровня — 1 очко).
const SKILL_MAX := {"gather": 3, "combat": 3, "engineer": 3}


func _ready() -> void:
	# EventBus загружается после InventorySystem — подписываемся отложенно,
	# когда все автозагрузки уже готовы (Этап 4.23).
	_connect_events.call_deferred()


## Подписка на «ночь пережита» для начисления очка навыка (Этап 4.23).
func _connect_events() -> void:
	if EventBus.has_signal("night_survived"):
		EventBus.night_survived.connect(_on_night_survived)


func _on_night_survived() -> void:
	add_skill_point(1)


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


## Текущий уровень ветки навыка (Этап 4.23).
func get_skill_level(branch: String) -> int:
	match branch:
		"gather": return gather_level
		"combat": return combat_level
		"engineer": return engineer_level
	return 0


## Повысить ветку навыка за 1 очко (Этап 4.23). Возвращает true при успехе.
func upgrade_skill(branch: String) -> bool:
	if not SKILL_MAX.has(branch):
		return false
	if skill_points <= 0:
		print("Навыки: нет свободных очков")
		return false
	if get_skill_level(branch) >= SKILL_MAX[branch]:
		print("Навыки: ветка «", branch, "» уже максимального уровня")
		return false
	skill_points -= 1
	match branch:
		"gather": gather_level += 1
		"combat": combat_level += 1
		"engineer": engineer_level += 1
	print("Навыки: ветка «", branch, "» повышена до ", get_skill_level(branch),
			" (осталось очков: ", skill_points, ")")
	skills_changed.emit()
	return true


## Начислить очко навыка за пережитую ночь (Этап 4.23).
func add_skill_point(amount: int = 1) -> void:
	skill_points += amount
	print("Навыки: +", amount, " очко за пережитую ночь (всего ", skill_points, ")")
	skills_changed.emit()
