class_name LevelInspector
extends VBoxContainer
## 面板只调用文档命令；参数值、轨道值和关键帧各自明确显示。
var workspace

func refresh() -> void:
	LevelUI.clear(self)
	if workspace == null: return
	var doc: LevelDocument = workspace.document
	if workspace.inspector_mode=="level": _level();return
	if workspace.selected_items.size()>1: _many_items();return
	var track := doc.find("tracks", workspace.selected_track)
	if not track.is_empty():
		var key := LevelFormat.find(track.keys, workspace.selected_item)
		var clip := LevelFormat.find(track.clips, workspace.selected_item)
		if not key.is_empty(): _key(track,key); return
		if not clip.is_empty(): _clip(track,clip); return
	if workspace.selection.is_empty(): _level(); return
	var object_data := doc.find("objects", workspace.selection[0])
	if object_data.is_empty(): _level(); return
	LevelUI.label(self, "对象属性", 18)
	LevelUI.text_field(self,"名称",object_data.name,func(value): workspace.set_object_field("name",value))
	workspace.resource_field(self,"素材",object_data.asset,"all",func(value): workspace.set_object_field("asset",value))
	LevelUI.choice(self,"坐标层",["world","life","death","hud"],object_data.layer,func(value): workspace.set_object_field("layer",value),["世界","生界","死界（中心对称）","屏幕 HUD"])
	LevelUI.number(self,"层级",float(object_data.depth),func(value): workspace.set_object_field("depth",value),1,-999,999)
	LevelUI.toggle(self,"锁定对象",object_data.locked,func(value): workspace.set_object_field("locked",value))
	LevelUI.toggle(self,"隐藏对象",object_data.hidden,func(value): workspace.set_object_field("hidden",value))
	LevelUI.label(self,("当前动画值 · 自动关键帧开启" if workspace.auto_key else "基础属性 · 自动关键帧关闭")+"\n"+str({"intro":"曲前","song":"歌曲","outro":"曲后"}[workspace.section])+" · "+("当前难度 "+workspace.difficulty() if workspace.difficulty_only else "所有难度"),12)
	if workspace.selection.size()>1: LevelUI.label(self,"已选 %d 个对象；共同属性批量修改"%workspace.selection.size(),12)
	var fields: Dictionary = object_data.fields
	if workspace.auto_key: fields = LevelShowSampler.object_state(doc.data.show,object_data,workspace.section,workspace.time_us,workspace.difficulty())
	LevelUI.vector(self,"位置",LevelFormat.vec(fields.position),func(value): workspace.set_property("position",value))
	LevelUI.number(self,"旋转 °",float(fields.rotation),func(value): workspace.set_property("rotation",value),0.5)
	LevelUI.vector(self,"大小",LevelFormat.vec(fields.scale),func(value): workspace.set_property("scale",value),0.01)
	LevelUI.number(self,"透明度",float(fields.opacity),func(value): workspace.set_property("opacity",value),0.01,0,1)
	LevelUI.color(self,"颜色",str(fields.color),func(value): workspace.set_property("color",value))
	LevelUI.toggle(self,"显示",bool(fields.visible),func(value): workspace.set_property("visible",value))
	if object_data.type == "text":
		LevelUI.text_field(self,"文字",str(fields.text),func(value): workspace.set_property("text",value))
		workspace.resource_field(self,"字体",str(fields.font),"font",func(value): workspace.set_property("font",value))
		LevelUI.number(self,"字号",float(fields.font_size),func(value): workspace.set_property("font_size",roundi(value)),1,8,400)
		LevelUI.vector(self,"区域尺寸",LevelFormat.vec(fields.size),func(value): workspace.set_property("size",value))
		LevelUI.choice(self,"对齐",[0,1,2],int(fields.alignment),func(value): workspace.set_property("alignment",value),["左","中","右"])
		LevelUI.number(self,"打字进度",float(fields.visible_ratio),func(value): workspace.set_property("visible_ratio",value),0.01,0,1)
	if object_data.type == "audio": LevelUI.number(self,"音量 dB",float(fields.volume_db),func(value): workspace.set_property("volume_db",value),0.5,-80,12)
	if object_data.type == "camera":
		LevelUI.number(self,"镜头缩放",float(fields.zoom),func(value): workspace.set_property("zoom",value),0.01,0.1,10)
		LevelUI.number(self,"震动强度",float(fields.shake),func(value): workspace.set_property("shake",value),1,0,200)
	var library: LevelAssetLibrary = workspace.assets()
	if library.entries.has(object_data.asset):
		for parameter: String in library.entries[object_data.asset].exposed_parameters:
			var spec: Dictionary = library.entries[object_data.asset].exposed_parameters[parameter]
			var value: Variant = fields.get(parameter,spec.get("default",0.0))
			if value is bool: LevelUI.toggle(self,parameter,value,func(next): workspace.set_property(parameter,next))
			elif value is float or value is int: LevelUI.number(self,parameter,float(value),func(next): workspace.set_property(parameter,next),float(spec.get("step",0.01)),float(spec.get("min",-10000)),float(spec.get("max",10000)))
			elif value is Array:LevelUI.vector(self,parameter,LevelFormat.vec(value),func(next):workspace.set_property(parameter,next),0.01)
			elif spec.get("type","")=="color":LevelUI.color(self,parameter,str(value),func(next):workspace.set_property(parameter,next))
			else:LevelUI.text_field(self,parameter,str(value),func(next):workspace.set_property(parameter,next))
	var key_row := HFlowContainer.new(); add_child(key_row)
	for property: String in ["position","rotation","scale","opacity","visible"]:
		LevelUI.button(key_row,"◆ " + str(LevelFormat.PROPERTIES[property]),func(): workspace.key_property(property))
	var properties:Array=[""];var captions:Array=["选择要插入的属性…"]
	for property:String in fields:properties.append(property);captions.append(str(LevelFormat.PROPERTIES.get(property,property)))
	if library.entries.has(object_data.asset):
		for parameter:String in library.entries[object_data.asset].exposed_parameters:
			if not parameter in properties:properties.append(parameter);captions.append(parameter)
	LevelUI.choice(self,"手动关键帧",properties,"",func(property):
		if not str(property).is_empty():workspace.key_property(property),captions)
	var actions := HFlowContainer.new(); add_child(actions)
	LevelUI.button(actions,"添加动作",func(): workspace.add_clip("action"))
	LevelUI.button(actions,"显示区间",func(): workspace.add_clip("visibility"))
	LevelUI.button(actions,"添加音频",func(): workspace.add_clip("audio"))
	if object_data.type == "actor":
		LevelUI.button(actions,"绑定 BOSS 音符",workspace.open_boss_binding)
		LevelUI.button(actions,"检查命中反馈",func():workspace.test_feedback(true))
		LevelUI.button(actions,"检查失误反馈",func():workspace.test_feedback(false))
	if not track.is_empty():
		LevelUI.label(self,"轨道设置",16)
		LevelUI.toggle(self,"静音／禁用轨道",track.muted,func(value): workspace.set_track_field(track.id,"muted",value))
		LevelUI.toggle(self,"锁定轨道",track.locked,func(value): workspace.set_track_field(track.id,"locked",value))
		LevelUI.choice(self,"作用范围",["common","difficulty"],"common" if track.difficulties.is_empty() else "difficulty",func(value): workspace.set_track_field(track.id,"difficulties",[] if value == "common" else [workspace.difficulty()]),["所有难度","当前难度"])

	_mark_mixed()

