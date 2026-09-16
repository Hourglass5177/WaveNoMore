extends SceneTree
## 对实际导出包运行，覆盖资源转换后的关联和正式 StageRoot 装配。
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var catalog=load("res://content/catalogs/mvp_catalog.tres")
	var planning=PlanningParameters.read()
	if not planning.errors.is_empty():printerr(planning.errors);quit(1);return
	for stage in catalog.stages:
		stage.resolve_dependencies_sync()
		var source=stage.get_meta("planning_source_chart")
		var issues=ChartPathAdapter.validate(source,stage.rule_set)
		if not issues.is_empty():printerr(stage.display_name,issues);quit(1);return
		for ghost in source.ghost_events:
			if Array(ghost.tuning_ids)!=ghost.get_meta("json_source").tuning_ids:
				printerr("导出丢失关联：",ghost.event_id);quit(1);return
		var game=load("res://scenes/stage/stage_root.tscn").instantiate()
		root.add_child(game)
		if not game.load_stage(stage,false):printerr("正式装配失败：",stage.display_name);quit(1);return
		print("PACKAGED PASS ",stage.display_name," Ghost=",source.ghost_events.size()," BOSS=",game.level_show_player.boss_emissions.size())
		game.queue_free();await process_frame
	print("PACKAGED THREE STAGES PASS parameters=",planning.values.size())
	quit()
