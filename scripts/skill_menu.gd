extends CanvasLayer

## Меню навыков (Этап 4.23): открывается клавишей N (см. player.gd).
## Показывает свободные очки и три ветки; кнопка [+] тратит 1 очко на ветку.
## Очки навыков: 3 на старте, +1 за каждую пережитую ночь (InventorySystem).

const BRANCHES := [
	{"key": "gather",   "name": "Добыча",  "desc": "+1 ресурс за удар топором"},
	{"key": "combat",   "name": "Бой",     "desc": "+10 урона топором в ближнем бою"},
	{"key": "engineer", "name": "Инженер", "desc": "+5 HP к ремонту, открывает крафт"},
]

@onready var _points_label: Label = $Panel/VBox/PointsLabel
@onready var _rows_box: VBoxContainer = $Panel/VBox/Rows

var _rows: Array = []
var _capture_mode := false


func _ready() -> void:
	add_to_group("skill_menu")
	_capture_mode = OS.get_cmdline_user_args().has("--capture")
	# Меню должно работать на паузе (открыто = игра на паузе).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_rows()
	InventorySystem.skills_changed.connect(_refresh)
	visible = false
	_refresh()


func _build_rows() -> void:
	for branch in BRANCHES:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(64, 0)
		btn.pressed.connect(_on_upgrade.bind(branch.key))
		row.add_child(label)
		row.add_child(btn)
		_rows_box.add_child(row)
		_rows.append({"branch": branch, "label": label, "btn": btn})


func _on_upgrade(branch_key: String) -> void:
	InventorySystem.upgrade_skill(branch_key)


func _refresh() -> void:
	_points_label.text = "Свободные очки: %d" % InventorySystem.skill_points
	for r in _rows:
		var key: String = r.branch.key
		var lvl: int = InventorySystem.get_skill_level(key)
		var maxl: int = InventorySystem.SKILL_MAX[key]
		r.label.text = "%s [%d/%d] — %s" % [r.branch.name, lvl, maxl, r.branch.desc]
		var maxed: bool = lvl >= maxl
		r.btn.disabled = maxed or InventorySystem.skill_points <= 0
		r.btn.text = "MAX" if maxed else "[+]"


## Открыть/закрыть меню (вызывается из player.gd по клавише N).
func toggle() -> void:
	visible = not visible
	# Паузы в игре НЕТ (решение автора 2026-06-16): меню открыто — игра идёт.
	# Только освобождаем/захватываем курсор для кликов по кнопкам.
	if not _capture_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	if visible:
		_refresh()


## Закрыть меню, если открыто (для Esc из player.gd). Открытие/закрытие по N —
## простым toggle() из player.gd: паузы нет, player всегда получает ввод.
func close() -> void:
	if visible:
		toggle()
