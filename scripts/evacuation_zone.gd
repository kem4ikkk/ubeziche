extends Area3D

## Зона эвакуации (Этап 4.11): финальная точка, до которой игрок должен
## добежать, когда после всех пережитых волн вызван транспорт.
## До старта эвакуации зона скрыта и не отслеживает игрока — её включает
## GameStateManager через activate(), когда пережиты все волны.
## Детектирует игрока тем же способом, что и мастерская (Area3D, слой 2).

var _player_inside: bool = false
var _active: bool = false


func _ready() -> void:
	add_to_group("evacuation_zone")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# До вызова транспорта зона невидима и не отслеживает вход.
	visible = false
	monitoring = false


## Включить зону: показать и начать отслеживать вход игрока.
func activate() -> void:
	_active = true
	visible = true
	monitoring = true


## В зоне ли игрок (для GameStateManager). Помимо отслеживаемого флага
## делаем прямой опрос пересечений — на случай телепорта/момента включения.
func is_player_inside() -> bool:
	if _player_inside:
		return true
	if not monitoring:
		return false
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			return true
	return false


func _on_body_entered(body: Node3D) -> void:
	if _active and body.is_in_group("player"):
		_player_inside = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_inside = false
