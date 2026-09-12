class_name LevelBossPanel
extends VBoxContainer
## 绑定面板与主时间线并行；只有新建草稿需要“创建”，已存在绑定按字段撤销。
var workspace
var object_id := ""
var binding_id := ""
var data := {}
var _form := VBoxContainer.new()
var _notes := ItemList.new()
var _binding_select := OptionButton.new()
var _preview := LevelShowPlayer.new()
var _viewport := SubViewport.new()
var _slider := HSlider.new()
var _release_label := Label.new()
var _updating := false
var _preview_signature := ""
var _create: Button
var _content := VBoxContainer.new()

func edit_document() -> LevelDocument: return workspace.document

func _ready() -> void:
	size_flags_vertical=Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
	scroll.add_child(_content); _content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	LevelUI.label(_content,"BOSS 攻击编排",18)
	_content.add_child(_binding_select); _binding_select.item_selected.connect(_select_binding)
	LevelUI.button(_content,"复制动作配置并重新选音符",_copy_settings)
	var search := LineEdit.new(); search.placeholder_text="搜索音符时间或 ID"; _content.add_child(search)
	search.text_changed.connect(func(value): _populate_notes(value))
	LevelUI.label(_content,"只读谱面 · 选择 BOSS 音符",12)
	_notes.custom_minimum_size.y=130; _notes.select_mode=ItemList.SELECT_MULTI; _content.add_child(_notes)
	_notes.multi_selected.connect(func(_index,_selected):
		if _updating: return
		var visible_ids := []
		for index in _notes.item_count: visible_ids.append(str(_notes.get_item_metadata(index)))
		var ids: Array=data.note_ids.filter(func(id):return not id in visible_ids)
		for index in _notes.get_selected_items(): ids.append(str(_notes.get_item_metadata(index)))
		_change("note_ids",ids))
	_notes.item_activated.connect(func(index):
		var note: Resource=workspace.song_document.find_note(str(_notes.get_item_metadata(index)))
		if note!=null: workspace.seek(workspace.song_document.tempo_map().tick_to_us(note.tick)); workspace.timeline.focus_time(workspace.time_us))
	LevelUI.button(_content,"全选此难度 BOSS 音符",func():
		var ids := []
		for note in ChartEditEvents.all(workspace.song_document.chart()):
			if (note is NoteEvent or note is GhostEvent) and note.boss: ids.append(note.event_id)
		_change("note_ids",ids); _populate_notes())
	_viewport.size=Vector2i(640,360); _viewport.size_2d_override=Vector2i(640,360); _viewport.size_2d_override_stretch=true
	_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED; add_child(_viewport); _viewport.add_child(_preview)
	var image := TextureRect.new(); image.texture=_viewport.get_texture(); image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; image.custom_minimum_size.y=140; _content.add_child(image)
	LevelUI.label(_content,"动作局部时间（秒）",12)
	_slider.min_value=0; _slider.max_value=3; _slider.step=0.001; _content.add_child(_slider)
	_slider.value_changed.connect(func(_value): _sample_action())
	LevelUI.button(_content,"将当前动作帧设为出手帧",func(): _change("release_sec",_slider.value); _rebuild_form())
	_content.add_child(_release_label); _release_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_form)
	_create=LevelUI.button(_content,"创建绑定",_apply)
	LevelUI.button(_content,"取消新建 / 返回属性",func():workspace._show_inspector("properties"))
	LevelUI.button(_content,"删除当前绑定",func():
		var existing: Dictionary=workspace.document.find("bindings",binding_id)
		if not existing.is_empty(): workspace.document.replace("删除 BOSS 绑定","bindings",[existing],[])
		open(object_id))
	var feedback := HFlowContainer.new(); _content.add_child(feedback)
	LevelUI.button(feedback,"预览命中反馈",func(): workspace.test_feedback(true))
	LevelUI.button(feedback,"预览失误反馈",func(): workspace.test_feedback(false))
	workspace.document.changed.connect(func(kind):
		if kind=="edit" and not workspace.document.editing and not binding_id.is_empty():
			var current: Dictionary=workspace.document.find("bindings",binding_id)
			if not current.is_empty(): data=current.duplicate(true); _update_times()
			if visible and not workspace._field_focused(): _rebuild_form(); _populate_notes())

