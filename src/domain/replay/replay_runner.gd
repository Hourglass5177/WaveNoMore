class_name ReplayRunner
extends RefCounted

## 不依赖场景树的 Replay 执行器。它按输入时间精确推进 GameplaySimulation，
## 可更换帧步验证结果是否与刷新率无关；这里不负责实时画面播放。

static func run(
		compiled: CompiledChart,
		rules: GameplayRuleSet,
		replay: ReplayData,
		frame_step_us: int = 16_667,
		pet: PetEffectProfile = null
) -> Dictionary:
	return run_with_frame_steps(compiled, rules, replay, PackedInt64Array([maxi(1, frame_step_us)]), pet)


static func run_with_frame_steps(
		compiled: CompiledChart,
		rules: GameplayRuleSet,
		replay: ReplayData,
		frame_steps_us: PackedInt64Array,
		pet: PetEffectProfile = null
) -> Dictionary:
	if compiled == null or rules == null or replay == null:
		return {"ok": false, "error": "ReplayRunner received a null dependency."}
	if replay.schema_version != ReplayData.CURRENT_SCHEMA_VERSION:
		return {
			"ok": false,
			"error": "Unsupported replay schema v%d; this build requires v%d." % [
				replay.schema_version,
				ReplayData.CURRENT_SCHEMA_VERSION,
			],
		}
	if not replay.chart_hash.is_empty() and replay.chart_hash != compiled.content_hash:
		return {"ok": false, "error": "Replay chart hash mismatch."}
	var expected_rules_hash: String = ChartCompiler.rules_hash(rules)
	if not replay.rules_hash.is_empty() and replay.rules_hash != expected_rules_hash:
		return {"ok": false, "error": "Replay rules hash mismatch."}
	if frame_steps_us.is_empty():
		frame_steps_us = PackedInt64Array([16_667])
	var simulation := GameplaySimulation.new()
	simulation.configure(compiled, rules, false, pet)
	var samples: Array[SemanticInputSample] = []
	for source_sample in replay.sorted_inputs():
		samples.append(SemanticInputSample.create(
			source_sample.timestamp_us + replay.captured_input_offset_us,
			source_sample.sequence,
			source_sample.kind,
			source_sample.tune_vector
		))
	var input_index: int = 0
	var frame_index: int = 0
	# 从最早判定窗（可能是负拍）开始，并在谱尾后多推进一个最晚判定窗，
	# 即使玩家完全不操作，也能让所有音符正常结算为 Miss。
	var cursor_us: int = 0
	for note in compiled.notes:
		cursor_us = mini(cursor_us, int(note["start_us"]) - rules.miss_window_ms * 1000)
	for field in compiled.tuning_fields:
		cursor_us = mini(cursor_us, int(field["start_us"]))
	for region in compiled.rapid_regions:
		cursor_us = mini(cursor_us, int(region["start_us"]))
	if not samples.is_empty():
		cursor_us = mini(cursor_us, samples[0].timestamp_us)
	# Hold 与调频都在原定尾点完成；只有普通音符还需要 Miss 窗。
	var settle_us: int = rules.miss_window_ms * 1000 + 1
	var finish_us: int = maxi(compiled.end_time_us + settle_us + simulation.pet_effect.hold_head_bonus_ms * 1000, simulation.wave_engine.last_arrival_us())
	if not samples.is_empty():
		finish_us = maxi(finish_us, samples[-1].timestamp_us + settle_us)
	while cursor_us < finish_us and not simulation.health_engine.failed:
		var step_us: int = maxi(1, int(frame_steps_us[frame_index % frame_steps_us.size()]))
		frame_index += 1
		var frame_end_us: int = mini(finish_us, cursor_us + step_us)
		while input_index < samples.size() and samples[input_index].timestamp_us <= frame_end_us:
			var event_time_us: int = samples[input_index].timestamp_us
			if event_time_us < cursor_us:
				input_index += 1
				continue
			# 先推进到“尚未包含这个时刻”，再处理全部同时间输入，最后结算该时刻。
			# 这样卡在判定边界或区域尾点的输入不会先被系统判成超时。
			simulation.advance_to(event_time_us, false)
			while input_index < samples.size() and samples[input_index].timestamp_us == event_time_us:
				simulation.accept_input(samples[input_index])
				input_index += 1
			simulation.advance_to(event_time_us, true)
		cursor_us = frame_end_us
		simulation.advance_to(cursor_us, true)
	var summary: ResultSummary = simulation.result_summary()
	var digest: String = result_digest(simulation.judgments, simulation.strays, summary)
	var verified: bool = replay.expected_result_digest.is_empty() or replay.expected_result_digest == digest
	return {
		"ok": true,
		"verified": verified,
		"digest": digest,
		"summary": summary,
		"simulation": simulation,
		"judgments": simulation.judgments,
		"strays": simulation.strays,
	}


