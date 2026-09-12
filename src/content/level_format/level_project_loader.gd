class_name LevelProjectLoader
extends RefCounted
## 工具预览与正式游玩统一装配入口。
static func load_stage(path: String, difficulty := "") -> Dictionary:
	var opened := LevelProjectIO.open_project(path)
	if not opened.error.is_empty(): return {"stage": null, "errors": [{"message": opened.error}]}
	return make_stage(opened.level, opened.directory, difficulty)

static func make_stage(level: Dictionary, directory: String, difficulty := "", decoded: Dictionary = {}, validate := true) -> Dictionary:
	var song_path := directory.path_join(str(level.get("song_path", "song/song.json")))
	var project := decoded if not decoded.is_empty() else ChartProjectLoader.read_project(song_path, difficulty, false, ChartSceneLibrary.shared().scene_ids())
	if not project.errors.is_empty(): return {"stage": null, "errors": project.errors}
	var issues := LevelFormat.issues(level,project.charts)
	var assets := LevelAssetLibrary.new(); assets.configure(directory,level.get("packs",[]))
	issues.append_array(assets.validate_level(level))
	# 草稿预览允许暂缺素材，问题列表仍显示关联；正式装入和导出继续检查完整依赖。
	if validate and not issues.is_empty():return {"stage":null,"errors":issues}
	var chart: SongChart = project.charts[0]
	var raw: Dictionary = chart.get_meta("json_source", {}).duplicate(true)
	raw["presentation"] = {"scene_id": level.scene_id, "use_scene_show": false}
	chart.set_meta("json_source", raw)
	var stage := ChartProjectLoader.make_stage(project.song, chart)
	if stage == null: return {"stage": null, "errors": [{"message": "关卡场景无法装配"}]}
	stage.stage_id = str(level.level_id) + ":" + chart.chart_id
	stage.display_name = str(level.title); stage.description = str(level.get("description", ""))
	stage.order_index = int(level.get("order_index", 0))
	stage.song_title = project.song.title; stage.song_artist = str(level.get("author", ""))
	stage.unlocked_by_default = bool(level.get("unlocked_by_default", true))
	stage.stage_show.level_data = level.show.duplicate(true)
	stage.stage_show.asset_directory = directory
	stage.stage_show.asset_packs = level.get("packs", []).duplicate(true)
	stage.stage_show.difficulty_id = chart.difficulty_id
	for data:Dictionary in level.show.get("legacy_cues",[]):
		var cue:=ShowCue.new();cue.event_id=str(data.id);cue.tick=int(data.tick);cue.duration_ticks=int(data.duration_ticks)
		cue.track=int(data.track);cue.cue_id=StringName(data.cue_id);cue.target_slot=StringName(data.target_slot);cue.parameters=_legacy_value(data.parameters)
		stage.stage_show.cues.append(cue)
	var rules_path := str(level.get("rule_path", "res://content/rules/default_gameplay_rules.tres"))
	stage.rule_set = load(rules_path) as GameplayRuleSet
	if stage.rule_set == null: return {"stage": null, "errors": [{"message": "规则预设不存在：" + rules_path}]}
	stage.chart = ChartPathAdapter.project(chart, stage.rule_set)
	stage.reward.reward_id = str(level.level_id)
	stage.reward.next_stage_id = str(level.get("next_stage_id", ""))
	stage.reward.fc_grants_base_pet = bool(level.get("fc_grants_base_pet", true))
	stage.reward.ap_grants_advanced_pet = bool(level.get("ap_grants_advanced_pet", true))
	var pet_path := str(level.get("pet_path", ""))
	if not pet_path.is_empty(): stage.reward.pet = load(pet_path) as PetDefinition
	stage.set_meta("level", level.duplicate(true))
	stage.set_meta("level_source_chart", chart)
	stage.cover = assets.resolve(str(level.get("cover", ""))) as Texture2D
	return {"stage": stage, "errors": assets.issues if validate else []}

static func _legacy_value(value:Variant) -> Variant:
	if value is Dictionary:
		if value.get("_type","")=="Vector2":return Vector2(float(value.x),float(value.y))
		if value.get("_type","")=="Color":return Color(str(value.html))
		var result:={}
		for key in value:result[key]=_legacy_value(value[key])
		return result
	if value is Array:return value.map(_legacy_value)
	return value
