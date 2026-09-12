class_name LevelEnvironmentPanel
extends RefCounted
## 展示请求和实际安排；计算结果不作为可写字段，避免误改循环衔接。
static func build(panel: VBoxContainer, workspace) -> void:
	var doc: LevelDocument = workspace.document
	LevelUI.label(panel,"环境场景",18)
	var initial:=str(doc.data.get("initial_background",""))
	LevelUI.label(panel,"初始环境 · "+workspace.environment_name(initial if not initial.is_empty() else "stage:"+str(doc.data.scene_id)),12)
	LevelUI.button(panel,"选择初始环境",func():workspace.choose_environment(func(asset):doc.fields("选择初始环境",{"initial_background":asset})))
	if not initial.is_empty():LevelUI.button(panel,"恢复沿用基础场景背景",func():doc.fields("恢复初始环境",{"initial_background":""}))
	LevelUI.button(panel,"在游标处添加换景",func():workspace.choose_environment(func(asset):workspace.add_environment_cue(asset,workspace.time_us)))
	var cues:Array=doc.entries("scene_cues").filter(func(cue):return cue.id in workspace.selected_items)
	if cues.is_empty():
		LevelUI.label(panel,"将环境素材拖入时间线。标记表示请求换景，各层等待自己的循环接缝后滚入。",12);return
	var cue:Dictionary=cues[0]
	LevelUI.label(panel,"已选 %d 次换景"%cues.size() if cues.size()>1 else str(cue.name),16)
	if cues.size()==1:
		LevelUI.number(panel,"请求时间（秒）",float(cue.time_us)/1000000.0,func(value):workspace.set_environment_field("time_us",roundi(value*1000000)),0.001)
	else:
		var original:=cues.duplicate(true)
		LevelUI.number(panel,"整体平移（秒）",0,func(value):
			var after:=original.duplicate(true)
			for item in after:item.time_us+=roundi(value*1000000)
			doc.replace("平移换景选区","scene_cues",cues,after),0.001)
	LevelUI.button(panel,"更换目标环境",func():workspace.choose_environment(func(asset):
		doc.begin_edit();workspace.set_environment_field("asset",asset);workspace.set_environment_field("name",workspace.environment_name(asset));doc.end_edit()))
	LevelUI.choice(panel,"作用范围",["common","difficulty"],"common" if cue.difficulties.is_empty() else "difficulty",func(value):workspace.set_environment_field("difficulties",[] if value=="common" else [workspace.difficulty()]),["所有难度","当前难度"])
	_effect_fields(panel,cue,func(key,value):workspace.set_environment_field(key,value),cues)
	LevelUI.label(panel,"滚动层：旧尾接新头，淡化只作用于接缝附近。固定装饰：直接更换或交叉淡化。",12)
	var tools:=HFlowContainer.new();panel.add_child(tools)
	LevelUI.button(tools,"预览这次衔接",workspace.preview_environment_cue)
	LevelUI.button(tools,"退出预览",workspace.end_environment_preview)
	LevelUI.button(tools,"上一帧",func():workspace.step_environment(-1))
	LevelUI.button(tools,"下一帧",func():workspace.step_environment(1))
	LevelUI.toggle(panel,"显示接缝辅助线",workspace.surface.show_environment_seams,func(value):workspace.surface.show_environment_seams=value;workspace.surface.queue_redraw())
	var sequence:StageEnvironmentSequence=workspace.timeline.environment
	if sequence==null:return
	var ids:=[""];var names:=["全部层"]
	for lane in sequence.lanes:ids.append(lane.id);names.append(lane.name)
	var controller:ParallaxController=workspace.show_player().environment_controller
	LevelUI.choice(panel,"预览层",ids,controller.environment_only_layer,func(value):controller.environment_only_layer=value;workspace._sample_show(true),names)
	for part in sequence.transitions:
		if not part.cue_id in workspace.selected_items:continue
		LevelUI.label(panel,str(part.name),14)
		var readout:=LevelUI.label(panel,"",12);readout.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		readout.set_meta("environment_part",[part.cue_id,part.layer_id])
		if cues.size()!=1:continue
		var layer_id:String=part.layer_id
		var override:Dictionary=cue.get("layers",{}).get(layer_id,{})
		var expand:=CheckBox.new();expand.text="单独设置本层效果";expand.button_pressed=not override.is_empty();panel.add_child(expand)
		var controls:=VBoxContainer.new();panel.add_child(controls);controls.visible=expand.button_pressed
		var effective:Dictionary=cue.duplicate(true);effective.merge(override,true)
		expand.toggled.connect(func(value):
			controls.visible=value
			var current:=doc.find("scene_cues",cue.id)
			var values:Dictionary=current.get("layers",{}).duplicate(true)
			if value:values[layer_id]={"effect":current.get("effect","none"),"blend_px":current.get("blend_px",128.0),"static_fade_us":current.get("static_fade_us",500000)}
			else:values.erase(layer_id)
			workspace.set_environment_field("layers",values)
			workspace.inspector.refresh.call_deferred())
		_effect_fields(controls,effective,func(key,value):
			var values:Dictionary=doc.find("scene_cues",cue.id).get("layers",{}).duplicate(true)
			if not values.has(layer_id):values[layer_id]={}
			values[layer_id][key]=value;workspace.set_environment_field("layers",values))
	update_times(panel,workspace)

## 派生时间单独更新，数值拖动时保留正在输入的控件和焦点。
static func update_times(panel:Control,workspace) -> void:
	var sequence:StageEnvironmentSequence=workspace.timeline.environment
	if sequence==null:return
	for label in panel.find_children("*","Label",true,false):
		if not label.has_meta("environment_part"):continue
		var identity:Array=label.get_meta("environment_part")
		var text:="此层与上一场景相同，无需衔接"
		for part in sequence.transitions:
			if part.cue_id!=identity[0] or part.layer_id!=identity[1]:continue
			var offset:=sequence.absolute_time(str(part.section),0)
			text="入画 %.3f s → 完成并采用新速度 %.3f s"%[float(int(part.enter_us)-offset)/1000000.0,float(int(part.finish_us)-offset)/1000000.0] if part.finish_us<900000000000000 else "当前行进下无法完成"
			if part.ready_us>part.request_us:text+="\n排队：等待此层上一场景完成衔接"
			if part.finish_us>sequence.end_us:text+="\n结束前未完成；保持原歌曲和片尾长度"
			break
		if label.text!=text:label.text=text

static func _effect_fields(panel:Control,data:Dictionary,change:Callable,cues:Array=[]) -> void:
	var effect:=LevelUI.choice(panel,"衔接效果",["none","fade"],str(data.get("effect","none")),func(value):change.call("effect",value),["无","淡化"])
	var width:=LevelUI.number(panel,"渐变宽度（设计像素）",float(data.get("blend_px",128.0)),func(value):change.call("blend_px",value),1,0,8192)
	var duration:=LevelUI.number(panel,"固定装饰淡化（秒）",float(data.get("static_fade_us",500000))/1000000.0,func(value):change.call("static_fade_us",roundi(value*1000000)),0.01,0,60)
	for field in [[effect,"effect","none"],[width,"blend_px",128.0],[duration,"static_fade_us",500000]]:
		if cues.is_empty() or cues.all(func(item):return item.get(field[1],field[2])==data.get(field[1],field[2])):continue
		if field[0] is SpinBox:field[0].get_line_edit().text="";field[0].get_line_edit().placeholder_text="多个值"
		else:field[0].select(-1);field[0].text="多个值"
