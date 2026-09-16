extends SceneTree
## 从原有美术场景补全漏填的素材清单，制作可独立交付的第三关包。
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var directory:=ProjectSettings.globalize_path("res://../Levels/output/保底关卡/level_3")
	var error:=LevelAssetPackWriter.write("res://content/backgrounds/level_3.tres",directory.path_join("packs/level_3.pck"))
	if not error.is_empty():printerr(error);quit(1);return
	var opened:=LevelProjectIO.open_project(directory.path_join("level.json"))
	opened.level.initial_background="level_3_background_1"
	opened.level.packs=[{"path":"packs/level_3.pck","manifest":"res://content/backgrounds/level_3.tres","name":"牲 · 第三关环境"}]
	error=LevelProjectIO.save(opened.level,directory)
	if not error.is_empty():printerr(error);quit(1);return
	print("第三关场景及素材包已恢复")
	quit()
