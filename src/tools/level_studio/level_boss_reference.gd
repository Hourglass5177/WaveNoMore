class_name LevelBossReference
extends RefCounted
## 总览与时间线共用只读记录；失效 ID 不猜测谱面时间。
const COLORS := {"未绑定": Color("ffbb55"), "已绑定": Color("68d6ae"), "失效关联": Color("ff6c78")}

static func collect(workspace) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if workspace.song_document.charts.is_empty():return result
	var tempo: TempoMap=workspace.song_document.tempo_map()
	var bindings: Array=workspace.document.entries("bindings").filter(func(item):return item.difficulty==workspace.difficulty())
	var known:={}
	for note in ChartEditEvents.all(workspace.song_document.chart()):
		if not (note is NoteEvent or note is GhostEvent) or not note.boss:continue
		known[note.event_id]=true
		var owners: Array=bindings.filter(func(item):return note.event_id in item.note_ids)
		var invalid: bool=owners.any(func(item):return workspace.document.find("objects",item.object_id).is_empty())
		result.append({"id":note.event_id,"time_us":tempo.tick_to_us(note.tick),"end_us":tempo.tick_to_us(note.tick+note.duration_ticks),"kind":"调频幽灵" if note is GhostEvent else ("Hold" if note.kind==GameplayTypes.NoteKind.HOLD else "Tap"),"side":"双侧" if note is GhostEvent else ("生" if note.affinity==GameplayTypes.Affinity.ZHU else "死"),"status":"失效关联" if invalid else ("未绑定" if owners.is_empty() else "已绑定"),"owners":owners})
	for binding: Dictionary in bindings:
		for id: String in binding.note_ids:
			if known.has(id):continue
			known[id]=true
			result.append({"id":id,"time_us":-1,"end_us":-1,"kind":"已删除或取消 BOSS 标记","side":"—","status":"失效关联","owners":bindings.filter(func(item):return id in item.note_ids)})
	result.sort_custom(func(a,b):return a.time_us<b.time_us if a.time_us>=0 and b.time_us>=0 else a.time_us>=0 and b.time_us<0)
	return result

static func describe(record: Dictionary, document: LevelDocument) -> String:
	var names: Array=record.owners.map(func(item):return str(document.find("objects",item.object_id).get("name","失效对象"))+" / "+str(item.action))
	var at:="无法定位：谱面已不存在对应 BOSS 音符" if record.time_us<0 else "%.3f 秒"%(float(record.time_us)/1000000)
	if record.end_us>record.time_us:at+=" → %.3f 秒"%(float(record.end_us)/1000000)
	return "%s · %s · %s · %s\n%s\n%s"%[at,record.side,record.kind,record.status,record.id,"未分配演出对象" if names.is_empty() else "、".join(names)]
