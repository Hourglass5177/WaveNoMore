## 写谱器的内存工作文档。谱面与演出使用深拷贝，未保存编辑不会改到这两份源资源；
## 歌曲、主题、规则和奖励只供当前工具读取。
@tool
class_name MingheChartEditorDocument
extends RefCounted

## 文档任何可见内容变化后发出；reason 只用于区分刷新来源，不保存业务状态。
signal changed(reason: String)

## 普通 Tap、Hold 与双押所在的谱面数组名。
const TRACK_NOTES := "notes"
## 允许改变频率但不计分的调频场数组名。
const TRACK_TUNING_FIELDS := "tuning_fields"
## 生、死两钟独立调频滑条数组名。
const TRACK_TUNING_SLIDERS := "tuning_sliders"
## 动态素音凝现请求数组名。
const TRACK_SU_MANIFESTATIONS := "su_manifestations"
## 双钟疾振区域数组名。
const TRACK_RAPID := "rapid"
## 仅用于谱师导航的段落标记数组名。
const TRACK_SECTIONS := "sections"
## 与谱面并行的 StageShow 演出指令数组名。
const TRACK_SHOW := "show"

## 当前关卡入口资源；打开既有关卡时保留原引用，当前工具不直接编辑其元数据。
var stage_definition: Resource
## 当前歌曲定义，只供播放音频和读取首拍偏移。
var song_definition: Resource
## 当前关卡视觉主题，只传给正式预览，不在此工具中修改。
var visual_theme: Resource
## 当前判定规则，供校验和预览读取。
var rule_set: Resource
## 当前奖励定义，只随关卡快照传递。
var reward_definition: Resource
## 可编辑 SongChart 的深拷贝工作副本。
var chart: Resource
## 可编辑 StageShow 的深拷贝工作副本。
var stage_show: Resource

## 原 `stage_definition.tres` 路径；空字符串表示新建且从未保存。
var stage_path: String = ""
## 正式 `song_chart.tres` 目标路径；空字符串会触发首次保存流程。
var chart_path: String = ""
## 正式 `stage_show.tres` 目标路径；必须与 chart_path 成对提交。
var show_path: String = ""
## 最近一次正式保存的内容哈希，用当前哈希与它比较即可判断「未保存」。
var last_saved_signature: String = ""

## 新事件 ID 的递增尾号；打开文档时会从已有 ID 重新推算，避免碰撞。
var _id_counter: int = 1


func open_stage(stage: Resource, source_path: String = "") -> bool:
	if stage == null:
		return false
	# StageDefinition 可以只是目录中的轻量入口。先解析惰性路径，再取得编辑器拥有的工作副本。
	if stage.has_method("resolve_dependencies_sync"):
		if not bool(stage.call("resolve_dependencies_sync", ResourceLoader.CACHE_MODE_IGNORE)):
			return false
	# 关卡元数据保持原引用；谱面和演出在下方复制后才交给编辑器修改。
	stage_definition = stage
	stage_path = source_path if not source_path.is_empty() else stage.resource_path
	song_definition = stage.get("song")
	visual_theme = stage.get("visual_theme")
	rule_set = stage.get("rule_set")
	reward_definition = stage.get("reward")
	var source_chart: Resource = stage.get("chart")
	var source_show: Resource = stage.get("stage_show")
	chart_path = source_chart.resource_path if source_chart != null else ""
	show_path = source_show.resource_path if source_show != null else ""
	if chart_path.is_empty():
		chart_path = String(stage.get("chart_resource_path"))
	if show_path.is_empty():
		show_path = String(stage.get("stage_show_resource_path"))
	chart = _deep_copy_resource(source_chart)
	stage_show = _deep_copy_resource(source_show)
	if chart == null:
		chart = SongChart.new()
	if stage_show == null:
		stage_show = StageShow.new()
	_reseed_id_counter()
	last_saved_signature = content_signature()
	changed.emit("open")
	return true


