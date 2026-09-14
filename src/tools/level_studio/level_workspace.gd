extends Control
## 工作区只协调文档、选区和共用运行时，谱面在此保持只读。
var document := LevelDocument.new()
var song_document := StudioDocument.new()
var audio := StudioAudio.new()
var preview := StudioPreviewSession.new()
var timeline := LevelTimeline.new()
var surface := LevelPreviewSurface.new()
var inspector: LevelInspector = preload("res://scenes/tools/level_studio/inspector.tscn").instantiate()
var viewport := SubViewport.new()
var selection := PackedStringArray()
var _pending_packs: Array=[]
var _background_choice_key:=""
var _background_choices:={}
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
var _object_tree = preload("res://src/tools/level_studio/level_object_tree.gd").new()
var _object_search := LineEdit.new()
var _object_type := OptionButton.new()
var _show_dependencies := false
var _guide: PanelContainer
var _sequence_list := ItemList.new()
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
var _standalone_environment: ParallaxController
var _environment_preview := {}
var _environment_last_redraw := 0
var _environment_switching := false
var _review := {}
var _review_switching := false
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
	timeline.environment_dropped.connect(add_environment_cue)
	timeline.asset_dropped.connect(_drop_timeline_asset)
	timeline.note_requested.connect(_select_reference_note)
	timeline.bind(document)
	document.changed.connect(_document_changed)
	document.view_snapshot=_selection_snapshot
	document.history_gate=_history_pack_gate
	document.history_view_requested.connect(_restore_history_selection)
	document.rejected.connect(func(reason):_status.text=reason)
	document.edit_started.connect(_pause_review)
	get_viewport().gui_focus_changed.connect(func(control):
		if control is LineEdit or control is TextEdit or control is SpinBox or control is LevelCurveEditor:_pause_review())
	surface.selection_changed.connect(func(ids):
		if ids!=selection or _transform_keys().is_empty():select_objects(ids))
	surface.transform_committed.connect(_commit_transform)
	surface.candidate_changed.connect(func(values): _candidate_objects = values; _update_show())
	surface.asset_dropped.connect(_drop_canvas_asset)
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
	var resume_path:=""
	for index in range(arguments.size()-1):
		if arguments[index]=="--resume-level-session":resume_path=arguments[index+1];break
	if not resume_path.is_empty():_resume_pack_session.call_deferred(resume_path)
	elif not opening.is_empty():_open_path.call_deferred(opening)
	elif offer_recovery_on_start:_offer_recovery.call_deferred()

func _build_ui() -> void:
	var toolbar: HFlowContainer = %Toolbar
	_add_menu(toolbar,"文件",[["新建",_new],["打开",_open],["保存",save],["另存为",_save_as],["导入歌曲",import_song],["导出关卡包",export_package],["最近工程",_recent_projects],["查看恢复稿",_show_recoveries]])
	_add_menu(toolbar,"编辑",[["撤销",func():document.undo()],["重做",func():document.undo(true)],["复制",_copy_selection],["粘贴",_paste_selection],["删除",delete_selection],["粘贴到选中对象",func():timeline.paste_selected(selection[0] if selection.size()==1 else "@invalid")]])
	_add_menu(toolbar,"素材",[["导入素材",import_asset],["导入动画",import_animation],["导入素材包",import_pack],["应用待更新素材包",_apply_pending_packs],["重新定位缺失素材",_relocate_asset],["清理未使用素材",clean_unused_assets]])
	LevelUI.button(toolbar,"保存",save,"保存当前字段及工程（Ctrl+S）")
	_trial_button=LevelUI.button(toolbar,"在游戏中试玩",playtest)
	_add_menu(toolbar,"帮助",[["操作说明",_help],["显示起步引导",func():_guide.show()]])
	_scale_menu.text="界面";add_child(_scale_menu);_scale_menu.hide()
	for caption in ["自动缩放","100%","125%","150%","200%"]:_scale_menu.get_popup().add_radio_check_item(caption)
	_scale_menu.get_popup().add_separator()
	_scale_menu.get_popup().add_item("显示整个区段",10)
	_scale_menu.get_popup().id_pressed.connect(func(id):
		if id==10:_fit_timeline();return
		_ui_scale=[0.0,1.0,1.25,1.5,2.0][id];_apply_ui_scale();_save_preferences())
	var menu := MenuButton.new(); menu.text="视图"; toolbar.add_child(menu)
	for pair in [["界面倍率…",20],["布置布局",21],["动画布局",22],["BOSS 布局",23],["恢复默认布局",0],["显隐素材与对象",1],["显隐属性面板",2],["显隐时间线",8],["专注预览 / 恢复",9]]: menu.get_popup().add_item(pair[0],pair[1])
	menu.get_popup().id_pressed.connect(_view_action)
	menu.get_popup().about_to_popup.connect(_prepare_command)
	var tools_menu := MenuButton.new(); tools_menu.text="工程工具"; toolbar.add_child(tools_menu)
	for pair in [["导入旧场景演出",5],["重新定位缺失素材",6],["选择配套游戏",7],["试玩日志与重试",24]]: tools_menu.get_popup().add_item(pair[0],pair[1])
	tools_menu.get_popup().id_pressed.connect(_view_action)
	var ordered:=["文件","编辑","素材","视图","工程工具","帮助","保存","在游戏中试玩","更多"]
	for index in ordered.size():
		for child in toolbar.get_children():
			if child is BaseButton and child.text==ordered[index]:toolbar.move_child(child,index);break
	LevelUI.button(%InspectorTabs,"属性",func(): _show_inspector("properties"))
	LevelUI.button(%InspectorTabs,"关卡设置",func(): _show_inspector("level"))
	LevelUI.button(%InspectorTabs,"BOSS",open_boss_binding)
	var assets_panel := VBoxContainer.new(); assets_panel.name = "素材"; _left_panel.add_child(assets_panel)
	_asset_search.placeholder_text = "搜索素材名称或路径"; assets_panel.add_child(_asset_search); _asset_search.text_changed.connect(func(_value): _refresh_assets())
	for caption in ["全部","场景 / BOSS","图片","音频","字体","环境场景","动画"]: _asset_category.add_item(caption)
	_add_menu(assets_panel,"＋ 导入",[["普通素材",import_asset],["动画",import_animation],["素材包",import_pack]])
	LevelUI.toggle(assets_panel,"显示内部依赖",false,func(value):_show_dependencies=value;_refresh_assets())
	assets_panel.add_child(_asset_category); _asset_category.item_selected.connect(func(_index): _refresh_assets())
	_asset_list.get_v_scroll_bar().value_changed.connect(func(_value):_refresh_visible_thumbnails.call_deferred())
	_asset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL; _asset_list.fixed_icon_size = Vector2i(48,48); _asset_list.max_columns = 1
	assets_panel.add_child(_asset_list); _asset_list.item_activated.connect(func(index): add_asset_object(str(_asset_list.get_item_metadata(index))))
	var objects_panel := VBoxContainer.new(); objects_panel.name = "对象"; _left_panel.add_child(objects_panel)
	_object_search.placeholder_text="搜索对象名称";objects_panel.add_child(_object_search);_object_search.text_changed.connect(func(_value):_refresh_objects())
	for kind in ["全部","sprite","animated_sprite","text","actor","audio","camera","group"]:_object_type.add_item(str({"sprite":"图片","animated_sprite":"动画","text":"文字","actor":"BOSS / 场景","audio":"声音","camera":"镜头","group":"分组"}.get(kind,kind)));_object_type.set_item_metadata(_object_type.item_count-1,kind)
	objects_panel.add_child(_object_type);_object_type.item_selected.connect(func(_index):_refresh_objects())
	_object_tree.rearrange_requested.connect(_rearrange_objects)
	_object_tree.button_clicked.connect(func(item,_column,id,_mouse):
		var entry:=document.find("objects",str(item.get_metadata(0)));var next:=entry.duplicate(true)
		var field: String="hidden" if id==0 else "locked";next[field]=not bool(entry[field]);document.replace("切换对象"+field,"objects",[entry],[next]))
	var add := MenuButton.new(); add.text = "+ 添加对象"; objects_panel.add_child(add)
	for pair in [["精灵","sprite"],["BOSS / 场景","actor"],["环境","environment"],["HUD 文字","text"],["HUD 图片","image"],["音频","audio"],["镜头","camera"],["分组","group"]]:
		add.get_popup().add_item(pair[0]); add.get_popup().set_item_metadata(add.get_popup().item_count-1,pair[1])
	add.get_popup().index_pressed.connect(func(index): add_object(str(add.get_popup().get_item_metadata(index))))
	_object_tree.hide_root = true; _object_tree.select_mode = Tree.SELECT_MULTI; _object_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	objects_panel.add_child(_object_tree); _object_tree.multi_selected.connect(func(_item,_column,_selected): _tree_selection())
	var object_actions := HFlowContainer.new(); objects_panel.add_child(object_actions)
	for entry in [["复制",copy_objects],["粘贴",paste_objects],["对称",mirror_objects],["分组",group_objects],["解组",ungroup_objects],["删除",delete_objects]]: LevelUI.button(object_actions,entry[0],entry[1])
	var top: HFlowContainer = %PreviewToolbar
	%TimelineEdit.add_child(_difficulty); _difficulty.item_selected.connect(_switch_difficulty)
	add_child(_scene);_scene.hide()
	for stage in ChartSceneLibrary.shared().all_stages(): _scene.add_item(stage.display_name); _scene.set_item_metadata(_scene.item_count-1,stage.stage_id)
	_scene.item_selected.connect(func(index): document.fields("切换基础场景",{"scene_id":_scene.get_item_metadata(index)}))
	for pair in [["移动","move"],["旋转","rotate"],["缩放","scale"]]:
		var button:=LevelUI.button(top,pair[0],func():_set_transform_mode(pair[1]),"切换画面操纵工具："+pair[0]+"（"+str({"move":"W","rotate":"E","scale":"R"}[pair[1]])+"）")
		button.toggle_mode=true;_mode_buttons[pair[1]]=button
	_add_menu(top,"对齐",[["对齐画布中心",align_center],["左对齐",func():align_objects("left")],["右对齐",func():align_objects("right")],["顶对齐",func():align_objects("top")],["底对齐",func():align_objects("bottom")],["水平居中",func():align_objects("center_x")],["垂直居中",func():align_objects("center_y")],["水平等距",func():align_objects("distribute_x")],["垂直等距",func():align_objects("distribute_y")]])
	_set_transform_mode("move")
	LevelUI.button(top,"适应画面",func(): surface.zoom=1;surface.pan=Vector2.ZERO;surface.queue_redraw()).set_meta("narrow_hide",true)
	LevelUI.button(top,"定位选中",surface.frame_selection).set_meta("narrow_hide",true)
	_add_menu(top,"更多",[["适应画面",func():surface.zoom=1;surface.pan=Vector2.ZERO;surface.queue_redraw()],["定位选中",surface.frame_selection],["显示／隐藏网格",func():surface.show_grid=not surface.show_grid;surface.queue_redraw()],["显示／隐藏路径",func():surface.show_paths=not surface.show_paths;surface.queue_redraw()]])
	%PreviewHost.add_child(surface); %PreviewHost.move_child(surface,0); surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_inspector_scroll.add_child(inspector); inspector.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	boss_panel=LevelBossPanel.new(); boss_panel.workspace=self; %RightPanel.add_child(boss_panel); boss_panel.hide()
	var sequences := VBoxContainer.new(); sequences.name="片段"; _left_panel.add_child(sequences)
	LevelUI.button(sequences,"保存选区为演出片段",_save_sequence)
	_sequence_list.size_flags_vertical=Control.SIZE_EXPAND_FILL;sequences.add_child(_sequence_list)

	LevelUI.button(sequences,"插入演出片段",_insert_sequence)
	LevelUI.button(sequences,"重命名片段",_rename_sequence)
	LevelUI.button(sequences,"预览所选片段",_preview_sequence)
	LevelUI.button(sequences,"删除所选模板",_delete_sequence)
	_guide=preload("res://scenes/tools/level_studio/workflow_panel.tscn").instantiate();%Middle.add_child(_guide);%Middle.move_child(_guide,1)
	_guide.get_node("Body/Steps/Directory").pressed.connect(save);_guide.get_node("Body/Steps/Song").pressed.connect(import_song)
	_guide.get_node("Body/Steps/Theme").pressed.connect(func():_show_inspector("level"));_guide.get_node("Body/Steps/Assets").pressed.connect(import_asset)
	_guide.get_node("Body/Steps/Close").pressed.connect(_guide.hide)
	var edges:=HBoxContainer.new();%Middle.add_child(edges);%Middle.move_child(edges,0)
	LevelUI.button(edges,"◀ 素材／对象",func():_left_panel.visible=not _left_panel.visible)
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;edges.add_child(spacer)
	LevelUI.button(edges,"属性 ▶",func():%RightPanel.visible=not %RightPanel.visible)
	var bottom: VBoxContainer = %Bottom
	var transport: HFlowContainer = %Transport
	for caption in ["曲前","歌曲","曲后"]: _section.add_item(caption)
	_section.select(1); transport.add_child(_section); _section.item_selected.connect(func(index): set_section(LevelFormat.SECTIONS[index]))
	LevelUI.button(transport,"开头",func(): seek(0))
	_add_menu(transport,"整关审片",[["从曲前开始连续预览",start_full_review],["退出审片并恢复视图",end_full_review],["上一事件",func():timeline.navigate_event(-1)],["下一事件",func():timeline.navigate_event(1)]])
	_play.text="播放";_play.icon=preload("res://assets/chart_studio/play.svg"); transport.add_child(_play); _play.pressed.connect(toggle_play)
	_position.custom_minimum_size.x=95; transport.add_child(_position)
	LevelUI.choice(transport,"速率",[0.5,0.75,1.0,1.25,1.5,2.0],1.0,func(value): audio.set_rate(value))
	_loop_toggle=LevelUI.toggle(transport,"循环",false,func(value): audio.loop_enabled=value)
	_follow.text="跟随";_follow.button_pressed=true;_follow.tooltip_text="播放时跟随游标；手动浏览后暂停跟随，重新播放或勾选可恢复"
	transport.add_child(_follow);_follow.toggled.connect(func(_value):
		if _follow_suspended:_follow.set_pressed_no_signal(true)
		_follow_suspended=false;_follow.text="跟随")
	timeline.manual_browse.connect(func():_follow_suspended=true;_follow.text="跟随暂停")
	_add_menu(transport,"环境场景",[["编辑环境编排",open_environment_settings],["添加换景",func():choose_environment(func(asset):add_environment_cue(asset,time_us))],["退出衔接预览",end_environment_preview]])
	_add_menu(transport,"循环范围",[["设置循环起点",func():timeline.loop_start_us=time_us;audio.loop_start=float(time_us)/1000000;timeline.queue_redraw()],["设置循环终点",func():timeline.loop_end_us=time_us;audio.loop_end=float(time_us)/1000000;timeline.queue_redraw()]])
	LevelUI.choice(transport,"吸附",[120,240,480,60,0],120,func(value): timeline.snap_ticks=value,["1/16","1/8","1/4","1/32","关闭"])
	_add_menu(%TimelineEdit,"插入关键帧",[["位置",func():key_property("position")],["旋转",func():key_property("rotation")],["大小",func():key_property("scale")],["透明度",func():key_property("opacity")],["显示",func():key_property("visible")]])
	var split_button:=LevelUI.button(%TimelineEdit,"拆分",func():timeline.split_selected(),"在游标处拆分所选片段（S）");split_button.set_meta("requires_clip",true)
	_add_menu(%TimelineEdit,"添加片段",[["动作",func():add_clip("action")],["显示区间",func():add_clip("visibility")],["音频",func():add_clip("audio")]])
	LevelUI.toggle(%TimelineEdit,"自动关键帧",false,func(value):auto_key=value;surface.record_at_cursor=true;inspector.refresh())
	LevelUI.choice(%TimelineEdit,"新轨道范围",[false,true],false,func(value):difficulty_only=value;inspector.refresh(),["所有难度","当前难度"])
	_add_menu(%TimelineEdit,"轨道视图",[["全部／选中对象",func():timeline.only_selected=not timeline.only_selected;timeline.rebuild_rows()],["全部／当前难度",func():timeline.current_difficulty_only=not timeline.current_difficulty_only;timeline.rebuild_rows()],["显示／隐藏空轨",func():timeline.hide_empty=not timeline.hide_empty;timeline.rebuild_rows()],["适应选区",timeline.fit_selection],["上一事件",func():timeline.navigate_event(-1)],["下一事件",func():timeline.navigate_event(1)]])
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
	var available:=Vector2i(get_viewport().get_visible_rect().size)-Vector2i(40,96)
	dialog.popup_centered(minimum.min(available))
	# 自动换行和滚动区在首帧才获得宽度，再收敛一次尺寸，防止初始最小高度撑出窗口。
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(dialog):
		dialog.size=minimum.min(Vector2i(get_viewport().get_visible_rect().size)-Vector2i(40,96))
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
	if selection==ids and selected_track==track_id and selected_item==item_id and inspector_mode=="properties":return
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
	timeline.selected_objects=selection.duplicate()
	if timeline.only_selected:timeline.rebuild_rows()
	timeline.selected_object=selection[0] if not selection.is_empty() else ""; timeline.selected_track=selected_track
	surface.queue_redraw(); timeline.queue_redraw(); _sync_tree_selection();_update_command_controls()
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
	var included:=PackedStringArray()
	var query:=_object_search.text.to_lower();var filter: String=str(_object_type.get_selected_metadata())
	for object_data: Dictionary in document.entries("objects"):
		if not query.is_empty() and not query in str(object_data.name).to_lower():continue
		if filter!="全部" and filter!=object_data.type:continue
		var id: String=object_data.id
		while not id.is_empty() and id not in included:included.append(id);id=str(document.find("objects",id).get("parent_id",""))
	for object_data:Dictionary in document.entries("objects"):
		if object_data.id not in included:continue
		var item:=_object_tree.create_item(root);items[object_data.id]=item
		item.set_text(0,("🔒 " if object_data.locked else "")+("◌ " if object_data.hidden else "")+str(object_data.name));item.set_metadata(0,object_data.id);item.collapsed=bool(folded_objects.get(object_data.id,false)) and query.is_empty()
		item.add_button(0,_editor_icon("hidden" if object_data.hidden else "visible"),0,false,"显示／隐藏对象");item.add_button(0,_editor_icon("locked" if object_data.locked else "unlocked"),1,false,"锁定／解锁对象")
	# Tree 支持层级展示；文档的父子关系仍独立于 UI 的排序。
	for object_data:Dictionary in document.entries("objects"):
		if items.has(object_data.id) and items.has(object_data.parent_id):items[object_data.id].get_parent().remove_child(items[object_data.id]);items[object_data.parent_id].add_child(items[object_data.id])
	_tree_updating=false;_sync_tree_selection()

