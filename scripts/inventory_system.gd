## Автозагрузка для управления инвентарём.
## Сигнал говорит HUD-у что нужно обновиться.

extends Node

signal inventory_changed(inventory: Dictionary)
signal money_changed(amount: int)  ## деньги — вторая валюта (Этап 4.7.2)
signal tier_changed(new_tier: int)  ## тир убежища (Этап 4.15)
## Склад изменился: домашний запас/ёмкость (Этап 4.43). HUD и меню слушают.
signal storage_changed(stored: Dictionary, capacity: int)

## Лимит ПЕРЕНОСКИ дерева/стали в РЮКЗАКЕ (Этап 4.43): база 20, навык «Мастерство
## сбора» даёт +3 за уровень. Склад НЕ повышает переноску — это отдельный запас.
const RESOURCE_CAP := 20
const CARRY_PER_GATHER_SKILL := 3
const CAPPED_RESOURCES := ["wood", "steel"]

var inventory: Dictionary = {
	"wood": 0,
	"steel": 0,  # переименовано из "stone" — стройматериал, как в оригинале (Этап 4.16)
	# Электричество больше НЕ ресурс-запас (Этап 4.25): питание турелей — это
	# мгновенный бюджет мощности (сумма генераторов vs сумма турелей), считается
	# в turret.gd/hud.gd по группам, а не хранится здесь. Боезапас турелей убран.
}

# Склад (Warehouse, Этап 4.43): ОТДЕЛЬНЫЙ домашний запас дерева/стали. Постройка
# «Склад» повышает ёмкость склада (storage_capacity), но НЕ размер рюкзака. Дома
# у мастерской ресурсы можно тратить и из рюкзака, и со склада (см. use_resource);
# в поле собираешь в рюкзак (лимит переноски), лишнее сдаёшь на склад.
var stored: Dictionary = {"wood": 0, "steel": 0}
var storage_capacity: int = 0

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

# Навыки (Этап 4.23 → 4.40, полные деревья оригинала). Очки: на старте 3, +1 за
# пережитую ночь. Меню по N.
signal skills_changed()

var skill_points: int = 3

# ПОЛНЫЕ ДЕРЕВЬЯ НАВЫКОВ (по оригиналу New Zombie Shelter, Этап 4.40). Каждая
# ветка = 3 вертикальные ЦЕПОЧКИ (колонки) по 3 узла (тиры 1..3) + ультимейт
# (тир 4). ПРАВИЛО: узел открывается, когда узел НИЖЕ в его колонке прокачан до
# своего максимума («предыдущая до 3»). КЛАСС выбирается на узле «мастерство»
# (средняя колонка, тир 2) — взяв одну мастерскую ветку, другие классы закрыты.
# Ультимейт ветки открывается после выбора её класса.
const SKILL_MAX_LEVEL := 3      # дефолтный потолок узла (если у узла нет своего "max")

# Структура «ёлочка» (гейты по этапам, Этап 4.40): tier1 (3 узла, открыты сразу)
# → mastery (узел «мастерство» = выбор класса; открыт, когда ЛЮБОЙ tier1 на макс.)
# → tier2 (2 узла; открыты, когда mastery на макс.) → tier3 (3 узла; открыты,
# когда ЛЮБОЙ tier2 на макс.) → ultimate (открыт, когда ЛЮБОЙ tier3 на макс.).
# В сетке меню: ряд1=tier1[0..2], ряд2=[tier2[0], mastery, tier2[1]],
# ряд3=tier3[0..2], ряд4=ultimate (по центру).
const TREE := {
	"combat": {"title": "Сражение",
		"tier1": ["weapon_basic", "combat_reinforce", "health_boost"],
		"mastery": "combat_mastery",
		"tier2": ["weapon_mid", "armor_improve"],
		"tier3": ["weapon_adv", "battlefield_expert", "special_weapon"],
		"ultimate": "airstrike"},
	"gather": {"title": "Выживание",
		"tier1": ["gather_basic", "speed_boost", "adventurer"],
		"mastery": "survival_mastery",
		"tier2": ["gather_adv", "campfire_skill"],
		"tier3": ["hunter", "patience", "scavenger"],
		"ultimate": "camouflage"},
	"engineer": {"title": "Технология",
		"tier1": ["field_repair", "engineer_basic", "project_improve"],
		"mastery": "tech_mastery",
		"tier2": ["engineer_mid", "electrician"],
		"tier3": ["recycling", "engineer_expert", "skilled_builder"],
		"ultimate": "demolition"},
}
const BRANCH_ORDER := ["combat", "gather", "engineer"]

