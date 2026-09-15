class_name LevelInspector
extends VBoxContainer
## 面板只调用文档命令；参数值、轨道值和关键帧各自明确显示。
var workspace
var _form_identity:=""
var _transform_label: Label
var _occlusion_label: Label

func refresh() -> void:
	var identity:=""
	if workspace!=null and workspace.inspector_mode=="properties" and workspace.selected_track.is_empty() and not workspace.selection.is_empty():
		identity=JSON.stringify(Array(workspace.selection).map(func(id):
			var entry: Dictionary=workspace.document.find("objects",id)
			return [entry.get("type"),entry.get("asset"),entry.get("fields",{}).keys()]))
	if not identity.is_empty() and identity==_form_identity:
		sync_fields();return
	_form_identity=identity
	LevelUI.clear(self)
	if workspace == null: return
	if workspace.inspector_mode=="level": _level();return
	if workspace.selected_track=="@environment":
		LevelEnvironmentPanel.build(self,workspace);return
	var doc: LevelDocument = workspace.document
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

	_transform_label=LevelUI.label(self,workspace.transform_caption(),12)
	if workspace.selection.size()>1: LevelUI.label(self,"已选 %d 个对象；共同属性批量修改"%workspace.selection.size(),12)
	var fields: Dictionary = object_data.fields.duplicate(true)
	var sampled:=LevelShowSampler.object_state(doc.data.show,object_data,workspace.section,workspace.time_us,workspace.difficulty())
	if workspace.auto_key:fields=sampled
	else:
		for property: String in LevelTransformEdit.PROPERTIES:fields[property]=sampled[property]
	if object_data.type == "text" and _all_type("text"):
		LevelUI.text_field(self,"文字",str(fields.text),func(value): workspace.set_property("text",value))
		workspace.resource_field(self,"字体",str(fields.font),"font",func(value): workspace.set_property("font",value))
		LevelUI.number(self,"字号",float(fields.font_size),func(value): workspace.set_property("font_size",roundi(value)),1,8,400)
		LevelUI.vector(self,"区域尺寸",LevelFormat.vec(fields.size),func(value): workspace.set_property("size",value),1,func(axis,value):workspace.set_property_component("size",axis,value))
		LevelUI.choice(self,"对齐",[0,1,2],int(fields.alignment),func(value): workspace.set_property("alignment",value),["左","中","右"])
		LevelUI.number(self,"打字进度",float(fields.visible_ratio),func(value): workspace.set_property("visible_ratio",value),0.01,0,1)
	if object_data.type == "audio" and _all_type("audio"): LevelUI.number(self,"音量 dB",float(fields.volume_db),func(value): workspace.set_property("volume_db",value),0.5,-80,12)
	if object_data.type == "camera" and _all_type("camera"):
		LevelUI.number(self,"镜头缩放",float(fields.zoom),func(value): workspace.set_property("zoom",value),0.01,0.1,10)
		LevelUI.number(self,"震动强度",float(fields.shake),func(value): workspace.set_property("shake",value),1,0,200)
	LevelUI.vector(self,"位置",LevelFormat.vec(fields.position),func(value): workspace.set_property("position",value),1,func(axis,value):workspace.set_property_component("position",axis,value))
	LevelUI.number(self,"旋转 °",float(fields.rotation),func(value): workspace.set_property("rotation",value),0.5)
	LevelUI.vector(self,"大小",LevelFormat.vec(fields.scale),func(value): workspace.set_property("scale",value),0.01,func(axis,value):workspace.set_property_component("scale",axis,value))
	LevelUI.number(self,"透明度",float(fields.opacity),func(value): workspace.set_property("opacity",value),0.01,0,1)
	LevelUI.color(self,"颜色",str(fields.color),func(value): workspace.set_property("color",value))
	LevelUI.toggle(self,"显示",bool(fields.visible),func(value): workspace.set_property("visible",value))
	LevelUI.label(self,"素材与显示",16)
	if Array(workspace.selection).all(func(id):return workspace.object_asset_category(doc.find("objects",id))==workspace.object_asset_category(object_data)):
		workspace.resource_field(self,"素材",object_data.asset,workspace.object_asset_category(object_data),workspace.set_object_asset)
	else:LevelUI.label(self,"所选对象的素材类型不同，请按类型选择后替换。",12)
	var asset_actions:=HFlowContainer.new();add_child(asset_actions)
	var clear_button:=LevelUI.button(asset_actions,"清除引用",workspace.clear_object_asset_reference,"保留对象与演出，移除素材引用")
	clear_button.disabled=Array(workspace.selection).all(func(id):return str(doc.find("objects",id).asset).is_empty())
	LevelUI.button(asset_actions,"删除对象",workspace.delete_objects)
	LevelUI.choice(self,"坐标层",["world","life","death","hud"],object_data.layer,func(value): workspace.set_object_field("layer",value),["世界","生界","死界（中心对称）","屏幕 HUD"])
	LevelUI.number(self,"对象排序／视差",float(object_data.depth),func(value): workspace.set_object_field("depth",value),1,-999,999)
	LevelUI.label(self,"背景遮挡",16)
	var choices: Dictionary=workspace.background_layer_choices()
	var current_depth:=int(object_data.get("occlusion_depth",0))
	if not choices.has(current_depth):choices[current_depth]="深度 %d（当前环境无此层）"%current_depth
	var depths: Array=choices.keys();depths.sort();var layer_captions:=[]
	for depth in depths:layer_captions.append(choices[depth])
	LevelUI.choice(self,"背景层",depths,int(object_data.get("occlusion_depth",0)),func(value):workspace.set_object_field("occlusion_depth",value),layer_captions)
	var mode: String="inherit" if object_data.get("occlusion_inherit",object_data.get("occlusion_order","none")=="none") else str(object_data.get("occlusion_order","none"))
	LevelUI.choice(self,"前后位置",["inherit","none","front","back"],mode,workspace.set_occlusion_mode,["沿用父组","不参与","背景前","背景后"])
	_occlusion_label=LevelUI.label(self,_occlusion_caption(),12)
	LevelUI.toggle(self,"锁定对象",object_data.locked,func(value): workspace.set_object_field("locked",value))
	LevelUI.toggle(self,"隐藏对象",object_data.hidden,func(value): workspace.set_object_field("hidden",value))
	if not str(object_data.asset).is_empty() and _same_asset():
		LevelUI.button(self,"定位使用此素材的对象",func():workspace.select_asset_users(object_data.asset))
		if workspace.assets().kind(object_data.asset)=="animation":
			var names: PackedStringArray=workspace.assets().actions(object_data.asset)
			LevelUI.choice(self,"默认动作",Array(names),str(object_data.get("animation",workspace.assets().default_animation(object_data.asset))),func(value):workspace.set_object_field("animation",value))
			LevelUI.button(self,"重新导入此动画",func():workspace.import_animation(object_data.asset))
	var bases:=VBoxContainer.new();bases.set_meta("base_fields",true);add_child(bases);bases.hide()
	var base_toggle:=LevelUI.button(self,"高级：直接编辑全局基础值",func():
		bases.visible=not bases.visible
		if bases.visible and bases.get_child_count()==0:_build_bases(bases))
	move_child(base_toggle,bases.get_index())

	var library: LevelAssetLibrary = workspace.assets()
	if _same_asset() and library.entries.has(object_data.asset):
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
	for property:String in fields:
		if Array(workspace.selection).all(func(id):return doc.find("objects",id).fields.has(property)):properties.append(property);captions.append(str(LevelFormat.PROPERTIES.get(property,property)))
	if _same_asset() and library.entries.has(object_data.asset):
		for parameter:String in library.entries[object_data.asset].exposed_parameters:
			if not parameter in properties:properties.append(parameter);captions.append(parameter)
	LevelUI.choice(self,"手动关键帧",properties,"",func(property):
		if not str(property).is_empty():workspace.key_property(property),captions)
	var actions := HFlowContainer.new(); add_child(actions)
	LevelUI.button(actions,"添加动作",func(): workspace.add_clip("action"))
	LevelUI.button(actions,"显示区间",func(): workspace.add_clip("visibility"))
	LevelUI.button(actions,"添加音频",func(): workspace.add_clip("audio"))
	if object_data.type == "actor" and _all_type("actor"):
		LevelUI.button(actions,"绑定 BOSS 音符",workspace.open_boss_binding)
		LevelUI.button(actions,"检查命中反馈",func():workspace.test_feedback(true))
		LevelUI.button(actions,"检查失误反馈",func():workspace.test_feedback(false))
	if not track.is_empty():
		LevelUI.label(self,"轨道设置",16)
		LevelUI.toggle(self,"静音／禁用轨道",track.muted,func(value): workspace.set_track_field(track.id,"muted",value))
		LevelUI.toggle(self,"锁定轨道",track.locked,func(value): workspace.set_track_field(track.id,"locked",value))
		LevelUI.choice(self,"作用范围",["common","difficulty"],"common" if track.difficulties.is_empty() else "difficulty",func(value): workspace.set_track_field(track.id,"difficulties",[] if value == "common" else [workspace.difficulty()]),["所有难度","当前难度"])

	_mark_mixed()
	sync_fields()

