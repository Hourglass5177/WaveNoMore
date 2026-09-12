extends Control
## 工作区只协调文档、选区和共用运行时，谱面在此保持只读。
var document := LevelDocument.new()
var song_document := StudioDocument.new()
var audio := StudioAudio.new()
var preview := StudioPreviewSession.new()
var timeline := LevelTimeline.new()
var surface := LevelPreviewSurface.new()
var inspector := LevelInspector.new()
var viewport := SubViewport.new()
var selection := PackedStringArray()
var selected_track := ""
var selected_item := ""
var section := "song"
var time_us := 0
var auto_key := false
var difficulty_only := false
var workspace_state := {}
var _assets := LevelAssetLibrary.new()
var _standalone: LevelShowPlayer
var _show_signature := ""
var _asset_signature := ""
var _stage_signature := ""
var _candidate_objects: Array = []
var _candidate_tracks: Array = []
var _refresh_queued := false
var _loading := false
var _tree_updating := false
var _object_tree := Tree.new()
var _asset_list := LevelAssetList.new()
var _asset_search := LineEdit.new()
var _asset_category := OptionButton.new()
var _difficulty := OptionButton.new()
var _scene := OptionButton.new()
var _section := OptionButton.new()
@onready var _status: Label = %Status
var _position := Label.new()
var _play := Button.new()
@onready var _problems: ItemList = %Problems
@onready var _vertical: VSplitContainer = %Vertical
@onready var _left_split: HSplitContainer = %LeftSplit
@onready var _right_split: HSplitContainer = %RightSplit
@onready var _left_panel: TabContainer = %LeftPanel
@onready var _inspector_scroll: ScrollContainer = %InspectorScroll
var _autosave := Timer.new()
var _audition := AudioStreamPlayer.new()
var _recent: Array = []
var _trial_pid := -1
var _trial_poll := 0.0
var _trial_executable := ""
var _trial_button: Button
var _before_trial_fps := 60
var _pending_trial := {}
var recovery_path := "user://level_studio/recovery.json"
var offer_recovery_on_start := true
var _wave_jobs: Array = []
var _wave_versions := {}
var _ui_scale := 0.0
var _scale_menu := MenuButton.new()
var _left_width := 220
var _right_width := 310
var _timeline_height := 270
var _layout_queued := false
var _follow := CheckBox.new()
var _follow_suspended := false
var _mode_buttons := {}
var selected_items := PackedStringArray()
var edit_target := "objects"
var inspector_mode := "properties"
var boss_panel: LevelBossPanel
var _boss_signature := ""
var _compiled_boss := {"tracks":[],"emissions":{}}
var _loading_started := -1
var _seek_pending := false
var _seek_elapsed := 0.05
var _seeking := false
var _background := false
var _trial_folder := ""
var _trial_request := ""
var _trial_stage := ""
var _trial_started := 0
var _trial_timeout := false
var _focus_layout := {}
var _views := {}
var _refresh_tree := true
var _refresh_preview := true
var _refresh_checks := true
var _refresh_inspector := true
var _loop_toggle: CheckBox


func _ready() -> void:
	get_window().title = "冥河 · 关卡编辑器"
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	get_window().content_scale_size = Vector2i.ZERO
	get_window().min_size = Vector2i(1024,720)
	Input.ignore_joypad_on_unfocused_application = true
	InputEventBuffer.set_mode(InputEventBuffer.InputMode.DISABLED); InputEventBuffer.set_process_input(false)
	Engine.max_fps = 60
	add_child(audio); add_child(preview); add_child(_audition)
	viewport.size = Vector2i(1920,1080); viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; add_child(viewport)
	surface.viewport = viewport; surface.document = document
	inspector.workspace = self
	_build_ui()
	timeline.bind(document)
	document.changed.connect(_document_changed)
	surface.selection_changed.connect(func(ids): select_objects(ids))
	surface.transform_committed.connect(_commit_transform)
	surface.candidate_changed.connect(func(values): _candidate_objects = values; _update_show())
	surface.asset_dropped.connect(func(asset,at): add_asset_object(asset,at))
	timeline.selection_set_changed.connect(_timeline_selection)
	timeline.seek_requested.connect(_scrub)
	timeline.seek_finished.connect(func(_us): _finish_seek())
	timeline.candidate_changed.connect(func(values): _candidate_tracks = values; _update_show())
	timeline.loop_changed.connect(func(start,end): audio.loop_start = float(start)/1000000; audio.loop_end = float(end)/1000000)
	timeline.binding_requested.connect(func(object_id,binding_id):select_objects(PackedStringArray([object_id]));open_boss_binding(binding_id))
	audio.position_changed.connect(_position_changed)
	audio.discontinuity.connect(func(_seconds,_reason):
		if not _loading and not _seeking and section == "song" and is_instance_valid(preview.stage_root): _seek_pending=true)
	audio.waveform_ready.connect(func(peaks,duration): timeline.waveform = peaks; timeline.waveform_duration = duration; timeline.queue_redraw())
	audio.error_reported.connect(message)
	audio.state_changed.connect(func(): _play.text = "暂停" if audio.playing else "播放";_play.icon=preload("res://assets/chart_studio/pause.svg") if audio.playing else preload("res://assets/chart_studio/play.svg"); if not audio.playing and show_player() != null: show_player().stop_audio())
	preview.loading_changed.connect(_preview_loading)
	preview.rebuilt.connect(func(): _sample_show(true))
	add_child(_autosave); _autosave.wait_time = 1.0; _autosave.one_shot = true; _autosave.timeout.connect(_write_recovery)
	get_tree().auto_accept_quit = false; get_window().close_requested.connect(func(): _discard_or(func(): get_tree().quit()))
	get_window().files_dropped.connect(_files_dropped)
	_load_preferences()
	get_window().size_changed.connect(_apply_ui_scale)
	get_window().dpi_changed.connect(_apply_ui_scale)
	resized.connect(_queue_layout)
	_vertical.resized.connect(_queue_layout)
	_right_split.resized.connect(_queue_layout)
	_left_split.dragged.connect(func(offset):_left_width=offset)
	_right_split.dragged.connect(func(offset):_right_width=roundi(_right_split.size.x)-offset)
	_vertical.dragged.connect(func(offset):_timeline_height=roundi(_vertical.size.y)-offset)
	_apply_ui_scale()
	_reset_layout.call_deferred()
	_document_changed("project")
	var arguments:=OS.get_cmdline_user_args()
	var opening:=""
	for index in range(arguments.size()-1):
		if arguments[index]=="--open-level":opening=arguments[index+1];break
	if not opening.is_empty():_open_path.call_deferred(opening)
	elif offer_recovery_on_start:_offer_recovery.call_deferred()

