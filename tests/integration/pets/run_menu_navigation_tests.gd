extends SceneTree
## 用真实手柄事件检查长目录和覆盖式弹窗，不依赖鼠标移动焦点。
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
	# 长目录只在内存中装配，测试期间不写玩家进度。
	catalog.data = old_catalog.duplicate() as ContentCatalogData
	catalog.data.stages = old_catalog.stages.duplicate()
	for i in 14:
		var entry := old_catalog.stages[0].duplicate() as StageDefinition
		entry.stage_id = "navigation_%d" % i
		entry.display_name = "目录滚动测试 %d" % i
		catalog.data.stages.append(entry)
	catalog._rebuild_indices()
	saves.data = saves.default_data()
	var app = load("res://scenes/app/app_main.tscn").instantiate()
	root.add_child(app)
	await frames()
	root.get_node("AppRouter").navigate(&"stage_select")
	await frames()
	var page = app._current_screen
	var buttons: Array[Node] = page._stage_list.find_children("*", "Button", true, false)
	var scroll: ScrollContainer = page._stage_list.get_parent()
	buttons[0].grab_focus()
	for i in 8:
		await joy(JOY_BUTTON_DPAD_DOWN)
		check(root.gui_get_focus_owner() == buttons[i + 1], "方向键连续向下选择歌曲 %d" % i)
	check(scroll.scroll_vertical > 0, "手柄下切带动目录滚动")
	var focused: Control = root.gui_get_focus_owner()
	check(scroll.get_global_rect().encloses(focused.get_global_rect()), "当前歌曲按钮保持完整可见")
	await screenshot("menu-scroll")
	for i in 8:
		await joy(JOY_BUTTON_DPAD_UP)
	check(root.gui_get_focus_owner() == buttons[0] and scroll.scroll_vertical == 0, "向上选择回到目录顶部")
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
	modal._build_list()
	if modal._debug_panel != null: modal._debug_panel.show()
	await frames()
	for i in 12:
		await joy(JOY_BUTTON_DPAD_DOWN)
		check(modal.is_ancestor_of(root.gui_get_focus_owner()), "动态内容不破坏弹窗焦点范围")
	await joy(JOY_BUTTON_B)
	await frames()
	check(app._current_screen == page, "取消弹窗不会同时触发底层返回")
	check(root.gui_get_focus_owner() == opener, "关闭后回到打开弹窗的按钮")
	buttons[0].grab_focus()
	await joy(JOY_BUTTON_DPAD_DOWN)
	check(root.gui_get_focus_owner() == buttons[1], "关闭弹窗后恢复目录导航")
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
	catalog._discover_stage_packages()
	saves.data = old_save
	print("MENU NAVIGATION TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func screenshot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/pet-review/%s.png" % name)
