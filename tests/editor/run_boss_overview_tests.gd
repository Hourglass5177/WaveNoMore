extends SceneTree
var failures:=0
func _initialize() -> void:run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:failures+=1;printerr("FAIL: "+label)
func settle() -> void:
	for frame in 5:await process_frame
func click(control: Control) -> void:
	var viewport:=control.get_viewport();var point:=control.get_global_rect().get_center()
	if viewport is Window and viewport!=root and viewport.is_embedded():point+=Vector2(viewport.position);viewport=root
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;viewport.push_input(event,true)
func run() -> void:
	var output:=ProjectSettings.globalize_path("res://../Levels/output/boss-overview")
	var opened:=LevelProjectIO.open_project("res://examples/level-studio/渡口演出/level.json")
	LevelProjectIO.copy_dependencies(LevelProjectIO.dependencies(opened.level,opened.directory),opened.directory,output)
	LevelProjectIO.save(opened.level,output)
	var workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate();workspace.offer_recovery_on_start=false;root.add_child(workspace);await settle()
	workspace._open_path(output.path_join("level.json"));await settle()
	var chart: SongChart=workspace.song_document.chart();var note:=NoteEvent.new();note.event_id="overview_hold";note.boss=true;note.tick=960;note.kind=GameplayTypes.NoteKind.HOLD;note.duration_ticks=960;chart.note_events.append(note)
	var missing: Dictionary=workspace.document.entries("bindings")[0].duplicate(true);missing.id="overview_invalid";missing.note_ids=["missing_note"]
	workspace.document.replace("测试失效关联","bindings",[],[missing]);await settle()
	workspace.select_objects(PackedStringArray());var before: Dictionary=workspace.document.data.duplicate(true);var cursor: int=workspace.document.cursor
	var records:=LevelBossReference.collect(workspace)
	check(records.any(func(item):return item.id==note.event_id and item.end_us>item.time_us and item.status=="未绑定"),"Hold 保留持续时间及未绑定状态")
	check(records.any(func(item):return item.id=="missing_note" and item.time_us<0 and item.status=="失效关联"),"失效 ID 不猜测时间")
	workspace.open_boss_overview(note.event_id);await settle()
	var dialog=workspace.get_children().filter(func(node):return node.scene_file_path=="res://scenes/tools/level_studio/boss_overview.tscn")[0]
	check(dialog.get_node("%Notes").item_count==records.size(),"不选对象可打开当前难度总览")
	check(dialog.get_node("%Add").disabled,"未选择 BOSS 对象时不可误加入绑定")
	click(dialog.get_node("%Locate"));await settle()
	check(workspace.time_us==workspace.song_document.tempo_map().tick_to_us(note.tick),"定位所选 BOSS 音符")
	dialog.get_node("%Filter").select(1);dialog.get_node("%Filter").item_selected.emit(1);await settle()
	check(dialog.get_node("%Notes").item_count==records.filter(func(item):return item.status=="未绑定").size(),"未绑定筛选")
	click(dialog.get_ok_button());await settle()
	check(workspace.document.data==before and workspace.document.cursor==cursor and workspace.selection.is_empty(),"浏览定位筛选不修改文档选区及历史")
	workspace.timeline.boss_notes=records;workspace.timeline.queue_redraw();await settle()
	var record: Dictionary=records.filter(func(item):return item.id==note.event_id)[0]
	var rect: Rect2=workspace.timeline._boss_rect(record)
	check(workspace.timeline._get_tooltip(rect.get_center()).contains("Hold"),"参考轨悬停展示类型与持续时间")
	# 点击实际 BOSS 参考轨打开只读详情，不切换绑定。
	var point: Vector2=workspace.timeline.global_position+Vector2(maxf(LevelTimeline.HEADER+5,rect.position.x+5),92)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;root.push_input(event,true)
	await settle()
	check(workspace.document.data==before and workspace.document.cursor==cursor,"点击参考标记不会修改绑定")
	check(workspace.get_children().any(func(window):return window.scene_file_path=="res://scenes/tools/level_studio/boss_overview.tscn" and window.visible and window.selected_id==note.event_id),"实际点击参考轨打开对应只读详情")
	for window in workspace.get_children():
		if window.scene_file_path=="res://scenes/tools/level_studio/boss_overview.tscn":click(window.get_ok_button())
	await settle()
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(output.path_join("timeline.png"))
	var binding: Dictionary=workspace.document.entries("bindings")[0]
	workspace.select_objects(PackedStringArray([str(binding.object_id)]));workspace.open_boss_binding(str(binding.id));workspace.open_boss_overview(note.event_id);await settle()
	dialog=workspace.get_children().filter(func(window):return window.scene_file_path=="res://scenes/tools/level_studio/boss_overview.tscn")[0]
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(output.path_join("overview.png"))
	check(not dialog.get_node("%Add").disabled,"明确选中 BOSS 后可使用加入按钮")
	var before_add: int=workspace.document.cursor;click(dialog.get_node("%Add"));await settle()
	check(note.event_id in workspace.document.find("bindings",binding.id).note_ids and workspace.document.cursor==before_add+1,"明确加入现有绑定一次撤销")
	workspace.document.undo();await settle()
	check(not note.event_id in workspace.document.find("bindings",binding.id).note_ids,"撤销加入恢复原绑定")
	workspace._switch_difficulty(1);await settle()
	check(not LevelBossReference.collect(workspace).any(func(item):return item.id==note.event_id or item.id=="missing_note"),"切换难度不会混入其他难度音符与失效关联")
	workspace.queue_free();await settle();print("BOSS OVERVIEW failures=",failures);quit(failures)