func _build_ui() -> void:
	var toolbar: HFlowContainer = %Toolbar
	_add_menu(toolbar,"文件",[["新建",_new],["打开",_open],["保存",save],["另存为",_save_as],["导入歌曲",import_song],["导出关卡包",export_package]])
	_add_menu(toolbar,"编辑",[["撤销",func():document.undo()],["重做",func():document.undo(true)],["复制",_copy_selection],["粘贴",_paste_selection],["删除",delete_selection]])
	_add_menu(toolbar,"素材",[["导入素材",import_asset],["导入素材包",import_pack],["重新定位缺失素材",_relocate_asset]])
	LevelUI.button(toolbar,"保存",save,"保存当前字段及工程（Ctrl+S）")
	_trial_button=LevelUI.button(toolbar,"在游戏中试玩",playtest)
	LevelUI.button(toolbar,"帮助",_help)
	_scale_menu.text="界面";toolbar.add_child(_scale_menu)
	for caption in ["自动缩放","100%","125%","150%","200%"]:_scale_menu.get_popup().add_radio_check_item(caption)
	_scale_menu.get_popup().add_separator()
	_scale_menu.get_popup().add_item("显示整个区段",10)
	_scale_menu.get_popup().id_pressed.connect(func(id):
		if id==10:_fit_timeline();return
		_ui_scale=[0.0,1.0,1.25,1.5,2.0][id];_apply_ui_scale();_save_preferences())
	var menu := MenuButton.new(); menu.text="视图"; toolbar.add_child(menu)
	for pair in [["恢复默认布局",0],["显隐素材与对象",1],["显隐属性面板",2],["显隐时间线",8],["专注预览 / 恢复",9]]: menu.get_popup().add_item(pair[0],pair[1])
	menu.get_popup().id_pressed.connect(_view_action)
	menu.get_popup().about_to_popup.connect(_cancel_gestures)
	var recent := MenuButton.new(); recent.text="最近工程"; toolbar.add_child(recent)
	recent.get_popup().about_to_popup.connect(func():
		recent.get_popup().clear()
		for index in _recent.size(): recent.get_popup().add_item(str(_recent[index]),100+index))
	recent.get_popup().id_pressed.connect(_view_action)
	var tools_menu := MenuButton.new(); tools_menu.text="工程"; toolbar.add_child(tools_menu)
	for pair in [["导入旧场景演出",5],["重新定位缺失素材",6],["选择配套游戏",7]]: tools_menu.get_popup().add_item(pair[0],pair[1])
	tools_menu.get_popup().id_pressed.connect(_view_action)
	LevelUI.button(%InspectorTabs,"属性",func(): _show_inspector("properties"))
	LevelUI.button(%InspectorTabs,"关卡设置",func(): _show_inspector("level"))
	LevelUI.button(%InspectorTabs,"BOSS",open_boss_binding)
	var assets_panel := VBoxContainer.new(); assets_panel.name = "素材"; _left_panel.add_child(assets_panel)
	_asset_search.placeholder_text = "搜索素材名称或路径"; assets_panel.add_child(_asset_search); _asset_search.text_changed.connect(func(_value): _refresh_assets())
	for caption in ["全部","场景 / BOSS","图片","音频","字体"]: _asset_category.add_item(caption)
	assets_panel.add_child(_asset_category); _asset_category.item_selected.connect(func(_index): _refresh_assets())
	_asset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL; _asset_list.fixed_icon_size = Vector2i(48,48); _asset_list.max_columns = 1
	assets_panel.add_child(_asset_list); _asset_list.item_activated.connect(func(index): add_asset_object(str(_asset_list.get_item_metadata(index))))
	var objects_panel := VBoxContainer.new(); objects_panel.name = "对象"; _left_panel.add_child(objects_panel)
	var add := MenuButton.new(); add.text = "+ 添加对象"; objects_panel.add_child(add)
	for pair in [["精灵","sprite"],["BOSS / 场景","actor"],["环境","environment"],["HUD 文字","text"],["HUD 图片","image"],["音频","audio"],["镜头","camera"],["分组","group"]]:
		add.get_popup().add_item(pair[0]); add.get_popup().set_item_metadata(add.get_popup().item_count-1,pair[1])
	add.get_popup().index_pressed.connect(func(index): add_object(str(add.get_popup().get_item_metadata(index))))
	_object_tree.hide_root = true; _object_tree.select_mode = Tree.SELECT_MULTI; _object_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	objects_panel.add_child(_object_tree); _object_tree.multi_selected.connect(func(_item,_column,_selected): _tree_selection())
	var object_actions := HFlowContainer.new(); objects_panel.add_child(object_actions)
	for entry in [["复制",copy_objects],["粘贴",paste_objects],["对称",mirror_objects],["分组",group_objects],["解组",ungroup_objects],["删除",delete_selection]]: LevelUI.button(object_actions,entry[0],entry[1])
	var top: HFlowContainer = %PreviewToolbar
	top.add_child(_difficulty); _difficulty.item_selected.connect(_switch_difficulty)
	top.add_child(_scene)
	for stage in ChartSceneLibrary.shared().all_stages(): _scene.add_item(stage.display_name); _scene.set_item_metadata(_scene.item_count-1,stage.stage_id)
	_scene.item_selected.connect(func(index): document.fields("切换基础场景",{"scene_id":_scene.get_item_metadata(index)}))
	for pair in [["移动 W","move"],["旋转 E","rotate"],["缩放 R","scale"]]:
		var button:=LevelUI.button(top,pair[0],func():_set_transform_mode(pair[1]),"切换画面操纵工具："+pair[0])
		button.toggle_mode=true;_mode_buttons[pair[1]]=button
	_set_transform_mode("move")
	LevelUI.button(top,"适应画面",func(): surface.zoom=1;surface.pan=Vector2.ZERO;surface.queue_redraw())
	LevelUI.button(top,"定位选中",surface.frame_selection)
	LevelUI.toggle(top,"网格",true,func(value): surface.show_grid=value;surface.queue_redraw())
	LevelUI.toggle(top,"路径",true,func(value): surface.show_paths=value;surface.queue_redraw())
	%PreviewHost.add_child(surface); %PreviewHost.move_child(surface,0); surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inspector_scroll.add_child(inspector); inspector.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	boss_panel=LevelBossPanel.new(); boss_panel.workspace=self; %RightPanel.add_child(boss_panel); boss_panel.hide()
	var sequences := VBoxContainer.new(); sequences.name="片段"; _left_panel.add_child(sequences)
	LevelUI.button(sequences,"保存选区为演出片段",_save_sequence)
	LevelUI.button(sequences,"插入演出片段",_insert_sequence)
	var bottom: VBoxContainer = %Bottom
	var transport: HFlowContainer = %Transport
	for caption in ["曲前","歌曲","曲后"]: _section.add_item(caption)
	_section.select(1); transport.add_child(_section); _section.item_selected.connect(func(index): set_section(LevelFormat.SECTIONS[index]))
	LevelUI.button(transport,"开头",func(): seek(0))
	_play.text="播放";_play.icon=preload("res://assets/chart_studio/play.svg"); transport.add_child(_play); _play.pressed.connect(toggle_play)
	_position.custom_minimum_size.x=95; transport.add_child(_position)
	LevelUI.choice(transport,"速率",[0.5,0.75,1.0,1.25,1.5,2.0],1.0,func(value): audio.set_rate(value))
	_loop_toggle=LevelUI.toggle(transport,"循环",false,func(value): audio.loop_enabled=value)
	_follow.text="跟随";_follow.button_pressed=true;_follow.tooltip_text="播放时跟随游标；手动浏览后暂停跟随，重新播放或勾选可恢复"
	transport.add_child(_follow);_follow.toggled.connect(func(_value):
		if _follow_suspended:_follow.set_pressed_no_signal(true)
		_follow_suspended=false;_follow.text="跟随")
	timeline.manual_browse.connect(func():_follow_suspended=true;_follow.text="跟随暂停")
	LevelUI.button(transport,"循环起点",func(): timeline.loop_start_us=time_us;audio.loop_start=float(time_us)/1000000;timeline.queue_redraw())
	LevelUI.button(transport,"循环终点",func(): timeline.loop_end_us=time_us;audio.loop_end=float(time_us)/1000000;timeline.queue_redraw())
	LevelUI.choice(transport,"吸附",[120,240,480,60,0],120,func(value): timeline.snap_ticks=value,["1/16","1/8","1/4","1/32","关闭"])
	LevelUI.toggle(transport,"自动关键帧",false,func(value): auto_key=value;surface.record_at_cursor=value;inspector.refresh())
	LevelUI.toggle(transport,"仅当前难度",false,func(value): difficulty_only=value;inspector.refresh())
	var edit_menu:=MenuButton.new();edit_menu.text="演出";toolbar.add_child(edit_menu)
	for caption in ["◆ 位置关键帧","在游标处拆分（S）","对齐画布中心","添加动作片段","添加显示区间","添加音频片段"]:edit_menu.get_popup().add_item(caption)
	edit_menu.get_popup().id_pressed.connect(func(id):
		match id:
			0:key_property("position")
			1:timeline.split_selected()
			2:align_center()
			3:add_clip("action")
			4:add_clip("visibility")
			5:add_clip("audio")
	)
	bottom.add_child(timeline); timeline.size_flags_vertical=Control.SIZE_EXPAND_FILL
	%ProblemToggle.toggled.connect(func(value): _problems.visible=value and _problems.item_count>0)
	_problems.item_activated.connect(_locate_problem)
	_status.text="新建工程 · 导入歌曲和素材后开始编排";_status.clip_text=true
	for split in [_left_split,_right_split,_vertical]:split.add_theme_constant_override("separation",10)
	_play.tooltip_text="播放 / 暂停（Space）";surface.tooltip_text="双指平移 · Ctrl+滚动围绕鼠标缩放 · 中键平移 · W/E/R 操纵 · Esc 取消拖动"
	_inspector_scroll.follow_focus=true

func difficulty() -> String:
	return song_document.chart().difficulty_id if not song_document.charts.is_empty() else "normal"

func assets() -> LevelAssetLibrary: return _assets
func show_player() -> LevelShowPlayer:
	return preview.stage_root.level_show_player if is_instance_valid(preview.stage_root) else _standalone

func message(text: String) -> void:
	_status.text=text
	var dialog:=AcceptDialog.new(); dialog.title="关卡编辑器";dialog.dialog_text=text;add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free);dialog.canceled.connect(dialog.queue_free);_popup(dialog,Vector2i(640,200))

func _popup(dialog: Window, minimum: Vector2i) -> void:
	_cancel_gestures()
	var old_focus:=get_viewport().gui_get_focus_owner()
	dialog.transient=true;dialog.exclusive=true
	dialog.visibility_changed.connect(func():
		if not dialog.visible and is_instance_valid(old_focus): old_focus.grab_focus())
	var available:=Vector2i(get_viewport().get_visible_rect().size)-Vector2i(40,40)
	dialog.popup_centered(minimum.min(available))
	# 自动换行和滚动区在首帧才获得宽度，再收敛一次尺寸，防止初始最小高度撑出窗口。
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(dialog):
		dialog.size=minimum.min(Vector2i(get_viewport().get_visible_rect().size)-Vector2i(40,40))
		dialog.move_to_center()

func _file_dialog(title: String, mode: FileDialog.FileMode, filters: PackedStringArray, action: Callable) -> void:
	var dialog:=FileDialog.new();dialog.title=title;dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.file_mode=mode;dialog.filters=filters
	add_child(dialog)
	if not document.directory.is_empty(): dialog.current_dir=ProjectSettings.globalize_path(document.directory)
	if mode==FileDialog.FILE_MODE_OPEN_DIR: dialog.dir_selected.connect(func(path): action.call(path);dialog.queue_free())
	else: dialog.file_selected.connect(func(path): action.call(path);dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);_popup(dialog,Vector2i(920,640))

func select_objects(ids: PackedStringArray,track_id:="",item_id:="") -> void:
	LevelUI.finish_fields(%RightPanel); document.end_edit()
	selection=ids; selected_track=track_id; selected_item=item_id
	selected_items=PackedStringArray() if item_id.is_empty() else PackedStringArray([item_id])
	edit_target="timeline" if not track_id.is_empty() else "objects"
	_sync_selection()

func _timeline_selection(ids: PackedStringArray, track_id: String, items: PackedStringArray) -> void:
	LevelUI.finish_fields(%RightPanel); document.end_edit()
	selection=ids; selected_track=track_id; selected_items=items
	selected_item=items[0] if items.size()==1 else ""
	edit_target="timeline"; _sync_selection()

func _sync_selection() -> void:
	surface.selected=selection.duplicate(); timeline.selected=selected_items.duplicate()
	timeline.selected_object=selection[0] if not selection.is_empty() else ""; timeline.selected_track=selected_track
	surface.queue_redraw(); timeline.queue_redraw(); _sync_tree_selection()
	if inspector_mode!="boss": _show_inspector("properties")

func _show_inspector(mode: String) -> void:
	LevelUI.finish_fields(%RightPanel); document.end_edit()
	inspector_mode=mode; %RightPanel.show()
	_inspector_scroll.visible=mode!="boss"; boss_panel.visible=mode=="boss"
	if mode!="boss": inspector.refresh()

func edit_document() -> LevelDocument: return document

func _tree_selection() -> void:
	if _tree_updating:return
	var ids:=PackedStringArray();var item:=_object_tree.get_next_selected(null)
	while item!=null:ids.append(str(item.get_metadata(0)));item=_object_tree.get_next_selected(item)
	select_objects(ids)

