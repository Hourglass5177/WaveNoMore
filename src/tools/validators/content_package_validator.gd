## 关卡内容包校验器：跨 Song、Chart、Show、Theme、Reward 与 Catalog 检查引用是否闭合。
class_name ContentPackageValidator
extends RefCounted


static func validate_catalog(catalog: ContentCatalogData) -> Array[Dictionary]:
	# Catalog 层先检查关卡/随从身份，再逐关深入，并在最后核对跨关解锁和奖励引用。
	var issues: Array[Dictionary] = []
	if catalog == null:
		issues.append(_issue("error", "catalog", "ContentCatalogData 为空。"))
		return issues
	var stage_ids: Dictionary = {}
	var pet_ids: Dictionary = {}
	for pet: PetDefinition in catalog.pets:
		if pet == null:
			issues.append(_issue("error", "catalog.pets", "存在空随从引用。"))
			continue
		if pet.pet_id.is_empty() or pet_ids.has(pet.pet_id):
			issues.append(_issue("error", "pet:%s" % pet.pet_id, "随从 ID 为空或重复。"))
		pet_ids[pet.pet_id] = true
	for stage: StageDefinition in catalog.stages:
		if stage == null:
			issues.append(_issue("error", "catalog.stages", "存在空关卡引用。"))
			continue
		if stage.stage_id.is_empty() or stage_ids.has(stage.stage_id):
			issues.append(_issue("error", "stage:%s" % stage.stage_id, "关卡 ID 为空或重复。"))
		stage_ids[stage.stage_id] = true
		issues.append_array(validate_stage(stage))
	for stage: StageDefinition in catalog.stages:
		if stage != null and stage.reward != null and not stage.reward.next_stage_id.is_empty() and not stage_ids.has(stage.reward.next_stage_id):
			issues.append(_issue("error", "stage:%s.reward" % stage.stage_id, "next_stage_id 不存在：%s" % stage.reward.next_stage_id))
		if stage != null and stage.reward != null and stage.reward.pet != null and not pet_ids.has(stage.reward.pet.pet_id):
			issues.append(_issue("error", "stage:%s.reward" % stage.stage_id, "奖励随从未登记到目录：%s" % stage.reward.pet.pet_id))
	return issues


## 谱面内部规则交给 ChartValidator；这里补查资源路径、歌曲时长、奖励和演出边界。
static func validate_stage(stage: StageDefinition) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var prefix := "stage:%s" % stage.stage_id
	_validate_dependency_paths(stage, prefix, issues)
	if stage.song == null:
		issues.append(_issue("error", prefix, "缺少 SongDefinition。"))
	else:
		if stage.song.song_id.strip_edges().is_empty():
			issues.append(_issue("error", prefix + ".song", "song_id 不能为空。"))
		if stage.song.title.strip_edges().is_empty():
			issues.append(_issue("error", prefix + ".song", "歌曲标题不能为空。"))
		if stage.song.audio_stream == null:
			issues.append(_issue("warning", prefix + ".song", "缺少发行 BGM；运行时只能使用 Graybox 节拍。"))
		if not stage.song_title.is_empty() and stage.song_title != stage.song.title:
			issues.append(_issue("warning", prefix + ".song", "选关标题与 SongDefinition.title 不一致。"))
		if not stage.song_artist.is_empty() and stage.song_artist != stage.song.artist:
			issues.append(_issue("warning", prefix + ".song", "选关作者与 SongDefinition.artist 不一致。"))
	if stage.chart == null:
		issues.append(_issue("error", prefix, "缺少 SongChart。"))
	if stage.stage_show == null:
		issues.append(_issue("error", prefix, "缺少 StageShow。"))
	elif stage.stage_show.show_id.strip_edges().is_empty():
		issues.append(_issue("error", prefix + ".show", "show_id 不能为空。"))
	if stage.visual_theme == null:
		issues.append(_issue("error", prefix, "缺少 StageVisualTheme。"))
	elif stage.visual_theme.theme_id.strip_edges().is_empty():
		issues.append(_issue("error", prefix + ".theme", "theme_id 不能为空。"))
	if stage.reward == null:
		issues.append(_issue("error", prefix, "缺少 RewardDefinition。"))
	elif stage.reward.reward_id.strip_edges().is_empty():
		issues.append(_issue("error", prefix + ".reward", "reward_id 不能为空。"))
	if stage.rule_set == null:
		issues.append(_issue("error", prefix, "缺少 GameplayRuleSet。"))
	if stage.chart != null and stage.rule_set != null:
		var song_duration_us := _authored_song_duration_us(stage.song)
		var report := ChartValidator.validate(stage.chart, stage.rule_set, song_duration_us)
		for chart_issue: Dictionary in report.to_array():
			var severity := "error" if int(chart_issue.get("severity", 0)) >= 2 else "warning"
			issues.append(_issue(severity, "%s.chart.%s" % [prefix, chart_issue.get("track", "")], str(chart_issue.get("message", ""))))
		var compile_result := ChartCompiler.compile(stage.chart, stage.rule_set, song_duration_us)
		if not bool(compile_result.get("ok", false)):
			issues.append(_issue("error", prefix + ".chart", "谱面无法编译。"))
	if stage.stage_show != null:
		var chart_end_tick := stage.chart.end_tick if stage.chart != null else -1
		issues.append_array(_validate_show(stage.stage_show, prefix + ".show", chart_end_tick))
	return issues


