extends "res://src/presentation/actors/boss_visual.gd"
## 正式演出适配：复用素材审看的可定位骨骼、揭眼与骨片实现。
var _event_signature := ""
var _attack_rate := 1.0

func _set_clip(name: String, at: float, duration: float=INF, mix: float=.08) -> void:
	super._set_clip(name,at,duration,mix)
	# 编排时间已经除过速率，骨骼仍须以相同倍率推进素材时间。
	skeleton.get_animation_state().get_track(0).set_time_scale(_attack_rate if name.begins_with("attack") else 1.0)

func _event(event: Dictionary) -> void:
	if mode=="death":return
	if mode=="phase_break" and event.kind in ["clip","start","end","hurt"]:return
	if event.kind=="clip":
		_attack_rate=float(event.rate)
		var at:=float(event.time)
		_set_clip(str(event.action),at,float(event.duration),0.0)
		skeleton.get_animation_state().get_track(0).set_time_scale(_attack_rate)
		if event.action=="attack_loop":loop_start=at;stop_pending=false
		return
	super._event(event)

func _transition(at: float) -> void:
	if _event_signature.is_empty():
		super._transition(at);return
	if mode=="phase_break":
		super._transition(at)
		# 揭眼不取消期间的发射；恢复此刻仍有效的自动动作及其局部时间。
		for event in events:
			if event.kind!="clip" or float(event.time)>at or float(event.time)+float(event.duration)<=at:continue
			_event(event)
			skeleton.get_animation_state().get_track(0).set_track_time((at-float(event.time))*float(event.rate))
			skeleton.update_skeleton(0.0)
		return
	# 每个自动片段有明确终点；下一片段由同一时间线接管。
	_set_clip("idle",at,INF,.10)

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
			timeline.append({"kind":"clip","action":clip.action,"rate":float(clip.get("rate",1.0)),"duration":float(clip.duration_us)/1000000,"time":float(int(clip.start_us)-offset_us)/1000000})
	if not battle.is_empty():
		for hit in battle.get("hits",[]):timeline.append({"kind":"hurt","time":float(hit)/1000000})
		if int(battle.phase_us) >= 0: timeline.append({"kind":"phase_break","time":float(battle.phase_us)/1000000})
		if int(battle.finish_us) >= 0 and battle.hp == 0: timeline.append({"kind":"death","time":float(battle.finish_us)/1000000})
	timeline.sort_custom(func(a,b):return a.time<b.time)
	# 审看状态机以零开始；提前蓄势统一平移，不截断曲前动作。
	var origin := minf(0.0, float(timeline[0].time)) if not timeline.is_empty() else 0.0
	for event in timeline: event.time -= origin
	var signature := JSON.stringify(timeline)
	if signature != _event_signature:
		# 新事件位于已采样游标之后时直接续算；只有改写历史才从起点恢复。
		var same_history:=timeline.size()>=cursor and events.slice(0,cursor)==timeline.slice(0,cursor)
		var future:=timeline.size()<=cursor or float(timeline[cursor].time)>=clock
		dirty=dirty or not same_history or not future
		events=timeline;_event_signature=signature
	sample(maxf(0.0,float(at_us)/1000000-origin))