func _sync_tree_selection() -> void:
	_tree_updating=true
	var item:=_object_tree.get_root()
	if item!=null:item=item.get_next_in_tree()
	while item!=null:
		if str(item.get_metadata(0)) in selection:item.select(0)
		else:item.deselect(0)
		item=item.get_next_in_tree()
	_tree_updating=false
	if _object_tree.get_selected()!=null:_object_tree.scroll_to_item(_object_tree.get_selected())

func _refresh_objects() -> void:
	_tree_updating=true
	var folded_objects := {}
	var old_item:=_object_tree.get_root()
	while old_item!=null:
		if old_item.get_metadata(0)!=null: folded_objects[str(old_item.get_metadata(0))]=old_item.collapsed
		old_item=old_item.get_next_in_tree()
	_object_tree.clear();var root:=_object_tree.create_item();var items:={}
	for object_data:Dictionary in document.entries("objects"):
		var item:=_object_tree.create_item(root);items[object_data.id]=item
		item.set_text(0,("🔒 " if object_data.locked else "")+("◌ " if object_data.hidden else "")+str(object_data.name));item.set_metadata(0,object_data.id);item.collapsed=bool(folded_objects.get(object_data.id,false))
	# Tree 支持层级展示；文档的父子关系仍独立于 UI 的排序。
	for object_data:Dictionary in document.entries("objects"):
		if items.has(object_data.parent_id):items[object_data.id].get_parent().remove_child(items[object_data.id]);items[object_data.parent_id].add_child(items[object_data.id])
	_tree_updating=false;_sync_tree_selection()

func _refresh_assets() -> void:
	_asset_list.clear()
	var search:=_asset_search.text.to_lower();var category:=_asset_category.selected
	for asset_id:String in _assets.entries:
		var entry:VisualAssetEntry=_assets.entries[asset_id]
		var name:=entry.display_name if not entry.display_name.is_empty() else asset_id
		if not search.is_empty() and not search in (name+asset_id).to_lower():continue
		if category not in [0,1]:continue
		_asset_list.add_item(name,entry.thumbnail);_asset_list.set_item_metadata(_asset_list.item_count-1,asset_id)
	if document.directory.is_empty():return
	for path in _assets.list_files():
		var extension:=path.get_extension().to_lower();var kind:=2 if extension in ["png","jpg","jpeg","svg","webp"] else (3 if extension in ["wav","ogg","mp3"] else 4)
		if category!=0 and category!=kind:continue
		if not search.is_empty() and not search in path.to_lower():continue
		var texture:=_assets.resolve(path) as Texture2D if kind==2 else null
		_asset_list.add_item(path.get_file(),texture);_asset_list.set_item_metadata(_asset_list.item_count-1,path)

func _document_changed(kind:String) -> void:
	get_window().title="冥河 · 关卡编辑器 — "+str(document.data.title)+( " *" if document.dirty else "")
	if kind=="saved": return
	if kind=="project":
		_refresh_tree=true; _refresh_preview=true; _refresh_checks=true; _refresh_inspector=true; _boss_signature=""
	else:
		for change: Dictionary in document.last_changes:
			_refresh_checks=_refresh_checks or kind!="preview"
			if change.kind=="objects":
				_refresh_preview=true
				if change.before.size()!=change.after.size(): _refresh_tree=true
				else:
					for index in change.after.size():
						for field: String in ["id","name","parent_id","locked","hidden"]:
							if change.before[index].get(field)!=change.after[index].get(field): _refresh_tree=true
			elif change.kind in ["tracks","bindings"]: _refresh_preview=true
			elif change.kind=="metadata":
				for key: String in change.after:
					if key in ["scene_id","rule_path","packs","show","song_path"]: _refresh_preview=true
		_refresh_inspector=_refresh_inspector or not _field_focused()
	if document.dirty and kind!="preview": _autosave.start()
	if _refresh_queued: return
	_refresh_queued=true; _refresh.call_deferred()

func _field_focused() -> bool:
	var focus:=get_viewport().gui_get_focus_owner()
	return document.editing or (focus!=null and %RightPanel.is_ancestor_of(focus))

func _refresh() -> void:
	_refresh_queued=false
	if not document.editing:
		selection=PackedStringArray(Array(selection).filter(func(id):return not document.find("objects",id).is_empty()))
		var valid_items := PackedStringArray()
		for track: Dictionary in document.entries("tracks"):
			for item: Dictionary in track.keys+track.clips:
				if item.id in selected_items:valid_items.append(item.id)
		if valid_items!=selected_items:
			selected_items=valid_items;selected_item=selected_items[0] if selected_items.size()==1 else "";timeline.selected=selected_items.duplicate();_refresh_inspector=true
		surface.selected=selection.duplicate()
	if _refresh_tree: _refresh_objects()
	if _refresh_preview: _update_show()
	if _refresh_checks: refresh_problems()
	if _refresh_inspector and not _field_focused() and inspector_mode!="boss": inspector.refresh()
	_refresh_tree=false; _refresh_preview=false; _refresh_checks=false; _refresh_inspector=false
	for index in _scene.item_count:
		if _scene.get_item_metadata(index)==document.data.scene_id: _scene.select(index)
	var signature:=str(document.data.scene_id)+"|"+str(document.data.rule_path)+"|"+difficulty()
	if not song_document.charts.is_empty() and signature!=_stage_signature: _refresh_song_preview()

func _effective_show() -> Dictionary:
	var show:Dictionary=document.data.show.duplicate(true)
	for pair in [["objects",_candidate_objects],["tracks",_candidate_tracks]]:
		if auto_key and pair[0]=="objects":continue
		for candidate:Dictionary in pair[1]:
			for index in show[pair[0]].size():
				if show[pair[0]][index].id==candidate.id:show[pair[0]][index]=candidate
	if auto_key:
		# 拖动只覆盖当前时刻的候选键，基础值和正式文档等松手后再提交。
		for object_data:Dictionary in _candidate_objects:
			for property:String in ["position","rotation","scale"]:
				var target:Dictionary={}
				for track:Dictionary in show.tracks:
					if track.object_id==object_data.id and track.property==property and track.section==section and track.difficulties==([difficulty()] if difficulty_only else []):target=track;break
				if target.is_empty():
					target=LevelFormat.track(object_data.id,property,section);target.difficulties=[difficulty()] if difficulty_only else [];show.tracks.append(target)
				var found:=false
				for key:Dictionary in target.keys:
					if int(key.time_us)==time_us:key.value=object_data.fields[property];found=true;break
				if not found:target.keys.append(LevelFormat.key(time_us,object_data.fields[property]))
	for track:Dictionary in show.tracks:track.keys.sort_custom(func(a,b):return int(a.time_us)<int(b.time_us))
	return show

func _update_show() -> void:
	var player:=show_player()
	if player==null:
		_standalone=LevelShowPlayer.new();viewport.add_child(_standalone);player=_standalone
	var show:=_effective_show()
	var signature:=JSON.stringify(show.objects.map(func(value):return [value.id,value.type,value.asset]))+JSON.stringify(document.data.packs)+document.directory
	if signature!=_show_signature:
		player.configure(show,document.directory,document.data.packs,difficulty());_show_signature=signature
	else:player.show=show;player.difficulty=difficulty();player.prepare_parameters()
	_assets=player.assets;surface.player=player
	if is_instance_valid(preview.stage_root):
		var boss_key := JSON.stringify([show.bindings,show.objects.map(func(item):return [item.id,item.asset,item.parent_id,item.layer,item.fields.get("position"),item.fields.get("rotation"),item.fields.get("scale")]),show.tracks.filter(func(track):return track.type=="action" or track.property in ["position","rotation","scale"]),difficulty(),_stage_signature])
		if boss_key!=_boss_signature:
			_compiled_boss=LevelBossCompiler.compile(preview.stage_root.stage_session.stage_definition,preview.stage_root.stage_session.compiled_chart.tempo_map,player); _boss_signature=boss_key
		var compiled: Dictionary=_compiled_boss
		player.show.tracks.append_array(compiled.tracks)
		surface.emissions=compiled.emissions
		var rows:={}
		for track:Dictionary in compiled.tracks:
			var row_id:="generated_"+str(track.object_id)+"_"+str(track.type)
			if not rows.has(row_id):
				var row:=track.duplicate(true);row.id=row_id;row.clips=[];row.generated=true;row.locked=true;rows[row_id]=row
			for clip:Dictionary in track.clips:
				var copy:=clip.duplicate(true);copy.binding_id=track.binding_id;rows[row_id].clips.append(copy)
		timeline.generated_tracks=rows.values();timeline.rebuild_rows()
		if compiled.emissions!=preview.stage_root.chart_scheduler.boss_emissions:
			preview.stage_root.chart_scheduler.configure_boss_emissions(compiled.emissions)
			if _candidate_objects.is_empty() and _candidate_tracks.is_empty() and not _loading:preview.seek_preview(time_us)
	_sample_show(true);_request_clip_waveforms()
	if signature!=_asset_signature: _asset_signature=signature;_refresh_assets()

func _request_clip_waveforms() -> void:
	for track:Dictionary in document.entries("tracks"):
		if track.type!="audio":continue
		for clip:Dictionary in track.clips:
			var path:=document.directory.path_join(str(clip.asset))
			if not FileAccess.file_exists(path):continue
			var modified:=FileAccess.get_modified_time(path)
			if _wave_versions.get(path,-1)==modified:continue
			_wave_versions[path]=modified
			var holder:={"result":{}}
			var task:=WorkerThreadPool.add_task(func():holder.result=StudioAudio.decode_peaks(path))
			_wave_jobs.append({"id":task,"asset":clip.asset,"directory":document.directory,"version":modified,"path":path,"holder":holder})

func _sample_show(silent:bool) -> void:
	var player:=show_player()
	if player==null:return
	player.playing=audio.playing;player.playback_rate=audio.rate
	player.advance(section,time_us,not silent and audio.playing)
	surface.queue_redraw()

