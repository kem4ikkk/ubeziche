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
	# Электричество больше НЕ ресурс-запас (Этап 4.25): питание турелей — это
	# мгновенный бюджет мощности (сумма генераторов vs сумма турелей), считается
	# в turret.gd/hud.gd по группам, а не хранится здесь. Боезапас турелей убран.
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

# Классовые инструменты (Этап 4.27): крафтятся в мастерской по уровню ветки
# навыка, дают баффы (не добычу — добыча только от навыка «Добыча»):
#  has_knife (Бой)         — +урон топора, чуть выше скорость атаки;
#  has_improved_axe (Добыча) — самая высокая скорость атаки (быстрее всех);
#  has_hammer (Инженер)    — ремонт x2 HP + скорость атаки как у ножа.
var has_hammer: bool = false
var has_knife: bool = false
var has_improved_axe: bool = false

# Навыки (Этап 4.23): очки. Как в оригинале (New Zombie Shelter, меню по N):
# на старте 3 очка, +1 за каждую пережитую ночь.
signal skills_changed()

var skill_points: int = 3

# Узлы-навыки (правка 2026-06-17): каждая ветка — несколько ОТДЕЛЬНЫХ навыков со
# своей иконкой и уровнем 1..3 (раньше ветка была одной общей цифрой, и игроку
# было непонятно, что именно качается). Класс выбирается отдельно и открывает
# сигнатуру (верхний узел) своей ветки. На СТАРТЕ всё на 0 — ничего не вкачано.
#
# Реестр навыков: id → {branch, name, icon}. Порядок здесь = порядок в ветке
# (первым идёт НИЖНИЙ узел, над «выбором класса»). Эффект каждого навыка
# применяется ПО ЕГО УРОВНЮ в соответствующем потребителе:
#   melee    — урон топора по зомби (player.swing_axe):       +4/ур.
#   vigor    — макс HP (player._apply_combat_hp):              +15/ур.
#   gather   — ресурса за удар (resource_pickup.hit):  база 1 +1/ур → 2/3/4.
#   capacity — лимит дерева/стали (get_resource_cap):         +20/ур.
#   repair   — % к ремонту построек (player._repair_building): +5%/ур.
#   turret   — % к урону турелей (turret._try_fire):          +5%/ур.
const SKILLS := {
	"melee":    {"branch": "combat",   "name": "Сила удара", "icon": "sword"},
	"vigor":    {"branch": "combat",   "name": "Закалка",    "icon": "heart"},
	"gather":   {"branch": "gather",   "name": "Сбор",       "icon": "pickaxe"},
	"capacity": {"branch": "gather",   "name": "Запас",      "icon": "backpack"},
	"repair":   {"branch": "engineer", "name": "Ремонт",     "icon": "hammer"},
	"turret":   {"branch": "engineer", "name": "Турели",     "icon": "turret"},
}
const SKILL_MAX_LEVEL := 3

var skill_levels: Dictionary = {
	"melee": 0, "vigor": 0, "gather": 0, "capacity": 0, "repair": 0, "turret": 0,
}

# Класс игрока (Этап 4.12). Один из "combat"/"gather"/"engineer"; "" — ещё не
# выбран (класс выбирается в меню навыков N). Класс определяет ТОЛЬКО сигнатурную
# способность (верхний узел своей ветки, клавиша F).
signal class_changed(player_class: String)
var player_class: String = ""

# Сигнатурные способности (Этап 4.12): открываются узлом своей ветки за очко
# (нужен выбранный класс + хотя бы 1 вложенное очко в свою ветку). Эффект — в
# player.gd (клавиша F). Здесь — только состояние.
var has_airstrike: bool = false   # Боец — Авиаудар
var has_sprint: bool = false      # Добытчик — Ускорение
var has_c4: bool = false          # Инженер — право крафтить C4
var c4_charges: int = 0           # сколько зарядов C4 в наличии (крафт в мастерской)


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
		inventory[resource_type] = mini(inventory[resource_type], get_resource_cap())
	inventory_changed.emit(inventory)


