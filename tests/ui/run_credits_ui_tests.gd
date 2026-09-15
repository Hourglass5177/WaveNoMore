extends SceneTree
## 使用正式 AppMain 打开著作弹窗，检查署名、焦点和实际渲染排版。
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr(message)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://builds/credits-review")
	var settings := root.get_node("SettingsService")
	settings.fullscreen = false
	settings.resolution = Vector2i(1280,720)
	settings.apply_display_settings()
	var app = load("res://scenes/app/app_main.tscn").instantiate()
	app._title_revealed = true
	app._boot_splash_shown = true
	root.add_child(app)
	await create_timer(0.3).timeout
	var title = app._current_screen
	var credits_button: Button = title._buttons[1]
	credits_button.grab_focus()
	title._activate(1)
	await create_timer(0.3).timeout
	check(app.modal_host.get_child_count() == 1,"著作按钮接入正式弹窗")
	var modal = app.modal_host.get_child(0)
	check(modal.get_node("%Studio").text == "华中科技大学 Memo工作室 出品","出品信息完整")
	var expected := ["山羊電燈","沙漏","沙漏、且听风吟","山羊電燈、Chickenoil、阎王仙人、\nFisher小鱼、彭河","Julia","hinako1804","岚","神秘人士"]
	var grid: GridContainer = modal.get_node("%CreditsGrid")
	for i in 8:
		var names := grid.get_child(i*2+1) as Label
		check(names.text == expected[i],"署名保持原文 %d" % i)
		check(names.get_theme_font_size("font_size") == 34,"署名字号 %d" % i)
	check(modal.get_node("%Back").has_focus(),"默认焦点落在返回")
	check(app.screen_host.focus_behavior_recursive == Control.FOCUS_BEHAVIOR_DISABLED,"底层菜单退出导航")
	for resolution in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160),Vector2i(1600,1000)]:
		settings.resolution = resolution
		settings.apply_display_settings()
		await create_timer(0.18).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/credits-review/%dx%d.png" % [resolution.x,resolution.y])
		check(grid.position.y + grid.size.y < modal.get_node("%Back").position.y,"名单与返回按钮不重叠")
		check(grid.position.x + grid.size.x <= 1600,"长署名不越过面板边缘")
	var cancel := InputEventJoypadButton.new()
	cancel.button_index = JOY_BUTTON_B
	cancel.pressed = true
	Input.parse_input_event(cancel)
	await create_timer(0.3).timeout
	check(app.modal_host.get_child_count() == 0,"手柄返回关闭弹窗")
	check(credits_button.has_focus(),"关闭后恢复著作按钮焦点")
	cancel = InputEventJoypadButton.new()
	cancel.button_index = JOY_BUTTON_B
	Input.parse_input_event(cancel)
	await process_frame
	title._activate(1)
	await create_timer(0.25).timeout
	modal = app.modal_host.get_child(0)
	modal.get_node("%Back").pressed.emit()
	modal.get_node("%Back").pressed.emit()
	await create_timer(0.25).timeout
	check(app.modal_host.get_child_count() == 0,"重复确认只关闭一次")
	app.queue_free()
	# 退出独立检查进程前释放主菜单环境音解码器。
	var audio := root.get_node("MenuAudioService")
	if audio._ambient_fade: audio._ambient_fade.kill()
	for child in audio.get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	await process_frame
	await create_timer(0.1).timeout
	print("CREDITS UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