# Реестр узлов: id → {branch, name, icon, max, kind, desc, ready}.
#   kind: "normal" | "mastery" (выбор класса) | "signature" (ультимейт, F).
#   ready: реализован ли эффект (false → в UI помечается «скоро»).
const SKILLS := {
	# --- Бой ---
	"weapon_basic":     {"branch": "combat", "name": "Мастер оружия (нач.)", "icon": "pistol", "max": 3, "kind": "normal", "ready": true, "desc": "Открывает чёрный рынок и двойные пистолеты. Урон +10%/ур; цена −15%/ур."},
	"weapon_mid":       {"branch": "combat", "name": "Мастер оружия (средн.)", "icon": "rifle", "max": 3, "kind": "normal", "ready": true, "desc": "Открывает дробовик/снайперку. Урон +10%/ур; цена −20%/ур."},
	"weapon_adv":       {"branch": "combat", "name": "Мастер оружия (продв.)", "icon": "mg", "max": 3, "kind": "normal", "ready": true, "desc": "Открывает автомат. Урон +10%/ур; цена −25%/ур."},
	"combat_reinforce": {"branch": "combat", "name": "Боевое подкрепление", "icon": "magazine", "max": 1, "kind": "normal", "ready": true, "desc": "Ёмкость магазина +50%."},
	"combat_mastery":   {"branch": "combat", "name": "Боевое мастерство", "icon": "swords", "max": 1, "kind": "mastery", "ready": true, "desc": "Класс «Боец». На верстаке доступно Мачете."},
	"battlefield_expert": {"branch": "combat", "name": "Эксперт на поле боя", "icon": "ghost", "max": 2, "kind": "normal", "ready": true, "desc": "При HP ≤30% авто-невидимость 5/7 c (кулдаун)."},
	"health_boost":     {"branch": "combat", "name": "Улучшение запаса HP", "icon": "heart", "max": 3, "kind": "normal", "ready": true, "desc": "Макс. HP: +15 / +30 / +45."},
	"armor_improve":    {"branch": "combat", "name": "Улучшение бронежилета", "icon": "shield", "max": 3, "kind": "normal", "ready": true, "desc": "Снижает урон по игроку: −10% / −20% / −30%."},
	"special_weapon":   {"branch": "combat", "name": "Мастер особого оружия", "icon": "grenade", "max": 3, "kind": "normal", "ready": true, "desc": "Урон топора +4/ур; гранаты; −30% цена."},
	"airstrike":        {"branch": "combat", "name": "Запрос на авиаудар", "icon": "jet", "max": 1, "kind": "signature", "ready": true, "desc": "Авиаудар (F): AoE 80, радиус 5, кд 25 с."},
	# --- Выживание ---
	"gather_basic":     {"branch": "gather", "name": "Мастерство сбора (нач.)", "icon": "pickaxe", "max": 3, "kind": "normal", "ready": true, "desc": "Сбор: ресурса за удар 2 / 3 / 4; +лимит."},
	"gather_adv":       {"branch": "gather", "name": "Мастерство сбора (продв.)", "icon": "gem", "max": 3, "kind": "normal", "ready": true, "desc": "Ещё +1 ресурса за удар за каждый уровень."},
	"hunter":           {"branch": "gather", "name": "Охотник", "icon": "beartrap", "max": 1, "kind": "normal", "ready": false, "desc": "Скорость установки ловушек и их урон +."},
	"speed_boost":      {"branch": "gather", "name": "Повышение скорости", "icon": "speed", "max": 3, "kind": "normal", "ready": true, "desc": "Скорость передвижения +5% / +10% / +20%."},
	"survival_mastery": {"branch": "gather", "name": "Мастерство выживания", "icon": "leaf", "max": 1, "kind": "mastery", "ready": true, "desc": "Класс «Добытчик». На верстаке доступен Лом."},
	"patience":         {"branch": "gather", "name": "Терпение", "icon": "hourglass", "max": 1, "kind": "normal", "ready": true, "desc": "Расход психздоровья ×0.5; при 50% HP +1%/с."},
	"adventurer":       {"branch": "gather", "name": "Искатель приключений", "icon": "compass", "max": 3, "kind": "normal", "ready": true, "desc": "Залежи дерева/стали дозревают быстрее и их больше."},
	"campfire_skill":   {"branch": "gather", "name": "Походный костёр", "icon": "campfire", "max": 1, "kind": "normal", "ready": true, "desc": "Костёр восстанавливает HP и психздоровье."},
	"scavenger":        {"branch": "gather", "name": "Мусорщик", "icon": "moneybag", "max": 1, "kind": "normal", "ready": true, "desc": "Больше шанс ресурсов и денег с зомби."},
	"camouflage":       {"branch": "gather", "name": "Маскировка", "icon": "leaves", "max": 1, "kind": "signature", "ready": true, "desc": "Невидимость для врагов 15 с (F), кулдаун 30 с."},
	# --- Инженер ---
	"field_repair":     {"branch": "engineer", "name": "Ремонт на поле боя", "icon": "wrench", "max": 3, "kind": "normal", "ready": true, "desc": "Ремонт построек +5% / +10% / +15%."},
	"engineer_mid":     {"branch": "engineer", "name": "Инженер (средн.)", "icon": "tower", "max": 3, "kind": "normal", "ready": true, "desc": "Урон турелей +5% / +10% / +15%."},
	"recycling":        {"branch": "engineer", "name": "Переработка", "icon": "recycle", "max": 1, "kind": "normal", "ready": true, "desc": "При уничтожении постройки возвращается 50% её ресурсов."},
	"engineer_basic":   {"branch": "engineer", "name": "Инженер (нач.)", "icon": "gear", "max": 3, "kind": "normal", "ready": true, "desc": "Прочность (HP) новых построек +10%/ур."},
	"tech_mastery":     {"branch": "engineer", "name": "Техническое мастерство", "icon": "toolcross", "max": 1, "kind": "mastery", "ready": true, "desc": "Класс «Инженер». На верстаке доступен Молот."},
	"engineer_expert":  {"branch": "engineer", "name": "Инженер-эксперт", "icon": "factory", "max": 3, "kind": "normal", "ready": true, "desc": "Скорострельность турелей +7% / +14% / +21%."},
	"project_improve":  {"branch": "engineer", "name": "Улучшение проекта", "icon": "blueprint", "max": 3, "kind": "normal", "ready": true, "desc": "Меньше ресурсов на постройку."},
	"electrician":      {"branch": "engineer", "name": "Инженер-электрик", "icon": "bolt", "max": 1, "kind": "normal", "ready": true, "desc": "Турели потребляют на 20% меньше мощности."},
	"skilled_builder":  {"branch": "engineer", "name": "Умелый строитель", "icon": "bricks", "max": 1, "kind": "normal", "ready": true, "desc": "При высоком психздоровье постройки прочнее (+20% HP)."},
	"demolition":       {"branch": "engineer", "name": "Команда подрывников", "icon": "dynamite", "max": 1, "kind": "signature", "ready": true, "desc": "C4 (F): крафт на верстаке, рвёт любой объект."},
}

