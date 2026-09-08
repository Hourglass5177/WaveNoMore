class_name LocalChartLibrary
extends RefCounted
## 索引仅保存已检查的元信息；原包按字节保留，难度可分别引用不同版本的包。
var directory := "user://local_charts"
var data := {"version": 1, "songs": {}, "scores": {}}
var error := ""

func open() -> void:
	var path := directory.path_join("index.json")
	if not FileAccess.file_exists(path): return
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary or raw.get("version") != 1 or not raw.get("songs") is Dictionary:
		error = "本地谱面索引无法读取，原包仍保留在：" + ProjectSettings.globalize_path(directory)
		return
	data = raw

func update_summary(info: Dictionary) -> String:
	var previous: Dictionary = data.songs.get(info.song_id, {}).get("charts", {})
	var names: PackedStringArray = []
	for chart: Dictionary in info.charts:
		if previous.has(chart.chart_id): names.append(str(chart.name))
	return "将更新以下难度：%s。包中未包含的其他难度保留。" % "、".join(names) if not names.is_empty() else ""

func import_checked(source: String, info: Dictionary) -> String:
	if not error.is_empty(): return error
	if source.get_extension().to_lower() != "zip": return "加入本地谱面需要 ZIP，请先从写谱器导出谱面包。"
	DirAccess.make_dir_recursive_absolute(directory)
	var filename := "package_%s.zip" % Crypto.new().generate_random_bytes(12).hex_encode()
	var target := directory.path_join(filename)
	var copied := DirAccess.copy_absolute(source, target)
	if copied != OK: return "复制谱面包失败：" + error_string(copied)
	var next := data.duplicate(true)
	var song: Dictionary = next.songs.get(info.song_id, {"charts": {}})
	song.merge({"song_id": info.song_id, "title": info.title, "artist": info.artist}, true)
	for chart: Dictionary in info.charts:
		var entry := chart.duplicate(true)
		entry.package = filename
		song.charts[chart.chart_id] = entry
	next.songs[info.song_id] = song
	var message := _commit(next)
	if not message.is_empty(): DirAccess.remove_absolute(target)
	else: _remove_unused_packages()
	return message

func context(song_id: String, chart_id: String) -> Dictionary:
	var chart: Dictionary = data.songs.get(song_id, {}).get("charts", {}).get(chart_id, {})
	if chart.is_empty(): return {}
	return {"origin": "local", "song_id": song_id, "chart_id": chart_id, "difficulty_id": chart.difficulty_id, "path": directory.path_join(chart.package)}

func remove(song_id: String, chart_id: String) -> String:
	var next := data.duplicate(true)
	var song: Dictionary = next.songs.get(song_id, {})
	if song.is_empty(): return ""
	song.charts.erase(chart_id)
	if song.charts.is_empty(): next.songs.erase(song_id)
	var message := _commit(next)
	if message.is_empty(): _remove_unused_packages()
	return message

func record_result(context_data: Dictionary, result: Dictionary) -> String:
	var next := data.duplicate(true)
	# 复用正式编译内容标识；不同修订的最好成绩互不覆盖。
	var key := JSON.stringify([context_data.song_id, context_data.chart_id, result.get("content_hash", "")])
	var previous: Dictionary = next.scores.get(key, {})
	if int(result.get("score", 0)) >= int(previous.get("score", 0)): next.scores[key] = result.duplicate(true)
	return _commit(next)

func _commit(next: Dictionary) -> String:
	if not error.is_empty(): return error
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("index.json")
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return "无法保存本地谱面库：" + ProjectSettings.globalize_path(path)
	file.store_string(JSON.stringify(next, "  ", false))
	file.close()
	var result := DirAccess.rename_absolute(path + ".tmp", path)
	if result != OK: return "保存本地谱面库失败：" + error_string(result)
	data = next
	return ""

func _remove_unused_packages() -> void:
	var used := {}
	for song: Dictionary in data.songs.values():
		for chart: Dictionary in song.charts.values(): used[chart.package] = true
	# 仅处理本模块生成的内部包，不扫描或删除导入源。
	for name in DirAccess.get_files_at(directory):
		if name.begins_with("package_") and name.ends_with(".zip") and not used.has(name):
			DirAccess.remove_absolute(directory.path_join(name))