func _refresh_assets() -> void:
	_asset_list.clear();_asset_list.set_meta("loaded_metadata",{})
	var search:=_asset_search.text.to_lower();var category:=_asset_category.selected
	for asset_id:String in _assets.entries:
		var entry:VisualAssetEntry=_assets.entries[asset_id]
		var name:=entry.display_name if not entry.display_name.is_empty() else asset_id
		if not search.is_empty() and not search in (name+asset_id).to_lower():continue
		if entry.background != null: continue
		if category not in [0,1]:continue
		_asset_list.add_item(name,entry.thumbnail);_asset_list.set_item_metadata(_asset_list.item_count-1,asset_id)
	var background_ids := PackedStringArray()
	for entry in _assets.backgrounds():
		background_ids.append(entry.id)
		if category not in [0,5] or (not search.is_empty() and not search in str(entry.name).to_lower()):continue
		_asset_list.add_item("环境 · "+str(entry.name),entry.thumbnail);_asset_list.set_item_metadata(_asset_list.item_count-1,entry.id)
	_asset_list.set_meta("background_ids",background_ids)
	if document.directory.is_empty():return
	var internal:=PackedStringArray()
	if not _show_dependencies:
		for file in _assets.list_files():
			if file.ends_with(LevelAnimationAsset.SUFFIX):internal.append_array(LevelAnimationAsset.dependencies(document.directory.path_join(file)))
	var usage:={}
	for reference: Dictionary in LevelProjectIO.references(document.data):usage[reference.asset]=int(usage.get(reference.asset,0))+1
	for path in _assets.list_files():
		if document.directory.path_join(path) in internal:continue
		var kind:=_assets.kind(path)
		var category_id: int={"image":2,"audio":3,"font":4,"animation":6}.get(kind,-1)
		if category_id<0 or (category!=0 and category!=category_id):continue
		if not search.is_empty() and not search in (_asset_caption(path)+path).to_lower():continue
		var placeholder:=_editor_icon("asset")
		_asset_list.add_item(_asset_caption(path),placeholder);_asset_list.set_item_metadata(_asset_list.item_count-1,path)
		_asset_list.set_item_tooltip(_asset_list.item_count-1,"来源：工程文件\n类型："+str({"image":"图片","animation":"动画","audio":"声音","font":"字体"}.get(kind,kind))+"\n引用：%d 处\n%s"%[int(usage.get(path,0)),path])
	_refresh_visible_thumbnails.call_deferred()

func _refresh_visible_thumbnails() -> void:
	var scroll:=_asset_list.get_v_scroll_bar().value
	var loaded:=0
	for index in _asset_list.item_count:
		if _asset_list.get_item_icon(index)!=_editor_icon("asset"):continue
		var rect:=_asset_list.get_item_rect(index)
		if rect.end.y<scroll or rect.position.y>scroll+_asset_list.size.y:continue
		var asset:=str(_asset_list.get_item_metadata(index));var kind:=_assets.kind(asset)
		var metadata: Dictionary=_asset_list.get_meta("loaded_metadata",{})
		if metadata.has(asset):continue
		metadata[asset]=true
		if kind=="audio":
			var sound:=_assets.resolve(asset) as AudioStream
			if sound!=null:_asset_list.set_item_tooltip(index,_asset_list.get_item_tooltip(index)+"\n时长：%.3f s"%sound.get_length())
		if kind not in ["image","animation"]:continue
		var resource:=_assets.resolve(asset);var thumbnail: Texture2D
		if resource is Texture2D:
			thumbnail=resource;_asset_list.set_item_tooltip(index,_asset_list.get_item_tooltip(index)+"\n尺寸：%d × %d"%[resource.get_width(),resource.get_height()])
		elif resource is SpriteFrames:
			var action:=_assets.default_animation(asset)
			if not action.is_empty() and resource.get_frame_count(action)>0:
				thumbnail=resource.get_frame_texture(action,0);_asset_list.set_item_tooltip(index,_asset_list.get_item_tooltip(index)+"\n动作："+"、".join(resource.get_animation_names())+"\n默认动作：%.3f s"%LevelAnimationAsset.duration(resource,action))
		_asset_list.set_item_icon(index,thumbnail);loaded+=1
		if loaded>=4:
			if not get_tree().process_frame.is_connected(_refresh_visible_thumbnails):get_tree().process_frame.connect(_refresh_visible_thumbnails,CONNECT_ONE_SHOT)
			return

func _document_changed(kind:String) -> void:
	get_window().title="冥河 · 关卡编辑器 — "+str(document.data.title)+( " *" if document.dirty else "")
	if kind=="saved": return
	inspector.sync_fields.call_deferred()
	if kind=="project":
		_refresh_tree=true; _refresh_preview=true; _refresh_checks=true; _refresh_inspector=true; _boss_signature=""
	else:
		for change: Dictionary in document.last_changes:
			# 名称、颜色与变换不会改变资源有效性，避免每个字段扫描整份演出。
			if kind!="preview":
				if change.kind!="objects":_refresh_checks=true
				elif change.before.size()!=change.after.size():_refresh_checks=true
				else:
					for entry: Dictionary in change.after:
						var previous:=LevelFormat.find(change.before,entry.id)
						if previous.get("asset")!=entry.asset or previous.get("type")!=entry.type or previous.get("fields",{}).get("font")!=entry.fields.get("font"):_refresh_checks=true
			if change.kind=="objects":
				_refresh_preview=true
				if change.before.size()!=change.after.size(): _refresh_tree=true
				else:
					for index in change.after.size():
						for field: String in ["id","name","parent_id","locked","hidden"]:
							if change.before[index].get(field)!=change.after[index].get(field): _refresh_tree=true
			elif change.kind in ["tracks","bindings","scene_cues"]: _refresh_preview=true
			elif change.kind=="metadata":
				for key: String in change.after:
					if key in ["scene_id","rule_path","packs","show","song_path","initial_background","intro_us","outro_us"]: _refresh_preview=true
		for change: Dictionary in document.last_changes:
			if change.kind=="objects":
				for entry: Dictionary in change.after:
					var previous:=LevelFormat.find(change.before,entry.id)
					if previous.get("asset")!=entry.asset or previous.get("type")!=entry.type:_refresh_inspector=true
	if document.dirty and kind!="preview": _autosave.start()
	if _refresh_queued: return
	_refresh_queued=true; _refresh.call_deferred()

func _field_focused() -> bool:
	var focus:=get_viewport().gui_get_focus_owner()
	return document.editing or (focus!=null and %RightPanel.is_ancestor_of(focus) and (focus is LineEdit or focus is TextEdit or focus is SpinBox or focus is LevelCurveEditor))

func _refresh() -> void:
	_refresh_queued=false
	if not document.editing:
		selection=PackedStringArray(Array(selection).filter(func(id):return not document.find("objects",id).is_empty()))
		var valid_items := PackedStringArray()
		for track: Dictionary in document.entries("tracks"):
			for item: Dictionary in track.keys+track.clips:
				if item.id in selected_items:valid_items.append(item.id)
		if selected_track=="@environment":
			valid_items=PackedStringArray(document.entries("scene_cues").filter(func(cue):return cue.id in selected_items).map(func(cue):return cue.id))
		if valid_items!=selected_items:
			selected_items=valid_items;selected_item=selected_items[0] if selected_items.size()==1 else "";timeline.selected=selected_items.duplicate();_refresh_inspector=true
		surface.selected=selection.duplicate()
	if _refresh_tree: _refresh_objects()
	_refresh_sequences()
	if not document.entries("objects").is_empty() and not song_document.charts.is_empty():_guide.hide()
	if _refresh_preview: _update_show()
	if _refresh_checks: refresh_problems()
	if _refresh_inspector and not _field_focused() and inspector_mode!="boss": inspector.refresh()
	_refresh_tree=false; _refresh_preview=false; _refresh_checks=false; _refresh_inspector=false
	_update_command_controls()
	for index in _scene.item_count:
		if _scene.get_item_metadata(index)==document.data.scene_id: _scene.select(index)
	var signature:=str(document.data.scene_id)+"|"+str(document.data.rule_path)+"|"+difficulty()
	if not song_document.charts.is_empty() and signature!=_stage_signature: _refresh_song_preview()

