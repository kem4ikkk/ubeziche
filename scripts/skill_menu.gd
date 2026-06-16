extends CanvasLayer

## Меню навыков (Этап 4.23): открывается клавишей N (см. player.gd).
## Показывает класс игрока, свободные очки и три ветки; кнопка [+] тратит 1 очко.
## Очки: 3 на старте, +1 за пережитую ночь (InventorySystem).
## Этап 4.12: своя ветка качается до SKILL_MAX, чужая — до OFF_CLASS_MAX; отдельная
## строка открывает сигнатурную способность своего класса (Авиаудар/Костёр/C4).

const BRANCHES := [
	{"key": "gather",   "name": "Добыча",  "desc": "+1 ресурс/удар, +лимит ресурсов"},
	{"key": "combat",   "name": "Бой",     "desc": "+урон ближнего боя, +макс HP"},
	{"key": "engineer", "name": "Инженер", "desc": "+HP ремонта, +урон турелей"},
]

# Сигнатурная способность по классу (Этап 4.12).
const ABILITY_BY_CLASS := {"combat": "Авиаудар", "gather": "Костёр", "engineer": "C4"}
const CLASS_NAMES := {"combat": "Боец", "gather": "Добытчик", "engineer": "Инженер", "": "не выбран"}

@onready var _points_label: Label = $Panel/VBox/PointsLabel
@onready var _rows_box: VBoxContainer = $Panel/VBox/Rows

var _rows: Array = []
var _ability_label: Label
var _ability_btn: Button
var _capture_mode := false


func _ready() -> void:
	add_to_group("skill_menu")
	_capture_mode = OS.get_cmdline_user_args().has("--capture")
	# Меню работает всегда (паузы в игре нет, Этап 4.31).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_rows()
	InventorySystem.skills_changed.connect(_refresh)
	InventorySystem.class_changed.connect(func(_c): _refresh())
	visible = false
	_refresh()


func _build_rows() -> void:
	for branch in BRANCHES:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(72, 0)
		btn.pressed.connect(_on_upgrade.bind(branch.key))
		row.add_child(label)
		row.add_child(btn)
		_rows_box.add_child(row)
		_rows.append({"branch": branch, "label": label, "btn": btn})
	# Строка сигнатурной способности класса (после веток).
	var arow := HBoxContainer.new()
	_ability_label = Label.new()
	_ability_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ability_btn = Button.new()
	_ability_btn.custom_minimum_size = Vector2(96, 0)
	_ability_btn.pressed.connect(_on_unlock_ability)
	arow.add_child(_ability_label)
	arow.add_child(_ability_btn)
	_rows_box.add_child(arow)


func _on_upgrade(branch_key: String) -> void:
	InventorySystem.upgrade_skill(branch_key)


func _on_unlock_ability() -> void:
	InventorySystem.unlock_ability()


func _refresh() -> void:
	var cls: String = InventorySystem.player_class
	_points_label.text = "Класс: %s    Свободные очки: %d" % [CLASS_NAMES.get(cls, cls), InventorySystem.skill_points]
	for r in _rows:
		var key: String = r.branch.key
		var lvl: int = InventorySystem.get_skill_level(key)
		var cap: int = InventorySystem.get_skill_cap(key)
		var own: bool = cls == "" or key == cls
		var tag := "" if own else "  (чужая)"
		r.label.text = "%s [%d/%d]%s — %s" % [r.branch.name, lvl, cap, tag, r.branch.desc]
		var maxed: bool = lvl >= cap
		r.btn.disabled = maxed or InventorySystem.skill_points <= 0
		r.btn.text = "MAX" if maxed else "[+]"
	_refresh_ability(cls)


## Строка сигнатурной способности своего класса.
func _refresh_ability(cls: String) -> void:
	if cls == "":
		_ability_label.text = "Способность: выберите класс"
		_ability_btn.disabled = true
		_ability_btn.text = "—"
		return
	var aname: String = ABILITY_BY_CLASS.get(cls, "?")
	if InventorySystem.ability_unlocked():
		_ability_label.text = "Способность: %s — открыта (F)" % aname
		_ability_btn.disabled = true
		_ability_btn.text = "Готово"
	else:
		_ability_label.text = "Способность: %s (нужен ур. ветки ≥1 и очко)" % aname
		var can: bool = InventorySystem.get_skill_level(cls) >= 1 and InventorySystem.skill_points > 0
		_ability_btn.disabled = not can
		_ability_btn.text = "Открыть"


## Открыть/закрыть меню (вызывается из player.gd по клавише N).
func toggle() -> void:
	visible = not visible
	# Паузы в игре НЕТ (решение автора 2026-06-16): меню открыто — игра идёт.
	# Только освобождаем/захватываем курсор для кликов по кнопкам.
	if not _capture_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	if visible:
		_refresh()


## Закрыть меню, если открыто (для Esc из player.gd).
func close() -> void:
	if visible:
		toggle()
