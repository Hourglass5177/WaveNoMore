extends SceneTree
## 验收场景通过普通素材包进入实际 EXE，不向产品添加测试入口。
func _initialize() -> void:_build.call_deferred()
func _build() -> void:
	var destination:=ProjectSettings.globalize_path("res://").path_join("../Levels/output/release-qa").simplify_path()
	# Godot 源资源临时留在工程缓存，打好的验收包统一输出到 Levels。
	var staging:="res://.godot/level-release-staging"
	DirAccess.make_dir_recursive_absolute(staging)
	var opened:=LevelProjectIO.open_project("res://examples/level-studio/渡口演出/level.json")
	for relative in LevelProjectIO.dependencies(opened.level,opened.directory):
		var target:=destination.path_join(relative)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		DirAccess.copy_absolute(opened.directory.path_join(relative),target)
	var node:=Node2D.new();node.set_script(load("res://tests/editor/level_release_probe.gd"))
	var scene:=PackedScene.new();scene.pack(node);node.free()
	ResourceSaver.save(scene,staging.path_join("probe.tscn"))
	var entry:=VisualAssetEntry.new();entry.asset_id="qa:probe";entry.category=&"actor";entry.runtime_scene=scene
	var manifest:=VisualAssetManifest.new();manifest.manifest_id="release-qa";manifest.entries.append(entry)
	var manifest_path:=staging.path_join("manifest.tres");ResourceSaver.save(manifest,manifest_path)
	var error:=LevelAssetPackWriter.write(manifest_path,destination.path_join("packs/probe.pck"))
	if not error.is_empty():printerr(error);quit(1);return
	opened.level.packs.append({"path":"packs/probe.pck","manifest":manifest_path,"name":"验收探针"})
	var object:=LevelFormat.object("actor","qa:probe");object.id="qa_probe";opened.level.show.objects.append(object)
	LevelProjectIO.save(opened.level,destination)
	error=LevelProjectIO.export_zip(opened.level,destination,destination.path_join("probe.level.zip"))
	if not error.is_empty():printerr(error);quit(1);return
	quit()