func _effective_show() -> Dictionary:
	var show: Dictionary=document.data.show.duplicate()
	# 轨道采样只读；只复制容器与会补默认参数的对象，避免每次改颜色深拷贝所有关键帧。
	show.objects=document.entries("objects").duplicate(true);show.tracks=document.entries("tracks").duplicate()
	if not _candidate_objects.is_empty():
		var before:=[]
		for candidate: Dictionary in _candidate_objects:
			var original:=document.find("objects",candidate.id).duplicate(true)
			original.fields=LevelShowSampler.object_state(document.data.show,original,section,time_us,difficulty())
			before.append(original)
		var result:=LevelTransformEdit.build(document,before,_candidate_objects,section,time_us,difficulty(),auto_key,difficulty_only,_transform_keys())
		if result.error.is_empty():show=result.show
		else:_status.text=result.error
	for candidate: Dictionary in _candidate_tracks:
		for index in show.tracks.size():
			if show.tracks[index].id==candidate.id:show.tracks[index]=candidate
	return show

func _update_show() -> void:
	var player:=show_player()
	if player==null:
		_standalone=LevelShowPlayer.new();viewport.add_child(_standalone);player=_standalone
	var show:=_effective_show()
	var signature:=JSON.stringify(show.objects.map(func(value):return [value.id,value.type,value.asset]))+JSON.stringify(document.data.packs)+document.directory
	if signature!=_show_signature:
		player.update_show(show,document.directory,document.data.packs,difficulty());_show_signature=signature
	else:player.show=show;player.difficulty=difficulty();player.prepare_parameters()
	_assets=player.assets;surface.player=player
	if is_instance_valid(preview.stage_root):
		var bound:={}
		for binding: Dictionary in show.bindings:
			var id: String=binding.object_id
			while not id.is_empty() and not bound.has(id):bound[id]=true;id=str(LevelFormat.find(show.objects,id).get("parent_id",""))
		var relevant: Array=show.objects.filter(func(item):return bound.has(item.id) or item.type=="camera")
		var boss_key := JSON.stringify([show.bindings,relevant.map(func(item):return [item.id,item.asset,item.parent_id,item.layer,item.depth,item.fields]),show.tracks.filter(func(track):return bound.has(track.object_id) or relevant.any(func(item):return item.type=="camera" and item.id==track.object_id)),difficulty(),_stage_signature])
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
		if timeline.generated_tracks!=rows.values():timeline.generated_tracks=rows.values();timeline.rebuild_rows()
		if compiled.emissions!=preview.stage_root.chart_scheduler.boss_emissions:
			preview.stage_root.chart_scheduler.configure_boss_emissions(compiled.emissions)
			if _candidate_objects.is_empty() and _candidate_tracks.is_empty() and not _loading:preview.seek_preview(time_us)
	_update_environment(player)
	player.playing=audio.playing;player.playback_rate=audio.rate;player.refresh_visuals(section,time_us);surface.queue_redraw();_request_clip_waveforms()
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
	if selected_track=="@environment":LevelEnvironmentPanel.update_times(inspector,self)
	var player:=show_player()
	if player==null:return
	player.playing=audio.playing;player.playback_rate=audio.rate
	player.advance(section,time_us,not silent and audio.playing)
	surface.environment=timeline.environment
	surface.queue_redraw()
	if timeline.environment!=null and Time.get_ticks_msec()-_environment_last_redraw>100:
		_environment_last_redraw=Time.get_ticks_msec();timeline.queue_redraw()

func _refresh_song_preview() -> void:
	if song_document.charts.is_empty():return
	_loading=true;audio.set_playing(false)
	var loaded:=LevelProjectLoader.make_stage(document.data,document.directory,difficulty(),{},false)
	if not loaded.errors.is_empty():_loading=false;message(ChartProjectLoader.describe_issues(loaded.errors));return
	if is_instance_valid(_standalone):viewport.remove_child(_standalone);_standalone.queue_free();_standalone=null
	if is_instance_valid(_standalone_environment):
		viewport.remove_child(_standalone_environment);_standalone_environment.queue_free();_standalone_environment=null
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
	_update_command_controls()
	if _seek_pending:
		_seek_pending=false; _seek_elapsed=0; preview.seek_preview(time_us)
	if show_player()!=null: show_player().seek(section,time_us)
	if inspector_mode!="boss" and not _field_focused(): inspector.refresh()

func set_section(value:String) -> void:
	if not _review.is_empty():end_full_review()
	if not _environment_preview.is_empty(): end_environment_preview()
	_store_view(); _prepare_command(); audio.set_playing(false)
	section=value; timeline.section=value; timeline.rebuild_rows(); _section.select(LevelFormat.SECTIONS.find(value))
	_loading=true; audio.set_stream(song_document.song.audio_stream if value=="song" and song_document.song!=null else null); _loading=false
	_restore_view()

func toggle_play() -> void:
	if not _review.is_empty():_review.playing=not audio.playing
	if not _environment_preview.is_empty():_environment_preview.playing_intent=not audio.playing
	_follow_suspended=false;_follow.text="跟随"
	audio.set_playing(not audio.playing)

func _position_changed(seconds:float) -> void:
	_update_command_controls()
	if _review_position(seconds) or _environment_position(seconds):return
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
	_cancel_gestures(); LevelUI.finish_fields(%RightPanel); document.end_edit()

func _set_background(value: bool) -> void:
	_background=value
	if value:
		_pause_review()
		if not _environment_preview.is_empty():_environment_preview.playing_intent=false
		_cancel_gestures(); document.end_edit(true); audio.set_playing(false); _audition.stop()
	preview.set_suspended(value); Engine.max_fps=10 if value else 60
	if not preview.rebuilding: viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED if value else SubViewport.UPDATE_ALWAYS

func _preview_loading(active: bool) -> void:
	if active and _loading_started<0: _loading_started=Time.get_ticks_msec()
	elif not active: _loading_started=-1; %Loading.hide()

func add_object(kind:String) -> void:
	var id:=document.add_object(kind);select_objects(PackedStringArray([id]));_left_panel.current_tab=1

func add_asset_object(asset:String,at:=Vector2(960,540)) -> void:
	if asset in _asset_list.get_meta("background_ids", PackedStringArray()):
		add_environment_cue(asset,time_us);return
	var resource:=_assets.resolve(asset)
	if resource==null:
		message("无法读取素材，请重新导入或修复缺失引用：\n"+asset);return
	if resource is SpriteFrames and _assets.default_animation(asset).is_empty():
		message("此动画没有可显示的帧，请在动画导入窗口添加图片后重新导入。");return
	if resource is Font:
		if selection.is_empty() or not Array(selection).all(func(id):return document.find("objects",id).type=="text"):_status.text="先选择文字对象，再拖入字体。";return
		set_property("font",asset);return
	var kind:="actor" if resource is PackedScene else ("audio" if resource is AudioStream else ("animated_sprite" if resource is SpriteFrames else "sprite"))
	var object_data:=LevelFormat.object(kind,asset);object_data.fields.position=[at.x,at.y]
	if kind == "animated_sprite": object_data.animation = _assets.default_animation(asset)
	object_data.name=_asset_caption(asset)
	if object_data.name.is_empty():object_data.name=asset
	var changes: Array=[{"kind":"objects","before":[],"after":[object_data]}]
	if kind in ["animated_sprite","audio"]:
		var track:=LevelFormat.track(object_data.id,"action" if kind=="animated_sprite" else "audio",section,"action" if kind=="animated_sprite" else "audio");track.difficulties=[difficulty()] if difficulty_only and not difficulty().is_empty() else []
		var remaining:=_section_duration_us()-time_us
		var duration:=remaining if remaining>0 else roundi(maxf(2.0,(LevelAnimationAsset.duration(resource,object_data.animation) if resource is SpriteFrames else resource.get_length()))*1000000)
		var clip:=LevelFormat.clip(time_us,"",duration);clip.name=object_data.name;clip.action=object_data.animation;clip.loop=resource.get_animation_loop(clip.action) if resource is SpriteFrames else false
		if kind=="audio":clip.asset=asset;clip.duration_us=roundi(resource.get_length()*1000000)
		track.clips=[clip];changes.append({"kind":"tracks","before":[],"after":[track]})
	document.commit("从素材库添加对象与动画",changes);select_objects(PackedStringArray([object_data.id]))


func set_object_field(field:String,value:Variant) -> void:
	var before:=[];var after:=[]
	for id in selection:
		var object_data:=document.find("objects",id)
		if object_data.is_empty():continue
		before.append(object_data.duplicate(true));object_data=object_data.duplicate(true);object_data[field]=value;after.append(object_data)
	if before!=after:document.replace("修改对象"+field,"objects",before,after)

## 清除对象对外部素材的引用，但保留对象及其变换和演出轨道。
func clear_object_asset_reference() -> void:
	var before:=[];var after:=[]
	for id in selection:
		var current:=document.find("objects",id)
		if current.is_empty():continue
		var updated:=current.duplicate(true)
		updated.asset=""
		updated.animation=""
		before.append(current.duplicate(true));after.append(updated)
	if not before.is_empty():document.replace("清除素材引用", "objects", before, after)

func set_property(property:String,value:Variant) -> void:
	if property in LevelTransformEdit.PROPERTIES:
		var before:=[];var after:=[]
		for id in selection:
			var entry:=document.find("objects",id).duplicate(true)
			entry.fields=LevelShowSampler.object_state(document.data.show,entry,section,time_us,difficulty())
			before.append(entry);entry=entry.duplicate(true);entry.fields[property]=value;after.append(entry)
		_commit_transform(before,after);return
	if auto_key:
		var changes:=[]
		# 多选作为一次撤销：先在独立文档上组装受影响轨道，再一次提交。
		var candidate:=LevelDocument.new();candidate.reset(document.data)
		for id in selection:
			var error:=_record_key(candidate,id,property,value)
			if not error.is_empty():_status.text=error;return
		for track:Dictionary in candidate.entries("tracks"):
			var original:=document.find("tracks",track.id)
			if original!=track:changes.append({"kind":"tracks","before":[] if original.is_empty() else [original.duplicate(true)],"after":[track]})
		if not changes.is_empty():document.commit("自动记录"+str(LevelFormat.PROPERTIES.get(property,property)),changes)
		return
	var before:=[];var after:=[]
	for id in selection:
		var object_data:=document.find("objects",id)
		if object_data.is_empty():continue
		before.append(object_data.duplicate(true));object_data=object_data.duplicate(true);object_data.fields[property]=value;after.append(object_data)
	if before!=after:document.replace("修改基础"+str(LevelFormat.PROPERTIES.get(property,property)),"objects",before,after)

func key_property(property:String) -> void:
	var candidate:=LevelDocument.new();candidate.reset(document.data)
	for id in selection:
		var object_data:=document.find("objects",id)
		if object_data.is_empty():continue
		var state:=LevelShowSampler.object_state(document.data.show,object_data,section,time_us,difficulty())
		var fallback:Variant=object_data.fields.get(property)
		if _assets.entries.has(object_data.asset):fallback=_assets.entries[object_data.asset].exposed_parameters.get(property,{}).get("default",fallback)
		if fallback is Vector2:fallback=[fallback.x,fallback.y]
		if fallback is Color:fallback=fallback.to_html()
		var error:=_record_key(candidate,id,property,state.get(property,fallback))
		if not error.is_empty():_status.text=error;return
	var before:=[];var after:=[]
	for track:Dictionary in candidate.entries("tracks"):
		var original:=document.find("tracks",track.id)
		if original!=track:
			if not original.is_empty():before.append(original.duplicate(true))
			after.append(track)
	if not after.is_empty():document.replace("插入关键帧","tracks",before,after)

func _commit_transform(before:Array,after:Array) -> void:
	var result:=LevelTransformEdit.build(document,before,after,section,time_us,difficulty(),auto_key,difficulty_only,_transform_keys())
	if not result.error.is_empty():_status.text=result.error;return
	document.commit("记录当前帧" if auto_key else "整体调整对象与动画",result.changes)

func set_track_field(id:String,field:String,value:Variant) -> void:
	var before:=document.find("tracks",id);var after:=before.duplicate(true);after[field]=value
	if before!=after:document.replace("修改轨道","tracks",[before],[after])

func set_item_field(track_id:String,item_id:String,field:String,value:Variant) -> void:
	var before:=document.find("tracks",track_id)
	if before.is_empty():return
	var after:=before.duplicate(true)
	for item:Dictionary in after.keys+after.clips:
		if item.id==item_id:
			item[field]=value
			if field=="out_handle":item.out_handle[0]=clampf(float(item.out_handle[0]),0,float(item.in_handle[0]))
			elif field=="in_handle":item.in_handle[0]=clampf(float(item.in_handle[0]),float(item.out_handle[0]),1)
	after.keys.sort_custom(func(a,b):return int(a.time_us)<int(b.time_us))
	if before!=after:document.replace("修改关键帧或片段","tracks",[before],[after])

func set_key_curve(track_id:String,key_id:String,first:Vector2,second:Vector2) -> void:
	var before:=document.find("tracks",track_id)
	if before.is_empty():return
	var after:=before.duplicate(true)
	var key:=LevelFormat.find(after.keys,key_id)
	key.interpolation="bezier";key.out_handle=[first.x,first.y];key.in_handle=[second.x,second.y]
	document.replace("调整贝塞尔曲线","tracks",[before],[after])

func add_clip(kind:String) -> void:
	if selection.is_empty():message("先选择一个对象，再添加演出片段。");return
	var object_data:=document.find("objects",selection[0])
	var track:=LevelFormat.track(object_data.id,kind,section,kind);track.difficulties=[difficulty()] if difficulty_only and not difficulty().is_empty() else []
	var clip:=LevelFormat.clip(time_us,str(object_data.asset) if kind=="audio" else "",2000000)
	clip.name={"action":"动作","visibility":"显示区间","audio":"音频","sequence":"演出片段"}.get(kind,kind)
	if kind=="action":
		var actions:=_assets.actions(object_data.asset)
		if actions.is_empty():_status.text="所选素材没有可用动作，请先选择动画素材。";return
		var preferred:=str(object_data.get("animation",""))
		clip.action=preferred if preferred in actions else (_assets.default_animation(object_data.asset) if not _assets.default_animation(object_data.asset).is_empty() else actions[0])
	if kind=="audio":
		var stream:=_assets.resolve(str(clip.asset)) as AudioStream
		if stream!=null:clip.duration_us=roundi(stream.get_length()*1000000)
	track.clips=[clip];document.replace("添加"+str(clip.name),"tracks",[],[track])
	select_objects(selection,track.id,clip.id)

