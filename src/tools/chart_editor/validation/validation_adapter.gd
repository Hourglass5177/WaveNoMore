## 将正式 ChartValidator 的结果整理成写谱器问题列表，并补充 StageShow 的编辑期完整性检查。
@tool
class_name MingheChartValidationAdapter
extends RefCounted

## 兼容历史目录布局的候选路径；当前已有全局 ChartValidator 时不会使用这些后备项。
const VALIDATOR_CANDIDATES := [
	"res://src/content/chart_validator.gd",
	"res://src/content/validation/chart_validator.gd",
	"res://src/domain/chart/chart_validator.gd",
	"res://src/domain/chart/validation/chart_validator.gd",
]

## 外部注入的正式校验器；为空时直接调用工程的 ChartValidator。
var shared_validator: Object


func set_shared_validator(value: Object) -> void:
	shared_validator = value


func validate(document: MingheChartEditorDocument) -> Array[Dictionary]:
	var validator: Object = shared_validator
	if validator == null:
		var report: ValidationReport = ChartValidator.validate(document.chart, document.rule_set, -1)
		var shared_issues: Array[Dictionary] = _normalize_shared_result(report)
		if shared_issues.is_empty():
			shared_issues.append(_issue("info", "chart.valid", "共享 ChartValidator 检查通过", "", 0, ""))
		shared_issues.append_array(_stage_show_integrity_checks(document))
		return shared_issues
	if validator != null:
		var shared_result: Variant = _call_shared_validator(validator, document)
		var normalized: Array[Dictionary] = _normalize_shared_result(shared_result)
		if normalized.is_empty():
			normalized.append(_issue("info", "chart.valid", "共享 ChartValidator 检查通过", "", 0, ""))
		normalized.append_array(_stage_show_integrity_checks(document))
		return normalized
	return _editor_integrity_checks(document)


func _discover_validator() -> Object:
	for path in VALIDATOR_CANDIDATES:
		if ResourceLoader.exists(path):
			var script := load(path) as Script
			if script != null and script.can_instantiate():
				return script.new()
	return null


func _call_shared_validator(validator: Object, document: MingheChartEditorDocument) -> Variant:
	if validator.has_method("validate_document"):
		return validator.call("validate_document", document.chart, document.stage_show, document.visual_theme)
	if not validator.has_method("validate"):
		return null
	var argument_count := _method_argument_count(validator, "validate")
	match argument_count:
		1:
			return validator.call("validate", document.chart)
		2:
			return validator.call("validate", document.chart, document.rule_set)
		_:
			return validator.call("validate", document.chart, document.rule_set, -1)


func _method_argument_count(target: Object, method_name: String) -> int:
	for method in target.get_method_list():
		if String(method.get("name", "")) == method_name:
			return Array(method.get("args", [])).size()
	return 0


func _normalize_shared_result(result: Variant) -> Array[Dictionary]:
	# 兼容数组、字典和 ValidationReport，向 UI 统一输出可定位的 Dictionary。
	var source: Array = []
	if result is Array:
		source = result
	elif result is Dictionary:
		source = result.get("issues", [])
	elif result is Object and result.get("issues") != null:
		source = result.get("issues")
	var output: Array[Dictionary] = []
	for issue in source:
		if issue is Dictionary:
			output.append({
				"severity": _severity_name(issue.get("severity", "error")),
				"code": String(issue.get("code", "shared")),
				"message": String(issue.get("message", issue)),
				"event_id": String(issue.get("event_id", "")),
				"tick": int(issue.get("tick", 0)),
				"track": String(issue.get("track", issue.get("track_id", ""))),
			})
		elif issue is Object:
			var severity_value: Variant = issue.get("severity")
			output.append({
				"severity": _severity_name(severity_value),
				"code": String(issue.get("code")),
				"message": String(issue.get("message")),
				"event_id": String(issue.get("event_id")),
				"tick": int(issue.get("tick")),
				"track": String(issue.get("track")),
			})
	return output


func _severity_name(value: Variant) -> String:
	if value is int:
		match int(value):
			0: return "info"
			1: return "warning"
			_: return "error"
	return String(value).to_lower()