var skill_levels: Dictionary = {}     # id → уровень (инициализируется в _init_skill_levels)

# Класс игрока. Один из "combat"/"gather"/"engineer"; "" — ещё не выбран. Класс
# выбирается на узле «мастерство» своей ветки (Этап 4.40), а не на старте.
signal class_changed(player_class: String)
var player_class: String = ""

# Сигнатурные способности (тир-4 ультимейты): открываются как обычный узел после
# выбора класса ветки. Эффект — в player.gd (клавиша F).
var has_airstrike: bool = false    # Боец — Авиаудар
var has_camouflage: bool = false   # Добытчик — Маскировка (эффект «скоро»)
var has_c4: bool = false           # Инженер — Команда подрывников (C4)
var c4_charges: int = 0            # сколько зарядов C4 в наличии (крафт на верстаке)


func _ready() -> void:
	_init_skill_levels()
	# EventBus загружается после InventorySystem — подписываемся отложенно,
	# когда все автозагрузки уже готовы (Этап 4.23).
	_connect_events.call_deferred()


## Инициализация уровней всех узлов нулями.
func _init_skill_levels() -> void:
	skill_levels.clear()
	for id in SKILLS:
		skill_levels[id] = 0


## Подписка на «ночь пережита» для начисления очка навыка (Этап 4.23).
func _connect_events() -> void:
	if EventBus.has_signal("night_survived"):
		EventBus.night_survived.connect(_on_night_survived)


func _on_night_survived() -> void:
	add_skill_point(1)