func _key(track: Dictionary,key: Dictionary) -> void:
	LevelUI.label(self,"关键帧 · " + str(LevelFormat.PROPERTIES.get(track.property,track.property)),18)
	LevelUI.number(self,"时间（秒）",float(key.time_us)/1000000,func(value): workspace.set_item_field(track.id,key.id,"time_us",roundi(value*1000000)),0.001)
	var update := func(value): workspace.set_item_field(track.id,key.id,"value",value)
	if key.value is Array: LevelUI.vector(self,"值",LevelFormat.vec(key.value),update,0.1,func(axis,value):workspace.set_item_component(track.id,key.id,"value",axis,value))
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
		workspace.set_item_field(track.id,key.id,"out_handle",[clampf(value[0],0,1),value[1]]),0.01,func(axis,value):workspace.set_item_component(track.id,key.id,"out_handle",axis,value))
	LevelUI.vector(self,"入手柄",LevelFormat.vec(key.in_handle),func(value):
		workspace.set_item_field(track.id,key.id,"in_handle",[clampf(value[0],0,1),value[1]]),0.01,func(axis,value):workspace.set_item_component(track.id,key.id,"in_handle",axis,value))
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
		LevelUI.button(self,"独立试听此片段",func(): workspace.audition_clip(LevelFormat.find(workspace.document.find("tracks",track.id).clips,clip.id)))
	elif track.type == "sequence": LevelUI.text_field(self,"片段模板",str(clip.asset),func(value): change.call("asset",value))
	LevelUI.button(self,"在游标处拆分",workspace.timeline.split_selected)
	LevelUI.button(self,"删除片段",workspace.timeline.delete_selected)

