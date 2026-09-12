extends SceneTree
var failures:=0
var checks:=0
func _initialize() -> void:_run.call_deferred()
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+label)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join("../Levels/output/ui").simplify_path())
	root.size=Vector2i(1440,900)
	var workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate()
	workspace.offer_recovery_on_start=false;workspace.recovery_path="user://level-tests/example-recovery.json"
	root.add_child(workspace);await process_frame;await process_frame
	workspace._open_path("res://examples/level-studio/渡口演出/level.json")
	for frame in 8:await process_frame
	check(workspace.song_document.charts.size()==2,"示例工程加载两种难度")
	check(is_instance_valid(workspace.preview.stage_root),"示例编辑预览使用正式 StageRoot")
	workspace._reset_layout();workspace.select_objects(PackedStringArray(["ferryman"]));workspace.seek(3400000)
	for frame in 30:await process_frame
	check(workspace.show_player().drivers.has("ferryman"),"素材包原生动画进入工作区")
	check(not workspace.preview.stage_root.chart_scheduler.boss_emissions.is_empty(),"编辑预览安装 BOSS 发射数据")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://").path_join("../Levels/output/ui/level-editor-example.png").simplify_path())
	workspace.open_boss_binding();await process_frame;await process_frame
	var panel: LevelBossPanel=workspace.boss_panel
	check(panel.visible,"BOSS 编排集成右侧面板")
	panel._select_binding(1);panel._slider.value=0.3
	for frame in 4:await process_frame
	check(workspace.timeline.is_visible_in_tree() and not workspace._modal_open(),"编排期间主时间线保持可操作")
	check(panel.data.note_ids.size()>0,"面板还原绑定音符组和出手帧")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://").path_join("../Levels/output/ui/level-editor-boss-panel.png").simplify_path())
	workspace.queue_free();await process_frame;await process_frame
	print("LEVEL EXAMPLE UI TESTS: %d (%d checks)"%[failures,checks]);quit(1 if failures else 0)
