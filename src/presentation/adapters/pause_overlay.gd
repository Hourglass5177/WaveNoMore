class_name PauseOverlay
extends CanvasLayer

const ArtScreen = preload("res://src/app/ui/art_screen.gd")

## 暂停覆盖层。始终保持处理能力，确保主场景暂停后按钮和恢复倒计时仍能工作。

## 玩家点击退出时触发，由上层应用切回选关页。
signal exit_requested
signal external_retry_requested
signal add_local_requested
var _external := false
var _transitioning := false
var _chrome_tween: Tween
var _retry_tween: Tween
var _chrome: Array[CanvasItem] = []

## 整个暂停界面根 Control 的路径；切换暂停状态时只需显隐这个节点。
@export var root_path: NodePath = ^"Root"
## 暂停标题和恢复倒计时 Label 的路径。
@export var title_path: NodePath = ^"Root/Design/Countdown"
## 继续按钮路径；点击后请求会话配置的倒计时恢复。
@export var continue_button_path: NodePath = ^"Root/Design/Continue"
## 重试按钮路径；点击后重建当前关卡运行状态。
@export var retry_button_path: NodePath = ^"Root/Design/Retry"
## 退出按钮路径；点击后终止关卡并发出 exit_requested。
@export var exit_button_path: NodePath = ^"Root/Design/Exit"

# 绑定后的会话接收继续、重试和终止请求；其余字段缓存界面控件。
var _session: StageSession
# 暂停面板的根控件；统一控制整张面板的显示和鼠标拦截。
var _root: ArtScreen
# 暂停面板标题文字节点。
var _title: Label
# “继续”按钮节点，按下后发出 continue_requested。
var _continue_button: Button
# “重试”按钮节点，按下后发出 retry_requested。
var _retry_button: Button
# “退出”按钮节点，按下后发出 exit_requested。
var _exit_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 40
	_root = get_node(root_path)
	_title = get_node(title_path) as Label
	_continue_button = get_node(continue_button_path) as Button
	_retry_button = get_node(retry_button_path) as Button
	_exit_button = get_node(exit_button_path) as Button
	_continue_button.pressed.connect(_on_continue_pressed)
	_retry_button.pressed.connect(_on_retry_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)
	%AddLocal.pressed.connect(func(): add_local_requested.emit())
	_chrome.assign([_root.get_node("Dim"), _root.get_node("Design/Panel"),
		_root.get_node("Design/Fire"), _continue_button, _retry_button, _exit_button, %AddLocal])
	_root.visible = false
	_update_focus_order()


func bind(session: StageSession) -> void:
	_session = session
	if not session.state_changed.is_connected(_on_state_changed):
		session.state_changed.connect(_on_state_changed)
	if not session.resume_countdown_changed.is_connected(_on_resume_countdown_changed):
		session.resume_countdown_changed.connect(_on_resume_countdown_changed)


func _on_state_changed(_previous: int, current: int, _reason: StringName) -> void:
	var paused: bool = current == GameplayTypes.StageState.PAUSED
	if not paused:
		_root.hide()
		if _retry_tween: _retry_tween.kill()
		_transitioning = false
		return
	if _chrome_tween: _chrome_tween.kill()
	for item in _chrome: item.modulate.a = 1.0
	_transitioning = false
	_title.text = ""
	%ClosedEye.show()
	%OpenEye.hide()
	_root.show()
	_root.fade_in()
	_root.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	for button in [_continue_button, _retry_button, _exit_button, %AddLocal]: button.disabled = false
	_continue_button.grab_focus()


## 面板与按钮先退场；眼睛独立留在玩法画面上，不再以面板作倒计时底板。
func _begin_eye_transition() -> void:
	_transitioning = true
	for button in [_continue_button, _retry_button, _exit_button, %AddLocal]: button.disabled = true
	%ClosedEye.hide()
	%OpenEye.show()
	_chrome_tween = create_tween().set_parallel(true)
	for item in _chrome:
		_chrome_tween.tween_property(item, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_SINE)


func _on_resume_countdown_changed(seconds_remaining: float) -> void:
	if seconds_remaining <= 0.0:
		_title.text = ""
		return
	if not _transitioning: _begin_eye_transition()
	# 默认三秒依次显示 3、2、1，每个数字占满一秒，再恢复玩法。
	_title.text = "%d" % ceili(seconds_remaining)
	# 用会话剩余时间收尾，不延长恢复时刻，也不让淡出覆盖已经开始的玩法。
	if seconds_remaining < 0.14:
		_root.modulate.a = smoothstep(0.0, 0.14, seconds_remaining)


func _on_continue_pressed() -> void:
	if _transitioning: return
	if is_instance_valid(_session):
		_session.request_resume()


func _on_retry_pressed() -> void:
	if _transitioning: return
	_begin_eye_transition()
	# 重玩前保持原会话暂停；眼内倒计时结束才重置，避免新一局在过渡背后推进。
	await _chrome_tween.finished
	var duration := _session.resume_countdown_sec if is_instance_valid(_session) else 0.0
	if duration > 0.0:
		_retry_tween = create_tween()
		_retry_tween.tween_method(_on_resume_countdown_changed, duration, 0.001, duration)
		await _retry_tween.finished
	_root.hide()
	if _external:
		external_retry_requested.emit()
	elif is_instance_valid(_session):
		_session.retry()


func _on_exit_pressed() -> void:
	if _transitioning: return
	_transitioning = true
	for button in [_continue_button, _retry_button, _exit_button, %AddLocal]: button.disabled = true
	await _root.fade_out()
	if not _external and is_instance_valid(_session):
		_session.abort()
	exit_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _root.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_continue_pressed()

func configure_external(temporary: bool) -> void:
	_external = true
	_exit_button.text = "结束试玩" if temporary else "返回本地谱面"
	%ExitArt.hide()
	%AddLocal.visible = temporary
	_update_focus_order()

func _update_focus_order() -> void:
	# 暂停主操作只在这一行循环；试玩附加按钮参与 Tab，方向下移可抵达。
	var row: Array[Button] = [_retry_button, _continue_button, _exit_button]
	for i in row.size():
		row[i].focus_neighbor_left = row[i].get_path_to(row[posmod(i - 1, row.size())])
		row[i].focus_neighbor_right = row[i].get_path_to(row[(i + 1) % row.size()])
		row[i].focus_neighbor_top = row[i].get_path()
		row[i].focus_neighbor_bottom = row[i].get_path_to(%AddLocal) if %AddLocal.visible else row[i].get_path()
	var order := row.duplicate()
	if %AddLocal.visible: order.append(%AddLocal)
	for i in order.size():
		order[i].focus_next = order[i].get_path_to(order[(i + 1) % order.size()])
		order[i].focus_previous = order[i].get_path_to(order[posmod(i - 1, order.size())])
	%AddLocal.focus_neighbor_top = %AddLocal.get_path_to(_continue_button)

func _input(event: InputEvent) -> void:
	if _root.visible: get_node("/root/UiInputHints").observe(event)
