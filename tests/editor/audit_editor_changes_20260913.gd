extends SceneTree
## 审计复现：记录实际行为，不修改正式工程；画面和日志留在 Levels/output。
var output := ProjectSettings.globalize_path("res://").path_join("../Levels/output/editor-audit-20260913").simplify_path()
var workspace
func _initialize() -> void: run.call_deferred()
func settle(count := 5) -> void:
	for index in count: await process_frame
func note(label: String, value: Variant) -> void: print("AUDIT ", label, " = ", value)
func pointer(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
	root.push_input(event,true)
func move(at: Vector2) -> void:
	var event := InputEventMouseMotion.new();event.position=at;event.global_position=at;event.button_mask=MOUSE_BUTTON_MASK_LEFT
	root.push_input(event,true)
func find_button(node: Node, caption: String) -> Button:
	if node is Button and node.text==caption:return node
	for child in node.get_children():
		var found := find_button(child,caption)
		if found!=null:return found
	return null
func close_dialogs() -> void:
	for child in workspace.get_children():
		if child is Window:child.hide()
func capture(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
func run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	var library := LevelAssetLibrary.new();library.configure("res://assets/image/animation",[])
	note("relative_animation_resolves",library.resolve("assets/monkey.tres")!=null)
	note("fallback_animation_resolves",library.resolve("assets/image/animation/monkey/monkey.tres")!=null)
	var frames_path := "res://assets/image/animation/monkey/monkey.tres"
	var frames := library.resolve(frames_path) as SpriteFrames
	note("direct_animation_frames",frames.get_frame_count("default"))
	var player := LevelShowPlayer.new();root.add_child(player)
	var animated := LevelFormat.object("animated_sprite",frames_path);animated.animation="default"
	player.configure({"objects":[animated],"tracks":[]},"",[],"")
	player.advance("song",450000,false)
	note("animation_at_450ms",player.objects[animated.id].get_node("Content").frame)
	var track := LevelFormat.track(animated.id,"action","song","action")
	var clip := LevelFormat.clip(0,"",2000000);clip.action="default";track.clips=[clip]
	player.show.tracks=[track];player.seek("song",450000)
	note("animation_with_explicit_action_at_450ms",player.objects[animated.id].get_node("Content").frame)
	player.queue_free();await settle()
	root.size=Vector2i(1280,720)
	workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate();workspace.offer_recovery_on_start=false;workspace.recovery_path=output.path_join("recovery.json")
	root.add_child(workspace);await settle(10)
	workspace._ui_scale=1;workspace._apply_ui_scale();workspace.add_object("text");await settle()
	var id: String=workspace.selection[0]
	for auto in [false,true]:
		workspace.auto_key=auto;workspace.surface.record_at_cursor=true
		var at: Vector2=workspace.surface.global_position+workspace.surface.to_view(Vector2(960,540))
		pointer(at,true);move(at+Vector2(55,0));await settle()
		note("drag_candidate_auto_"+str(auto),workspace.show_player().objects[id].position)
		pointer(at+Vector2(55,0),false);await settle();close_dialogs();await settle()
		note("drag_committed_auto_"+str(auto),workspace.document.find("objects",id).fields.position)
		note("drag_track_count_auto_"+str(auto),workspace.document.entries("tracks").size())
	workspace.auto_key=false;workspace.key_property("position");await settle()
	var at: Vector2=workspace.surface.global_position+workspace.surface.to_view(Vector2(960,540))
	pointer(at,true);move(at+Vector2(55,0));await settle()
	note("existing_key_live_position",workspace.show_player().objects[id].position)
	pointer(at+Vector2(55,0),false);await settle()
	note("existing_key_committed_position",workspace.show_player().objects[id].position)
	# 轨道标题会展示对象属性；明确的“删除对象”按钮应删除对象。
	var selected_track: Dictionary=workspace.document.entries("tracks")[0]
	workspace.select_objects(PackedStringArray([id]),selected_track.id);await settle()
	note("track_title_edit_target",workspace.edit_target)
	var delete_button := find_button(workspace.inspector,"删除对象")
	note("delete_button_on_track_title",delete_button!=null)
	if delete_button!=null:delete_button.pressed.emit();await settle()
	note("object_survives_delete_object_button",not workspace.document.find("objects",id).is_empty())
	workspace.select_objects(PackedStringArray([id]));await settle();await capture("workspace-1280")
	root.size=Vector2i(1920,1080);workspace._ui_scale=0;workspace._apply_ui_scale();await settle(10);await capture("workspace-1920-auto")
	workspace.queue_free();await settle()
	# 渲染像素与实际拾取同时检查，避免仅以排序数字判断遮挡。
	root.size=Vector2i(640,360);root.content_scale_factor=1
	var controller := ParallaxController.new();root.add_child(controller);await settle()
	var sublayer = controller._get_sublayer(4,"audit")
	var backdrop := Polygon2D.new();backdrop.polygon=PackedVector2Array([Vector2.ZERO,Vector2(640,0),Vector2(640,360),Vector2(0,360)]);backdrop.color=Color.BLUE;sublayer.add_child(backdrop)
	player=LevelShowPlayer.new();root.add_child(player)
	var obj := LevelFormat.object("sprite");obj.fields.position=[320,180];obj.depth=4;obj.occlusion_depth=4;obj.occlusion_order="back"
	player.configure({"objects":[obj],"tracks":[]},"",[],"");player.environment_controller=controller
	var square := Polygon2D.new();square.polygon=PackedVector2Array([Vector2(-50,-50),Vector2(50,-50),Vector2(50,50),Vector2(-50,50)]);square.color=Color.RED;player.objects[obj.id].add_child(square)
	player.seek("song",0);await settle();await capture("back-depth4")
	if DisplayServer.get_name()!="headless": note("back_depth4_center_pixel",root.get_texture().get_image().get_pixel(320,180))
	player.show.objects[0].occlusion_order="none";player.seek("song",0)
	note("none_returns_to_player",player.objects[obj.id].get_parent()==player)
	# 已创建的深度本应仍能查询子层，现在遍历会撞到外部 Node2D。
	note("begin_sublayer_lookup_after_occlusion",true)
	controller.get_sublayer_velocity(4,"audit")
	note("end_sublayer_lookup_after_occlusion",true)
	player.configure({"objects":[],"tracks":[]},"",[],"");player.queue_free();controller.queue_free();await settle()
	await extra_probes()
	# 单独复现清除动画引用，避免重复错误掩盖前面的输出。
	player=LevelShowPlayer.new();root.add_child(player)
	animated.asset="";animated.animation=""
	note("begin_empty_animation_reference",true)
	player.configure({"objects":[animated],"tracks":[]},"",[],"")
	player.queue_free();await settle();note("finished",true);quit()

func extra_probes() -> void:
	# HUD 实际盖住世界对象，但新排序是否仍能拾取最上面的对象？
	var player := LevelShowPlayer.new();root.add_child(player)
	var hud := LevelFormat.object("sprite");hud.layer="hud";hud.fields.position=[320,180]
	var world := LevelFormat.object("sprite");world.depth=5;world.fields.position=[320,180]
	var level := LevelFormat.new_level();level.show.objects=[hud,world]
	player.configure(level.show,"",[],"")
	for pair in [[hud,Color.GREEN],[world,Color.RED]]:
		var polygon := Polygon2D.new();polygon.polygon=PackedVector2Array([Vector2(-60,-60),Vector2(60,-60),Vector2(60,60),Vector2(-60,60)]);polygon.color=pair[1];player.objects[pair[0].id].add_child(polygon)
	await settle();await capture("hud-pick-order")
	if DisplayServer.get_name()!="headless":note("hud_center_pixel",root.get_texture().get_image().get_pixel(320,180))
	var surface := LevelPreviewSurface.new();surface.size=Vector2(640,360);surface.player=player;surface.document=LevelDocument.new();surface.document.reset(level);root.add_child(surface);await settle()
	var event := InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=surface.to_view(Vector2(320,180));surface._gui_input(event)
	note("visible_hud_but_picks_world",surface.selected==PackedStringArray([world.id]))
	surface.cancel_drag();surface.queue_free();player.queue_free();await settle()
	# 用正式环境采样复现结构冲突，不只测试手工查询。
	var controller := ParallaxController.new();root.add_child(controller);await settle()
	var sequence := StageEnvironmentSequence.new()
	sequence.build(load("res://tests/fixtures/environment/a.tres"),[],Callable(),"",Vector3i(0,10000000,0))
	controller.set_environment(sequence)
	var outside := Node2D.new();root.add_child(outside);controller.set_object_occlusion(outside,1,"back")
	note("begin_environment_sample_after_occlusion",true);controller.sample_environment(1000000);note("end_environment_sample_after_occlusion",true)
	controller.queue_free();await settle()
	for path in ["res://content/backgrounds/s00_grave_background.tres","res://content/backgrounds/s02_grave2_background.tres","res://content/backgrounds/s02_grave2_background2.tres"]:
		controller=ParallaxController.new();root.add_child(controller);await settle()
		note("background_validation_"+path.get_file(),controller.configure(load(path),false))
		controller.queue_free();await settle()
	var source := "res://assets/image/animation/monkey/monkey.tres"
	var imported := LevelProjectIO.import_file(source,output.path_join("imported"))
	level=LevelFormat.new_level();level.show.objects=[LevelFormat.object("animated_sprite",imported.path)]
	note("imported_animation_dependencies",LevelProjectIO.dependencies(level,output.path_join("imported")))
