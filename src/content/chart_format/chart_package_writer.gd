class_name ChartPackageWriter
extends RefCounted
## 只序列化传入快照；不保存工程、不改变资源元数据或编辑历史。
static func write(song: SongDefinition, charts: Array[SongChart], directory: String, path: String) -> String:
	var manifest := ChartJsonCodec.encode_song(song)
	var audio_path := str(manifest.get("audio", ""))
	if audio_path.is_empty() or not FileAccess.file_exists(directory.path_join(audio_path)):
		return "找不到项目音乐：" + audio_path
	var old_entries: Array = manifest.get("charts", [])
	manifest.charts = []
	var files := {}
	for chart in charts:
		var issues := ChartProjectLoader.check_chart(chart)
		if not issues.is_empty(): return ChartProjectLoader.describe_issues(issues)
		if not chart.difficulty_id.is_valid_filename(): return "难度标识不能用作文件名：" + chart.difficulty_id
		var relative := "charts/%s.json" % chart.difficulty_id
		if files.has(relative): return "难度标识重复：" + chart.difficulty_id
		var entry := {}
		for previous: Dictionary in old_entries:
			if previous.get("chart_id") == chart.chart_id: entry = previous.duplicate(true)
		entry.merge({"chart_id": chart.chart_id, "difficulty_id": chart.difficulty_id, "path": relative}, true)
		manifest.charts.append(entry)
		files[relative] = (JSON.stringify(ChartJsonCodec.encode_chart(chart), "  ", false) + "\n").to_utf8_buffer()
	if charts.is_empty(): return "没有可打包的难度"
	files["song.json"] = (JSON.stringify(manifest, "  ", false) + "\n").to_utf8_buffer()
	files[audio_path] = FileAccess.get_file_as_bytes(directory.path_join(audio_path))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var pack := ZIPPacker.new()
	if pack.open(path + ".tmp") != OK: return "无法创建谱面包：" + path
	for relative: String in files:
		var error := pack.start_file(relative)
		if error == OK: error = pack.write_file(files[relative])
		pack.close_file()
		if error != OK:
			pack.close()
			DirAccess.remove_absolute(path + ".tmp")
			return "打包失败：" + error_string(error)
	var close_error := pack.close()
	if close_error != OK: return "完成谱面包失败：" + error_string(close_error)
	var rename_error := DirAccess.rename_absolute(path + ".tmp", path)
	return "" if rename_error == OK else "写入谱面包失败：" + error_string(rename_error)
