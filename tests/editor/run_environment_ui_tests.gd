extends SceneTree
## 通过实际 Viewport 路由完成换景编辑、取消、撤销与跨面板保存。
var failures := 0
var workspace
func _initialize() -> void: run.call_deferred()
func check(value:bool,label:String) -> void:
	if not value:failures+=1;printerr("FAIL ",label)
func settle(count:=3) -> void:
	for index in count:await process_frame
func mouse(point:Vector2,pressed:bool,shift:=false) -> void:
	var event:=InputEventMouseButton.new();event.position=workspace.timeline.global_position+point;event.global_position=event.position;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.shift_pressed=shift;root.push_input(event,true)
func motion(point:Vector2) -> void:
	var event:=InputEventMouseMotion.new();event.position=workspace.timeline.global_position+point;event.global_position=event.position;event.button_mask=MOUSE_BUTTON_MASK_LEFT;event.alt_pressed=true;root.push_input(event,true)
func run() -> void:
	root.size=Vector2i(1440,900)
	workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate();workspace.offer_recovery_on_start=false;workspace.recovery_path=ProjectSettings.globalize_path("res://../Levels/output/environment/ui/recovery.json");root.add_child(workspace);await settle(6)
	workspace._ui_scale=1;workspace._apply_ui_scale();workspace.timeline.waveform_duration=30
	var output:=ProjectSettings.globalize_path("res://../Levels/output/environment/ui")
	check(LevelAssetPackWriter.write("res://tests/fixtures/environment/manifest.tres",output.path_join("environment.pck")).is_empty(),"环境资源包导出")
	workspace.document.directory=output
	workspace.document.fields("接入素材包",{"packs":[{"path":"environment.pck","manifest":"res://tests/fixtures/environment/manifest.tres"}]});await settle()
	workspace.document.fields("初始环境",{"initial_background":"environment_test_a"})
	workspace.add_environment_cue("environment_test_b",1000000)
	workspace.add_environment_cue("environment_test_c",1200000);await settle(6)
	check(workspace.timeline.environment!=null,"工作区编排背景序列")
	var cues:Array=workspace.document.entries("scene_cues");var first:String=cues[0].id;var second:String=cues[1].id
	var timeline:LevelTimeline=workspace.timeline
	timeline.left_seconds=0;timeline.pixels_per_second=200;timeline.row_scroll=0;timeline.queue_redraw();await settle()
	var a:=Vector2(timeline.x_at(1000000),LevelTimeline.RULER+12)
	var b:=Vector2(timeline.x_at(1200000),a.y)
	mouse(a,true);mouse(a,false);mouse(b,true,true);mouse(b,false,true);await settle()
	check(workspace.selected_items.size()==2,"换景 Shift 多选跨属性刷新保持")
	var before:int=workspace.document.cursor
	mouse(a,true);motion(a+Vector2(3,0));mouse(a+Vector2(3,0),false);await settle()
	check(workspace.document.cursor==before,"小于6像素视为点击")
	mouse(a,true);motion(a+Vector2(60,0));await settle()
	check(workspace.document.find("scene_cues",first).time_us==1300000,"真实拖动即时预览")
	workspace._set_background(true);workspace._set_background(false);mouse(a,false);await settle()
	check(workspace.document.find("scene_cues",first).time_us==1000000 and workspace.document.cursor==before,"失焦取消候选和历史")
	mouse(a,true);motion(a+Vector2(60,0));mouse(a+Vector2(60,0),false);await settle()
	check(workspace.document.cursor==before+1,"多选一次拖动一次撤销")
	workspace.document.undo();await settle()
	check(workspace.document.find("scene_cues",first).time_us==1000000 and workspace.document.find("scene_cues",second).time_us==1200000,"撤销恢复两个请求")
	timeline.copy_selected();workspace.seek(3000000);timeline.paste_selected();await settle()
	check(workspace.document.entries("scene_cues").size()==4,"复制粘贴保留场景顺序")
	timeline.delete_selected();await settle();check(workspace.document.entries("scene_cues").size()==2,"删除明确的换景选区")
	workspace.document.undo();await settle();check(workspace.document.entries("scene_cues").size()==4,"撤销删除")
	workspace._timeline_selection(PackedStringArray(),"@environment",PackedStringArray([first]));await settle()
	workspace.set_environment_field("effect","fade");await settle()
	var spin:SpinBox=workspace.inspector.find_children("*","SpinBox",true,false)[0]
	spin.get_line_edit().grab_focus();spin.value=1.1;spin.value=1.2;await settle();check(is_instance_valid(spin) and spin.get_line_edit().has_focus(),"数值连调不重建正在操作的控件")
	workspace._prepare_command();await settle();check(workspace.document.find("scene_cues",first).time_us==1200000,"保存入口提交当前字段")
	var overrides:Array=workspace.inspector.find_children("*","CheckBox",true,false).filter(func(control):return control.text=="单独设置本层效果")
	check(not overrides.is_empty(),"层效果有独立入口")
	if not overrides.is_empty():
		overrides[0].button_pressed=true;await settle()
		check(workspace.document.find("scene_cues",first).layers.has("ground"),"开启单层设置即保存覆盖状态")
		overrides=workspace.inspector.find_children("*","CheckBox",true,false).filter(func(control):return control.text=="单独设置本层效果")
		overrides[0].button_pressed=false;await settle()
		check(not workspace.document.find("scene_cues",first).layers.has("ground"),"取消单层设置恢复继承")
	check(LevelProjectIO.save(workspace.document.data,output,workspace._workspace_snapshot()).is_empty(),"保存新增字段和视图")
	var reopened:=LevelProjectIO.open_project(output.path_join("level.json"))
	check(reopened.error.is_empty() and reopened.level.show.scene_cues==JSON.parse_string(JSON.stringify(workspace.document.data.show.scene_cues)),"重新打开保留请求和效果")
	workspace._write_recovery()
	var recovery:=LevelProjectIO.read_json(workspace.recovery_path)
	check(recovery.get("level",{}).get("show",{}).get("scene_cues",[])==reopened.level.show.scene_cues,"恢复稿保存换景内容")
	workspace.seek(2400000);var previous:int=workspace.time_us;workspace.preview_environment_cue();await settle()
	check(workspace._workspace_snapshot().time_us==previous,"保存不写入临时衔接预览位置")
	workspace.end_environment_preview();await settle();check(workspace.time_us==previous,"结束衔接预览恢复位置")
	if DisplayServer.get_name()!="headless":
		workspace.timeline.folded["@environment"]=false;workspace.timeline.rebuild_rows();workspace.seek(3500000);await settle(4);await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("workspace.png"))
		var finish:int=timeline.environment.transitions[0].finish_us
		for factor in [1.0,1.5,2.0]:
			root.size=Vector2i(2560,1440);workspace._ui_scale=factor;workspace._apply_ui_scale();await settle(8)
			check(timeline.environment.transitions[0].finish_us==finish,"界面倍率不改变换景时间")
			var point:=Vector2(777,444)
			check(workspace.surface.to_world(workspace.surface.to_view(point)).distance_to(point)<0.01,"界面倍率保持画布拾取")
			check(timeline.get_global_rect().end.x<=root.get_visible_rect().size.x+1,"场景轨道保持在视口内")
			await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(output.path_join("scale-%d.png"%roundi(factor*100)))
		workspace._ui_scale=0;root.mode=Window.MODE_MAXIMIZED;await settle(20)
		check(root.mode==Window.MODE_MAXIMIZED and timeline.environment.transitions[0].finish_us==finish,"真实最大化保持衔接安排")
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(output.path_join("maximized.png"))
		root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720);await settle(10)
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(output.path_join("restored.png"))
	workspace.document.fields("片头",{"intro_us":2000000,"outro_us":2000000});await settle()
	workspace.set_section("intro");workspace.add_environment_cue("environment_test_b",1500000);await settle()
	workspace.preview_environment_cue();await settle();check(workspace._environment_preview.range_start<0,"预览包含曲前")
	workspace._position_changed(2.1);await settle();check(workspace.section=="song","衔接预览连续跨入歌曲")
	workspace.end_environment_preview();await settle();check(workspace.section=="intro","退出恢复原区段")
	workspace.queue_free();await settle()
	print("ENVIRONMENT UI failures=",failures);quit(1 if failures else 0)
