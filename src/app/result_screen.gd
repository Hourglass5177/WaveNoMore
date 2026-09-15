extends "res://src/app/ui/art_screen.gd"
## 仅展示已结算结果；奖励已由宿主保存，页面不重复授予或修改判定。
signal retry_requested(stage_id: String)
signal next_stage_requested(stage_id: String)
signal stage_select_requested
signal add_local_requested

@onready var _title: Label = %Title
@onready var _mark: Control = %Rating
@onready var _summary: Label = %Score
@onready var _retry: Button = %Retry
@onready var _select: Button = %Exit
var _stage: StageDefinition
var _next_id := ""
var _external := false

func _ready() -> void:
	super._ready()
	MingheUiStyle.add_backdrop(self)
	%Next.pressed.connect(func(): _leave(&"next"))
	_retry.pressed.connect(func(): _leave(&"retry"))
	_select.set_meta("ui_sound", &"cancel")
	_select.pressed.connect(func(): _leave(&"exit"))
	%AddLocal.pressed.connect(func():
		if not closing:
			%AddLocal.disabled = true
			add_local_requested.emit())

func present(stage: StageDefinition, result: Dictionary) -> void:
	_stage = stage
	var cleared := bool(result.get("cleared", false))
	_title.text = "复位成功" if cleared else "魂火已熄"
	%StageName.text = stage.display_name if stage != null else ""
	_summary.set_score(int(result.get("score", 0)))
	_mark.set_result(result)
	_mark.visible = _mark.texture != null
	var counts: Dictionary = result.get("grade_counts", {})
	var grades := PackedInt32Array()
	for i in 4:
		grades.append(int(counts.get(["PERFECT", "GOOD", "PASS", "MISS"][i], counts.get(i, 0))))
	for i in 4:
		get_node("%" + ["Perfect", "Good", "Pass", "Miss"][i]).text = "%s  %d" % [["臻", "良", "过", "失"][i], grades[i]]
	# 失败时尚未结算的音符不进入分母；百分比不能反推玄同、至臻。
	var total := grades[0] + grades[1] + grades[2] + grades[3]
	%HitRate.text = "%.2f%%" % (100.0 * (total-grades[3]) / total) if total > 0 else "—"
	%PerfectRate.text = "%.2f%%" % (100.0 * grades[0] / total) if total > 0 else "—"
	%Soul.text = "魂火  %d" % int(result.get("soul_fire", 0))
	var pet_name := str(result.get("pet_name", ""))
	%Bonus.text = "%s%s · 随从加分 %d" % [pet_name, " · 进阶" if result.get("pet_advanced", false) else "", int(result.get("bonus_score", 0))] if not pet_name.is_empty() else ""
	_next_id = ""
	%Reward.text = ""
	if stage != null and stage.reward != null:
		var reward := stage.reward
		if cleared: _next_id = reward.next_stage_id
		if reward.pet != null:
			var state: Dictionary = SaveService.pet_state(reward.pet.pet_id)
			var status := "已进阶" if state.get("advanced", false) else ("已收服" if state.get("owned", false) else "未收服")
			%Reward.text = reward.pet.display_name + status
	%Next.visible = not _external and not _next_id.is_empty()
	%Reward.visible = not _external and not %Reward.text.is_empty()
	_retry.disabled = stage == null
	_update_focus.call_deferred()

func configure_external(temporary: bool) -> void:
	_external = true
	%Next.hide()
	%Reward.hide()
	_select.get_node("Art").hide()
	for style in ["normal", "hover", "pressed"]:
		_select.remove_theme_stylebox_override(style)
	_select.text = "结束试玩" if temporary else "返回本地谱面"
	%AddLocal.visible = temporary
	_update_focus.call_deferred()

## 导入弹窗关闭后恢复原按钮；允许取消导入后再次打开。
func restore_external_focus() -> void:
	%AddLocal.disabled = false
	_update_focus()
	if %AddLocal.visible: %AddLocal.grab_focus()

func _update_focus() -> void:
	if closing: return
	var buttons: Array[Control] = []
	for button: Button in [%Next, _retry, _select, %AddLocal]:
		if button.visible and not button.disabled: buttons.append(button)
	for i in buttons.size():
		var button := buttons[i]
		var previous := button.get_path_to(buttons[posmod(i-1, buttons.size())])
		var following := button.get_path_to(buttons[(i+1) % buttons.size()])
		button.focus_neighbor_left = previous
		button.focus_previous = previous
		button.focus_neighbor_top = previous
		button.focus_neighbor_right = following
		button.focus_next = following
		button.focus_neighbor_bottom = following
	(%Next if %Next.visible else _select).grab_focus()

func _leave(action: StringName) -> void:
	if closing: return
	await fade_out()
	match action:
		&"retry": retry_requested.emit(_stage.stage_id)
		&"next": next_stage_requested.emit(_next_id)
		_: stage_select_requested.emit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		get_node("/root/MenuAudioService").play_ui(&"cancel")
		_leave(&"exit")

func show_notice(message: String) -> void:
	%Notice.text = message
	%Notice.visible = not message.is_empty()
	%AddLocal.disabled = false
