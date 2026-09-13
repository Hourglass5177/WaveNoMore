extends SceneTree
## 真实 Viewport 输入与 GPU 像素配对；不以计算出的排序值代替画面检查。
var failures:=0
var output:=ProjectSettings.globalize_path("res://").path_join("../Levels/output/editor-fixes").simplify_path()
var workspace
func _initialize() -> void:run.call_deferred()
func check(value: bool, label: String) -> void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures+=1
func settle(count:=6) -> void:
	for index in count:await process_frame
func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
func pointer(at: Vector2, pressed: bool) -> void:
	var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
func motion(at: Vector2) -> void:
	var event:=InputEventMouseMotion.new();event.position=at;event.global_position=at;event.button_mask=MOUSE_BUTTON_MASK_LEFT;event.alt_pressed=true;root.push_input(event,true)
func square(parent: Node, color: Color) -> Polygon2D:
	var result:=Polygon2D.new();result.polygon=PackedVector2Array([Vector2(-60,-60),Vector2(60,-60),Vector2(60,60),Vector2(-60,60)]);result.color=color;parent.add_child(result);return result
func pixel(color: Color, label: String) -> void:
	await settle();await capture(label)
	if DisplayServer.get_name()!="headless":check(root.get_texture().get_image().get_pixel(320,180).is_equal_approx(color),label)
func button(node: Node, caption: String) -> Button:
	if node is Button and node.text==caption:return node
	for child in node.get_children():
		var found:=button(child,caption)
		if found!=null:return found
	return null