func _level() -> void:
	var level: Dictionary = workspace.document.data
	LevelUI.label(self,"关卡设置",18)
	var scene_ids:=[];var scene_names:=[]
	for stage in ChartSceneLibrary.shared().all_stages():scene_ids.append(stage.stage_id);scene_names.append(stage.display_name)
	LevelUI.choice(self,"基础主题",scene_ids,str(level.scene_id),func(value):workspace.document.fields("切换基础主题",{"scene_id":value}),scene_names)
	LevelEnvironmentPanel.initial_controls(self,workspace)
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
	var names := {"名称":"name","素材":"asset","坐标层":"layer","对象排序／视差":"depth","背景层":"occlusion_depth","前后位置":"occlusion_order","位置":"position","旋转 °":"rotation","大小":"scale","透明度":"opacity","颜色":"color","显示":"visible","文字":"text","字体":"font","字号":"font_size","区域尺寸":"size","对齐":"alignment","打字进度":"visible_ratio","音量 dB":"volume_db","镜头缩放":"zoom","震动强度":"shake","锁定对象":"locked","隐藏对象":"hidden","默认动作":"animation"}
	for row in get_children():
		if not row is HBoxContainer or row.get_child_count()<2 or not row.get_child(0) is Label: continue
		var caption: String=row.get_child(0).text
		if not names.has(caption): continue
		var property: String=names[caption]; var values := []
		for id in workspace.selection:
			var object_data: Dictionary=workspace.document.find("objects",id)
			var fields: Dictionary=LevelShowSampler.object_state(workspace.document.data.show,object_data,workspace.section,workspace.time_us,workspace.difficulty())
			if property=="occlusion_order":values.append("inherit" if object_data.get("occlusion_inherit",object_data.get("occlusion_order","none")=="none") else object_data.get("occlusion_order","none"))
			elif property in LevelTransformEdit.PROPERTIES or workspace.auto_key:values.append(object_data.get(property,fields.get(property)))
			else:values.append(object_data.get(property,object_data.fields.get(property)))
		if values.all(func(value):return value==values[0]): continue
		row.get_child(0).text=caption+" · 多个值"
		for control in row.get_children():
			if control is SpinBox:
				var axis:=row.get_children().filter(func(c):return c is SpinBox).find(control)
				if values[0] is Array and values.all(func(v):return v is Array and v[axis]==values[0][axis]):continue
				control.get_line_edit().text=""; control.get_line_edit().placeholder_text="多个值"
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
			if values[0] is Array: LevelUI.vector(self,"值",LevelFormat.vec(values[0]),update,0.01,func(axis,value):_batch_values(value,"value",axis))
			elif values[0] is float or values[0] is int: LevelUI.number(self,"值",float(values[0]),update,0.01)
			elif values[0] is bool: LevelUI.toggle(self,"值",values[0],update)
			elif before[0].property=="color":LevelUI.color(self,"值",str(values[0]),update)
			LevelUI.choice(self,"插值",["hold","linear","ease","bezier"],"linear",func(value):_batch_values(value,"interpolation"),["保持","线性","缓入缓出","贝塞尔"])
	LevelUI.button(self,"删除选中事件",workspace.timeline.delete_selected)

