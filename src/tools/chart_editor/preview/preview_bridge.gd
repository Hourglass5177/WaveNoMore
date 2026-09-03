## 写谱器到正式 StageRoot 的桥。预览使用深拷贝快照，绝不把运行时状态写回正在编辑的资源。
@tool
class_name MingheChartPreviewBridge
extends RefCounted

## 成功创建预览节点后发出，同时返回其使用的不可回写关卡快照。
signal preview_ready(preview_node: Node, stage_snapshot: Resource)
## 找不到或无法创建正式关卡根节点时发出，reason 可直接显示给用户。
signal preview_unavailable(reason: String)

## 兼容当前工程中可能采用的 StageRoot 场景路径，按顺序找到第一项即停止。
const STAGE_SCENE_CANDIDATES := [
	"res://scenes/stage/stage_root.tscn",
	"res://scenes/stage/StageRoot.tscn",
	"res://scenes/stage/gameplay_stage.tscn",
]

## 测试可注入轻量工厂；正常运行留空并实例化正式 StageRoot。
var runtime_factory: Callable
## 预留的正式 ChartCompiler 注入点，供宿主和测试共享运行时服务。
var shared_compiler: Object
## 预留的正式 ChartValidator 注入点，与编译器一起传入预览协议。
var shared_validator: Object


func set_runtime_factory(factory: Callable) -> void:
	runtime_factory = factory


func set_shared_services(compiler: Object, validator: Object) -> void:
	shared_compiler = compiler
	shared_validator = validator


func build_stage_snapshot(document: MingheChartEditorDocument, seek_tick: int = 0) -> Resource:
	# 保留关卡身份和美术配置，只替换为当前未保存的 Chart/Show 工作副本。
	var snapshot: Resource
	if document.stage_definition != null:
		snapshot = document.stage_definition.duplicate(true)
	else:
		snapshot = StageDefinition.new()
	snapshot.set("song", _copy(document.song_definition))
	snapshot.set("chart", _build_preview_chart(document.chart, seek_tick))
	snapshot.set("stage_show", _build_preview_show(document.stage_show, seek_tick))
	snapshot.set("visual_theme", _copy(document.visual_theme))
	snapshot.set("reward", _copy(document.reward_definition))
	snapshot.set("rule_set", _copy(document.rule_set))
	snapshot.set_meta("preview_seek_tick", maxi(0, seek_tick))
	return snapshot


func create_preview(document: MingheChartEditorDocument, options: Dictionary = {}) -> Node:
	# 可注入 runtime_factory 供测试；正常使用时发现并实例化正式 StageRoot 场景。
	var seek_tick := maxi(0, int(options.get("seek_tick", 0)))
	var stage_snapshot := build_stage_snapshot(document, seek_tick)
	var preview_node: Node
	if runtime_factory.is_valid():
		preview_node = runtime_factory.call(stage_snapshot, options)
	else:
		var scene := _discover_stage_scene()
		if scene != null:
			preview_node = scene.instantiate()
	if preview_node == null:
		preview_unavailable.emit("正式 StageRoot 尚未可用；PreviewBridge 已保留同一 Resource snapshot 接口")
		return null
	if _has_property(preview_node, &"initial_stage"):
		preview_node.set("initial_stage", stage_snapshot)
		if _has_property(preview_node, &"auto_start_initial_stage"):
			preview_node.set("auto_start_initial_stage", bool(options.get("auto_start", true)))
		_seek_after_ready(preview_node, seek_tick)
	elif preview_node.is_inside_tree():
		_configure_preview_node(preview_node, stage_snapshot, options)
		_call_seek(preview_node, seek_tick)
	else:
		preview_node.ready.connect(
			func() -> void:
				_configure_preview_node(preview_node, stage_snapshot, options)
				_call_seek(preview_node, seek_tick),
			CONNECT_ONE_SHOT
		)
	preview_ready.emit(preview_node, stage_snapshot)
	return preview_node


func seek(preview_node: Node, tick: int) -> void:
	_call_seek(preview_node, tick)


