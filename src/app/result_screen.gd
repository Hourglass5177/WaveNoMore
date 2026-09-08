extends Control

## 关卡结算页。接收已经结算完毕的结果，只负责展示并提供重试、返回选关入口。

## 玩家选择重试时发出；`stage_id` 是要重新加载的关卡稳定 ID。
signal retry_requested(stage_id: String)
## 玩家选择离开结算页、返回选关页时发出。
signal stage_select_requested
signal add_local_requested
var _select: Button

## 显示“渡河已毕”或“魂火已熄”的结算标题。
var _title: Label
## 显示 FC/AP 标记和最终分数。
var _summary: Label
## 显示关卡名、各判定数量与剩余魂火。
var _detail: Label
## 重试按钮；需要 `_stage` 才能确定重试哪一关。
var _retry: Button
## 本次结算对应的关卡定义，在 `present()` 中注入。
var _stage: StageDefinition


func _ready() -> void:
	MingheUiStyle.add_backdrop(self)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(780, 720)
	panel.add_theme_stylebox_override("panel", MingheUiStyle.panel_style())
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 24)
	panel.add_child(column)
	_title = Label.new()
	MingheUiStyle.style_title(_title, 52)
	column.add_child(_title)
	_summary = Label.new()
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.add_theme_font_size_override("font_size", 34)
	_summary.add_theme_color_override("font_color", MingheUiStyle.SU)
	column.add_child(_summary)
	_detail = Label.new()
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MingheUiStyle.style_body(_detail, 22)
	column.add_child(_detail)
	_retry = Button.new()
	_retry.text = "再渡一次"
	MingheUiStyle.style_button(_retry, true)
	_retry.pressed.connect(func() -> void:
		if _stage != null:
			retry_requested.emit(_stage.stage_id)
	)
	column.add_child(_retry)
	var select := Button.new()
	_select = select
	select.text = "返回选关"
	MingheUiStyle.style_button(select)
	select.pressed.connect(func() -> void: stage_select_requested.emit())
	column.add_child(select)
	_retry.grab_focus.call_deferred()


func present(stage: StageDefinition, result: Dictionary) -> void:
	_stage = stage
	var cleared := bool(result.get("cleared", false))
	_title.text = "渡河已毕" if cleared else "魂火已熄"
	var mark := ""
	if bool(result.get("all_perfect", result.get("ap", false))):
		mark = "ALL PERFECT"
	elif bool(result.get("full_combo", result.get("fc", false))):
		mark = "FULL COMBO"
	_summary.text = "%s\n%d" % [mark, int(result.get("score", 0))]
	var counts: Dictionary = result.get("grade_counts", {})
	_detail.text = "%s\nPERFECT %d   GOOD %d   PASS %d   MISS %d\n魂火 %d" % [
		stage.display_name if stage != null else "未知渡口",
		int(counts.get("PERFECT", counts.get(0, 0))),
		int(counts.get("GOOD", counts.get(1, 0))),
		int(counts.get("PASS", counts.get(2, 0))),
		int(counts.get("MISS", counts.get(3, 0))),
		int(result.get("soul_fire", 0)),
	]
	if not str(result.get("pet_name", "")).is_empty():
		_detail.text += "\n%s%s  ·  随从加分 %d" % [result.pet_name, " · 进阶" if result.get("pet_advanced", false) else "", int(result.get("bonus_score", 0))]


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		stage_select_requested.emit()

func configure_external(temporary: bool) -> void:
	_select.text = "结束试玩" if temporary else "返回本地谱面"
	if temporary:
		var button := Button.new()
		button.text = "加入本地谱面"
		MingheUiStyle.style_button(button)
		_select.get_parent().add_child(button)
		button.pressed.connect(func(): add_local_requested.emit())

func show_notice(message: String) -> void:
	_detail.text += "\n" + message
