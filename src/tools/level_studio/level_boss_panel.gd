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
var _search := ""
var _note_type := "全部类型"
var _note_side := "全部侧"
var _note_scope := "全部绑定"
var _note_from := 0.0
var _note_to := 0.0
var _preview_role := ""
var _summary := Label.new()
var _local_playing := false
var _play_button: Button

func edit_document() -> LevelDocument: return workspace.document

func _ready() -> void:
	size_flags_vertical=Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; add_child(scroll)
	scroll.add_child(_content); _content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	LevelUI.label(_content,"BOSS 攻击编排",18)
	_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;_content.add_child(_summary)
	var navigation:=HFlowContainer.new();_content.add_child(navigation)
	for pair in [["动作设置","Actions"],["战斗与阶段","Battle"],["发射路径","Paths"]]:
		LevelUI.button(navigation,pair[0],func():
			if _form.get_child_count()>0:scroll.ensure_control_visible(_form.get_child(0).get_node(pair[1])))
	_content.add_child(_binding_select); _binding_select.item_selected.connect(_select_binding)
	LevelUI.button(_content,"复制动作配置并重新选音符",_copy_settings)
	var filters:=VBoxContainer.new();filters.visible=false
	var filter_button:=LevelUI.button(_content,"展开音符筛选",func():filters.visible=not filters.visible)
	filter_button.tooltip_text="按类型、生死侧、绑定及时间筛选；不改变已选音符"
	_content.add_child(filters)
	var search := LineEdit.new(); search.placeholder_text="搜索音符时间或 ID"; filters.add_child(search)
	search.text_changed.connect(func(value): _search=value;_populate_notes())
	LevelUI.choice(filters,"类型",["全部类型","Tap","Hold","调频幽灵"],"全部类型",func(value):_note_type=value;_populate_notes())
	LevelUI.choice(filters,"生死侧",["全部侧","生","死","双侧幽灵"],"全部侧",func(value):_note_side=value;_populate_notes())
	LevelUI.choice(filters,"绑定",["全部绑定","未绑定","当前绑定","其他绑定"],"全部绑定",func(value):_note_scope=value;_populate_notes())
	LevelUI.number(filters,"段落起点 秒",0,func(value):_note_from=value;_populate_notes(),0.1,0,100000)
	LevelUI.number(filters,"段落终点（0=全曲）",0,func(value):_note_to=value;_populate_notes(),0.1,0,100000)
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
	LevelUI.button(_content,"全选筛选结果",func():
		var ids: Array=data.note_ids.duplicate()
		for index in _notes.item_count:
			var id: String=str(_notes.get_item_metadata(index))
			if id not in ids:ids.append(id)
		_change("note_ids",ids);_populate_notes())
	_viewport.size=Vector2i(640,360); _viewport.size_2d_override=Vector2i(640,360); _viewport.size_2d_override_stretch=true
	_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED; add_child(_viewport); _viewport.add_child(_preview)
	var image := TextureRect.new(); image.texture=_viewport.get_texture(); image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; image.custom_minimum_size.y=140; _content.add_child(image)
	LevelUI.label(_content,"动作局部时间（秒）",12)
	_slider.min_value=0; _slider.max_value=3; _slider.step=0.001; _content.add_child(_slider)
	_slider.value_changed.connect(func(_value): _sample_action())
	var stepping:=HBoxContainer.new();_content.add_child(stepping)
	_play_button=LevelUI.button(stepping,"播放动作",func():_local_playing=not _local_playing;_play_button.text="暂停动作" if _local_playing else "播放动作")
	LevelUI.button(stepping,"上一素材帧",func():_step_material_frame(-1));LevelUI.button(stepping,"下一素材帧",func():_step_material_frame(1))
	LevelUI.button(_content,"将当前动作帧设为出手帧",func():
		workspace.document.begin_edit();_change("action",LevelBossActions.resolve(workspace.assets(),workspace.document.find("objects",object_id),data).action);_change("action_mode","custom");_change("release_sec",_slider.value);workspace.document.end_edit();_rebuild_form())
	_content.add_child(_release_label); _release_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_form)
	_create=LevelUI.button(_content,"创建绑定",_apply)
	LevelUI.button(_content,"取消新建 / 返回属性",func():workspace._show_inspector("properties"))
	LevelUI.button(_content,"删除当前绑定",func():
		var existing: Dictionary=workspace.document.find("bindings",binding_id)
		if not existing.is_empty(): workspace.document.replace("删除 BOSS 绑定","bindings",[existing],[])
		if workspace.document.last_error.is_empty():open(object_id))
	var feedback := HFlowContainer.new(); _content.add_child(feedback)
	LevelUI.button(feedback,"预览命中反馈",func(): workspace.test_feedback(true))
	LevelUI.button(feedback,"预览失误反馈",func(): workspace.test_feedback(false))
	workspace.document.changed.connect(func(kind):
		if kind=="edit" and not workspace.document.editing and not binding_id.is_empty():
			var current: Dictionary=workspace.document.find("bindings",binding_id)
			if not current.is_empty(): data=current.duplicate(true); _update_times()
			if visible and not workspace._field_focused(): _rebuild_form(); _populate_notes())