func _defaults() -> Dictionary:
	var object_data: Dictionary=workspace.document.find("objects",object_id)
	var actions: PackedStringArray=workspace.assets().actions(str(object_data.get("asset","")))
	var action := str(actions[0]) if not actions.is_empty() else "attack"
	return {"id":LevelFormat.id("binding"),"object_id":object_id,"difficulty":workspace.difficulty(),"note_ids":[],"action":action,"release_sec":workspace.assets().release_time(str(object_data.get("asset","")),action),"return_us":600000,"action_duration_us":1000000,"rate":1.0,"life_anchor":"life","death_anchor":"death","sound":"","effect":"","hit_effect":"","miss_effect":""}

func open(id: String, binding := "") -> void:
	object_id=id; binding_id=binding
	data=workspace.document.find("bindings",binding).duplicate(true) if not binding.is_empty() else _defaults()
	if data.is_empty(): binding_id=""; data=_defaults()
	_binding_select.clear(); _binding_select.add_item("新建攻击绑定"); _binding_select.set_item_metadata(0,"")
	for entry: Dictionary in workspace.document.entries("bindings"):
		if entry.object_id!=object_id or entry.difficulty!=workspace.difficulty(): continue
		_binding_select.add_item(str(entry.action)+" · %d 个音符"%entry.note_ids.size()); _binding_select.set_item_metadata(_binding_select.item_count-1,entry.id)
		if entry.id==binding_id: _binding_select.select(_binding_select.item_count-1)
	_populate_notes(); _rebuild_form()

func _select_binding(index: int) -> void:
	workspace._prepare_command(); open(object_id,str(_binding_select.get_item_metadata(index)))

func _copy_settings() -> void:
	var copied := data.duplicate(true)
	open(object_id)
	for key: String in copied:
		if key not in ["id","object_id","difficulty","note_ids"]: data[key]=copied[key]
	_rebuild_form(); workspace._status.text="动作配置已复制，请为新绑定选择音符"

func _populate_notes(search := "") -> void:
	_updating=true; _notes.clear()
	var tempo: TempoMap=workspace.song_document.tempo_map()
	for note in ChartEditEvents.all(workspace.song_document.chart()):
		if not (note is NoteEvent or note is GhostEvent) or not note.boss: continue
		var caption := "%.3f s · %s"%[float(tempo.tick_to_us(note.tick))/1000000,note.event_id]
		if not search.is_empty() and not search.to_lower() in caption.to_lower(): continue
		_notes.add_item(caption); _notes.set_item_metadata(_notes.item_count-1,note.event_id)
		if note.event_id in data.get("note_ids",[]): _notes.select(_notes.item_count-1,false)
	for id: String in data.get("note_ids",[]):
		if workspace.song_document.find_note(id)==null:
			_notes.add_item("失效关联 · "+id);_notes.set_item_metadata(_notes.item_count-1,id);_notes.select(_notes.item_count-1,false)
	_updating=false

func _change(key: String, value: Variant) -> void:
	data[key]=value
	if not binding_id.is_empty():
		var before: Dictionary=workspace.document.find("bindings",binding_id).duplicate(true)
		if not before.is_empty(): workspace.document.replace("修改 BOSS "+key,"bindings",[before],[data.duplicate(true)])
	_update_times(); _sample_action()

