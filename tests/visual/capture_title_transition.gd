extends SceneTree
## 60 FPS 固定步长记录正式入口；由 UI runner 提供隔离用户目录和 MovieWriter。
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if not OS.get_user_data_dir().contains("UIReview"):
		quit(2)
		return
	var settings := root.get_node("SettingsService")
	settings.resolution = Vector2i(1280,720)
	settings.fullscreen = false
	settings.apply_display_settings()
	var app: Control = load("res://scenes/app/app_main.tscn").instantiate()
	root.add_child(app)
	for i in 600:
		if i == 240 or i == 242:
			var event := InputEventKey.new()
			event.keycode = KEY_ENTER
			event.pressed = i == 240
			Input.parse_input_event(event)
		await process_frame
	app.queue_free()
	await process_frame
	quit()
