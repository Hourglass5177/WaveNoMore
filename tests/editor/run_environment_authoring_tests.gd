extends SceneTree
## 背景制作端通过 Viewport 输入路由检查边界候选、取消、历史与预览恢复。
var failures:=0
var workspace
var output:=ProjectSettings.globalize_path("res://../Levels/output/environment/authoring")
func _initialize() -> void:run.call_deferred()
func check(value:bool,label:String) -> void:
	if not value:failures+=1;printerr("FAIL ",label)
func settle() -> void:
	for index in 4:await process_frame
func mouse(point:Vector2,pressed:bool) -> void:
	var event:=InputEventMouseButton.new();event.position=workspace.surface.global_position+point;event.global_position=event.position;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
func motion(point:Vector2) -> void:
	var event:=InputEventMouseMotion.new();event.position=workspace.surface.global_position+point;event.global_position=event.position;event.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(event,true)
func run() -> void:
	root.size=Vector2i(1440,1000)
	DirAccess.make_dir_recursive_absolute(output)
	var path:=output.path_join("background.tres")
	check(ResourceSaver.save(load("res://tests/fixtures/environment/a.tres"),path)==OK,"建立独立制作稿")
	workspace=load("res://addons/parallax_background_editor/workspace.gd").new();root.add_child(workspace);workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);workspace.request_open(path);await settle()
	var doc=workspace.document;var surface=workspace.surface
	doc.selected_id=-1;doc.selected_sublayer_id=doc.sublayers[0].id;workspace._rebuild_tree();workspace._update_properties();await settle()
	var original:Array=doc.signature()
	var edge:Vector2=surface.pan+Vector2(240,540)*surface.zoom
	mouse(edge,true);motion(edge+Vector2(3,0));mouse(edge+Vector2(3,0),false);await settle()
	check(doc.signature()==original,"循环边界小于6像素不编辑")
	mouse(edge,true);motion(edge+Vector2(35,0));await settle();check(doc.signature()!=original,"循环边界候选实时预览")
	var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true;root.push_input(escape,true);mouse(edge,false);await settle()
	check(doc.signature()==original,"Esc 取消循环边界")
	mouse(edge,true);motion(edge+Vector2(35,0));mouse(edge+Vector2(35,0),false);await settle()
	check(doc.signature()!=original,"循环边界松手提交")
	workspace._undo_action();await settle();check(doc.signature()==original,"一次撤销恢复循环边界")
	workspace._change_cycle_field(360,"cycle_end");workspace._cancel_cycle_edit();await settle()
	check(doc.signature()==original,"精确输入候选可取消")
	workspace._change_cycle_field(360,"cycle_end");workspace._finish_cycle_edit();await settle()
	check(workspace.save_document(),"保存循环范围")
	var reopened:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as StageBackgroundDefinition
	check(reopened.layers[0].sublayers[0].cycle_end==360 and reopened.layers[0].sublayers[0].continuity_id=="ground","重开保留范围和对应身份")
	var saved:Array=doc.signature();var pan:Vector2=surface.pan
	workspace._start_cycle_preview(load("res://tests/fixtures/environment/b.tres"));workspace._playing=false;surface.song_time=3.0;surface.refresh();surface.update_sample();await settle()
	check(surface.controller.environment!=null,"制作端调用正式拼接器")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(output.path_join("preview.png"))
	workspace._end_cycle_preview();await settle()
	check(doc.signature()==saved and surface.pan==pan,"衔接预览不写资源且恢复视图")
	workspace.queue_free();await settle()
	print("ENVIRONMENT AUTHORING failures=",failures);quit(1 if failures else 0)
