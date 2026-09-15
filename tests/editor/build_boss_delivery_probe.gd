extends SceneTree
func _initialize() -> void:build.call_deferred()
func build() -> void:
	var source:=ProjectSettings.globalize_path("res://../Levels/output/保底关卡/level_1")
	var destination:=ProjectSettings.globalize_path("res://../Levels/output/boss-delivery-qa")
	var opened:=LevelProjectIO.open_project(source.path_join("level.json"))
	LevelProjectIO.copy_dependencies(LevelProjectIO.dependencies(opened.level,source),source,destination)
	var staging:="res://.godot/boss-delivery-probe";DirAccess.make_dir_recursive_absolute(staging)
	var node:=Node2D.new();node.set_script(load("res://tests/editor/boss_delivery_probe.gd"))
	var scene:=PackedScene.new();scene.pack(node);node.free();ResourceSaver.save(scene,staging.path_join("probe.tscn"))
	var entry:=VisualAssetEntry.new();entry.asset_id="qa:boss";entry.category=&"actor";entry.runtime_scene=scene
	var manifest:=VisualAssetManifest.new();manifest.manifest_id="boss-delivery-qa";manifest.entries.append(entry)
	var path:=staging.path_join("manifest.tres");ResourceSaver.save(manifest,path)
	var error:=LevelAssetPackWriter.write(path,destination.path_join("packs/probe.pck"))
	if not error.is_empty():printerr(error);quit(1);return
	opened.level.packs.append({"path":"packs/probe.pck","manifest":path,"name":"验收"})
	opened.level.show.objects.append(LevelFormat.object("actor","qa:boss"))
	LevelProjectIO.save(opened.level,destination);quit()