func create_empty() -> void:
	# 新建时直接组成完整内存关卡；首次保存才拆成六个 .tres 文件。
	stage_definition = StageDefinition.new()
	song_definition = SongDefinition.new()
	visual_theme = StageVisualTheme.new()
	rule_set = GameplayRuleSet.new()
	reward_definition = RewardDefinition.new()
	chart = SongChart.new()
	stage_show = StageShow.new()
	stage_definition.set("stage_id", "new_stage")
	stage_definition.set("display_name", "新关卡")
	song_definition.set("song_id", "new_song")
	song_definition.set("title", "新歌曲")
	song_definition.set("fallback_duration_sec", 16.0)
	visual_theme.set("theme_id", "new_stage_graybox")
	reward_definition.set("reward_id", "new_stage_reward")
	chart.set("chart_id", "new_chart")
	chart.set("difficulty_id", "normal")
	chart.set("end_tick", 7680)
	var tempo := TempoEvent.new()
	tempo.tick = 0
	tempo.bpm = 120.0
	var typed_tempos: Array[TempoEvent] = [tempo]
	(chart as SongChart).tempo_events = typed_tempos
	var meter := MeterEvent.new()
	meter.tick = 0
	meter.numerator = 4
	meter.denominator = 4
	var typed_meters: Array[MeterEvent] = [meter]
	(chart as SongChart).meter_events = typed_meters
	stage_show.set("show_id", "new_show")
	stage_definition.set("song", song_definition)
	stage_definition.set("chart", chart)
	stage_definition.set("stage_show", stage_show)
	stage_definition.set("visual_theme", visual_theme)
	stage_definition.set("reward", reward_definition)
	stage_definition.set("rule_set", rule_set)
	stage_definition.set("rule_set_resource_path", "res://content/rules/default_gameplay_rules.tres")
	stage_path = ""
	chart_path = ""
	show_path = ""
	_id_counter = 1
	last_saved_signature = ""
	changed.emit("new")


func replace_working_copy(new_chart: Resource, new_show: Resource, reason: String) -> void:
	chart = _deep_copy_resource(new_chart)
	stage_show = _deep_copy_resource(new_show)
	_reseed_id_counter()
	changed.emit(reason)


func snapshot() -> Dictionary:
	# Undo 使用之后不会再修改的深拷贝快照，签名用于跳过没有实际变化的操作。
	return {
		"chart": _deep_copy_resource(chart),
		"stage_show": _deep_copy_resource(stage_show),
		"signature": content_signature(),
	}


func is_dirty() -> bool:
	return content_signature() != last_saved_signature


func mark_saved() -> void:
	last_saved_signature = content_signature()
	changed.emit("saved")


func next_id(prefix: String) -> String:
	var candidate := ""
	while candidate.is_empty() or find_event(candidate) != null:
		candidate = "%s_%08d" % [prefix, _id_counter]
		_id_counter += 1
	return candidate


func get_track_array(track: String) -> Array:
	# 工具轨道名称与 Resource 数组在此集中映射，其他 UI 不直接猜字段名。
	if chart == null or stage_show == null:
		return []
	match track:
		TRACK_NOTES:
			return chart.get("note_events")
		TRACK_TUNING_FIELDS:
			return chart.get("tuning_fields")
		TRACK_TUNING_SLIDERS:
			return chart.get("tuning_sliders")
		TRACK_SU_MANIFESTATIONS:
			return chart.get("su_manifestations")
		TRACK_RAPID:
			return chart.get("rapid_regions")
		TRACK_SECTIONS:
			return chart.get("sections")
		TRACK_SHOW:
			return stage_show.get("cues")
	return []


func set_track_array(track: String, values: Array) -> void:
	# Godot 的导出数组带元素类型，写回前必须过滤并重建对应强类型数组。
	match track:
		TRACK_NOTES:
			var typed_notes: Array[NoteEvent] = []
			for value in values:
				if value is NoteEvent:
					typed_notes.append(value)
			(chart as SongChart).note_events = typed_notes
		TRACK_TUNING_FIELDS:
			var typed_fields: Array[TuningFieldRegion] = []
			for value in values:
				if value is TuningFieldRegion:
					typed_fields.append(value)
			(chart as SongChart).tuning_fields = typed_fields
		TRACK_TUNING_SLIDERS:
			var typed_sliders: Array[TuningSliderEvent] = []
			for value in values:
				if value is TuningSliderEvent:
					typed_sliders.append(value)
			(chart as SongChart).tuning_sliders = typed_sliders
		TRACK_SU_MANIFESTATIONS:
			var typed_manifestations: Array[SuManifestationEvent] = []
			for value in values:
				if value is SuManifestationEvent:
					typed_manifestations.append(value)
			(chart as SongChart).su_manifestations = typed_manifestations
		TRACK_RAPID:
			var typed_rapid: Array[RapidRegion] = []
			for value in values:
				if value is RapidRegion:
					typed_rapid.append(value)
			(chart as SongChart).rapid_regions = typed_rapid
		TRACK_SECTIONS:
			var typed_sections: Array[SectionMarker] = []
			for value in values:
				if value is SectionMarker:
					typed_sections.append(value)
			(chart as SongChart).sections = typed_sections
		TRACK_SHOW:
			var typed_cues: Array[ShowCue] = []
			for value in values:
				if value is ShowCue:
					typed_cues.append(value)
			(stage_show as StageShow).cues = typed_cues