func _refresh_song_preview() -> void:
	if song_document.charts.is_empty():return
	_loading=true;audio.set_playing(false)
	var loaded:=LevelProjectLoader.make_stage(document.data,document.directory,difficulty(),{},false)
	if not loaded.errors.is_empty():_loading=false;message(ChartProjectLoader.describe_issues(loaded.errors));return
	if is_instance_valid(_standalone):viewport.remove_child(_standalone);_standalone.queue_free();_standalone=null
	_boss_signature=""
	_stage_signature=str(document.data.scene_id)+"|"+str(document.data.rule_path)+"|"+difficulty()
	preview.sound_enabled=false
	if preview.load_preview(loaded.stage,viewport):
		preview.stage_root.level_show_external=true
		preview.stage_root.hud.hide()
		_show_signature="";_update_show()
		preview.seek_preview(time_us if section=="song" else 0)
	timeline.tempo=song_document.tempo_map();timeline.sections=song_document.chart().sections
	timeline.difficulty=difficulty();timeline.reference_notes=[]
	for note in ChartEditEvents.all(song_document.chart()):
		if note is NoteEvent or note is GhostEvent: timeline.reference_notes.append({"id":note.event_id,"time_us":timeline.tempo.tick_to_us(note.tick)})
	timeline.rebuild_rows()
	_loading=false

func seek(us:int) -> void:
	_scrub(us); _finish_seek()

func _scrub(us:int) -> void:
	_seeking=true; time_us=us; audio.seek(float(us)/1000000.0); _seeking=false
	_seek_pending=section=="song"; timeline.time_us=us; timeline.update_cursor()
	if not _seek_pending and show_player()!=null: show_player().seek(section,us)

func _finish_seek() -> void:
	if _seek_pending:
		_seek_pending=false; _seek_elapsed=0; preview.seek_preview(time_us)
	if show_player()!=null: show_player().seek(section,time_us)
	if inspector_mode!="boss" and not _field_focused(): inspector.refresh()

func set_section(value:String) -> void:
	_store_view(); _prepare_command(); audio.set_playing(false)
	section=value; timeline.section=value; timeline.rebuild_rows(); _section.select(LevelFormat.SECTIONS.find(value))
	_loading=true; audio.set_stream(song_document.song.audio_stream if value=="song" and song_document.song!=null else null); _loading=false
	_restore_view()

func toggle_play() -> void:
	_follow_suspended=false;_follow.text="跟随"
	audio.set_playing(not audio.playing)

func _position_changed(seconds:float) -> void:
	time_us=roundi(seconds*1000000);timeline.time_us=time_us;timeline.update_cursor();_position.text="%8.3f s"%seconds
	if audio.playing:
		if _follow.button_pressed and not _follow_suspended:timeline.focus_time(time_us)
		if section=="song":preview.advance(seconds,true)
		else:
			var duration:=int(document.data.get(section+"_us",0))
			if duration>0 and time_us>=duration:audio.set_playing(false)
	_sample_show(not audio.playing)

func _process(delta:float) -> void:
	_seek_elapsed+=delta
	if _seek_pending and _seek_elapsed>=0.05: _seek_pending=false; _seek_elapsed=0; preview.seek_preview(time_us)
	%Loading.visible=_loading_started>=0 and Time.get_ticks_msec()-_loading_started>=200
	if %Loading.visible: %Loading/Message.text="正在加载和定位"+"·".repeat(int(Time.get_ticks_msec()/350)%4)
	for index in range(_wave_jobs.size()-1,-1,-1):
		var job:Dictionary=_wave_jobs[index]
		if WorkerThreadPool.is_task_completed(job.id):
			WorkerThreadPool.wait_for_task_completion(job.id);_wave_jobs.remove_at(index)
			if job.directory==document.directory and _wave_versions.get(job.path,-1)==job.version and job.holder.result.has("peaks"):
				timeline.clip_waveforms[job.asset]=job.holder.result;timeline.queue_redraw()
	if _trial_pid<=0:return
	_trial_poll+=delta
	if _trial_poll<0.3:return
	_trial_poll=0
	_read_trial_status()
	if not OS.is_process_running(_trial_pid):
		_trial_pid=-1;_trial_button.disabled=false;_trial_button.text="在游戏中试玩"
		_set_background(_background)
		_status.text="试玩已结束，可继续编排" if _trial_stage=="ready" else "试玩未完成加载，请查看日志："+_trial_folder.path_join("game.log")

func _exit_tree() -> void:
	for job:Dictionary in _wave_jobs:WorkerThreadPool.wait_for_task_completion(job.id)

func _unhandled_key_input(event:InputEvent) -> void:
	if _background or _modal_open() or not event is InputEventKey or not event.pressed or event.echo:return
	var focus:=get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:return
	if event.ctrl_pressed:
		match event.keycode:
			KEY_S:save()
			KEY_O:_open()
			KEY_N:_new()
			KEY_Z:document.undo(event.shift_pressed)
			KEY_Y:document.undo(true)
			KEY_C:
				if edit_target=="timeline":timeline.copy_selected()
				else:copy_objects()
			KEY_V:
				if edit_target=="timeline":timeline.paste_selected()
				else:paste_objects()
			_:return
	else:
		match event.keycode:
			KEY_SPACE:toggle_play()
			KEY_DELETE:delete_selection()
			KEY_W:_set_transform_mode("move")
			KEY_E:_set_transform_mode("rotate")
			KEY_R:_set_transform_mode("scale")
			KEY_S:timeline.split_selected()
			KEY_I:audio.loop_start=audio.position;timeline.loop_start_us=time_us
			KEY_O:audio.loop_end=audio.position;timeline.loop_end_us=time_us
			KEY_HOME:seek(0)
			KEY_ESCAPE:surface.cancel_drag();timeline.cancel_drag()
			_:return
	get_viewport().set_input_as_handled();surface.queue_redraw();timeline.queue_redraw()

func _shortcut_input(event:InputEvent) -> void:
	if _background or _modal_open() or not event is InputEventKey or not event.pressed or event.echo:return
	if event.ctrl_pressed and event.keycode==KEY_S:
		save(); get_viewport().set_input_as_handled(); return
	if event.keycode!=KEY_SPACE:return
	var focus:=get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:return
	toggle_play();get_viewport().set_input_as_handled()

func _modal_open() -> bool:
	return get_viewport().gui_get_focus_owner()!=null and get_viewport().gui_get_focus_owner().get_window()!=get_window() or _visible_window(self)

func _visible_window(node: Node) -> bool:
	for child in node.get_children():
		if child is Window and child.visible: return true
		if _visible_window(child): return true
	return false

func _cancel_gestures() -> void:
	surface.cancel_drag(); timeline.cancel_drag()
	for node in inspector.find_children("*","Control",true,false):
		if node is LevelCurveEditor: node.cancel_drag()

func _prepare_command() -> void:
	LevelUI.finish_fields(%RightPanel); document.end_edit(); _cancel_gestures()

func _set_background(value: bool) -> void:
	_background=value
	if value:
		_cancel_gestures(); document.end_edit(true); audio.set_playing(false); _audition.stop()
	preview.set_suspended(value); Engine.max_fps=10 if value else 60
	if not preview.rebuilding: viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED if value else SubViewport.UPDATE_ALWAYS

func _preview_loading(active: bool) -> void:
	if active and _loading_started<0: _loading_started=Time.get_ticks_msec()
	elif not active: _loading_started=-1; %Loading.hide()

func add_object(kind:String) -> void:
	var id:=document.add_object(kind);select_objects(PackedStringArray([id]));_left_panel.current_tab=1

func add_asset_object(asset:String,at:=Vector2(960,540)) -> void:
	var resource:=_assets.resolve(asset)
	var kind:="actor" if resource is PackedScene else ("audio" if resource is AudioStream else "sprite")
	var object_data:=LevelFormat.object(kind,asset);object_data.fields.position=[at.x,at.y]
	object_data.name=asset.get_file().get_basename() if not _assets.entries.has(asset) else str(_assets.entries[asset].display_name)
	if object_data.name.is_empty():object_data.name=asset
	document.replace("从素材库添加对象","objects",[],[object_data]);select_objects(PackedStringArray([object_data.id]))
	if kind=="audio":add_clip("audio")

func set_object_field(field:String,value:Variant) -> void:
	var before:=[];var after:=[]
	for id in selection:
		var object_data:=document.find("objects",id)
		if object_data.is_empty():continue
		before.append(object_data.duplicate(true));object_data=object_data.duplicate(true);object_data[field]=value;after.append(object_data)
	if before!=after:document.replace("修改对象"+field,"objects",before,after)

func set_property(property:String,value:Variant) -> void:
	if auto_key:
		var changes:=[]
		# 多选作为一次撤销：先在独立文档上组装受影响轨道，再一次提交。
		var candidate:=LevelDocument.new();candidate.reset(document.data)
		for id in selection:candidate.set_key(id,property,section,time_us,value,difficulty() if difficulty_only else "")
		for track:Dictionary in candidate.entries("tracks"):
			var original:=document.find("tracks",track.id)
			if original!=track:changes.append({"kind":"tracks","before":[] if original.is_empty() else [original.duplicate(true)],"after":[track]})
		if not changes.is_empty():document.commit("自动记录"+str(LevelFormat.PROPERTIES.get(property,property)),changes)
		return
	var before:=[];var after:=[]
	for id in selection:
		var object_data:=document.find("objects",id)
		if object_data.is_empty() or object_data.locked:continue
		before.append(object_data.duplicate(true));object_data=object_data.duplicate(true);object_data.fields[property]=value;after.append(object_data)
	if before!=after:document.replace("修改基础"+str(LevelFormat.PROPERTIES.get(property,property)),"objects",before,after)

