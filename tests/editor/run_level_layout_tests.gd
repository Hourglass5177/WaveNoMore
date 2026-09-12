extends SceneTree
## 验证窗口缩放、逻辑画布、弹窗和连续编辑；GPU 运行额外检查实际最大化。
var failures:=0
var checks:=0
func _initialize() -> void:_run.call_deferred()
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+label)
func settle(frames:=8) -> void:
	for frame in frames:await process_frame

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join("../Levels/output/ui").simplify_path())
	var workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate()
	workspace.offer_recovery_on_start=false;workspace.recovery_path="user://level-tests/layout-recovery.json"
	root.add_child(workspace);await settle()
	workspace._ui_scale=0.0
	workspace._open_path("res://examples/level-studio/渡口演出/level.json");await settle()
	workspace._reset_layout()
	for window_size in [Vector2i(1024,720),Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3440,1440)]:
		root.size=window_size;workspace._apply_ui_scale();await settle()
		check(root.content_scale_factor>=minf(root.size.x/1280.0,root.size.y/720.0),"自动倍率随窗口增长 "+str(window_size))
		check(workspace.surface.size.x>=320 and workspace.timeline.size.y>=120,"缩放后预览与时间线保持可用 "+str(window_size))
		check(absf(workspace._inspector_scroll.size.x-310)<20,"窗口变化保留属性栏逻辑宽度 "+str(window_size))
	workspace._ui_scale=1.0;root.size=Vector2i(1920,1080);workspace._apply_ui_scale();await settle()
	check(is_equal_approx(root.content_scale_factor,1.0),"手动倍率可保留更多工作空间")
	workspace._right_width=360;workspace._queue_layout();await settle()
	root.size=Vector2i(1280,720);await settle()
	check(absf(workspace._inspector_scroll.size.x-360)<20,"自定义侧栏宽度在还原窗口后保留")
	workspace._ui_scale=2.0;workspace._apply_ui_scale();await settle()
	check(is_equal_approx(root.content_scale_factor,1.0),"小窗口限制倍率以免控件被挤出")
	workspace._ui_scale=0.0;workspace._reset_layout();workspace.select_objects(PackedStringArray(["ferryman"]));await settle()
	var surface=workspace.surface
	var pointer:Vector2=surface.size*Vector2(0.7,0.6)
	var point:Vector2=surface.to_world(pointer)
	var wheel:=InputEventMouseButton.new();wheel.pressed=true;wheel.ctrl_pressed=true;wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.position=pointer
	surface._gui_input(wheel)
	check(surface.to_view(point).distance_to(pointer)<0.01,"预览滚轮围绕鼠标位置缩放")
	check(surface.to_world(surface.to_view(Vector2(711,432))).distance_to(Vector2(711,432))<0.01,"界面缩放后画布拾取坐标一致")
	var spin:SpinBox
	for row in workspace.inspector.get_children():
		for child in row.get_children():
			if child is SpinBox:spin=child;break
		if spin!=null:break
	spin.get_line_edit().grab_focus();var original_id:=spin.get_instance_id()
	spin.value+=1;await settle()
	check(is_instance_valid(spin) and spin.get_instance_id()==original_id and spin.get_line_edit().has_focus(),"连续数字编辑保留输入框及焦点")
	workspace.surface.grab_focus();workspace._set_transform_mode("rotate")
	check(workspace._mode_buttons.rotate.button_pressed and not workspace._mode_buttons.move.button_pressed,"当前操纵模式清晰高亮")
	workspace._mode_buttons.rotate.grab_focus()
	var space:=InputEventKey.new();space.keycode=KEY_SPACE;space.pressed=true
	Input.parse_input_event(space);await settle(2)
	check(workspace.audio.playing,"点击工具按钮后 Space 仍能播放")
	workspace.audio.set_playing(false)
	var text_entry:=LineEdit.new();workspace.add_child(text_entry);text_entry.grab_focus()
	Input.parse_input_event(space);await settle(2)
	check(not workspace.audio.playing,"文本框输入空格不会启动播放")
	text_entry.queue_free();workspace.surface.grab_focus()
	workspace._fit_timeline()
	check(workspace.timeline.x_at(24000000)<=workspace.timeline.size.x,"一键显示完整歌曲区段")
	workspace.timeline.left_seconds=0;workspace.timeline.pixels_per_second=100
	workspace._follow_suspended=false;workspace.audio.playing=true;workspace._position_changed(20);workspace.audio.playing=false
	check(workspace.timeline.x_at(20000000)<workspace.timeline.size.x,"播放头离开视野时自动跟随")
	workspace.timeline.manual_browse.emit();var saved_left:float=workspace.timeline.left_seconds
	workspace.audio.playing=true;workspace._position_changed(30);workspace.audio.playing=false
	check(is_equal_approx(workspace.timeline.left_seconds,saved_left),"手动浏览后不抢回时间线视野")
	workspace.seek(3400000);await settle()
	if DisplayServer.get_name()!="headless":
		root.mode=Window.MODE_MAXIMIZED;await settle(25)
		check(root.mode==Window.MODE_MAXIMIZED and root.content_scale_factor>1,"实际最大化自动放大界面")
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://").path_join("../Levels/output/ui/level-ui-maximized.png").simplify_path())
		print("MAXIMIZED: %s; UI scale %.3f; logical %s"%[root.size,root.content_scale_factor,root.get_visible_rect().size])
	workspace.open_boss_binding();await settle(10)
	var panel: LevelBossPanel=workspace.boss_panel
	check(panel.visible and panel.get_global_rect().end.x<=root.get_visible_rect().size.x+1,"缩放后的 BOSS 面板保持在可视范围内")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://").path_join("../Levels/output/ui/level-ui-maximized-boss.png").simplify_path())
	workspace._show_inspector("properties");await settle()
	workspace.surface.grab_focus()
	var dialog:=AcceptDialog.new();workspace.add_child(dialog);workspace._popup(dialog,Vector2i(400,200));await settle()
	dialog.hide();await settle()
	check(workspace.surface.has_focus(),"弹窗关闭恢复原控件焦点")
	dialog.queue_free()
	if DisplayServer.get_name()!="headless":
		root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1280,720);await settle(15)
		check(root.get_visible_rect().size.y>=720,"从最大化还原后重新计算倍率")
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://").path_join("../Levels/output/ui/level-ui-restored.png").simplify_path())
	workspace.queue_free();await settle()
	print("LEVEL LAYOUT TESTS: %d (%d checks)"%[failures,checks]);quit(1 if failures else 0)
