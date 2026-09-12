extends Control

## 本次游玩固定的随从身份；重试沿用，返回选择页后重新解析。
var _run_pet: PetDefinition
var _run_pet_advanced := false
var _run_pet_ready := false

## 应用层总入口。负责页面与弹窗的装卸，并把关卡结果送往存档和结算页。

## 标题页场景模板，进入应用或返回首页时实例化。
const LOCAL_SCENE := preload("res://scenes/screens/local_charts_screen.tscn")
const TITLE_SCENE := preload("res://scenes/screens/title_screen.tscn")
## 选关页场景模板，集中展示 ContentCatalog 中的可用关卡。
const STAGE_SELECT_SCENE := preload("res://scenes/screens/stage_select_screen.tscn")
## 加载页场景模板，负责异步装入一关及其依赖资源。
const LOADING_SCENE := preload("res://scenes/screens/stage_loading_screen.tscn")
## 结算页场景模板，展示 StageSession 产出的最终成绩。
const RESULT_SCENE := preload("res://scenes/screens/result_screen.tscn")
## 设置弹窗模板；弹窗覆盖当前页面，不进入页面路由历史。
const SETTINGS_MODAL := preload("res://scenes/ui/modals/settings_modal.tscn")
## 音画与输入校准弹窗模板。
const CALIBRATION_MODAL := preload("res://scenes/ui/modals/calibration_modal.tscn")
## 随从查看和装备弹窗模板。
const PET_SELECT_MODAL := preload("res://scenes/ui/modals/pet_select_modal.tscn")
## 公共关卡运行场景路径；具体歌曲、谱面和美术资源由 StageDefinition 注入。
const STAGE_ROOT_PATH := "res://scenes/stage/stage_root.tscn"

## 当前全屏页面的挂载容器。场景中的 `%ScreenHost` 必须启用“唯一名称”。
@onready var screen_host: Control = %ScreenHost
## 模态弹窗的挂载容器；打开弹窗时会暂时拦截鼠标输入。
@onready var modal_host: Control = %ModalHost

## 当前挂载的页面或关卡根节点。切页时先释放它，避免两个页面同时响应输入。
var _current_screen: Node
## 最近启动的关卡定义。关卡结束后仍需保留到结算页和重试流程使用。
var _current_stage: StageDefinition
# 来源上下文贯穿重试和结算；不借用 Catalog 的内置关卡路径。
var _run_context := {}
var _library := LocalChartLibrary.new()
var _jobs := ChartReadJobs.new()
var _load_request := -1
var _local_selection := {}
var _load_message: Label



func _ready() -> void:
	if StudioLaunch.is_level_editor():
		get_tree().change_scene_to_file.call_deferred("res://scenes/tools/level_studio/studio.tscn")
		return
	if StudioLaunch.is_active():
		get_tree().change_scene_to_file.call_deferred("res://scenes/tools/chart_studio/studio.tscn")
		return
	# AppRouter 记录页面和返回历史；具体实例化哪个场景仍由这个宿主统一完成。
	AppRouter.route_requested.connect(_on_route_requested)
	AppRouter.clear_history()
	_library.open()
	add_child(_jobs)
	_jobs.completed.connect(_external_loaded)
	var trial := ChartTrialLaunch.arguments()
	if trial.has("path"):
		ChartTrialLaunch.report(trial, "recognized")
		AppRouter.navigate(&"external_loading", trial, false)
	else:
		AppRouter.navigate(AppRouter.ROUTE_TITLE, {}, false)


func _on_route_requested(route: StringName, context: Dictionary) -> void:
	# 设置、校准和随从属于覆盖式弹窗：它们不卸载当前页面，也不写入页面返回栈。
	match route:
		&"settings":
			_show_modal(SETTINGS_MODAL)
			return
		&"calibration":
			_show_modal(CALIBRATION_MODAL)
			return
		&"pets":
			_show_modal(PET_SELECT_MODAL)
			return
	# 其余路由都代表完整页面切换，同一时间只保留一个 ScreenHost 子节点。
	_clear_screen()
	match route:
		&"local_charts":
			_show_local_charts()
		&"external_loading":
			_show_external_loading(context)
		AppRouter.ROUTE_TITLE:
			_show_title()
		AppRouter.ROUTE_STAGE_SELECT:
			_show_stage_select()
		AppRouter.ROUTE_LOADING:
			_show_loading(str(context.get("stage_id", "")))
		AppRouter.ROUTE_STAGE:
			_show_stage(context.get("stage") as StageDefinition)
		AppRouter.ROUTE_RESULT:
			_show_result(context.get("stage") as StageDefinition, context.get("result", {}) as Dictionary)
		_:
			_show_error("未知页面：%s" % route)
	AppRouter.commit_route(route, context)