func copy_objects() -> void:document.copy_objects(selection)
func paste_objects() -> void:
	var ids:=document.paste_objects()
	if not document.last_error.is_empty():return
	select_objects(ids)
	if Array(selection).any(func(id):return document.find("objects",id).type=="actor"): _status.text="已复制演出；BOSS 副本尚未绑定音符"
func mirror_objects() -> void:document.copy_objects(selection);select_objects(document.paste_objects(true))
func delete_selection() -> void:
	if edit_target=="timeline":timeline.delete_selected();return
	delete_objects()

func delete_objects() -> void:
	document.delete_objects(selection)
	if not document.last_error.is_empty():return
	select_objects(PackedStringArray())

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
	_file_dialog("关卡另存为 · 选择新目录",FileDialog.FILE_MODE_OPEN_DIR,[],_save_as_progress)

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
	end_full_review()
	_discard_or(func():
		end_environment_preview()
		_autosave.stop();audio.set_playing(false);preview.clear_preview();song_document=StudioDocument.new();workspace_state={};_views.clear();document.reset(LevelFormat.new_level())
		_loading=true;audio.set_stream(null);_loading=false
		timeline.generated_tracks.clear();timeline.clip_waveforms.clear();_wave_versions.clear()
		_stage_signature="";_show_signature="";selection.clear();selected_track="";selected_item="";_difficulty.clear();section="song";timeline.section="song";_views.clear();_restore_view())

func _open() -> void:
	_discard_or(func():_file_dialog("打开关卡工程或关卡包",FileDialog.FILE_MODE_OPEN_FILE,["*.json ; 关卡文档","*.zip ; 关卡包"],_open_path))

func _open_path(path:String) -> void:
	end_full_review()
	_prepare_command(); _autosave.stop()
	if path.get_extension().to_lower()=="zip":
		_file_dialog("解压关卡包到制作目录",FileDialog.FILE_MODE_OPEN_DIR,[],func(folder):
			var error:=LevelProjectIO.unpack(path,folder)
			if not error.is_empty():message(error)
			else:_open_path(folder.path_join("level.json")))
		return
	# 关卡工程目录中常见的 show.json 是演出子文档；用户从文件管理器选择它时，
	# 自动回到同目录的 level.json，避免把子文档误判为不兼容的关卡。
	if path.get_file().to_lower() == "show.json":
		var level_path := path.get_base_dir().path_join("level.json")
		if FileAccess.file_exists(level_path): path = level_path
	var opened:=LevelProjectIO.open_project(path)
	if not opened.error.is_empty():message(opened.error);return
	end_environment_preview()
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

func _section_duration_us() -> int:
	if section!="song":return int(document.data.get(section+"_us",0))
	return roundi(timeline.waveform_duration*1000000)

func import_animation(replace_asset := "", source_path := "") -> void:
	_ensure_directory(func():
		var dialog=load("res://scenes/tools/level_studio/animation_import.tscn").instantiate();dialog.directory=document.directory
		add_child(dialog)
		dialog.imported.connect(func(path):
			if not replace_asset.is_empty():
				var before:=[];var after:=[]
				for object_data: Dictionary in document.entries("objects"):
					if object_data.asset!=replace_asset:continue
					before.append(object_data.duplicate(true));var next:=object_data.duplicate(true);next.asset=path;after.append(next)
				document.replace("重新导入动画并更新引用","objects",before,after)
			_asset_signature="";_show_signature="";_update_show();_status.text="已导入动画；拖入画布将创建动作片段。")
		_popup(dialog,Vector2i(1000,680))
		if not source_path.is_empty():dialog.load_resource(source_path))

func import_asset() -> void:
	_ensure_directory(func():_file_dialog("导入图片、声音或字体",FileDialog.FILE_MODE_OPEN_FILE,["*.png,*.jpg,*.jpeg,*.webp,*.svg ; 图片","*.wav,*.ogg,*.mp3 ; 音频","*.ttf,*.otf ; 字体"],_import_asset_path))

func _import_asset_path(path:String) -> void:
	# SpriteFrames 不能只复制 .tres/.res：从来源工程读取图片，再写入独立动画依赖。
	if path.get_extension().to_lower() in ["tres","res"]:
		import_animation("",path);return
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
			packs[existing]=entry;_pending_packs=packs;_apply_pending_packs()
		else:packs.append(entry);document.fields("导入素材包",{"packs":packs});_show_signature="";_update_show()))

func export_package() -> void:
	_prepare_command()
	_ensure_directory(func():
		refresh_problems()
		var issues:=LevelFormat.issues(document.data,song_document.charts);issues.append_array(_assets.validate_level(document.data))
		var errors:=issues.filter(func(issue):return issue.get("severity","error")=="error")
		var files:=LevelProjectIO.dependencies(document.data,document.directory);var bytes:=0
		for relative in files:bytes+=LevelProjectIO._file_size(document.directory.path_join(relative))
		var dialog:=ConfirmationDialog.new();dialog.title="导出检查";dialog.ok_button_text="选择输出位置"
		dialog.dialog_text="难度：%s\n依赖：%d 项，原始大小约 %.1f MB（压缩后大小以结果为准）\n%d 项错误 / %d 项提示\n%s"%["、".join(song_document.charts.map(func(chart):return chart.difficulty_id)),files.size(),float(bytes)/1048576,errors.size(),issues.size()-errors.size(),ChartProjectLoader.describe_issues(issues)]
		add_child(dialog);dialog.get_ok_button().disabled=not errors.is_empty()
		dialog.confirmed.connect(func():dialog.queue_free();_file_dialog("导出完整关卡包",FileDialog.FILE_MODE_SAVE_FILE,["*.zip ; 关卡包"],_export_with_progress))
		dialog.canceled.connect(dialog.queue_free);_popup(dialog,Vector2i(660,360)))

func _export_with_progress(path: String) -> void:
	var job=preload("res://scenes/tools/level_studio/package_progress.tscn").instantiate();add_child(job);_popup(job,Vector2i(540,180))
	var error: String=await job.run_export(document.data.duplicate(true),document.directory,path);job.queue_free()
	if not error.is_empty():_status.text=error;return
	_status.text="已导出关卡包："+path
	var done:=AcceptDialog.new();done.title="导出完成";done.dialog_text=path;add_child(done)
	done.add_button("打开输出目录",true,"folder");done.custom_action.connect(func(_id):OS.shell_open(ProjectSettings.globalize_path(path.get_base_dir())))
	done.confirmed.connect(done.queue_free);done.canceled.connect(done.queue_free);_popup(done,Vector2i(600,180))

func _save_as_progress(path: String) -> void:
	_prepare_command()
	if not document.directory.is_empty() and ProjectSettings.globalize_path(path).simplify_path()!=ProjectSettings.globalize_path(document.directory).simplify_path():
		var files:=LevelProjectIO.dependencies(document.data,document.directory)
		var protected: Array=[];_collect_asset_paths(document.history,protected);files.append_array(LevelProjectIO.expand_dependencies(PackedStringArray(protected),document.directory))
		var job=preload("res://scenes/tools/level_studio/package_progress.tscn").instantiate();add_child(job);_popup(job,Vector2i(540,180))
		var error: String=await job.run_copy(files,document.directory,path);job.queue_free()
		if not error.is_empty():_status.text=error;return
	if _save_to(path):_show_signature="";_read_song();_update_show()

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
	if _environment_preview.is_empty():_store_view()
	var visible_layout: Dictionary=_focus_layout if not _focus_layout.is_empty() else {"left":_left_panel.visible,"right":%RightPanel.visible,"bottom":%Bottom.visible}
	var state:=_environment_preview
	return {"left_width":_left_width,"right_width":_right_width,"timeline_height":_timeline_height,"time_us":state.get("time_us",time_us),"section":state.get("section",section),"zoom":state.get("zoom",timeline.pixels_per_second),"left_seconds":state.get("left",timeline.left_seconds),"difficulty":difficulty(),"views":state.get("views",_views).duplicate(true),"panels":visible_layout.duplicate(),"pending_packs":_pending_packs.duplicate(true)}

func _apply_workspace(state:Dictionary) -> void:
	_pending_packs=state.get("pending_packs",[]).duplicate(true)
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
	StudioProjectIO.write_json(_recovery_file(),{"level":document.data,"directory":document.directory,"workspace":workspace_state,"updated":Time.get_datetime_string_from_system()})

func _offer_recovery() -> void:
	if not DirAccess.get_files_at("user://level_studio/recoveries").is_empty():_show_recoveries();return
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
	if issue.has("pack_path"):import_pack();return
	var route: Array=issue.get("path",[])
	if route.size()>2 and route[0]=="show" and route[1]=="sequences":
		_left_panel.current_tab=2
		var id: String=document.entries("sequences")[int(route[2])].id
		for row in _sequence_list.item_count:
			if _sequence_list.get_item_metadata(row)==id:_sequence_list.select(row);_sequence_list.ensure_current_is_visible();break
		_offer_reference_repair(issue);return
	if issue.has("binding_id"):
		var binding:=document.find("bindings",str(issue.binding_id))
		if not binding.is_empty():
			for chart_index in song_document.charts.size():
				if song_document.charts[chart_index].difficulty_id==binding.difficulty and song_document.current!=chart_index: _difficulty.select(chart_index);_switch_difficulty(chart_index)
			select_objects(PackedStringArray([str(binding.object_id)]));open_boss_binding(str(binding.id))
			if issue.has("path"):_offer_reference_repair(issue)
			return
	if issue.has("track_id"):
		var track:=document.find("tracks",str(issue.track_id))
		if not track.is_empty():
			for chart_index in song_document.charts.size():
				if not track.difficulties.is_empty() and difficulty() not in track.difficulties and song_document.charts[chart_index].difficulty_id in track.difficulties:_switch_difficulty(chart_index);break
			if section!=track.section:set_section(track.section)
			timeline.folded.erase(track.object_id);timeline.rebuild_rows()
			select_objects(PackedStringArray([str(track.object_id)]),str(track.id),str(issue.get("item_id","")))
	elif issue.has("object_id"):select_objects(PackedStringArray([str(issue.object_id)]))
	if issue.has("scene_cue_id"):
		var cue:=document.find("scene_cues",str(issue.scene_cue_id))
		if not cue.is_empty():
			for chart_index in song_document.charts.size():
				if not LevelFormat.visible_in(cue,difficulty()) and LevelFormat.visible_in(cue,song_document.charts[chart_index].difficulty_id):_difficulty.select(chart_index);_switch_difficulty(chart_index);break
			if section!=cue.section:set_section(cue.section)
		_timeline_selection(PackedStringArray(),"@environment",PackedStringArray([str(issue.scene_cue_id)]) if not cue.is_empty() else PackedStringArray())
	if issue.has("time_us"):seek(int(issue.time_us));timeline.focus_time(time_us)
	if issue.has("path"):_offer_reference_repair(issue)

func _help() -> void:
	message("制作流程：导入 song.json → 导入素材包或图片 → 添加对象 → 编排关键帧和动作 → 绑定 BOSS 音符 → 试玩 → 导出关卡包。\n\n预览：W 移动 / E 旋转 / R 缩放；双指平移、Ctrl+滚动缩放、中键平移；Alt 暂时关闭画面吸附。\n时间线：双指两轴浏览，Ctrl+滚动缩放，中键平移；拖动关键帧/片段，拖片段边缘裁剪，S 拆分；Shift+拖动尺标设置循环区间。\nCtrl+S 保存，Ctrl+Z 撤销，Ctrl+C/V 复制粘贴，Delete 删除，Space 播放/暂停，Esc 取消拖动。\n自动关键帧关闭：无动画改基础值，已有位置／旋转／大小动画则整体调整当前区段；开启后记录游标处。HUD 使用正向屏幕坐标。\nGodot/Spine 负责素材内部结构，关卡工具调用已声明的动作与参数。素材包更新通过“重启并应用”恢复未保存文档和撤销历史。")

func _view_action(id:int) -> void:
	if id>=100:_discard_or(func():_open_path(str(_recent[id-100])));return
	match id:
		20:_scale_menu.get_popup().position=Vector2i(get_global_mouse_position());_scale_menu.get_popup().popup()
		21,22,23:_apply_layout_preset(id-21)
		24:_show_trial_log()
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
	for control in %PreviewToolbar.get_children():
		if control.get_meta("narrow_hide",false):control.visible=%Middle.size.x>=600
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
	document.replace("保存可复用演出片段","sequences",[],[data]);_status.text="已保存 "+str(data.name)+"，可从左侧片段库插入"

func _insert_sequence() -> void:
	var sequences:=document.entries("sequences")
	if sequences.is_empty():message("先选中对象并使用“保存选区为演出片段”。");return
	var dialog:=ConfirmationDialog.new();dialog.title="插入演出片段";dialog.ok_button_text="在当前时间插入"
	var choice:=OptionButton.new();dialog.add_child(choice)
	for data:Dictionary in sequences:choice.add_item(str(data.name))
	if not _sequence_list.get_selected_items().is_empty():choice.select(_sequence_list.get_selected_items()[0])
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
		if _trial_executable.is_empty() and OS.has_feature("editor"):_trial_executable=OS.get_executable_path()
		if _trial_executable.is_empty() or not FileAccess.file_exists(_trial_executable):_choose_game()
		else:_launch_trial())

