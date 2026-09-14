extends SceneTree
## 检查实际根窗口像素和工具字体隔离；用户目录由审看脚本隔离。
var checks := 0
var failures := 0
func _init() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	if not OS.get_user_data_dir().contains("UIReview"):
		quit(2)
		return
	var label := Label.new()
	root.add_child(label)
	await process_frame
	check(label.has_theme_font_override("font") == not StudioLaunch.is_active(),"正式 UI 字体与工具隔离")
	if StudioLaunch.is_active():
		print("DISPLAY FONT TESTS: ",checks," checks, ",failures," failures (editor)")
		quit(failures)
		return
	var settings = root.get_node("SettingsService")
	for fullscreen in [false,true]:
		settings.fullscreen = fullscreen
		for size: Vector2i in settings.RESOLUTIONS:
			settings.resolution = size
			settings.apply_display_settings()
			for i in 4: await process_frame
			await RenderingServer.frame_post_draw
			var actual := root.get_texture().get_image().get_size()
			print("RENDER ",size," => ",actual," / fullscreen=",fullscreen)
			check(actual==size,"真实渲染像素 %s / fullscreen=%s"%[size,fullscreen])
			check(root.content_scale_size==Vector2i(1920,1080),"设计坐标保持 1080p")
			check(root.mode==(Window.MODE_EXCLUSIVE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED),"窗口模式")
	settings.fullscreen = false
	settings.resolution = Vector2i(2560,1440)
	settings.apply_display_settings()
	label.queue_free()
	await process_frame
	print("DISPLAY FONT TESTS: ",checks," checks, ",failures," failures")
	quit(failures)