func _show_title() -> void:
	var screen := TITLE_SCENE.instantiate()
	_mount_screen(screen)
	screen.start_requested.connect(func() -> void: AppRouter.navigate(AppRouter.ROUTE_STAGE_SELECT))
	screen.settings_requested.connect(func() -> void: _show_modal(SETTINGS_MODAL))
	screen.calibration_requested.connect(func() -> void: _show_modal(CALIBRATION_MODAL))


func _show_stage_select() -> void:
	_run_pet_ready = false
	MenuAudioService.stop_preview()
	var screen := STAGE_SELECT_SCENE.instantiate()
	_mount_screen(screen)
	screen.stage_selected.connect(func(stage_id: String) -> void:
		AppRouter.navigate(AppRouter.ROUTE_LOADING, {"stage_id": stage_id})
	)
	screen.back_requested.connect(func() -> void: AppRouter.navigate(AppRouter.ROUTE_TITLE))
	screen.settings_requested.connect(func() -> void: _show_modal(SETTINGS_MODAL))
	screen.local_charts_requested.connect(func(): AppRouter.navigate(&"local_charts"))
	screen.pets_requested.connect(func() -> void: _show_modal(PET_SELECT_MODAL))


func _show_loading(stage_id: String) -> void:
	_run_context = {}
	var screen := LOADING_SCENE.instantiate()
	_mount_screen(screen)
	screen.stage_ready.connect(func(stage: StageDefinition) -> void:
		AppRouter.navigate(AppRouter.ROUTE_STAGE, {"stage": stage}, false)
	)
	screen.load_cancelled.connect(func() -> void: AppRouter.navigate(AppRouter.ROUTE_STAGE_SELECT, {}, false))
	screen.load_failed.connect(func(_message: String) -> void: pass)
	screen.begin.call_deferred(stage_id)


func _show_stage(stage: StageDefinition) -> void:
	if stage == null:
		_show_error("没有可加载的关卡定义。")
		return
	if not ResourceLoader.exists(STAGE_ROOT_PATH):
		_show_error("StageRoot 尚未生成。")
		return
	_current_stage = stage
	var packed := load(STAGE_ROOT_PATH) as PackedScene
	var stage_root := packed.instantiate()
	_mount_screen(stage_root)
	# 输入、音频、画面三种偏移由 SongClock 分开处理，不能先在应用层相加。
	var song_clock := stage_root.get_node_or_null("Session/SongClock")
	if song_clock != null:
		song_clock.set("input_compensation_sec", SettingsService.input_compensation_sec())
		song_clock.set("visual_lead_sec", SettingsService.visual_lead_sec())
		if _object_has_property(song_clock, &"audio_calibration_sec"):
			song_clock.set("audio_calibration_sec", SettingsService.audio_calibration_sec())
	if stage_root.has_method("set_debug_visible"):
		stage_root.call("set_debug_visible", SettingsService.debug_hud_enabled)
	_connect_first_signal(stage_root, [&"stage_finished", &"result_ready", &"stage_result"], _on_stage_finished)
	_connect_first_signal(stage_root, [&"exit_requested", &"quit_requested"], _on_stage_exit_requested)
	# 本地游玩使用同一装备；编辑器临时试玩始终使用空配置。
	if not _run_pet_ready:
		_run_pet = ContentCatalog.get_pet(SaveService.equipped_pet_id()) if _run_context.get("origin", "") != "trial" else null
		_run_pet_advanced = SaveService.equipped_pet_advanced() if _run_pet != null else false
		_run_pet_ready = true
	stage_root.set_pet(_run_pet, _run_pet_advanced)
	var stage_started := false
	if not _run_context.is_empty():
		stage_started = stage_root.load_stage(stage, false)
		if stage_started:
			_run_context.content_hash = stage_root.stage_session.compiled_chart.content_hash
			var pause: PauseOverlay = stage_root.get_node("PauseLayer")
			pause.configure_external(_run_context.origin == "trial")
			pause.external_retry_requested.connect(_retry_external)
			pause.add_local_requested.connect(_add_trial_to_library)
			ChartTrialLaunch.report(_run_context, "ready")
			_start_countdown(stage_root)
	elif stage_root.has_method("configure_stage"):
		stage_started = bool(stage_root.call("configure_stage", stage))
	elif stage_root.has_method("start_stage"):
		stage_started = bool(stage_root.call("start_stage", stage))
	else:
		_show_error("StageRoot 缺少 configure_stage/start_stage 接口。")
		return
	# 关卡节点已经挂上树，并不代表编译、音频和会话真的准备成功。
	# 失败时必须立刻撤下空壳关卡；否则歌曲时间永远停在 0，看起来像程序卡死。
	if not stage_started:
		ChartTrialLaunch.report(_run_context, "error", "谱面编译或关卡准备失败")
		_show_error("关卡载入失败：谱面或运行配置无效。")


