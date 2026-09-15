extends SceneTree
## 用真实手柄事件检查正式轮播、加载闭环和弹窗焦点。
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", message)

func frames() -> void:
	for i in 3:
		await process_frame

func joy(button: JoyButton) -> void:
	for pressed in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		await frames()

func _run() -> void:
	var catalog = root.get_node("ContentCatalog")
	var saves = root.get_node("SaveService")
	var old_catalog: ContentCatalogData = catalog.data
	var old_save: Dictionary = saves.data
	saves.data = saves.default_data()
	var app = load("res://scenes/app/app_main.tscn").instantiate()
	root.add_child(app)
	await frames()
	root.get_node("AppRouter").navigate(&"stage_select")
	await frames()
	var page = app._current_screen
	check(page.get_node_or_null("Design/Cards") != null, "正式入口挂载美术选关页")
	check(page._levels.map(func(v): return v.stage_id) == ["tutorial2","s07","s08"], "教程2及最后两张测试关映射正确")
	check(root.gui_get_focus_owner() == page, "进入选关聚焦卡片区")
	await joy(JOY_BUTTON_DPAD_RIGHT)
	await create_timer(0.5).timeout
	check(page.current_index() == 1, "手柄右切蛇卡")
	check(page._cards[1].scale.is_equal_approx(Vector2.ONE), "当前卡片移动到完整可见的前景")
	await joy(JOY_BUTTON_DPAD_LEFT)
	await create_timer(0.5).timeout
	check(page.current_index() == 0, "手柄左切返回蝙蝠")
	await screenshot("menu-carousel")
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner() == page.get_node("Design/Actions/Back"), "向下进入功能栏")
	await joy(JOY_BUTTON_DPAD_UP)
	check(root.gui_get_focus_owner() == page, "功能栏向上回到卡片区")
	var opener: Button
	for node in page.find_children("*", "Button", true, false):
		if node.text == "随从": opener = node
	opener.grab_focus()
	opener.pressed.emit()
	await frames()
	var modal = app.modal_host.get_child(0)
	for button in [JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
		for i in 5:
			await joy(button)
			check(modal.is_ancestor_of(root.gui_get_focus_owner()), "随从弹窗方向导航不进入底层选关")
	await screenshot("modal-focus")
	# 重建卡片和显示开发按钮后仍然只在弹窗中寻焦。
	for pet: PetDefinition in catalog.data.pets:
		saves.data.pets[pet.pet_id] = {"owned": true, "advanced": false}
	modal._show_pet()
	modal.get_node("%DevPanel").show()
	await frames()
	for i in 12:
		await joy(JOY_BUTTON_DPAD_DOWN)
		check(modal.is_ancestor_of(root.gui_get_focus_owner()), "动态内容不破坏弹窗焦点范围")
	await joy(JOY_BUTTON_B)
	check(is_instance_valid(modal) and modal.closing,"返回先淡出弹窗")
	check(app.screen_host.focus_behavior_recursive==Control.FOCUS_BEHAVIOR_DISABLED,"淡出期间底层焦点仍隔离")
	await create_timer(0.2).timeout
	await frames()
	check(app._current_screen == page, "取消弹窗不会同时触发底层返回")
	check(root.gui_get_focus_owner() == opener, "关闭后回到打开弹窗的按钮")
	page.grab_focus()
	await joy(JOY_BUTTON_DPAD_RIGHT)
	check(page.current_index() == 1, "关闭弹窗后恢复轮播导航")
	await joy(JOY_BUTTON_DPAD_LEFT)
	await create_timer(0.5).timeout
	await joy(JOY_BUTTON_A)
	for i in 600:
		await process_frame
		if app._current_stage != null: break
	check(app._current_stage != null and app._current_stage.stage_id == "tutorial2", "确认蝙蝠经过正式加载页进入教程2")
	if app._current_stage != null:
		check(app._current_stage.song.audio_stream.get_length() > 100.0, "教程音乐已载入")
		check(is_equal_approx(app._current_stage.song.first_beat_offset_sec,14.4493657848589), "首拍偏移保持原谱精度")
		check(app._current_screen.stage_session.compiled_chart != null, "正式会话完成谱面编译")
		await create_timer(0.4).timeout
		await screenshot("tutorial2-game")
	app._on_stage_exit_requested()
	await frames()
	check(app._current_screen.get_node_or_null("Design/Cards") != null, "退出关卡回到美术选关")
	for id: String in ["s07","s08"]:
		var stage: StageDefinition = catalog.get_stage(id)
		check(stage.resolve_dependencies_sync(), "保留测试关可完整加载："+id)

	var expected := [
		["Perfect获得的分数额外增加2%", "Perfect获得的分数额外增加3%"],
		["受到的伤害-10%", "受到的伤害-20%"],
		["Hold的判定窗口更宽松", "Hold的判定窗口更宽松，且判定等级固定提高一级"],
	]
	for i in 3:
		check(catalog.data.pets[i].base_description == expected[i][0] and catalog.data.pets[i].advanced_description == expected[i][1], "技能描述保留策划原文")
	app.queue_free()
	await frames()
	catalog.data = old_catalog
	catalog._rebuild_indices()
	saves.data = old_save
	print("MENU NAVIGATION TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func screenshot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://builds/pet-review")
	root.get_texture().get_image().save_png("res://builds/pet-review/%s.png" % name)
