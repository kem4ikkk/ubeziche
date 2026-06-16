extends CanvasLayer

## HP-бар босса (Этап 4.13b): полоса сверху по центру. Появляется на спавне босса,
## обновляется по его HP, скрывается при гибели. Слушает EventBus boss_* сигналы.

@onready var _bar: ProgressBar = $Panel/Bar
@onready var _name_label: Label = $Panel/NameLabel


func _ready() -> void:
	add_to_group("boss_bar")
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.boss_spawned.connect(_on_boss_spawned)
	EventBus.boss_health_changed.connect(_on_boss_health_changed)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	visible = false


func _on_boss_spawned(boss_name: String, max_hp: float) -> void:
	_name_label.text = "БОСС: %s" % boss_name
	_bar.max_value = max_hp
	_bar.value = max_hp
	visible = true


func _on_boss_health_changed(hp: float, max_hp: float) -> void:
	_bar.max_value = max_hp
	_bar.value = hp


func _on_boss_defeated() -> void:
	visible = false