## 局部播放只推进素材时钟，不启动歌曲或改变主时间线。
func _process(delta: float) -> void:
	if not _local_playing:return
	if not is_visible_in_tree():
		_local_playing=false;_play_button.text="播放动作";return
	_slider.value=fposmod(_slider.value+delta,maxf(0.001,_slider.max_value))

func _defaults() -> Dictionary:
	var object_data: Dictionary=workspace.document.find("objects",object_id)
	var actions: PackedStringArray=workspace.assets().actions(str(object_data.get("asset","")))
	var action := str(actions[0]) if not actions.is_empty() else "attack"
	var preferred: String=workspace.assets().default_animation(str(object_data.get("asset","")))
	if not preferred.is_empty():action=preferred
	var duration: float=workspace.assets().action_duration(str(object_data.get("asset","")),action)
	return {"id":LevelFormat.id("binding"),"object_id":object_id,"difficulty":workspace.difficulty(),"note_ids":[],"action":action,"release_sec":workspace.assets().release_time(str(object_data.get("asset","")),action),"return_us":600000,"action_duration_us":maxi(10000,roundi(duration*1000000)),"rate":1.0,"life_anchor":"life","death_anchor":"death","sound":"","effect":"","hit_effect":"","miss_effect":""}

func open(id: String, binding := "") -> void:
	object_id=id; binding_id=binding; _preview_role="";_local_playing=false
	if _play_button!=null:_play_button.text="播放动作"
	data=workspace.document.find("bindings",binding).duplicate(true) if not binding.is_empty() else _defaults()
	if data.is_empty(): binding_id=""; data=_defaults()
	# 派生绑定在打开时作为可编辑草稿呈现，创建后成为显式覆盖；打开本身不写盘。
	var effective:=LevelBossCompiler.effective_bindings(workspace.song_document.chart(),workspace.document.data.show,workspace.difficulty())
	for entry: Dictionary in effective:
		if entry.get("automatic",false) and entry.object_id==object_id and (binding.is_empty() or entry.id==binding):
			data.merge(entry,true);data.id=LevelFormat.id("binding");binding_id=""
	_binding_select.clear(); _binding_select.add_item("自动关联（保存为显式绑定）" if data.get("automatic",false) else "新建攻击绑定"); _binding_select.set_item_metadata(0,"")
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

func _populate_notes() -> void:
	_updating=true; _notes.clear()
	var tempo: TempoMap=workspace.song_document.tempo_map()
	for note in ChartEditEvents.all(workspace.song_document.chart()):
		if not (note is NoteEvent or note is GhostEvent) or not note.boss: continue
		var seconds:=float(tempo.tick_to_us(note.tick))/1000000
		var kind:= "调频幽灵" if note is GhostEvent else ("Tap" if note.kind==GameplayTypes.NoteKind.TAP else "Hold")
		var side: String="双侧幽灵" if note is GhostEvent else ("生" if note.affinity==GameplayTypes.Affinity.ZHU else "死")
		if _note_side!="全部侧" and side!=_note_side:continue
		var owners: Array=LevelBossCompiler.effective_bindings(workspace.song_document.chart(),workspace.document.data.show,workspace.difficulty()).filter(func(binding):return binding.difficulty==workspace.difficulty() and note.event_id in binding.note_ids)
		if _note_type!="全部类型" and kind!=_note_type:continue
		if seconds<_note_from or (_note_to>0 and seconds>_note_to):continue
		if _note_scope=="未绑定" and not owners.is_empty():continue
		if _note_scope=="当前绑定" and not note.event_id in data.note_ids:continue
		if _note_scope=="其他绑定" and not owners.any(func(binding):return binding.id!=binding_id):continue
		var owner_names: Array=owners.map(func(binding):return str(workspace.document.find("objects",binding.object_id).get("name","失效对象"))+" / "+str(binding.action))
		var caption := "%.3f s · %s · %s\n%s"%[seconds,side+" · "+kind,note.event_id,"未绑定" if owners.is_empty() else "、".join(owner_names)]
		if not _search.is_empty() and not _search.to_lower() in caption.to_lower(): continue
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
		if not before.is_empty():
			workspace.document.replace("修改 BOSS "+key,"bindings",[before],[data.duplicate(true)])
			if not workspace.document.last_error.is_empty():data=before;_rebuild_form()
	_update_times(); _sample_action()

