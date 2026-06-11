extends StaticBody3D

## Временная мишень для проверки стрельбы.
## Позже по этому же принципу (HealthComponent + take_damage) сделаем зомби.

@onready var health: HealthComponent = $HealthComponent


func _ready() -> void:
	health.died.connect(_on_died)
	health.health_changed.connect(_on_health_changed)


## Вызывается выстрелом игрока (см. player.gd → shoot()).
func take_damage(amount: float) -> void:
	health.take_damage(amount)


func _on_health_changed(current: float, maximum: float) -> void:
	print("Мишень ранена. HP: ", current, "/", maximum)


func _on_died() -> void:
	print("Мишень уничтожена!")
	queue_free()