func key_property(property:String) -> void:
	var candidate:=LevelDocument.new();candidate.reset(document.data)
	for id in selection:
		var object_data:=document.find("objects",id)
		if object_data.is_empty() or object_data.locked:continue
		var state:=LevelShowSampler.object_state(document.data.show,object_data,section,time_us,difficulty())
		var fallback:Variant=object_data.fields.get(property)
		if _assets.entries.has(object_data.asset):fallback=_assets.entries[object_data.asset].exposed_parameters.get(property,{}).get("default",fallback)
		if fallback is Vector2:fallback=[fallback.x,fallback.y]
		if fallback is Color:fallback=fallback.to_html()
		candidate.set_key(id,property,section,time_us,state.get(property,fallback),difficulty() if difficulty_only else "")
	var before:=[];var after:=[]
	for track:Dictionary in candidate.entries("tracks"):
		var original:=document.find("tracks",track.id)
		if original!=track:
			if not original.is_empty():before.append(original.duplicate(true))
			after.append(track)
	if not after.is_empty():document.replace("插入关键帧","tracks",before,after)

func _commit_transform(before:Array,after:Array) -> void:
	if not auto_key:
		if before!=after:document.replace("变换对象","objects",before,after)
		return
	var candidate:=LevelDocument.new();candidate.reset(document.data)
	for index in after.size():
		for property in ["position","rotation","scale"]:
			if before[index].fields[property]!=after[index].fields[property]:candidate.set_key(after[index].id,property,section,time_us,after[index].fields[property],difficulty() if difficulty_only else "")
	var old_tracks:=[];var new_tracks:=[]
	for track:Dictionary in candidate.entries("tracks"):
		var original:=document.find("tracks",track.id)
		if original!=track:
			if not original.is_empty():old_tracks.append(original.duplicate(true))
			new_tracks.append(track)
	if not new_tracks.is_empty():document.replace("记录对象变换","tracks",old_tracks,new_tracks)

func set_track_field(id:String,field:String,value:Variant) -> void:
	var before:=document.find("tracks",id);var after:=before.duplicate(true);after[field]=value
	if before!=after:document.replace("修改轨道","tracks",[before],[after])

func set_item_field(track_id:String,item_id:String,field:String,value:Variant) -> void:
	var before:=document.find("tracks",track_id);var after:=before.duplicate(true)
	for item:Dictionary in after.keys+after.clips:
		if item.id==item_id:
			item[field]=value
			if field=="out_handle":item.out_handle[0]=clampf(float(item.out_handle[0]),0,float(item.in_handle[0]))
			elif field=="in_handle":item.in_handle[0]=clampf(float(item.in_handle[0]),float(item.out_handle[0]),1)
	after.keys.sort_custom(func(a,b):return int(a.time_us)<int(b.time_us))
	if before!=after:document.replace("修改关键帧或片段","tracks",[before],[after])

func set_key_curve(track_id:String,key_id:String,first:Vector2,second:Vector2) -> void:
	var before:=document.find("tracks",track_id);var after:=before.duplicate(true)
	var key:=LevelFormat.find(after.keys,key_id)
	key.interpolation="bezier";key.out_handle=[first.x,first.y];key.in_handle=[second.x,second.y]
	document.replace("调整贝塞尔曲线","tracks",[before],[after])

func add_clip(kind:String) -> void:
	if selection.is_empty():message("先选择一个对象，再添加演出片段。");return
	var object_data:=document.find("objects",selection[0])
	var track:=LevelFormat.track(object_data.id,kind,section,kind);track.difficulties=[difficulty()] if difficulty_only else []
	var clip:=LevelFormat.clip(time_us,str(object_data.asset) if kind=="audio" else "",2000000)
	clip.name={"action":"动作","visibility":"显示区间","audio":"音频","sequence":"演出片段"}.get(kind,kind)
	if kind=="action":
		var actions:=_assets.actions(object_data.asset)
		clip.action=actions[0] if not actions.is_empty() else "idle"
	if kind=="audio":
		var stream:=_assets.resolve(str(clip.asset)) as AudioStream
		if stream!=null:clip.duration_us=roundi(stream.get_length()*1000000)
	track.clips=[clip];document.replace("添加"+str(clip.name),"tracks",[],[track])
	select_objects(selection,track.id,clip.id)

func copy_objects() -> void:document.copy_objects(selection)
func paste_objects() -> void:
	select_objects(document.paste_objects())
	if Array(selection).any(func(id):return document.find("objects",id).type=="actor"): _status.text="已复制演出；BOSS 副本尚未绑定音符"
func mirror_objects() -> void:document.copy_objects(selection);select_objects(document.paste_objects(true))
func delete_selection() -> void:
	if edit_target=="timeline":timeline.delete_selected();return
	var unlocked:=PackedStringArray()
	for id in selection:
		if not document.find("objects",id).get("locked",false):unlocked.append(id)
	document.delete_objects(unlocked);select_objects(PackedStringArray())

func align_center() -> void:
	set_property("position",[960.0,540.0])

func group_objects() -> void:
	if selection.is_empty():return
	var before:=[];var after:=[];var parent:=str(document.find("objects",selection[0]).parent_id)
	var layer:=str(document.find("objects",selection[0]).layer)
	for id in selection:
		var object_data:=document.find("objects",id)
		if object_data.parent_id!=parent or object_data.layer!=layer:message("请在同一父组和同一坐标层内选择对象，再建立新组。");return
		before.append(object_data.duplicate(true))
	var group:=LevelFormat.object("group");group.parent_id=parent;group.layer=layer;group.fields.position=[0.0,0.0]
	after.append(group)
	for source:Dictionary in before:
		var object_data:=source.duplicate(true);object_data.parent_id=group.id;object_data.layer="world";after.append(object_data)
	document.replace("对象分组","objects",before,after);select_objects(PackedStringArray([group.id]))

func ungroup_objects() -> void:
	var difficulties:=PackedStringArray()
	for chart:SongChart in song_document.charts:difficulties.append(chart.difficulty_id)
	if difficulties.is_empty():difficulties.append(difficulty())
	var changes:=LevelGroupBake.changes(document.data.show,selection,difficulties)
	if not changes.is_empty():document.commit("解组并烘焙变换",changes);select_objects(PackedStringArray())

func audition_clip(clip:Dictionary) -> void:
	_audition.stop();_audition.stream=_assets.resolve(str(clip.asset)) as AudioStream
	if _audition.stream==null:message("找不到可试听的音频。");return
	_audition.volume_db=float(clip.gain_db);_audition.pitch_scale=float(clip.rate);_audition.play(float(clip.offset_us)/1000000)
	var playback_id:=Time.get_ticks_usec();_audition.set_meta("audition_id",playback_id)
	get_tree().create_timer(float(clip.duration_us)/1000000).timeout.connect(func():
		if is_instance_valid(_audition) and _audition.get_meta("audition_id")==playback_id:_audition.stop())

func _ensure_directory(action:Callable) -> void:
	if not document.directory.is_empty():action.call();return
	_file_dialog("选择关卡工程目录",FileDialog.FILE_MODE_OPEN_DIR,[],func(path):
		if _save_to(path):action.call())

func save() -> void:
	_prepare_command(); _ensure_directory(func():_save_to(document.directory))

func _save_to(path:String) -> bool:
	_prepare_command()
	workspace_state.merge(_workspace_snapshot(),true)
	var previous_directory:=document.directory
	var error:=LevelProjectIO.save(document.data,path,workspace_state)
	if not error.is_empty():message(error);return false
	document.directory=path;document.mark_saved();_remember(path.path_join("level.json"));_autosave.stop()
	_discard_recovery(previous_directory)
	_status.text="已保存："+path;return true

func _save_as() -> void:
	_file_dialog("关卡另存为 · 选择新目录",FileDialog.FILE_MODE_OPEN_DIR,[],_save_as_to)

func _save_as_to(path:String) -> bool:
	_prepare_command()
	if not document.directory.is_empty() and ProjectSettings.globalize_path(path).simplify_path()!=ProjectSettings.globalize_path(document.directory).simplify_path():
		for relative in LevelProjectIO.dependencies(document.data,document.directory):
			if relative in ["level.json","show.json"]:continue
			var source:=document.directory.path_join(relative)
			if not FileAccess.file_exists(source):continue
			DirAccess.make_dir_recursive_absolute(path.path_join(relative).get_base_dir())
			if DirAccess.copy_absolute(source,path.path_join(relative))!=OK:message("复制依赖失败："+relative);return false
	if not _save_to(path):return false
	_show_signature="";_read_song();_update_show();return true

func _new() -> void:
	_discard_or(func():
		_autosave.stop();audio.set_playing(false);preview.clear_preview();song_document=StudioDocument.new();workspace_state={};_views.clear();document.reset(LevelFormat.new_level())
		_loading=true;audio.set_stream(null);_loading=false
		timeline.generated_tracks.clear();timeline.clip_waveforms.clear();_wave_versions.clear()
		_stage_signature="";_show_signature="";selection.clear();selected_track="";selected_item="";_difficulty.clear();section="song";timeline.section="song";_views.clear();_restore_view())

func _open() -> void:
	_discard_or(func():_file_dialog("打开关卡工程或关卡包",FileDialog.FILE_MODE_OPEN_FILE,["*.json ; 关卡文档","*.zip ; 关卡包"],_open_path))

func _open_path(path:String) -> void:
	_prepare_command(); _autosave.stop()
	if path.get_extension().to_lower()=="zip":
		_file_dialog("解压关卡包到制作目录",FileDialog.FILE_MODE_OPEN_DIR,[],func(folder):
			var error:=LevelProjectIO.unpack(path,folder)
			if not error.is_empty():message(error)
			else:_open_path(folder.path_join("level.json")))
		return
	var opened:=LevelProjectIO.open_project(path)
	if not opened.error.is_empty():message(opened.error);return
	audio.set_playing(false);preview.clear_preview();song_document=StudioDocument.new()
	workspace_state=opened.workspace;document.reset(opened.level,opened.directory);selection.clear();selected_track="";selected_item=""
	timeline.generated_tracks.clear();timeline.clip_waveforms.clear();_wave_versions.clear()
	_stage_signature="";_show_signature="";_read_song();_apply_workspace(workspace_state);_remember(path)
	_status.text="已打开："+str(document.data.title)