func _rebuild_form() -> void:
	LevelUI.clear(_form)
	var panel=load("res://scenes/tools/level_studio/boss_options.tscn").instantiate();_form.add_child(panel)
	var form: VBoxContainer=panel.get_node("Actions")
	var object_data: Dictionary=workspace.document.find("objects",object_id)
	if object_data.is_empty(): return
	var actions: PackedStringArray=workspace.assets().actions(str(object_data.asset))
	LevelUI.label(form,"动作识别",16)
	LevelUI.choice(form,"攻击控制",["自动识别","手动覆盖"],"手动覆盖" if data.get("action_mode","auto")=="custom" else "自动识别",func(value):_change("action_mode","custom" if value=="手动覆盖" else "auto");_rebuild_form())
	var spec := LevelBossActions.resolve(workspace.assets(),object_data,data)
	_summary.text="静息循环：%s\n%s\n攻击：%s"%[str(spec.idle),"自动关联 %d 个音符（当前难度）"%data.note_ids.size() if data.get("automatic",false) else ("已绑定 %d 个音符"%data.note_ids.size() if not binding_id.is_empty() else "新建草稿：尚未创建音符绑定")," → ".join([spec.attack_start,spec.attack_loop,spec.attack_end]) if spec.segmented else (spec.action if not str(spec.action).is_empty() else "未识别，请配置动作映射")]

	LevelUI.label(form,"自动识别："+(str(spec.attack_start)+" → "+str(spec.attack_loop)+" → "+str(spec.attack_end) if spec.segmented else str(spec.attack)),12)
	if str(spec.action).is_empty(): LevelUI.label(form,"未找到攻击动作，请配置映射或显式覆盖。",12)
	if not actions.is_empty():
		LevelUI.choice(form,"素材动作",Array(actions),str(data.action),func(value):
			workspace.document.begin_edit(); _change("action_mode","custom"); _change("action",value); _change("release_sec",workspace.assets().release_time(object_data.asset,value))
			if str(object_data.asset).ends_with(LevelSpineAsset.SUFFIX):_change("action_duration_us",roundi(workspace.assets().action_duration(object_data.asset,value)/float(data.rate)*1000000))
			workspace.document.end_edit(); _rebuild_form())
	else: LevelUI.label(form,"素材未声明动作，请在素材库替换 BOSS 素材。",12)
	if data.get("action_mode","auto")=="auto":
		LevelUI.label(form,"自动出手 %.3f 秒%s"%[float(spec.release),"（未声明标记，采用动作中点）" if not spec.segmented and not workspace.assets().has_release_marker(object_data.asset,spec.action) else ""],12)
	else:LevelUI.number(form,"出手帧 秒",float(data.release_sec),func(value):_change("release_sec",value),0.001,0,120)
	LevelUI.number(form,"动作长度 秒",float(data.action_duration_us)/1000000,func(value):_change("action_duration_us",roundi(value*1000000)),0.01,0.01,120)
	LevelUI.number(form,"动作速率",float(data.rate),func(value):_change("rate",value),0.05,0.05,8)
	form=panel.get_node("Paths")
	LevelUI.label(form,"发射路径",16)
	LevelUI.choice(form,"路径模式",["分侧自然散射","原自定义路径"],"原自定义路径" if data.get("path_mode","auto")=="custom" else "分侧自然散射",func(value):_change("path_mode","custom" if value=="原自定义路径" else "auto");_rebuild_form())
	LevelUI.number(form,"巡航速度 像素/秒",float(data.get("flight_speed",object_data.get("boss",{}).get("flight_speed",600))),func(value):_change("flight_speed",value),10,100,3000)
	LevelUI.number(form,"散射角度 ±度",float(data.get("spread_deg",object_data.get("boss",{}).get("spread_deg",30))),func(value):_change("spread_deg",value),1,0,60)
	LevelUI.number(form,"自定义飞行时间 秒",float(data.return_us)/1000000,func(value):_change("return_us",roundi(value*1000000)),0.01,0.01,5)
	form=panel.get_node("Battle")
	LevelUI.label(form,"战斗与阶段（对象设置）",16)
	var previews:=HFlowContainer.new();form.add_child(previews)
	for pair in [["静息","idle"],["攻击","attack_start"],["受击","hurt"],["半血转阶段","phase_break"],["破防攻击","attack_loop"],["死亡","death"]]:
		var button:=LevelUI.button(previews,"预览"+pair[0],func():
			_preview_role=pair[1]
			_slider.max_value=7.0 if pair[1]=="death" else 3.0
			_slider.value=0;_sample_action())
		button.disabled=str(spec.get(pair[1],"" )).is_empty() and (pair[1] not in ["attack_start","attack_loop"] or str(spec.get("attack","")).is_empty())
	LevelUI.number(form,"血量 / 理论伤害",float(object_data.get("boss",{}).get("health_ratio",0.8)),func(value):_object_setting("health_ratio",value),0.05,0.05,2)
	var profiles := {"沿用导入素材":"","蝙蝠完整表现":"bat","蛇完整表现":"snake","羊头双阶段完整表现":"goat","羊头真眼完整表现":"goat_eye"}
	LevelUI.choice(form,"完整表现素材",profiles.keys(),profiles.find_key(str(object_data.get("boss",{}).get("visual",""))),func(value):_object_setting("visual",profiles[value]))
	LevelUI.choice(form,"整关战斗预览",["全 Perfect 模拟","未击败模拟"],"未击败模拟" if workspace.surface.player.boss_preview_mode=="miss" else "全 Perfect 模拟",func(value):
		workspace.surface.player.boss_preview_mode="miss" if value=="未击败模拟" else "perfect"
		workspace.surface.player.refresh_visuals(workspace.section,workspace.time_us))
	LevelUI.label(form,"空值沿用导入素材；goat 包含揭眼与真眼最终死亡。零血先破防，最后一波结算后死亡。",12)
	form=panel.get_node("Advanced/Content")
	for role in ["idle","attack","attack_start","attack_loop","attack_end","hurt","phase_break","death"]:
		var choices: Array=[""]; choices.append_array(Array(actions))
		LevelUI.choice(form,role+" 映射",choices,str(object_data.get("boss",{}).get("actions",{}).get(role,"")),func(value):
			var mapping: Dictionary=workspace.document.find("objects",object_id).get("boss",{}).get("actions",{}).duplicate()
			if str(value).is_empty():mapping.erase(role)
			else:mapping[role]=value
			_object_setting("actions",mapping))
	form=panel.get_node("Paths")
	var anchors: Array=[]
	if workspace.assets().entries.has(object_data.asset): anchors=workspace.assets().entries[object_data.asset].anchors.keys()
	for pair in [["生发射锚点","life_anchor"],["死发射锚点","death_anchor"]]:
		if not anchors.is_empty(): LevelUI.choice(form,pair[0],anchors,str(data.get(pair[1],"")),func(value):_change(pair[1],value))
		else: LevelUI.label(form,pair[0]+"：素材未声明锚点",12)
	for pair in [["发射音效","sound","audio"],["发射特效","effect","effect"],["命中特效","hit_effect","effect"],["失误特效","miss_effect","effect"]]:
		workspace.resource_field(form,pair[0],str(data.get(pair[1],"")),pair[2],func(value):_change(pair[1],value))
	for pair in [["生弹射手柄","life_handle",Vector2(1700,-100)],["死弹射手柄","death_handle",Vector2(-1700,100)]]:
		LevelUI.vector(form,pair[0],LevelFormat.vec(data.get(pair[1],[]),pair[2]),func(value):_change(pair[1],value),1,func(axis,value):
			var next:=LevelFormat.vec(data.get(pair[1],[]),pair[2]);next[axis]=value;_change(pair[1],[next.x,next.y]))
	LevelUI.label(form,"手柄相对发射点；入轨端切线自动衔接普通路径。",11)
	_slider.max_value=maxf(float(data.action_duration_us)/1000000*float(data.rate),float(data.release_sec)); _update_times(); _sample_action()

