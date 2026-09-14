extends SceneTree
## 连续操作回归：使用真实表单和工作区命令，测试目录与用户工程分离。
var failures := 0
var workspace
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; printerr("FAIL: ", label)
func settle() -> void:
	for i in 4: await process_frame
func run() -> void:
	workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate()
	workspace.offer_recovery_on_start=false; workspace.recovery_path="user://level-tests/reliability.json"; root.add_child(workspace); await settle()
	var a:=LevelFormat.object("sprite"); a.fields.position=[100.0,200.0]
	var b:=LevelFormat.object("sprite"); b.fields.position=[300.0,400.0]
	var data:=LevelFormat.new_level(); data.show.objects=[a,b]; workspace.document.reset(data)
	workspace.select_objects(PackedStringArray([a.id,b.id])); await settle()
	for row in workspace.inspector.get_children():
		if row is HBoxContainer and row.get_child(0) is Label and row.get_child(0).text.begins_with("位置"):
			row.get_child(1).value=500; break
	LevelUI.finish_fields(workspace.inspector); workspace.document.end_edit(); await settle()
	check(workspace.document.find("objects",b.id).fields.position==[500.0,400.0],"多选只改 X 保留第二对象 Y")
	workspace.document.undo(); await settle()
	check(workspace.document.find("objects",b.id).fields.position==[300.0,400.0],"撤销恢复多选位置")
	workspace.document.set_key(a.id,"opacity","song",1000000,0.4,"normal")
	var source: Dictionary=workspace.document.entries("tracks")[0].duplicate(true)
	workspace.select_objects(PackedStringArray([a.id]),source.id,source.keys[0].id); workspace.timeline.difficulty="normal"; workspace.timeline.copy_selected()
	workspace.set_section("intro"); workspace.timeline.difficulty="hard"; workspace.timeline.time_us=2000000
	workspace.timeline.paste_selected(); await settle()
	check(workspace.document.find("tracks",source.id)==source,"跨段粘贴不修改来源轨")
	var targets: Array=workspace.document.entries("tracks").filter(func(t):return t.section=="intro" and t.difficulties==["hard"])
	check(targets.size()==1 and targets[0].keys[0].time_us==2000000,"专属事件粘贴到当前区段及难度")
	workspace.document.undo(); await settle()
	workspace.set_track_field(source.id,"locked",true)
	var old: Dictionary=workspace.document.find("tracks",source.id).duplicate(true)
	workspace.set_item_field(source.id,source.keys[0].id,"value",0.8)
	check(workspace.document.find("tracks",source.id)==old,"锁定轨道拒绝数值编辑")
	workspace.select_objects(PackedStringArray(),"@environment")
	workspace._show_inspector("level")
	check(workspace.inspector.get_child(0).text=="关卡设置","环境选区不拦截关卡设置入口")
	var folder:=ProjectSettings.globalize_path("res://").path_join("../Levels/output/reliability/fixtures").simplify_path()
	DirAccess.make_dir_recursive_absolute(folder.path_join("source1"));DirAccess.make_dir_recursive_absolute(folder.path_join("source2"))
	for index in [1,2]:
		var file:=FileAccess.open(folder.path_join("source%d/same.svg"%index),FileAccess.WRITE)
		file.store_string('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><rect width="16" height="16" fill="'+("red" if index==1 else "blue")+'"/></svg>');file.close()
	var first:=LevelProjectIO.import_file(folder.path_join("source1/same.svg"),folder)
	var second:=LevelProjectIO.import_file(folder.path_join("source2/same.svg"),folder)
	check(first.path!=second.path and FileAccess.get_file_as_string(folder.path_join(first.path)).contains("red"),"同名普通素材导入保留旧版本")
	var template_object:=LevelFormat.object("sprite",first.path)
	var template_track:=LevelFormat.track(template_object.id,"font","intro");template_track.keys=[LevelFormat.key(0,"assets/template-font.ttf")]
	data=LevelFormat.new_level();data.show.sequences=[{"id":"template","name":"模板","objects":[template_object],"tracks":[template_track]}]
	var dependencies:=LevelProjectIO.dependencies(data,folder)
	check(first.path in dependencies and "assets/template-font.ttf" in dependencies,"模板及字体关键帧纳入依赖")
	var player:=LevelShowPlayer.new();root.add_child(player)
	var visual:=LevelFormat.object("sprite",first.path);var other:=LevelFormat.object("sprite",first.path)
	var sound:=LevelFormat.object("audio");var sound_track:=LevelFormat.track(sound.id,"audio","song","audio")
	var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=22050;stream.data=PackedByteArray();var bytes:=PackedByteArray();bytes.resize(44100*3);stream.data=bytes
	stream.save_to_wav(folder.path_join("sound.wav"))
	var imported_sound:=LevelProjectIO.import_file(folder.path_join("sound.wav"),folder)
	var clip:=LevelFormat.clip(0,imported_sound.path,3000000);sound_track.clips=[clip]
	var show:={"objects":[visual,other,sound],"tracks":[sound_track],"bindings":[]}
	player.configure(show,folder,[],"normal");player.playing=true;player.advance("song",100000)
	var sound_instance=player.sounds.get(clip.id);var visual_instance=player.objects[other.id]
	show=show.duplicate(true);show.objects[0].fields.color="ff0000ff";player.show=show.duplicate(true);player.refresh_visuals("song",100000)
	check(player.sounds.get(clip.id)==sound_instance and is_instance_valid(sound_instance),"视觉重采样保留声音实例")
	var changed_instance=player.objects[visual.id]
	show.objects[0].asset=second.path;player.update_show(show,folder,[],"normal");player.refresh_visuals("song",100000)
	check(player.objects[other.id]==visual_instance and player.sounds.get(clip.id)==sound_instance,"替换单对象不重建其他对象或声音")
	check(player.objects[visual.id]!=changed_instance,"确实重建被替换素材的对象")
	player.queue_free();await settle()
	# 多选取消、批量锁定和历史选区恢复。
	data=LevelFormat.new_level();data.show.objects=[a.duplicate(true),b.duplicate(true)];workspace.document.reset(data,folder);workspace.select_objects(PackedStringArray([a.id,b.id]));await settle()
	workspace.document.begin_edit();workspace.set_property_component("scale",1,2);workspace.document.end_edit(true);await settle()
	check(workspace.document.find("objects",a.id).fields.scale==a.fields.scale,"取消大小 Y 调整恢复文档")
	workspace.select_objects(PackedStringArray([a.id]));await settle()
	for row in workspace.inspector.get_children():
		if row.get_meta("caption","")=="大小":
			var spin: SpinBox=row.get_child(2);spin.get_line_edit().grab_focus();spin.value=3
			var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true;spin.get_line_edit().gui_input.emit(escape);await settle()
			check(is_equal_approx(spin.value,1) and spin.get_line_edit().text=="1.0","Esc 同时恢复正在输入的数值控件")
	workspace.select_objects(PackedStringArray([b.id]));workspace.set_object_field("locked",true);workspace.select_objects(PackedStringArray([a.id,b.id]))
	var cursor: int=workspace.document.cursor;workspace.set_base_property("position",[900,900])
	check(workspace.document.cursor==cursor and workspace.document.find("objects",a.id).fields.position==a.fields.position,"批量包含锁定成员整次拒绝")
	workspace.select_objects(PackedStringArray([b.id]));workspace.set_object_field("locked",false);workspace.select_objects(PackedStringArray([a.id,b.id]));workspace.delete_objects();workspace.document.undo();await settle()
	check(workspace.selection==PackedStringArray([a.id,b.id]) and workspace.document.entries("objects").size()==2,"删除撤销恢复原选区")
	workspace.document.undo(true);await settle();check(workspace.selection.is_empty(),"重做删除恢复删除后的选区")
	workspace.document.undo();await settle()
	var group:=LevelFormat.object("group");group.fields.position=[700,500];workspace.document.replace("添加分组","objects",[],[group])
	var pose:=LevelShowSampler.object_transform(workspace.document.data.show,a.id,workspace.section,workspace.time_us,workspace.difficulty())
	workspace._rearrange_objects(PackedStringArray([a.id]),group.id,0);await settle()
	var moved:=LevelShowSampler.object_transform(workspace.document.data.show,a.id,workspace.section,workspace.time_us,workspace.difficulty())
	check(pose.origin.distance_to(moved.origin)<0.01 and workspace.document.find("objects",a.id).parent_id==group.id,"对象树更改父组保持显示变换")
	workspace.document.undo();await settle();check(workspace.document.find("objects",a.id).parent_id.is_empty(),"撤销父组调整恢复原层级")
	# 长动画层级计算可以从进度窗口取消，不提交半份候选。
	workspace.document.set_key(group.id,"position","song",5000000,[800,500])
	var before_bake: Dictionary=workspace.document.data.duplicate(true)
	var cancel_bake:=func():
		for child in workspace.get_children():
			if child is ConfirmationDialog and child.title=="保持动画并调整父组":child.canceled.emit()
	process_frame.connect(cancel_bake)
	await workspace._rearrange_objects(PackedStringArray([a.id]),group.id,0)
	process_frame.disconnect(cancel_bake);await settle()
	check(workspace.document.data==before_bake,"取消长动画父组调整不改变文档")
	workspace.document.undo();await settle()
	# 相同键时间粘贴保留目标稳定 ID 与插值，撤销恢复。
	workspace.set_section("song");workspace.document.set_key(a.id,"opacity","song",1000000,0.4)
	var copied: Dictionary=workspace.document.entries("tracks")[0];workspace.select_objects(PackedStringArray([a.id]),copied.id,copied.keys[0].id);workspace.timeline.copy_selected()
	workspace.document.set_key(a.id,"opacity","song",2000000,0.9);var target_id: String=workspace.document.find("tracks",copied.id).keys[1].id
	workspace.timeline.time_us=2000000;workspace.timeline.paste_selected();await settle()
	check(workspace.document.find("tracks",copied.id).keys.size()==2 and workspace.document.find("tracks",copied.id).keys[1].id==target_id and workspace.document.find("tracks",copied.id).keys[1].value==0.4,"同时间粘贴替换值并保留键 ID")
	workspace.document.undo();check(workspace.document.find("tracks",copied.id).keys[1].value==0.9,"撤销同时间粘贴恢复旧值")
	# 后台压缩可取消，最终输出只在完整关闭 ZIP 后发布。
	data=LevelFormat.new_level();data.show.objects=[template_object];data.song_path="song/song.json"
	var font_source:="C:/Windows/Fonts/arial.ttf"
	if FileAccess.file_exists(font_source):
		var imported_font:=LevelProjectIO.import_file(font_source,folder)
		var text:=LevelFormat.object("text");var font_track:=LevelFormat.track(text.id,"font","song");font_track.keys=[LevelFormat.key(0,imported_font.path)]
		data.show.sequences=[{"id":"font_template","name":"模板独占字体","objects":[text],"tracks":[font_track]}]

	LevelProjectIO.write_json(folder.path_join(data.song_path),{"charts":[]})
	var job=load("res://scenes/tools/level_studio/package_progress.tscn").instantiate();workspace.add_child(job)
	var package_path:=folder.path_join("template.zip");var error: String=await job.run_export(data,folder,package_path)
	check(error.is_empty(),"后台压缩完成")
	check(LevelProjectIO.unpack(package_path,folder.path_join("isolated")).is_empty(),"关卡包可解压到隔离目录")
	var isolated:=LevelProjectIO.open_project(folder.path_join("isolated/level.json"));check(isolated.error.is_empty() and FileAccess.file_exists(folder.path_join("isolated").path_join(first.path)),"隔离工程包含对象素材")
	if not data.show.get("sequences",[]).is_empty():
		var library:=LevelAssetLibrary.new();library.configure(folder.path_join("isolated"),[])
		check(library.resolve(data.show.sequences[0].tracks[0].keys[0].value) is Font,"模板独占字体关键帧在隔离目录可以装配")
	job.queue_free();await settle()
	check(LevelProjectIO.export_zip(data,folder,folder.path_join("cancelled.zip"),Callable(),func():return true)=="已取消" and not FileAccess.file_exists(folder.path_join("cancelled.zip")),"取消不发布半成品 ZIP")
	# 无音频审片边界以及开始编辑时固定目标。
	data=LevelFormat.new_level();data.intro_us=1000000;data.outro_us=1000000;data.show.objects=[a.duplicate(true)];workspace.document.reset(data,folder);workspace.timeline.waveform_duration=2;workspace.set_section("song");workspace.seek(500000)
	workspace.start_full_review();check(workspace.section=="intro","整关预览从曲前开始")
	workspace._review_position(1.0);check(workspace.section=="song","审片从曲前进入歌曲")
	workspace._review_position(2.0);check(workspace.section=="outro","无音频歌曲时按确定时长进入曲后")
	workspace.document.begin_edit();check(not workspace.audio.playing and not workspace._review.playing,"编辑开始先暂停审片")
	workspace.document.end_edit();workspace.end_full_review();check(workspace.section=="song" and workspace.time_us==500000 and not workspace.audio.playing,"退出审片恢复游标并保持暂停")
	# 重启会话往返保留未保存历史，不覆盖正式工程。
	var snapshot:={"level":workspace.document.data,"directory":folder,"history":workspace.document.history,"cursor":workspace.document.cursor,"saved_cursor":-1,"workspace":workspace._workspace_snapshot(),"selection":workspace._selection_snapshot(),"clipboard":{},"timeline_clipboard":[]}
	LevelProjectIO.write_json(folder.path_join("restart.json"),snapshot);workspace._resume_pack_session(folder.path_join("restart.json"));await settle()
	check(workspace.document.dirty and workspace.document.saved_cursor==-1,"重启恢复保留未保存状态")
	# 窄窗口代理菜单保留嵌套菜单、原索引信号与动态禁用状态。
	var toolbar=load("res://src/tools/level_studio/level_toolbar.gd").new();root.add_child(toolbar)
	var source_menu:=PopupMenu.new();var copied_menu:=PopupMenu.new();toolbar.add_child(source_menu);toolbar.add_child(copied_menu)
	var nested:=PopupMenu.new();nested.name="Nested";source_menu.add_child(nested);nested.add_check_item("轨道筛选",42);source_menu.add_submenu_item("视图",nested.name)
	var activated:=[-1];nested.index_pressed.connect(func(index):activated[0]=index)
	toolbar._copy_menu(copied_menu,source_menu)
	var proxy: PopupMenu=copied_menu.get_node(copied_menu.get_item_submenu(0));proxy.id_pressed.emit(42)
	nested.set_item_checked(0,true);nested.set_item_disabled(0,true);proxy.about_to_popup.emit()
	check(activated[0]==0 and proxy.is_item_checked(0) and proxy.is_item_disabled(0),"更多保留嵌套菜单命令与状态")
	toolbar.queue_free()
	workspace.queue_free(); await settle()
	print("LEVEL RELIABILITY failures=",failures); quit(failures)