func all_tracks() -> PackedStringArray:
	return PackedStringArray([
		TRACK_NOTES,
		TRACK_TUNING_FIELDS,
		TRACK_TUNING_SLIDERS,
		TRACK_SU_MANIFESTATIONS,
		TRACK_RAPID,
		TRACK_SECTIONS,
		TRACK_SHOW,
	])


func all_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for track in all_tracks():
		for event in get_track_array(track):
			if event != null:
				result.append({"track": track, "event": event})
	return result


func find_event(event_id: String) -> Resource:
	for entry in all_events():
		var event: Resource = entry.event
		if String(event.get("event_id")) == event_id:
			return event
	return null


func find_track(event_id: String) -> String:
	for entry in all_events():
		if String(entry.event.get("event_id")) == event_id:
			return entry.track
	return ""


func add_event(track: String, event: Resource, reason: String = "add") -> void:
	var values := get_track_array(track).duplicate()
	values.append(event)
	set_track_array(track, values)
	sort_tracks()
	changed.emit(reason)


func remove_events(event_ids: PackedStringArray, reason: String = "delete") -> void:
	for track in all_tracks():
		var kept: Array = []
		for event in get_track_array(track):
			if event == null or not event_ids.has(String(event.get("event_id"))):
				kept.append(event)
		set_track_array(track, kept)
	sort_tracks()
	changed.emit(reason)


func sort_tracks() -> void:
	for track in all_tracks():
		var values := get_track_array(track).duplicate()
		values.sort_custom(_event_less)
		set_track_array(track, values)


func notify_mutated(reason: String) -> void:
	sort_tracks()
	if chart != null:
		chart.emit_changed()
	if stage_show != null:
		stage_show.emit_changed()
	changed.emit(reason)


func content_signature() -> String:
	# 递归序列化可存储字段后计算哈希；Resource 路径和对象地址不参与，深拷贝仍会得到同一签名。
	var root := {
		"chart": _resource_to_variant(chart),
		"show": _resource_to_variant(stage_show),
	}
	return JSON.stringify(root, "", true).sha256_text()


func _event_less(a: Resource, b: Resource) -> bool:
	var tick_a := int(a.get("tick"))
	var tick_b := int(b.get("tick"))
	if tick_a != tick_b:
		return tick_a < tick_b
	return String(a.get("event_id")) < String(b.get("event_id"))


func _deep_copy_resource(source: Resource) -> Resource:
	if source == null:
		return null
	return source.duplicate(true)


func _reseed_id_counter() -> void:
	_id_counter = 1
	for entry in all_events():
		var id := String(entry.event.get("event_id"))
		var suffix := id.get_slice("_", id.get_slice_count("_") - 1)
		if suffix.is_valid_int():
			_id_counter = maxi(_id_counter, suffix.to_int() + 1)


func _resource_to_variant(resource: Resource) -> Variant:
	# 只序列化真正落盘的属性，并排除路径、名称和脚本对象，保证同一内容得到稳定哈希。
	if resource == null:
		return null
	var result: Dictionary = {"__class": resource.get_class()}
	for property in resource.get_property_list():
		var usage := int(property.get("usage", 0))
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var name := StringName(property.get("name", &""))
		if name == &"resource_path" or name == &"resource_name" or name == &"script":
			continue
		result[String(name)] = _variant_to_serializable(resource.get(name))
	return result


func _variant_to_serializable(value: Variant) -> Variant:
	# 数组和字典递归展开；字典键排序后，插入顺序不同也不会误报成内容变化。
	if value is Resource:
		return _resource_to_variant(value)
	if value is Array:
		var output: Array = []
		for item in value:
			output.append(_variant_to_serializable(item))
		return output
	if value is Dictionary:
		var output_dict: Dictionary = {}
		var keys: Array = value.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
		for key in keys:
			output_dict[String(key)] = _variant_to_serializable(value[key])
		return output_dict
	if value is StringName:
		return String(value)
	if value is Vector2:
		return [value.x, value.y]
	if value is Rect2:
		return [value.position.x, value.position.y, value.size.x, value.size.y]
	if value is Color:
		return value.to_html(true)
	if value is Object:
		return value.resource_path if value is Resource else "<object>"
	return value
