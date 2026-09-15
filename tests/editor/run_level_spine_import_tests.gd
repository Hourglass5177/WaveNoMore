extends SceneTree
## 通过导入窗口确认、关卡对象及隔离目录采样验证骨骼素材全链路。
var failures:=0
func _initialize() -> void:run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:failures+=1;printerr("FAIL: "+label)
func settle() -> void:
	for frame in 5:await process_frame
func run() -> void:
	var output:=ProjectSettings.globalize_path("res://../Levels/output/spine-import")
	DirAccess.make_dir_recursive_absolute(output)
	DirAccess.copy_absolute("res://assets/bosses/animation_studies/snake/boss.spine-json",output.path_join("boss.json"))
	var json_source:=LevelSpineAsset.read_data(output.path_join("boss.json"),"res://assets/bosses/animation_studies/snake/boss.atlas")
	check(json_source.error.is_empty(),"普通 .json 扩展名也能读取 Spine 骨骼")
	var workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate()
	workspace.offer_recovery_on_start=false;workspace.recovery_path=output.path_join("recovery.json");root.add_child(workspace);await settle()
	workspace.document.reset(LevelFormat.new_level(),output)
	workspace.import_spine("res://assets/bosses/animation_studies/snake/boss.spine-json");await settle()
	var dialog=workspace.get_children().filter(func(node):return node.scene_file_path=="res://scenes/tools/level_studio/spine_import.tscn")[0]
	check(not dialog.get_ok_button().disabled,"工程已有 BOSS 骨骼和图集可导入")
	if dialog.get_ok_button().disabled:printerr(dialog.get_node("%Status").text);quit(1);return
	check(dialog.candidate.actions.size()>1,"读取真实骨骼动作列表")
	dialog.seconds=0.25;dialog._sample();dialog.settings.markers[dialog.settings.default_animation]=0.25
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		dialog.viewport.get_texture().get_image().save_png(output.path_join("spine-preview.png"))
	var selected_action: String=dialog.settings.default_animation
	var imported:=[""];dialog.imported.connect(func(path):imported[0]=path)
	# 确认按钮经实际 Viewport 事件派发，不直接调用写入函数。
	var button: Button=dialog.get_ok_button();var point:=button.get_global_rect().get_center()+Vector2(dialog.position)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;root.push_input(event,true)
	await settle();check(not imported[0].is_empty(),"点击确认完成导入")
	if imported[0].is_empty():quit(1);return
	var asset: String=imported[0]
	check(workspace.assets().list_files().has(asset),"素材栏列出骨骼描述")
	check(is_equal_approx(workspace.assets().release_time(asset,selected_action),0.25),"出手标记从素材读取")
	workspace.seek(1000000);check(workspace.add_asset_object(asset),"骨骼拖入创建演出对象")
	await settle()
	var object_id: String=workspace.selection[0]
	check(workspace.document.find("objects",object_id).type=="actor","骨骼沿用 actor 类型")
	check(workspace.document.entries("tracks").size()==1 and workspace.document.entries("tracks")[0].clips[0].start_us==1000000,"当前游标创建动作片段")
	workspace.boss_panel.object_id=object_id
	var defaults: Dictionary=workspace.boss_panel._defaults()
	check(defaults.action==selected_action and is_equal_approx(defaults.release_sec,0.25),"BOSS 草稿使用所选骨骼动作及出手标记")
	var player=workspace.show_player();check(player.drivers.has(object_id),"正式播放器接入骨骼驱动")
	var driver: LevelAnimationDriver=player.drivers[object_id]
	check(driver.spines.size()==1,"运行场景保留真实 Spine 骨骼")
	var clips:=[{"id":"test","action":selected_action,"loop":false,"weight":1.0,"local_us":500000}]
	driver.sample(clips,500000)
	var spine=driver.spines[0];var first=spine.get_skeleton().get_bones()[1].get_global_transform()
	clips[0].local_us=1000000;driver.sample(clips,1000000);clips[0].local_us=500000;driver.sample(clips,500000)
	check(first.is_equal_approx(spine.get_skeleton().get_bones()[1].get_global_transform()),"骨骼回拖与直接定位姿态一致")
	clips[0].action=workspace.assets().actions(asset)[1];driver.sample(clips,500000)
	check(spine.get_animation_state().get_track(0).get_animation().get_name()==clips[0].action,"同片段切换动作重置采样")
	var isolated:=output.path_join("isolated")
	LevelProjectIO.write_json(output.path_join("song/song.json"),{"charts":[]})
	var export_error:=LevelProjectIO.export_zip(workspace.document.data,output,output.path_join("spine.level.zip"))
	check(export_error.is_empty(),"ZIP 收集骨骼图集图片："+export_error)
	check(LevelProjectIO.unpack(output.path_join("spine.level.zip"),isolated).is_empty(),"ZIP 解压到隔离目录")
	var library:=LevelAssetLibrary.new();library.configure(isolated,[])
	check(library.resolve(asset) is PackedScene,"隔离目录不依赖原素材位置或导入缓存")
	workspace.document.undo();check(workspace.document.entries("objects").is_empty(),"对象与动作片段一次撤销")
	var files_before: PackedStringArray=workspace.assets().list_files()
	workspace.import_spine("res://assets/bosses/animation_studies/snake/boss.spine-json");await settle()
	var cancelled=workspace.get_children().filter(func(node):return node.scene_file_path=="res://scenes/tools/level_studio/spine_import.tscn")[0]
	var cancel_button: Button=cancelled.get_cancel_button();var cancel_point:=cancel_button.get_global_rect().get_center()+Vector2(cancelled.position)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=cancel_point;root.push_input(event,true)
	await settle();check(workspace.assets().list_files()==files_before,"取消导入不生成半成品素材")
	workspace.queue_free();await settle();print("LEVEL SPINE IMPORT failures=",failures);quit(failures)