static func build_perfect_replay(
		compiled: CompiledChart,
		rules: GameplayRuleSet,
		song: SongDefinition = null
) -> ReplayData:
	# 这是自动测试用的理想输入生成器，不是玩家可用的自动演奏功能。
	var replay := ReplayData.new()
	replay.replay_id = "perfect:%s" % compiled.chart_id
	replay.chart_hash = compiled.content_hash
	replay.rules_hash = ChartCompiler.rules_hash(rules)
	# 纯领域测试没有 SongDefinition 时不伪造歌曲身份；要交给 Runtime 播放时必须传入歌曲。
	if song != null:
		replay.song_timing_hash = ReplayData.compute_song_timing_hash(
			song.song_id,
			song.first_beat_offset_sec,
			compiled.content_hash
		)
	var raw_events: Array[Dictionary] = []
	for note in compiled.notes:
		var press_kind: int = GameplayTypes.SemanticInputKind.LIFE_A_PRESSED if int(note["affinity"]) == GameplayTypes.Affinity.ZHU else GameplayTypes.SemanticInputKind.DEATH_A_PRESSED
		var release_kind: int = GameplayTypes.SemanticInputKind.LIFE_A_RELEASED if int(note["affinity"]) == GameplayTypes.Affinity.ZHU else GameplayTypes.SemanticInputKind.DEATH_A_RELEASED
		raw_events.append({"time": int(note["start_us"]), "kind": press_kind, "vector": Vector2.ZERO, "priority": 0 if press_kind == GameplayTypes.SemanticInputKind.LIFE_A_PRESSED else 1})
		var release_time: int = int(note["end_us"]) if note["unit_kind"] == &"hold" else int(note["start_us"]) + 1000
		raw_events.append({"time": release_time, "kind": release_kind, "vector": Vector2.ZERO, "priority": 3 if release_kind == GameplayTypes.SemanticInputKind.LIFE_A_RELEASED else 4})
	# 调频段开始时领域层会把两钟恢复到统一基频。重放生成器记录同样的重置点，
	# 随后把每个采样的绝对引导位置转换成相对位移语义。
	for field in compiled.tuning_fields:
		raw_events.append({
			"time": int(field["start_us"]),
			"event_type": &"tuning_reset",
			"priority": -1,
		})
	_append_tuning_hold_events(
		raw_events,
		compiled.tuning_sliders,
		compiled.su_manifestations
	)
	for slider in compiled.tuning_sliders:
		var life: bool = int(slider["affinity"]) == GameplayTypes.Affinity.ZHU
		var end_us: int = int(slider["end_us"])
		var step: int = maxi(1, rules.tuning_sample_interval_ticks)
		var sample_tick: int = int(slider["tick"])
		var end_tick: int = int(slider["end_tick"])
		while sample_tick <= end_tick:
			# 输入与谱面事件同刻时，模拟器会先处理玩家输入再包含该时刻的场域事件。
			# 起点位移延后 1 微秒，确保 field_enter 已完成；这个偏移远低于任何判定精度。
			var target_time_us: int = compiled.tempo_map.tick_to_us(sample_tick)
			if sample_tick == int(slider["tick"]):
				target_time_us += 1
			raw_events.append({
				"time": target_time_us,
				"event_type": &"tuning_target",
				"life": life,
				"target": _slider_guide_value(slider, sample_tick),
				"priority": 2,
			})
			sample_tick += step
		# 采样步长不一定整除滑条长度，尾点也必须有一次精确目标位移。
		if (sample_tick - step) != end_tick:
			raw_events.append({
				"time": end_us,
				"event_type": &"tuning_target",
				"life": life,
				"target": _slider_guide_value(slider, end_tick),
				"priority": 2,
			})
	for region in compiled.rapid_regions:
		var required: int = int(region["required_strikes"])
		var duration_us: int = int(region["end_us"]) - int(region["start_us"])
		for index in range(required):
			var strike_us: int = int(region["start_us"]) + roundi(float(index) * float(duration_us) / float(maxi(1, required - 1)))
			var life: bool = index % 2 == 0
			var press_kind: int = GameplayTypes.SemanticInputKind.LIFE_A_PRESSED if life else GameplayTypes.SemanticInputKind.DEATH_A_PRESSED
			var release_kind: int = GameplayTypes.SemanticInputKind.LIFE_A_RELEASED if life else GameplayTypes.SemanticInputKind.DEATH_A_RELEASED
			raw_events.append({"time": strike_us, "kind": press_kind, "vector": Vector2.ZERO, "priority": 0 if life else 1})
			raw_events.append({"time": strike_us + 1000, "kind": release_kind, "vector": Vector2.ZERO, "priority": 3 if life else 4})
	# 同一时刻固定处理“频率段重置 → 按下 → 调频位移 → 松开”。
	raw_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["time"]) != int(b["time"]):
			return int(a["time"]) < int(b["time"])
		if int(a["priority"]) != int(b["priority"]):
			return int(a["priority"]) < int(b["priority"])
		if a.has("kind") and b.has("kind"):
			return int(a["kind"]) < int(b["kind"])
		return bool(a.get("life", false)) and not bool(b.get("life", false))
	)
	var base_value: float = inverse_lerp(
		rules.tuning_min_frequency_hz,
		rules.tuning_max_frequency_hz,
		rules.tuning_base_frequency_hz
	)
	var current_value := Vector2(base_value, base_value)
	for event: Dictionary in raw_events:
		var event_type: StringName = event.get("event_type", &"input")
		if event_type == &"tuning_reset":
			current_value = Vector2(base_value, base_value)
			continue
		if event_type == &"tuning_target":
			var life: bool = bool(event["life"])
			var target: float = float(event["target"])
			var delta := Vector2(target - current_value.x, 0.0) if life else Vector2(0.0, target - current_value.y)
			var displacement_sample := SemanticInputSample.create(
				int(event["time"]),
				replay.inputs.size(),
				GameplayTypes.SemanticInputKind.TUNING_DISPLACED,
				delta
			)
			replay.inputs.append(displacement_sample)
			# 下一步以实际写入 Replay 的 Q15 位移为准，消除连续量化误差的累积。
			if life:
				current_value.x = clampf(current_value.x + displacement_sample.tune_vector.x, 0.0, 1.0)
			else:
				current_value.y = clampf(current_value.y + displacement_sample.tune_vector.y, 0.0, 1.0)
			continue
		replay.inputs.append(SemanticInputSample.create(
			int(event["time"]),
			replay.inputs.size(),
			int(event["kind"]),
			event["vector"]
		))
	return replay


