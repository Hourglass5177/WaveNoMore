## ArtLab 主界面：从美术清单选择真实运行时场景，并切换状态、画幅与遮挡条件做交付检查。
extends Control

## 当前用于检查的美术交付清单。正式素材接入后仍从同一清单读取。
const DEFAULT_MANIFEST := preload("res://content/visual/graybox_manifest.tres")

## 实际承载素材实例和辅助线的预览画布，由 `_ready()` 创建并一直复用。
var _canvas: MingheArtLabCanvas
## 约束预览画布宽高比的容器；切换 16:9、20:9、16:10 时只修改它。
var _preview_frame: AspectRatioContainer
## 界面底部的校验摘要标签，显示错误数、警告数和第一条问题。
var _report: Label
## 素材条目下拉框；索引与 `DEFAULT_MANIFEST.entries` 的顺序保持一致。
var _asset_option: OptionButton
## 状态下拉框；内容来自当前条目的 required_states，空时回退到 state_names。
var _state_option: OptionButton


func _ready() -> void:
	MingheUiStyle.add_backdrop(self)
	var root_column := VBoxContainer.new()
	root_column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_column.add_theme_constant_override("separation", 10)
	add_child(root_column)
	root_column.add_child(_build_toolbar())
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_column.add_child(center)
	_preview_frame = AspectRatioContainer.new()
	_preview_frame.ratio = 16.0 / 9.0
	_preview_frame.stretch_mode = AspectRatioContainer.STRETCH_FIT
	_preview_frame.custom_minimum_size = Vector2(960, 540)
	center.add_child(_preview_frame)
	_canvas = MingheArtLabCanvas.new()
	_canvas.custom_minimum_size = Vector2(960, 540)
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_frame.add_child(_canvas)
	_report = Label.new()
	_report.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	MingheUiStyle.style_body(_report, 17)
	root_column.add_child(_report)
	_populate_assets()
	_validate_manifest(true)


func select_entry_by_id(asset_id: String) -> bool:
	for index: int in DEFAULT_MANIFEST.entries.size():
		var entry := DEFAULT_MANIFEST.entries[index]
		if entry != null and entry.asset_id == asset_id:
			_asset_option.select(index)
			_on_asset_selected(index)
			return true
	return false


func get_art_lab_canvas() -> MingheArtLabCanvas:
	return _canvas


func _build_toolbar() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MingheUiStyle.panel_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var title := Label.new()
	title.text = "ArtLab"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", MingheUiStyle.BONE)
	row.add_child(title)
	_asset_option = _empty_option(230)
	_asset_option.tooltip_text = "从 VisualAssetManifest 选择并实例化实际 runtime_scene"
	_asset_option.item_selected.connect(_on_asset_selected)
	row.add_child(_asset_option)
	_state_option = _empty_option(175)
	_state_option.tooltip_text = "调用资产实际状态接口或角色 AnimationPlayer"
	_state_option.item_selected.connect(_on_state_selected)
	row.add_child(_state_option)
	row.add_child(_option(["Perfect", "Good", "Pass", "Miss"], _on_judgment, 0, 135))
	row.add_child(_option(["16:9", "20:9", "16:10"], _on_aspect, 0, 125))
	row.add_child(_option(["低画质", "中画质", "高画质"], _on_quality, 1, 135))
	row.add_child(_option(["低遮挡", "中遮挡", "高遮挡"], _on_pressure, 1, 135))
	var validate := Button.new()
	validate.text = "严格交付校验"
	validate.custom_minimum_size.x = 170
	validate.tooltip_text = "禁止 placeholder；出现占位资产时校验失败"
	MingheUiStyle.style_button(validate, true)
	validate.pressed.connect(func() -> void: _validate_manifest(false))
	row.add_child(validate)
	return panel


func _empty_option(width: float) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(width, 48)
	option.add_theme_font_size_override("font_size", 17)
	option.focus_mode = Control.FOCUS_ALL
	return option


func _option(items: Array[String], callback: Callable, selected: int, width: float) -> OptionButton:
	var option := _empty_option(width)
	for item: String in items:
		option.add_item(item)
	option.select(selected)
	option.item_selected.connect(callback)
	return option


func _populate_assets() -> void:
	_asset_option.clear()
	for entry in DEFAULT_MANIFEST.entries:
		if entry == null:
			continue
		_asset_option.add_item("%s · %s" % [entry.asset_id, entry.category])
	if _asset_option.item_count > 0:
		_asset_option.select(0)
		_on_asset_selected(0)


func _populate_states(entry) -> void:
	_state_option.clear()
	if entry == null:
		return
	var states: PackedStringArray = entry.required_states if not entry.required_states.is_empty() else entry.state_names
	for state_name: String in states:
		_state_option.add_item(state_name)
	if _state_option.item_count > 0:
		_state_option.select(0)


func _on_asset_selected(index: int) -> void:
	if index < 0 or index >= DEFAULT_MANIFEST.entries.size():
		return
	var entry := DEFAULT_MANIFEST.entries[index]
	_canvas.set_manifest_entry(entry)
	_populate_states(entry)
	if _state_option.item_count > 0:
		_on_state_selected(0)


func _on_state_selected(index: int) -> void:
	if _canvas == null or _canvas.get_manifest_entry() == null:
		return
	var states := _canvas.get_manifest_entry().required_states
	if states.is_empty():
		states = _canvas.get_manifest_entry().state_names
	if index >= 0 and index < states.size():
		_canvas.apply_state(StringName(states[index]))


func _on_judgment(index: int) -> void:
	_canvas.judgment = index


func _on_aspect(index: int) -> void:
	_preview_frame.ratio = [16.0 / 9.0, 20.0 / 9.0, 16.0 / 10.0][index]


func _on_quality(index: int) -> void:
	_canvas.quality_level = index


func _on_pressure(index: int) -> void:
	_canvas.background_pressure = index


func _validate_manifest(allow_placeholders: bool) -> void:
	# 日常预览允许灰盒占位；「严格交付校验」会把每个占位资源视为错误。
	var issues := ArtManifestValidator.validate(DEFAULT_MANIFEST, allow_placeholders)
	if issues.is_empty():
		_report.text = "Manifest 结构与 runtime_scene 实例校验通过。"
		_report.add_theme_color_override("font_color", Color("b8c795"))
		return
	var errors := 0
	var warnings := 0
	for issue: Dictionary in issues:
		if issue.get("severity") == "error":
			errors += 1
		else:
			warnings += 1
	_report.text = "Manifest：%d 项错误，%d 项警告。首项：%s" % [errors, warnings, issues[0].get("message", "")]
	_report.add_theme_color_override("font_color", Color("dc746a") if errors > 0 else Color("d1b476"))
