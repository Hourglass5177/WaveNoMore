extends SceneTree
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var output:=ProjectSettings.globalize_path("res://../Levels/output/保底关卡")
	var summary:=LevelProjectIO.read_json(output.path_join("制作摘要.json"))
	var workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate();workspace.offer_recovery_on_start=false;root.add_child(workspace)
	for frame in 5:await process_frame
	for entry: Dictionary in summary.completed:
		var directory:=output.path_join("level_"+str(int(entry.level)))
		var result:=LevelProjectLoader.load_stage(directory.path_join("level.json"),"normal")
		if result.stage==null:printerr(result.errors);quit(1);return
		workspace._open_path(directory.path_join("level.json"))
		for frame in 5:await process_frame
		workspace.preview.suspended=false
		var target:=roundi((float(entry.first_judgment_sec)-2.0)*1000000)
		workspace.time_us=target;workspace.timeline.time_us=target
		await workspace.preview.seek_preview(target)
		workspace.surface.player.seek("song",target)
		for frame in 5:await process_frame
		if workspace.surface.emissions.size()!=int(entry.notes):printerr("BOSS 关联遗漏");quit(1);return
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("level_%d-BOSS.png"%int(entry.level)))
		var error:=LevelProjectIO.export_zip(workspace.document.data,directory,output.path_join("level_%d-BOSS.level.zip"%int(entry.level)))
		if not error.is_empty():printerr(error);quit(1);return
		print("BOSS LEVEL ",entry.level," OK emissions=",workspace.surface.emissions.size())
	workspace.queue_free();await process_frame;quit()

