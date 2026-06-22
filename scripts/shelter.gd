extends Node3D

## Убежище (Этап 5.x) — ПЕРИМЕТР серых стен с проходами в центре карты (узел
## ShelterPerimeter). Это и есть главная цель обороны: зомби бьют его сегменты,
## урон по ЛЮБОМУ сегменту снимает ОБЩИЙ запас HP убежища. HP=0 → ПОРАЖЕНИЕ
## (а не смерть игрока). Макс. HP растёт с тиром убежища.

@onready var health: HealthComponent = $HealthComponent

const BASE_HP := 600.0
const HP_PER_TIER := 400.0          # +HP за каждый тир выше первого


func _ready() -> void:
	add_to_group("shelter")
	_apply_tier_hp(true)
	InventorySystem.tier_changed.connect(func(_t: int) -> void: _apply_tier_hp(false))
	health.died.connect(_on_died)


## Пересчёт макс. HP по тиру. При апгрейде добавляем разницу к текущему HP.
func _apply_tier_hp(initial: bool) -> void:
	var new_max: float = BASE_HP + HP_PER_TIER * float(InventorySystem.shelter_tier - 1)
	var old_max: float = health.max_health
	health.max_health = new_max
	if initial:
		health.current_health = new_max
	elif new_max > old_max:
		health.current_health += (new_max - old_max)        # апгрейд тира — +HP
	health.current_health = minf(health.current_health, new_max)   # не выше нового макс
	health.health_changed.emit(health.current_health, health.max_health)


## Урон по убежищу (вызывается сегментами периметра при атаке зомби).
func take_damage(amount: float) -> void:
	health.take_damage(amount)
	EventBus.building_damaged.emit("Убежище")


## Ремонт убежища (молот/инженер — позже).
func repair(amount: float) -> void:
	health.heal(amount)


func get_health() -> float:
	return health.current_health


func get_max_health() -> float:
	return health.max_health


func get_health_ratio() -> float:
	return health.current_health / health.max_health if health.max_health > 0.0 else 0.0


func is_full_health() -> bool:
	return health.current_health >= health.max_health


func _on_died() -> void:
	EventBus.shelter_destroyed.emit()
