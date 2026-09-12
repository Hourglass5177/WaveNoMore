class_name LevelBossCompiler
extends RefCounted
## 从各难度自己的稳定音符 ID 派生动作时间，不往谱面中插入额外攻击事件。
static func compile(stage: StageDefinition, tempo: TempoMap, player: LevelShowPlayer) -> Dictionary:
	var emissions := {}; var tracks: Array = []; var seen_actions := {}; var issues: Array = []
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
		var action := str(binding.get("action", ""))
		var release_sec := float(binding.get("release_sec", player.assets.release_time(str(object_data.asset), action)))
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
				path.merge({"release_us": release_us, "entry_us": entry_us, "object_id": object_id, "binding_id": binding.id, "binding": binding.duplicate(true)})
				emissions[note_id] = path
			# 同一对象同一出手时刻只生成一次动作；连发可通过各绑定的动作与出手帧调整。
			var action_key := object_id + ":" + str(start_us) + ":" + action
			if seen_actions.has(action_key): continue
			seen_actions[action_key] = true
			if not action.is_empty():
				var track := LevelFormat.track(object_id, "action", "song", "action")
				track.id = "binding_track_" + str(binding.id) + "_" + note_id
				track.binding_id = binding.id
				var clip := LevelFormat.clip(start_us + offset_us, "", int(binding.get("action_duration_us", 1000000)))
				clip.id = "binding_action_" + str(binding.id) + "_" + str(start_us)
				clip.action = action; clip.rate = rate; clip.name = "攻击 · " + action
				track.clips = [clip]; tracks.append(track)
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
	return {"emissions": emissions, "tracks": tracks, "issues": issues}
