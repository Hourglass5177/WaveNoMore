extends ConfirmationDialog
signal imported(path: String)
var directory := ""
var frames := SpriteFrames.new()
var action := "default"
var label := "新动画"
var source_sheet: Texture2D
var columns:=1
var rows:=1
var cell_width:=0
var cell_height:=0
var margin:=0
var spacing:=0
var first_frame:=1
var last_frame:=0
var _resource_replacements:={}
var _name_field: LineEdit
var _duration: SpinBox
var _busy:=false
var _cancel:=false
var _playing:=false
var _seconds:=0.0
var _action_choice: OptionButton
var _fps: SpinBox
var _loop: CheckBox
var _names: Array[String]=[]

func _ready() -> void:
	dialog_hide_on_ok=false
	for pair in [["连续图片",_choose_images],["图片文件夹",_choose_folder],["整张精灵表",_choose_sheet],["Godot SpriteFrames",_choose_resource]]:LevelUI.button(%Sources,pair[0],pair[1])
	LevelUI.button(%Playback,"播放／暂停",func():_playing=not _playing)
	LevelUI.button(%Playback,"上一帧",func():_step(-1));LevelUI.button(%Playback,"下一帧",func():_step(1))
	LevelUI.toggle(%Playback,"原始尺寸",false,func(value):%Preview.original_size=value;%Preview.queue_redraw())
	LevelUI.toggle(%Playback,"切割辅助线",false,func(value):_show_sheet(value))
	LevelUI.button(%FrameActions,"上移",func():_reorder(-1));LevelUI.button(%FrameActions,"下移",func():_reorder(1))
	LevelUI.button(%FrameActions,"移除所选帧",_remove_frame)
	_duration=LevelUI.number(%FrameActions,"帧时长倍率",1,func(value):
		var selected: PackedInt32Array=%Frames.get_selected_items()
		if not _busy and not selected.is_empty():frames.set_frame(action,selected[0],frames.get_frame_texture(action,selected[0]),value);_refresh_time(),0.1,0.01,100)
	_name_field=LevelUI.text_field(%Settings,"名称",label,func(value):label=value)
	_action_choice=LevelUI.choice(%Settings,"动作",["default"],"default",func(value):action=value;_refresh())
	_fps=LevelUI.number(%Settings,"帧率",12,func(value):frames.set_animation_speed(action,value);_refresh_time(),1,1,240)
	_loop=LevelUI.toggle(%Settings,"循环",true,func(value):frames.set_animation_loop(action,value))
	for spec in [["列数","columns",1],["行数","rows",1],["格宽（0=自动）","cell_width",0],["格高（0=自动）","cell_height",0],["边距","margin",0],["间隔","spacing",0],["首帧","first_frame",1],["末帧（0=全部）","last_frame",0]]:
		LevelUI.number(%SheetSettings,spec[0],spec[2],func(value):set(spec[1],int(value)),1,1 if spec[1] in ["columns","rows","first_frame"] else 0,10000)
	LevelUI.button(%SheetSettings,"应用切割",slice_sheet);%SheetSettings.hide()
	%Frames.item_selected.connect(_select_frame)
	%Frames.frame_moved.connect(_move_frame)
	%Time.value_changed.connect(func(value):_playing=false;_seconds=value;_sample())
	confirmed.connect(_write);canceled.connect(_close)
	close_requested.connect(_close)
	window_input.connect(func(event):
		if event is InputEventKey and event.pressed and event.keycode==KEY_SPACE:
			var focus:=gui_get_focus_owner()
			if not focus is LineEdit:_playing=not _playing;set_input_as_handled())
	frames.set_animation_speed("default",12);_refresh()

func _file(title_text: String,mode: int,filters: PackedStringArray,callback: Callable) -> void:
	if _busy:return
	var dialog:=FileDialog.new();dialog.title=title_text;dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.file_mode=mode;dialog.filters=filters;add_child(dialog)
	if mode==FileDialog.FILE_MODE_OPEN_FILES:dialog.files_selected.connect(func(paths):callback.call(paths);dialog.queue_free())
	elif mode==FileDialog.FILE_MODE_OPEN_DIR:dialog.dir_selected.connect(func(path):callback.call(path);dialog.queue_free())
	else:dialog.file_selected.connect(func(path):callback.call(path);dialog.queue_free())
	dialog.canceled.connect(func():dialog.queue_free();get_cancel_button().grab_focus())
	dialog.popup_centered(Vector2i(850,520))

func _choose_images() -> void:_file("选择连续图片",FileDialog.FILE_MODE_OPEN_FILES,["*.png,*.jpg,*.jpeg,*.webp,*.svg ; 图片"],load_images)
func _choose_folder() -> void:
	_file("选择图片文件夹",FileDialog.FILE_MODE_OPEN_DIR,[],func(folder):
		var paths:=PackedStringArray()
		for file in DirAccess.get_files_at(folder):
			if file.get_extension().to_lower() in LevelAnimationAsset.IMAGE_EXTENSIONS:paths.append(folder.path_join(file))
		load_images(paths))
