extends SceneTree
## 使用隔离存档、正式弹窗和真实输入事件验证；假后端只证明软件输出，不代替实机震感。
const OUT := "res://builds/settings-review"
var checks := 0
var failures := 0
var hints: Node
var settings: Node

class HapticsBackend extends RefCounted:
	var available := true
	var bound := false
	var outputs: Array = []
	var stops := 0
	func list_devices() -> Array[Dictionary]:
		return [{"device_id": 71, "name": "测试手柄"}] if available else []
	func bind_device(id: int) -> bool:
		bound = available and id == 71
		return bound
	func get_capabilities() -> Dictionary:
		return {"device_id": 71, "dual_strength": bound and available}
	func get_output_status() -> Dictionary:
		return {"device_id": 71, "mode": "dual_strength" if available and bound else "unsupported"}
	func set_output(lf: float, ls: float, rf: float, rs: float, fm: float, sm: float) -> bool:
		outputs.append([lf, ls, rf, rs, fm, sm])
		return available and bound
	func stop() -> void: stops += 1
	func unbind_device() -> void: bound = false

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 3) -> void:
	for i in count: await process_frame

func press(code: JoyButton) -> void:
	for down in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = code; event.pressed = down; event.device = 0
		Input.parse_input_event(event)
		await frames(2)

func shot(name: String) -> void:
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "/" + name + ".png")

