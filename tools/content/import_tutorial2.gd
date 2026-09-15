extends SceneTree
## 将工程内的教程源谱投影为正式关卡资源；更新源谱后可重新运行。
const DEST := "res://content/stages/tutorial2/"
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var project := ChartProjectLoader.read_chart_data(DEST+"source/song.json", "normal")
	if not project.errors.is_empty():
		printerr(project.errors)
		quit(1)
		return
	var stage := ChartProjectLoader.make_stage(project.song, project.charts[0])
	stage.song.audio_stream = load(DEST+"source/audio/level 2-v3.wav")
	stage.stage_id = "tutorial2"
	stage.display_name = "教程2"
	stage.song_title = stage.song.title
	stage.song_artist = stage.song.artist
	stage.order_index = 1
	stage.unlocked_by_default = true
	# 源谱保留在正式谱面资源中，运行时仍可应用策划表最新的路径参数。
	var source_chart: SongChart = stage.get_meta("planning_source_chart")
	ResourceSaver.save(source_chart, DEST+"source_chart.tres")
	stage.set_meta("planning_source_chart",load(DEST+"source_chart.tres"))
	for slot: String in ["song", "chart", "stage_show", "visual_theme", "background", "reward"]:
		var resource: Resource = stage.get(slot)
		if resource == null: continue
		var path := DEST+slot+".tres"
		var error := ResourceSaver.save(resource,path)
		if error != OK:
			printerr("保存失败：",path)
			quit(1)
			return
		stage.set(slot,null)
		stage.set(slot+"_resource_path",path)
	stage.rule_set = null
	stage.rule_set_resource_path = "res://content/rules/default_gameplay_rules.tres"
	var error := ResourceSaver.save(stage,DEST+"stage_definition.tres")
	print("教程2导入：",error_string(error))
	quit(0 if error == OK else 1)
