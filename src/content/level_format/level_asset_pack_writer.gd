@tool
class_name LevelAssetPackWriter
extends RefCounted
## 将指定素材清单及实际依赖打成资源包，保持 Godot 已导入的纹理/音频数据。
static func write(manifest_path: String, target: String) -> String:
	var manifest := load(manifest_path) as VisualAssetManifest
	if manifest == null: return "请选择 VisualAssetManifest 素材清单"
	var pending: Array[String] = [manifest_path]
	var files := {}
	while not pending.is_empty():
		var path: String = pending.pop_back()
		if files.has(path): continue
		if not FileAccess.file_exists(path): return "缺少依赖：" + path
		files[path] = true
		# 外部源美术不打包；只有场景、清单直接引用的运行资源及其导入产物进入 PCK。
		for dependency in ResourceLoader.get_dependencies(path): pending.append(dependency.split("::")[-1])
		if FileAccess.file_exists(path + ".uid"): files[path + ".uid"] = true
		if FileAccess.file_exists(path + ".import"):
			files[path + ".import"] = true
			var config := ConfigFile.new(); config.load(path + ".import")
			for imported: String in config.get_value("deps", "dest_files", PackedStringArray()):
				if not FileAccess.file_exists(imported): return "请先在 Godot 完成素材导入：" + path
				files[imported] = true
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var pack := PCKPacker.new()
	var error := pack.pck_start(target)
	if error != OK: return "无法创建素材包：" + error_string(error)
	for path: String in files:
		error = pack.add_file(path, path)
		if error != OK: return "无法打包素材：" + path
	error = pack.flush()
	if error != OK: return "完成素材包失败：" + error_string(error)
	var descriptor := {"format": "minghe-assets", "format_version": 1, "name": manifest.manifest_id, "pack": target.get_file(), "manifest": manifest_path}
	var file := FileAccess.open(target.get_basename() + ".assetpack.json", FileAccess.WRITE)
	if file == null: return "无法写入素材包描述文件"
	file.store_string(JSON.stringify(descriptor, "  ") + "\n")
	return ""
