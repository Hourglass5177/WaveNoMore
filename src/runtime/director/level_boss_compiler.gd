class_name LevelBossCompiler
extends RefCounted
## 从各难度自己的稳定音符 ID 派生动作时间，不往谱面中插入额外攻击事件。
static func compile(stage: StageDefinition, tempo: TempoMap, player: LevelShowPlayer) -> Dictionary:
	var emissions := {}; var tracks: Array = []; var events: Array = []; var issues: Array = []
	var notes := {}
	var source: SongChart = stage.get_meta("level_source_chart", stage.chart)
	for note in source.note_events: notes[note.event_id] = note
	for note in source.ghost_events: notes[note.event_id] = note
	var approach_us := roundi(stage.rule_set.approach_duration_sec * 1000000.0)
	# 公共演出以音频起点为零；谱面时间以首拍为零，只在接口处换算。
	var offset_us := roundi(stage.song.first_beat_offset_sec * 1000000.0)
	for binding: Dictionary in player.show.get("bindings", []):
		if str(binding.get("difficulty", "")) != stage.chart.difficulty_id: continue
		var object_id := str(binding.get("object_id", ""))
		var object_data := LevelFormat.find(player.show.get("objects", []), object_id)
		if object_data.is_empty(): continue
		var duration_us := maxi(1, int(binding.get("return_us", 600000)))
		var spec := LevelBossActions.resolve(player.assets, object_data, binding)
		var action := str(spec.action)
		if action.is_empty(): issues.append({"message": "BOSS 素材没有可识别的攻击动作，请配置动作映射。", "binding_id": binding.id})
		var release_sec := float(spec.release)
		var rate := maxf(0.01, float(binding.get("rate", 1.0)))
		for note_id: String in binding.get("note_ids", []):
			if not notes.has(note_id): issues.append({"message": "攻击关联的音符已删除：" + note_id, "binding_id": binding.id}); continue
			var note: Resource = notes[note_id]
			if not note.boss: issues.append({"message": "音符已取消 BOSS 标记：" + note_id, "binding_id": binding.id}); continue
			var entry_us := tempo.tick_to_us(note.tick) - approach_us
			var release_us := entry_us - duration_us
			var start_us := release_us - roundi(release_sec * 1000000.0 / rate)
			if note is NoteEvent:
				var death: bool = note.affinity == GameplayTypes.Affinity.XUAN
				var anchor_name := str(binding.get("death_anchor" if death else "life_anchor", "death" if death else "life"))
				var release_pose := {"id":"release_" + str(binding.id),"action":action,"local_us":roundi(release_sec * 1000000.0),"loop":false,"weight":1.0}
				var origin := player.anchor_at(object_id, anchor_name, "song", release_us + offset_us, release_pose)
				var entrance: Vector2 = stage.rule_set.death_note_spawn if death else stage.rule_set.life_note_spawn
				var cue: Vector2 = stage.rule_set.death_note_cue if death else stage.rule_set.life_note_cue
				var bell: Vector2 = stage.rule_set.death_wave_origin if death else stage.rule_set.life_wave_origin
				var profile := NoteApproachPath.build_profile(entrance, cue, bell, stage.rule_set.note_curve_outer_bend_px, stage.rule_set.note_curve_center_handle_px)
				var velocity := NoteApproachPath.tangent_at_ratio(profile, 0.0) * NoteApproachPath.length(profile) / stage.rule_set.approach_duration_sec
				var handle := LevelFormat.vec(binding.get("death_handle" if death else "life_handle", []), (entrance - origin).normalized() * (origin.distance_to(entrance) + 400.0))
				var path := BossEmissionPath.build(origin, entrance, velocity, duration_us, handle)
				if binding.get("path_mode","auto") != "custom":
					var settings: Dictionary = player.assets.boss_defaults.duplicate()
					settings.merge(object_data.get("boss", {}),true)
					var seed := source.chart_id+":"+stage.chart.difficulty_id+":"+object_id+":"+note_id
					path=BossEmissionPath.scatter(origin,profile,stage.rule_set.approach_duration_sec,float(stage.rule_set.miss_window_ms)/1000,seed,float(binding.get("flight_speed",settings.get("flight_speed",600.0))),float(binding.get("spread_deg",settings.get("spread_deg",30.0))))
					entry_us=tempo.tick_to_us(note.tick)-int(path.join_lead_us)
					release_us=entry_us-int(path.duration_us)
					# 出手时间改变后再次读取对象运动，避免沿用旧固定提前段的位置。
					origin=player.anchor_at(object_id,anchor_name,"song",release_us+offset_us,release_pose)
					path=BossEmissionPath.scatter(origin,profile,stage.rule_set.approach_duration_sec,float(stage.rule_set.miss_window_ms)/1000,seed,float(binding.get("flight_speed",settings.get("flight_speed",600.0))),float(binding.get("spread_deg",settings.get("spread_deg",30.0))))
					release_us=entry_us-int(path.duration_us)
				path.merge({"release_us": release_us, "entry_us": entry_us, "object_id": object_id, "binding_id": binding.id, "binding": binding.duplicate(true)})
				if path.has("arc_profile"):
					path.origin_sampler = func(): return player.anchor_at(object_id,anchor_name,"song",release_us+offset_us,release_pose)
					path.origin_revision = func():
						var state: Dictionary=player.boss_battle.states.get(object_id,{}) if player.boss_battle != null else {}
						var phase:=int(state.get("phase_us",-1))
						return phase if phase<=release_us else -1
				emissions[note_id] = path
			elif note is GhostEvent:
				# 双侧前导只提示 BOSS 出手，不替代领域计算的调频目标与素音位置。
				for side in ["life","death"]:
					var rules := stage.rule_set
					var entrance: Vector2 = rules.life_note_spawn if side=="life" else rules.death_note_spawn
					var cue: Vector2 = rules.life_note_cue if side=="life" else rules.death_note_cue
					var bell: Vector2 = rules.life_wave_origin if side=="life" else rules.death_wave_origin
					var profile := NoteApproachPath.build_profile(entrance,cue,bell,rules.note_curve_outer_bend_px,rules.note_curve_center_handle_px)
					var origin := player.anchor_at(object_id,str(binding.get(side+"_anchor",side)),"song",release_us+offset_us)
					var settings: Dictionary=player.assets.boss_defaults.duplicate();settings.merge(object_data.get("boss",{}),true)
					var path := BossEmissionPath.scatter(origin,profile,rules.approach_duration_sec,float(rules.miss_window_ms)/1000,source.chart_id+object_id+note_id+side,float(binding.get("flight_speed",settings.get("flight_speed",600))),float(binding.get("spread_deg",settings.get("spread_deg",30))))
					var end := tempo.tick_to_us(note.tick)-int(path.join_lead_us)
					var start := end-int(path.duration_us)
					path.merge({"release_us":start,"entry_us":end,"object_id":object_id,"binding_id":binding.id,"binding":binding.duplicate(true),"ghost":true,"side":side})
					emissions[note_id+":"+side]=path
					release_us=mini(release_us,start)
			events.append({"object_id":object_id,"binding_id":binding.id,"asset":str(object_data.asset),"release_us":release_us,"spec":spec})
			var effect := str(binding.get("effect", ""))
			if not effect.is_empty():
				var track := LevelFormat.track(object_id, "effect", "song", "effect")
				track.binding_id = binding.id
				var clip := LevelFormat.clip(release_us + offset_us, effect, int(binding.get("effect_duration_us", 400000)))
				clip.id = "binding_effect_" + str(binding.id) + "_" + str(release_us)
				track.clips = [clip]; tracks.append(track)
			var sound := str(binding.get("sound", ""))
			if not sound.is_empty():
				var track := LevelFormat.track(object_id, "audio", "song", "audio")
				track.binding_id = binding.id
				var clip := LevelFormat.clip(release_us + offset_us, sound, int(binding.get("sound_duration_us", 1000000)))
				clip.id = "binding_sound_" + str(binding.id) + "_" + str(release_us)
				clip.transient = true
				track.clips = [clip]; tracks.append(track)
	tracks.append_array(LevelBossActions.tracks(events, player.assets, offset_us))
	return {"emissions": emissions, "tracks": tracks, "issues": issues, "battles": battle_configs(player)}

static func battle_configs(player: LevelShowPlayer) -> Array:
	var result: Array = []
	for object: Dictionary in player.show.get("objects", []):
		var ids: Array = []
		for binding: Dictionary in player.show.get("bindings", []):
			if binding.object_id != object.id or binding.difficulty != player.difficulty: continue
			for id in binding.note_ids:
				if id not in ids: ids.append(id)
		if ids.is_empty(): continue
		var spec := LevelBossActions.resolve(player.assets, object, {})
		var config: Dictionary = player.assets.boss_defaults.duplicate(true)
		config.merge(object.get("boss",{}),true)
		config.merge({"id":object.id,"name":object.name,"note_ids":ids,"actions":spec},true)
		config.phase_duration_us = roundi(player.assets.action_duration(object.asset,spec.phase_break)*1000000) if not str(spec.phase_break).is_empty() else 0
		config.death_duration_us = roundi(player.assets.action_duration(object.asset,spec.death)*1000000) if not str(spec.death).is_empty() else 600000
		if config.get("visual","") == "goat": config.phase_duration_us = 3000000
		if spec.has("death_duration"): config.death_duration_us = roundi(float(spec.death_duration)*1000000)
		result.append(config)
	return result
