extends SceneTree

## 应用流程烟雾测试。
## 从主场景启动并走到真实关卡，快速发现路由、全局服务或透明 UI 吞输入等问题。

## 已执行的断言数量，用来确认测试没有提前跳过主要流程。
var _checks := 0
## 累计失败消息；所有流程跑完后统一输出，避免首个错误遮住后续问题。
var _failures: PackedStringArray = []
## 本测试挂到 SceneTree 下的正式 AppMain 实例；结束时统一 `queue_free()`。
var _app: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# 这里加载正式主场景，因此 project.godot 中的 Autoload 也会参与测试。
	var app_scene := load("res://scenes/app/app_main.tscn") as PackedScene
	_expect(app_scene != null, "AppMain scene loads")
	if app_scene == null:
		_finish()
		return
	var app := app_scene.instantiate()
	_app = app
	root.add_child(app)
	await process_frame
	await process_frame
	# 先检查透明应用容器不会截走关卡鼠标输入，再验证各页面路由。
	_expect_equal(
		(app as Control).mouse_filter,
		Control.MOUSE_FILTER_IGNORE,
		"AppMain does not consume gameplay mouse input"
	)
	_expect_equal(
		(app.get_node("ScreenHost") as Control).mouse_filter,
		Control.MOUSE_FILTER_IGNORE,
		"ScreenHost does not consume gameplay mouse input"
	)
	var router := root.get_node_or_null("AppRouter")
	_expect(router != null, "AppRouter autoload is available")
	if router == null:
		_finish()
		return
	_expect_equal(router.current_route, &"title", "boot routes to Title")
	_expect(_has_child_named(app.get_node("ScreenHost"), "TitleScreen"), "TitleScreen is mounted")
	var title_start := _find_button_with_text(app.get_node("ScreenHost"), "开始渡河")
	_expect(title_start != null and title_start.has_focus(), "title gives controller focus to Start")
	_send_joy_button(JOY_BUTTON_A, true)
	await process_frame
	_send_joy_button(JOY_BUTTON_A, false)
	await process_frame
	_expect_equal(router.current_route, &"stage_select", "gamepad A confirms the focused menu button")
	_send_joy_button(JOY_BUTTON_B, true)
	await process_frame
	_send_joy_button(JOY_BUTTON_B, false)
	await process_frame
	_expect_equal(router.current_route, &"title", "gamepad B returns from StageSelect")
	var settings_modal := (load("res://scenes/ui/modals/settings_modal.tscn") as PackedScene).instantiate()
	root.add_child(settings_modal)
	await process_frame
	var frequency_slider := settings_modal.find_child("TuningWaveFrequencySlider", true, false) as HSlider
	_expect(frequency_slider != null, "settings exposes a dedicated tuning-wave frequency slider")
	if frequency_slider != null:
		# 设置弹窗既要展示安全范围，也要从 SettingsService 读回持久化值。
		var settings_service := root.get_node("SettingsService")
		_expect_equal(frequency_slider.min_value, 0.35, "frequency slider exposes the safe low-density limit")
		_expect_equal(frequency_slider.max_value, 1.0, "frequency slider can restore the original visual density")
		_expect_equal(frequency_slider.step, 0.05, "frequency slider uses readable five-percent steps")
		_expect_near(
			frequency_slider.value,
			float(settings_service.get("tuning_wave_frequency_scale")),
			0.000001,
			"frequency slider opens at the persisted value"
		)
	settings_modal.free()

	router.call("navigate", &"stage_select", {}, false)
	await process_frame
	_expect_equal(router.current_route, &"stage_select", "Title routes to StageSelect")
	_expect(_has_child_named(app.get_node("ScreenHost"), "StageSelectScreen"), "StageSelectScreen is mounted")
	var content_catalog := root.get_node_or_null("ContentCatalog")
	_expect(
		content_catalog != null and content_catalog.call("get_stage", "s01") != null,
		"runtime catalog exposes playable test stage s01"
	)

	router.call("navigate", &"loading", {"stage_id": "s01"}, false)
	for _index: int in 240:
		await process_frame
		if router.current_route == &"stage":
			break
	_expect_equal(router.current_route, &"stage", "threaded loading routes to Stage")
	var stage_root := app.get_node("ScreenHost").get_node_or_null("StageRoot")
	_expect(stage_root != null, "StageRoot is mounted")
	if stage_root != null:
		var session := stage_root.get_node_or_null("Session/StageSession")
		_expect(session != null and session.stage_definition != null, "StageSession receives StageDefinition")
		if session != null and session.stage_definition != null:
			_expect_equal(session.stage_definition.stage_id, "s01", "loaded stage ID is s01")
		var input_router := stage_root.get_node_or_null("Session/InputRouter")
		var semantic_kinds: Array[int] = []
		var strike_affinities: Array[int] = []
		var presentation := stage_root.get_node_or_null("Presentation/GrayboxStagePresentation")
		if presentation != null:
			presentation.bell_struck.connect(func(affinity: int) -> void:
				strike_affinities.append(affinity)
			)
		if input_router != null:
			input_router.semantic_input_emitted.connect(func(sample: SemanticInputSample) -> void:
				semantic_kinds.append(sample.kind)
			)
			_send_mouse_button(MOUSE_BUTTON_LEFT, true)
			await process_frame
			_send_mouse_button(MOUSE_BUTTON_LEFT, false)
			_send_mouse_button(MOUSE_BUTTON_RIGHT, true)
			await process_frame
			_send_mouse_button(MOUSE_BUTTON_RIGHT, false)
			await process_frame
		_expect(
			semantic_kinds.has(GameplayTypes.SemanticInputKind.DEATH_PRESSED),
			"physical left mouse click reaches the death bell"
		)
		_expect(
			semantic_kinds.has(GameplayTypes.SemanticInputKind.LIFE_PRESSED),
			"physical right mouse click reaches the life bell"
		)
		_expect_equal(
			semantic_kinds,
			[
				GameplayTypes.SemanticInputKind.DEATH_PRESSED,
				GameplayTypes.SemanticInputKind.DEATH_RELEASED,
				GameplayTypes.SemanticInputKind.LIFE_PRESSED,
				GameplayTypes.SemanticInputKind.LIFE_RELEASED,
			],
			"left-death then right-life mouse order remains deterministic"
		)
		_expect_equal(
			strike_affinities,
			[GameplayTypes.Affinity.XUAN, GameplayTypes.Affinity.ZHU],
			"left/right mouse presses produce immediate death/life visual feedback"
		)
		if input_router != null:
			_expect(not input_router.life_held and not input_router.death_held, "mouse releases clear both held states")
		semantic_kinds.clear()
		strike_affinities.clear()
		_send_key(KEY_F, true)
		await process_frame
		_send_key(KEY_F, false)
		_send_key(KEY_J, true)
		await process_frame
		_send_key(KEY_J, false)
		await process_frame
		_expect_equal(
			semantic_kinds,
			[
				GameplayTypes.SemanticInputKind.DEATH_PRESSED,
				GameplayTypes.SemanticInputKind.DEATH_RELEASED,
				GameplayTypes.SemanticInputKind.LIFE_PRESSED,
				GameplayTypes.SemanticInputKind.LIFE_RELEASED,
			],
			"PC F/J fallback follows left-death then right-life"
		)
		_expect_equal(
			strike_affinities,
			[GameplayTypes.Affinity.XUAN, GameplayTypes.Affinity.ZHU],
			"F/J fallback produces matching death/life bell feedback"
		)
		if session != null:
			session.resume_countdown_sec = 0.0
			_send_joy_button(JOY_BUTTON_START, true)
			await process_frame
			_send_joy_button(JOY_BUTTON_START, false)
			await process_frame
			_expect_equal(session.state, GameplayTypes.StageState.PAUSED, "gamepad Start pauses gameplay")
			_send_joy_button(JOY_BUTTON_B, true)
			await process_frame
			_send_joy_button(JOY_BUTTON_B, false)
			await process_frame
			_expect(session.state != GameplayTypes.StageState.PAUSED, "gamepad B resumes from the pause overlay")
		if stage_root.has_method("teardown"):
			stage_root.call("teardown")
			await process_frame
			# Headless 的 Dummy 音频在线程中处理停止命令。
			# 正常页面切换自然会留出这点时间，烟雾测试则会立即退出。
			await create_timer(0.08, true).timeout
	_finish()


# 让合成事件经过真实 Input Map 和 _unhandled_input，才能查出键位错误或透明 UI 吞输入。
func _send_mouse_button(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = Vector2(960.0, 540.0)
	event.global_position = event.position
	Input.parse_input_event(event)


func _send_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)


func _send_joy_button(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


func _find_button_with_text(parent: Node, text_value: String) -> Button:
	if parent is Button and (parent as Button).text == text_value:
		return parent as Button
	for child: Node in parent.get_children():
		var found := _find_button_with_text(child, text_value)
		if found != null:
			return found
	return null


func _has_child_named(parent: Node, child_name: String) -> bool:
	return parent != null and parent.get_node_or_null(child_name) != null


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, var_to_str(actual), var_to_str(expected)])


func _expect_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s (actual=%s expected=%s)" % [message, actual, expected])


func _finish() -> void:
	if is_instance_valid(_app):
		_app.free()
	if _failures.is_empty():
		print("APP FLOW TESTS: %d checks passed." % _checks)
		quit(0)
		return
	printerr("APP FLOW TESTS FAILED: %d/%d checks failed." % [_failures.size(), _checks])
	for failure: String in _failures:
		printerr("  - " + failure)
	quit(1)
