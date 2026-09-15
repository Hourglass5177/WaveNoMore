class_name BossBattleEngine
extends RefCounted
## 只消费玩法事实；整数伤害与固定谱面边界保证回放不依赖渲染帧率。
const UNIT := 1000
var definitions: Array = []
var states := {}
var schedule: Array = []
var cursor := 0
var consumed := {}
var history: Array = []
var completed := {}
var coverage := {}
var perfect_events: Array = []
var preview_cursor := 0
var preview_time := -9223372036854775807
var preview_success := true
var contacts := {}

func configure(configs: Array, compiled: CompiledChart, rules: GameplayRuleSet) -> void:
	definitions = configs.duplicate(true); schedule.clear(); perfect_events.clear()
	for config: Dictionary in definitions:
		var total := 0
		var last := 0
		config.note_ends={}
		for note: Dictionary in compiled.notes:
			if str(note.id) not in config.note_ids: continue
			total += UNIT
			perfect_events.append({"object_id":config.id,"key":str(note.id)+":head","time_us":int(note.get("start_us",note.end_us)),"amount":UNIT})
			var death:=int(note.get("affinity",0))==GameplayTypes.Affinity.XUAN
			var bell: Vector2=rules.death_wave_origin if death else rules.life_wave_origin
			var cue: Vector2=rules.death_note_cue if death else rules.life_note_cue
			var spawn: Vector2=rules.death_note_spawn if death else rules.life_note_spawn
			var speed:=NoteApproachPath.length(NoteApproachPath.build_profile(spawn,cue,bell,rules.note_curve_outer_bend_px,rules.note_curve_center_handle_px))/rules.approach_duration_sec
			var fallback_end:=int(note.end_us)+roundi(cue.distance_to(bell)/maxf(speed,1)*1000000)+rules.hold_sustain_grace_ms*1000+1
			var ideal:=int(note.end_us) if note.unit_kind==&"hold" else int(note.end_us)+roundi(cue.distance_to(bell)/(rules.wave_speed_px_sec+speed)*1000000)
			config.note_ends[str(note.id)]={"kind":str(note.unit_kind),"fallback":fallback_end,"ideal":ideal}
			last = maxi(last,fallback_end)
			if note.unit_kind != &"hold": continue
			total += UNIT
			perfect_events.append({"object_id":config.id,"key":str(note.id)+":tail","time_us":int(note.end_us),"amount":UNIT})
			var tick := int(note.tick)
			while tick < int(note.end_tick):
				var end := mini(tick + compiled.ppq, int(note.end_tick))
				var amount := roundi(float(end-tick) / compiled.ppq * UNIT)
				schedule.append({"object_id":config.id,"note_id":str(note.id),"time_us":compiled.tempo_map.tick_to_us(end),"amount":amount,"kind":"sustain"})
				total += amount; tick = end
		for ghost: Dictionary in compiled.su_manifestations:
			if str(ghost.id) not in config.note_ids: continue
			var ids: Array = Array(ghost.get("tuning_ids", []))
			var end_tick := int(ghost.get("tick", 0))
			for slider: Dictionary in compiled.tuning_sliders:
				if slider.id in ids: end_tick = maxi(end_tick, int(slider.end_tick))
			var tick := int(ghost.get("tick", 0))
			while tick < end_tick:
				var end := mini(tick + compiled.ppq, end_tick)
				var amount := roundi(float(end-tick) / compiled.ppq * UNIT)
				var begin_us := compiled.tempo_map.tick_to_us(tick)
				var end_us := compiled.tempo_map.tick_to_us(end)
				# 每拍固定 48 个时间切片统计有效覆盖，不按渲染帧采样。
				for sample_index in range(1,49):
					var at := begin_us + (end_us-begin_us)*sample_index/48
					schedule.append({"object_id":config.id,"note_id":str(ghost.id),"time_us":at,"amount":amount,"kind":"tuning","slider_ids":ids,"segment":end_us,"last":sample_index==48})
				total += amount; tick = end
			last = maxi(last, compiled.tempo_map.tick_to_us(end_tick) + rules.miss_window_ms*1000+1)
		config.maximum = maxi(1, roundi(total * float(config.get("health_ratio", 0.8)))) if total > 0 else 0
		config.last_us = last
	schedule.sort_custom(func(a,b): return a.time_us < b.time_us)
	for item: Dictionary in schedule:
		if item.kind == "tuning" and not item.last: continue
		perfect_events.append({"object_id":item.object_id,"key":"%s:%s:%d" % [item.note_id,item.kind,item.time_us],"time_us":item.time_us,"amount":item.amount})
	perfect_events.sort_custom(func(a,b):return a.time_us<b.time_us)
	reset()

func reset() -> void:
	states.clear(); consumed.clear(); completed.clear(); history.clear(); coverage.clear(); cursor = 0
	contacts.clear()
	preview_cursor=0;preview_time=-9223372036854775807
	for config: Dictionary in definitions:
		states[config.id] = {"hp":config.maximum,"maximum":config.maximum,"phase_us":-1,"broken_us":-1,"finish_us":-1,"name":config.name,"config":config,"hits":[]}

