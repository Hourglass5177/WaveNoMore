class_name ChartProjectLoader
extends RefCounted
## 游戏和工具共用的接入点：JSON 项目直接装配正式领域资源，不另造导出音符。
static func make_stage(song: SongDefinition, chart: SongChart) -> StageDefinition:
	var stage := StageDefinition.new()
	stage.stage_id = chart.chart_id
	stage.display_name = song.title
	stage.song = song.duplicate(true)
	stage.chart = ChartPathAdapter.project(chart, load("res://content/rules/default_gameplay_rules.tres"))
	var raw: Dictionary = chart.get_meta("json_source", {})
	stage.song.first_beat_offset_sec = float(raw.get("timing", {}).get("first_beat_offset_ms", 0)) / 1000.0
	var presentation: Dictionary = raw.get("presentation", {})
	var library := ChartSceneLibrary.shared()
	var resolved := library.resolve(presentation)
	if not resolved.errors.is_empty(): return null
	stage.visual_theme = library.theme_copy(presentation)
	stage.background = resolved.background.duplicate(true) if resolved.background != null else null
	stage.stage_show = resolved.show.duplicate(true) if resolved.show != null else StageShow.new()
	stage.reward = RewardDefinition.new()
	stage.rule_set = load("res://content/rules/default_gameplay_rules.tres")
	return stage

## 同步入口完成表现检查；后台任务使用 read_project，交回主线程后再检查表现依赖。
static func inspect_package(path: String) -> Dictionary:
	return check_project_presentation(read_project(path, "", true, ChartSceneLibrary.shared().scene_ids()))

static func read_chart_data(path: String, difficulty_id: String = "") -> Dictionary:
	return check_project_presentation(read_project(path, difficulty_id, false, ChartSceneLibrary.shared().scene_ids()))

static func load_stage(path: String, difficulty_id: String = "") -> Dictionary:
	var project := read_chart_data(path, difficulty_id)
	if not project.errors.is_empty(): return {"stage": null, "errors": project.errors}
	return {"stage": make_stage(project.song, project.charts[0]), "errors": []}

static func check_project_presentation(project: Dictionary) -> Dictionary:
	if not project.errors.is_empty(): return project
	for chart: SongChart in project.charts:
		project.errors.append_array(presentation_issues(chart))
	return project

static func presentation_issues(chart: SongChart) -> Array:
	var issues: Array = ChartSceneLibrary.shared().resolve(chart.get_meta("json_source", {}).get("presentation", {})).errors.duplicate(true)
	for issue: Dictionary in issues: issue["difficulty_id"] = chart.difficulty_id
	return issues

## scene_ids 由任务启动时复制；此入口不访问共享场景库，也不加载表现素材。
static func read_project(path: String, difficulty: String, all_charts: bool, scene_ids: PackedStringArray) -> Dictionary:
	var pack := ZIPReader.new()
	var read: Callable
	if path.get_extension().to_lower() == "zip":
		if pack.open(path) != OK: return {"errors": [{"message": "无法打开谱面 ZIP：" + path}]}
		read = func(relative: String): return pack.read_file(relative) if pack.file_exists(relative) else PackedByteArray()
	else:
		read = func(relative: String): return FileAccess.get_file_as_bytes(path.get_base_dir().path_join(relative))
	var result := _decode_project(read, difficulty, all_charts, scene_ids)
	if path.get_extension().to_lower() == "zip": pack.close()
	return result