func _launch_trial() -> void:
	var folder:="user://level_studio/trials/"+LevelFormat.id("trial")
	DirAccess.make_dir_recursive_absolute(folder)
	var path:=folder.path_join("level.zip")
	_trial_stage="preparing";_trial_button.disabled=true;_trial_button.text="准备试玩快照…"
	var job=preload("res://scenes/tools/level_studio/package_progress.tscn").instantiate();add_child(job);_popup(job,Vector2i(540,180))
	var error: String=await job.run_export(_pending_trial.level,_pending_trial.directory,path);job.queue_free()
	if not error.is_empty():_trial_button.disabled=false;_trial_button.text="在游戏中试玩";_pending_trial.clear();message(error);return
	_trial_folder=folder; _trial_request=LevelFormat.id("request"); _trial_stage=""; _trial_started=Time.get_ticks_msec(); _trial_timeout=false
	var args:=PackedStringArray(["--log-file",ProjectSettings.globalize_path(folder.path_join("game.log")),"--","--play-level",ProjectSettings.globalize_path(path),"--difficulty",_pending_trial.difficulty,"--trial-status",ProjectSettings.globalize_path(folder.path_join("status.json")),"--trial-request",_trial_request,"--trial-log",ProjectSettings.globalize_path(folder.path_join("game.log"))])
	# 工程内试玩直接启动同一引擎与当前源码，无需先导出配套游戏。
	if OS.has_feature("editor") and _trial_executable==OS.get_executable_path():
		var engine_args:=PackedStringArray(["--path",ProjectSettings.globalize_path("res://")])
		if DisplayServer.get_name()=="headless":engine_args.append("--headless")
		engine_args.append_array(args);args=engine_args
	_trial_pid=OS.create_process(_trial_executable,args,false)
	_pending_trial.clear()
	if _trial_pid<=0:_trial_button.disabled=false;_trial_button.text="在游戏中试玩";message("无法启动配套游戏。");return
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
	_views[_view_key()]={"time_us":time_us,"zoom":timeline.pixels_per_second,"left_seconds":timeline.left_seconds,"row_scroll":timeline.row_scroll,"folded":timeline.folded.duplicate(),"selection":Array(selection),"items":Array(selected_items),"track":selected_track,"target":edit_target,"loop":audio.loop_enabled,"start":timeline.loop_start_us,"end":timeline.loop_end_us,"pan":[surface.pan.x,surface.pan.y],"canvas_zoom":surface.zoom,"follow":_follow.button_pressed,"suspended":_follow_suspended,"filters":{"selected":timeline.only_selected,"difficulty":timeline.current_difficulty_only,"empty":timeline.hide_empty},"object_search":_object_search.text,"object_type":_object_type.selected}

func _restore_view() -> void:
	var view: Dictionary=_views.get(_view_key(),{})
	timeline.pixels_per_second=float(view.get("zoom",100)); timeline.left_seconds=float(view.get("left_seconds",0)); timeline.row_scroll=float(view.get("row_scroll",0)); timeline.folded=view.get("folded",{}).duplicate()
	selection=PackedStringArray(view.get("selection",[])); selected_items=PackedStringArray(view.get("items",[])); selected_track=str(view.get("track","")); selected_item=selected_items[0] if selected_items.size()==1 else ""; edit_target=str(view.get("target","objects"))
	timeline.loop_start_us=int(view.get("start",0)); timeline.loop_end_us=int(view.get("end",4000000)); audio.loop_start=float(timeline.loop_start_us)/1000000; audio.loop_end=float(timeline.loop_end_us)/1000000; audio.loop_enabled=bool(view.get("loop",false)); _loop_toggle.set_pressed_no_signal(audio.loop_enabled)
	surface.pan=LevelFormat.vec(view.get("pan",[0,0])); surface.zoom=float(view.get("canvas_zoom",1)); _follow.set_pressed_no_signal(bool(view.get("follow",true))); _follow_suspended=bool(view.get("suspended",false))
	var filters: Dictionary=view.get("filters",{})
	timeline.only_selected=filters.get("selected",false);timeline.current_difficulty_only=filters.get("difficulty",true);timeline.hide_empty=filters.get("empty",false)
	_object_search.text=view.get("object_search","");_object_type.select(int(view.get("object_type",0)))
	timeline.rebuild_rows(); _sync_selection(); seek(int(view.get("time_us",0)))

func _switch_difficulty(index: int) -> void:
	end_full_review()
	end_environment_preview()
	_store_view(); _prepare_command(); song_document.current=index; _stage_signature=""; _boss_signature=""; _refresh_song_preview(); _restore_view(); _show_inspector("properties")

func resource_field(parent: Node, caption: String, current: String, category: String, commit: Callable) -> void:
	var box := LevelUI.row(parent,caption)
	var value_id := [current]
	var button := Button.new(); box.add_child(button); button.text=_asset_caption(current);button.set_meta("resource_value",value_id);button.set_meta("asset_caption",_asset_caption)
	button.pressed.connect(func(): _choose_resource(category,value_id[0],func(value):commit.call(value);value_id[0]=value;button.text=_asset_caption(value);button.tooltip_text=value))
	# 路径用于排查素材，高频操作使用名称和选择器。
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; button.clip_text=true; button.tooltip_text=current


func _asset_caption(id: String) -> String:
	if id.is_empty(): return "选择素材…"
	if _assets.entries.has(id):return str(_assets.entries[id].display_name)
	if id.ends_with(LevelAnimationAsset.SUFFIX):return str(LevelProjectIO.read_json(document.directory.path_join(id)).get("name",id.get_file()))
	return id.get_file()

func _choose_resource(category: String, current: String, commit: Callable) -> void:
	_prepare_command()
	var dialog=preload("res://scenes/tools/level_studio/asset_picker.tscn").instantiate()
	dialog.library=_assets;dialog.packs=document.data.packs;dialog.caption=_asset_caption;dialog.category=category;dialog.current=current;dialog.commit=commit
	add_child(dialog);_popup(dialog,Vector2i(760,600))

func _add_menu(parent: Node, caption: String, commands: Array) -> void:
	var menu := MenuButton.new(); menu.text=caption; parent.add_child(menu)
	for command: Array in commands: menu.get_popup().add_item(command[0])
	menu.set_meta("command_group",caption)
	menu.get_popup().about_to_popup.connect(func():
		_prepare_command()
		for index in commands.size():
			var reason:=_command_reason(caption,index)
			menu.get_popup().set_item_disabled(index,not reason.is_empty());menu.get_popup().set_item_tooltip(index,reason))
	menu.get_popup().index_pressed.connect(func(index):commands[index][1].call())

func _copy_selection() -> void:
	if edit_target=="timeline": timeline.copy_selected()
	else: copy_objects()
func _paste_selection() -> void:
	if edit_target=="timeline": timeline.paste_selected()
	else: paste_objects()

func _discard_recovery(directory: String) -> void:
	for path in [recovery_path,_recovery_file()]:
		var recovery:=LevelProjectIO.read_json(path)
		if recovery.get("directory")==directory:DirAccess.remove_absolute(path)

func _notification(what: int) -> void:
	# 原生素材/颜色弹窗仍属于本应用；只有切出应用才进入后台休眠。
	if not is_node_ready():return
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:_set_background(true)
	elif what==NOTIFICATION_APPLICATION_FOCUS_IN:_set_background(false)

func _update_environment(player: LevelShowPlayer) -> void:
	var controller: ParallaxController
	var initial: StageBackgroundDefinition
	var velocity := Vector2.ZERO
	if is_instance_valid(preview.stage_root):
		controller=preview.stage_root.get_parallax_controller()
		var stage:StageDefinition=preview.stage_root.stage_session.stage_definition
		initial=stage.background
		if stage.visual_theme!=null:velocity=stage.visual_theme.camera_velocity
	else:
		if not is_instance_valid(_standalone_environment):
			_standalone_environment=ParallaxController.new();viewport.add_child(_standalone_environment)
		controller=_standalone_environment
		initial=_assets.background("stage:"+str(document.data.scene_id))
		controller.configure_boundary(song_document.chart() if not song_document.charts.is_empty() else null,
			song_document.offset_sec() if not song_document.charts.is_empty() else 0.0, PlanningParameters.read())
	var duration:=roundi(timeline.waveform_duration*1000000.0)
	if song_document.song!=null: duration=roundi(song_document.song.audio_stream.get_length()*1000000.0) if song_document.song.audio_stream!=null else roundi(song_document.song.fallback_duration_sec*1000000.0)
	if is_instance_valid(preview.stage_root):duration=roundi((preview.stage_root.stage_session.get_end_song_time_sec()+preview.stage_root.stage_session.stage_definition.song.first_beat_offset_sec)*1000000.0)
	player.configure_environment(controller,document.data,initial,Vector3i(int(document.data.get("intro_us",0)),duration,int(document.data.get("outro_us",0))),velocity)
	timeline.environment=controller.environment;surface.environment=controller.environment
	timeline.rebuild_rows()

func open_environment_settings() -> void:
	end_full_review()
	_timeline_selection(PackedStringArray(),"@environment",PackedStringArray())

func choose_environment(callback: Callable) -> void:
	var dialog:=ConfirmationDialog.new();dialog.title="选择环境场景";dialog.ok_button_text="使用此场景"
	var box:=VBoxContainer.new();dialog.add_child(box)
	var search:=LineEdit.new();search.placeholder_text="搜索环境场景";box.add_child(search)
	var list:=ItemList.new();list.custom_minimum_size=Vector2(480,280);box.add_child(list)
	var choices:=_assets.backgrounds()
	var refresh:=func(query:String):
		list.clear()
		for item in choices:
			if query.is_empty() or query.to_lower() in str(item.name).to_lower():
				list.add_item(str(item.name),item.thumbnail);list.set_item_metadata(list.item_count-1,item.id)
	search.text_changed.connect(refresh);refresh.call("")
	var accept:=func():
		if list.get_selected_items().is_empty():return
		var asset:=str(list.get_item_metadata(list.get_selected_items()[0]));dialog.hide();callback.call(asset);dialog.queue_free()
	dialog.confirmed.connect(accept);list.item_activated.connect(func(_index):accept.call())
	dialog.canceled.connect(dialog.queue_free);_popup(dialog,Vector2i(560,400));search.grab_focus()

func environment_name(asset:String) -> String:
	for entry in _assets.backgrounds():
		if entry.id==asset:return entry.name
	return asset

func add_environment_cue(asset:String,at_us:int) -> void:
	_prepare_command()
	var cue:=LevelFormat.scene_cue(at_us,asset,section);cue.name=environment_name(asset)
	cue.difficulties=[difficulty()] if difficulty_only and not difficulty().is_empty() else []
	document.replace("添加环境换景","scene_cues",[],[cue])
	_timeline_selection(PackedStringArray(),"@environment",PackedStringArray([cue.id]))

func set_environment_field(key:String,value:Variant) -> void:
	var before:=document.entries("scene_cues").filter(func(cue):return cue.id in selected_items)
	var after:=before.duplicate(true)
	for cue in after:cue[key]=value
	if not after.is_empty():document.replace("修改环境换景","scene_cues",before,after)

func preview_environment_cue() -> void:
	if timeline.environment==null or selected_items.is_empty():return
	var parts:=timeline.environment.transitions.filter(func(part):return part.cue_id in selected_items)
	if parts.is_empty():message("这些层与前一场景相同，无需换景。");return
	var start:int=parts.map(func(part):return int(part.enter_us)).min()
	var end:int=parts.map(func(part):return int(part.finish_us)).max()
	start=maxi(-timeline.environment.intro_us,start-1000000);end=mini(timeline.environment.end_us,end+1000000)
	if end<=start:message("该衔接在关卡结束前尚未入画。");return
	if _environment_preview.is_empty():
		_store_view()
		_environment_preview={"section":section,"time_us":time_us,"playing":audio.playing,"loop":audio.loop_enabled,"start":audio.loop_start,"end":audio.loop_end,"left":timeline.left_seconds,"zoom":timeline.pixels_per_second,"scroll":timeline.row_scroll,"pan":surface.pan,"canvas_zoom":surface.zoom,"follow":_follow.button_pressed,"suspended":_follow_suspended,"seams":surface.show_environment_seams,"views":_views.duplicate(true)}
	_environment_preview.range_start=start;_environment_preview.range_end=end;_environment_preview.playing_intent=true
	audio.loop_enabled=false;surface.show_environment_seams=true
	_environment_go_to(start,true)

func _environment_go_to(absolute_us:int,playing:bool) -> void:
	var sequence:=timeline.environment
	if sequence==null:return
	_environment_switching=true;audio.set_playing(false)
	section="intro" if absolute_us<0 else ("outro" if absolute_us>=sequence.song_us else "song")
	var local_us:=absolute_us-sequence.absolute_time(section,0)
	timeline.section=section;_section.select(LevelFormat.SECTIONS.find(section));timeline.rebuild_rows()
	_loading=true;audio.set_stream(song_document.song.audio_stream if section=="song" and song_document.song!=null else null);_loading=false
	seek(local_us);_environment_switching=false;audio.set_playing(playing)

func _environment_position(seconds:float) -> bool:
	if _environment_preview.is_empty() or _environment_switching or not _environment_preview.get("playing_intent",false) or timeline.environment==null:return false
	var at:=timeline.environment.absolute_time(section,roundi(seconds*1000000))
	if at>=int(_environment_preview.range_end):_environment_go_to(_environment_preview.range_start,true);return true
	if (section=="intro" and at>=0) or (section=="song" and at>=timeline.environment.song_us):_environment_go_to(at,true);return true
	if section=="song" and song_document.song!=null and song_document.song.audio_stream!=null and seconds>=song_document.song.audio_stream.get_length() and not audio.playing:
		# 歌曲的判定尾段可能长于音频；继续用静音时钟走到片尾，不能卡在文件末端。
		_environment_switching=true;_loading=true;audio.set_stream(null);_loading=false
		audio.seek(seconds);audio.set_playing(true);_environment_switching=false
	return false