func next_boundary_us() -> int:
	return int(schedule[cursor].time_us) if cursor < schedule.size() else 9223372036854775807

func observe(record: JudgmentRecord) -> void:
	completed[record.unit_id] = record
	for config: Dictionary in definitions:
		if record.unit_id not in config.note_ids: continue
		if record.unit_kind == &"tap": _damage(config.id, record.unit_id+":head", record.grade, UNIT, record.finalized_at_us)
		elif record.unit_kind == &"hold":
			if not record.components.is_empty(): _damage(config.id, record.unit_id+":head", record.components[0].grade, UNIT, record.components[0].observed_us)
			_damage(config.id, record.unit_id+":tail", record.grade, UNIT, record.finalized_at_us)

func advance(time_us: int, inclusive: bool, notes: NoteJudgeEngine, tuning: TuningEngine) -> void:
	for config: Dictionary in definitions:
		for head: Dictionary in notes.boss_active_heads():
			if head.id in config.note_ids: _damage(config.id, str(head.id)+":head", head.grade, UNIT, head.time_us)
	while cursor < schedule.size():
		var item: Dictionary = schedule[cursor]
		if item.time_us > time_us or (item.time_us == time_us and not inclusive): break
		var grade := GameplayTypes.JudgmentGrade.MISS
		if item.kind == "tuning":
			var key := "%s:%s:%d" % [item.object_id,item.note_id,item.segment]
			var valid := tuning.ghost_grade(PackedStringArray(item.slider_ids), item.time_us) != GameplayTypes.JudgmentGrade.MISS
			coverage[key] = int(coverage.get(key,0)) + (1 if valid else 0)
			if not item.last: cursor += 1; continue
			grade = tuning.completion_grade(float(coverage[key])/48.0)
			coverage.erase(key)
		else:
			grade = notes.boss_sustain_grade(item.note_id)
			if completed.has(item.note_id):
				var record: JudgmentRecord = completed[item.note_id]
				if record.finalized_at_us >= item.time_us: grade = record.grade
		_damage(item.object_id, "%s:%s:%d" % [item.note_id,item.kind,item.time_us], grade,item.amount,item.time_us)
		cursor += 1
	for state: Dictionary in states.values():
		var ending:=_ending(state.config,false,false)
		if state.maximum == 0 or state.finish_us >= 0 or time_us < ending: continue
		var phase_end := int(state.phase_us) + int(state.config.get("phase_duration_us",0)) if state.phase_us >= 0 else 0
		if time_us >= phase_end: state.finish_us = maxi(ending,phase_end)

func simulate(time_us: int, success: bool) -> void:
	if time_us < preview_time or success != preview_success: reset()
	preview_time=time_us;preview_success=success
	while preview_cursor < perfect_events.size() and int(perfect_events[preview_cursor].time_us) <= time_us:
		var event: Dictionary=perfect_events[preview_cursor]
		_damage(event.object_id,event.key,GameplayTypes.JudgmentGrade.PERFECT if success else GameplayTypes.JudgmentGrade.MISS,event.amount,event.time_us)
		preview_cursor+=1
	for state: Dictionary in states.values():
		var phase_end := int(state.phase_us)+int(state.config.get("phase_duration_us",0)) if state.phase_us>=0 else 0
		var ending:=_ending(state.config,true,success)
		if state.maximum>0 and time_us>=maxi(ending,phase_end):state.finish_us=maxi(ending,phase_end)

func resolve_contact(id: String, at: int) -> void:
	contacts[id]=at

func _ending(config: Dictionary, simulated: bool, success: bool) -> int:
	var result:=0
	for id: String in config.note_ends:
		var end: Dictionary=config.note_ends[id]
		var at:=int(end.fallback)
		if simulated and success:at=end.ideal
		elif end.kind=="tap" and contacts.has(id):at=contacts[id]
		elif end.kind=="hold" and completed.has(id) and completed[id].grade!=GameplayTypes.JudgmentGrade.MISS:at=completed[id].finalized_at_us
		result=maxi(result,at)
	# Ghost 的终点不由 Tap 接触替代。
	if config.note_ends.size()<config.note_ids.size():result=maxi(result,int(config.last_us))
	return result

func _damage(id: String, key: String, grade: int, amount: int, at: int) -> void:
	var unique := id+":"+key
	if consumed.has(unique): return
	consumed[unique] = true
	var damage := amount if grade == GameplayTypes.JudgmentGrade.PERFECT else (amount / 2 if grade == GameplayTypes.JudgmentGrade.GOOD else 0)
	var state: Dictionary = states[id]
	if damage <= 0 or state.maximum == 0: return
	state.hp = maxi(0, int(state.hp)-damage)
	state.hits.append(at)
	if state.phase_us < 0 and state.hp * 2 <= state.maximum and int(state.config.get("phase_duration_us",0)) > 0: state.phase_us = at
	if state.hp == 0 and state.broken_us < 0: state.broken_us = at
	history.append({"object_id":id,"time_us":at,"hp":state.hp,"damage":damage})
