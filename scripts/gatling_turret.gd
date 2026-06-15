extends "res://scripts/turret.gd"

## Турель «Гатлинг» (Этап 4.8.4): дорогая турель с высокой скоростью стрельбы.
## В отличие от обычной (дешёвой и доступной с самого начала) турели,
## Гатлинг стоит намного больше ресурсов, но за счёт короткого интервала
## между выстрелами даёт намного больше урона в секунду по одиночной цели.
## Боезапаса нет (убран в 4.25) — работает, пока есть питание.

func _ready() -> void:
	super._ready()
	add_to_group("gatling")


func take_damage(amount: float) -> void:
	health.take_damage(amount)
	EventBus.building_damaged.emit("Гатлинг")


func _on_health_changed(current: float, maximum: float) -> void:
	hp_label.text = "Гатлинг %d / %d" % [current, maximum]
	var ratio := current / maximum
	if ratio > 0.6:
		hp_label.modulate = Color(0.4, 1.0, 0.4)
	elif ratio > 0.3:
		hp_label.modulate = Color(1.0, 0.85, 0.2)
	else:
		hp_label.modulate = Color(1.0, 0.3, 0.3)
