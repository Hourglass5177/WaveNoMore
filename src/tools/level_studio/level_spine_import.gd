extends ConfirmationDialog
## 骨骼导入先检查与预览，确认时才复制素材到关卡目录。
signal imported(path: String)
var directory:=""
var source:=""
var atlas:=""
var candidate:={}
var settings:={"name":"骨骼动画","default_animation":"","scale":0.2,"markers":{}}
var seconds:=0.0
var playing:=false
var actor: Node2D
var driver:=LevelAnimationDriver.new()
var viewport:=SubViewport.new()
var name_field: LineEdit
var scale_field: SpinBox
var play_button: Button

func _ready() -> void:
	dialog_hide_on_ok=false;get_ok_button().disabled=true
	LevelUI.button(%Sources,"选择骨骼文件",func():_choose("选择 Spine 骨骼",["*.spine-json,*.json,*.skel ; Spine 骨骼"],load_source))
	LevelUI.button(%Sources,"选择对应图集",func():_choose("选择 Spine 图集",["*.atlas ; Spine 图集"],func(path):atlas=path;_load()))
	name_field=LevelUI.text_field(%Settings,"素材名称",settings.name,func(value):settings.name=value)
	scale_field=LevelUI.number(%Settings,"显示比例",settings.scale,func(value):settings.scale=value;_rebuild(),0.01,0.001,100)
	play_button=LevelUI.button(%Controls,"播放",func():playing=not playing;_readout())
	LevelUI.button(%Controls,"上一帧",func():_step(-1));LevelUI.button(%Controls,"下一帧",func():_step(1))
	LevelUI.button(%Controls,"将当前动作帧设为出手帧",func():settings.markers[settings.default_animation]=seconds;_readout())
	%Actions.item_selected.connect(func(index):settings.default_animation=%Actions.get_item_text(index);seconds=0;_rebuild())
	%Time.value_changed.connect(func(value):playing=false;seconds=value;_sample())
	viewport.size=Vector2i(640,360);viewport.transparent_bg=true;viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED;add_child(viewport)
	%Preview.texture=viewport.get_texture()
	confirmed.connect(_write);canceled.connect(queue_free)

func _choose(caption: String, filters: PackedStringArray, callback: Callable) -> void:
	var dialog:=FileDialog.new();dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE
	dialog.title=caption;dialog.filters=filters;dialog.transient=true;dialog.exclusive=true;add_child(dialog)
	dialog.file_selected.connect(func(path):dialog.hide();callback.call(path);dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);dialog.popup_centered(Vector2i(850,520))

func load_source(path: String) -> void:
	source=path;settings.name=path.get_file().get_basename();name_field.text=settings.name
	# 同名图集自动带出，其他命名由美术明确选择，不使用另一套骨骼的图集。
	atlas=path.get_basename()+".atlas"
	_load()

func _load() -> void:
	playing=false;seconds=0;candidate.clear();%Actions.clear();get_ok_button().disabled=true
	if is_instance_valid(actor):actor.free();actor=null
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	%Status.text=source+"\n"+atlas
	if not FileAccess.file_exists(atlas):%Status.text+="\n请点击“选择对应图集”，图片应位于图集引用的相对路径。";return
	candidate=LevelSpineAsset.read_data(source,atlas)
	if not candidate.error.is_empty():%Status.text+="\n"+str(candidate.error);return
	settings.markers={};settings.default_animation=str(candidate.actions[0].name)
	settings.scale=300.0/maxf(1,maxf(candidate.data.get_width(),candidate.data.get_height()));scale_field.set_value_no_signal(settings.scale)
	for action in candidate.actions:%Actions.add_item(str(action.name))
	get_ok_button().disabled=false;_rebuild()

func _rebuild() -> void:
	if candidate.get("data")==null:return
	if is_instance_valid(actor):actor.free()
	actor=LevelSpineAsset.scene(candidate,settings).instantiate();viewport.add_child(actor);actor.position=Vector2(320,180)
	driver.configure(actor)
	for action in candidate.actions:
		if action.name==settings.default_animation:%Time.max_value=maxf(0.001,float(action.duration));break
	seconds=minf(seconds,%Time.max_value);_sample()

func _sample() -> void:
	if not is_instance_valid(actor):return
	driver.sample([{"id":"preview","action":settings.default_animation,"local_us":roundi(seconds*1000000),"loop":false,"weight":1.0}],roundi(seconds*1000000))
	%Time.set_value_no_signal(seconds);viewport.render_target_update_mode=SubViewport.UPDATE_ONCE;_readout()

func _readout() -> void:
	play_button.text="暂停" if playing else "播放"
	%Readout.text="动作时间 %.3f 秒 / %.3f 秒 · 出手标记 %.3f 秒"%[seconds,%Time.max_value,float(settings.markers.get(settings.default_animation,0))]

func _step(direction: int) -> void:
	playing=false;seconds=clampf(seconds+direction/60.0,0,%Time.max_value);_sample()

func _process(delta: float) -> void:
	if visible and playing and is_instance_valid(actor):seconds=fposmod(seconds+delta,%Time.max_value);_sample()

func _write() -> void:
	gui_release_focus()
	if get_ok_button().disabled:return
	var result:=LevelSpineAsset.write(source,atlas,directory,settings)
	if not result.error.is_empty():%Status.text=result.error;return
	hide();imported.emit(result.path);queue_free()