func import_song() -> void:
	_ensure_directory(func():_file_dialog("导入写谱器歌曲 song.json",FileDialog.FILE_MODE_OPEN_FILE,["*.json ; 歌曲清单"],func(path):
		var error:=LevelProjectIO.import_song(path,document.directory)
		if not error.is_empty():message(error);return
		workspace_state.song_source=path;_read_song();document.fields("导入歌曲",{"song_path":"song/song.json"});_write_recovery()))

func refresh_song() -> void:
	var source:=str(workspace_state.get("song_source",""))
	if source.is_empty() or not FileAccess.file_exists(source):import_song();return
	var error:=LevelProjectIO.import_song(source,document.directory)
	if not error.is_empty():message(error);return
	_stage_signature="";_read_song();refresh_problems();_status.text="谱面副本已刷新；绑定继续按稳定音符 ID 关联"

func _read_song() -> void:
	var previous_difficulty:=difficulty()
	var path:=document.directory.path_join(str(document.data.song_path))
	if not FileAccess.file_exists(path):return
	var error:=StudioProjectIO.open_project(path,song_document)
	if not error.is_empty():message(error);return
	_difficulty.clear()
	for chart in song_document.charts:_difficulty.add_item(str(chart.get_meta("json_source",{}).get("difficulty_name",chart.difficulty_id)))
	for index in song_document.charts.size():
		if song_document.charts[index].difficulty_id==previous_difficulty:song_document.current=index;_difficulty.select(index)
	_loading=true;audio.set_stream(song_document.song.audio_stream if section=="song" else null);_loading=false
	var raw:=ChartJsonCodec.encode_song(song_document.song)
	audio.build_waveform(song_document.directory.path_join(str(raw.get("audio",""))))
	_stage_signature="";_refresh_song_preview()

func import_asset() -> void:
	_ensure_directory(func():_file_dialog("导入图片、声音或字体",FileDialog.FILE_MODE_OPEN_FILE,["*.png,*.jpg,*.jpeg,*.webp,*.svg ; 图片","*.wav,*.ogg,*.mp3 ; 音频","*.ttf,*.otf ; 字体"],_import_asset_path))

func _import_asset_path(path:String) -> void:
	var imported:=LevelProjectIO.import_file(path,document.directory)
	if not imported.error.is_empty():message(imported.error);return
	_assets.cache.erase(imported.path);_show_signature="";_asset_signature="";_update_show();_status.text="已导入 "+str(imported.path)+" · 双击或拖入预览"

func import_pack() -> void:
	_ensure_directory(func():_file_dialog("导入 Godot 素材包描述",FileDialog.FILE_MODE_OPEN_FILE,["*.assetpack.json ; 素材包描述"],func(path):
		var descriptor:=LevelProjectIO.read_json(path)
		if descriptor.get("format","")!="minghe-assets":message("请选择与 PCK 一起导出的 .assetpack.json。");return
		var imported:=LevelProjectIO.import_file(path.get_base_dir().path_join(str(descriptor.pack)),document.directory,"packs/"+LevelFormat.id("revision"))
		if not imported.error.is_empty():message(imported.error);return
		var packs:Array=document.data.packs.duplicate(true)
		var entry:={"path":imported.path,"manifest":descriptor.manifest,"name":descriptor.get("name","")}
		var existing:=-1
		for index in packs.size():
			if packs[index].manifest==descriptor.manifest:existing=index;break
		if existing>=0:
			packs[existing]=entry;document.fields("更新素材包",{"packs":packs});save()
			message("素材包已更新并保存工程。请重新启动工具并打开本工程，清理 Godot 资源包缓存后使用新版素材。")
		else:packs.append(entry);document.fields("导入素材包",{"packs":packs});_show_signature="";_update_show()))

func export_package() -> void:
	_prepare_command()
	_ensure_directory(func():_file_dialog("导出完整关卡包",FileDialog.FILE_MODE_SAVE_FILE,["*.zip ; 关卡包"],func(path):
		refresh_problems()
		var issues:=LevelFormat.issues(document.data,song_document.charts);issues.append_array(_assets.validate_level(document.data))
		if not issues.is_empty():message(ChartProjectLoader.describe_issues(issues));return
		var error:=LevelProjectIO.export_zip(document.data,document.directory,path)
		if not error.is_empty():message(error)
		else:_status.text="已导出关卡包："+path))

func _discard_or(action:Callable) -> void:
	_prepare_command()
	if not document.dirty:action.call();return
	var dialog:=ConfirmationDialog.new();dialog.title="保存未完成的关卡";dialog.dialog_text="当前工程有未保存修改。";dialog.ok_button_text="保存并继续";dialog.cancel_button_text="取消"
	add_child(dialog);dialog.add_button("不保存",false,"discard")
	dialog.confirmed.connect(func():dialog.queue_free();_ensure_directory(func():
		if _save_to(document.directory):action.call()))
	dialog.custom_action.connect(func(_name):_discard_recovery(document.directory);dialog.queue_free();action.call())
	dialog.canceled.connect(dialog.queue_free);_popup(dialog,Vector2i(520,180))

func _workspace_snapshot() -> Dictionary:
	_store_view()
	var visible_layout: Dictionary=_focus_layout if not _focus_layout.is_empty() else {"left":_left_panel.visible,"right":%RightPanel.visible,"bottom":%Bottom.visible}
	return {"left_width":_left_width,"right_width":_right_width,"timeline_height":_timeline_height,"time_us":time_us,"section":section,"zoom":timeline.pixels_per_second,"left_seconds":timeline.left_seconds,"difficulty":difficulty(),"views":_views.duplicate(true),"panels":visible_layout.duplicate()}

func _apply_workspace(state:Dictionary) -> void:
	_left_width=int(state.get("left_width",state.get("left_split",220))); _right_width=int(state.get("right_width",310)); _timeline_height=int(state.get("timeline_height",270)); _queue_layout()
	for index in song_document.charts.size():
		if song_document.charts[index].difficulty_id==state.get("difficulty",""): song_document.current=index; _difficulty.select(index); break
	section=str(state.get("section","song")); timeline.section=section; _section.select(LevelFormat.SECTIONS.find(section))
	_views=state.get("views",{}).duplicate(true)
	if not _views.has(_view_key()): _views[_view_key()]={"time_us":state.get("time_us",0),"zoom":state.get("zoom",100),"left_seconds":state.get("left_seconds",0)}
	if not song_document.charts.is_empty():
		_loading=true; audio.set_stream(song_document.song.audio_stream if section=="song" else null); _loading=false; _refresh_song_preview()
	_restore_view()
	var panels: Dictionary=state.get("panels",{})
	_left_panel.visible=bool(panels.get("left",true)); %RightPanel.visible=bool(panels.get("right",true)); %Bottom.visible=bool(panels.get("bottom",true))

func _write_recovery() -> void:
	if document.editing: _autosave.start();return
	workspace_state.merge(_workspace_snapshot(),true)
	StudioProjectIO.write_json(recovery_path,{"level":document.data,"directory":document.directory,"workspace":workspace_state,"updated":Time.get_datetime_string_from_system()})

func _offer_recovery() -> void:
	var recovery:=LevelProjectIO.read_json(recovery_path)
	if recovery.is_empty():return
	var dialog:=ConfirmationDialog.new();dialog.title="恢复未保存的工程";dialog.dialog_text="找到上次的恢复稿："+str(recovery.level.get("title","未命名关卡"))+"\n"+str(recovery.get("updated","时间未知"))+" · %d 个对象"%recovery.level.show.objects.size();dialog.ok_button_text="恢复";dialog.cancel_button_text="稍后"
	add_child(dialog);dialog.confirmed.connect(func():
		dialog.queue_free();workspace_state=recovery.get("workspace",{});document.reset(recovery.level,str(recovery.get("directory","")));document.saved_cursor=-1;document.dirty=true
		_read_song();_apply_workspace(workspace_state);_document_changed("project"))
	dialog.canceled.connect(dialog.queue_free);_popup(dialog,Vector2i(560,180))

func _load_preferences() -> void:
	var settings:=ConfigFile.new();settings.load("user://level_studio/settings.cfg")
	_recent=settings.get_value("files","recent",[]);_trial_executable=str(settings.get_value("trial","executable",""))
	_ui_scale=float(settings.get_value("ui","scale",0))

func _remember(path:String) -> void:
	_recent.erase(path);_recent.push_front(path)
	if _recent.size()>8:_recent.resize(8)
	_save_preferences()

func _save_preferences() -> void:
	var settings:=ConfigFile.new();settings.set_value("files","recent",_recent);settings.set_value("trial","executable",_trial_executable)
	settings.set_value("ui","scale",_ui_scale)
	DirAccess.make_dir_recursive_absolute("user://level_studio");settings.save("user://level_studio/settings.cfg")

func _files_dropped(files:PackedStringArray) -> void:
	for path in files:
		if path.get_file()=="level.json" or path.get_extension()=="zip":_discard_or(func():_open_path(path));return
		if document.directory.is_empty():message("先保存关卡工程，再把素材文件拖入窗口。");return
		_import_asset_path(path)

func refresh_problems() -> void:
	_problems.clear()
	var issues:=LevelFormat.issues(document.data,song_document.charts)
	issues.append_array(_assets.validate_level(document.data))
	if song_document.charts.is_empty():issues.append({"message":"尚未导入歌曲与谱面；可以保存草稿"})
	for issue:Dictionary in issues:_problems.add_item(str(issue.message));_problems.set_item_metadata(_problems.item_count-1,issue)
	%ProblemToggle.visible=not issues.is_empty(); %ProblemToggle.text="%d 个问题 · 点击展开 / 收起"%issues.size()
	_problems.visible=not issues.is_empty() and %ProblemToggle.button_pressed

