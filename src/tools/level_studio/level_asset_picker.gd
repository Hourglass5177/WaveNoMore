extends ConfirmationDialog
## 素材选择只更新预览，确认才修改工作区中的引用。
var library: LevelAssetLibrary
var caption: Callable
var commit: Callable
var packs: Array = []
var category := "all"
var current := ""
var _resource: Resource
var _frames: SpriteFrames
var _action := ""
var _seconds := 0.0
var _playing := false
var _actions: OptionButton
var _sound := AudioStreamPlayer.new()
var _view := SubViewport.new()
var _player := LevelShowPlayer.new()

func _ready() -> void:
	add_child(_sound);add_child(_view);_view.size=Vector2i(640,360);_view.transparent_bg=true
	_view.render_target_update_mode=SubViewport.UPDATE_DISABLED;_view.add_child(_player)
	_actions=OptionButton.new();%Controls.add_child(_actions)
	_actions.item_selected.connect(func(index):_action=_actions.get_item_text(index);_seconds=0;_sample())
	LevelUI.button(%Controls,"播放／暂停",func():
		_playing=not _playing
		if _resource is AudioStream:
			if _playing:_sound.play(_seconds)
			else:_seconds=_sound.get_playback_position();_sound.stop())
	LevelUI.button(%Controls,"上一帧",func():_step(-1));LevelUI.button(%Controls,"下一帧",func():_step(1))
	LevelUI.toggle(%Controls,"原始尺寸",false,func(value):%Preview.original_size=value;%Preview.queue_redraw())
	%Search.text_changed.connect(func(_value):_populate());%List.item_selected.connect(_select)
	%List.item_activated.connect(func(_index):_apply());confirmed.connect(_apply);canceled.connect(queue_free)
	visibility_changed.connect(func():if not visible:_sound.stop();_playing=false)
	_populate()

func _populate() -> void:
	%List.clear()
	var choices:=PackedStringArray(Array(library.entries.keys()));choices.append_array(library.list_files())
	for id in choices:
		var kind:=library.kind(id)
		var matches:=category=="all" or category==kind or (category=="visual" and kind in ["image","animation"]) or (category=="effect" and kind in ["image","scene"])
		if not matches or (not %Search.text.is_empty() and not %Search.text.to_lower() in str(caption.call(id)).to_lower()):continue
		%List.add_item(caption.call(id));var index: int=%List.item_count-1;%List.set_item_metadata(index,id)
		if id==current:%List.select(index)
	get_ok_button().disabled=%List.get_selected_items().is_empty()
	if not get_ok_button().disabled:_select(%List.get_selected_items()[0])
	else:
		_sound.stop();_playing=false;_resource=null;_frames=null;_actions.clear();_actions.hide()
		%Preview.texture=null;%Preview.queue_redraw();_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
		%Info.text="没有匹配的素材，请调整搜索或先导入素材。"

func _select(index: int) -> void:
	current=str(%List.get_item_metadata(index));_sound.stop();_seconds=0;_playing=false
	_resource=library.resolve(current);_frames=_resource as SpriteFrames;_actions.clear()
	%Info.remove_theme_font_override("font")
	%Preview.texture=null;%Preview.queue_redraw();_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	get_ok_button().disabled=_resource==null
	%Info.text="素材不可用，请重新定位来源并导入。" if _resource==null else str(caption.call(current))
	for name in library.actions(current):_actions.add_item(name)
	_action=library.default_animation(current) if _frames!=null else ("default" if library.actions(current).has("default") else (_actions.get_item_text(0) if _actions.item_count else ""))
	if _frames!=null and _action.is_empty():get_ok_button().disabled=true;%Info.text="素材中的动作都没有帧，请先补齐图片。"
	for item in _actions.item_count:
		if _actions.get_item_text(item)==_action:_actions.select(item)
	_actions.visible=_actions.item_count>0
	if _resource is AudioStream:_sound.stream=_resource;%Info.text+=" · %.2f 秒"%_resource.get_length()
	elif _resource is Texture2D:%Preview.texture=_resource;%Info.text+=" · %d × %d"%[_resource.get_width(),_resource.get_height()]
	elif _resource is PackedScene:
		var actor:=LevelFormat.object("actor",current);actor.fields.position=[320,180]
		_player.configure({"objects":[actor],"tracks":[],"bindings":[]},library.directory,packs,"")
		_player.assets=library
	elif _resource is Font:
		%Info.add_theme_font_override("font",_resource);%Info.text+="\n冥河，冥河！0123456789"
	_sample()

func _sample() -> void:
	if _frames!=null and _frames.has_animation(_action):
		%Preview.texture=null
		var length:=LevelAnimationAsset.duration(_frames,_action)
		var position: float=(fposmod(_seconds,length) if length>0 and _frames.get_animation_loop(_action) else minf(_seconds,length))*_frames.get_animation_speed(_action)
		for index in _frames.get_frame_count(_action):
			if position<_frames.get_frame_duration(_action,index) or index==_frames.get_frame_count(_action)-1:
				%Preview.texture=_frames.get_frame_texture(_action,index);break
			position-=_frames.get_frame_duration(_action,index)
		%Info.text="%s · %s · %d 帧 · %.3f 秒"%[caption.call(current),_action,_frames.get_frame_count(_action),length]
		if %Preview.texture!=null:%Info.text+=" · %d × %d"%[%Preview.texture.get_width(),%Preview.texture.get_height()]
	elif _resource is PackedScene:
		if not _player.show.objects.is_empty():
			var track:=LevelFormat.track(_player.show.objects[0].id,"action","song","action")
			var clip:=LevelFormat.clip(0,"",3600000000);clip.action=_action;clip.loop=true;track.clips=[clip];_player.show.tracks=[track]
			_player.seek("song",roundi(_seconds*1000000));%Preview.texture=_view.get_texture();_view.render_target_update_mode=SubViewport.UPDATE_ONCE
	%Preview.queue_redraw()

func _step(delta: int) -> void:
	_playing=false;_sound.stop()
	if _frames!=null and _frames.has_animation(_action):
		# 图片帧可有不同持续时间，逐帧按钮跳到帧起点，不使用固定 1/fps。
		var duration:=LevelAnimationAsset.duration(_frames,_action)
		if duration>0 and _frames.get_animation_loop(_action):_seconds=fposmod(_seconds,duration)
		var boundaries: Array[float]=[];var at:=0.0
		for index in _frames.get_frame_count(_action):
			boundaries.append(at);at+=_frames.get_frame_duration(_action,index)/_frames.get_animation_speed(_action)
		if delta<0:boundaries.reverse()
		for boundary in boundaries:
			if (boundary-_seconds)*delta>0.00001:_seconds=boundary;break
	else:_seconds=maxf(0,_seconds+delta/60.0)
	_sample()

func _process(delta: float) -> void:
	if visible and _playing:_seconds+=delta;_sample()

func _apply() -> void:
	if get_ok_button().disabled:return
	hide();commit.call(current);queue_free()
