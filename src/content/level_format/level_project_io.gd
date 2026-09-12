class_name LevelProjectIO
extends RefCounted
## 制作目录保留 workspace.json；运行 ZIP 只包含关卡声明的依赖。
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return raw if raw is Dictionary else {}

static func write_json(path: String, data: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return "无法写入：" + path
	file.store_string(JSON.stringify(data, "  ", false) + "\n")
	file.close()
	if FileAccess.file_exists(path):
		if DirAccess.copy_absolute(path, path + ".bak") != OK: return "备份失败：" + path
	var error := DirAccess.rename_absolute(path + ".tmp", path)
	return "" if error == OK else "保存失败：" + error_string(error)

static func open_project(path: String) -> Dictionary:
	var root := path.get_base_dir()
	var level := read_json(path)
	if level.get("format", "") != "minghe-level" or int(level.get("format_version", 0)) != LevelFormat.VERSION:
		return {"error": "无法读取关卡文档或版本不兼容"}
	level["show"] = read_json(root.path_join(str(level.get("show_path", "show.json"))))
	if level.show.get("format", "") != "minghe-show": return {"error": "演出文档缺失或无法解析"}
	for track:Dictionary in level.show.get("tracks",[]):track.keys.sort_custom(func(a,b):return int(a.time_us)<int(b.time_us))
	return {"error": "", "level": level, "directory": root, "workspace": read_json(root.path_join("workspace.json"))}

static func save(level: Dictionary, root: String, workspace: Dictionary = {}) -> String:
	var metadata := level.duplicate(true)
	metadata.erase("show"); metadata["show_path"] = "show.json"
	var error := write_json(root.path_join("show.json"), level.show)
	if error.is_empty(): error = write_json(root.path_join("level.json"), metadata)
	if error.is_empty() and not workspace.is_empty(): error = write_json(root.path_join("workspace.json"), workspace)
	return error

static func import_song(source: String, root: String) -> String:
	# 谱面逐字节复制，刷新仍按音符 ID 关联；关卡工具不会重写谱师的源文件。
	var manifest := read_json(source)
	if manifest.is_empty(): return "无法读取歌曲清单"
	var files: Array = ["song.json", manifest.get("audio", "")]
	for chart: Dictionary in manifest.get("charts", []): files.append(chart.path)
	for relative: String in files:
		if not _relative(relative): return "歌曲依赖必须使用目录内相对路径：" + relative
		var origin := source if relative == "song.json" else source.get_base_dir().path_join(relative)
		var destination := root.path_join("song").path_join(relative)
		DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		if origin.simplify_path() != destination.simplify_path() and DirAccess.copy_absolute(origin, destination) != OK: return "复制失败：" + origin
	return ""

static func import_file(source: String, root: String, folder := "assets") -> Dictionary:
	var relative := folder.path_join(source.get_file())
	var target := root.path_join(relative)
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if source.simplify_path() != target.simplify_path() and DirAccess.copy_absolute(source, target) != OK: return {"error": "无法导入：" + source}
	return {"error": "", "path": relative}

static func dependencies(level: Dictionary, root: String) -> PackedStringArray:
	var paths := {"level.json": true, "show.json": true}
	var song_path := str(level.get("song_path", "song/song.json"))
	paths[song_path] = true
	var song := read_json(root.path_join(song_path))
	if not str(song.get("audio", "")).is_empty(): paths[song_path.get_base_dir().path_join(song.audio)] = true
	for chart: Dictionary in song.get("charts", []): paths[song_path.get_base_dir().path_join(chart.path)] = true
	for pack: Dictionary in level.get("packs", []): paths[pack.path] = true
	var assets := []
	assets.append(level.get("cover", ""))
	for object_data: Dictionary in level.show.get("objects", []):
		assets.append(object_data.get("asset", "")); assets.append(object_data.get("fields", {}).get("font", ""))
	for track: Dictionary in level.show.get("tracks", []):
		for clip: Dictionary in track.get("clips", []): assets.append(clip.get("asset", ""))
	for binding: Dictionary in level.show.get("bindings", []):
		for key in ["sound", "effect", "hit_effect", "miss_effect"]: assets.append(binding.get(key, ""))
	for asset: String in assets:
		if asset.begins_with("assets/"): paths[asset] = true
	return PackedStringArray(paths.keys())

static func export_zip(level: Dictionary, root: String, path: String) -> String:
	var files := dependencies(level, root)
	for relative in files:
		if not _relative(relative): return "依赖路径不能离开工程：" + relative
		if relative not in ["level.json", "show.json"] and not FileAccess.file_exists(root.path_join(relative)): return "缺少依赖：" + relative
	var metadata := level.duplicate(true); metadata.erase("show"); metadata["show_path"] = "show.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var zip := ZIPPacker.new()
	if zip.open(path + ".tmp") != OK: return "无法创建关卡包"
	for relative in files:
		var bytes: PackedByteArray
		if relative == "level.json": bytes = JSON.stringify(metadata, "  ").to_utf8_buffer()
		elif relative == "show.json": bytes = JSON.stringify(level.show, "  ").to_utf8_buffer()
		else: bytes = FileAccess.get_file_as_bytes(root.path_join(relative))
		var error := zip.start_file(relative)
		if error == OK: error = zip.write_file(bytes)
		zip.close_file()
		if error != OK: zip.close(); return "写入关卡包失败：" + relative
	if zip.close() != OK: return "完成关卡包失败"
	return "" if DirAccess.rename_absolute(path + ".tmp", path) == OK else "替换关卡包失败"

static func unpack(path: String, root: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(path) != OK: return "无法打开关卡包"
	for relative in zip.get_files():
		if relative.ends_with("/"): continue
		if not _relative(relative): zip.close(); return "包内路径越过目标目录：" + relative
		var target := root.path_join(relative)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null: zip.close(); return "无法解压：" + relative
		file.store_buffer(zip.read_file(relative)); file.close()
	zip.close()
	return ""

static func _relative(path: String) -> bool:
	return not path.is_empty() and not path.is_absolute_path() and not ".." in path.replace("\\", "/").split("/")