func _key(track: Dictionary,key: Dictionary) -> void:
	LevelUI.label(self,"关键帧 · " + str(LevelFormat.PROPERTIES.get(track.property,track.property)),18)
	LevelUI.number(self,"时间（秒）",float(key.time_us)/1000000,func(value): workspace.set_item_field(track.id,key.id,"time_us",roundi(value*1000000)),0.001)
	var update := func(value): workspace.set_item_field(track.id,key.id,"value",value)
	if key.value is Array: LevelUI.vector(self,"值",LevelFormat.vec(key.value),update,0.1)
	elif key.value is bool: LevelUI.toggle(self,"值",key.value,update)
	elif key.value is float or key.value is int: LevelUI.number(self,"值",float(key.value),update,0.01)
	elif track.property == "color": LevelUI.color(self,"值",str(key.value),update)
	else: LevelUI.text_field(self,"值",str(key.value),update)
	LevelUI.choice(self,"插值",["hold","linear","ease","bezier"],str(key.interpolation),func(value): workspace.set_item_field(track.id,key.id,"interpolation",value),["保持","线性","缓入缓出","贝塞尔"])
	var curve := LevelCurveEditor.new(); curve.first = LevelFormat.vec(key.out_handle); curve.second = LevelFormat.vec(key.in_handle); add_child(curve)
	curve.candidate_changed.connect(func(first,second): workspace.document.begin_edit();workspace.set_key_curve(track.id,key.id,first,second))
	curve.committed.connect(func(_first,_second): workspace.document.end_edit())
	curve.canceled.connect(func():workspace.document.end_edit(true))
	LevelUI.vector(self,"出手柄",LevelFormat.vec(key.out_handle),func(value):
		workspace.set_item_field(track.id,key.id,"out_handle",[clampf(value[0],0,1),value[1]]),0.01)
	LevelUI.vector(self,"入手柄",LevelFormat.vec(key.in_handle),func(value):
		workspace.set_item_field(track.id,key.id,"in_handle",[clampf(value[0],0,1),value[1]]),0.01)
	LevelUI.label(self,"拖动青色手柄调整到下一关键帧的过渡。",11)
	LevelUI.button(self,"删除关键帧",workspace.timeline.delete_selected)

