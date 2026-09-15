extends SceneTree
## 使用本地真实 PV 验证首次唤醒、按键防穿透、结束与返回；不修改玩家存档。
var checks := 0
var failures := 0
func _initialize(): run.call_deferred()
func check(value: bool, message: String):
	checks += 1
	if not value: failures += 1; printerr(message)
func joy(pressed: bool):
	var event := InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_A
	event.pressed = pressed
	Input.parse_input_event(event)
func run():
	var app = load("res://scenes/app/app_main.tscn").instantiate()
	app._boot_splash_shown = true
	root.add_child(app)
	await create_timer(.25).timeout
	var router := root.get_node("AppRouter")
	joy(true)
	await create_timer(1.0).timeout
	if not ResourceLoader.exists("res://assets/pv.ogv"):
		check(router.current_route == &"stage_select", "缺少本地视频仍可进入选关")
	else:
		check(router.current_route == &"intro_video", "首次唤醒直接进入视频")
		var pv = app._current_screen
		check(pv._video.is_playing(), "真实视频已开始播放")
		check(pv._video.bus == &"Music", "视频原声服从音乐音量")
		check(root.get_node("MenuAudioService")._ambient.stream_paused, "播放期间菜单环境音已淡出")
		check(not pv._leaving, "长按唤醒键不误跳过")
		joy(false)
		await process_frame
		if "--natural" in OS.get_cmdline_user_args():
			var deadline := Time.get_ticks_msec()+130000
			while router.current_route == &"intro_video" and Time.get_ticks_msec()<deadline:
				await create_timer(1.0).timeout
		else:
			joy(true)
			await process_frame
			joy(false)
		await create_timer(1.0).timeout
		check(router.current_route == &"stage_select", "播完或跳过后进入选关")
	check(app._current_screen.current_level().stage_id == "tutorial2", "选中第一关而非自动开局")
	check(app._current_screen.has_focus(), "选关获得手柄焦点")
	check(is_equal_approx(app._current_screen.modulate.a,1.0), "选关淡入完成")
	router.navigate(&"title", {}, false)
	await create_timer(.25).timeout
	check(app._current_screen.phase == app._current_screen.Phase.MENU, "同次启动返回主界面直接显示菜单")
	check(not app._current_screen.play_intro, "同次启动不重播视频")
	app.queue_free()
	await process_frame
	print("INTRO VIDEO: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