func step_environment(direction:int) -> void:
	if not _environment_preview.is_empty():_environment_preview.playing_intent=false
	audio.set_playing(false)
	if not _environment_preview.is_empty() and timeline.environment!=null:
		_environment_go_to(timeline.environment.absolute_time(section,time_us)+direction*16667,false)
	else:seek(time_us+direction*16667)

func end_environment_preview() -> void:
	if _environment_preview.is_empty():return
	var state:=_environment_preview;_environment_preview={}
	if timeline.environment!=null:_environment_go_to(timeline.environment.absolute_time(state.section,state.time_us),false)
	_views=state.views
	audio.set_playing(false);audio.loop_enabled=state.loop;audio.loop_start=state.start;audio.loop_end=state.end
	timeline.left_seconds=state.left;timeline.pixels_per_second=state.zoom;timeline.row_scroll=state.scroll
	surface.pan=state.pan;surface.zoom=state.canvas_zoom;surface.show_environment_seams=state.seams
	_follow_suspended=state.suspended
	_follow.set_pressed_no_signal(state.follow)
	var controller:ParallaxController=show_player().environment_controller if show_player()!=null else null
	if is_instance_valid(controller):controller.environment_only_layer=""
	seek(state.time_us);audio.set_playing(state.playing)

## 多选对齐按实际显示外框计算，结果交给同一变换命令处理动画及父组坐标。
func align_objects(operation: String) -> void:
	if not _selection_editable():return
	var player:=show_player()
	if player==null:return
	var rows:=[]
	for id in selection:
		var entry:=document.find("objects",id)
		if entry.is_empty() or not document.editable_object(id) or surface._has_selected_parent(entry):continue
		var box: Rect2=player.objects[id].transform*surface.object_bounds(entry)
		rows.append({"entry":entry,"box":box})
	if rows.size()<2:_status.text="请至少选择两个可编辑对象。";return
	var bounds: Rect2=rows[0].box
	for row: Dictionary in rows:bounds=bounds.merge(row.box)
	var axis:=0 if operation.ends_with("x") else 1
	if operation.begins_with("distribute"):
		if rows.size()<3:_status.text="等距分布需要至少三个对象。";return
		rows.sort_custom(func(a,b):return a.box.position[axis]<b.box.position[axis])
	var total:=0.0
	for row: Dictionary in rows:total+=row.box.size[axis]
	var gap: float=(bounds.size[axis]-total)/float(rows.size()-1)
	var cursor: float=bounds.position[axis]
	var before:=[];var after:=[]
	for row: Dictionary in rows:
		var delta:=Vector2.ZERO;var box: Rect2=row.box
		match operation:
			"left":delta.x=bounds.position.x-box.position.x
			"right":delta.x=bounds.end.x-box.end.x
			"top":delta.y=bounds.position.y-box.position.y
			"bottom":delta.y=bounds.end.y-box.end.y
			"center_x":delta.x=bounds.get_center().x-box.get_center().x
			"center_y":delta.y=bounds.get_center().y-box.get_center().y
			_:delta[axis]=cursor-box.position[axis];cursor+=box.size[axis]+gap
		var entry: Dictionary=row.entry.duplicate(true)
		entry.fields=LevelShowSampler.object_state(document.data.show,entry,section,time_us,difficulty());before.append(entry)
		var next:=entry.duplicate(true)
		var parent_pose:=Transform2D.IDENTITY
		if not str(entry.parent_id).is_empty():parent_pose=LevelShowSampler.object_transform(document.data.show,entry.parent_id,section,time_us,difficulty())
		elif entry.layer=="death":parent_pose=Transform2D(PI,Vector2(1920,1080))
		if player._root_layer(entry)!="hud":delta/=player.camera_zoom
		var local_delta:=parent_pose.basis_xform_inv(delta)
		var position:=LevelFormat.vec(entry.fields.position)+local_delta;next.fields.position=[position.x,position.y];after.append(next)
	_commit_transform(before,after)

func transform_caption() -> String:
	if not _transform_keys().is_empty():return "所选关键帧 · 只调整所选时间点"
	var animated:=false;var scopes:=PackedStringArray()
	for track: Dictionary in document.entries("tracks"):
		if track.object_id not in selection or track.section!=section or track.property not in LevelTransformEdit.PROPERTIES or not LevelFormat.visible_in(track,difficulty()):continue
		animated=animated or not track.keys.is_empty()
		var scope: String="所有难度" if track.difficulties.is_empty() else "、".join(track.difficulties)
		if scope not in scopes:scopes.append(scope)
	if scopes.is_empty():scopes.append("当前难度" if difficulty_only else "所有难度")
	return ("记录当前帧" if auto_key else ("整体调整动画" if animated else "基础值"))+" · "+str({"intro":"曲前","song":"歌曲","outro":"曲后"}[section])+"\n作用范围："+" / ".join(scopes)

func set_base_property(property: String,value: Variant) -> void:
	var before:=[];var after:=[]
	for id in selection:
		var entry:=document.find("objects",id);before.append(entry.duplicate(true));entry=entry.duplicate(true);entry.fields[property]=value;after.append(entry)
	document.replace("修改全局基础值","objects",before,after)

func object_asset_category(entry: Dictionary) -> String:
	return {"sprite":"visual","image":"visual","animated_sprite":"animation","actor":"scene","environment":"scene","audio":"audio"}.get(str(entry.type),"all")

func select_asset_users(asset: String) -> void:
	var ids:=PackedStringArray()
	for entry: Dictionary in document.entries("objects"):
		if entry.asset==asset or entry.fields.get("font","")==asset:ids.append(entry.id)
	for track: Dictionary in document.entries("tracks"):
		if track.clips.any(func(clip):return clip.get("asset","")==asset) and track.object_id not in ids:ids.append(track.object_id)
	for binding: Dictionary in document.entries("bindings"):
		for field in ["sound","effect","hit_effect","miss_effect"]:
			if binding.get(field,"")==asset and binding.object_id not in ids:ids.append(binding.object_id)
	select_objects(ids);_left_panel.current_tab=1;_status.text="已定位 %d 个使用对象"%ids.size()

func set_object_asset(asset: String) -> void:
	var before:=[];var after:=[];var resource:=_assets.resolve(asset)
	for id in selection:
		var entry:=document.find("objects",id);before.append(entry.duplicate(true));entry=entry.duplicate(true);entry.asset=asset
		if entry.type in ["sprite","image","animated_sprite"] and resource is SpriteFrames:entry.type="animated_sprite";entry.animation=_assets.default_animation(asset)
		after.append(entry)
	document.replace("替换素材并保留编排","objects",before,after)

func background_layer_choices() -> Dictionary:
	var key:=JSON.stringify([document.data.get("initial_background",""),document.data.scene_id,document.entries("scene_cues").map(func(cue):return cue.asset),document.data.packs,document.directory])
	if key==_background_choice_key:return _background_choices.duplicate()
	_background_choice_key=key
	var initial:=str(document.data.get("initial_background",""))
	var choices:={};var references: Array=[initial if not initial.is_empty() else "stage:"+str(document.data.scene_id)]
	for cue: Dictionary in document.data.show.get("scene_cues",[]):references.append(cue.asset)
	for reference in references:
		var background:=_assets.background(str(reference))
		if background==null:continue
		for layer: StageBackgroundLayer in background.layers:
			choices[layer.depth]="深度 %d"%layer.depth if layer.display_name.is_empty() else layer.display_name+" · 深度 %d"%layer.depth
	_background_choices=choices;return choices.duplicate()

func set_occlusion_mode(value: String) -> void:
	var before:=[];var after:=[]
	for id in selection:
		var entry:=document.find("objects",id);before.append(entry.duplicate(true));entry=entry.duplicate(true)
		entry.occlusion_inherit=value=="inherit";entry.occlusion_order="none" if value=="inherit" else value;after.append(entry)
	document.replace("修改背景遮挡关系","objects",before,after)

func clean_unused_assets() -> void:
	_prepare_command()
	if document.directory.is_empty():return
	var used:=LevelProjectIO.dependencies(document.data,document.directory)
	# 文档历史和当前恢复稿都可能重新引用素材，回收前一起检查。
	var protected: Array=[];_collect_asset_paths(document.history,protected)
	var drafts:=PackedStringArray([_recovery_file(),recovery_path])
	for file in DirAccess.get_files_at("user://level_studio/recoveries"):
		if file.ends_with(".json"):drafts.append("user://level_studio/recoveries/"+file)
	for path in drafts:
		var recovery:=LevelProjectIO.read_json(path)
		if recovery.get("directory","")==document.directory:_collect_asset_paths(recovery,protected)
	used.append_array(LevelProjectIO.expand_dependencies(PackedStringArray(protected),document.directory))
	var unused:=PackedStringArray()
	for path in _assets.list_files():
		if path not in used:unused.append(path)
	if unused.is_empty():_status.text="没有可清理的未使用素材；撤销中引用的资源会保留。";return
	var dialog:=ConfirmationDialog.new();dialog.title="清理未使用素材";dialog.ok_button_text="移入工程回收目录"
	dialog.dialog_text="以下 %d 项不被当前文档或撤销记录引用：\n%s"%[unused.size(),"\n".join(unused)]
	add_child(dialog);dialog.confirmed.connect(func():
		var recycle:=".unused/"+LevelFormat.id("cleanup");var failed:=PackedStringArray();var moved:=PackedStringArray()
		for relative in unused:
			var files:=PackedStringArray([relative])
			if relative.ends_with(LevelAnimationAsset.SUFFIX):
				for dependency in LevelAnimationAsset.dependencies(document.directory.path_join(relative)):files.append(dependency.trim_prefix(document.directory.replace("\\","/").simplify_path().trim_suffix("/")+"/"))
			for file in files:
				if file in used or file in moved:continue
				var target:=document.directory.path_join(recycle).path_join(file);DirAccess.make_dir_recursive_absolute(target.get_base_dir())
				if DirAccess.rename_absolute(document.directory.path_join(file),target)!=OK:failed.append(file)
				else:moved.append(file)
		_assets.cache.clear();_refresh_assets();_status.text="已移入 "+recycle+"，可从该目录取回。" if failed.is_empty() else "部分素材未能移动："+"、".join(failed);dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);_popup(dialog,Vector2i(760,460))

func _command_reason(group: String, index: int) -> String:
	if group in ["插入关键帧","添加片段","对齐"] and selection.is_empty():return "请先选择可编辑对象"
	if group in ["插入关键帧","添加片段","对齐"] and Array(selection).any(func(id):return not document.editable_object(id)):return "对象或父组已锁定／隐藏"
	if group=="对齐" and index>0 and selection.size()<(3 if index>=7 else 2):return "至少选择三个对象" if index>=7 else "至少选择两个对象"
	if group=="添加片段" and index==0:
		for id in selection:
			if not _assets.actions(document.find("objects",id).get("asset","")).is_empty():return ""
		return "所选素材没有可用动作"
	return ""

func _update_command_controls() -> void:
	if not is_node_ready():return
	_difficulty.visible=_difficulty.item_count>0
	var has_clip:=false
	for track: Dictionary in document.entries("tracks"):
		for clip: Dictionary in track.clips:
			if clip.id in selected_items and time_us>clip.start_us and time_us<clip.start_us+clip.duration_us:has_clip=true
	for control in %TimelineEdit.get_children():
		if control.get_meta("requires_clip",false):control.disabled=not has_clip;control.tooltip_text="在游标处拆分所选片段（S）" if has_clip else "请选中片段，并把游标放在片段内部"

func _transform_keys() -> PackedStringArray:
	var result:=PackedStringArray()
	for track: Dictionary in document.entries("tracks"):
		for key: Dictionary in track.keys:
			if key.id in selected_items:result.append(key.id)
	return result

func _collect_asset_paths(value: Variant, result: Array) -> void:
	if value is String and value.begins_with("assets/"):
		if value not in result:result.append(value)
	elif value is Dictionary:
		for child in value.values():_collect_asset_paths(child,result)
	elif value is Array:
		for child in value:_collect_asset_paths(child,result)

func _record_key(candidate: LevelDocument, id: String, property: String, value: Variant) -> String:
	if not document.editable_object(id):return "对象或父组已锁定／隐藏"
	var matches:=candidate.entries("tracks").filter(func(track):return track.type=="property" and track.object_id==id and track.property==property and track.section==section and LevelFormat.visible_in(track,difficulty()))
	if matches.is_empty():candidate.set_key(id,property,section,time_us,value,difficulty() if difficulty_only else "");return ""
	var before: Dictionary=matches.back()
	if before.get("locked",false) or before.get("generated",false):return "当前属性轨道已锁定或只读"
	var after:=before.duplicate(true);var found:=false
	for key: Dictionary in after.keys:
		if key.time_us==time_us:key.value=value;found=true;break
	if not found:after.keys.append(LevelFormat.key(time_us,value))
	candidate.replace("记录当前帧","tracks",[before],[after]);return ""

## 分量变更从每个对象的当前值出发，未编辑分量不从首个对象回写。
func set_property_component(property: String, axis: int, value: float, base := false) -> void:
	var before:=[];var after:=[]
	for id in selection:
		var entry:=document.find("objects",id).duplicate(true)
		if entry.is_empty():continue
		if not base:entry.fields=LevelShowSampler.object_state(document.data.show,entry,section,time_us,difficulty())
		before.append(entry);entry=entry.duplicate(true);entry.fields[property][axis]=value;after.append(entry)
	if not base and property in LevelTransformEdit.PROPERTIES:_commit_transform(before,after);return
	var candidate:=LevelDocument.new();candidate.reset(document.data)
	for entry: Dictionary in after:
		if auto_key and not base:
			var error:=_record_key(candidate,entry.id,property,entry.fields[property])
			if not error.is_empty():_status.text=error;return
		else:candidate.find("objects",entry.id).fields[property]=entry.fields[property]
	var changes:=[]
	for kind in ["objects","tracks"]:
		var old:=[];var next:=[]
		for entry: Dictionary in candidate.entries(kind):
			var original:=document.find(kind,entry.id)
			if original==entry:continue
			if not original.is_empty():old.append(original.duplicate(true))
			next.append(entry)
		if not next.is_empty():changes.append({"kind":kind,"before":old,"after":next})
	document.commit("修改"+str(LevelFormat.PROPERTIES.get(property,property))+[" X"," Y"][axis],changes)

