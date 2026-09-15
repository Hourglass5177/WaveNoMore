extends SceneTree
## 合成真实设备事件走正式 AppMain；设备名称分类单独验证，不假称真机硬件验收。
var checks := 0
var failures := 0
var app: Node
var hints: Node
const OUT := "res://builds/controller-review"

func _init() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func frames(count := 3) -> void:
	for i in count: await process_frame

func button(code: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = code
	event.pressed = pressed
	Input.parse_input_event(event)

func press(code: JoyButton) -> void:
	button(code, true)
	await frames(1)
	button(code, false)
	await frames(2)

func axis(value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = JOY_AXIS_LEFT_X
	event.axis_value = value
	Input.parse_input_event(event)

func key(code: Key, pressed: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)

func shot(name: String) -> void:
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "/" + name + ".png")

func _run() -> void:
	if not OS.get_user_data_dir().contains("UIReview"):
		push_error("使用 tools/ui/run_ui_review.ps1 -Suites controller 隔离验证")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	hints = root.get_node("UiInputHints")
	for item in [["Xbox Wireless Controller", &"xbox"], ["DualSense Wireless Controller", &"playstation"], ["Nintendo Switch Pro Controller", &"nintendo"], ["USB Gamepad", &"generic"]]:
		check(hints.detect_family(item[0]) == item[1], "设备名称识别 " + item[0])
	check(hints.detect_family("Wireless Controller", 0x054c) == &"playstation", "Sony 厂商 ID 识别")
	check(hints.detect_family("Pro Controller", 0x057e) == &"nintendo", "Nintendo 厂商 ID 识别")
	check(hints._textures.size() == 32, "32 个图标已预热")
	for texture: Texture2D in hints._textures.values():
		check(texture.get_width() >= 96 and not texture.get_image().is_invisible(), "矢量键帽正常栅格化")
	hints._set_family(&"xbox", 0)
	app = load("res://scenes/app/app_main.tscn").instantiate()
	app._title_revealed = true
	root.add_child(app)
	await create_timer(0.3).timeout
	var title: Control = app._current_screen
	var start: Button = title.get_node("%Start")
	check(start.has_focus(), "主菜单默认开始")
	check(start.get_node("Interaction").underline_offset == 10.0, "选中线位于按钮框下方")
	check(start.get_node("Art").self_modulate.r > title.get_node("%Credits/Art").self_modulate.r + 0.2, "主菜单选中亮度清晰区分")
	await shot("title-selected")
	var router: Node = root.get_node("AppRouter")
	router.navigate(&"stage_select", {}, false)
	await create_timer(0.25).timeout
	var select: Control = app._current_screen
	var glyph: Control = select.get_node("Design/Actions/Pets/Shortcut")
	check(glyph._texture == hints.texture_for(&"menu_pets"), "选关 Y 图标使用当前手柄")
	await shot("stage-xbox")
	check(not select.has_node("Design/PreviousHint") and not select.has_node("Design/NextHint"), "选关箭头下不再显示键帽")
	var original_target: int = select._target
	await press(JOY_BUTTON_Y)
	await create_timer(0.25).timeout
	check(app.modal_host.get_child_count() == 1, "Y 打开随从")
	var pets: Control = app.modal_host.get_child(0)
	check(not pets.has_node("Design/PreviousHint") and not pets.has_node("Design/NextHint"), "随从箭头下不再显示键帽")
	var original_index: int = pets._index
	await press(JOY_BUTTON_RIGHT_SHOULDER)
	check(pets._index == posmod(original_index + 1, pets.entries.size()), "RB 切换下一只")
	await press(JOY_BUTTON_LEFT_SHOULDER)
	check(pets._index == original_index, "LB 切回上一只")
	check(select._target == original_target, "肩键不穿透到选关")
	var focus_before := root.gui_get_focus_owner()
	await press(JOY_BUTTON_RIGHT_SHOULDER)
	check(root.gui_get_focus_owner() == focus_before, "切换保持当前操作焦点")
	var before_stick: int = pets._index
	for value in [0.62, 0.69, 0.78, 0.43]: axis(value)
	await frames()
	check(pets._index == posmod(before_stick + 1, pets.entries.size()), "摇杆抖动不连续翻页")
	axis(0.0)
	axis(0.65)
	await frames()
	check(pets._index == posmod(before_stick + 2, pets.entries.size()), "摇杆回中后可再次切换")
	axis(0.0)
	await press(JOY_BUTTON_X)
	check(app.modal_host.get_child_count() == 1 and app.modal_host.get_child(0) == pets, "随从窗口中 X 不打开底层设置")
	check(pets.get_node("%Preview").get_node_or_null("Interaction") == null, "随从本体保持无下划线")
	await shot("pets-shoulders")
	await press(JOY_BUTTON_B)
	await create_timer(0.2).timeout
	check(app.modal_host.get_child_count() == 0 and select.get_node("Design/Actions/Pets").has_focus(), "关闭随从回到随从入口")
	hints._set_family(&"playstation", 0)
	check(glyph._texture == hints.texture_for(&"menu_pets") and hints.glyph_name(&"menu_pets") == "triangle", "切换设备立即更新为三角")
	await press(JOY_BUTTON_X)
	await create_timer(0.25).timeout
	var settings: Control = app.modal_host.get_child(0)
	check(settings.has_method("select_tab"), "方块打开设置")
	await press(JOY_BUTTON_RIGHT_SHOULDER)
	check(settings._tab_index == 1, "R1 切到画面设置")
	await shot("settings-playstation")
	await press(JOY_BUTTON_LEFT_SHOULDER)
	check(settings._tab_index == 0, "L1 切回声音")
	await press(JOY_BUTTON_LEFT_SHOULDER)
	check(settings._tab_index == 2, "设置分类循环")
	var number: LineEdit = settings.get_node("%CalibrationPage").get_node("%AudioOffset").get_line_edit()
	number.grab_focus()
	key(KEY_E)
	key(KEY_E, false)
	await frames()
	check(settings._tab_index == 2, "数值输入 E 不误切分类")
	check(hints.family == &"keyboard" and hints.glyph_name(&"menu_pets") == "p", "键盘操作同步键帽")
	await press(JOY_BUTTON_B)
	await create_timer(0.2).timeout
	check(select.get_node("Design/Actions/Settings").has_focus(), "关闭设置回到设置入口")
	key(KEY_P)
	key(KEY_P, false)
	await create_timer(0.2).timeout
	check(app.modal_host.get_child_count() == 1, "键盘 P 打开随从")
	await press(JOY_BUTTON_B)
	await create_timer(0.2).timeout
	hints._set_family(&"nintendo", 0)
	check(hints.glyph_name(&"menu_pets") == "x" and hints.glyph_name(&"menu_settings") == "y", "Switch 保持物理位置并显示对应字母")
	await shot("stage-nintendo")
	hints._set_family(&"generic", 0)
	check(hints.glyph_name(&"menu_pets") == "north", "未知手柄使用位置图标")
	# 热插拔分类与页面生命周期分离；不依赖保存一份设备配置。
	hints._connection_changed(0, false)
	if Input.get_connected_joypads().is_empty(): check(hints.family == &"keyboard", "断开最后手柄回到键盘")
	router.navigate(&"loading", {"stage_id": "s01"}, false)
	for i in 300:
		await frames(1)
		if router.current_route == &"stage": break
	check(router.current_route == &"stage", "真实关卡可进入")
	var stage: Node = app._current_screen
	var session: Node = stage.stage_session
	check(session.request_pause(&"ui_controller_review"), "真实会话暂停")
	await create_timer(0.2).timeout
	var pause: Node = stage.pause_overlay
	check(pause._continue_button.has_focus(), "暂停默认继续")
	check(pause._root.get_node("Design/Panel").size.x < 1000.0, "暂停框缩小")
	await shot("pause-compact")
	await press(JOY_BUTTON_DPAD_LEFT)
	check(pause._retry_button.has_focus(), "继续左侧为重玩")
	await press(JOY_BUTTON_DPAD_RIGHT)
	check(pause._continue_button.has_focus(), "右侧回到继续")
	pause._on_continue_pressed()
	await create_timer(0.2).timeout
	var eye: TextureRect = pause.get_node("%OpenEye")
	var eye_scale := eye.size.x / eye.texture.get_width()
	var eye_center := eye.get_global_transform_with_canvas() * (Vector2(418,169) * eye_scale)
	var gate: Node2D = stage.get_node("Presentation/GrayboxStagePresentation/CueCanvas/GameplayCueLayer/TwinGateCueVisual")
	for sample in [[&"keyboard", "j", "f"], [&"playstation", "r1", "l1"], [&"xbox", "rb", "lb"], [&"nintendo", "r", "l"], [&"generic", "rb", "lb"]]:
		hints._set_family(sample[0], -1 if sample[0] == &"keyboard" else 0)
		check(gate.debug_snapshot()["life_input_glyph"] == sample[1] and gate.debug_snapshot()["death_input_glyph"] == sample[2], "关内按键提示跟随设备 " + str(sample[0]))
	hints._set_family(&"xbox", 0)
	var gate_center: Vector2 = gate.get_global_transform_with_canvas() * gate.life_gate
	check(eye_center.distance_to(gate_center) < 2.0, "眼眶中心与真实判定圈重合")
	var eye_radius := eye.get_global_transform_with_canvas().basis_xform(Vector2(129 * eye_scale, 0)).length()
	var gate_radius := gate.get_global_transform_with_canvas().basis_xform(Vector2(gate.gate_radius, 0)).length()
	check(absf(eye_radius - gate_radius) < 2.0, "眼眶内半径与判定圈一致")
	await shot("pause-eye-aligned")
	await _check_tuning_glyphs(stage, gate)
	stage.teardown()
	app.queue_free()
	await frames(5)
	await _check_pause_sizes()
	await _glyph_sheet()
	print("CONTROLLER UI: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _glyph_sheet() -> void:
	var canvas := SubViewport.new()
	canvas.size = Vector2i(860, 510)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var bg := ColorRect.new()
	bg.size = Vector2(860,510)
	bg.color = Color("19151f")
	canvas.add_child(bg)
	var names := ["Xbox", "PlayStation", "Nintendo", "通用手柄", "键盘"]
	var families := [&"xbox", &"playstation", &"nintendo", &"generic", &"keyboard"]
	for row in families.size():
		hints._set_family(families[row], 0 if row < 4 else -1)
		var caption := Label.new()
		caption.text = names[row]
		caption.position = Vector2(30, 45 + row * 92)
		caption.add_theme_font_override("font", load("res://assets/fonts/huiwen.otf"))
		caption.add_theme_font_size_override("font_size", 28)
		canvas.add_child(caption)
		for col in 6:
			var icon := TextureRect.new()
			icon.texture = hints.texture_for([&"ui_accept",&"ui_cancel",&"menu_settings",&"menu_pets",&"menu_previous",&"menu_next"][col])
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.position = Vector2(238+col*96, 38+row*92)
			icon.size = Vector2(76, 52)
			canvas.add_child(icon)
	await frames(3)
	await RenderingServer.frame_post_draw
	canvas.get_texture().get_image().save_png(OUT + "/controller-glyphs.png")
	canvas.queue_free()
	await frames()

func _check_pause_sizes() -> void:
	# 正式游戏由 SettingsService 配置 Window 的设计坐标和实际渲染尺寸。
	# 不能将未配置 2D override 的裸 SubViewport 当成正式窗口。
	var settings: Node = root.get_node("SettingsService")
	var previous_resolution: Vector2i = settings.resolution
	var previous_size := root.size
	for window_size: Vector2i in [Vector2i(1280,720), Vector2i(1800,1200)]:
		settings.resolution = Vector2i(1280,720) if window_size.y == 720 else Vector2i(1920,1080)
		settings.apply_display_settings()
		root.size = window_size
		await frames(5)
		var stage: Node = load("res://scenes/stage/stage_root.tscn").instantiate()
		root.add_child(stage)
		await frames(3)
		var pause: Node = stage.pause_overlay
		pause._on_state_changed(0, GameplayTypes.StageState.PAUSED, &"layout_review")
		pause._on_resume_countdown_changed(3.0)
		await create_timer(0.2).timeout
		var eye: TextureRect = pause.get_node("%OpenEye")
		var eye_scale := eye.size.x / eye.texture.get_width()
		var eye_center := eye.get_global_transform_with_canvas() * (Vector2(418,169) * eye_scale)
		var gate: Node2D = stage.get_node("Presentation/GrayboxStagePresentation/CueCanvas/GameplayCueLayer/TwinGateCueVisual")
		var gate_center: Vector2 = gate.get_global_transform_with_canvas() * gate.life_gate
		check(eye_center.distance_to(gate_center) < 2.0, "不同窗口眼眶中心对齐 %s" % window_size)
		var eye_radius := eye.get_global_transform_with_canvas().basis_xform(Vector2(129 * eye_scale,0)).length()
		var gate_radius := gate.get_global_transform_with_canvas().basis_xform(Vector2(gate.gate_radius,0)).length()
		check(absf(eye_radius-gate_radius) < 2.0, "不同窗口眼眶半径对齐 %s" % window_size)
		check(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP, "非 16:9 窗口保持等比留边")
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		check(picture.get_size() == settings.resolution, "实际渲染尺寸沿用正式设置")
		picture.save_png(OUT + "/pause-window-%dx%d.png" % [window_size.x,window_size.y])
		stage.teardown()
		stage.queue_free()
		await frames(4)
	settings.resolution = previous_resolution
	settings.apply_display_settings()
	root.size = previous_size
	await frames(3)

func _check_tuning_glyphs(stage: Node, gate: Node2D) -> void:
	stage.pause_overlay._root.hide()
	# 后续分段经过编译前的深复制仍必须保持无提示，复用后恢复独立滑条默认值。
	var segment := TuningSliderEvent.new()
	segment.show_rotation_cue = false
	var chart := SongChart.new()
	chart.tuning_sliders.append(segment)
	var copied := chart.duplicate(true) as SongChart
	var compiled := ChartCompiler._compile_tuning_sliders(copied, TempoMap.from_chart(copied))
	check(not compiled[0].show_rotation_cue, "后续分段提示标记经过复制与编译仍关闭")
	var cue: Node2D = load("res://scenes/presentation/fields/graybox_tuning_field.tscn").instantiate()
	root.add_child(cue)
	cue.prepare(compiled[0])
	check(not cue._show_rotation_cue, "后续分段不绘制摇杆提示")
	cue.prepare({})
	check(cue._show_rotation_cue, "对象池复用恢复独立滑条的起点提示")
	cue.queue_free()
	var layer := gate.get_parent()
	var sliders: Array[Node2D] = []
	for side in [GameplayTypes.Affinity.ZHU, GameplayTypes.Affinity.XUAN]:
		var field: Node2D = load("res://scenes/presentation/fields/graybox_tuning_field.tscn").instantiate()
		layer.add_child(field)
		field.set_process(false)
		sliders.append(field)
		for rotation_sign in [-1, 1]:
			field.prepare({"event_id": "glyph_review", "affinity": side, "start_value": 0.2, "end_value": 0.7, "traversal_count": 2, "traversal_ticks": 960, "duration_ticks": 1920})
			field.set_slider_state({"required_rotation_sign": rotation_sign, "interaction_open": true, "current_traversal_index": 0})
			field.set_region_progress(0.1)
			var early: Vector2 = field.visual_state_snapshot()["stick_cue_direction"]
			field.set_region_progress(0.4)
			var late: Vector2 = field.visual_state_snapshot()["stick_cue_direction"]
			check(early.angle_to(late) * rotation_sign > 0.0, "摇杆动画采用权威旋向 %d/%d" % [side,rotation_sign])
			await frames(2)
			check(late.is_equal_approx(field.visual_state_snapshot()["stick_cue_direction"]), "时钟不推进时手势冻结")
			field.set_region_progress(0.1)
			check(early.is_equal_approx(field.visual_state_snapshot()["stick_cue_direction"]), "定位恢复相同手势姿态")
		# 长滑条上仍反复演示，不会随总时长变成几乎静止的图标。
		field.prepare({"affinity": side, "start_value": 0.2, "end_value": 0.7, "duration_us": 12_000_000, "traversal_count": 1})
		field.set_slider_state({"required_rotation_sign": 1, "current_traversal_index": 0})
		field.set_region_progress(0.2 / 12.0)
		var first_demo: Vector2 = field._stick_cue_pose()["direction"]
		field.set_region_progress(1.4 / 12.0)
		check(first_demo.is_equal_approx(field._stick_cue_pose()["direction"]), "长单程每 1.2 秒循环同向演示")
		field.set_region_progress(1.2 / 12.0)
		check(is_zero_approx(field._stick_cue_pose()["demo_alpha"]), "演示复位时隐藏帽面，避免误示反向")
		field.prepare({"affinity": side, "start_value": 0.2, "end_value": 0.7, "traversal_count": 2, "traversal_ticks": 960, "duration_ticks": 1920})
		var start_center: Vector2 = field._stick_cue_pose()["center"]
		field.set_slider_state({"interaction_open": true, "endpoint_target_progress": 1.0})
		check(start_center.is_equal_approx(field._stick_cue_pose()["center"]), "开始交互后摇杆仍固定在起点")
		field.set_slider_state({"interaction_open": true, "endpoint_target_progress": 0.0, "current_traversal_index": 1})
		check(start_center.is_equal_approx(field._stick_cue_pose()["center"]), "折返不移动摇杆提示")
		# 第一程与折返衔接，同一端点没有反向跳位。
		var sign_value := 1 if side == GameplayTypes.Affinity.ZHU else -1
		field.set_slider_state({"required_rotation_sign": sign_value, "current_traversal_index": 0})
		field.set_region_progress(0.5)
		var endpoint: Vector2 = field.visual_state_snapshot()["stick_cue_direction"]
		field.set_slider_state({"required_rotation_sign": -sign_value, "current_traversal_index": 1})
		check(endpoint.is_equal_approx(field.visual_state_snapshot()["stick_cue_direction"]), "折返在同一摇杆端点接续")
		field.set_preview_presentation(1, 0, 1.0)
		field.set_tuning_active(true)
		field.set_slider_state({"required_rotation_sign": sign_value, "current_traversal_index": 0, "player_progress": 0.5})
	for progress in [0.1, 0.25, 0.4]:
		for field: Node2D in sliders:
			field.set_region_progress(progress)
		await shot("tuning-stick-%02d" % roundi(progress * 100))
	for field: Node2D in sliders:
		field.reset_for_pool()
		check(not field.visible, "回收隐藏整个手势")
		field.queue_free()
	await frames()