func press_inspector(caption: String) -> void:
	var control:=button(workspace.inspector,caption)
	check(control!=null,"可找到按钮："+caption)
	if control==null:return
	workspace._inspector_scroll.ensure_control_visible(control);await settle()
	var at:=control.get_global_rect().get_center();pointer(at,true);pointer(at,false);await settle()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(output);root.size=Vector2i(1280,720)
	workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate();workspace.offer_recovery_on_start=false;workspace.recovery_path=output.path_join("ui-recovery.json");root.add_child(workspace);await settle()
	workspace._ui_scale=1;workspace._apply_ui_scale();workspace.add_object("text");await settle()
	var id: String=workspace.selection[0]
	for auto in [false,true]:
		workspace.auto_key=auto
		var position: Vector2=workspace.show_player().objects[id].position
		var at: Vector2=workspace.surface.global_position+workspace.surface.to_view(position)
		var cursor: int=workspace.document.cursor
		pointer(at,true);motion(at+Vector2(35,0));await settle()
		var candidate: Vector2=workspace.show_player().objects[id].position
		check(not candidate.is_equal_approx(position),"拖动实时预览 auto="+str(auto))
		pointer(at+Vector2(35,0),false);await settle()
		check(candidate.is_equal_approx(workspace.show_player().objects[id].position) and workspace.document.cursor==cursor+1,"候选与一次提交一致 auto="+str(auto))
	workspace.auto_key=false
	var at: Vector2=workspace.surface.global_position+workspace.surface.to_view(workspace.show_player().objects[id].position)
	var cursor: int=workspace.document.cursor
	pointer(at,true);motion(at+Vector2(40,0));await settle()
	var escape:=InputEventKey.new();escape.pressed=true;escape.keycode=KEY_ESCAPE;root.push_input(escape,true);await settle()
	check(workspace.document.cursor==cursor and workspace._candidate_objects.is_empty(),"Esc 取消动画整体拖动")
	pointer(at,false)
	var selected_track: Dictionary=workspace.document.entries("tracks")[0]
	workspace.select_objects(PackedStringArray([id]),selected_track.id);await settle()
	await press_inspector("删除对象")
	check(workspace.document.find("objects",id).is_empty(),"09 轨道上下文的删除对象按钮")
	workspace.document.undo();await settle()
	check(workspace.selection==PackedStringArray([id]) and workspace.selected_track==selected_track.id,"09 删除撤销同时恢复选区")
	workspace.document.directory=output.path_join("roundtrip");workspace._show_signature="";workspace._update_show();await settle()
	var animation: String=""
	for asset: String in workspace.assets().list_files():
		if asset.ends_with(LevelAnimationAsset.SUFFIX):animation=asset;break
	workspace.add_asset_object(animation);await settle()
	var animated_id: String=workspace.selection[0]
	await press_inspector("清除引用")
	check(workspace.show_player().objects[animated_id].get_node_or_null("Content")==null,"05 清除引用按钮留下可绑定空对象")
	workspace.document.undo();await settle()
	workspace.select_objects(PackedStringArray([id]));await settle()
	workspace._choose_resource("animation",animation,func(_value):pass);await settle()
	await capture("animation-picker")
	for child in workspace.get_children():
		if child is ConfirmationDialog:child.hide();child.queue_free()
	await settle()
	workspace.import_animation();await settle()
	for child in workspace.get_children():
		if child is ConfirmationDialog and child.has_method("slice_sheet"):
			await child.load_resource("res://assets/image/animation/monkey/monkey.tres");await settle();await capture("animation-import")
			child.source_sheet=child.frames.get_frame_texture(child.action,0);child.get_node("%SheetSettings").show();await settle();await capture("animation-sheet")
			child.hide();child.queue_free()
	await settle()
	for size in [Vector2i(1024,720),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(3440,1440)]:
		root.size=size;workspace._ui_scale=0;workspace._apply_ui_scale();await settle(12)
		check(workspace.surface.to_world(workspace.surface.to_view(Vector2(711,432))).distance_to(Vector2(711,432))<0.01,"画布命中 "+str(size))
		await capture("workspace-%d"%size.x)
	for scale in [1.0,1.5,2.0]:
		root.size=Vector2i(2560,1440);workspace._ui_scale=scale;workspace._apply_ui_scale();await settle(12)
		check(is_equal_approx(root.content_scale_factor,scale),"界面倍率 "+str(scale))
		await capture("scale-%d"%int(scale*100))
	if DisplayServer.get_name()!="headless":
		root.mode=Window.MODE_MAXIMIZED;await settle(15);await capture("maximized")
		root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720);await settle(15)
	workspace._open_path("res://examples/level-studio/渡口演出/level.json");await settle(30)
	root.grab_focus();await settle(10)
	print("SPACE window_has_focus=",root.has_focus()," background=",workspace._background)
	workspace._mode_buttons.move.grab_focus()
	var space:=InputEventKey.new();space.pressed=true;space.keycode=KEY_SPACE;root.push_input(space,true);await settle(2)
	check(workspace.audio.playing,"工具按钮焦点 Space 经 Viewport 播放")
	workspace.audio.set_playing(false);workspace.queue_free();await settle()
	root.size=Vector2i(640,360);root.content_scale_factor=1
	var controller:=ParallaxController.new();root.add_child(controller);await settle()
	var layer=controller._get_sublayer(4,"test");var backdrop:=square(layer,Color.BLUE);backdrop.position=Vector2(320,180)
	var player:=LevelShowPlayer.new();root.add_child(player)
	var object_data:=LevelFormat.object("sprite");object_data.fields.position=[320,180];object_data.depth=4;object_data.occlusion_depth=4;object_data.occlusion_order="back"
	player.configure({"objects":[object_data],"tracks":[]},"",[],"");player.environment_controller=controller
	var content:=square(player.objects[object_data.id],Color.RED);content.z_index=4000
	player.seek("song",0);await pixel(Color.BLUE,"01-background-back")
	player.show.objects[0].occlusion_order="front";player.seek("song",0);await pixel(Color.RED,"07-background-front")
	var foreground=controller._get_sublayer(-2,"negative");var front_background:=square(foreground,Color.BLUE);front_background.position=Vector2(320,180)
	player.show.objects[0].occlusion_depth=-2;player.show.objects[0].occlusion_order="back";player.seek("song",0);await pixel(Color.BLUE,"07-negative-back")
	player.show.objects[0].occlusion_order="front";player.seek("song",0);await pixel(Color.RED,"07-negative-front")
	front_background.queue_free();await settle()
	controller.get_sublayer_velocity(4,"test");check(controller._layers[4].get_children().all(func(child):return child is ParallaxController.SubLayer),"背景子层不混入演出对象")
	player.show.objects[0].occlusion_order="none";player.show.objects[0].occlusion_inherit=false;player.seek("song",0)
	check(player.objects[object_data.id].get_parent()==player,"不参与归还宿主")
	player.show.objects[0].occlusion_order="back";player.show.objects[0].layer="hud";player.seek("song",0)
	check(player.objects[object_data.id].get_parent()==player,"HUD 归还宿主")
	var hud:=LevelFormat.object("sprite");hud.layer="hud";hud.fields.position=[320,180]
	object_data.layer="world";object_data.occlusion_order="none";object_data.occlusion_inherit=false
	player.configure({"objects":[hud,object_data],"tracks":[]},"",[],"")
	square(player.objects[hud.id],Color.GREEN);square(player.objects[object_data.id],Color.RED)
	await pixel(Color.GREEN,"08-hud-pick")
	var surface:=LevelPreviewSurface.new();surface.player=player;surface.document=LevelDocument.new();var data:=LevelFormat.new_level();data.show=player.show;surface.document.reset(data);root.add_child(surface)
	check(surface.objects_at(Vector2(320,180))[0]==hud.id,"可见像素与最上层拾取一致")
	data.show.objects[0].locked=true;surface.document.reset(data)
	check(surface.objects_at(Vector2(320,180))[0]==object_data.id,"锁定对象不参与拾取")
	surface.queue_free()
	player.show.objects[1].occlusion_order="front";player.show.objects[1].occlusion_depth=4;player.seek("song",0)
	controller.free();await settle()
	check(is_instance_valid(player.objects[object_data.id]) and player.objects[object_data.id].get_parent()==player,"控制器销毁归还播放器对象")
	player.queue_free();await settle()
	print("EDITOR FIXES UI failures=",failures);quit(failures)
