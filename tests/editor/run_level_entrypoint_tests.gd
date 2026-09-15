extends SceneTree
## 检查用户入口的实际回调、弹窗生命周期和最终文档，避免只测内部命令。
var failures:=0
var workspace
func _initialize() -> void:run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:failures+=1;printerr("FAIL: "+label)
func settle() -> void:
	for frame in 5:await process_frame
func click(control: Control) -> void:
	var viewport:=control.get_viewport();var point:=control.get_global_rect().get_center()
	if viewport is Window and viewport!=root and viewport.is_embedded():point+=Vector2(viewport.position);viewport=root
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=point;event.global_position=point;viewport.push_input(event,true)
func popup(title: String) -> Window:
	for child in workspace.get_children():
		if child is Window and child.title==title and child.visible:return child
	return null
func cancel(dialog: AcceptDialog) -> void:
	click(dialog.get_cancel_button() if dialog is ConfirmationDialog else dialog.get_ok_button());await settle()
func run() -> void:
	var output:=ProjectSettings.globalize_path("res://../Levels/output/entrypoints")
	DirAccess.make_dir_recursive_absolute(output)
	workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate();workspace.offer_recovery_on_start=false;workspace.recovery_path=output.path_join("recovery.json");root.add_child(workspace);await settle()
	workspace.document.reset(LevelFormat.new_level(),output);workspace.document.fields("测试修改",{"title":"入口回归"});await settle()
	workspace._recent=PackedStringArray();workspace._recent_projects();await settle()
	var recent: ConfirmationDialog=popup("最近工程");check(recent!=null and recent.get_ok_button().disabled,"最近工程空列表不能确认")
	await cancel(recent)
	workspace._write_recovery();workspace._show_recoveries();await settle()
	var recovery: ConfirmationDialog=popup("恢复工程草稿");check(recovery!=null and recovery.get_ok_button().disabled,"恢复稿未选中项目不能确认")
	await cancel(recovery);check(not workspace._autosave.is_stopped(),"取消恢复稿后自动恢复计时继续")
	workspace._open_path(output.path_join("missing-level.json"));await settle()
	check(not workspace._autosave.is_stopped() and workspace.document.data.title=="入口回归","打开失败不停止当前工程的自动恢复")
	await cancel(popup("关卡编辑器"))
	# 保存确认中的“不保存”继续打开文件选择器，不能留下另一个独占窗口。
	workspace._open();await settle();var discard: ConfirmationDialog=popup("保存未完成的关卡")
	var next_file:=[false]
	workspace.child_entered_tree.connect(func(node):
		if node is FileDialog and node.title=="打开关卡工程或关卡包":next_file[0]=not discard.visible,CONNECT_ONE_SHOT)
	for button in discard.find_children("*","Button",true,false):
		if button.text=="不保存":click(button);break
	await settle();check(next_file[0] and popup("打开关卡工程或关卡包")!=null,"不保存继续前先关闭旧独占窗口")
	await cancel(popup("打开关卡工程或关卡包"))
	# 非等长 SpriteFrames；空 default 不应使素材选择器预览空白。
	var frames:=SpriteFrames.new();frames.add_animation("walk");frames.set_animation_speed("walk",10)
	for spec in [[Color.RED,3],[Color.BLUE,1],[Color.GREEN,1]]:
		var image:=Image.create(32,32,false,Image.FORMAT_RGBA8);image.fill(spec[0]);frames.add_frame("walk",ImageTexture.create_from_image(image),spec[1])
	var imported:=await LevelAnimationAsset.write(frames,output,"入口动画")
	workspace._choose_resource("animation",imported.path,func(_value):pass);await settle()
	var picker=workspace.get_children().filter(func(node):return node.scene_file_path=="res://scenes/tools/level_studio/asset_picker.tscn")[0]
	check(picker._action=="walk" and picker.get_node("%Preview").texture!=null,"素材选择器跳过空默认动作")
	picker._step(1)
	check(is_equal_approx(picker._seconds,0.3) and picker.get_node("%Preview").texture.get_image().get_pixel(0,0).b>0.9,"素材选择器按实际帧时长逐帧")
	picker._seconds=1.1;picker._step(1);check(is_equal_approx(picker._seconds,0.3),"循环播放后仍从当前显示帧逐帧")
	picker._playing=true;picker.get_node("%Search").text="不存在的素材";picker.get_node("%Search").text_changed.emit("不存在的素材");await settle()
	check(not picker._playing and picker.get_node("%Preview").texture==null and picker.get_ok_button().disabled,"搜索无结果停止旧预览并清空画面")
	await cancel(picker)
	# 动画来源切换包含两层弹窗，确认后旧窗口退出再打开文件选择。
	workspace.import_animation();await settle()
	var animation=workspace.get_children().filter(func(node):return node.scene_file_path=="res://scenes/tools/level_studio/animation_import.tscn")[0]
	animation.frames=frames.duplicate(true);animation.action="walk";animation._refresh_actions();animation._refresh()
	for button in animation.get_node("%Sources").get_children():
		if button is Button and button.text=="Godot SpriteFrames":click(button);break
	await settle()
	var replace: ConfirmationDialog=animation.get_children().filter(func(node):return node is ConfirmationDialog)[0]
	check(replace.visible and replace.exclusive,"替换来源确认是独占子窗口")
	click(replace.get_ok_button());await settle()
	var source: FileDialog=animation.get_children().filter(func(node):return node is FileDialog)[0]
	check(source.visible and source.exclusive and source.title=="选择 SpriteFrames","来源确认后进入正确文件选择器")
	await cancel(source);check(animation.visible and animation.frames.get_frame_count("walk")==3,"取消来源选择保留候选帧")
	await cancel(animation)
	# 失败拖入不能给此前选中的对象偷偷添加显示片段。
	var object_data:=LevelFormat.object("sprite");workspace.document.replace("对象","objects",[],[object_data]);workspace.select_objects(PackedStringArray([object_data.id]));await settle()
	var before: Dictionary=workspace.document.data.duplicate(true);var cursor: int=workspace.document.cursor
	workspace._drop_timeline_asset("assets/missing.png",1000000);await settle()
	check(workspace.document.data==before and workspace.document.cursor==cursor,"失败拖入不修改既有对象与历史")
	check(not workspace._status.text.begins_with("已在当前区段"),"失败拖入不报告成功")
	await cancel(popup("关卡编辑器"))
	# 文件任务完成后切换完成提示，旧任务窗口必须先退出模态状态。
	LevelProjectIO.write_json(output.path_join("song/song.json"),{"charts":[]})
	await workspace._export_with_progress(output.path_join("entrypoints.zip"));await settle()
	check(popup("导出完成")!=null,"后台导出能进入完成提示")
	await cancel(popup("导出完成"))
	workspace._show_inspector("level");await settle()
	for row in workspace.inspector.get_children():
		if row.get_meta("caption","")=="标题":
			var edit: LineEdit=row.get_child(1);edit.grab_focus();edit.text="字段提交入口"
	var save_key:=InputEventKey.new();save_key.keycode=KEY_S;save_key.ctrl_pressed=true;save_key.pressed=true;root.push_input(save_key,true);await settle()
	check(LevelProjectIO.read_json(output.path_join("level.json")).get("title","")=="字段提交入口","文本框内 Ctrl+S 保存当前输入值")
	var final_document: LevelDocument=workspace.document;var saved_cursor:=final_document.cursor
	workspace.queue_free();await settle();check(final_document.cursor==saved_cursor,"界面销毁不把旧字段重新提交")
	print("LEVEL ENTRYPOINTS failures=",failures);quit(failures)