func _show_result(stage: StageDefinition, result: Dictionary) -> void:
	var screen := RESULT_SCENE.instantiate()
	_mount_screen(screen)
	screen.present(stage, result)
	if result.has("local_save_error"): screen.show_notice(str(result.local_save_error))
	if not _run_context.is_empty():
		screen.configure_external(_run_context.origin == "trial")
		screen.add_local_requested.connect(_add_trial_to_library)
	screen.retry_requested.connect(func(stage_id: String) -> void:
		if not _run_context.is_empty(): _retry_external()
		else: AppRouter.navigate(AppRouter.ROUTE_LOADING, {"stage_id": stage_id}, false)
	)
	screen.stage_select_requested.connect(_on_stage_exit_requested)


func _on_stage_finished(result: Variant = {}) -> void:
	var result_dictionary := result as Dictionary if result is Dictionary else {}
	if not result_dictionary.has("cleared") and result_dictionary.has("success"):
		result_dictionary["cleared"] = bool(result_dictionary["success"])
	if not result_dictionary.has("full_combo"):
		result_dictionary["full_combo"] = bool(result_dictionary.get("fc", false))
	if not result_dictionary.has("all_perfect"):
		result_dictionary["all_perfect"] = bool(result_dictionary.get("ap", false))
	if _run_context.is_empty():
		if _current_stage != null: SaveService.record_stage_result(_current_stage, result_dictionary)
	elif _run_context.origin == "local":
		result_dictionary.content_hash = _run_context.content_hash
		var error := _library.record_result(_run_context, result_dictionary)
		if not error.is_empty(): result_dictionary.local_save_error = error
		if _current_stage != null and _current_stage.has_meta("level"):
			SaveService.record_stage_result(_current_stage,result_dictionary)
	AppRouter.navigate(AppRouter.ROUTE_RESULT, {"stage": _current_stage, "result": result_dictionary}, false)


func _on_stage_exit_requested() -> void:
	_run_pet_ready = false
	if _run_context.get("origin") == "trial": get_tree().quit()
	elif _run_context.get("origin") == "local": AppRouter.navigate(&"local_charts", {}, false)
	else: AppRouter.navigate(AppRouter.ROUTE_STAGE_SELECT, {}, false)


func _connect_first_signal(source: Object, names: Array[StringName], callback: Callable) -> void:
	for signal_name: StringName in names:
		if source.has_signal(signal_name):
			source.connect(signal_name, callback)
			return


func _object_has_property(source: Object, property_name: StringName) -> bool:
	for property_data: Dictionary in source.get_property_list():
		if property_data.get("name", &"") == property_name:
			return true
	return false


func _show_modal(scene: PackedScene) -> void:
	var previous_focus: Control = get_viewport().gui_get_focus_owner()
	for child: Node in modal_host.get_children():
		child.queue_free()
	# 鼠标遮罩不会阻止方向键寻焦；弹窗期间整棵底层页面退出焦点导航。
	screen_host.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	var modal := scene.instantiate()
	modal_host.add_child(modal)
	# 平时 ModalHost 必须放过鼠标，关卡的左右鼠标点击才能进入输入单例；
	# 真正打开弹窗时才拦截鼠标，关闭后立刻恢复。键盘和手柄不受 mouse_filter 控制。
	modal_host.mouse_filter = Control.MOUSE_FILTER_STOP
	if modal.has_signal("close_requested"):
		modal.connect("close_requested", func() -> void:
			modal.queue_free()
			modal_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
			screen_host.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
			# 纯手柄操作时，弹窗关闭后把焦点还给打开弹窗前的按钮。
			if is_instance_valid(previous_focus) and previous_focus.is_visible_in_tree():
				previous_focus.grab_focus.call_deferred()
		)


