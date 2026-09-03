class_name PauseOverlay
extends CanvasLayer

## 暂停覆盖层。始终保持处理能力，确保主场景暂停后按钮和恢复倒计时仍能工作。

## 玩家点击退出时触发，由上层应用切回选关页。
signal exit_requested

## 整个暂停界面根 Control 的路径；切换暂停状态时只需显隐这个节点。
@export var root_path: NodePath = ^"Root"
## 暂停标题和恢复倒计时 Label 的路径。
@export var title_path: NodePath = ^"Root/Panel/Layout/Title"
## 继续按钮路径；点击后请求三秒倒计时恢复。
@export var continue_button_path: NodePath = ^"Root/Panel/Layout/ContinueButton"
## 重试按钮路径；点击后重建当前关卡运行状态。
@export var retry_button_path: NodePath = ^"Root/Panel/Layout/RetryButton"
## 退出按钮路径；点击后终止关卡并发出 exit_requested。
@export var exit_button_path: NodePath = ^"Root/Panel/Layout/ExitButton"

# 绑定后的会话接收继续、重试和终止请求；其余字段缓存界面控件。
var _session: StageSession
# 暂停面板的根控件；统一控制整张面板的显示和鼠标拦截。
var _root: Control
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
	_root = get_node(root_path) as Control
	_title = get_node(title_path) as Label
	_continue_button = get_node(continue_button_path) as Button
	_retry_button = get_node(retry_button_path) as Button
	_exit_button = get_node(exit_button_path) as Button
	_continue_button.pressed.connect(_on_continue_pressed)
	_retry_button.pressed.connect(_on_retry_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)
	_root.visible = false


func bind(session: StageSession) -> void:
	_session = session
	if not session.state_changed.is_connected(_on_state_changed):
		session.state_changed.connect(_on_state_changed)
	if not session.resume_countdown_changed.is_connected(_on_resume_countdown_changed):
		session.resume_countdown_changed.connect(_on_resume_countdown_changed)


func _on_state_changed(_previous: int, current: int, _reason: StringName) -> void:
	var paused: bool = current == GameplayTypes.StageState.PAUSED
	_root.visible = paused
	if paused:
		_title.text = "冥河暂寂"
		_continue_button.disabled = false
		_continue_button.grab_focus()


func _on_resume_countdown_changed(seconds_remaining: float) -> void:
	if seconds_remaining <= 0.0:
		_title.text = "再响"
		return
	_title.text = "%d" % ceili(seconds_remaining)
	_continue_button.disabled = true


func _on_continue_pressed() -> void:
	if is_instance_valid(_session):
		_session.request_resume()


func _on_retry_pressed() -> void:
	if is_instance_valid(_session):
		_session.retry()


func _on_exit_pressed() -> void:
	if is_instance_valid(_session):
		_session.abort()
	exit_requested.emit()


func _unhandled_input(event: InputEvent) -> void:
	if _root.visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if is_instance_valid(_session):
			_session.request_resume()