func _call_seek(preview_node: Node, tick: int) -> void:
	if preview_node == null:
		return
	if preview_node.has_method("seek_tick"):
		preview_node.call("seek_tick", tick)
	elif preview_node.has_method("seek"):
		preview_node.call("seek", tick)


func _seek_after_ready(preview_node: Node, tick: int) -> void:
	if preview_node.is_inside_tree() and preview_node.is_node_ready():
		_call_seek(preview_node, tick)
		return
	preview_node.ready.connect(
		func() -> void: _call_seek(preview_node, tick),
		CONNECT_ONE_SHOT
	)


func _discover_stage_scene() -> PackedScene:
	for path in STAGE_SCENE_CANDIDATES:
		if ResourceLoader.exists(path):
			return load(path) as PackedScene
	return null


func _configure_preview_node(preview_node: Node, stage_snapshot: Resource, options: Dictionary) -> void:
	if not is_instance_valid(preview_node):
		return
	if preview_node.has_method("prepare_stage"):
		preview_node.call("prepare_stage", stage_snapshot, options)
	elif preview_node.has_method("load_stage"):
		preview_node.call("load_stage", stage_snapshot, bool(options.get("auto_start", true)))
	elif preview_node.has_method("configure_stage"):
		preview_node.call("configure_stage", stage_snapshot)
	elif preview_node.has_method("prepare"):
		preview_node.call("prepare", stage_snapshot)
	else:
		preview_node.set_meta("stage_snapshot", stage_snapshot)


func _has_property(target: Object, property_name: StringName) -> bool:
	for property in target.get_property_list():
		if property.get("name", &"") == property_name:
			return true
	return false


func _build_preview_chart(source: Resource, seek_tick: int) -> Resource:
	# 中途预览裁掉已经起手的机制，不尝试伪造 Hold 或调频的中间状态。
	if source == null:
		return SongChart.new()
	var chart := source.duplicate(true) as SongChart
	if seek_tick <= 0:
		return chart
	var notes: Array[NoteEvent] = []
	for note: NoteEvent in chart.note_events:
		if note.tick >= seek_tick:
			notes.append(note)
	chart.note_events = notes
	var fields: Array[TuningFieldRegion] = []
	var retained_field_ids: Dictionary = {}
	for field: TuningFieldRegion in chart.tuning_fields:
		# 从中段启动时不伪造已经进入的调频场，只保留尚未开始的完整场。
		if field.tick >= seek_tick:
			fields.append(field)
			retained_field_ids[field.event_id] = true
	chart.tuning_fields = fields
	var sliders: Array[TuningSliderEvent] = []
	var group_sides: Dictionary = {}
	for slider: TuningSliderEvent in chart.tuning_sliders:
		if slider.tick < seek_tick or not retained_field_ids.has(slider.field_id):
			continue
		sliders.append(slider)
		if not slider.group_id.is_empty():
			var sides: Dictionary = group_sides.get(slider.group_id, {})
			sides[slider.affinity] = true
			group_sides[slider.group_id] = sides
	chart.tuning_sliders = sliders
	var manifestations: Array[SuManifestationEvent] = []
	for manifestation: SuManifestationEvent in chart.su_manifestations:
		var sides: Dictionary = group_sides.get(manifestation.group_id, {})
		if manifestation.tick >= seek_tick and sides.has(GameplayTypes.Affinity.ZHU) and sides.has(GameplayTypes.Affinity.XUAN):
			manifestations.append(manifestation)
	chart.su_manifestations = manifestations
	var rapid: Array[RapidRegion] = []
	for region: RapidRegion in chart.rapid_regions:
		if region.tick >= seek_tick:
			rapid.append(region)
	chart.rapid_regions = rapid
	return chart


func _build_preview_show(source: Resource, seek_tick: int) -> Resource:
	if source == null:
		return StageShow.new()
	var show := source.duplicate(true) as StageShow
	if seek_tick <= 0:
		return show
	var cues: Array[ShowCue] = []
	for cue: ShowCue in show.cues:
		if cue.tick >= seek_tick:
			cues.append(cue)
	show.cues = cues
	return show


func _copy(source: Resource) -> Resource:
	return source.duplicate(true) if source != null else null