func set_item_component(track_id: String, item_id: String, field: String, axis: int, value: float) -> void:
	var track:=document.find("tracks",track_id)
	var item:=LevelFormat.find(track.get("keys",[])+track.get("clips",[]),item_id)
	if item.is_empty():return
	var next: Array=item[field].duplicate();next[axis]=value
	set_item_field(track_id,item_id,field,next)

func _offer_reference_repair(issue: Dictionary) -> void:
	if not str(issue.asset).begins_with("assets/"):
		var category: String={"actor":"scene","environment":"scene","sprite":"visual","image":"visual","animated_sprite":"animation"}.get(str(issue.get("kind","")),str(issue.get("kind","all")))
		_choose_resource(category,str(issue.asset),func(value):_replace_reference_value(issue,value));return
	var dialog:=ConfirmationDialog.new();dialog.title="修复指定引用";dialog.ok_button_text="选择替代文件"
	dialog.dialog_text=str(issue.message)+"\n只替换此处引用；旧素材与撤销保留。"
	add_child(dialog);dialog.confirmed.connect(func():
		dialog.queue_free()
		var asset: String=issue.asset
		var extension:=str(issue.get("dependency",asset)).get_extension()
		_file_dialog("选择替代资源",FileDialog.FILE_MODE_OPEN_FILE,["*."+extension+" ; 对应类型资源"],func(path):_repair_reference(issue,path)))
	dialog.canceled.connect(dialog.queue_free);_popup(dialog,Vector2i(600,210))

func _repair_reference(issue: Dictionary, path: String) -> void:
	var imported:=LevelProjectIO.import_file(path,document.directory)
	if not imported.error.is_empty():message(imported.error);return
	var replacement: String=imported.path
	if issue.has("dependency"):
		var source: String=issue.asset
		var descriptor:=LevelProjectIO.read_json(document.directory.path_join(source))
		for animation: Dictionary in descriptor.get("animations",[]):
			for frame: Dictionary in animation.frames:
				var original: String=document.directory.path_join(source).get_base_dir().path_join(frame.image).simplify_path()
				var absolute: String=document.directory.path_join(imported.path) if original==str(issue.dependency).simplify_path() else original
				frame.image=absolute.replace("\\","/").trim_prefix(document.directory.replace("\\","/").path_join("assets")+"/")
		replacement="assets/"+LevelFormat.id("repair")+LevelAnimationAsset.SUFFIX
		var error:=LevelProjectIO.write_json(document.directory.path_join(replacement),descriptor)
		if not error.is_empty():message(error);return
	_replace_reference_value(issue,replacement)

func _replace_reference_value(issue: Dictionary,replacement: String) -> void:
	var next:=document.data.duplicate(true);var cursor: Variant=next;var route: Array=issue.path
	for index in route.size()-1:cursor=cursor[route[index]]
	cursor[route.back()]=replacement
	var changes:=[]
	if route[0]=="show":
		var kind: String=route[1];var old: Dictionary=document.data.show[kind][route[2]];var after: Dictionary=next.show[kind][route[2]]
		changes.append({"kind":kind,"before":[old],"after":[after]})
	else:changes.append({"kind":"metadata","before":{route[0]:document.data[route[0]]},"after":{route[0]:next[route[0]]}})
	document.commit("修复素材引用",changes)
	_asset_signature="";_show_signature="";_update_show()

## 审片只持有工作区状态，演出和玩法仍使用正式采样入口。
func start_full_review() -> void:
	_prepare_command();end_environment_preview()
	if _review.is_empty():_review={"workspace":_workspace_snapshot(),"playing":true}
	_review.playing=true;audio.loop_enabled=false;_loop_toggle.set_pressed_no_signal(false)
	_review_go("intro" if int(document.data.intro_us)>0 else "song",0,true)

func end_full_review() -> void:
	if _review.is_empty():return
	var saved: Dictionary=_review.workspace;_review={};audio.set_playing(false)
	_apply_workspace(saved);audio.set_playing(false);_status.text="已退出整关审片，恢复原视图；修改保留。"

func _pause_review() -> void:
	if _review.is_empty() or _review_switching:return
	_review.playing=false;audio.set_playing(false)

func _input(event: InputEvent) -> void:
	if _review.is_empty() or _modal_open():return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		if surface.get_global_rect().has_point(event.position) or (timeline.get_global_rect().has_point(event.position) and event.position.y>=timeline.global_position.y+LevelTimeline.RULER):_pause_review()

func _review_go(next_section: String, us: int, playing: bool) -> void:
	_review_switching=true;audio.set_playing(false);section=next_section;timeline.section=section;_section.select(LevelFormat.SECTIONS.find(section));timeline.rebuild_rows()
	_loading=true;audio.set_stream(song_document.song.audio_stream if section=="song" and song_document.song!=null else null);_loading=false
	seek(us);_review_switching=false;audio.set_playing(playing)

func _review_position(seconds: float) -> bool:
	if _review.is_empty() or _review_switching or not _review.get("playing",false):return false
	var limit:=_review_duration(section)
	if seconds*1000000>=limit:
		if section=="intro":_review_go("song",maxi(0,roundi(seconds*1000000)-limit),true)
		elif section=="song" and int(document.data.outro_us)>0:_review_go("outro",maxi(0,roundi(seconds*1000000)-limit),true)
		else:_review.playing=false;audio.set_playing(false);seek(limit);_status.text="整关审片结束；可定位检查或退出恢复原视图。"
		return true
	if section=="song" and not audio.playing:
		_review_switching=true;audio.set_stream(null);audio.seek(seconds);audio.set_playing(true);_review_switching=false
	return false

func _review_duration(value: String) -> int:
	if value!="song":return int(document.data.get(value+"_us",0))
	if is_instance_valid(preview.stage_root):return roundi((preview.stage_root.stage_session.get_end_song_time_sec()+preview.stage_root.stage_session.stage_definition.song.first_beat_offset_sec)*1000000)
	return maxi(1,roundi(timeline.waveform_duration*1000000))

func _apply_layout_preset(index: int) -> void:
	_left_panel.show();%RightPanel.show();%Bottom.show();_focus_layout.clear()
	_left_width=[220,180,200][index];_right_width=[285,310,360][index];_timeline_height=[210,360,300][index];_queue_layout()
	if index==2 and not selection.is_empty() and document.find("objects",selection[0]).type=="actor":open_boss_binding()
	_status.text=["布置布局","动画布局","BOSS 布局"][index]+"；可继续拖动分隔线调整。"

func _recent_projects() -> void:
	var dialog:=ConfirmationDialog.new();dialog.title="最近工程";dialog.ok_button_text="打开"
	var list:=ItemList.new();list.custom_minimum_size=Vector2(600,260);dialog.add_child(list)
	for path in _recent:list.add_item(str(path))
	add_child(dialog);dialog.confirmed.connect(func():
		if list.get_selected_items().is_empty():return
		var path: String=_recent[list.get_selected_items()[0]];dialog.queue_free();_discard_or(func():_open_path(path)))
	dialog.canceled.connect(dialog.queue_free);_popup(dialog,Vector2i(680,360))

func _drop_timeline_asset(asset: String, at_us: int) -> void:
	_prepare_command();seek(at_us)
	var kind:=_assets.kind(asset)
	if kind=="font":add_asset_object(asset);return
	document.begin_edit();add_asset_object(asset)
	if kind=="image" and not selection.is_empty():add_clip("visibility")
	document.end_edit()
	_status.text="已在当前区段 %.3f 秒插入 %s；一次撤销恢复。"%[float(at_us)/1000000,_asset_caption(asset)]

func _select_reference_note(id: String) -> void:
	if inspector_mode!="boss":
		open_boss_binding()
		if inspector_mode!="boss":return
	var note:=song_document.find_note(id)
	if note==null or not note.boss:_status.text="此音符未标记为 BOSS 音符。";return
	var ids: Array=boss_panel.data.get("note_ids",[]).duplicate()
	if id in ids:ids.erase(id)
	else:ids.append(id)
	boss_panel._change("note_ids",ids);boss_panel._populate_notes()

func _refresh_sequences() -> void:
	var sequences:=document.entries("sequences")
	var signature:=JSON.stringify(sequences.map(func(item):return [item.id,item.name,item.objects.size(),item.tracks]))
	if signature==_sequence_list.get_meta("signature",""):return
	var selected_id: String=str(_sequence_list.get_item_metadata(_sequence_list.get_selected_items()[0])) if not _sequence_list.get_selected_items().is_empty() else ""
	_sequence_list.set_meta("signature",signature);_sequence_list.clear()
	for item: Dictionary in sequences:
		var end:=0;var sections:=[]
		for track: Dictionary in item.tracks:
			if track.section not in sections:sections.append(track.section)
			for event: Dictionary in track.keys+track.clips:end=maxi(end,int(event.get("time_us",event.get("start_us",0)))+int(event.get("duration_us",0)))
		_sequence_list.add_item("%s · %d 对象 · %.2f 秒\n%s"%[item.name,item.objects.size(),float(end)/1000000," / ".join(sections)])
		var index:=_sequence_list.item_count-1;_sequence_list.set_item_metadata(index,item.id)
		if item.id==selected_id:_sequence_list.select(index)

func _selected_sequence() -> Dictionary:
	if _sequence_list.get_selected_items().is_empty():_status.text="先从片段库选择一个模板。";return {}
	return document.find("sequences",str(_sequence_list.get_item_metadata(_sequence_list.get_selected_items()[0])))

func _rename_sequence() -> void:
	var entry:=_selected_sequence()
	if entry.is_empty():return
	var dialog:=ConfirmationDialog.new();dialog.title="命名演出片段";var edit:=LineEdit.new();edit.text=entry.name;dialog.add_child(edit);add_child(dialog)
	dialog.confirmed.connect(func():var after:=entry.duplicate(true);after.name=edit.text;document.replace("重命名演出片段","sequences",[entry],[after]);dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);_popup(dialog,Vector2i(480,160));edit.grab_focus()

func _delete_sequence() -> void:
	var entry:=_selected_sequence()
	if not entry.is_empty():document.replace("删除演出模板","sequences",[entry],[])

func _preview_sequence() -> void:
	var entry:=_selected_sequence()
	if entry.is_empty():return
	var dialog:=ConfirmationDialog.new();dialog.title="片段预览 · "+str(entry.name);var box:=VBoxContainer.new();dialog.add_child(box)
	var view:=SubViewport.new();view.size=Vector2i(960,540);view.size_2d_override=Vector2i(1920,1080);view.size_2d_override_stretch=true;view.transparent_bg=true;dialog.add_child(view)
	var player:=LevelShowPlayer.new();view.add_child(player)
	var image:=TextureRect.new();image.texture=view.get_texture();image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;image.custom_minimum_size=Vector2(640,360);box.add_child(image)
	var slider:=HSlider.new();slider.step=0.001;slider.max_value=10;box.add_child(slider);add_child(dialog)
	var show:=entry.duplicate(true)
	for object_data: Dictionary in show.objects:
		if LevelFormat.find(show.objects,str(object_data.parent_id)).is_empty():object_data.parent_id=""
	var duration:=0
	for track: Dictionary in show.tracks:
		track.section="song";track.difficulties=[]
		for event: Dictionary in track.keys+track.clips:duration=maxi(duration,int(event.get("time_us",event.get("start_us",0)))+int(event.get("duration_us",0)))
	slider.max_value=maxf(1,float(duration)/1000000);player.configure(show,document.directory,document.data.packs,difficulty())
	slider.value_changed.connect(func(value):player.seek("song",roundi(value*1000000)))
	var playing:=[false];var timer:=Timer.new();timer.wait_time=1.0/60;dialog.add_child(timer)
	LevelUI.button(box,"播放／暂停",func():playing[0]=not playing[0])
	timer.timeout.connect(func():
		if playing[0]:slider.value=fposmod(slider.value+timer.wait_time,slider.max_value))
	timer.start();player.seek("song",0)
	dialog.confirmed.connect(dialog.queue_free);dialog.canceled.connect(dialog.queue_free);_popup(dialog,Vector2i(760,510))