## Добавить ресурс в РЮКЗАК (сбор/крафт). Дерево/сталь режутся по лимиту переноски;
## излишек теряется — чтобы накопить больше, сдай на склад (deposit).
func add_resource(resource_type: String, amount: int) -> void:
	if resource_type not in inventory:
		inventory[resource_type] = 0
	inventory[resource_type] += amount
	if resource_type in CAPPED_RESOURCES:
		inventory[resource_type] = mini(inventory[resource_type], get_resource_cap())
	inventory_changed.emit(inventory)


## Лимит переноски дерева/стали в рюкзаке: база 20 + «Мастерство сбора» (+3/ур).
## Склад на переноску НЕ влияет (у него отдельная ёмкость, см. get_storage_capacity).
func get_resource_cap() -> int:
	return RESOURCE_CAP + CARRY_PER_GATHER_SKILL * int(skill_levels.get("gather_basic", 0))


## --- Склад (Warehouse, Этап 4.43) ---
## Каждая постройка «Склад» повышает ёмкость домашнего запаса (общая на дерево и
## на сталь — по storage_capacity каждого). Постройка регистрирует/снимает свой
## вклад при установке/сносе (storage.gd). При уменьшении ёмкости лишний запас
## сверх новой ёмкости срезается (склад разрушен — ресурсы потеряны).

## Текущая ёмкость склада (на каждый ресурс: дерево и сталь по отдельности).
func get_storage_capacity() -> int:
	return storage_capacity


## Сколько ресурса лежит на складе.
func get_stored(resource_type: String) -> int:
	return int(stored.get(resource_type, 0))


## Увеличить ёмкость склада (постройка «Склад» при установке).
func add_storage_capacity(amount: int) -> void:
	storage_capacity += maxi(0, amount)
	storage_changed.emit(stored, storage_capacity)


## Снять ёмкость при разрушении/сносе склада; лишний запас сверх новой ёмкости теряется.
func remove_storage_capacity(amount: int) -> void:
	storage_capacity = maxi(0, storage_capacity - maxi(0, amount))
	for r in CAPPED_RESOURCES:
		if int(stored.get(r, 0)) > storage_capacity:
			stored[r] = storage_capacity
	storage_changed.emit(stored, storage_capacity)


## Сдать ресурс из рюкзака на склад (сколько влезло). Возвращает фактически сданное.
func deposit(resource_type: String, amount: int) -> int:
	if resource_type not in CAPPED_RESOURCES:
		return 0
	var have: int = int(inventory.get(resource_type, 0))
	var free: int = storage_capacity - int(stored.get(resource_type, 0))
	var moved: int = clampi(amount, 0, mini(have, free))
	if moved <= 0:
		return 0
	inventory[resource_type] = have - moved
	stored[resource_type] = int(stored.get(resource_type, 0)) + moved
	inventory_changed.emit(inventory)
	storage_changed.emit(stored, storage_capacity)
	return moved


## Забрать ресурс со склада в рюкзак (не больше свободного места рюкзака). Возвращает взятое.
func withdraw(resource_type: String, amount: int) -> int:
	if resource_type not in CAPPED_RESOURCES:
		return 0
	var in_store: int = int(stored.get(resource_type, 0))
	var free: int = get_resource_cap() - int(inventory.get(resource_type, 0))
	var moved: int = clampi(amount, 0, mini(in_store, free))
	if moved <= 0:
		return 0
	stored[resource_type] = in_store - moved
	inventory[resource_type] = int(inventory.get(resource_type, 0)) + moved
	inventory_changed.emit(inventory)
	storage_changed.emit(stored, storage_capacity)
	return moved


## Сдать всё дерево/сталь из рюкзака на склад (сколько влезет).
func deposit_all() -> void:
	for r in CAPPED_RESOURCES:
		deposit(r, int(inventory.get(r, 0)))


## Забрать со склада всё дерево/сталь (сколько влезет в рюкзак).
func withdraw_all() -> void:
	for r in CAPPED_RESOURCES:
		withdraw(r, int(stored.get(r, 0)))


## Смерть игрока (Этап 4.43): теряем половину ПЕРЕНОСИМЫХ (в рюкзаке) дерева/стали.
## Склад не трогаем. Возвращает словарь потерь для лога.
func drop_carried_on_death() -> Dictionary:
	var lost := {}
	for r in CAPPED_RESOURCES:
		var have: int = int(inventory.get(r, 0))
		var drop: int = have / 2   # целочисленно: половина вниз
		if drop > 0:
			inventory[r] = have - drop
		lost[r] = drop
	inventory_changed.emit(inventory)
	return lost