func _locate_problem(index:int) -> void:
	var issue:Variant=_problems.get_item_metadata(index)
	if not issue is Dictionary:return
	if issue.has("binding_id"):
		var binding:=document.find("bindings",str(issue.binding_id))
		if not binding.is_empty():
			for chart_index in song_document.charts.size():
				if song_document.charts[chart_index].difficulty_id==binding.difficulty and song_document.current!=chart_index: _difficulty.select(chart_index);_switch_difficulty(chart_index)
			select_objects(PackedStringArray([str(binding.object_id)]));open_boss_binding(str(binding.id));return
	if issue.has("object_id"):select_objects(PackedStringArray([str(issue.object_id)]))
	elif issue.has("track_id"):
		var track:=document.find("tracks",str(issue.track_id))
		if not track.is_empty():
			if section!=track.section:set_section(track.section)
			select_objects(PackedStringArray([str(track.object_id)]),str(track.id))
	elif issue.has("binding_id"):
		var binding:=document.find("bindings",str(issue.binding_id))
		if not binding.is_empty():select_objects(PackedStringArray([str(binding.object_id)]));open_boss_binding(str(binding.id))
	if issue.has("time_us"):seek(int(issue.time_us));timeline.focus_time(time_us)

func _help() -> void:
	message("制作流程：导入 song.json → 导入素材包或图片 → 添加对象 → 编排关键帧和动作 → 绑定 BOSS 音符 → 试玩 → 导出关卡包。\n\n预览：W 移动 / E 旋转 / R 缩放；双指平移、Ctrl+滚动缩放、中键平移；Alt 暂时关闭画面吸附。\n时间线：双指两轴浏览，Ctrl+滚动缩放，中键平移；拖动关键帧/片段，拖片段边缘裁剪，S 拆分；Shift+拖动尺标设置循环区间。\nCtrl+S 保存，Ctrl+Z 撤销，Ctrl+C/V 复制粘贴，Delete 删除，Space 播放/暂停，Esc 取消拖动。\n自动关键帧关闭时修改基础属性；开启后把当前值写入游标处。HUD 使用正向屏幕坐标。\nGodot/Spine 负责素材内部结构，关卡工具调用已声明的动作与参数。素材包更新后保存并重新启动工具。")

func _view_action(id:int) -> void:
	if id>=100:_discard_or(func():_open_path(str(_recent[id-100])));return
	match id:
		0:_reset_layout()
		1:_left_panel.visible=not _left_panel.visible
		2:%RightPanel.visible=not %RightPanel.visible
		8:%Bottom.visible=not %Bottom.visible
		9:_toggle_focus_preview()
		3:_save_sequence()
		4:_insert_sequence()
		5:_import_legacy_cues()
		6:_relocate_asset()
		7:_choose_game()

func _reset_layout() -> void:
	_left_panel.show();%RightPanel.show();%Bottom.show();_focus_layout.clear()
	_left_width=220;_right_width=310;_timeline_height=270;_queue_layout()

func _apply_ui_scale() -> void:
	_cancel_gestures()
	var window:=get_window()
	# 与写谱器使用相同的 1280×720 缩放基准；小窗口仍留够可操作的逻辑画布。
	var desired:=_ui_scale if _ui_scale>0 else maxf(maxf(1,DisplayServer.screen_get_scale()),minf(window.size.x/1280.0,window.size.y/720.0))
	var factor:=minf(desired,maxf(1,minf(window.size.x/1024.0,window.size.y/720.0)))
	if not is_equal_approx(window.content_scale_factor,factor):window.content_scale_factor=factor
	for index in 5:_scale_menu.get_popup().set_item_checked(index,is_equal_approx(_ui_scale,[0.0,1.0,1.25,1.5,2.0][index]))
	_scale_menu.tooltip_text="当前界面缩放：%d%%；小窗口会自动限制倍率以保留可用空间"%roundi(factor*100)
	surface.update_resolution.call_deferred();_queue_layout()

func _queue_layout() -> void:
	if _layout_queued:return
	_layout_queued=true;_layout_panels.call_deferred()

func _layout_panels() -> void:
	_layout_queued=false
	# 记住用户拖出的侧栏宽度和时间线高度，最大化新增空间交给中央预览。
	_left_split.split_offset=_left_width
	_right_split.split_offset=maxi(320,roundi(_right_split.size.x)-_right_width)
	_vertical.split_offset=maxi(240,roundi(_vertical.size.y)-_timeline_height)
	surface.update_resolution.call_deferred()

func _set_transform_mode(value:String) -> void:
	surface.mode=value
	for key:String in _mode_buttons:_mode_buttons[key].set_pressed_no_signal(key==value)
	surface.queue_redraw()

func _fit_timeline() -> void:
	var start:=0;var end:=int(document.data.get(section+"_us",0))
	if section=="song" and song_document.song!=null and song_document.song.audio_stream!=null:end=roundi(song_document.song.audio_stream.get_length()*1000000)
	for track:Dictionary in document.entries("tracks"):
		if track.section!=section:continue
		for key:Dictionary in track.keys:start=mini(start,int(key.time_us));end=maxi(end,int(key.time_us))
		for clip:Dictionary in track.clips:start=mini(start,int(clip.start_us));end=maxi(end,int(clip.start_us)+int(clip.duration_us))
	timeline.left_seconds=float(start)/1000000-0.2
	timeline.pixels_per_second=maxf(1,(timeline.size.x-LevelTimeline.HEADER-20)/(maxf(1,float(end-start)/1000000)+0.4))
	_follow_suspended=true;timeline.queue_redraw()

func _save_sequence() -> void:
	if selection.is_empty():message("先选择要保存为演出片段的对象。");return
	document.copy_objects(selection)
	var data:=document.clipboard.duplicate(true);data.id=LevelFormat.id("sequence");data.name="演出片段 "+str(document.entries("sequences").size()+1)
	data.tracks=data.tracks.filter(func(track):return track.section==section)
	var start:=9223372036854775807
	for track:Dictionary in data.tracks:
		for key:Dictionary in track.keys:start=mini(start,int(key.time_us))
		for clip:Dictionary in track.clips:start=mini(start,int(clip.start_us))
	if start==9223372036854775807:start=0
	for track:Dictionary in data.tracks:
		for key:Dictionary in track.keys:key.time_us-=start
		for clip:Dictionary in track.clips:clip.start_us-=start
	document.replace("保存可复用演出片段","sequences",[],[data]);_status.text="已保存 "+str(data.name)+"，可从视图菜单插入"

func _insert_sequence() -> void:
	var sequences:=document.entries("sequences")
	if sequences.is_empty():message("先选中对象并使用“保存选区为演出片段”。");return
	var dialog:=ConfirmationDialog.new();dialog.title="插入演出片段";dialog.ok_button_text="在当前时间插入"
	var choice:=OptionButton.new();dialog.add_child(choice)
	for data:Dictionary in sequences:choice.add_item(str(data.name))
	add_child(dialog);dialog.confirmed.connect(func():
		var data:Dictionary=sequences[choice.selected].duplicate(true)
		for track:Dictionary in data.tracks:
			track.section=section
			for key:Dictionary in track.keys:key.time_us+=time_us
			for clip:Dictionary in track.clips:clip.start_us+=time_us
		document.clipboard=data;select_objects(document.paste_objects());dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);_popup(dialog,Vector2i(540,180))

func _relocate_asset() -> void:
	if selection.is_empty():message("先在对象列表或问题列表选中缺失素材的对象。");return
	_ensure_directory(func():_file_dialog("重新定位所选对象的素材",FileDialog.FILE_MODE_OPEN_FILE,["*.png,*.jpg,*.webp,*.svg,*.wav,*.ogg,*.mp3 ; 素材"],func(path):
		var imported:=LevelProjectIO.import_file(path,document.directory)
		if not imported.error.is_empty():message(imported.error)
		else:set_object_field("asset",imported.path)))

func _import_legacy_cues() -> void:
	var resolved:=ChartSceneLibrary.shared().resolve({"scene_id":document.data.scene_id,"use_scene_show":true})
	if resolved.show==null:message("当前基础场景没有旧演出。");return
	var show:Dictionary=document.data.show.duplicate(true)
	show.legacy_cues=[]
	for cue:ShowCue in resolved.show.cues:
		show.legacy_cues.append({"id":cue.event_id,"tick":cue.tick,"duration_ticks":cue.duration_ticks,"track":cue.track,"cue_id":str(cue.cue_id),"target_slot":str(cue.target_slot),"parameters":_json_parameters(cue.parameters)})
	document.fields("显式导入旧场景演出",{"show":show});_stage_signature=""
	_status.text="已导入旧 Cue 快照，重复导入会替换这份快照"

func _json_parameters(value:Variant) -> Variant:
	if value is Vector2:return {"_type":"Vector2","x":value.x,"y":value.y}
	if value is Color:return {"_type":"Color","html":value.to_html()}
	if value is Dictionary:
		var result:={}
		for key in value:result[key]=_json_parameters(value[key])
		return result
	if value is Array:return value.map(_json_parameters)
	return value

func open_boss_binding(binding_id:="") -> void:
	if selection.is_empty() or song_document.charts.is_empty(): message("先导入歌曲，并选择一个 BOSS 对象。");return
	if document.find("objects",selection[0]).get("type","")!="actor":message("请选择对象列表中的 BOSS / 场景对象，再编排攻击。");return
	_prepare_command(); boss_panel.open(selection[0],binding_id); _show_inspector("boss")

func test_feedback(hit:bool) -> void:
	if selection.is_empty() or show_player()==null:return
	var effect:=""
	for binding:Dictionary in document.entries("bindings"):
		if binding.object_id==selection[0] and binding.difficulty==difficulty() and (inspector_mode!="boss" or binding.id==boss_panel.binding_id):effect=str(binding.get("hit_effect" if hit else "miss_effect",""));break
	show_player().feedback(selection[0],hit,time_us,effect);_sample_show(true)

func _choose_game() -> void:
	_file_dialog("选择配套游戏 minghe.exe",FileDialog.FILE_MODE_OPEN_FILE,["*.exe ; Windows 游戏"],func(path):
		_trial_executable=path;_remember(document.directory.path_join("level.json"))
		if not _pending_trial.is_empty():_launch_trial())

func playtest() -> void:
	_prepare_command()
	if _trial_pid>0:return
	_ensure_directory(func():
		var loaded:=LevelProjectLoader.make_stage(document.data,document.directory,difficulty())
		if not loaded.errors.is_empty():message(ChartProjectLoader.describe_issues(loaded.errors));return
		_pending_trial={"level":document.data.duplicate(true),"directory":document.directory,"difficulty":difficulty()}
		if _trial_executable.is_empty():
			var bundled:=OS.get_executable_path().get_base_dir().path_join("game/minghe.exe")
			if FileAccess.file_exists(bundled):_trial_executable=bundled
		if _trial_executable.is_empty() or not FileAccess.file_exists(_trial_executable):_choose_game()
		else:_launch_trial())