func _rebuild_form() -> void:
	LevelUI.clear(_form)
	var object_data: Dictionary=workspace.document.find("objects",object_id)
	if object_data.is_empty(): return
	var actions: PackedStringArray=workspace.assets().actions(str(object_data.asset))
	if not actions.is_empty():
		LevelUI.choice(_form,"素材动作",Array(actions),str(data.action),func(value):
			workspace.document.begin_edit(); _change("action",value); _change("release_sec",workspace.assets().release_time(object_data.asset,value)); workspace.document.end_edit(); _rebuild_form())
	else: LevelUI.label(_form,"素材未声明动作，请在素材库替换 BOSS 素材。",12)
	LevelUI.number(_form,"出手帧 秒",float(data.release_sec),func(value):_change("release_sec",value),0.001,0,120)
	LevelUI.number(_form,"动作长度 秒",float(data.action_duration_us)/1000000,func(value):_change("action_duration_us",roundi(value*1000000)),0.01,0.01,120)
	LevelUI.number(_form,"动作速率",float(data.rate),func(value):_change("rate",value),0.05,0.05,8)
	LevelUI.number(_form,"弹射回转 秒",float(data.return_us)/1000000,func(value):_change("return_us",roundi(value*1000000)),0.01,0.01,5)
	var anchors: Array=[]
	if workspace.assets().entries.has(object_data.asset): anchors=workspace.assets().entries[object_data.asset].anchors.keys()
	for pair in [["生发射锚点","life_anchor"],["死发射锚点","death_anchor"]]:
		if not anchors.is_empty(): LevelUI.choice(_form,pair[0],anchors,str(data.get(pair[1],"")),func(value):_change(pair[1],value))
		else: LevelUI.label(_form,pair[0]+"：素材未声明锚点",12)
	for pair in [["发射音效","sound","audio"],["发射特效","effect","effect"],["命中特效","hit_effect","effect"],["失误特效","miss_effect","effect"]]:
		workspace.resource_field(_form,pair[0],str(data.get(pair[1],"")),pair[2],func(value):_change(pair[1],value))
	for pair in [["生弹射手柄","life_handle",Vector2(1700,-100)],["死弹射手柄","death_handle",Vector2(-1700,100)]]:
		LevelUI.vector(_form,pair[0],LevelFormat.vec(data.get(pair[1],[]),pair[2]),func(value):_change(pair[1],value))
	LevelUI.label(_form,"手柄相对发射点；入轨端切线自动衔接普通路径。",11)
	_slider.max_value=float(data.action_duration_us)/1000000; _update_times(); _sample_action()

func _sample_action() -> void:
	var object_data: Dictionary=workspace.document.find("objects",object_id).duplicate(true)
	if object_data.is_empty(): return
	object_data.fields.position=[320,180]; object_data.fields.scale=[1,1]; object_data.fields.rotation=0; object_data.parent_id=""; object_data.layer="world"
	var track:=LevelFormat.track(object_id,"action","song","action")
	var clip:=LevelFormat.clip(0,"",int(data.action_duration_us)); clip.action=data.action; clip.rate=data.rate; track.clips=[clip]
	var show:={"objects":[object_data],"tracks":[track],"bindings":[]}
	var signature: String = str(object_data.asset)+workspace.document.directory+JSON.stringify(workspace.document.data.packs)
	if signature!=_preview_signature: _preview.configure(show,workspace.document.directory,workspace.document.data.packs,workspace.difficulty()); _preview_signature=signature
	else: _preview.show=show
	_preview.seek("song",roundi(_slider.value*1000000)); _viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func _update_times() -> void:
	if _create==null: return
	_create.visible=binding_id.is_empty(); _create.disabled=data.get("note_ids",[]).is_empty()
	_create.tooltip_text="先选择至少一个 BOSS 音符" if _create.disabled else "创建绑定（可撤销）"
	if data.get("note_ids",[]).is_empty(): _release_label.text="选择音符后，主时间线显示攻击时序。"; return
	var note: Resource=workspace.song_document.find_note(str(data.note_ids[0]))
	if note==null: _release_label.text="关联音符已失效，请重新选择。"; return
	var hit := float(workspace.song_document.tempo_map().tick_to_us(note.tick))/1000000
	var approach := 2.25
	if is_instance_valid(workspace.preview.stage_root): approach=workspace.preview.stage_root.stage_session.rule_set.approach_duration_sec
	var release := hit-approach-float(data.return_us)/1000000
	_release_label.text="歌曲时间\n动作开始 %.3f s\n发射 %.3f s → 入轨 %.3f s\n判定 %.3f s"%[release-float(data.release_sec)/float(data.rate),release,hit-approach,hit]

func _apply() -> void:
	if data.note_ids.is_empty(): return
	workspace.document.replace("创建 BOSS 绑定","bindings",[],[data.duplicate(true)])
	open(object_id,str(data.id))
