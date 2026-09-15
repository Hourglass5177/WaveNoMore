extends SceneTree
## 从初始环境按钮完成选择，不绕过 UI 直接写文档。
var failures:=0
var workspace
func _initialize() -> void:run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:failures+=1;printerr("FAIL: "+label)
func settle() -> void:
	for frame in 6:await process_frame
func click(control: Control) -> void:
	var viewport:=control.get_viewport()
	var point:=control.get_global_rect().get_center()
	if viewport is Window and viewport!=root and viewport.is_embedded():point+=Vector2(viewport.position);viewport=root
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		event.position=point;event.global_position=point
		viewport.push_input(event,true)
func button(text: String) -> Button:
	for node in workspace.inspector.find_children("*","Button",true,false):
		if node.text==text:return node
	return null
func choose(asset: String, caption := "选择初始环境") -> void:
	var source:=button(caption);var ancestor:=source.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer:ancestor.ensure_control_visible(source)
		ancestor=ancestor.get_parent()
	await settle();click(source);await settle()
	var dialogs: Array=workspace.get_children().filter(func(node):return node is ConfirmationDialog and node.title=="选择环境场景")
	check(dialogs.size()==1,"点击按钮打开环境选择器")
	if dialogs.is_empty():return
	var dialog: ConfirmationDialog=dialogs[0]
	var list: ItemList=dialog.find_children("*","ItemList",true,false)[0]
	var index:=-1
	for item in list.item_count:
		if list.get_item_metadata(item)==asset:index=item
	check(index>=0,"选择器包含目标环境")
	if index<0:dialog.queue_free();return
	list.select(index);list.item_selected.emit(index)
	click(dialog.get_ok_button());await settle()
func run() -> void:
	var output:=ProjectSettings.globalize_path("res://../Levels/output/environment/initial")
	DirAccess.make_dir_recursive_absolute(output)
	workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate();workspace.offer_recovery_on_start=false;workspace.recovery_path=output.path_join("recovery.json");root.add_child(workspace);await settle()
	check(LevelAssetPackWriter.write("res://tests/fixtures/environment/manifest.tres",output.path_join("environment.pck")).is_empty(),"准备环境资源")
	workspace.document.directory=output
	workspace.document.fields("接入素材包",{"packs":[{"path":"environment.pck","manifest":"res://tests/fixtures/environment/manifest.tres"}]});await settle()
	workspace.open_environment_settings();await settle()
	await choose("environment_test_b")
	check(workspace.document.data.get("initial_background","")=="environment_test_b","确认后写入初始环境")
	var labels: Array=workspace.inspector.find_children("*","Label",true,false)
	check(labels.any(func(node):return node.text=="初始环境 · 靛蓝渡口"),"确认后立即显示新环境名称")
	check(button("恢复沿用基础场景背景")!=null,"确认后可恢复沿用主题背景")
	check(workspace.timeline.environment!=null,"确认后建立初始环境预览")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("initial-environment.png"))
		var picture: Image=workspace.viewport.get_texture().get_image()
		var pixel:=picture.get_pixel(picture.get_width()/2,picture.get_height()/2)
		check(pixel.b>0.8 and pixel.r<0.2,"GPU 实际显示所选蓝色环境")
	workspace.document.undo();await settle()
	check(str(workspace.document.data.get("initial_background","")).is_empty(),"撤销恢复沿用主题")
	workspace.document.undo(true);await settle()
	check(workspace.inspector.find_children("*","Label",true,false).any(func(node):return node.text=="初始环境 · 靛蓝渡口"),"重做同步环境名称")
	workspace._show_inspector("level");await settle()
	check(button("选择初始环境")!=null,"关卡设置也能直接选择初始环境")
	var choose_button:=button("选择初始环境");click(choose_button);await settle()
	var dialog: ConfirmationDialog=workspace.get_children().filter(func(node):return node is ConfirmationDialog and node.title=="选择环境场景")[0]
	var list: ItemList=dialog.find_children("*","ItemList",true,false)[0]
	check(not list.get_selected_items().is_empty() and list.get_item_metadata(list.get_selected_items()[0])=="environment_test_b","重开时选中当前初始环境")
	var search: LineEdit=dialog.find_children("*","LineEdit",true,false)[0];search.text="不存在的环境";search.text_changed.emit(search.text)
	check(list.item_count==0 and dialog.get_ok_button().disabled,"无搜索结果时禁用确认")
	var cursor: int=workspace.document.cursor;click(dialog.get_cancel_button());await settle()
	check(workspace.document.cursor==cursor and workspace.document.data.initial_background=="environment_test_b","取消选择不修改环境或历史")
	check(root.gui_get_focus_owner()==choose_button,"关闭选择器焦点返回原按钮")
	click(button("恢复沿用基础场景背景"));await settle()
	check(workspace.document.data.initial_background=="" and not button("恢复沿用基础场景背景").visible,"恢复沿用立即同步控件")
	check(not workspace.show_player().environment_controller._configured_objects.is_empty(),"未导入歌曲时仍装配沿用的基础背景")
	await choose("environment_test_a");check(workspace.document.data.initial_background=="environment_test_a","从关卡设置实际选择初始环境")
	workspace.open_environment_settings();await settle();await choose("environment_test_b","在游标处添加换景")
	check(workspace.document.entries("scene_cues").size()==1,"共用选择器可以添加换景")
	await choose("environment_test_c","更换目标环境")
	check(workspace.document.entries("scene_cues")[0].asset=="environment_test_c","共用选择器可以更换目标环境")
	workspace.queue_free();await settle();print("LEVEL INITIAL ENVIRONMENT failures=",failures);quit(failures)