func _mount_screen(screen: Node) -> void:
	_current_screen = screen
	screen_host.add_child(screen)


func _clear_screen() -> void:
	_jobs.cancel_request(_load_request)
	_load_request = -1
	_current_stage = null if AppRouter.current_route != AppRouter.ROUTE_RESULT else _current_stage
	for child: Node in screen_host.get_children():
		screen_host.remove_child(child)
		child.queue_free()
	_current_screen = null


func _show_error(message: String) -> void:
	_clear_screen()
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MingheUiStyle.style_title(label, 30)
	screen_host.add_child(label)
	var back := Button.new()
	back.text = "结束试玩" if _run_context.get("origin") == "trial" else "返回"
	MingheUiStyle.style_button(back)
	back.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	back.position = Vector2((size.x - 360) / 2, size.y * 0.75)
	screen_host.add_child(back)
	back.pressed.connect(_on_stage_exit_requested)
	back.grab_focus()

func _show_local_charts() -> void:
	_run_pet_ready = false
	MenuAudioService.stop_preview()
	var screen := LOCAL_SCENE.instantiate()
	screen.library = _library; screen.jobs = _jobs
	screen.selected_song = _local_selection.get("song_id", "")
	screen.selected_chart = _local_selection.get("chart_id", "")
	_mount_screen(screen)
	screen.play_requested.connect(func(context: Dictionary):
		_local_selection = context.duplicate()
		AppRouter.navigate(&"external_loading", context))
	screen.back_requested.connect(func(): AppRouter.navigate(AppRouter.ROUTE_STAGE_SELECT))

func _show_external_loading(context: Dictionary) -> void:
	_run_context = context.duplicate(true)
	MenuAudioService.stop_preview()
	var control := Control.new()
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mount_screen(control)
	MingheUiStyle.add_backdrop(control)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 760
	center.add_child(column)
	_load_message = Label.new()
	_load_message.text = "正在加载谱面和音乐…"
	_load_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MingheUiStyle.style_body(_load_message, 28)
	column.add_child(_load_message)
	var cancel := Button.new()
	cancel.text = "结束试玩" if context.origin == "trial" else "取消并返回本地谱面"
	MingheUiStyle.style_button(cancel)
	cancel.pressed.connect(_on_stage_exit_requested)
	column.add_child(cancel)
	cancel.grab_focus()
	_load_request = _jobs.request(str(context.path), str(context.get("difficulty_id", "")))

func _external_loaded(id: int, result: Dictionary) -> void:
	if id != _load_request: return
	_load_request = -1
	if result.stage == null:
		var message := ChartProjectLoader.describe_issues(result.errors)
		_load_message.text = message
		ChartTrialLaunch.report(_run_context, "error", message)
		return
	AppRouter.navigate(AppRouter.ROUTE_STAGE, {"stage": result.stage}, false)

func _retry_external() -> void:
	_run_context.skip_intro = true
	AppRouter.navigate(&"external_loading", _run_context.duplicate(true), false)

func _start_countdown(stage_root: Node) -> void:
	InputEventBuffer.set_mode(InputEventBuffer.InputMode.DISABLED)
	var countdown := ChartReadyCountdown.new()
	stage_root.add_child(countdown)
	countdown.finished.connect(func():stage_root.start_level(bool(_run_context.get("skip_intro",false))))

func _add_trial_to_library() -> void:
	# 复用同一导入页面和更新确认；不自动改变本次临时试玩的成绩策略。
	var modal := LOCAL_SCENE.instantiate()
	modal.library = _library; modal.jobs = _jobs; modal.import_only = true
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	modal_host.add_child(layer)
	layer.add_child(modal)
	modal.close_requested.connect(func():
		layer.queue_free()
		if is_instance_valid(_current_screen):
			var pause := _current_screen.get_node_or_null("PauseLayer")
			if pause != null: pause._continue_button.grab_focus()
			elif _current_screen.has_method("configure_external"): _current_screen._retry.grab_focus())
	modal.import_path(str(_run_context.path))

func _unhandled_input(event: InputEvent) -> void:
	if AppRouter.current_route == &"external_loading" and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_stage_exit_requested()