static func _decode_project(read: Callable, difficulty: String, all_charts: bool, scene_ids: PackedStringArray) -> Dictionary:
	var raw: Variant = JSON.parse_string((read.call("song.json") as PackedByteArray).get_string_from_utf8())
	if not raw is Dictionary: return {"errors": [{"message": "无法解析 song.json"}]}
	var decoded := ChartJsonCodec.decode_song(raw)
	if decoded.song == null: return {"errors": decoded.errors}
	if decoded.song.song_id.is_empty(): return {"errors": [{"message": "歌曲缺少 song_id"}]}
	for relative in [raw.get("audio", "")] + raw.get("charts", []).map(func(entry): return entry.path):
		if not relative is String or relative.is_empty() or relative.is_absolute_path() or ".." in relative.replace("\\", "/").split("/"):
			return {"errors": [{"message": "音乐和谱面必须使用包内相对路径：" + str(relative)}]}
	var charts: Array[SongChart] = []
	var metadata: Array[Dictionary] = []
	var errors: Array = []
	var ids := {}
	var difficulties := {}
	for entry: Dictionary in raw.get("charts", []):
		if not all_charts and not difficulty.is_empty() and entry.get("difficulty_id") != difficulty: continue
		var id := str(entry.get("difficulty_id", ""))
		var chart_raw: Variant = JSON.parse_string((read.call(str(entry.path)) as PackedByteArray).get_string_from_utf8())
		if not chart_raw is Dictionary:
			errors.append({"difficulty_id": id, "message": "无法解析：" + str(entry.path)})
			continue
		var result := ChartJsonCodec.decode_chart(chart_raw)
		if result.chart == null or not result.errors.is_empty():
			for error in result.errors: errors.append({"difficulty_id": id, "message": str(error)})
			continue
		var chart: SongChart = result.chart
		if chart.chart_id.is_empty() or chart.chart_id != str(entry.get("chart_id", "")) or chart.difficulty_id != id or ids.has(chart.chart_id) or difficulties.has(id):
			errors.append({"difficulty_id": id, "message": "歌曲清单与谱面标识不一致，或难度重复"})
		ids[chart.chart_id] = true
		difficulties[id] = true
		errors.append_array(check_chart(chart, scene_ids, false))
		charts.append(chart)
		metadata.append({"chart_id": chart.chart_id, "difficulty_id": id, "name": str(chart_raw.get("difficulty_name", id)), "mapper": str(chart_raw.get("mapper", ""))})
		if not all_charts: break
	if charts.is_empty() and errors.is_empty(): errors.append({"message": "找不到指定难度"})
	if not errors.is_empty(): return {"errors": errors}
	var audio_path := str(raw.get("audio", ""))
	decoded.song.audio_stream = ChartJsonCodec.audio_from_bytes(read.call(audio_path), audio_path.get_extension())
	if decoded.song.audio_stream == null: return {"errors": [{"message": "音乐缺失或无法解码：" + audio_path}]}
	return {"song": decoded.song, "charts": charts, "metadata": {"song_id": decoded.song.song_id, "title": decoded.song.title, "artist": decoded.song.artist, "charts": metadata}, "errors": []}

static func check_chart(chart: SongChart, scene_ids: PackedStringArray = PackedStringArray(), check_assets := true) -> Array:
	var issues: Array = []
	if check_assets:
		issues.append_array(presentation_issues(chart))
	else:
		var presentation: Dictionary = chart.get_meta("json_source", {}).get("presentation", {})
		if presentation.has("scene_id"):
			if not scene_ids.has(str(presentation.scene_id)): issues.append({"message": "找不到场景：" + str(presentation.scene_id)})
		else:
			var theme_id := str(presentation.get("theme_id", "default"))
			if not ChartSceneLibrary.LEGACY_THEMES.has(theme_id): issues.append({"message": "未知主题：" + theme_id})
	if not chart.get_meta("unknown_notes", []).is_empty(): issues.append({"message": "包含当前游戏无法解释的音符或行为"})
	var rules: GameplayRuleSet = load("res://content/rules/default_gameplay_rules.tres")
	issues.append_array(ChartPathAdapter.validate(chart, rules))
	if issues.is_empty():
		for issue in ChartValidator.validate(ChartPathAdapter.project(chart, rules), rules).issues:
			if issue.severity == ValidationIssue.Severity.ERROR: issues.append(issue.to_dictionary())
	for issue: Dictionary in issues: issue["difficulty_id"] = chart.difficulty_id
	return issues

static func describe_issues(issues) -> String:
	var lines: PackedStringArray = []
	for issue in issues:
		if issue is Dictionary:
			lines.append("%s %s：%s" % [issue.get("difficulty_id", ""), issue.get("event_id", ""), issue.get("message", "无法加载")])
		else: lines.append(str(issue))
	return "\n".join(lines)