func run() -> void:
	if not OS.get_user_data_dir().contains("UIReview"):
		push_error("请使用 tools/ui/run_ui_review.ps1 -Suites settings-ux 隔离玩家配置")
		quit(2); return
	DirAccess.make_dir_recursive_absolute(OUT)
	hints = root.get_node("UiInputHints")
	settings = root.get_node("SettingsService")
	test_cursor()
	test_persistence()
	test_runtime_strength()
	settings.resolution = Vector2i(1280,720); settings.fullscreen = false
	settings.apply_display_settings()
	var app = load("res://scenes/app/app_main.tscn").instantiate()
	app._title_revealed = true
	root.add_child(app)
	root.get_node("AppRouter").navigate(&"stage_select")
	await create_timer(0.35).timeout
	await test_pets(app)
	var opener: Button = app._current_screen.get_node("Design/Actions/Settings")
	opener.grab_focus()
	settings.controller_haptics_scale = 0.6
	app._show_modal(load("res://scenes/ui/modals/settings_modal.tscn"))
	await frames()
	var modal: Control = app.modal_host.get_child(0)
	check(modal._pages.size() == 4, "四类设置均存在")
	modal.select_tab(2)
	check(is_equal_approx(modal.get_node("%Haptics").value, 0.6), "打开时读取玩家倍率")
	modal.get_node("%Haptics").value = 0.3
	modal._restore_page_defaults()
	check(modal.get_node("%Haptics").value == 1.0 and settings.controller_haptics_scale == 0.6, "恢复默认只改变本页草稿")
	check(modal.get_node("%HapticsValue").text == "50%", "默认倍率1显示50%")
	modal.get_node("%Haptics").value = 2.0
	check(modal.get_node("%HapticsValue").text == "100%", "最大倍率2显示100%")
	modal.select_tab(0); modal.get_node("%Music").value = -20.0
	modal._restore_page_defaults()
	check(modal.get_node("%Music").value == -4.0, "声音页恢复脚本初值")
	modal.select_tab(1); modal.get_node("%Wave").value = 0.35
	modal._restore_page_defaults()
	check(is_equal_approx(modal.get_node("%Wave").value, 0.85), "画面页恢复相纹默认")
	modal.select_tab(3)
	modal.get_node("%CalibrationPage").get_node("%AudioOffset").value = 60
	modal._restore_page_defaults()
	check(modal.get_node("%CalibrationPage").draft_values().audio_output_offset_ms == 0, "校准恢复本页默认复用归零")
	modal.select_tab(2)
	test_preview(modal)
	# 上下导航及滚动通过真实事件；右侧数值控件左右调值。
	modal.get_node("%Haptics").grab_focus()
	var original: float = modal.get_node("%Haptics").value
	await press(JOY_BUTTON_DPAD_LEFT)
	check(is_equal_approx(modal.get_node("%Haptics").value, original - 0.1), "手柄每次调整5%")
	for i in 12:
		await press(JOY_BUTTON_DPAD_DOWN)
		var owner := root.gui_get_focus_owner()
		check(owner != null and modal.is_ancestor_of(owner) and not owner is Label and not owner is ScrollBar, "焦点只在弹窗可操作项中")
	modal.select_tab(3)
	await frames()
	modal.get_node("%CalibrationPage").get_node("%VisualOffset").get_line_edit().grab_focus()
	await frames()
	check(modal.get_node("%Scroll").scroll_vertical > 0, "校准页跟随下方焦点滚动")
	modal._show_controls(); await frames(); modal._hide_controls()
	check(modal.get_node("%Controls").has_focus(), "操作说明关闭后回到原入口")
	for size: Vector2i in [Vector2i(1280,720), Vector2i(1920,1080)]:
		settings.resolution = size; settings.apply_display_settings()
		for i in 4:
			modal.select_tab(i); modal._tabs[i].grab_focus()
			modal.get_node("%Error").text = ""
			await shot("%d-%s" % [size.y, ["sound","display","controller","calibration"][i]])
			var scroll: ScrollContainer = modal.get_node("%Scroll")
			check(scroll.position.y + scroll.size.y < modal.get_node("%Defaults").position.y, "内容与底部按钮无重叠")
	modal.get_node("%Haptics").value = 0.25
	await press(JOY_BUTTON_B)
	await create_timer(0.2).timeout
	check(settings.controller_haptics_scale == 0.6 and opener.has_focus(), "取消不保存并恢复入口焦点")
	app._show_modal(load("res://scenes/ui/modals/settings_modal.tscn"))
	await frames()
	modal = app.modal_host.get_child(0)
	modal.get_node("%Haptics").value = 0.5
	modal._save_and_close()
	await create_timer(0.2).timeout
	settings.controller_haptics_scale = 0.0; settings.load_settings()
	check(settings.controller_haptics_scale == 0.5, "弹窗保存后重新读取仍为25%")
	app.free()
	print("SETTINGS/CURSOR/PET UX: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func test_cursor() -> void:
	hints._window_focused = true; hints._cursor_released_until_input = false
	hints._set_family(&"xbox", 0)
	check(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN, "手柄隐藏光标")
	var mouse := InputEventMouseMotion.new(); mouse.relative = Vector2(8,0)
	hints.observe(mouse)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "鼠标移动恢复光标")
	var axis := InputEventJoypadMotion.new(); axis.axis = JOY_AXIS_LEFT_X; axis.device = 0
	axis.axis_value = 0.1; hints.observe(axis)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "摇杆漂移不切换设备")
	axis.axis_value = 0.8; hints.observe(axis)
	check(not hints.mouse_hover_enabled(), "手柄时禁止旧鼠标位置悬停")
	hints.set_gameplay_mouse_capture(true)
	check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "调频捕获优先")
	hints.observe(mouse); hints.set_gameplay_mouse_capture(false)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "退出捕获按最新鼠标设备显示")
	hints.observe(axis); hints.set_gameplay_mouse_capture(true); hints.set_gameplay_mouse_capture(false)
	check(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN, "手柄暂停后隐藏而非恢复旧快照")
	hints.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "失焦交还光标")
	hints.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	hints.observe(axis); hints.set_gameplay_mouse_capture(true)
	hints._connection_changed(0, false)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "活动手柄断开交还光标")
	hints.set_gameplay_mouse_capture(false); hints.observe(mouse)

func test_persistence() -> void:
	# 全部写入独立UIReview目录，绝不修改玩家原有配置。
	var legacy := ConfigFile.new(); legacy.set_value("audio", "music_volume_db", -4.0)
	legacy.save(settings.SETTINGS_PATH)
	settings.controller_haptics_scale = 0.2; settings.load_settings()
	check(settings.controller_haptics_scale == 1.0, "旧配置缺项默认倍率1（界面50%）")
	legacy.set_value("controller", "controller_haptics_scale", 0.6); legacy.save(settings.SETTINGS_PATH)
	settings.load_settings()
	check(is_equal_approx(settings.controller_haptics_scale, 0.6), "旧配置保留实际倍率，不重复换算")
	for value: float in [0.0, 1.0, 2.0]:
		settings.controller_haptics_scale = value
		check(settings.save_settings(), "强度配置写入成功")
		settings.controller_haptics_scale = -1.0; settings.load_settings()
		check(settings.controller_haptics_scale == value, "0/50/100%重新加载一致")