## Сколько ресурса даёт один удар топором по узлу: база 1 + «Мастерство сбора»
## (нач.) + «Мастерство сбора» (продв.) (Этап 4.41).
func gather_yield() -> int:
	return 1 + get_skill_level("gather_basic") + get_skill_level("gather_adv")


## --- Эффекты навыков дерева (Этап 4.41): централизованные множители, чтобы
## игровые системы (оружие/турели/постройки) читали бонусы из одного места. ---

## Класс оружия → id навыка «Мастер оружия».
func _weapon_skill_of(tier: String) -> String:
	return {"basic": "weapon_basic", "mid": "weapon_mid", "adv": "weapon_adv"}.get(tier, "")

## Множитель урона оружия по его классу (basic/mid/adv): +10% за уровень.
func weapon_damage_mult(tier: String) -> float:
	return 1.0 + 0.10 * get_skill_level(_weapon_skill_of(tier))

## Множитель цены оружия на чёрном рынке (дешевле с навыком; не ниже 10% цены).
func weapon_price_mult(tier: String) -> float:
	var per: float = {"basic": 0.15, "mid": 0.20, "adv": 0.25}.get(tier, 0.0)
	return maxf(0.1, 1.0 - per * get_skill_level(_weapon_skill_of(tier)))

## +50% к ёмкости магазина — «Боевое подкрепление».
func magazine_mult() -> float:
	return 1.5 if get_skill_level("combat_reinforce") > 0 else 1.0

## Доля снижения входящего урона по игроку — «Улучшение бронежилета».
func armor_reduction() -> float:
	return [0.0, 0.10, 0.20, 0.30][clampi(get_skill_level("armor_improve"), 0, 3)]

## Множитель прочности (макс HP) постройки при установке: «Инженер (нач.)»
## +10%/ур и «Умелый строитель» +20% при высоком психздоровье.
func building_hp_mult(high_sanity: bool) -> float:
	var m := 1.0 + 0.10 * get_skill_level("engineer_basic")
	if high_sanity and get_skill_level("skilled_builder") > 0:
		m += 0.20
	return m

## Множитель урона турелей — «Инженер (средн.)» +5%/ур.
func turret_damage_mult() -> float:
	return 1.0 + 0.05 * get_skill_level("engineer_mid")

## Множитель интервала стрельбы турелей (меньше = быстрее) — «Инженер-эксперт» −7%/ур.
func turret_fire_interval_mult() -> float:
	return maxf(0.4, 1.0 - 0.07 * get_skill_level("engineer_expert"))

## Множитель потребления мощности турелями — «Инженер-электрик» −20%.
func power_cost_mult() -> float:
	return 0.8 if get_skill_level("electrician") > 0 else 1.0


## Потратить ресурс на крафт/постройку (Этап 4.43): списываем СНАЧАЛА из рюкзака,
## потом со склада (дома у мастерской тратишь из общего запаса). Возвращает true,
## если суммарно (рюкзак + склад) хватило.
func use_resource(resource_type: String, amount: int) -> bool:
	if get_total_resource(resource_type) < amount:
		return false
	var from_bag: int = mini(int(inventory.get(resource_type, 0)), amount)
	inventory[resource_type] = int(inventory.get(resource_type, 0)) - from_bag
	var rest: int = amount - from_bag
	if rest > 0 and resource_type in stored:
		stored[resource_type] = int(stored.get(resource_type, 0)) - rest
		storage_changed.emit(stored, storage_capacity)
	inventory_changed.emit(inventory)
	return true


## Количество ресурса В РЮКЗАКЕ (для HUD/переноски).
func get_resource(resource_type: String) -> int:
	return inventory.get(resource_type, 0)


## Всего доступно ресурса = рюкзак + склад (для проверок «хватает ли» на крафт/постройку).
func get_total_resource(resource_type: String) -> int:
	return int(inventory.get(resource_type, 0)) + int(stored.get(resource_type, 0))


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


## Группа узла: {branch, group} (tier1/mastery/tier2/tier3/ultimate) или {}.
func _group(skill_id: String) -> Dictionary:
	for b in TREE:
		var t: Dictionary = TREE[b]
		if skill_id in t.tier1: return {"branch": b, "group": "tier1"}
		if skill_id == t.mastery: return {"branch": b, "group": "mastery"}
		if skill_id in t.tier2: return {"branch": b, "group": "tier2"}
		if skill_id in t.tier3: return {"branch": b, "group": "tier3"}
		if skill_id == t.ultimate: return {"branch": b, "group": "ultimate"}
	return {}