func _choose_sheet() -> void:
	_file("选择精灵表",FileDialog.FILE_MODE_OPEN_FILE,["*.png,*.jpg,*.jpeg,*.webp ; 精灵表"],func(path):
		source_sheet=LevelAnimationAsset.read_texture(path);_fps.set_value_no_signal(12);_loop.set_pressed_no_signal(true);label=path.get_file().get_basename();_name_field.text=label;get_ok_button().disabled=true;%SheetSettings.show();_show_sheet(true))
func _choose_resource() -> void:_file("选择 SpriteFrames",FileDialog.FILE_MODE_OPEN_FILE,["*.tres,*.res ; SpriteFrames"],func(path):_resource_replacements.clear();load_resource(path))

func load_images(paths: PackedStringArray) -> void:
	var ordered:=Array(paths);ordered.sort_custom(func(a,b):return str(a).naturalnocasecmp_to(str(b))<0)
	_busy=true;get_ok_button().disabled=true;frames=SpriteFrames.new();frames.set_animation_speed("default",12);action="default";_names.clear();%SheetSettings.hide();source_sheet=null
	for path: String in ordered:
		if _cancel:break
		var texture:=LevelAnimationAsset.read_texture(path)
		if texture!=null:frames.add_frame(action,texture);_names.append(path.get_file())
		%Status.text="读取图片 %d / %d"%[_names.size(),ordered.size()]
		await get_tree().process_frame
	_busy=false
	if _cancel:queue_free();return
	_refresh_actions();_refresh()

func load_resource(path: String) -> void:
	if _busy:return
	_busy=true;get_ok_button().disabled=true
	var prepared:={};var dependencies:=LevelAnimationAsset.source_dependencies(path,_resource_replacements)
	for index in dependencies.size():
		if _cancel:break
		var dependency: Dictionary=dependencies[index]
		if FileAccess.file_exists(dependency.path) and dependency.path.get_extension().to_lower() in LevelAnimationAsset.IMAGE_EXTENSIONS:prepared[dependency.path]=LevelAnimationAsset.read_texture(dependency.path)
		%Status.text="读取来源图片 %d / %d，可取消"%[index+1,dependencies.size()]
		await get_tree().process_frame
	_busy=false
	if _cancel:queue_free();return
	var loaded:=LevelAnimationAsset.import_resource(path,_resource_replacements,prepared)
	LevelUI.clear(%Missing)
	if not loaded.error.is_empty():
		%Status.text=loaded.error;get_ok_button().disabled=true
		for missing: Dictionary in loaded.get("missing",[]):
			LevelUI.button(%Missing,"重新定位："+str(missing.path),func():
				_file("补齐 "+str(missing.ref),FileDialog.FILE_MODE_OPEN_FILE,[],func(chosen):_resource_replacements[missing.ref]=chosen;load_resource(path)))
		return
	var resource: SpriteFrames=loaded.frames
	if resource.get_animation_names().is_empty():%Status.text="资源中没有动作，请先制作至少一个动作。";return
	frames=resource.duplicate(true);label=path.get_file().get_basename();_name_field.text=label;_names.clear();source_sheet=null;%SheetSettings.hide();_refresh_actions();_refresh()

func slice_sheet() -> void:
	if source_sheet==null or _busy:return
	LevelUI.finish_fields(%SheetSettings)
	var extent:=source_sheet.get_size()-Vector2.ONE*margin*2-Vector2(columns-1,rows-1)*spacing
	var cell:=(extent/Vector2(columns,rows)).floor()
	if cell_width>0:cell.x=cell_width
	if cell_height>0:cell.y=cell_height
	if cell.x<1 or cell.y<1:%Status.text="边距或行列数过大，切割区域为空。";return
	var candidate:=SpriteFrames.new();candidate.set_animation_speed("default",_fps.value);candidate.set_animation_loop("default",_loop.button_pressed);var names: Array[String]=[]
	for index in range(maxi(0,first_frame-1),mini(columns*rows,last_frame) if last_frame>0 else columns*rows):
		var texture:=AtlasTexture.new();texture.atlas=source_sheet
		texture.region=Rect2(Vector2(margin,margin)+Vector2(index%columns,index/columns)*(cell+Vector2.ONE*spacing),cell)
		if texture.region.end.x>source_sheet.get_width() or texture.region.end.y>source_sheet.get_height():%Status.text="切割范围超出精灵表，请调整格宽／格高或行列数。";return
		candidate.add_frame("default",texture);names.append("第 %d 格"%(index+1))
	frames=candidate;action="default";_names=names
	_refresh_actions();_refresh();_show_sheet(true)