func _sample_action() -> void:
	var object_data: Dictionary=workspace.document.find("objects",object_id).duplicate(true)
	if object_data.is_empty(): return
	object_data.fields.position=[320,180]; object_data.fields.scale=[1,1]; object_data.fields.rotation=0; object_data.parent_id=""; object_data.layer="world"
	var track:=LevelFormat.track(object_id,"action","song","action")
	var spec:=LevelBossActions.resolve(workspace.assets(),object_data,data)
	var clip:=LevelFormat.clip(0,"",maxi(1,roundi(_slider.max_value*1000000))); clip.action=spec.get(_preview_role,spec.action) if not _preview_role.is_empty() else spec.action; clip.rate=1.0;clip.boss_control=true
	if str(clip.action).is_empty() and _preview_role in ["attack_start","attack_loop"]:clip.action=spec.attack
	track.clips=[clip]
	var show:={"objects":[object_data],"tracks":[track],"bindings":[]}
	var signature: String = str(object_data.id)+"|"+str(object_data.asset)+workspace.document.directory+JSON.stringify(workspace.document.data.packs)+JSON.stringify(object_data.get("boss",{}))
	if signature!=_preview_signature: _preview.configure(show,workspace.document.directory,workspace.document.data.packs,workspace.difficulty()); _preview_signature=signature
	else: _preview.show=show
	_preview.seek("song",roundi(_slider.value*1000000)); _viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	var content: Node=_preview.objects[object_id].get_node_or_null("Content")
	if content != null and content.has_method("preview_role"):content.preview_role(_preview_role if not _preview_role.is_empty() else "attack_start",_slider.value)