func _batch_values(value: Variant, field := "value", axis := -1) -> void:
	var before: Array=workspace.timeline._selected_tracks(); var after:=before.duplicate(true)
	for track: Dictionary in after:
		for key: Dictionary in track.keys:
			if key.id in workspace.selected_items:
				if axis>=0:key[field][axis]=value
				else:key[field]=value
	workspace.document.replace("修改多选关键帧","tracks",before,after)

func sync_fields() -> void:
	if workspace==null:return
	LevelEnvironmentPanel.update_initial(self,workspace)
	if workspace.inspector_mode=="level":_sync_level_fields();return
	if workspace.inspector_mode!="properties" or workspace.selected_track=="@environment":return
	var doc: LevelDocument=workspace.document
	if not workspace.selection.is_empty():
		if is_instance_valid(_transform_label):_transform_label.text=workspace.transform_caption()
		if is_instance_valid(_occlusion_label):
			_occlusion_label.text=_occlusion_caption()
	var track:=doc.find("tracks",workspace.selected_track)
	var item:=LevelFormat.find(track.get("keys",[])+track.get("clips",[]),workspace.selected_item)
	var names:={"名称":"name","位置":"position","旋转 °":"rotation","大小":"scale","透明度":"opacity","颜色":"color","显示":"visible","对象排序／视差":"depth","文字":"text","字号":"font_size","区域尺寸":"size","打字进度":"visible_ratio","音量 dB":"volume_db","镜头缩放":"zoom","震动强度":"shake","素材":"asset","字体":"font","坐标层":"layer","背景层":"occlusion_depth","锁定对象":"locked","隐藏对象":"hidden","默认动作":"animation","对齐":"alignment","前后位置":"occlusion_mode"}
	for row in get_children():
		if row.has_meta("base_fields"):
			for base_row in row.get_children():
				var property: String={"基础位置":"position","基础大小":"scale","基础旋转":"rotation"}.get(str(base_row.get_meta("caption","")),"")
				if not property.is_empty():LevelUI.sync_row(base_row,Array(workspace.selection).map(func(id):return doc.find("objects",id).fields[property]))
		if row is LevelCurveEditor and not item.is_empty() and item.has("out_handle") and row._drag<0:
			row.first=LevelFormat.vec(item.out_handle);row.second=LevelFormat.vec(item.in_handle);row.queue_redraw();continue
		if not row is Control:continue
		var caption: String=row.get_meta("caption","")
		var values:=[]
		if not item.is_empty():
			var item_fields:={"值":"value","出手柄":"out_handle","入手柄":"in_handle","播放速率":"rate","名称":"name","时间（秒）":"time_us","开始（秒）":"start_us","长度（秒）":"duration_us","素材偏移":"offset_us","淡入（秒）":"fade_in_us","淡出（秒）":"fade_out_us","循环素材":"loop","结束保持末态":"hold_last","瞬时音效（定位不补播）":"transient","增益 dB":"gain_db","音频素材":"asset","素材动作":"action","动作／状态":"action","插值":"interpolation"}
			if item_fields.has(caption) and item.has(item_fields[caption]):
				var field: String=item_fields[caption];values=[float(item[field])/1000000 if field.ends_with("_us") else item[field]]
		elif names.has(caption):
			var property: String=names[caption]
			for id in workspace.selection:
				var object_data:=doc.find("objects",id)
				if object_data.is_empty():continue
				var fields: Dictionary=LevelShowSampler.object_state(doc.data.show,object_data,workspace.section,workspace.time_us,workspace.difficulty()) if workspace.auto_key or property in LevelTransformEdit.PROPERTIES else object_data.fields
				if property=="occlusion_mode":values.append("inherit" if object_data.get("occlusion_inherit",object_data.get("occlusion_order","none")=="none") else object_data.get("occlusion_order","none"))
				else:values.append(object_data.get(property,fields.get(property)))
		if not values.is_empty() and values[0]!=null:LevelUI.sync_row(row,values)

