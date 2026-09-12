class_name StudioProjectIO
extends RefCounted
## 项目路径均相对歌曲根目录；JSON 是游戏与工具共同的数据源。

static func open_project(path: String, doc: StudioDocument) -> String:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary: return "歌曲 JSON 无法解析"
	var decoded := ChartJsonCodec.decode_song(value)
	if decoded.song == null: return str(decoded.errors)
	var loaded: Array[SongChart] = []
	var errors: PackedStringArray = []
	for entry: Dictionary in value.get("charts", []):
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path.get_base_dir().path_join(entry.path)))
		if not raw is Dictionary: return "无法读取谱面 %s" % entry.path
		var result := ChartJsonCodec.decode_chart(raw)
		if result.chart == null: return str(result.errors)
		loaded.append(result.chart)
		errors.append_array(result.errors)
	if loaded.is_empty(): return "歌曲没有难度谱面"
	doc.song = decoded.song
	doc.charts = loaded
	doc.current = 0
	doc.directory = path.get_base_dir()
	doc.load_errors = errors
	doc.reset_history()
	doc.song.audio_stream = ChartJsonCodec.load_audio(doc.directory.path_join(str(value.get("audio", ""))))
	doc.dirty = false
	doc.changed.emit()
	return ""

static func write_json(path: String, data: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return "无法写入：" + path
	file.store_string(JSON.stringify(data, "  ", false) + "\n")
	file.close()
	if FileAccess.file_exists(path):
		var backup_error := DirAccess.copy_absolute(path, path + ".bak")
		if backup_error != OK: return "备份失败：" + path
	var error := DirAccess.rename_absolute(path + ".tmp", path)
	return "" if error == OK else "保存失败：" + error_string(error)

static func save_project(doc: StudioDocument, target: String = "") -> String:
	if target.is_empty(): target = doc.directory
	if target.is_empty(): return "请先选择项目目录"
	var song_data := ChartJsonCodec.encode_song(doc.song)
	var audio_path: String = song_data.get("audio", "")
	if not doc.directory.is_empty() and target != doc.directory and not audio_path.is_empty():
		DirAccess.make_dir_recursive_absolute(target.path_join(audio_path).get_base_dir())
		var error := DirAccess.copy_absolute(doc.directory.path_join(audio_path), target.path_join(audio_path))
		if error != OK: return "复制音频失败：" + error_string(error)
	if target != doc.directory and DirAccess.dir_exists_absolute(doc.directory.path_join("legacy")):
		var copy_error := copy_directory(doc.directory.path_join("legacy"), target.path_join("legacy"))
		if not copy_error.is_empty(): return copy_error
	var previous_entries: Array = song_data.get("charts", [])
	song_data.charts = []
	for chart in doc.charts:
		if not chart.difficulty_id.is_valid_filename(): return "难度标识不能用作文件名：" + chart.difficulty_id
		var relative := "charts/%s.json" % chart.difficulty_id
		var error := write_json(target.path_join(relative), ChartJsonCodec.encode_chart(chart))
		if not error.is_empty(): return error
		var entry := {}
		for old: Dictionary in previous_entries:
			if old.get("chart_id") == chart.chart_id: entry = old.duplicate(true); break
		entry.merge({"chart_id": chart.chart_id, "difficulty_id": chart.difficulty_id, "path": relative}, true)
		song_data.charts.append(entry)
	var error := write_json(target.path_join("song.json"), song_data)
	if error.is_empty():
		doc.song.set_meta("json_source", song_data)
		doc.directory = target
		doc.dirty = false
	return error

static func import_audio(path: String, doc: StudioDocument) -> String:
	if doc.directory.is_empty(): return "请先保存项目，再导入音频"
	var stream := ChartJsonCodec.load_audio(path)
	if stream == null: return "无法解码音频；请使用 PCM WAV、Ogg Vorbis 或 MP3"
	var relative := "audio/" + path.get_file()
	var dest := doc.directory.path_join(relative)
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	if path != dest and DirAccess.copy_absolute(path, dest) != OK: return "复制音频失败"
	doc.song.audio_stream = stream
	var data := ChartJsonCodec.encode_song(doc.song)
	data.audio = relative
	doc.song.set_meta("json_source", data)
	doc.chart().end_tick = maxi(1, floori(doc.tempo_map().us_to_tick(roundi(stream.get_length() * 1000000.0))))
	doc.mark_changed()
	return ""

static func export_zip(doc: StudioDocument, path: String, selected: PackedInt32Array = PackedInt32Array()) -> String:
	return package_snapshot(doc, path, selected)

static func package_snapshot(doc: StudioDocument, path: String, selected: PackedInt32Array = PackedInt32Array()) -> String:
	var charts: Array[SongChart] = []
	for i in doc.charts.size():
		if selected.is_empty() or selected.has(i): charts.append(doc.charts[i].duplicate(true))
	return ChartPackageWriter.write(doc.song.duplicate(true), charts, doc.directory, path)

static func copy_directory(source: String, target: String) -> String:
	DirAccess.make_dir_recursive_absolute(target)
	for filename in DirAccess.get_files_at(source):
		if DirAccess.copy_absolute(source.path_join(filename), target.path_join(filename)) != OK: return "复制失败：" + filename
	for directory in DirAccess.get_directories_at(source):
		var error := copy_directory(source.path_join(directory), target.path_join(directory))
		if not error.is_empty(): return error
	return ""

static func import_legacy(path: String, target: String, doc: StudioDocument) -> String:
	var stage := ResourceLoader.load(path) as StageDefinition
	if stage == null or not stage.resolve_dependencies_sync(): return "无法解析旧关卡及依赖"
	if FileAccess.file_exists(target.path_join("song.json")): return "旧谱导入需要新的项目目录"
	var source_chart := stage.chart.duplicate(true) as SongChart
	var omitted: Array = []
	for note in source_chart.note_events:
		if note.kind not in [GameplayTypes.NoteKind.TAP, GameplayTypes.NoteKind.HOLD] or note.affinity not in [GameplayTypes.Affinity.ZHU, GameplayTypes.Affinity.XUAN]: omitted.append(note.event_id)
	source_chart.note_events = source_chart.note_events.filter(func(n: NoteEvent) -> bool: return not omitted.has(n.event_id))
	var raw := ChartJsonCodec.encode_chart(source_chart)
	raw.merge({"song_id": stage.song.song_id, "difficulty_name": source_chart.difficulty_id, "mapper": "", "presentation": {"theme_id": "default"}}, true)
	if ChartSceneLibrary.shared().contains_source(stage):
		raw.presentation = {"scene_id": stage.stage_id, "use_scene_show": false}
	raw.timing.first_beat_offset_ms = stage.song.first_beat_offset_sec * 1000
	# 原始文件逐字节归档，连同路径依赖保留；游戏仅解释转换后的 JSON。
	var pending: Array[String] = [path]
	var visited := {}
	var archived := {}
	while not pending.is_empty():
		var source: String = pending.pop_back()
		if visited.has(source): continue
		visited[source] = true
		var relative := "legacy/res/" + source.trim_prefix("res://") if source.begins_with("res://") else "legacy/external/" + str(visited.size()) + "_" + source.get_file()
		var destination := target.path_join(relative)
		DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		if DirAccess.copy_absolute(source, destination) != OK: return "归档失败：" + source
		archived[source] = relative
		if source.get_extension() in ["tres", "tscn", "res", "scn"]:
			for dependency in ResourceLoader.get_dependencies(source): pending.append(dependency.split("::")[-1])
	doc.song = stage.song.duplicate(true)
	doc.song.set_meta("json_source", {"audio": "", "charts": []})
	doc.charts.assign([ChartJsonCodec.decode_chart(raw).chart])
	doc.current = 0
	doc.directory = target
	doc.reset_history()
	if stage.song.audio_stream != null and not stage.song.audio_stream.resource_path.is_empty():
		var audio_error := import_audio(stage.song.audio_stream.resource_path, doc)
		if not audio_error.is_empty(): return audio_error
		# 导入音乐不能覆盖旧谱原定的尾点。
		doc.chart().end_tick = source_chart.end_tick
	var notice := "只转换生死 Tap/Hold、时间和段落；旧调频、素音和演出数据原样归档，不转换为新版谱面事件。"
	if raw.presentation.has("scene_id"): notice += "已关联内置场景，场景演出默认关闭，可在预览区单独开启。"
	else: notice += "未匹配内置场景，使用旧版默认主题。"
	var report := {"source": path, "archived_files": archived, "omitted_note_ids": omitted, "notice": notice}
	var error := write_json(target.path_join("legacy/import-report.json"), report)
	if not error.is_empty(): return error
	doc.mark_changed()
	return save_project(doc)
