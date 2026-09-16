extends SceneTree
## 将关卡编辑器保存的第一关同步到现有内置入口，保持选关与存档 ID。
const DEST := "res://content/stages/tutorial2/"
const PROJECT := "res://content/stage_project/tutorial_1/"
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	var source:=ProjectSettings.globalize_path("res://../Levels/output/钟-用户修改快照/level.json")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--source="):source=arg.trim_prefix("--source=")
	var opened:=LevelProjectIO.open_project(source)
	if not opened.error.is_empty():printerr(opened.error);quit(1);return
	if opened.level.title!="钟":printerr("来源不是钟，停止导入");quit(1);return
	var error:=LevelProjectIO.copy_dependencies(LevelProjectIO.dependencies(opened.level,opened.directory),opened.directory,PROJECT)
	if not error.is_empty():printerr(error);quit(1);return
	error=LevelProjectIO.save(opened.level,PROJECT)
	if not error.is_empty():printerr(error);quit(1);return
	var result:=LevelProjectLoader.load_stage(PROJECT+"level.json","normal")
	if result.stage==null:printerr(result.errors);quit(1);return
	var stage: StageDefinition=result.stage
	var previous:=load(DEST+"stage_definition.tres") as StageDefinition
	previous.resolve_dependencies_sync()
	stage.stage_id=previous.stage_id;stage.order_index=previous.order_index
	stage.reward=previous.reward;stage.unlocked_by_default=previous.unlocked_by_default
	stage.song_title=stage.display_name
	stage.song.audio_stream=load(PROJECT+"song/"+str(LevelProjectIO.read_json(PROJECT+"song/song.json").audio))
	var source_chart: SongChart=stage.get_meta("level_source_chart")
	ResourceSaver.save(source_chart,DEST+"source_chart.tres")
	stage.set_meta("planning_source_chart",load(DEST+"source_chart.tres"))
	stage.remove_meta("level_source_chart")
	# 将相对文件引用改为正式工程资源路径，发布时不依赖 Levels 目录。
	for object: Dictionary in stage.stage_show.level_data.objects:
		if not str(object.asset).is_empty() and not str(object.asset).contains(":"):object.asset=PROJECT+str(object.asset)
	for slot: String in ["song","chart","stage_show","visual_theme","background","reward"]:
		var resource: Resource=stage.get(slot)
		if resource==null:continue
		var path:=DEST+slot+".tres"
		var code:=ResourceSaver.save(resource,path)
		if code!=OK:printerr("保存失败：",path);quit(1);return
		stage.set(slot,null);stage.set(slot+"_resource_path",path)
	stage.rule_set=null;stage.rule_set_resource_path="res://content/rules/default_gameplay_rules.tres"
	var code:=ResourceSaver.save(stage,DEST+"stage_definition.tres")
	print("已更新内置第一关：",stage.display_name,"，ID=",stage.stage_id,"，结果=",error_string(code))
	quit(0 if code==OK else 1)