static func _validate_show(show: StageShow, location: String, chart_end_tick: int) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	if show.schema_version != 1:
		issues.append(_issue("error", location, "不支持的 StageShow schema_version：%d" % show.schema_version))
	var ids: Dictionary = {}
	var previous_tick := -2147483648
	for cue: ShowCue in show.cues:
		if cue == null:
			issues.append(_issue("error", location, "存在空演出 cue。"))
			continue
		if cue.event_id.is_empty() or ids.has(cue.event_id):
			issues.append(_issue("error", location, "演出 cue ID 为空或重复：%s" % cue.event_id))
		ids[cue.event_id] = true
		if cue.tick < previous_tick:
			issues.append(_issue("error", location, "演出 cue 未按 tick 排序：%s" % cue.event_id))
		previous_tick = cue.tick
		if cue.duration_ticks < 0:
			issues.append(_issue("error", location, "duration_ticks 不能为负数：%s" % cue.event_id))
		if chart_end_tick >= 0 and cue.tick + maxi(0, cue.duration_ticks) > chart_end_tick:
			issues.append(_issue("error", location, "演出 cue 超出谱面结尾：%s" % cue.event_id))
		if cue.cue_id.is_empty():
			issues.append(_issue("error", location, "cue_id 不能为空：%s" % cue.event_id))
	return issues


static func _validate_dependency_paths(stage: StageDefinition, location: String, issues: Array[Dictionary]) -> void:
	# 即使依赖已加载到内存，正式内容仍必须保留可独立重载的资源路径。
	var paths := {
		"song": stage.song_resource_path,
		"chart": stage.chart_resource_path,
		"show": stage.stage_show_resource_path,
		"theme": stage.visual_theme_resource_path,
		"reward": stage.reward_resource_path,
		"rules": stage.rule_set_resource_path,
	}
	for slot: String in paths:
		var path := str(paths[slot])
		if path.is_empty():
			issues.append(_issue("error", "%s.%s" % [location, slot], "关卡包必须声明独立资源路径。"))
		elif not ResourceLoader.exists(path):
			issues.append(_issue("error", "%s.%s" % [location, slot], "资源路径不存在：%s" % path))


static func _authored_song_duration_us(song: SongDefinition) -> int:
	if song == null:
		return -1
	var audio_duration_sec := song.fallback_duration_sec
	if song.audio_stream != null and song.audio_stream.get_length() > 0.0:
		audio_duration_sec = song.audio_stream.get_length()
	# 谱面 tick 0 位于音频的 first_beat_offset_sec：负值增加前奏空间，正值会消耗可写谱时长。
	return maxi(0, int(round((audio_duration_sec - song.first_beat_offset_sec) * 1_000_000.0)))


static func _issue(severity: String, location: String, message: String) -> Dictionary:
	return {"severity": severity, "location": location, "message": message}
