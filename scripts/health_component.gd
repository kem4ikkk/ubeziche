extends Node
class_name HealthComponent

## Переиспользуемый компонент здоровья.
## Вешается на любой объект, который можно ранить: врага, постройку, игрока.
## Логика урона/смерти живёт здесь, а не дублируется в каждом объекте.

signal died                                          ## когда HP дошло до 0
signal health_changed(current: float, maximum: float)  ## при любом изменении HP

@export var max_health: float = 30.0
var current_health: float


func _ready() -> void:
	current_health = max_health


func take_damage(amount: float) -> void:
	if current_health <= 0.0:
		return  # уже мертвы — игнорируем
	current_health = max(current_health - amount, 0.0)
	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		died.emit()


func heal(amount: float) -> void:
	if current_health <= 0.0:
		return
	current_health = min(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)
