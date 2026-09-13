class_name LevelTransformEdit
extends RefCounted
## 画布与字段共同生成候选；预览、松手和批量对齐使用完全相同的变更。
const PROPERTIES := ["position","rotation","scale"]

static func build(document: LevelDocument, before: Array, after: Array, section: String, time_us: int, difficulty: String, auto_key: bool, new_difficulty: bool, selected_keys: PackedStringArray=PackedStringArray()) -> Dictionary:
	var show: Dictionary=document.data.show.duplicate(true)
	var selected: Array=before.map(func(item):return item.id)
	for index in after.size():
		var source: Dictionary=before[index]
		var target: Dictionary=after[index]
		var parent: String=str(source.parent_id)
		var nested:=false
		while not parent.is_empty():
			if parent in selected:nested=true;break
			parent=str(document.find("objects",parent).get("parent_id",""))
		if nested:continue
		if not document.editable_object(source.id):return {"error":"对象或父组已锁定／隐藏，未提交变换。"}
		for property: String in PROPERTIES:
			var old: Variant=source.fields[property];var value: Variant=target.fields[property]
			if old==value:continue
			var tracks: Array=show.tracks.filter(func(track):return track.type=="property" and track.object_id==source.id and track.property==property and track.section==section and LevelFormat.visible_in(track,difficulty))
			if not selected_keys.is_empty():tracks=tracks.filter(func(track):return track.keys.any(func(key):return key.id in selected_keys))
			if tracks.any(func(track):return track.get("locked",false) or track.get("generated",false)):
				return {"error":"对应动画轨道只读或已锁定，未提交变换。"}
			if not selected_keys.is_empty():
				for track: Dictionary in tracks:
					for key: Dictionary in track.keys:
						if key.id in selected_keys:key.value=adjust(key.value,old,value,property)
				continue
			if auto_key:
				var track: Dictionary
				if tracks.is_empty():
					track=LevelFormat.track(source.id,property,section);track.difficulties=[difficulty] if new_difficulty and not difficulty.is_empty() else [];show.tracks.append(track)
				else:track=tracks.back()
				var found:=false
				for key: Dictionary in track.keys:
					if int(key.time_us)==time_us:key.value=value;found=true;break
				if not found:track.keys.append(LevelFormat.key(time_us,value))
			elif tracks.any(func(track):return not track.keys.is_empty()):
				for track: Dictionary in tracks:
					if track.keys.is_empty():continue
					# 单区段起点补键，不改全局基础值，其他区段保持原样。
					if int(track.keys[0].time_us)>0:
						var prefix: Dictionary=document.data.show.duplicate(true)
						prefix.tracks=prefix.tracks.slice(0,document.entries("tracks").find(document.find("tracks",track.id))+1)
						var base: Variant=LevelShowSampler.object_state(prefix,document.find("objects",source.id),section,0,difficulty)[property]
						track.keys.push_front(LevelFormat.key(0,base))
					for key: Dictionary in track.keys:key.value=adjust(key.value,old,value,property)
			else:
				LevelFormat.find(show.objects,source.id).fields[property]=value
	for track: Dictionary in show.tracks:track.keys.sort_custom(func(a,b):return int(a.time_us)<int(b.time_us))
	var changes:=[]
	for kind: String in ["objects","tracks"]:
		var previous:=[];var next:=[]
		for entry: Dictionary in show[kind]:
			var original:=document.find(kind,entry.id)
			if original==entry:continue
			if not original.is_empty():previous.append(original.duplicate(true))
			next.append(entry)
		if not next.is_empty():changes.append({"kind":kind,"before":previous,"after":next})
	return {"error":"","show":show,"changes":changes}

static func adjust(value: Variant, old: Variant, next: Variant, property: String) -> Variant:
	if value is Array:
		var result: Array=value.duplicate()
		for axis in result.size():
			result[axis]=float(value[axis])*float(next[axis])/float(old[axis]) if property=="scale" and not is_zero_approx(float(old[axis])) else float(value[axis])+float(next[axis])-float(old[axis])
		return result
	return float(value)+float(next)-float(old)