func _clip(track: Dictionary,clip: Dictionary) -> void:
	LevelUI.label(self,"片段属性",18)
	var change := func(key,value): workspace.set_item_field(track.id,clip.id,key,value)
	LevelUI.text_field(self,"名称",str(clip.name),func(value): change.call("name",value))
	for pair in [["开始（秒）","start_us"],["长度（秒）","duration_us"],["素材偏移","offset_us"],["淡入（秒）","fade_in_us"],["淡出（秒）","fade_out_us"]]:
		LevelUI.number(self,pair[0],float(clip.get(pair[1],0))/1000000,func(value): change.call(pair[1],roundi(value*1000000)),0.01,-10000 if pair[1] == "start_us" else (0.001 if pair[1] == "duration_us" else 0),100000)
	LevelUI.number(self,"播放速率",float(clip.rate),func(value): change.call("rate",value),0.05,0.05,8)
	LevelUI.toggle(self,"循环素材",bool(clip.loop),func(value): change.call("loop",value))
	LevelUI.toggle(self,"结束保持末态",bool(clip.hold_last),func(value): change.call("hold_last",value))
	if track.type == "action":
		var object_data: Dictionary = workspace.document.find("objects",track.object_id)
		var actions: PackedStringArray = workspace.assets().actions(object_data.asset)
		if not actions.is_empty(): LevelUI.choice(self,"素材动作",Array(actions),str(clip.action),func(value): change.call("action",value))
		LevelUI.text_field(self,"动作／状态",str(clip.action),func(value): change.call("action",value))
	elif track.type == "audio":
		LevelUI.toggle(self,"瞬时音效（定位不补播）",bool(clip.get("transient",false)),func(value):change.call("transient",value))
		workspace.resource_field(self,"音频素材",str(clip.asset),"audio",func(value): change.call("asset",value))
		LevelUI.number(self,"增益 dB",float(clip.gain_db),func(value): change.call("gain_db",value),0.5,-80,12)
		LevelUI.button(self,"独立试听此片段",func(): workspace.audition_clip(clip))
	elif track.type == "sequence": LevelUI.text_field(self,"片段模板",str(clip.asset),func(value): change.call("asset",value))
	LevelUI.button(self,"在游标处拆分",workspace.timeline.split_selected)
	LevelUI.button(self,"删除片段",workspace.timeline.delete_selected)

func _level() -> void:
	var level: Dictionary = workspace.document.data
	LevelUI.label(self,"关卡设置",18)
	LevelUI.text_field(self,"关卡 ID",str(level.level_id),func(value):workspace.document.fields("关卡标识",{"level_id":value}))
	for pair in [["标题","title"],["作者","author"],["说明","description"],["封面素材","cover"],["下一关 ID","next_stage_id"]]:
		LevelUI.text_field(self,pair[0],str(level.get(pair[1],"")),func(value): workspace.document.fields("修改关卡设置",{pair[1]:value}))
	LevelUI.number(self,"目录顺序",float(level.order_index),func(value): workspace.document.fields("目录顺序",{"order_index":roundi(value)}))
	for pair in [["片头（秒）","intro_us"],["片尾（秒）","outro_us"]]:
		LevelUI.number(self,pair[0],float(level.get(pair[1],0))/1000000,func(value): workspace.document.fields("区段长度",{pair[1]:roundi(value*1000000)}),0.1,0,600)
	LevelUI.toggle(self,"默认解锁",bool(level.get("unlocked_by_default",true)),func(value): workspace.document.fields("默认解锁",{"unlocked_by_default":value}))
	var rule_paths:=["res://content/rules/default_gameplay_rules.tres"];var rule_names:=["默认玩法规则"]
	for stage:StageDefinition in ChartSceneLibrary.shared().all_stages():
		if stage.rule_set!=null and not stage.rule_set.resource_path.is_empty() and not stage.rule_set.resource_path in rule_paths:
			rule_paths.append(stage.rule_set.resource_path);rule_names.append(stage.display_name+" · 规则")
	LevelUI.choice(self,"规则预设",rule_paths,str(level.rule_path),func(value):workspace.document.fields("规则预设",{"rule_path":value}),rule_names)
	var pet_paths:=[""];var pet_names:=["无随从奖励"]
	for pet:PetDefinition in ContentCatalog.data.pets:pet_paths.append(pet.resource_path);pet_names.append(pet.display_name)
	LevelUI.choice(self,"随从奖励",pet_paths,str(level.get("pet_path","")),func(value):workspace.document.fields("随从奖励",{"pet_path":value}),pet_names)
	LevelUI.toggle(self,"FC 获得普通形态",bool(level.fc_grants_base_pet),func(value): workspace.document.fields("FC 奖励",{"fc_grants_base_pet":value}))
	LevelUI.toggle(self,"AP 获得进阶形态",bool(level.ap_grants_advanced_pet),func(value): workspace.document.fields("AP 奖励",{"ap_grants_advanced_pet":value}))
	LevelUI.button(self,"刷新关联谱面",workspace.refresh_song)
	LevelUI.button(self,"检查素材与绑定",workspace.refresh_problems)