func make_haptics(parent: Node, backend: HapticsBackend) -> ControllerHaptics:
	var haptics := ControllerHaptics.new(); haptics._backend = backend
	parent.add_child(haptics); haptics._focused = true
	haptics.set_output_enabled(true)
	return haptics

func test_runtime_strength() -> void:
	var backend := HapticsBackend.new()
	var haptics := make_haptics(root, backend)
	# 延迟加载宿主脚本，避免命令行主脚本在 Autoload 注册前解析它的依赖。
	var stage = load("res://src/runtime/session/stage_root.gd").new()
	stage.controller_haptics = haptics; stage._haptics_base_strength = 0.6
	var hold := haptics.create_handle(ControllerHaptics.MotorSide.RIGHT, 0.35, 4.0)
	hold.set_enabled(true)
	for value: float in [0.0, 1.0, 2.0, 1.0]:
		settings.controller_haptics_scale = value; stage._apply_haptics_settings()
		haptics.play_once(ControllerHaptics.MotorSide.LEFT, 1.0, 120.0, 80.0)
		var output: Array = backend.outputs.back()
		check(is_equal_approx(output[5], 0.6 * value), "玩家倍率与场景倍率只相乘一次")
		check(output.slice(0,4) == [120.0,1.0,4.0,0.35], "Tap和Hold原强度与频率不改写")
	haptics.free(); stage.free()

func test_preview(modal: Control) -> void:
	var page: Control = modal.get_node("%ControllerPage")
	page.deactivate()
	var backend := HapticsBackend.new()
	page._haptics = make_haptics(page, backend); page.activate()
	modal.get_node("%Haptics").value = 0.5
	check(backend.outputs.is_empty(), "拖动滑条不自动试震")
	page._test_haptics()
	check(backend.outputs.back() == [120.0,1.0,120.0,1.0,1.0,0.5], "试震用草稿25%并保持120Hz双侧")
	check(page._haptics._one_shots.size() == 1 and page._haptics._one_shots[0].until_us - Time.get_ticks_usec() <= 80000, "只发送80ms短震")
	check(settings.controller_haptics_scale == 0.6, "试震不改玩家配置")
	modal.get_node("%Haptics").value = 0.0
	var count := backend.outputs.size(); page._test_haptics()
	check(backend.outputs.size() == count, "0%不发送试震")
	modal.get_node("%Haptics").value = 2.0; page._test_haptics()
	check(backend.outputs.back()[5] == 2.0, "100%试震发送两倍强度倍率")
	page.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(page._haptics._one_shots.is_empty(), "失焦清除试震")
	modal.get_node("%TestHaptics").grab_focus()
	backend.available = false; page._connection_changed(0, false); page._refresh_device()
	check(modal.get_node("%TestHaptics").disabled and modal.get_node("%Haptics").has_focus(), "断连禁用测试且焦点回到滑条")
	page.deactivate()
	check(not backend.bound and backend.stops > 0, "离页停止并释放测试设备")
	page.activate()

func test_pets(app: Node) -> void:
	var saves: Node = root.get_node("SaveService")
	var previous: Dictionary = saves.data.duplicate(true)
	var opener: Button = app._current_screen.get_node("Design/Actions/Pets")
	opener.grab_focus()
	app._show_modal(load("res://scenes/ui/modals/pet_select_modal.tscn"))
	await frames()
	var modal: Control = app.modal_host.get_child(0)
	for owned in [false, true]:
		for entry in modal.entries: saves.data.pets[entry.pet_id] = {"owned": owned, "advanced": owned}
		modal._show_pet()
		modal.get_node("%Back").grab_focus()
		for i in 12:
			await press(JOY_BUTTON_DPAD_DOWN)
			var owner := root.gui_get_focus_owner()
			check(owner is BaseButton and modal.is_ancestor_of(owner) and not owner.disabled, "随从上下导航仅停在可操作按钮")
		check(modal.get_node("%Base").focus_mode == Control.FOCUS_NONE and modal.get_node("%Advanced").focus_mode == Control.FOCUS_NONE, "两条技能描述不可聚焦")
	await press(JOY_BUTTON_B); await create_timer(0.2).timeout
	check(opener.has_focus(), "关闭随从回到原入口")
	saves.data = previous
