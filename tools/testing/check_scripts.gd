extends SceneTree

## 在 Autoload 注册完成后加载所有工程脚本，覆盖编辑器扫描的旧测试和工具。
func _initialize() -> void:
	_check.call_deferred()


func _check() -> void:
	var files: PackedStringArray = []
	for folder: String in ["res://src", "res://tests", "res://tools", "res://addons"]:
		_collect(folder, files)
	var failures: PackedStringArray = []
	for path: String in files:
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			failures.append(path)
	print("SCRIPT AUDIT: %d checked; %d failed" % [files.size(), failures.size()])
	for path: String in failures:
		printerr("FAILED: ", path)
	quit(0 if failures.is_empty() else 1)


func _collect(folder: String, files: PackedStringArray) -> void:
	for file: String in DirAccess.get_files_at(folder):
		if file.ends_with(".gd"):
			files.append(folder.path_join(file))
	for child: String in DirAccess.get_directories_at(folder):
		if not child.begins_with("."):
			_collect(folder.path_join(child), files)
