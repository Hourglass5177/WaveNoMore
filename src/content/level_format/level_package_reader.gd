class_name LevelPackageReader
extends RefCounted
## 后台只展开包和解码歌曲；Godot 场景与素材包留到主线程装配。
static var expanded := {}
static var cache_mutex := Mutex.new()
static func read(path: String, difficulty: String, all_charts: bool, scene_ids: PackedStringArray) -> Dictionary:
	var level_path := path
	if path.get_extension().to_lower() == "zip":
		var zip := ZIPReader.new()
		if zip.open(path) != OK: return {"errors": [{"message": "无法打开文件：" + path}]}
		var is_level := zip.file_exists("level.json"); zip.close()
		if not is_level: return ChartProjectLoader.read_project(path,difficulty,all_charts,scene_ids)
		var revision := str(FileAccess.get_modified_time(path))
		cache_mutex.lock()
		var cached: Dictionary = expanded.get(path, {}).duplicate()
		cache_mutex.unlock()
		var folder: String = cached.get("folder", "") if cached.get("revision", "") == revision else ""
		if folder.is_empty():
			folder = "user://level_packages/session_%d/%s" % [OS.get_process_id(),LevelFormat.id("package")]
			var error := LevelProjectIO.unpack(path,folder)
			if not error.is_empty(): return {"errors": [{"message":error}]}
			cache_mutex.lock(); expanded[path] = {"folder":folder,"revision":revision}; cache_mutex.unlock()
		level_path = folder.path_join("level.json")
	elif LevelProjectIO.read_json(path).get("format","") != "minghe-level":
		return ChartProjectLoader.read_project(path,difficulty,all_charts,scene_ids)
	var opened := LevelProjectIO.open_project(level_path)
	if not opened.error.is_empty(): return {"errors":[{"message":opened.error}]}
	var result := ChartProjectLoader.read_project(opened.directory.path_join(str(opened.level.song_path)),difficulty,all_charts,scene_ids)
	if not result.errors.is_empty(): return result
	result.level = opened.level; result.level_directory = opened.directory
	result.metadata.song_id = str(opened.level.level_id)
	result.metadata.title = str(opened.level.title)
	result.metadata.artist = str(opened.level.get("author",""))
	result.metadata.level_id = str(opened.level.level_id)
	result.metadata.order_index = int(opened.level.get("order_index",0))
	result.metadata.description = str(opened.level.get("description", ""))
	result.metadata.unlocked_by_default = bool(opened.level.get("unlocked_by_default", true))
	for chart:Dictionary in result.metadata.charts: chart.level_id = str(opened.level.level_id)
	return result

static func finish(result: Dictionary, inspect_all: bool) -> Dictionary:
	if not result.has("level"):
		result=ChartProjectLoader.check_project_presentation(result)
		if not inspect_all:return {"stage":ChartProjectLoader.make_stage(result.song,result.charts[0]) if result.errors.is_empty() else null,"errors":result.errors}
		return result
	if inspect_all:
		result.errors.append_array(LevelFormat.issues(result.level,result.charts))
		var library:=LevelAssetLibrary.new();library.configure(result.level_directory,result.level.packs)
		result.errors.append_array(library.validate_level(result.level))
		var cover := library.resolve(str(result.level.get("cover", ""))) as Texture2D
		if cover != null: result.metadata.cover_image = cover.get_image()
		return result
	return LevelProjectLoader.make_stage(result.level,result.level_directory,result.charts[0].difficulty_id,result)