static func result_digest(judgments: Array[JudgmentRecord], strays: Array[StrayInputRecord], summary: ResultSummary) -> String:
	# 把结果写成稳定文本后再哈希，测试便能直接比较不同帧步是否得到完全相同的结局。
	var lines := PackedStringArray(["JudgmentResult:v2"])
	for record in judgments:
		lines.append(record.canonical_line())
	for stray in strays:
		lines.append("stray|" + stray.canonical_line())
	var result: Dictionary = summary.to_dictionary()
	var keys: Array = result.keys()
	keys.sort()
	for key in keys:
		lines.append("result|%s=%s" % [key, var_to_str(result[key])])
	return "\n".join(lines).sha256_text()


static func _slider_guide_value(slider: Dictionary, sample_tick: int) -> float:
	var traversal_ticks: int = maxi(1, int(slider["traversal_ticks"]))
	var elapsed_ticks: int = clampi(sample_tick - int(slider["tick"]), 0, int(slider["duration_ticks"]))
	var traversal_index: int = mini(
		int(slider["traversal_count"]) - 1,
		floori(float(elapsed_ticks) / float(traversal_ticks))
	)
	var within_traversal: int = elapsed_ticks - traversal_index * traversal_ticks
	var ratio: float = clampf(float(within_traversal) / float(traversal_ticks), 0.0, 1.0)
	if traversal_index % 2 == 1:
		ratio = 1.0 - ratio
	return lerpf(float(slider["start_value"]), float(slider["end_value"]), ratio)