func _all_type(type: String) -> bool:
	return Array(workspace.selection).all(func(id):return workspace.document.find("objects",id).get("type","")==type)

func _occlusion_caption() -> String:
	var relations:=Array(workspace.selection).map(func(id):return LevelShowPlayer.effective_occlusion(workspace.document.data.show,workspace.document.find("objects",id)))
	if relations.is_empty():return "当前生效：不参与背景遮挡"
	if relations.any(func(value):return value!=relations[0]):return "当前生效：多个位置"
	var relation: Array=relations[0]
	return "当前生效："+("不参与背景遮挡" if relation.is_empty() else "深度 %s · %s"%[relation[0],"背景前" if relation[1]=="front" else "背景后"])

func _same_asset() -> bool:
	if workspace.selection.is_empty():return false
	var first: String=workspace.document.find("objects",workspace.selection[0]).asset
	return Array(workspace.selection).all(func(id):return workspace.document.find("objects",id).asset==first)

func _build_bases(bases: VBoxContainer) -> void:
	var object_data: Dictionary=workspace.document.find("objects",workspace.selection[0])
	LevelUI.number(bases,"背景深度",object_data.get("occlusion_depth",0),func(value):workspace.set_object_field("occlusion_depth",int(value)),1,-999,999)
	LevelUI.label(bases,"基础值用于没有动画覆盖的时刻；修改会影响所有区段。",12)
	LevelUI.vector(bases,"基础位置",LevelFormat.vec(object_data.fields.position),func(value):workspace.set_base_property("position",value),1,func(axis,value):workspace.set_property_component("position",axis,value,true))
	LevelUI.number(bases,"基础旋转",float(object_data.fields.rotation),func(value):workspace.set_base_property("rotation",value),0.5)
	LevelUI.vector(bases,"基础大小",LevelFormat.vec(object_data.fields.scale),func(value):workspace.set_base_property("scale",value),0.01,func(axis,value):workspace.set_property_component("scale",axis,value,true))

func _sync_level_fields() -> void:
	var fields:={"基础主题":"scene_id","关卡 ID":"level_id","标题":"title","作者":"author","说明":"description","封面素材":"cover","下一关 ID":"next_stage_id","目录顺序":"order_index","片头（秒）":"intro_us","片尾（秒）":"outro_us","默认解锁":"unlocked_by_default","规则预设":"rule_path"}
	for row in get_children():
		var field: String=fields.get(str(row.get_meta("caption","")),"")
		if field.is_empty() or not workspace.document.data.has(field):continue
		var value: Variant=workspace.document.data[field]
		LevelUI.sync_row(row,[float(value)/1000000 if field.ends_with("_us") else value])