func _update_times() -> void:
	if _create==null: return
	_create.text="保存为显式绑定" if data.get("automatic",false) else "创建绑定"
	_create.visible=binding_id.is_empty(); _create.disabled=data.get("note_ids",[]).is_empty()
	_create.tooltip_text="先选择至少一个 BOSS 音符" if _create.disabled else "创建绑定（可撤销）"
	if data.get("note_ids",[]).is_empty(): _release_label.text="选择音符后，主时间线显示攻击时序。"; return
	var approach := 2.25
	if is_instance_valid(workspace.preview.stage_root): approach=workspace.preview.stage_root.stage_session.rule_set.approach_duration_sec
	var lines:=PackedStringArray(["新建草稿" if binding_id.is_empty() else "已创建绑定","歌曲时间 · 开始 / 发射 / 入轨 / 判定"])
	var first:=INF;var last:=-INF
	for id: String in data.note_ids:
		var note: Resource=workspace.song_document.find_note(id)
		if note==null:lines.append("失效关联 · "+id);continue
		var hit:=float(workspace.song_document.tempo_map().tick_to_us(note.tick))/1000000
		var release:=hit-approach-float(data.return_us)/1000000
		var entry:=hit-approach
		var resolved:=LevelBossActions.resolve(workspace.assets(),workspace.document.find("objects",object_id),data)
		if data.get("path_mode","auto")!="custom" and workspace.surface.emissions.has(id):
			var path: Dictionary=workspace.surface.emissions[id]
			release=float(path.release_us)/1000000;entry=float(path.entry_us)/1000000
		var start:=release-float(resolved.release)/float(data.rate)
		first=minf(first,start);last=maxf(last,hit)
		lines.append("%s：%.3f / %.3f / %.3f / %.3f s"%[id,start,release,entry,hit])
	if first!=INF:lines.insert(1,"覆盖 %.3f → %.3f s"%[first,last])
	_release_label.text="\n".join(lines)

## 非均匀帧长按素材边界逐帧，主时间线速率不改变这里的读数。
func _step_material_frame(direction: int) -> void:
	var entry: Dictionary=workspace.document.find("objects",object_id)
	var resource: Resource=workspace.assets().resolve(str(entry.get("asset","")))
	var boundaries: Array[float]=[0.0]
	if resource is SpriteFrames and resource.has_animation(data.action):
		var at:=0.0
		for index in resource.get_frame_count(data.action):
			at+=resource.get_frame_duration(data.action,index)/resource.get_animation_speed(data.action);boundaries.append(at)
	else:
		# 场景动作没有离散图片帧时采用制作帧率 60 fps。
		_slider.value=clampf((floorf(_slider.value*60+0.0001)+direction)/60,0,_slider.max_value);return
	if direction<0:boundaries.reverse()
	for at: float in boundaries:
		if (at-_slider.value)*direction>0.00001:_slider.value=at;return

func _apply() -> void:
	if data.note_ids.is_empty(): return
	data.erase("automatic")
	workspace.document.replace("创建 BOSS 绑定","bindings",[],[data.duplicate(true)])
	if workspace.document.last_error.is_empty():open(object_id,str(data.id))

func _object_setting(key: String, value: Variant) -> void:
	var before: Dictionary=workspace.document.find("objects",object_id).duplicate(true)
	var after := before.duplicate(true)
	if not after.has("boss"): after.boss={}
	after.boss[key]=value
	workspace.document.replace("修改 BOSS 设置","objects",[before],[after])
