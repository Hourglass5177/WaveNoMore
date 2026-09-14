extends SceneTree
## 从窗口文件拖放开始，验证外部 SpriteFrames 的依赖、默认动作和实际预览实例。
var failures:=0
func _initialize() -> void:run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:failures+=1;printerr("FAIL: "+label)
func settle() -> void:
	for frame in 5:await process_frame
func run() -> void:
	var output:=ProjectSettings.globalize_path("res://").path_join("../Levels/output/reliability/spriteframes-drop").simplify_path()
	var source:=output.path_join("source");var target:=output.path_join("level")
	DirAccess.make_dir_recursive_absolute(source);DirAccess.make_dir_recursive_absolute(target)
	var file:=FileAccess.open(source.path_join("project.godot"),FileAccess.WRITE);file.store_string("config_version=5\n");file.close()
	file=FileAccess.open(source.path_join("sheet.svg"),FileAccess.WRITE);file.store_string('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="32"><rect width="32" height="32" fill="red"/><rect x="32" width="32" height="32" fill="blue"/></svg>');file.close()
	file=FileAccess.open(source.path_join("actor.tres"),FileAccess.WRITE)
	file.store_string('''[gd_resource type="SpriteFrames" load_steps=4 format=3]
[ext_resource type="Texture2D" path="res://sheet.svg" id="1"]
[sub_resource type="AtlasTexture" id="Red"]
atlas = ExtResource("1")
region = Rect2(0, 0, 32, 32)
[sub_resource type="AtlasTexture" id="Blue"]
atlas = ExtResource("1")
region = Rect2(32, 0, 32, 32)
[resource]
animations = [{"frames": [], "loop": true, "name": &"default", "speed": 5.0}, {"frames": [{"duration": 1.0, "texture": SubResource("Red")}, {"duration": 2.0, "texture": SubResource("Blue")}], "loop": true, "name": &"walk", "speed": 10.0}]
''');file.close()
	var workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate()
	workspace.offer_recovery_on_start=false;workspace.recovery_path="user://level-tests/spriteframes-drop.json";root.add_child(workspace);await settle()
	workspace.document.reset(LevelFormat.new_level(),target);await settle()
	# 发出操作系统拖入所接的窗口信号，而不是直接调用动画编解码器。
	workspace.get_window().files_dropped.emit(PackedStringArray([source.path_join("actor.tres")]))
	await settle()
	var dialogs: Array=workspace.get_children().filter(func(node):return node.scene_file_path=="res://scenes/tools/level_studio/animation_import.tscn")
	check(dialogs.size()==1,"拖入 SpriteFrames 打开动画依赖导入窗口")
	if dialogs.is_empty():workspace.queue_free();await settle();quit(failures);return
	var dialog=dialogs[0]
	while dialog._busy:await process_frame
	check(dialog.action=="walk" and dialog.get_node("%Preview").texture!=null,"跳过空 default，导入前实际显示素材帧")
	check(not FileAccess.file_exists(target.path_join("assets/actor.tres")),"不把原始 tres 当普通文件复制")
	var imported:=[""];dialog.imported.connect(func(path):imported[0]=path);await dialog._write();await settle()
	check(not imported[0].is_empty(),"确认后生成独立动画描述")
	if imported[0].is_empty():workspace.queue_free();await settle();quit(failures);return
	# 隔离来源，后续预览和重新装配只能依赖工程里的图片。
	DirAccess.rename_absolute(source.path_join("sheet.svg"),source.path_join("sheet.unavailable"))
	workspace.seek(1000000)
	var listed:=false
	for index in workspace._asset_list.item_count:
		if workspace._asset_list.get_item_metadata(index)==imported[0]:listed=true
	check(listed,"确认后动画出现在素材栏")
	workspace.surface._drop_data(workspace.surface.to_view(Vector2(960,540)),{"level_asset":imported[0]});await settle()
	var objects: Array=workspace.document.entries("objects");var tracks: Array=workspace.document.entries("tracks")
	check(objects.size()==1 and objects[0].type=="animated_sprite" and objects[0].animation=="walk","拖入预览创建可播放动作对象")
	check(tracks.size()==1 and tracks[0].clips[0].start_us==1000000 and tracks[0].clips[0].action=="walk","同时在当前游标创建动作片段")
	if objects.size()==1:
		workspace.seek(1150000);await settle()
		var sprite: AnimatedSprite2D=workspace.show_player().objects[objects[0].id].get_node("Content")
		check(sprite.is_visible_in_tree() and sprite.frame==1 and sprite.sprite_frames.get_frame_texture("walk",1).get_image().get_pixel(8,8).b>0.9,"来源图片不可用时，预览仍显示动作第二帧")
		if DisplayServer.get_name()!="headless":
			# 放大测试对象以检查真正绘出的帧，避免 32px 素材缩小后被选框覆盖。
			workspace.set_property("scale",[8.0,8.0]);await settle()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("spriteframes-preview.png"))
			var rendered: Image=workspace.viewport.get_texture().get_image()
			var center:=rendered.get_pixel(rendered.get_width()/2,rendered.get_height()/2)
			check(center.b>0.9 and center.r<0.1,"GPU 预览实际绘出蓝色第二帧")
			workspace.document.undo();await settle()
		workspace.document.undo();await settle();check(workspace.document.entries("objects").is_empty() and workspace.document.entries("tracks").is_empty(),"对象和动作片段一次撤销")
		workspace.document.undo(true);await settle();check(workspace.document.entries("objects").size()==1,"重做恢复动画对象")
	var library:=LevelAssetLibrary.new();library.configure(target,[])
	var frames:=library.resolve(imported[0]) as SpriteFrames
	check(frames!=null and frames.get_frame_count("walk")==2 and is_equal_approx(frames.get_frame_duration("walk",1),2.0),"独立装配保留图集区域和帧时长")
	DirAccess.rename_absolute(source.path_join("sheet.unavailable"),source.path_join("sheet.svg"))
	workspace.queue_free();await settle();print("LEVEL SPRITEFRAMES DROP failures=",failures);quit(failures)