func _stage_show_integrity_checks(document: MingheChartEditorDocument) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var ids: Dictionary = {}
	for cue in document.get_track_array(MingheChartEditorDocument.TRACK_SHOW):
		if cue == null:
			issues.append(_issue("error", "show.null", "StageShow 含空 cue", "", 0, "show"))
			continue
		var event_id := String(cue.get("event_id"))
		var tick := int(cue.get("tick"))
		if event_id.is_empty():
			issues.append(_issue("error", "show.id_empty", "演出 cue 缺少稳定 ID", event_id, tick, "show"))
		elif ids.has(event_id):
			issues.append(_issue("error", "show.id_duplicate", "重复演出 cue ID：%s" % event_id, event_id, tick, "show"))
		ids[event_id] = true
		if String(cue.get("cue_id")).is_empty():
			issues.append(_issue("warning", "show.cue_empty", "演出事件尚未选择 cue_id", event_id, tick, "show"))
		if int(cue.get("duration_ticks")) < 0:
			issues.append(_issue("error", "show.duration", "演出 cue 持续时间不能为负", event_id, tick, "show"))
	return issues


func _editor_integrity_checks(document: MingheChartEditorDocument) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var ids: Dictionary = {}
	var field_ids: Dictionary = {}
	for field in document.get_track_array(MingheChartEditorDocument.TRACK_TUNING_FIELDS):
		if field != null:
			field_ids[String(field.get("event_id"))] = true
	var group_sides: Dictionary = {}
	for slider in document.get_track_array(MingheChartEditorDocument.TRACK_TUNING_SLIDERS):
		if slider == null or String(slider.get("group_id")).is_empty():
			continue
		var group_id := String(slider.get("group_id"))
		var sides: Dictionary = group_sides.get(group_id, {})
		sides[int(slider.get("affinity"))] = true
		group_sides[group_id] = sides
	for entry in document.all_events():
		var event: Resource = entry.event
		var track: String = entry.track
		var event_id := String(event.get("event_id"))
		var tick := int(event.get("tick"))
		if event_id.is_empty():
			issues.append(_issue("error", "empty_id", "事件缺少稳定 ID", event_id, tick, track))
		elif ids.has(event_id):
			issues.append(_issue("error", "duplicate_id", "重复事件 ID：%s" % event_id, event_id, tick, track))
		else:
			ids[event_id] = true
		var duration_value: Variant = event.get("duration_ticks") if _has_property(event, &"duration_ticks") else null
		if duration_value != null and int(duration_value) < 0:
			issues.append(_issue("error", "negative_duration", "事件持续时间不能为负", event_id, tick, track))
		if track == MingheChartEditorDocument.TRACK_TUNING_SLIDERS:
			var field_id := String(event.get("field_id"))
			if field_id.is_empty() or not field_ids.has(field_id):
				issues.append(_issue("error", "missing_tuning_field", "调频滑条没有指向有效调频场", event_id, tick, track))
			if int(event.get("traversal_ticks")) <= 0 or int(event.get("traversal_count")) <= 0:
				issues.append(_issue("error", "invalid_tuning_traversal", "调频滑条的单程时长和程数必须为正数", event_id, tick, track))
		if track == MingheChartEditorDocument.TRACK_SU_MANIFESTATIONS:
			var group_id := String(event.get("group_id"))
			var sides: Dictionary = group_sides.get(group_id, {})
			if group_id.is_empty() or not sides.has(GameplayTypes.Affinity.ZHU) or not sides.has(GameplayTypes.Affinity.XUAN):
				issues.append(_issue("error", "missing_paired_tuning_group", "素音凝现必须指向一组完整的生死双滑条", event_id, tick, track))
		if track == MingheChartEditorDocument.TRACK_SHOW and String(event.get("cue_id")).is_empty():
			issues.append(_issue("warning", "empty_cue", "演出事件尚未选择 cue_id", event_id, tick, track))
	if issues.is_empty():
		issues.append(_issue("info", "editor_integrity_ok", "编辑器结构检查通过；正式发布仍以共享 ChartValidator 为准", "", 0, ""))
	return issues


func _issue(severity: String, code: String, message: String, event_id: String, tick: int, track: String) -> Dictionary:
	return {
		"severity": severity,
		"code": code,
		"message": message,
		"event_id": event_id,
		"tick": tick,
		"track": track,
	}


func _has_property(target: Object, property_name: StringName) -> bool:
	for property in target.get_property_list():
		if property.get("name", &"") == property_name:
			return true
	return false
