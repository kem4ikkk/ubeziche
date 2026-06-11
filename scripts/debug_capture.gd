extends Node
## Режим «прогон для Claude»: авто-скриншот + дамп состояния игры.
##
## Включается ТОЛЬКО при запуске с пользовательским аргументом --capture:
##   Godot_..._console.exe --path . -- --capture        (снимок через 2 c)
##   Godot_..._console.exe --path . -- --capture 3.5     (снимок через 3.5 c)
##
## При обычном запуске игры этот автозагруз ничего не делает.
## Результат: файл debug/last_run.png + строки "CLAUDE..." в консоли.

const OUT_DIR := "res://debug"
const OUT_FILE := "last_run.png"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--capture"):
		return  # обычный запуск — режим выключен
	await _run_capture(args)


func _run_capture(args: PackedStringArray) -> void:
	# Сколько секунд «поиграть» до снимка (по умолчанию 2.0).
	var delay := 2.0
	var idx := args.find("--capture")
	if idx != -1 and idx + 1 < args.size() and args[idx + 1].is_valid_float():
		delay = args[idx + 1].to_float()

	print("CLAUDE: режим прогона активен, снимок через ", delay, " c")
	await get_tree().create_timer(delay).timeout

	# Ждём отрисовку кадра, затем снимаем картинку с экрана.
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()

	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var abs_path := abs_dir.path_join(OUT_FILE)
	var err := image.save_png(abs_path)
	if err == OK:
		print("CLAUDE_SCREENSHOT: ", abs_path)
	else:
		print("CLAUDE: не удалось сохранить скриншот, код ", err)

	_dump_state()
	get_tree().quit()


## Печатает ключевое состояние сцены — это я читаю из консоли.
func _dump_state() -> void:
	print("CLAUDE_STATE_BEGIN")
	print("  fps: ", Engine.get_frames_per_second())
	var scene := get_tree().current_scene
	if scene:
		var player := scene.get_node_or_null("Player")
		if player and player is Node3D:
			print("  player_pos: ", (player as Node3D).global_position)
		var dummies := 0
		for child in scene.get_children():
			if child.name.begins_with("TargetDummy"):
				dummies += 1
		print("  target_dummies: ", dummies)
	print("CLAUDE_STATE_END")