static func _append_tuning_hold_events(
		raw_events: Array[Dictionary],
		sliders: Array[Dictionary],
		su_manifestations: Array[Dictionary]
) -> void:
	# 同侧首尾相接的多条滑条属于连续操作。理想 Replay 只在整段开头按下、最后松开，
	# 避免前一条的尾部松键在后一条已经开始后把 held 状态意外清掉。
	var su_time_by_group: Dictionary = {}
	for manifestation: Dictionary in su_manifestations:
		var group_id: String = str(manifestation.get("group_id", ""))
		if group_id.is_empty():
			continue
		su_time_by_group[group_id] = maxi(
			int(su_time_by_group.get(group_id, 0)),
			int(manifestation.get("time_us", manifestation.get("start_us", 0)))
		)
	for affinity: int in [GameplayTypes.Affinity.ZHU, GameplayTypes.Affinity.XUAN]:
		var intervals: Array[Dictionary] = []
		for slider: Dictionary in sliders:
			if int(slider.get("affinity", GameplayTypes.Affinity.SU)) != affinity:
				continue
			var carrier_end_us: int = int(slider["end_us"])
			var group_id: String = str(slider.get("group_id", ""))
			if su_time_by_group.has(group_id):
				carrier_end_us = maxi(carrier_end_us, int(su_time_by_group[group_id]))
			intervals.append({"start_us": int(slider["start_us"]), "end_us": carrier_end_us})
		intervals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["start_us"]) != int(b["start_us"]):
				return int(a["start_us"]) < int(b["start_us"])
			return int(a["end_us"]) < int(b["end_us"])
		)
		var merged: Array[Dictionary] = []
		for interval: Dictionary in intervals:
			if merged.is_empty() or int(interval["start_us"]) > int(merged[-1]["end_us"]) + 1000:
				merged.append(interval.duplicate())
			else:
				merged[-1]["end_us"] = maxi(int(merged[-1]["end_us"]), int(interval["end_us"]))
		var life: bool = affinity == GameplayTypes.Affinity.ZHU
		var press_kind: int = GameplayTypes.SemanticInputKind.LIFE_A_PRESSED if life else GameplayTypes.SemanticInputKind.DEATH_A_PRESSED
		var release_kind: int = GameplayTypes.SemanticInputKind.LIFE_A_RELEASED if life else GameplayTypes.SemanticInputKind.DEATH_A_RELEASED
		for interval: Dictionary in merged:
			raw_events.append({
				"time": int(interval["start_us"]),
				"kind": press_kind,
				"vector": Vector2.ZERO,
				"priority": 0 if life else 1,
			})
			raw_events.append({
				# 若这组随后凝现素音，测试 Replay 只把载波维持到该事件；计分窗口
				# 仍在滑条原定尾点结束，不会误伤后续另一种音符的按住状态。
				"time": int(interval["end_us"]) + 1000,
				"kind": release_kind,
				"vector": Vector2.ZERO,
				"priority": 3 if life else 4,
			})
