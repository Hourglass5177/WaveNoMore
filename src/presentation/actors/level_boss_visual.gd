extends "res://src/presentation/actors/boss_visual.gd"
## 正式演出适配：复用素材审看的可定位骨骼、揭眼与骨片实现。
var _event_signature := ""
func preview_role(role: String, seconds: float) -> void:
	events=[];dirty=true;_event_signature=""
	var offset:=0.0
	match role:
		"phase_break": events.append({"kind":"phase_break","time":0.0})
		"death":
			if initial_form=="goat":events.append({"kind":"phase_break","time":0.0});offset=3.0
			events.append({"kind":"death","time":offset})
		"hurt": events.append({"kind":"hurt","time":0.0})
		_: events.append({"kind":"start","time":0.0})
	sample(seconds+offset)

func emission_anchor(side: String) -> Vector2:
	var points: Array=mouths if not mouths.is_empty() else (eyes if not eyes.is_empty() else lights)
	if points.is_empty():return Vector2.ZERO
	return _point(points[mini(1,points.size()-1)] if side=="death" else points[0])

func sample_show(tracks: Array, object_id: String, battle: Dictionary, at_us: int, offset_us: int) -> void:
	var timeline: Array[Dictionary] = []
	for track: Dictionary in tracks:
		if track.object_id != object_id or not track.has("binding_id") or track.type != "action": continue
		for clip: Dictionary in track.clips:
			if clip.action == "attack_start": timeline.append({"kind":"start","time":float(int(clip.start_us)-offset_us)/1000000})
			elif clip.action == "attack_end": timeline.append({"kind":"end","time":float(int(clip.start_us)-offset_us)/1000000-0.000001})
	if not battle.is_empty():
		for hit in battle.get("hits",[]):timeline.append({"kind":"hurt","time":float(hit)/1000000})
		if int(battle.phase_us) >= 0: timeline.append({"kind":"phase_break","time":float(battle.phase_us)/1000000})
		if int(battle.finish_us) >= 0 and battle.hp == 0: timeline.append({"kind":"death","time":float(battle.finish_us)/1000000})
	timeline.sort_custom(func(a,b):return a.time<b.time)
	# 审看状态机以零开始；提前蓄势统一平移，不截断曲前动作。
	var origin := minf(0.0, float(timeline[0].time)) if not timeline.is_empty() else 0.0
	for event in timeline: event.time -= origin
	var signature := JSON.stringify(timeline)
	if signature != _event_signature: events=timeline;dirty=true;_event_signature=signature
	sample(maxf(0.0,float(at_us)/1000000-origin))