func edit_document() -> LevelDocument: return workspace.document

func _mark_mixed() -> void:
	if workspace.selection.size()<2: return
	var names := {"名称":"name","素材":"asset","坐标层":"layer","层级":"depth","位置":"position","旋转 °":"rotation","大小":"scale","透明度":"opacity","颜色":"color","显示":"visible","文字":"text","字体":"font","字号":"font_size","区域尺寸":"size","对齐":"alignment","打字进度":"visible_ratio","音量 dB":"volume_db","镜头缩放":"zoom","震动强度":"shake"}
	for row in get_children():
		if not row is HBoxContainer or row.get_child_count()<2 or not row.get_child(0) is Label: continue
		var caption: String=row.get_child(0).text
		if not names.has(caption): continue
		var property: String=names[caption]; var values := []
		for id in workspace.selection:
			var object_data: Dictionary=workspace.document.find("objects",id)
			var fields: Dictionary=LevelShowSampler.object_state(workspace.document.data.show,object_data,workspace.section,workspace.time_us,workspace.difficulty()) if workspace.auto_key else object_data.fields
			values.append(object_data.get(property,fields.get(property)))
		if values.all(func(value):return value==values[0]): continue
		row.get_child(0).text=caption+" · 多个值"
		for control in row.get_children():
			if control is SpinBox: control.get_line_edit().text=""; control.get_line_edit().placeholder_text="多个值"
			elif control is LineEdit: control.text="";control.placeholder_text="多个值";control.set_meta("mixed_value",true)
			elif control is OptionButton: control.select(-1);control.text="多个值"

func _many_items() -> void:
	LevelUI.label(self,"时间线多选 · %d 项"%workspace.selected_items.size(),18)
	LevelUI.label(self,"相对时间保持不变；一次批量修改对应一次撤销。",12)
	var before: Array=workspace.timeline._selected_tracks()
	LevelUI.number(self,"整体平移 秒",0,func(value):
		var old := []; var after := before.duplicate(true)
		for track: Dictionary in after:
			old.append(workspace.document.find("tracks",track.id).duplicate(true))
			for item: Dictionary in track.keys+track.clips:
				if item.id in workspace.selected_items:
					var field := "time_us" if item.has("time_us") else "start_us"
					item[field]+=roundi(value*1000000)
		workspace.document.replace("批量平移选区","tracks",old,after),0.001)
	if not before.is_empty() and before.all(func(track):return track.type=="property" and track.property==before[0].property):
		var values := []
		for track: Dictionary in before:
			for key: Dictionary in track.keys:
				if key.id in workspace.selected_items: values.append(key.value)
		if not values.is_empty():
			var update := func(value): _batch_values(value)
			var mixed: bool=not values.all(func(value):return value==values[0])
			LevelUI.label(self,"多个值" if mixed else "共同值",12)
			if values[0] is Array: LevelUI.vector(self,"值",LevelFormat.vec(values[0]),update,0.01)
			elif values[0] is float or values[0] is int: LevelUI.number(self,"值",float(values[0]),update,0.01)
			elif values[0] is bool: LevelUI.toggle(self,"值",values[0],update)
			elif before[0].property=="color":LevelUI.color(self,"值",str(values[0]),update)
			LevelUI.choice(self,"插值",["hold","linear","ease","bezier"],"linear",func(value):_batch_values(value,"interpolation"),["保持","线性","缓入缓出","贝塞尔"])
	LevelUI.button(self,"删除选中事件",workspace.timeline.delete_selected)

func _batch_values(value: Variant, field := "value") -> void:
	var before: Array=workspace.timeline._selected_tracks(); var after:=before.duplicate(true)
	for track: Dictionary in after:
		for key: Dictionary in track.keys:
			if key.id in workspace.selected_items: key[field]=value
	workspace.document.replace("修改多选关键帧","tracks",before,after)
