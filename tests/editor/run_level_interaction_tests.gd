extends SceneTree
## 通过 Viewport 输入路由测试完整鼠标/触摸板事件，避免只验证内部字段赋值。
var failures := 0
var checks := 0
var workspace
func _initialize() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures+=1;printerr("FAIL: "+label)
func settle(count := 3) -> void:
	for frame in count: await process_frame
func mouse(local: Vector2, button: int, pressed: bool, shift := false, ctrl := false, factor := 1.0) -> void:
	var event:=InputEventMouseButton.new();event.position=workspace.timeline.global_position+local;event.global_position=event.position;event.button_index=button;event.pressed=pressed;event.shift_pressed=shift;event.ctrl_pressed=ctrl;event.factor=factor
	root.push_input(event,true)
func motion(local: Vector2, alt := false) -> void:
	var event:=InputEventMouseMotion.new();event.position=workspace.timeline.global_position+local;event.global_position=event.position;event.alt_pressed=alt;event.button_mask=MOUSE_BUTTON_MASK_LEFT
	root.push_input(event,true)
func click(local: Vector2, shift := false) -> void:
	mouse(local,MOUSE_BUTTON_LEFT,true,shift);mouse(local,MOUSE_BUTTON_LEFT,false,shift)

func _run() -> void:
	root.size=Vector2i(1440,900)
	workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate();workspace.offer_recovery_on_start=false;workspace.recovery_path="user://level-tests/interaction-recovery.json";root.add_child(workspace);await settle(5)
	workspace._ui_scale=1;workspace._apply_ui_scale();await settle()
	for index in 25: workspace.add_object("text")
	var id: String=workspace.selection[0]
	workspace.document.set_key(id,"opacity","song",1000000,0.2)
	workspace.document.set_key(id,"opacity","song",2000000,0.9)
	await settle()
	var t: LevelTimeline=workspace.timeline
	workspace._follow_suspended=false
	var before_history: int=workspace.document.history.size()
	var previous_zoom: float=t.pixels_per_second
	mouse(Vector2(300,110),MOUSE_BUTTON_WHEEL_DOWN,true,false,false,0.125);await settle()
	check(is_equal_approx(t.row_scroll,6),"高精度纵向滚动保留 0.125 滚动量")
	check(t.pixels_per_second==previous_zoom and not workspace._follow_suspended,"纵向浏览不缩放、不解除播放跟随")
	mouse(Vector2(300,110),MOUSE_BUTTON_WHEEL_RIGHT,true,false,false,0.25);await settle()
	check(is_equal_approx(t.left_seconds,0.25) and workspace._follow_suspended,"横向滚动浏览时间并暂停跟随")
	var pan:=InputEventPanGesture.new();pan.position=t.global_position+Vector2(300,110);pan.delta=Vector2(0.25,0.5);root.push_input(pan,true);await settle()
	check(is_equal_approx(t.left_seconds,0.33) and is_equal_approx(t.row_scroll,22),"斜向双指事件分别处理两轴")
	var anchor:=t.time_at(400)
	mouse(Vector2(400,110),MOUSE_BUTTON_WHEEL_UP,true,false,true,0.5);await settle()
	check(absi(t.time_at(400)-anchor)<=1,"Ctrl 高精度缩放保留鼠标时间锚点")
	check(workspace.document.history.size()==before_history,"浏览不产生文档历史")
	t.left_seconds=0;t.pixels_per_second=100;t.row_scroll=0
	# 使用首个对象的轨道，让小窗口下也能实际命中。
	id=workspace.document.entries("objects")[0].id
	workspace.document.set_key(id,"opacity","song",1000000,0.2);workspace.document.set_key(id,"opacity","song",2000000,0.9);await settle()
	var track: Dictionary=workspace.document.entries("tracks").filter(func(item):return item.object_id==id)[0]
	var key1: String=track.keys[0].id;var key2: String=track.keys[1].id
	var p1:=Vector2(t.x_at(1000000),LevelTimeline.RULER+LevelTimeline.ROW+12)
	var p2:=Vector2(t.x_at(2000000),p1.y)
	click(p1);click(p2,true);await settle()
	check(workspace.selected_items.size()==2 and t.selected.size()==2,"Shift 多选由工作区统一保留")
	click(p1,true);await settle()
	check(workspace.selected_items==PackedStringArray([key2]),"Shift 取消选择不会被属性同步加回")
	click(p1);await settle();before_history=workspace.document.history.size()
	mouse(p1,MOUSE_BUTTON_LEFT,true);motion(p1+Vector2(3,0));mouse(p1+Vector2(3,0),MOUSE_BUTTON_LEFT,false);await settle()
	check(workspace.document.history.size()==before_history,"未超过 6 像素不产生移动")
	mouse(p1,MOUSE_BUTTON_LEFT,true);motion(p1+Vector2(37,0),true)
	var old_left: float=t.left_seconds
	mouse(p1,MOUSE_BUTTON_WHEEL_RIGHT,true);await settle()
	check(t.left_seconds==old_left,"编辑手势中忽略独立滚动")
	workspace._set_background(true);await settle();workspace._set_background(false)
	check(workspace.document.history.size()==before_history and t._candidate.is_empty(),"失焦取消候选且不提交历史")
	mouse(p1,MOUSE_BUTTON_LEFT,false)
	mouse(p1,MOUSE_BUTTON_LEFT,true);motion(p1+Vector2(37,0),true);mouse(p1+Vector2(37,0),MOUSE_BUTTON_LEFT,false);await settle()
	check(workspace.document.find("tracks",track.id).keys[0].time_us==1370000,"Alt 拖动关闭时间吸附")
	check(workspace.document.history.size()==before_history+1,"一次拖动一次撤销")
	workspace.document.undo();await settle()
	check(workspace.document.find("tracks",track.id).keys[0].time_us==1000000,"撤销恢复拖动前位置")
	click(Vector2(12,LevelTimeline.RULER+12));await settle()
	check(t.folded.get(id,false),"独立折叠箭头生效")
	click(Vector2(t.x_at(1000000),LevelTimeline.RULER+12));await settle()
	check(key1 in workspace.selected_items,"折叠行仍能命中事件")
	workspace.select_objects(PackedStringArray([id]));await settle()
	var spin: SpinBox
	for row in workspace.inspector.get_children():
		for control in row.get_children():
			if control is SpinBox: spin=control;break
		if spin!=null: break
	var previous: float=spin.value;before_history=workspace.document.cursor
	spin.get_line_edit().grab_focus();spin.value=previous+1;spin.value=previous+2;await settle()
	check(is_instance_valid(spin) and spin.get_line_edit().has_focus(),"数值连续修改控件与焦点保持")
	LevelUI.finish_fields(workspace.inspector);workspace.document.end_edit();await settle()
	check(workspace.document.cursor==before_history+1,"连续数值修改合并为一条历史")
	workspace.document.undo();await settle();check(workspace.document.find("objects",id).depth==previous,"数值撤销回到本次手势起点")
	var snapshot: Dictionary=workspace._workspace_snapshot()
	t.left_seconds=12;t.row_scroll=35;workspace.surface.pan=Vector2(43,51);workspace._follow_suspended=true
	workspace._store_view();workspace.set_section("intro");workspace.set_section("song");await settle()
	check(is_equal_approx(t.left_seconds,12) and workspace.surface.pan==Vector2(43,51),"切换区段恢复时间线和画布视图")
	workspace._apply_workspace(snapshot);await settle()
	workspace._toggle_focus_preview();check(not workspace.get_node("%Bottom").visible,"专注预览折叠时间线")
	workspace._toggle_focus_preview();check(workspace.get_node("%Bottom").visible,"退出专注模式还原布局")
	var curve:=LevelCurveEditor.new();workspace.inspector.add_child(curve);await settle()
	var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true;press.position=Vector2(1,1);curve._gui_input(press)
	check(curve._drag==-1,"曲线空白处不拾取远处手柄")
	workspace.queue_free();await settle()
	print("LEVEL INTERACTION TESTS: %d (%d checks)"%[failures,checks]);quit(1 if failures else 0)