func _launch_trial() -> void:
	var folder:="user://level_studio/trials/"+LevelFormat.id("trial")
	DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("level.zip")
	var error:=LevelProjectIO.export_zip(_pending_trial.level,_pending_trial.directory,path)
	if not error.is_empty():message(error);return
	_trial_folder=folder; _trial_request=LevelFormat.id("request"); _trial_stage=""; _trial_started=Time.get_ticks_msec(); _trial_timeout=false
	var args:=PackedStringArray(["--log-file",ProjectSettings.globalize_path(folder.path_join("game.log")),"--","--play-level",ProjectSettings.globalize_path(path),"--difficulty",_pending_trial.difficulty,"--trial-status",ProjectSettings.globalize_path(folder.path_join("status.json")),"--trial-request",_trial_request,"--trial-log",ProjectSettings.globalize_path(folder.path_join("game.log"))])
	_trial_pid=OS.create_process(_trial_executable,args,false)
	_pending_trial.clear()
	if _trial_pid<=0:message("无法启动配套游戏。");return
	audio.set_playing(false);_audition.stop()
	_trial_button.disabled=true;_trial_button.text="正在启动游戏…";_status.text="可以继续编辑；游戏使用启动时的关卡快照"

func _read_trial_status() -> void:
	var status := LevelProjectIO.read_json(_trial_folder.path_join("status.json"))
	if status.get("request_id","")==_trial_request and status.get("stage","")!=_trial_stage:
		_trial_stage=str(status.stage)
		_trial_button.text="试玩进行中" if _trial_stage=="ready" else ("试玩加载失败" if _trial_stage=="error" else "游戏正在加载…")
		_status.text="游戏已加载；可以继续编辑，试玩使用启动快照" if _trial_stage=="ready" else str(status.get("message","正在加载关卡"))
	if _trial_stage!="ready" and not _trial_timeout and Time.get_ticks_msec()-_trial_started>15000:
		_trial_timeout=true; _status.text="试玩尚未完成加载；请检查配套游戏。日志："+_trial_folder.path_join("game.log")

func _toggle_focus_preview() -> void:
	if _focus_layout.is_empty():
		_focus_layout={"left":_left_panel.visible,"right":%RightPanel.visible,"bottom":%Bottom.visible}
		_left_panel.hide(); %RightPanel.hide(); %Bottom.hide()
	else:
		_left_panel.visible=_focus_layout.left; %RightPanel.visible=_focus_layout.right; %Bottom.visible=_focus_layout.bottom; _focus_layout.clear()
	_queue_layout()

func _view_key() -> String: return section+"/"+difficulty()
func _store_view() -> void:
	_views[_view_key()]={"time_us":time_us,"zoom":timeline.pixels_per_second,"left_seconds":timeline.left_seconds,"row_scroll":timeline.row_scroll,"folded":timeline.folded.duplicate(),"selection":Array(selection),"items":Array(selected_items),"track":selected_track,"target":edit_target,"loop":audio.loop_enabled,"start":timeline.loop_start_us,"end":timeline.loop_end_us,"pan":[surface.pan.x,surface.pan.y],"canvas_zoom":surface.zoom,"follow":_follow.button_pressed,"suspended":_follow_suspended}

func _restore_view() -> void:
	var view: Dictionary=_views.get(_view_key(),{})
	timeline.pixels_per_second=float(view.get("zoom",100)); timeline.left_seconds=float(view.get("left_seconds",0)); timeline.row_scroll=float(view.get("row_scroll",0)); timeline.folded=view.get("folded",{}).duplicate()
	selection=PackedStringArray(view.get("selection",[])); selected_items=PackedStringArray(view.get("items",[])); selected_track=str(view.get("track","")); selected_item=selected_items[0] if selected_items.size()==1 else ""; edit_target=str(view.get("target","objects"))
	timeline.loop_start_us=int(view.get("start",0)); timeline.loop_end_us=int(view.get("end",4000000)); audio.loop_start=float(timeline.loop_start_us)/1000000; audio.loop_end=float(timeline.loop_end_us)/1000000; audio.loop_enabled=bool(view.get("loop",false)); _loop_toggle.set_pressed_no_signal(audio.loop_enabled)
	surface.pan=LevelFormat.vec(view.get("pan",[0,0])); surface.zoom=float(view.get("canvas_zoom",1)); _follow.set_pressed_no_signal(bool(view.get("follow",true))); _follow_suspended=bool(view.get("suspended",false))
	timeline.rebuild_rows(); _sync_selection(); seek(int(view.get("time_us",0)))

func _switch_difficulty(index: int) -> void:
	_store_view(); _prepare_command(); song_document.current=index; _stage_signature=""; _boss_signature=""; _refresh_song_preview(); _restore_view(); _show_inspector("properties")

func resource_field(parent: Node, caption: String, current: String, category: String, commit: Callable) -> void:
	var box := LevelUI.row(parent,caption)
	var value_id := [current]
	var button := Button.new(); box.add_child(button); button.text=_asset_caption(current)
	button.pressed.connect(func(): _choose_resource(category,value_id[0],func(value):commit.call(value);value_id[0]=value;button.text=_asset_caption(value);button.tooltip_text=value))
	# 路径用于排查素材，高频操作使用名称和选择器。
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; button.clip_text=true; button.tooltip_text=current


func _asset_caption(id: String) -> String:
	if id.is_empty(): return "选择素材…"
	return str(_assets.entries[id].display_name) if _assets.entries.has(id) else id.get_file()

func _choose_resource(category: String, current: String, commit: Callable) -> void:
	var dialog := ConfirmationDialog.new(); dialog.title="选择素材"; dialog.ok_button_text="使用所选素材"
	var column := VBoxContainer.new(); dialog.add_child(column)
	var search := LineEdit.new(); search.placeholder_text="搜索素材名称"; column.add_child(search)
	var list := ItemList.new(); list.custom_minimum_size=Vector2(420,200); column.add_child(list)
	var texture := TextureRect.new(); texture.custom_minimum_size.y=140; texture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; texture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; column.add_child(texture)
	var font_sample := Label.new(); font_sample.text="冥河，冥河！"; font_sample.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; font_sample.hide(); column.add_child(font_sample)
	var view := SubViewport.new(); view.size=Vector2i(640,360); view.render_target_update_mode=SubViewport.UPDATE_DISABLED; dialog.add_child(view)
	var player := LevelShowPlayer.new(); view.add_child(player)
	var populate := func():
		list.clear(); list.add_item("无"); list.set_item_metadata(0,"")
		var choices := []
		for id: String in _assets.entries:
			if category in ["all","scene","effect"]: choices.append(id)
		for path: String in _assets.list_files():
			var ext := path.get_extension().to_lower()
			if category=="all" or (category=="audio" and ext in ["wav","ogg","mp3"]) or (category=="font" and ext in ["ttf","otf"]) or (category in ["image","effect"] and ext in ["png","jpg","jpeg","webp","svg"]): choices.append(path)
		for id: String in choices:
			if not search.text.is_empty() and not search.text.to_lower() in (_asset_caption(id)+id).to_lower(): continue
			list.add_item(_asset_caption(id)); list.set_item_metadata(list.item_count-1,id); list.set_item_tooltip(list.item_count-1,id)
			if id==current: list.select(list.item_count-1)
	var apply := func():
		if list.get_selected_items().is_empty(): return
		commit.call(str(list.get_item_metadata(list.get_selected_items()[0]))); dialog.queue_free()
	search.text_changed.connect(func(_value):populate.call()); list.item_activated.connect(func(_index):apply.call()); dialog.confirmed.connect(apply); dialog.canceled.connect(dialog.queue_free)
	LevelUI.button(column,"预览 / 试听所选素材",func():
		if list.get_selected_items().is_empty(): return
		var id:=str(list.get_item_metadata(list.get_selected_items()[0]))
		if category=="audio":
			_audition.stream=_assets.resolve(id) as AudioStream
			if _audition.stream!=null: _audition.play()
		else:
			var resource := _assets.resolve(id)
			texture.show(); font_sample.hide()
			if resource is Texture2D: texture.texture=resource
			elif resource is PackedScene:
				var actor := LevelFormat.object("actor",id); actor.fields.position=[320,180]
				player.configure({"objects":[actor],"tracks":[],"bindings":[]},document.directory,document.data.packs,difficulty())
				player.seek("song",0); texture.texture=view.get_texture();view.render_target_update_mode=SubViewport.UPDATE_ONCE
			elif resource is Font: texture.hide(); font_sample.show();font_sample.add_theme_font_override("font",resource)
	)
	dialog.visibility_changed.connect(func():
		if not dialog.visible:_audition.stop())
	add_child(dialog); populate.call(); _popup(dialog,Vector2i(540,490))

func _add_menu(parent: Node, caption: String, commands: Array) -> void:
	var menu := MenuButton.new(); menu.text=caption; parent.add_child(menu)
	for command: Array in commands: menu.get_popup().add_item(command[0])
	menu.get_popup().about_to_popup.connect(_cancel_gestures)
	menu.get_popup().index_pressed.connect(func(index):commands[index][1].call())

func _copy_selection() -> void:
	if edit_target=="timeline": timeline.copy_selected()
	else: copy_objects()
func _paste_selection() -> void:
	if edit_target=="timeline": timeline.paste_selected()
	else: paste_objects()

func _discard_recovery(directory: String) -> void:
	var recovery:=LevelProjectIO.read_json(recovery_path)
	if recovery.get("directory") == directory:DirAccess.remove_absolute(recovery_path)

func _notification(what: int) -> void:
	# 原生素材/颜色弹窗仍属于本应用；只有切出应用才进入后台休眠。
	if not is_node_ready():return
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:_set_background(true)
	elif what==NOTIFICATION_APPLICATION_FOCUS_IN:_set_background(false)
