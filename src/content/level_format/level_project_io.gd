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
	# 导入产生独立版本；已有引用不因同名文件被悄悄替换。
	if FileAccess.file_exists(target) and source.replace("\\","/").simplify_path()!=target.replace("\\","/").simplify_path():
		relative=folder.path_join(LevelFormat.id("import")+"_"+source.get_file());target=root.path_join(relative)
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if source.simplify_path() != target.simplify_path() and DirAccess.copy_absolute(source, target) != OK: return {"error": "无法导入：" + source}
	return {"error": "", "path": relative}

static func dependencies(level: Dictionary, root: String) -> PackedStringArray:
	# 文件选择器可能给出 Windows 分隔符；派生依赖的相对路径使用同一表示。
	root=root.replace("\\","/").simplify_path()
	var paths := {"level.json": true, "show.json": true}
	var song_path := str(level.get("song_path", "song/song.json"))
	paths[song_path] = true
	var song := read_json(root.path_join(song_path))
	if not str(song.get("audio", "")).is_empty(): paths[song_path.get_base_dir().path_join(song.audio)] = true
	for chart: Dictionary in song.get("charts", []): paths[song_path.get_base_dir().path_join(chart.path)] = true
	for pack: Dictionary in level.get("packs", []): paths[pack.path] = true
	for reference: Dictionary in references(level):
		var asset: String=reference.asset
		if asset.begins_with("assets/"):paths[asset]=true
	return expand_dependencies(PackedStringArray(paths.keys()),root)

## 制作模板与字段也持有引用；保留文档路径，问题定位与修复使用同一结果。
static func references(level: Dictionary) -> Array:
	var result:=[]
	_collect_references(level,[],{},result)
	return result

static func _collect_references(value: Variant, path: Array, context: Dictionary, result: Array) -> void:
	if value is Dictionary:
		context=context.duplicate()
		if value.has("id"):
			if value.has("fields"):context.object_id=value.id
			elif value.has("keys"):context.track_id=value.id;context.object_id=value.get("object_id","");context.section=value.get("section","song");context.difficulties=value.get("difficulties",[])
			elif value.has("note_ids"):context.binding_id=value.id
			elif value.has("blend_px"):context.scene_cue_id=value.id;context.section=value.get("section","song")
			elif value.has("time_us") or value.has("start_us"):context.item_id=value.id;context.time_us=value.get("time_us",value.get("start_us",0))
		for key in value:
			if key in ["name","text","description","title"]:continue
			_collect_references(value[key],path+[key],context,result)
	elif value is Array:
		for index in value.size():_collect_references(value[index],path+[index],context,result)
	elif value is String and not value.is_empty() and (value.begins_with("assets/") or (not path.is_empty() and str(path.back()) in ["asset","font","cover","initial_background","sound","effect","hit_effect","miss_effect"])):
		var reference:=context.duplicate();reference.asset=value;reference.path=path.duplicate();result.append(reference)

static func expand_dependencies(paths: PackedStringArray, root: String) -> PackedStringArray:
	root=root.replace("\\","/").simplify_path().trim_suffix("/")
	var result:=paths.duplicate()
	for asset in paths:
		if asset.ends_with(LevelSpineAsset.SUFFIX):
			for dependency in LevelSpineAsset.dependencies(root.path_join(asset)):
				var relative:=dependency.trim_prefix(root+"/")
				if relative not in result:result.append(relative)
		if asset.ends_with(LevelAnimationAsset.SUFFIX):
			for dependency in LevelAnimationAsset.dependencies(root.path_join(asset)):
				var relative:=dependency.trim_prefix(root+"/")
				if relative not in result:result.append(relative)
	return result

static func export_zip(level: Dictionary, root: String, path: String, progress:=Callable(), cancelled:=Callable()) -> String:
	var files := dependencies(level, root)
	for relative in files:
		if not _relative(relative): return "依赖路径不能离开工程：" + relative
		if relative not in ["level.json", "show.json"] and not FileAccess.file_exists(root.path_join(relative)): return "缺少依赖：" + relative
	var metadata := level.duplicate(true); metadata.erase("show"); metadata["show_path"] = "show.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var zip := ZIPPacker.new()
	if zip.open(path + ".tmp") != OK: return "无法创建关卡包"
	var done:=0;var total:=0
	for relative in files:total+=JSON.stringify(level).to_utf8_buffer().size() if relative in ["level.json","show.json"] else _file_size(root.path_join(relative))
	for relative in files:
		var error := zip.start_file(relative)
		var source: FileAccess
		if relative not in ["level.json","show.json"]:source=FileAccess.open(root.path_join(relative),FileAccess.READ)
		if source==null and relative not in ["level.json","show.json"]:zip.close();DirAccess.remove_absolute(path+".tmp");return "无法读取："+relative
		if error==OK:
			if source==null:
				var bytes:=JSON.stringify(metadata if relative=="level.json" else level.show,"  ").to_utf8_buffer();error=zip.write_file(bytes);done+=bytes.size()
			else:
				while source.get_position()<source.get_length() and error==OK:
					if cancelled.is_valid() and cancelled.call():source.close();zip.close();DirAccess.remove_absolute(path+".tmp");return "已取消"
					var bytes:=source.get_buffer(1024*1024);error=zip.write_file(bytes);done+=bytes.size()
					if progress.is_valid():progress.call(done,total,"压缩："+relative)
		if source!=null:source.close()
		zip.close_file()
		if error!=OK:zip.close();DirAccess.remove_absolute(path+".tmp");return "写入关卡包失败："+relative
		if cancelled.is_valid() and cancelled.call():zip.close();DirAccess.remove_absolute(path+".tmp");return "已取消"
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

static func _file_size(path: String) -> int:
	var file:=FileAccess.open(path,FileAccess.READ)
	return file.get_length() if file!=null else 0

static func copy_dependencies(files: PackedStringArray, root: String, target: String, progress:=Callable(), cancelled:=Callable()) -> String:
	var done:=0;var total:=0
	for relative in files:
		if relative in ["level.json","show.json"]:continue
		if not _relative(relative):return "依赖路径越出工程："+relative
		if not FileAccess.file_exists(root.path_join(relative)):return "缺少依赖："+relative
		total+=_file_size(root.path_join(relative))
	for relative in files:
		if relative in ["level.json","show.json"]:continue
		var destination:=target.path_join(relative)
		DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		var source:=FileAccess.open(root.path_join(relative),FileAccess.READ)
		var output:=FileAccess.open(destination+".copying",FileAccess.WRITE)
		if source==null or output==null:return "无法复制："+relative
		while source.get_position()<source.get_length():
			if cancelled.is_valid() and cancelled.call():source.close();output.close();DirAccess.remove_absolute(destination+".copying");return "已取消"
			var bytes:=source.get_buffer(1024*1024);output.store_buffer(bytes);done+=bytes.size()
			if output.get_error()!=OK:source.close();output.close();DirAccess.remove_absolute(destination+".copying");return "写入失败："+relative
			if progress.is_valid():progress.call(done,total,"复制："+relative)
		source.close();output.close()
		if DirAccess.rename_absolute(destination+".copying",destination)!=OK:return "无法完成复制："+relative
	return ""