## Лимит дерева/стали: базовый + навык «Запас» (capacity, +20 за уровень).
func get_resource_cap() -> int:
	return RESOURCE_CAP + 20 * int(skill_levels.get("capacity", 0))


## Сколько ресурса даёт один удар топором по узлу: база 1 + уровень навыка «Сбор».
func gather_yield() -> int:
	return 1 + int(skill_levels.get("gather", 0))


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


## Текущий уровень узла-навыка по его id (melee/vigor/gather/capacity/repair/turret).
func get_skill_level(skill_id: String) -> int:
	return int(skill_levels.get(skill_id, 0))


## Сколько всего очков вложено в ветку (сумма уровней её узлов). Нужно для ворот
## сигнатурной способности (≥1) и для подписи ветки в меню.
func get_branch_level(branch: String) -> int:
	var total := 0
	for id in SKILLS:
		if SKILLS[id].branch == branch:
			total += int(skill_levels.get(id, 0))
	return total


## Поднять узел-навык на 1 уровень за 1 очко. Возвращает true при успехе.
func upgrade_skill(skill_id: String) -> bool:
	if not SKILLS.has(skill_id):
		return false
	if skill_points <= 0:
		print("Навыки: нет свободных очков")
		return false
	if int(skill_levels.get(skill_id, 0)) >= SKILL_MAX_LEVEL:
		print("Навыки: «", skill_id, "» на потолке (", SKILL_MAX_LEVEL, ")")
		return false
	skill_points -= 1
	skill_levels[skill_id] = int(skill_levels.get(skill_id, 0)) + 1
	print("Навыки: «", skill_id, "» → ур.", skill_levels[skill_id],
			" (осталось очков: ", skill_points, ")")
	skills_changed.emit()
	return true


## Начислить очко навыка за пережитую ночь (Этап 4.23).
func add_skill_point(amount: int = 1) -> void:
	skill_points += amount
	print("Навыки: +", amount, " очко за пережитую ночь (всего ", skill_points, ")")
	skills_changed.emit()


## Потолок любого узла-навыка — SKILL_MAX_LEVEL (3).
func get_skill_cap(_skill_id: String = "") -> int:
	return SKILL_MAX_LEVEL


## Выбрать класс игрока (Этап 4.12). Вызывается экраном выбора класса один раз
## за забег. Меняет идентичность: своя ветка/способность/стат-бонусы.
func set_class(c: String) -> void:
	if c not in ["combat", "gather", "engineer"]:
		return
	player_class = c
	print("Класс выбран: ", c)
	class_changed.emit(player_class)
	skills_changed.emit()


## Открыта ли сигнатурная способность СВОЕГО класса.
func ability_unlocked() -> bool:
	match player_class:
		"combat": return has_airstrike
		"gather": return has_sprint
		"engineer": return has_c4
	return false


## Открыть сигнатурную способность своего класса за 1 очко (Этап 4.12).
## Требует выбранного класса и уровня своей ветки ≥ 1. Возвращает true при успехе.
func unlock_ability() -> bool:
	if player_class == "" or ability_unlocked():
		return false
	if get_branch_level(player_class) < 1:
		print("Навыки: сначала вложите очко в свою ветку")
		return false
	if skill_points <= 0:
		print("Навыки: нет свободных очков")
		return false
	skill_points -= 1
	match player_class:
		"combat": has_airstrike = true
		"gather": has_sprint = true
		"engineer": has_c4 = true
	print("Навыки: открыта сигнатурная способность класса «", player_class, "»")
	skills_changed.emit()
	return true


## Сбросить прогрессию класса/навыков для нового забега (Этап 4.12). Экран
## выбора класса вызывает это при старте сцены, чтобы класс выбирался заново
## (InventorySystem — автозагрузка и переживает reload_current_scene).
func reset_run_progression() -> void:
	player_class = ""
	skill_points = 3
	for id in skill_levels:
		skill_levels[id] = 0          # на старте ничего не вкачано
	has_airstrike = false
	has_sprint = false
	has_c4 = false
	c4_charges = 0
	skills_changed.emit()
