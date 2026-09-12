extends SceneTree
var failures:=0
var checks:=0
func _initialize() -> void:_run.call_deferred()
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+label)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join("../Levels/output/ui").simplify_path())
	var workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate()
	workspace.offer_recovery_on_start=false;workspace.recovery_path="user://level-tests/recovery.json"
	root.add_child(workspace)
	await process_frame;await process_frame
	check(workspace.show_player()!=null,"空白工程可显示演出画布")
	workspace.add_object("text");await process_frame
	var id:String=workspace.selection[0]
	workspace.set_property("text","山川异域，风月同天");await process_frame
	check(workspace.show_player().objects[id].get_node("Content").text=="山川异域，风月同天","属性编辑实时进入预览")
	workspace.auto_key=true;workspace.time_us=1000000;workspace.set_property("position",[600,300]);await process_frame
	check(workspace.document.entries("tracks").size()==1,"自动关键帧创建属性轨")
	workspace.time_us=2000000;workspace.set_property("position",[1000,500]);await process_frame
	workspace.seek(1500000)
	check(workspace.show_player().objects[id].position.is_equal_approx(Vector2(800,400)),"工作区定位和属性轨共用插值")
	workspace.add_clip("visibility");await process_frame
	var track_id:String=workspace.selected_track
	var clip_id:String=workspace.selected_item
	workspace.timeline.time_us=2000000;workspace.timeline.split_selected();await process_frame
	check(workspace.document.find("tracks",track_id).clips.size()==2,"时间线拆分生成两个连续片段")
	workspace.document.undo();await process_frame
	check(workspace.document.find("tracks",track_id).clips.size()==1,"一次撤销恢复完整片段")
	workspace.select_objects(PackedStringArray([id]));workspace.copy_objects();workspace.paste_objects();await process_frame
	check(workspace.document.entries("objects").size()==2,"图形对象复制携带独立实例")
	workspace._save_sequence();await process_frame
	check(workspace.document.entries("sequences").size()==1,"多对象演出可以保存成模板")
	workspace.select_objects(PackedStringArray([id]));workspace.set_item_field(track_id,clip_id,"fade_in_us",500000);await process_frame
	workspace._write_recovery()
	check(FileAccess.file_exists(workspace.recovery_path),"恢复稿包含最新制作文档")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://").path_join("../Levels/output/ui/level-editor-workspace.png").simplify_path())
	workspace.queue_free();await process_frame;await process_frame
	print("LEVEL WORKSPACE TESTS: %d (%d checks)"%[failures,checks]);quit(1 if failures else 0)