## Есть ли среди узлов хотя бы один, прокачанный до своего максимума.
func _any_maxed(ids: Array) -> bool:
	for id in ids:
		if int(skill_levels.get(id, 0)) >= get_skill_max(id):
			return true
	return false


## Потолок конкретного узла (у каждого свой "max").
func get_skill_max(skill_id: String) -> int:
	return int(SKILLS[skill_id].get("max", SKILL_MAX_LEVEL)) if SKILLS.has(skill_id) else SKILL_MAX_LEVEL


## Совместимость: общий вызов get_skill_cap(id).
func get_skill_cap(skill_id: String = "") -> int:
	return get_skill_max(skill_id) if skill_id != "" else SKILL_MAX_LEVEL


## Открыт ли узел для вложения (гейты «ёлочки»):
## tier1 — всегда; mastery — когда ЛЮБОЙ tier1 на макс. (и класс свободен/свой);
## tier2 — когда mastery на макс.; tier3 — когда ЛЮБОЙ tier2 на макс.;
## ultimate — когда ЛЮБОЙ tier3 на макс.
func is_skill_unlocked(skill_id: String) -> bool:
	if not SKILLS.has(skill_id):
		return false
	var g := _group(skill_id)
	if g.is_empty():
		return false
	var t: Dictionary = TREE[g.branch]
	match g.group:
		"tier1":
			return true
		"mastery":
			return _any_maxed(t.tier1) and (player_class == "" or player_class == g.branch)
		"tier2":
			return int(skill_levels.get(t.mastery, 0)) >= get_skill_max(t.mastery)
		"tier3":
			return _any_maxed(t.tier2)
		"ultimate":
			return _any_maxed(t.tier3)
	return false


## Поднять узел на 1 уровень за очко (с проверкой предусловия). true при успехе.
func upgrade_skill(skill_id: String) -> bool:
	if not SKILLS.has(skill_id):
		return false
	if skill_points <= 0:
		print("Навыки: нет свободных очков")
		return false
	if int(skill_levels.get(skill_id, 0)) >= get_skill_max(skill_id):
		print("Навыки: «", skill_id, "» на потолке")
		return false
	if not is_skill_unlocked(skill_id):
		print("Навыки: «", skill_id, "» закрыт — сначала прокачайте предыдущий узел")
		return false
	skill_points -= 1
	skill_levels[skill_id] = int(skill_levels.get(skill_id, 0)) + 1
	var meta: Dictionary = SKILLS[skill_id]
	if meta.kind == "mastery" and player_class == "":
		player_class = meta.branch
		print("Класс выбран: ", player_class)
		class_changed.emit(player_class)
	elif meta.kind == "signature":
		match skill_id:
			"airstrike": has_airstrike = true
			"camouflage": has_camouflage = true
			"demolition": has_c4 = true
	print("Навыки: «", skill_id, "» → ур.", skill_levels[skill_id], " (очков: ", skill_points, ")")
	skills_changed.emit()
	return true


## Начислить очко навыка за пережитую ночь (Этап 4.23).
func add_skill_point(amount: int = 1) -> void:
	skill_points += amount
	print("Навыки: +", amount, " очко за пережитую ночь (всего ", skill_points, ")")
	skills_changed.emit()


## Совместимость с тестами: прямой выбор класса (как взятие узла мастерства).
func set_class(c: String) -> void:
	if c not in BRANCH_ORDER or player_class != "":
		return
	player_class = c
	print("Класс выбран: ", c)
	class_changed.emit(player_class)
	skills_changed.emit()


## Открыта ли сигнатурная способность своего класса.
func ability_unlocked() -> bool:
	match player_class:
		"combat": return has_airstrike
		"gather": return has_camouflage
		"engineer": return has_c4
	return false


## Совместимость с тестами: открыть сигнатуру своего класса (как взятие ультимейта).
func unlock_ability() -> bool:
	if player_class == "" or ability_unlocked() or skill_points <= 0:
		return false
	skill_points -= 1
	skill_levels[TREE[player_class].ultimate] = 1
	match player_class:
		"combat": has_airstrike = true
		"gather": has_camouflage = true
		"engineer": has_c4 = true
	skills_changed.emit()
	return true


## Сбросить прогрессию класса/навыков для нового забега.
func reset_run_progression() -> void:
	player_class = ""
	skill_points = 3
	_init_skill_levels()              # все узлы на 0 — ничего не вкачано
	has_airstrike = false
	has_camouflage = false
	has_c4 = false
	c4_charges = 0
	skills_changed.emit()
