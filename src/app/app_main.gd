extends Control

## 应用层总入口。负责页面与弹窗的装卸，并把关卡结果送往存档和结算页。

## 标题页场景模板，进入应用或返回首页时实例化。
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


func _ready() -> void:
	# AppRouter 记录页面和返回历史；具体实例化哪个场景仍由这个宿主统一完成。
	AppRouter.route_requested.connect(_on_route_requested)
	AppRouter.clear_history()
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
	MenuAudioService.stop_preview()
	var screen := STAGE_SELECT_SCENE.instantiate()
	_mount_screen(screen)
	screen.stage_selected.connect(func(stage_id: String) -> void:
		AppRouter.navigate(AppRouter.ROUTE_LOADING, {"stage_id": stage_id})
	)
	screen.back_requested.connect(func() -> void: AppRouter.navigate(AppRouter.ROUTE_TITLE))
	screen.settings_requested.connect(func() -> void: _show_modal(SETTINGS_MODAL))
	screen.pets_requested.connect(func() -> void: _show_modal(PET_SELECT_MODAL))


func _show_loading(stage_id: String) -> void:
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
	if stage_root.has_method("configure_stage"):
		stage_root.call("configure_stage", stage)
	elif stage_root.has_method("start_stage"):
		stage_root.call("start_stage", stage)
	else:
		_show_error("StageRoot 缺少 configure_stage/start_stage 接口。")


func _show_result(stage: StageDefinition, result: Dictionary) -> void:
	var screen := RESULT_SCENE.instantiate()
	_mount_screen(screen)
	screen.present(stage, result)
	screen.retry_requested.connect(func(stage_id: String) -> void:
		AppRouter.navigate(AppRouter.ROUTE_LOADING, {"stage_id": stage_id}, false)
	)
	screen.stage_select_requested.connect(func() -> void:
		AppRouter.navigate(AppRouter.ROUTE_STAGE_SELECT, {}, false)
	)


func _on_stage_finished(result: Variant = {}) -> void:
	var result_dictionary := result as Dictionary if result is Dictionary else {}
	if not result_dictionary.has("cleared") and result_dictionary.has("success"):
		result_dictionary["cleared"] = bool(result_dictionary["success"])
	if not result_dictionary.has("full_combo"):
		result_dictionary["full_combo"] = bool(result_dictionary.get("fc", false))
	if not result_dictionary.has("all_perfect"):
		result_dictionary["all_perfect"] = bool(result_dictionary.get("ap", false))
	_apply_pet_result_modifier(result_dictionary)
	if _current_stage != null:
		SaveService.record_stage_result(_current_stage, result_dictionary)
	AppRouter.navigate(AppRouter.ROUTE_RESULT, {"stage": _current_stage, "result": result_dictionary}, false)


func _apply_pet_result_modifier(result: Dictionary) -> void:
	var pet_id := SaveService.equipped_pet_id()
	if pet_id.is_empty():
		return
	var pet := ContentCatalog.get_pet(pet_id)
	if pet == null:
		return
	var pet_state := SaveService.pet_state(pet_id)
	var effect_value := pet.advanced_effect_value if bool(pet_state.get("advanced", false)) else pet.base_effect_value
	# 随从加分故意放在判定结束后：装备与否都不能改变 Replay、FC/AP 或原始判定。
	if pet.effect_kind == PetDefinition.EffectKind.BONUS_SCORE:
		var raw_score := int(result.get("score", 0))
		var bonus := roundi(float(raw_score) * effect_value)
		result["raw_score_before_pet"] = raw_score
		result["pet_bonus"] = bonus
		result["score"] = raw_score + bonus
		result["equipped_pet_id"] = pet_id


func _on_stage_exit_requested() -> void:
	AppRouter.navigate(AppRouter.ROUTE_STAGE_SELECT, {}, false)


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
	var modal := scene.instantiate()
	modal_host.add_child(modal)
	# 平时 ModalHost 必须放过鼠标，关卡的左右鼠标点击才能进入 InputRouter；
	# 真正打开弹窗时才拦截鼠标，关闭后立刻恢复。键盘和手柄不受 mouse_filter 控制。
	modal_host.mouse_filter = Control.MOUSE_FILTER_STOP
	if modal.has_signal("close_requested"):
		modal.connect("close_requested", func() -> void:
			modal.queue_free()
			modal_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# 纯手柄操作时，弹窗关闭后把焦点还给打开弹窗前的按钮。
			if is_instance_valid(previous_focus) and previous_focus.is_visible_in_tree():
				previous_focus.grab_focus.call_deferred()
		)


func _mount_screen(screen: Node) -> void:
	_current_screen = screen
	screen_host.add_child(screen)


func _clear_screen() -> void:
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
