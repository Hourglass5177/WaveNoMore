extends SceneTree
## 串联素材、绑定、颜色、保存恢复与试玩状态；试玩握手读的是相同正式协议。
var failures := 0
var checks := 0
var workspace
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL: "+label)
func settle(count := 6) -> void:
	for frame in count: await process_frame
func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join("../Levels/output/ux").simplify_path())
	root.size=Vector2i(1440,900)
	workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate(); workspace.offer_recovery_on_start=false;workspace.recovery_path="user://level-tests/flow-recovery.json";root.add_child(workspace);await settle()
	workspace._open_path("res://examples/level-studio/渡口演出/level.json");await settle(20)
	workspace.select_objects(PackedStringArray(["ferryman"]));workspace.open_boss_binding();await settle()
	var panel: LevelBossPanel=workspace.boss_panel
	var asset: String=workspace.document.find("objects","ferryman").asset
	check(is_equal_approx(panel.data.release_sec,workspace.assets().release_time(asset,panel.data.action)),"新建绑定首次选中动作即读取素材出手标记")
	panel._select_binding(1);await settle()
	var binding: String=panel.binding_id
	var old_rate: float=panel.data.rate;var old_cursor: int=workspace.document.cursor
	workspace.document.begin_edit();panel._change("rate",1.5);panel._change("rate",2.0);workspace.document.end_edit();await settle()
	check(workspace.document.cursor==old_cursor+1 and workspace.document.find("bindings",binding).rate==2.0,"集成绑定字段连续修改一次提交")
	workspace.document.undo();await settle();check(is_equal_approx(panel.data.rate,old_rate),"撤销同步绑定面板")
	panel._copy_settings();check(panel.binding_id.is_empty() and panel.data.note_ids.is_empty(),"复制配置不重复音符关联")
	check(not workspace._modal_open() and workspace.timeline.is_visible_in_tree(),"BOSS 面板不阻断主时间线")
	workspace._show_inspector("properties");await settle()
	workspace.surface.grab_focus()
	var old_loads: int=workspace.preview.load_count;var old_boss: String=workspace._boss_signature
	workspace.set_object_field("name","测试改名");await settle()
	check(workspace.preview.load_count==old_loads and workspace._boss_signature==old_boss,"改名不重建正式预览或重编译攻击")
	var picker: ColorPickerButton
	for row in workspace.inspector.get_children():
		for child in row.get_children():
			if child is ColorPickerButton:picker=child;break
		if picker!=null:break
	picker.get_popup().popup_centered();await settle()
	check(not workspace._background,"本应用颜色弹窗不触发后台休眠")
	picker.get_popup().hide();await settle()
	var previous: String=workspace.document.find("objects","ferryman").fields.color
	old_cursor=workspace.document.cursor
	picker.color_changed.emit(Color("55bbffff"));picker.color_changed.emit(Color("77ddffff"));await settle()
	check(workspace.document.find("objects","ferryman").fields.color=="77ddffff" and is_instance_valid(picker),"颜色实时预览且控件保持")
	picker.popup_closed.emit();await settle();check(workspace.document.cursor==old_cursor+1,"颜色关闭后一次历史")
	check(workspace.preview.load_count==old_loads and workspace._boss_signature==old_boss,"调色不重建玩法或攻击")
	workspace.document.undo();await settle();check(workspace.document.find("objects","ferryman").fields.color==previous,"撤销调色恢复原色")
	workspace.timeline.left_seconds=-2;workspace.timeline.row_scroll=17;workspace.surface.pan=Vector2(8,9);workspace.timeline.folded={"ferryman":true};workspace._store_view()
	var state: Dictionary=workspace._workspace_snapshot();workspace._apply_workspace(state);await settle()
	check(workspace.timeline.folded.get("ferryman",false) and workspace.surface.pan==Vector2(8,9),"恢复工作区保留折叠与画布平移")
	workspace.set_object_field("name","需要恢复的名称");workspace._write_recovery()
	var recovery:=LevelProjectIO.read_json(workspace.recovery_path)
	check(recovery.has("updated") and recovery.workspace.has("views"),"恢复稿包含时间和各区段视图")
	# 在临时副本保存，示例工程保持原样。
	var folder: String=ProjectSettings.globalize_path("user://level-tests/flow-save")
	check(workspace._save_as_to(folder),"另存为包含歌曲及素材依赖")
	workspace._show_inspector("level");await settle()
	var title: LineEdit
	for row in workspace.inspector.get_children():
		if row is HBoxContainer and row.get_child(0) is Label and row.get_child(0).text=="标题": title=row.get_child(1)
	title.grab_focus();title.text="尚未离开输入框的标题"
	var save:=InputEventKey.new();save.pressed=true;save.ctrl_pressed=true;save.keycode=KEY_S;root.push_input(save,true);await settle()
	check(LevelProjectIO.read_json(folder.path_join("level.json")).title=="尚未离开输入框的标题","Ctrl+S 保存尚未失焦的文本字段")
	workspace._trial_folder="user://level-tests/mock-trial";workspace._trial_request="ux-test";workspace._trial_started=Time.get_ticks_msec()
	LevelProjectIO.write_json(workspace._trial_folder.path_join("status.json"),{"request_id":"ux-test","interface_version":1,"stage":"ready"})
	workspace._read_trial_status();check(workspace._trial_stage=="ready" and workspace._trial_button.text=="试玩进行中","试玩收到 ready 后才显示已加载")
	workspace._set_background(true);check(workspace.preview.suspended and not workspace.audio.playing,"后台暂停预览与声音")
	workspace._set_background(false);check(not workspace.preview.suspended and Engine.max_fps==60,"回前台立即恢复编辑，无需等待试玩退出")
	workspace._choose_resource("audio","",func(_value):pass);await settle()
	check(workspace._modal_open(),"素材选择器可打开并拥有焦点")
	for child in workspace.get_children():
		if child is Window and child.visible: child.hide();child.queue_free()
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://").path_join("../Levels/output/ux/flow.png").simplify_path())
	workspace.queue_free();await settle()
	print("LEVEL FLOW TESTS: %d (%d checks)"%[failures,checks]);quit(1 if failures else 0)