func _refresh_actions() -> void:
	_action_choice.clear()
	for name in frames.get_animation_names():_action_choice.add_item(name)
	if not frames.has_animation(action):action="default" if frames.has_animation("default") else str(frames.get_animation_names()[0])
	# 动作来源可以多选，直接按素材名字切换，不保留旧下拉的候选数组。
	for connection in _action_choice.item_selected.get_connections():_action_choice.item_selected.disconnect(connection.callable)
	_action_choice.item_selected.connect(func(index):action=_action_choice.get_item_text(index);_refresh())
	for index in _action_choice.item_count:
		if _action_choice.get_item_text(index)==action:_action_choice.select(index)

func _refresh() -> void:
	%Frames.clear()
	var count:=frames.get_frame_count(action)
	for index in count:%Frames.add_item(_names[index] if _names.size()==count else "第 %d 帧"%(index+1),frames.get_frame_texture(action,index))
	_fps.set_value_no_signal(frames.get_animation_speed(action));_loop.set_pressed_no_signal(frames.get_animation_loop(action))
	get_ok_button().disabled=count==0;_refresh_time()
	if count>0:%Frames.select(0);_show_frame(0)
	%Status.text="%s · %d 帧 · %.3f 秒；可拖动列表调整帧序。"%[action,count,LevelAnimationAsset.duration(frames,action)]

func _refresh_time() -> void:%Time.max_value=maxf(0.001,LevelAnimationAsset.duration(frames,action));%Time.set_value_no_signal(0);_seconds=0
func _select_frame(index: int) -> void:
	_playing=false;_seconds=0
	for previous in index:_seconds+=frames.get_frame_duration(action,previous)/frames.get_animation_speed(action)
	%Time.set_value_no_signal(_seconds);_show_frame(index)

func _show_frame(index: int) -> void:
	%Preview.regions.clear();%Preview.texture=frames.get_frame_texture(action,index);%Preview.queue_redraw()
	_duration.set_value_no_signal(frames.get_frame_duration(action,index))
func _sample() -> void:
	var cursor:=_seconds*frames.get_animation_speed(action)
	for index in frames.get_frame_count(action):
		var length:=frames.get_frame_duration(action,index)
		if cursor<length or index==frames.get_frame_count(action)-1:_show_frame(index);%Frames.select(index);return
		cursor-=length
func _process(delta: float) -> void:
	if not visible or not _playing or _busy:return
	var duration:=LevelAnimationAsset.duration(frames,action)
	if duration<=0:return
	_seconds+=delta
	if _seconds>=duration:
		if frames.get_animation_loop(action):_seconds=fposmod(_seconds,duration)
		else:_seconds=duration;_playing=false
	%Time.set_value_no_signal(_seconds);_sample()
func _step(delta: int) -> void:
	_playing=false
	var selected: PackedInt32Array=%Frames.get_selected_items()
	if selected.is_empty():return
	var index:=clampi(selected[0]+delta,0,frames.get_frame_count(action)-1);%Frames.select(index);%Frames.ensure_current_is_visible();_select_frame(index)
func _reorder(delta: int) -> void:
	var selected: PackedInt32Array=%Frames.get_selected_items()
	if not selected.is_empty():_move_frame(selected[0],clampi(selected[0]+delta,0,frames.get_frame_count(action)-1))
func _move_frame(from: int,to: int) -> void:
	if from==to or _busy:return
	var texture:=frames.get_frame_texture(action,from);var length:=frames.get_frame_duration(action,from)
	frames.remove_frame(action,from);frames.add_frame(action,texture,length,to)
	if _names.size()==frames.get_frame_count(action):var name:=_names[from];_names.remove_at(from);_names.insert(to,name)
	_refresh();%Frames.select(to);_select_frame(to)
func _remove_frame() -> void:
	if _busy:return
	var selected: PackedInt32Array=%Frames.get_selected_items()
	if selected.is_empty():return
	frames.remove_frame(action,selected[0]);_names.clear();_refresh()
func _show_sheet(enabled: bool) -> void:
	if not enabled or source_sheet==null:_sample();return
	_playing=false;%Preview.texture=source_sheet;%Preview.regions.clear()
	for index in frames.get_frame_count(action):
		var texture:=frames.get_frame_texture(action,index)
		if texture is AtlasTexture:%Preview.regions.append(texture.region)
	%Preview.queue_redraw()
func _write() -> void:
	if _busy:return
	LevelUI.finish_fields(%Settings);LevelUI.finish_fields(%FrameActions);_busy=true;get_ok_button().disabled=true
	var result:=await LevelAnimationAsset.write(frames.duplicate(true),directory,label,func(done,total):%Status.text="正在导入 %d / %d，可取消"%[done,total],func():return _cancel,action)
	_busy=false
	if _cancel:queue_free();return
	if not result.error.is_empty():%Status.text=result.error;get_ok_button().disabled=false;return
	imported.emit(result.path);queue_free()
func _close() -> void:
	_cancel=true;hide()
	if not _busy:queue_free()
