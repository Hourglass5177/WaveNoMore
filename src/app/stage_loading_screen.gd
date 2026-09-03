extends Control

## 关卡异步加载页。先异步加载 StageDefinition，再为歌曲、谱面、演出、主题、奖励和规则
## 发起后台加载请求，并逐帧查询进度。

## 关卡定义及其全部依赖加载完毕后发出，可安全进入 StageRoot。
signal stage_ready(stage: StageDefinition)
## 玩家主动取消加载时发出。
signal load_cancelled
## 加载无法继续时发出；`message` 是可直接显示给玩家的错误说明。
signal load_failed(message: String)

## 显示两阶段异步加载总进度，范围为 0～100。
var _progress: ProgressBar
## 显示当前加载阶段或错误原因。
var _status: Label
## 当前 StageDefinition 的 `res://` 资源路径。
var _stage_path := ""
## 是否仍有加载请求需要在 `_process()` 中轮询。
var _request_active := false
## 当前加载阶段：`idle`、`stage`、`dependencies`、`done`、`cancelled` 或 `failed`。
var _phase: StringName = &"idle"
## 第一阶段加载出的关卡定义；第二阶段会把各依赖资源填入其中。
var _stage: StageDefinition
## 第二阶段的请求表。每项保存依赖槽位名 `slot` 与资源路径 `path`。
var _dependency_requests: Array[Dictionary] = []


func _ready() -> void:
	MingheUiStyle.add_backdrop(self)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 340)
	panel.add_theme_stylebox_override("panel", MingheUiStyle.panel_style())
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 28)
	panel.add_child(column)
	_status = Label.new()
	_status.text = "沿冥河而下……"
	MingheUiStyle.style_title(_status, 35)
	column.add_child(_status)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(600, 24)
	_progress.show_percentage = false
	column.add_child(_progress)
	var cancel := Button.new()
	cancel.text = "取消"
	MingheUiStyle.style_button(cancel)
	cancel.pressed.connect(_cancel)
	column.add_child(cancel)
	cancel.grab_focus.call_deferred()
	set_process(false)


func begin(stage_id: String) -> void:
	_stage_path = ContentCatalog.get_stage_path(stage_id)
	if _stage_path.is_empty():
		_fail("关卡不存在：%s" % stage_id)
		return
	# 导出后 .tres 可能被重映射成二进制资源，脚本类名不再是可靠的加载器提示。
	# 因此先按普通 Resource 加载，再用 as 和 assign_dependency 检查真实类型。
	var error := ResourceLoader.load_threaded_request(_stage_path, "Resource", false)
	if error != OK:
		_fail("无法请求关卡资源：%s" % error_string(error))
		return
	_request_active = true
	_phase = &"stage"
	_progress.value = 0.0
	set_process(true)


func _process(_delta: float) -> void:
	if not _request_active:
		return
	if _phase == &"stage":
		_poll_stage_definition()
	elif _phase == &"dependencies":
		_poll_dependencies()


func _poll_stage_definition() -> void:
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(_stage_path, progress)
	if not progress.is_empty():
		_progress.value = float(progress[0]) * 15.0
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			_stage = ResourceLoader.load_threaded_get(_stage_path) as StageDefinition
			if _stage == null:
				_fail("关卡资源类型不正确。")
			else:
				_begin_dependency_requests()
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_fail("关卡索引异步加载失败。")


func _begin_dependency_requests() -> void:
	_dependency_requests.clear()
	var paths := _stage.dependency_paths()
	var keys: Array = paths.keys()
	keys.sort()
	for slot: String in keys:
		var path := str(paths[slot])
		var error := ResourceLoader.load_threaded_request(path, "Resource", true)
		if error != OK:
			_fail("无法请求关卡组件 %s：%s" % [slot, error_string(error)])
			return
		_dependency_requests.append({"slot": slot, "path": path})
	if _dependency_requests.is_empty():
		if _stage.dependencies_resolved():
			_complete()
		else:
			_fail("关卡没有提供完整组件或资源路径。")
		return
	_phase = &"dependencies"
	_status.text = "正在唤醒歌曲、谱面与演出……"


func _poll_dependencies() -> void:
	var total_progress := 0.0
	var all_loaded := true
	for request: Dictionary in _dependency_requests:
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(str(request["path"]), progress)
		if status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
			_fail("关卡组件加载失败：%s" % request["slot"])
			return
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			all_loaded = false
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			total_progress += 1.0
		elif not progress.is_empty():
			total_progress += float(progress[0])
	_progress.value = 15.0 + 85.0 * total_progress / float(maxi(_dependency_requests.size(), 1))
	if not all_loaded:
		return
	for request: Dictionary in _dependency_requests:
		var resource := ResourceLoader.load_threaded_get(str(request["path"]))
		if resource == null or not _stage.assign_dependency(str(request["slot"]), resource):
			_fail("关卡组件类型不匹配：%s" % request["slot"])
			return
	if not _stage.dependencies_resolved():
		_fail("关卡组件未完整解析。")
		return
	_complete()


func _complete() -> void:
	_request_active = false
	_phase = &"done"
	_progress.value = 100.0
	set_process(false)
	stage_ready.emit(_stage)


func _cancel() -> void:
	_request_active = false
	_phase = &"cancelled"
	set_process(false)
	load_cancelled.emit()


func _fail(message: String) -> void:
	_request_active = false
	_phase = &"failed"
	set_process(false)
	_status.text = message
	load_failed.emit(message)


func _unhandled_input(event: InputEvent) -> void:
	# 加载失败后也允许按 B / Esc 返回，避免手柄只能改用 A 去点“取消”。
	if _phase != &"done" and _phase != &"cancelled" and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_cancel()
