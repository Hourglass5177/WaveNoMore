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
	for i in 780:
		if i in [444,446,624,626]:
			var event := InputEventKey.new()
			event.keycode = KEY_ENTER
			event.pressed = i in [444,624]
			Input.parse_input_event(event)
		await process_frame
	# MovieWriter 结束前显式停止菜单音源，给音频线程回收解码器的机会。
	var audio := root.get_node("MenuAudioService")
	if audio._ambient_fade: audio._ambient_fade.kill()
	for child in audio.get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	app.queue_free()
	for i in 3: await process_frame
	await create_timer(0.1).timeout
	quit()