func _rearrange_objects(ids: PackedStringArray, target_id: String, placement: int) -> void:
	_prepare_command();_pause_review()
	var target:=document.find("objects",target_id)
	var parent_id: String=target_id if placement==0 and target.get("type","")=="group" else str(target.get("parent_id",""))
	var roots:=PackedStringArray()
	for id in ids:
		var entry:=document.find("objects",id);var ancestor: String=entry.get("parent_id","");var nested:=false
		while not ancestor.is_empty():
			if ancestor in ids:nested=true;break
			ancestor=str(document.find("objects",ancestor).get("parent_id",""))
		if not nested:roots.append(id)
	for id in roots:
		var parent:=parent_id
		while not parent.is_empty():
			if parent==id:_status.text="不能把对象放进自己或自己的子组。";return
			parent=str(document.find("objects",parent).get("parent_id",""))
		if not document.editable_object(id):_status.text="选区包含锁定／隐藏对象，未移动。";return
	if not parent_id.is_empty() and not document.editable_object(parent_id):_status.text="目标父组已锁定／隐藏。";return
	var changes:=[];var old_objects:=document.entries("objects").duplicate(true);var next_objects:=old_objects.duplicate(true)
	var old_tracks:=[];var next_tracks:=[]
	var bake_dialog: ConfirmationDialog
	var bake_steps:=0
	var scopes:=PackedStringArray()
	for chart in song_document.charts:scopes.append(chart.difficulty_id)
	if scopes.is_empty():scopes.append(difficulty())
	for id in roots:
		var original:=document.find("objects",id);var entry:=LevelFormat.find(next_objects,id)
		if entry.parent_id==parent_id:continue
		var relevant_ids:={}
		for start_id: String in [id,parent_id]:
			var ancestor:=start_id
			while not ancestor.is_empty() and not relevant_ids.has(ancestor):relevant_ids[ancestor]=true;ancestor=str(document.find("objects",ancestor).get("parent_id",""))
		entry.parent_id=parent_id
		var relation:=LevelShowPlayer.effective_occlusion(document.data.show,original)
		entry.occlusion_inherit=false;entry.occlusion_order="none" if relation.is_empty() else relation[1]
		if not relation.is_empty():entry.occlusion_depth=relation[0]
		for track in document.entries("tracks"):
			if track.object_id==id and track.property in ["position","rotation","scale","skew"]:old_tracks.append(track.duplicate(true))
		for stage: String in LevelFormat.SECTIONS:
			var times:={0:true};var end:=0
			for track: Dictionary in document.entries("tracks"):
				if track.section!=stage or not relevant_ids.has(track.object_id) or track.property not in ["position","rotation","scale","skew"]:continue
				for key: Dictionary in track.keys:times[int(key.time_us)]=true;end=maxi(end,int(key.time_us))
			for at in range(0,end,16667):times[at]=true
			var ordered:=times.keys();ordered.sort()
			for scope: String in scopes:
				var tracks:={}
				for property in ["position","rotation","scale","skew"]:
					var track:=LevelFormat.track(id,property,stage);track.difficulties=[] if scopes.size()==1 else [scope];tracks[property]=track
				for at: int in ordered:
					bake_steps+=1
					if ordered.size()>240 and bake_steps%128==0:
						if bake_dialog==null:
							bake_dialog=preload("res://scenes/tools/level_studio/package_progress.tscn").instantiate();bake_dialog.title="保持动画并调整父组";add_child(bake_dialog);_popup(bake_dialog,Vector2i(540,180))
						bake_dialog.get_node("%Status").text="正在计算 %s · %s · %.2f s；可取消"%[entry.name,stage,float(at)/1000000]
						bake_dialog.get_node("%Progress").value=100.0*float(at)/maxi(1,end)
						await get_tree().process_frame
						if bake_dialog._is_cancelled():bake_dialog.queue_free();_status.text="已取消层级调整，文档保持原样。";return
					var pose:=LevelShowSampler.object_transform(document.data.show,id,stage,at,scope)
					var parent_pose:=LevelShowSampler.object_transform(document.data.show,parent_id,stage,at,scope) if not parent_id.is_empty() else (Transform2D(PI,Vector2(1920,1080)) if entry.layer=="death" else Transform2D.IDENTITY)
					if is_zero_approx(parent_pose.determinant()):
						if bake_dialog!=null:bake_dialog.queue_free()
						_status.text="目标父组在动画中缩放为零，无法保留显示变换。";return
					pose=parent_pose.affine_inverse()*pose
					var values:={"position":[pose.origin.x,pose.origin.y],"rotation":rad_to_deg(pose.get_rotation()),"scale":[pose.get_scale().x,pose.get_scale().y],"skew":rad_to_deg(pose.get_skew())}
					for property in tracks:tracks[property].keys.append(LevelFormat.key(at,values[property]))
				next_tracks.append_array(tracks.values())
	var moved: Array=next_objects.filter(func(entry):return entry.id in roots)
	next_objects=next_objects.filter(func(entry):return entry.id not in roots)
	var index:=next_objects.find(LevelFormat.find(next_objects,target_id));index=next_objects.size() if index<0 else index+(1 if placement>=0 else 0)
	for entry in moved:next_objects.insert(index,entry);index+=1
	changes.append({"kind":"objects","before":old_objects,"after":next_objects,"before_order":old_objects.map(func(entry):return entry.id),"after_order":next_objects.map(func(entry):return entry.id)})
	if not next_tracks.is_empty():changes.append({"kind":"tracks","before":old_tracks,"after":next_tracks})
	if bake_dialog!=null:bake_dialog.queue_free()
	document.commit("调整对象层级并保持变换",changes)
	if document.last_error.is_empty():select_objects(roots)

func _recovery_file() -> String:
	if recovery_path!="user://level_studio/recovery.json":return recovery_path
	return "user://level_studio/recoveries/"+str(document.data.level_id)+"_"+str(document.directory.simplify_path().hash())+".json"

func _show_recoveries() -> void:
	_prepare_command();_autosave.stop()
	var choices:=[]
	for file in DirAccess.get_files_at("user://level_studio/recoveries"):
		if file.ends_with(".json"):choices.append("user://level_studio/recoveries/"+file)
	if FileAccess.file_exists(recovery_path):choices.append(recovery_path)
	var dialog:=ConfirmationDialog.new();dialog.title="恢复工程草稿";dialog.ok_button_text="恢复为未保存工程"
	var list:=ItemList.new();list.custom_minimum_size=Vector2(640,300);dialog.add_child(list)
	for path: String in choices:
		var draft:=LevelProjectIO.read_json(path)
		if not draft.has("level"):continue
		list.add_item("%s · %s · %d 对象 / %d 轨道\n%s"%[draft.level.get("title","未命名"),draft.get("updated",""),draft.level.show.objects.size(),draft.level.show.tracks.size(),draft.get("directory","")]);list.set_item_metadata(list.item_count-1,path)
	add_child(dialog);dialog.confirmed.connect(func():
		if list.get_selected_items().is_empty():return
		var draft:=LevelProjectIO.read_json(str(list.get_item_metadata(list.get_selected_items()[0])));dialog.queue_free()
		if document.dirty:_preserve_before_restore()
		end_full_review();end_environment_preview();audio.set_playing(false);preview.clear_preview();song_document=StudioDocument.new()
		workspace_state=draft.get("workspace",{});document.reset(draft.level,draft.get("directory",""));document.saved_cursor=-1;document.dirty=true
		_read_song();_apply_workspace(workspace_state);_document_changed("project"))
	dialog.canceled.connect(func():
		dialog.queue_free()
		if document.dirty:_autosave.start())
	_popup(dialog,Vector2i(720,400))

## 历史只附带对应选区，撤销不强迫用户退回旧的布局。
func _selection_snapshot() -> Dictionary:
	return {"objects":Array(selection),"track":selected_track,"items":Array(selected_items),"target":edit_target,"section":section,"difficulty":difficulty(),"inspector_mode":inspector_mode,"binding_id":boss_panel.binding_id}

func _restore_history_selection(state: Dictionary) -> void:
	if state.is_empty():return
	_pause_review()
	var context_changed: bool=section!=state.section or difficulty()!=state.difficulty
	_store_view()
	for index in song_document.charts.size():
		if song_document.charts[index].difficulty_id==state.difficulty:song_document.current=index;_difficulty.select(index);break
	if section!=state.section:
		section=state.section;timeline.section=section;_section.select(LevelFormat.SECTIONS.find(section))
		_loading=true;audio.set_stream(song_document.song.audio_stream if section=="song" and song_document.song!=null else null);_loading=false
	selection=PackedStringArray(state.objects);selected_track=state.track;selected_items=PackedStringArray(state.items);selected_item=selected_items[0] if selected_items.size()==1 else "";edit_target=state.target
	if context_changed:_refresh_song_preview()
	timeline.rebuild_rows();_sync_selection()
	var mode: String=state.get("inspector_mode","properties")
	if mode=="boss" and not selection.is_empty():boss_panel.open(selection[0],state.get("binding_id",""))
	if mode!=inspector_mode:_show_inspector(mode)

func _selection_editable() -> bool:
	for id in selection:
		if not document.editable_object(id):
			_status.text="选区包含不可编辑对象："+str(document.find("objects",id).get("name",id))+"；整次操作未提交。";return false
	return true

func _show_trial_log() -> void:
	if _trial_folder.is_empty():_status.text="尚未启动试玩。";return
	var dialog:=ConfirmationDialog.new();dialog.title="试玩日志";dialog.ok_button_text="重新启动"
	var log:=TextEdit.new();log.editable=false;log.custom_minimum_size=Vector2(740,420);log.text=FileAccess.get_file_as_string(_trial_folder.path_join("game.log")) if FileAccess.file_exists(_trial_folder.path_join("game.log")) else "日志尚未生成。";dialog.add_child(log);add_child(dialog)
	dialog.confirmed.connect(func():
		if _trial_pid>0 and OS.is_process_running(_trial_pid):OS.kill(_trial_pid)
		_trial_pid=-1;_trial_button.disabled=false;dialog.queue_free();playtest())
	dialog.canceled.connect(dialog.queue_free);_popup(dialog,Vector2i(800,520))

## Godot 已挂载的资源包不能卸载；用一次重启恢复会话切换版本。
func _apply_pending_packs() -> void:
	if _pending_packs.is_empty():_status.text="没有待应用的素材包版本。";return
	_prepare_command()
	var candidate:=_history_document()
	candidate.fields("更新素材包",{"packs":_pending_packs.duplicate(true)})
	_offer_pack_restart(candidate,"应用新素材包")

func _history_document() -> LevelDocument:
	var candidate:=LevelDocument.new();candidate.reset(document.data.duplicate(true),document.directory)
	candidate.history.assign(document.history.duplicate(true));candidate.cursor=document.cursor;candidate.saved_cursor=document.saved_cursor;candidate.dirty=document.dirty
	return candidate

func _history_pack_gate(command: Dictionary, redo: bool) -> bool:
	for change: Dictionary in command.changes:
		if change.kind=="metadata" and change.after.has("packs") and change.before.get("packs",[])!=change.after.packs:
			var candidate:=_history_document();candidate.undo(redo)
			_offer_pack_restart(candidate,"重做素材包版本" if redo else "撤销素材包版本")
			return false
	return true

func _offer_pack_restart(candidate: LevelDocument, caption: String) -> void:
	var dialog:=ConfirmationDialog.new();dialog.title=caption;dialog.ok_button_text="重启并应用";dialog.cancel_button_text="稍后"
	var names:=PackedStringArray()
	for entry: Dictionary in document.entries("objects"):
		if _assets.entries.has(entry.asset):names.append(str(entry.name))
	dialog.dialog_text="新版本已准备。切换已挂载的素材包需要重启编辑器。\n未保存文档、撤销历史和布局将恢复，正式工程不会被覆盖。\n使用素材包的对象：\n"+("无" if names.is_empty() else "、".join(names))
	add_child(dialog);dialog.confirmed.connect(func():
		var state:=_workspace_snapshot();state.pending_packs=[]
		var snapshot:={"level":candidate.data,"directory":candidate.directory,"history":candidate.history,"cursor":candidate.cursor,"saved_cursor":candidate.saved_cursor,"workspace":state,"selection":_selection_snapshot(),"clipboard":document.clipboard,"timeline_clipboard":timeline._clipboard}
		var path:="user://level_studio/restarts/"+LevelFormat.id("session")+".json"
		var error:=LevelProjectIO.write_json(path,snapshot)
		if not error.is_empty():message(error);return
		var args:=PackedStringArray()
		if OS.has_feature("editor"):args.append_array(["--path",ProjectSettings.globalize_path("res://")])
		args.append_array(["--","--level-editor","--resume-level-session",ProjectSettings.globalize_path(path)])
		var pid:=OS.create_process(OS.get_executable_path(),args,false)
		if pid<=0:message("无法重新启动；会话保留在："+path);return
		_autosave.stop();get_tree().quit())
	dialog.canceled.connect(func():dialog.queue_free();_status.text="版本切换尚未应用；可从素材菜单继续。")
	_popup(dialog,Vector2i(620,260))

func _resume_pack_session(path: String) -> void:
	var session:=LevelProjectIO.read_json(path)
	if session.is_empty():message("无法恢复重启会话："+path);return
	workspace_state=session.workspace;document.reset(session.level,session.directory)
	document.history.assign(session.history);document.cursor=int(session.cursor);document.saved_cursor=int(session.saved_cursor);document.dirty=document.cursor!=document.saved_cursor
	document.clipboard=session.get("clipboard",{});timeline._clipboard=session.get("timeline_clipboard",[])
	_read_song();_apply_workspace(workspace_state);_restore_history_selection(session.get("selection",{}));_document_changed("project")
	_status.text="素材包版本已切换；未保存修改和撤销历史已恢复。"

func _drop_canvas_asset(asset: String, at: Vector2) -> void:
	if _assets.kind(asset)=="font":
		for id in surface.objects_at(at):
			if document.find("objects",id).type=="text":select_objects(PackedStringArray([id]));set_property("font",asset);return
		_status.text="请将字体拖到可编辑的文字对象上。";return
	add_asset_object(asset,at)

func _editor_icon(name: String) -> Texture2D:
	if not has_meta("editor_icons"):set_meta("editor_icons",{})
	var icons: Dictionary=get_meta("editor_icons")
	if not icons.has(name):
		icons[name]=load("res://assets/level_studio/"+name+".svg")
	return icons[name]

func _preserve_before_restore() -> void:
	var path:="user://level_studio/recoveries/"+str(document.data.level_id)+"_before_restore_"+LevelFormat.id("draft")+".json"
	LevelProjectIO.write_json(path,{"level":document.data,"directory":document.directory,"workspace":_workspace_snapshot(),"updated":Time.get_datetime_string_from_system(),"note":"恢复前保留的未保存文档"})
