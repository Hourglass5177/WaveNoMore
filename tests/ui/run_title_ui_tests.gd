extends SceneTree
## 用正式 AppMain 和真实输入事件验证启动、路由、弹窗与回访，不依赖旧标题文案找按钮。
var checks := 0
var failures := 0
var app: Control
const OUT := "res://builds/title-review"

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",message)

func frames(count := 3) -> void:
	for i in count: await process_frame

func key(code: Key, pressed: bool, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	await frames()

func joy(code: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await frames()

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+"/"+name+".png")

func _run() -> void:
	if not OS.get_user_data_dir().contains("UIReview"):
		printerr("请使用 tools/ui/run_ui_review.ps1 -Suites title 隔离玩家数据")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	app = load("res://scenes/app/app_main.tscn").instantiate()
	root.add_child(app)
	await create_timer(0.25).timeout
	var page = app._current_screen
	check(page.phase == page.Phase.SPLASH, "首次启动先播放工作室开屏")
	await key(KEY_ENTER, true)
	await key(KEY_ENTER, false)
	check(page.phase == page.Phase.SPLASH, "开屏输入不穿透")
	await create_timer(0.6).timeout
	await shot("memo-splash")
	await create_timer(2.0).timeout
	check(not page.has_node("BootSplash"), "开屏结束回收节点")
	var initial_count: int = page.get_child_count()
	check(page.name == "TitleScreen" and page.phase == page.Phase.WAITING,"正式启动进入美术等待页")
	check(page._prompt.visible and page._title.modulate.a == 0.0,"等待时只显示背景和提示")
	check(page._buttons.all(func(b): return b.disabled),"等待时按钮不响应")
	await shot("waiting")
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(120,200)
	motion.relative = Vector2.ONE
	Input.parse_input_event(motion)
	var axis := InputEventJoypadMotion.new()
	axis.axis_value = 0.1
	Input.parse_input_event(axis)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	Input.parse_input_event(wheel)
	await key(KEY_ENTER,true,true)
	check(page.phase == page.Phase.WAITING,"鼠标移动、滚轮、摇杆漂移、重复键不唤醒")
	await key(KEY_ENTER,true)
	check(page.phase == page.Phase.REVEALING,"任意新按键展开菜单")
	await create_timer(0.8).timeout
	check(page.phase == page.Phase.MENU and app._title_revealed,"展开完成记录本次启动状态")
	check(page._buttons[0].has_focus(),"下划线默认开始游戏")
	await key(KEY_ENTER,true,true)
	await key(KEY_ENTER,false)
	check(app._current_screen == page,"长按跨入场与松开均不会误入选关")
	await create_timer(0.2).timeout
	check(page._buttons[0].get_node("Interaction").amount > 0.99,"默认选中细光可见")
	await shot("menu")
	motion.position = page._buttons[1].get_global_transform_with_canvas() * (page._buttons[1].size*0.5)
	motion.relative = Vector2(30,0)
	root.push_input(motion,true)
	await frames()
	check(page._buttons[1].has_focus(),"实际鼠标移入同步选中项")
	await key(KEY_LEFT,true)
	await key(KEY_LEFT,false)
	await create_timer(0.2).timeout
	check(page._buttons[0].has_focus() and page._buttons[1].get_node("Interaction").amount < 0.01,"键盘接管时静止鼠标不保留第二条下划线")
	await joy(JOY_BUTTON_DPAD_LEFT,true)
	await joy(JOY_BUTTON_DPAD_LEFT,false)
	check(page._buttons[3].has_focus(),"手柄左移循环至退出")
	await joy(JOY_BUTTON_DPAD_RIGHT,true)
	await joy(JOY_BUTTON_DPAD_RIGHT,false)
	check(page._buttons[0].has_focus(),"手柄右移循环回开始")
	await key(KEY_TAB,true)
	await key(KEY_TAB,false)
	check(page._buttons[1].has_focus(),"Tab 按原稿顺序导航")
	await key(KEY_ENTER,true)
	await key(KEY_ENTER,false)
	check(app._current_screen == page and app.modal_host.get_child_count() == 0,"著作信息仅保留入口")
	await key(KEY_RIGHT,true)
	await key(KEY_RIGHT,false)
	check(page._buttons[2].has_focus(),"方向键选择操作设置")
	await key(KEY_ENTER,true)
	await key(KEY_ENTER,false)
	await create_timer(0.25).timeout
	check(app.modal_host.get_child_count() == 1,"操作设置打开正式设置弹窗")
	var modal = app.modal_host.get_child(0)
	for i in 5:
		await joy(JOY_BUTTON_DPAD_DOWN,true)
		await joy(JOY_BUTTON_DPAD_DOWN,false)
		check(modal.is_ancestor_of(root.gui_get_focus_owner()),"弹窗焦点不进入底层菜单")
	motion.position = Vector2(200,950)
	Input.parse_input_event(motion)
	await frames()
	check(modal.is_ancestor_of(root.gui_get_focus_owner()),"悬停底层菜单不会抢弹窗焦点")
	modal.close_requested.emit()
	await create_timer(0.25).timeout
	check(page._buttons[2].has_focus(),"关闭设置恢复原按钮")
	await create_timer(0.2).timeout
	var bright := 0
	for button in page._buttons:
		if button.get_node("Interaction").amount > 0.01: bright += 1
	check(bright == 1,"菜单只有一条选中下划线")
	check(page.get_child_count() == initial_count,"持续动画不增加页面节点")
	page._buttons[0].grab_focus()
	await joy(JOY_BUTTON_A,true)
	await joy(JOY_BUTTON_A,false)
	await create_timer(0.25).timeout
	check(app._current_screen.get_node_or_null("Design/Cards") != null,"开始游戏进入正式美术选关")
	await joy(JOY_BUTTON_B,true)
	await joy(JOY_BUTTON_B,false)
	await create_timer(0.25).timeout
	page = app._current_screen
	check(page.phase == page.Phase.MENU and not page._prompt.visible,"选关返回直接显示菜单")
	check(page._buttons[0].has_focus(),"返回菜单默认开始游戏")
	# 实际独立画布读回，验证根窗口缩放以外的场景自适配。
	var canvas := SubViewport.new()
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var sample = load("res://scenes/screens/title_screen.tscn").instantiate()
	sample.skip_prompt = true
	canvas.add_child(sample)
	sample.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for size in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160),Vector2i(1800,1200)]:
		canvas.size = size
		await frames(5)
		await RenderingServer.frame_post_draw
		var image := canvas.get_texture().get_image()
		check(image.get_size() == size,"真实渲染尺寸 %s" % size)
		var design: Control = sample.get_node("Design")
		check(is_equal_approx(design.scale.x,design.scale.y),"等比缩放 %s" % size)
		check(design.position.is_equal_approx((Vector2(size)-Vector2(1920,1080)*design.scale)*0.5),"居中留边 %s" % size)
		image.save_png(OUT+"/menu-%dx%d.png" % [size.x,size.y])
	# 第二次独立实例检验手柄任意键以及鼠标唤醒。
	for mode in ["joy","mouse"]:
		sample.free()
		sample = load("res://scenes/screens/title_screen.tscn").instantiate()
		canvas.add_child(sample)
		sample.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await frames()
		var event: InputEvent
		if mode == "joy":
			event = InputEventJoypadButton.new()
			event.button_index = JOY_BUTTON_X
		else:
			event = InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.position = Vector2(100,100)
		event.pressed = true
		canvas.push_input(event,true)
		await create_timer(0.8).timeout
		check(sample.phase == sample.Phase.MENU,"任意按钮唤醒："+mode)
		event.pressed = false
		canvas.push_input(event,true)
		check(sample.phase == sample.Phase.MENU,"释放唤醒按钮不会退出菜单："+mode)
	canvas.queue_free()
	await frames()
	# 截获退出意图，避免结束测试进程；重复输入应只有一次意图。
	for connection in page.quit_requested.get_connections():
		page.quit_requested.disconnect(connection.callable)
	var quits := [0]
	page.quit_requested.connect(func(): quits[0] += 1)
	page._buttons[3].grab_focus()
	await key(KEY_ENTER,true)
	await key(KEY_ENTER,false)
	await key(KEY_ENTER,true)
	await key(KEY_ENTER,false)
	await create_timer(0.25).timeout
	check(quits[0] == 1,"退出淡出期间重复确认只发出一次退出意图")
	app.queue_free()
	await frames()
	print("TITLE UI: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
