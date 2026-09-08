extends SceneTree
var failures := 0
var directory := "user://chart_studio/tests/local_" + str(Time.get_ticks_usec())
func _initialize() -> void: run.call_deferred()
func check(value: bool, description: String) -> void:
	print("PASS " if value else "FAIL ", description)
	if not value: failures += 1

func run() -> void:
	var doc := StudioDocument.new()
	check(StudioProjectIO.open_project("res://tests/editor/fixtures/tuning/song.json", doc).is_empty(), "打开五轨示例")
	var original := FileAccess.get_sha256(doc.directory.path_join("charts/normal.json"))
	doc.song.title = "中文 未保存试玩"
	doc.dirty = true
	var source := doc.directory
	var first_id := doc.chart().chart_id
	doc.add_difficulty("hard", true)
	var second_id := doc.chart().chart_id
	var history_before := str(doc._histories)
	var revision := doc.revision
	var zip := directory.path_join("多难度 包.zip")
	check(StudioProjectIO.export_zip(doc, zip).is_empty(), "从内存生成多难度包")
	check(doc.dirty and doc.revision == revision and str(doc._histories) == history_before and doc.directory == source, "打包不改未保存状态、目录和历史")
	check(FileAccess.get_sha256(source.path_join("charts/normal.json")) == original, "打包不写原工程")
	var inspected := ChartProjectLoader.inspect_package(zip)
	check(inspected.errors.is_empty() and inspected.charts.size() == 2, "检查全部难度和音乐")
	check(inspected.song.title == "中文 未保存试玩", "包中包含未保存修改")
	var future_zip := directory.path_join("future.zip")
	_rewrite(zip, future_zip, "charts/hard.json", true)
	var future := ChartProjectLoader.inspect_package(future_zip)
	check(not future.errors.is_empty() and ChartProjectLoader.describe_issues(future.errors).contains("hard"), "第一难度有效仍拒绝另一个难度的未知版本")
	var reader := ZIPReader.new(); reader.open(zip)
	var manifest: Dictionary = JSON.parse_string(reader.read_file("song.json").get_string_from_utf8()); reader.close()
	var missing_audio := directory.path_join("missing_audio.zip")
	_rewrite(zip, missing_audio, str(manifest.audio), false)
	check(not ChartProjectLoader.inspect_package(missing_audio).errors.is_empty(), "缺失音乐不产生可导入包")
	var lib := LocalChartLibrary.new()
	lib.directory = directory.path_join("库"); lib.open()
	check(lib.import_checked(zip, inspected.metadata).is_empty(), "导入原始 ZIP")
	var context := lib.context(doc.song.song_id, first_id)
	check(FileAccess.get_sha256(lib.directory.path_join(lib.data.songs[doc.song.song_id].charts[first_id].package)) == FileAccess.get_sha256(zip), "内部包逐字节保留")
	check(ChartProjectLoader.load_stage(context.path, context.difficulty_id).stage != null, "本地库可加载真实 Stage")
	var old_package: String = lib.data.songs[doc.song.song_id].charts[first_id].package
	var single := directory.path_join("单难度.zip")
	check(StudioProjectIO.package_snapshot(doc, single, PackedInt32Array([1])).is_empty(), "当前难度快照只打一个难度")
	var updated := ChartProjectLoader.inspect_package(single)
	check(updated.charts.size() == 1 and not lib.update_summary(updated.metadata).is_empty(), "重复导入给出更新摘要")
	check(lib.import_checked(single, updated.metadata).is_empty(), "更新单个难度")
	check(lib.data.songs[doc.song.song_id].charts.size() == 2 and lib.data.songs[doc.song.song_id].charts[first_id].package == old_package, "未涉及的难度继续引用旧包")
	DirAccess.remove_absolute(zip); DirAccess.remove_absolute(single)
	check(ChartProjectLoader.load_stage(lib.context(doc.song.song_id, second_id).path, "hard").stage != null, "删除导入源后仍能加载")
	check(lib.record_result({"song_id": doc.song.song_id, "chart_id": first_id}, {"content_hash": "a", "score": 20}).is_empty(), "保存独立成绩")
	lib.record_result({"song_id": doc.song.song_id, "chart_id": first_id}, {"content_hash": "b", "score": 30})
	check(lib.data.scores.size() == 2, "不同编译版本不混用成绩")
	check(lib.remove(doc.song.song_id, second_id).is_empty() and lib.data.songs[doc.song.song_id].charts.size() == 1, "按难度移除")
	check(DirAccess.get_files_at(lib.directory).size() == 2, "只留下被引用的包和索引")
	# 解码失败必须指出具体难度，不允许因为第一难度有效便接受整个包。
	doc.chart().note_events[0].duration_ticks = -100
	check(not StudioProjectIO.package_snapshot(doc, zip).is_empty(), "不可玩难度阻止打包")
	check(not ChartProjectLoader.inspect_package(directory.path_join("缺失.zip")).errors.is_empty(), "损坏或缺失包给出错误")
	print("LOCAL CHART TESTS: ", failures)
	quit(1 if failures else 0)

func _rewrite(source: String, target: String, changed_path: String, change_version: bool) -> void:
	var input := ZIPReader.new(); input.open(source)
	var output := ZIPPacker.new(); output.open(target)
	for name in input.get_files():
		if name == changed_path and not change_version: continue
		var bytes := input.read_file(name)
		if name == changed_path:
			var json: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
			json.format_version = 999
			bytes = JSON.stringify(json).to_utf8_buffer()
		output.start_file(name); output.write_file(bytes); output.close_file()
	output.close(); input.close()
