class_name GameplaySimulation
extends RefCounted

## 一局玩法的纯逻辑总入口，统一调度普通音符、调频、疾振、物理波、计分和魂火。
## 外部只能按绝对微秒推进或提交语义输入，不能依赖 Node、帧 delta 或画面碰撞。

## 本局编译谱；configure 后只读，所有机制共用其中的确定性微秒时间轴。
var compiled: CompiledChart
## 本局规则表；判定窗、计分、魂火和物理坐标均从此读取。
var rules: GameplayRuleSet
## Tap/Hold 的头、持续、尾与乱按绑定判定器。
var note_engine := NoteJudgeEngine.new()
## 调频开放段、每程端点卡拍及双侧成组结算判定器。
var tuning_engine := TuningEngine.new()
## 双钟疾振的计数、防抖和交替判定器。
var rapid_engine := RapidEngine.new()
## 实体音符路径、圆形波传播及波—音符接触求解器。
var wave_engine := WaveInteractionEngine.new()
## 长按两口钟产生的持续载波；只参与相纹和素音，不命中普通音符。
var carrier_engine := CarrierWaveEngine.new()
## 判定等级、Combo 与基础/奖励分累计器。
var score_engine := ScoreEngine.new()
## 魂火、伤害组去重与失败状态累计器。
var health_engine := HealthEngine.new()

## 当前歌曲时间，单位微秒；极小初值表示尚未推进到任何有效时间。
var current_time_us: int = -9_000_000_000_000_000
## 生钟键当前是否按住；由 LIFE_PRESSED/RELEASED 更新，失焦时强制 false。
var life_held: bool = false
## 死钟键当前是否按住；由 DEATH_PRESSED/RELEASED 更新，失焦时强制 false。
var death_held: bool = false
## 本局全部已完成判定；按 record.sequence 稳定排列，直到本局销毁。
var judgments: Array[JudgmentRecord] = []
## 本局全部未被机制消费的乱按；按输入 sequence 稳定排列。
var strays: Array[StrayInputRecord] = []

## 尚未被 StageSession 取走的新增判定；drain_judgments 后清空。
var _pending_judgments: Array[JudgmentRecord] = []
## 尚未被上层取走的新增乱按；drain_strays 后清空。
var _pending_strays: Array[StrayInputRecord] = []
## 尚未交给表现层的发波事件；每项含波 ID、波源、阵营、强度和发射微秒。
var _pending_wave_launches: Array[Dictionary] = []
## 尚未交给表现层的波—音符接触事件；只描述已由物理求解确认的相遇。
var _pending_wave_contacts: Array[Dictionary] = []
## 尚未交给表现层的漏过判定点事件；表示音符未被目标彩波击中而抵达钟点。
var _pending_note_arrivals: Array[Dictionary] = []
## 已经到时的素音凝现结果；位置来自两列真实载波圆波前的交点。
var _su_manifestations: Array[Dictionary] = []
## 下一条尚未处理的编译后素音事件索引。
var _su_cursor: int = 0
## 分配给下一条 JudgmentRecord 的全局递增序号；同微秒也不会重复。
var _judgment_sequence: int = 0
## 最近一次输入的 InputOwner；NONE 表示未被任何机制消费。
var _last_input_owner: int = GameplayTypes.InputOwner.NONE
## 暂停后等待重新确认按键状态的标志；为 true 时拒收普通玩法输入。
var _paused_for_rearm: bool = false
## 非致死调试标志；为 true 时魂火可为负，但 HealthEngine 不进入 failed。
var _debug_nonlethal: bool = false


func configure(p_compiled: CompiledChart, p_rules: GameplayRuleSet, debug_nonlethal: bool = false) -> void:
	compiled = p_compiled
	rules = p_rules
	_debug_nonlethal = debug_nonlethal
	note_engine.configure(compiled, rules)
	tuning_engine.configure(compiled, rules)
	rapid_engine.configure(compiled, rules)
	wave_engine.configure(compiled, rules)
	carrier_engine.configure(rules)
	score_engine.configure(rules)
	health_engine.configure(rules, _debug_nonlethal)
	current_time_us = -9_000_000_000_000_000
	life_held = false
	death_held = false
	judgments.clear()
	strays.clear()
	_pending_judgments.clear()
	_pending_strays.clear()
	_pending_wave_launches.clear()
	_pending_wave_contacts.clear()
	_pending_note_arrivals.clear()
	_su_manifestations.clear()
	_su_cursor = 0
	_judgment_sequence = 0
	_last_input_owner = GameplayTypes.InputOwner.NONE
	_paused_for_rearm = false


func reset() -> void:
	configure(compiled, rules, _debug_nonlethal)


func advance_to(time_us: int, inclusive: bool = true) -> void:
	if compiled == null or rules == null or time_us < current_time_us:
		return
	current_time_us = time_us
	if _paused_for_rearm:
		return
	# 魂火耗尽后冻结新的判定与计分，但已经发出的实体波仍继续传播，
	# 这样失败收尾时不会出现波纹在半空突然消失。
	wave_engine.advance_to(time_us, inclusive)
	if health_engine.failed:
		carrier_engine.advance_to(time_us, inclusive)
		_collect_wave_events()
		return
	rapid_engine.advance_to(time_us, inclusive)
	tuning_engine.advance_to(time_us, inclusive, life_held, death_held)
	_apply_tuning_frequency_changes(time_us, inclusive)
	note_engine.advance_to(time_us, inclusive)
	_process_su_manifestations(time_us, inclusive)
	_collect_engine_records()
	_collect_wave_events()


func accept_input(sample: SemanticInputSample) -> int:
	if sample == null or compiled == null or rules == null or health_engine.failed or _paused_for_rearm:
		return GameplayTypes.InputOwner.NONE
	# 即使设备适配器绕过 SemanticInputSample.create 直接构造对象，
	# 进入内核前仍重新量化为 Replay 约定的 Q15，保证实时与回放一致。
	sample = SemanticInputSample.create(sample.timestamp_us, sample.sequence, sample.kind, sample.tune_vector)
	if sample.timestamp_us < current_time_us:
		return GameplayTypes.InputOwner.NONE
	if sample.timestamp_us > current_time_us:
		# 先推进到端点之前，等输入处理完再由外层包含端点；否则同刻音符可能抢先过期。
		advance_to(sample.timestamp_us, false)
	current_time_us = sample.timestamp_us
	if sample.kind == GameplayTypes.SemanticInputKind.FOCUS_CANCELLED:
		carrier_engine.set_held(GameplayTypes.Affinity.ZHU, false, sample.timestamp_us)
		carrier_engine.set_held(GameplayTypes.Affinity.XUAN, false, sample.timestamp_us)
		life_held = false
		death_held = false
		note_engine.cancel_active(sample.timestamp_us)
		tuning_engine.cancel_active(sample.timestamp_us)
		rapid_engine.cancel_active(sample.timestamp_us)
		_last_input_owner = GameplayTypes.InputOwner.NONE
		_collect_engine_records()
		return _last_input_owner
	_update_held_state(sample)
	_update_carrier_held_state(sample)
	var consumed: bool = false
	# 输入所有权固定为：疾振 > 已起手或可起手的调频 > 普通 Tap/Hold。
	# 谱面校验器会拒绝区域机制与 Hold 的冲突，避免同一输入存在两种解释。
	if rapid_engine.can_consume(sample):
		consumed = rapid_engine.handle_input(sample)
		_last_input_owner = GameplayTypes.InputOwner.RAPID
	elif tuning_engine.can_consume(sample):
		consumed = tuning_engine.handle_input(sample, life_held, death_held)
		_last_input_owner = GameplayTypes.InputOwner.TUNING if consumed else GameplayTypes.InputOwner.NONE
	else:
		if sample.is_press():
			consumed = note_engine.handle_press(sample)
		elif sample.is_release():
			consumed = note_engine.handle_release(sample)
		_last_input_owner = GameplayTypes.InputOwner.NOTE if consumed else GameplayTypes.InputOwner.NONE
	if not consumed and sample.is_press():
		var stray := StrayInputRecord.create(sample, rules)
		strays.append(stray)
		_pending_strays.append(stray)
		score_engine.apply_stray(stray)
		health_engine.apply_stray(stray)
	# 所有按下都会产生真实传播的波。机制认可时发红/黑彩波，乱按发灰波；
	# 普通音符还会把唯一目标绑定给波，等待两者实际相遇。
	if sample.is_press():
		var bound_note: Dictionary = {}
		if consumed and _last_input_owner == GameplayTypes.InputOwner.NOTE:
			bound_note = note_engine.last_press_binding()
		var wave_qualified: bool = false
		match _last_input_owner:
			GameplayTypes.InputOwner.NOTE:
				wave_qualified = consumed
			GameplayTypes.InputOwner.TUNING:
				wave_qualified = tuning_engine.last_press_qualified()
			GameplayTypes.InputOwner.RAPID:
				wave_qualified = rapid_engine.last_press_qualified()
		wave_engine.launch(sample, wave_qualified, _last_input_owner, bound_note)
	_apply_tuning_frequency_changes(sample.timestamp_us, true)
	carrier_engine.advance_to(sample.timestamp_us, true)
	_collect_engine_records()
	_collect_wave_events()
	return _last_input_owner


func force_finish() -> void:
	if compiled == null:
		return
	# Hold 与调频都在谱面尾点完成；只有普通音符还需等待 Miss 窗。
	var settle_us: int = rules.miss_window_ms * 1000 + 1
	advance_to(compiled.end_time_us + settle_us, true)
	wave_engine.force_finish()
	_collect_wave_events()


func begin_pause_rearm() -> Dictionary:
	_paused_for_rearm = true
	var note_state: Dictionary = note_engine.begin_pause_rearm()
	var tuning_state: Dictionary = tuning_engine.begin_pause_rearm()
	var result := {
		"life_required": bool(note_state.get("life_required", false)) or bool(tuning_state.get("life_required", false)),
		"death_required": bool(note_state.get("death_required", false)) or bool(tuning_state.get("death_required", false)),
		"tuning_required": bool(tuning_state.get("tuning_required", false)),
	}
	life_held = false
	death_held = false
	carrier_engine.begin_pause(current_time_us)
	return result


func apply_resume_rearm(rearm_state: Dictionary) -> void:
	life_held = bool(rearm_state.get("life_held", false))
	death_held = bool(rearm_state.get("death_held", false))
	carrier_engine.resume_after_pause(life_held, death_held, current_time_us)
	note_engine.apply_resume_rearm(rearm_state)
	tuning_engine.apply_resume_rearm(rearm_state)
	_paused_for_rearm = false
	_collect_engine_records()


func drain_judgments() -> Array[JudgmentRecord]:
	var result: Array[JudgmentRecord] = _pending_judgments.duplicate()
	_pending_judgments.clear()
	return result


func drain_strays() -> Array[StrayInputRecord]:
	var result: Array[StrayInputRecord] = _pending_strays.duplicate()
	_pending_strays.clear()
	return result


func drain_wave_launches() -> Array[Dictionary]:
	var result: Array[Dictionary] = _pending_wave_launches.duplicate(true)
	_pending_wave_launches.clear()
	return result


func drain_wave_contacts() -> Array[Dictionary]:
	var result: Array[Dictionary] = _pending_wave_contacts.duplicate(true)
	_pending_wave_contacts.clear()
	return result


func drain_note_arrivals() -> Array[Dictionary]:
	var result: Array[Dictionary] = _pending_note_arrivals.duplicate(true)
	_pending_note_arrivals.clear()
	return result


func result_summary() -> ResultSummary:
	return ResultEvaluator.evaluate(judgments, strays, score_engine, health_engine, compiled.theoretical_unit_count)


func input_owner() -> int:
	if rapid_engine.is_active_at(current_time_us):
		return GameplayTypes.InputOwner.RAPID
	if tuning_engine.is_active():
		return GameplayTypes.InputOwner.TUNING
	if note_engine.has_active_hold():
		return GameplayTypes.InputOwner.NOTE
	return _last_input_owner


func snapshot() -> Dictionary:
	var evaluated: ResultSummary = result_summary()
	return {
		"time_us": current_time_us,
		"input_owner": input_owner(),
		"tuning_field_active": tuning_engine.field_active(),
		"active_tuning_field_id": tuning_engine.active_field_id(),
		"life_tuning_value": tuning_engine.life_tuning_value(),
		"death_tuning_value": tuning_engine.death_tuning_value(),
		"life_frequency_hz": tuning_engine.life_frequency_hz(),
		"death_frequency_hz": tuning_engine.death_frequency_hz(),
		"active_tuning_sliders": tuning_engine.active_slider_snapshots(),
		"rapid_ratio": rapid_engine.current_ratio(),
		"life_held": life_held,
		"death_held": death_held,
		"active_hold_ids": note_engine.active_hold_ids(),
		"held_hold_ids": note_engine.active_hold_ids(true),
		"score": score_engine.total_score(),
		"raw_score": score_engine.raw_score,
		"combo": score_engine.combo,
		"max_combo": score_engine.max_combo,
		"soul_fire": health_engine.soul_fire,
		"max_soul_fire": rules.max_soul_fire,
		"failed": health_engine.failed,
		"debug_nonlethal": _debug_nonlethal,
		"judgment_count": judgments.size(),
		"stray_count": strays.size(),
		"emitted_wave_count": wave_engine.wave_count(),
		"carrier_wave_count": carrier_engine.emission_count(),
		"carrier_wavefronts": carrier_engine.visible_wavefronts(current_time_us),
		"su_manifestations": _su_manifestations.duplicate(true),
		"paused_for_rearm": _paused_for_rearm,
		"cleared": evaluated.cleared,
		"fc": evaluated.full_combo,
		"ap": evaluated.all_perfect,
		"miss_count": evaluated.miss_count,
		"expected_judgment_count": compiled.theoretical_unit_count,
		"content_hash": compiled.content_hash,
	}


func _update_held_state(sample: SemanticInputSample) -> void:
	match sample.kind:
		GameplayTypes.SemanticInputKind.LIFE_PRESSED:
			life_held = true
		GameplayTypes.SemanticInputKind.LIFE_RELEASED:
			life_held = false
		GameplayTypes.SemanticInputKind.DEATH_PRESSED:
			death_held = true
		GameplayTypes.SemanticInputKind.DEATH_RELEASED:
			death_held = false


func _update_carrier_held_state(sample: SemanticInputSample) -> void:
	# 载波与滑条解耦：任何玩法段按住钟都会持续发波；松开只停止未来波前。
	match sample.kind:
		GameplayTypes.SemanticInputKind.LIFE_PRESSED:
			carrier_engine.set_held(GameplayTypes.Affinity.ZHU, true, sample.timestamp_us)
		GameplayTypes.SemanticInputKind.LIFE_RELEASED:
			carrier_engine.set_held(GameplayTypes.Affinity.ZHU, false, sample.timestamp_us)
		GameplayTypes.SemanticInputKind.DEATH_PRESSED:
			carrier_engine.set_held(GameplayTypes.Affinity.XUAN, true, sample.timestamp_us)
		GameplayTypes.SemanticInputKind.DEATH_RELEASED:
			carrier_engine.set_held(GameplayTypes.Affinity.XUAN, false, sample.timestamp_us)


func _apply_tuning_frequency_changes(target_us: int, inclusive: bool) -> void:
	# TuningEngine 只在固定 tick 或真实输入时生成频率变更，因此载波序列不依赖渲染帧率。
	for change: Dictionary in tuning_engine.drain_frequency_changes():
		var change_us: int = int(change.get("time_us", target_us))
		# 改频属于这个时间戳上的输入：先推进到端点之前，再让新频率参与端点发射。
		carrier_engine.advance_to(change_us, false)
		carrier_engine.set_all_frequencies(
			float(change.get("life_frequency_hz", tuning_engine.life_frequency_hz())),
			float(change.get("death_frequency_hz", tuning_engine.death_frequency_hz())),
			change_us
		)
	carrier_engine.advance_to(target_us, inclusive)


func _process_su_manifestations(time_us: int, inclusive: bool) -> void:
	if compiled == null:
		return
	while _su_cursor < compiled.su_manifestations.size():
		var event: Dictionary = compiled.su_manifestations[_su_cursor]
		var event_us: int = int(event.get("time_us", event.get("start_us", 0)))
		if event_us > time_us or (event_us == time_us and not inclusive):
			break
		var group_id: String = str(event.get("group_id", ""))
		var group_ready: bool = tuning_engine.has_finalized_group(group_id)
		var group_success: bool = group_ready and tuning_engine.group_grade(group_id) != GameplayTypes.JudgmentGrade.MISS
		var requested_count: int = maxi(1, int(event.get("count", 1)))
		var normalized_region: Rect2 = event.get(
			"spawn_region_normalized",
			Rect2(Vector2(0.2, 0.2), Vector2(0.6, 0.6))
		)
		var points: Array[Vector2] = []
		if group_success:
			points = carrier_engine.find_constructive_intersections(
				event_us,
				normalized_region,
				requested_count
			)
		# count 是期望上限，不是“少一个就整次失败”的硬门槛；只要真实加强纹中
		# 至少存在一个合法交点，就凝成实际找到的数量。完全没有交点才播失败魂影。
		var manifested: bool = group_success and not points.is_empty()
		var result: Dictionary = {
			"event_id": str(event.get("event_id", event.get("id", ""))),
			"group_id": group_id,
			"tick": int(event.get("tick", 0)),
			"time_us": event_us,
			"requested_count": requested_count,
			"points": points if manifested else [],
			"candidate_points": points,
			# 失败时没有真实交点可画，表现层仍应在谱师声明区域内显示“未凝实”，
			# 不能退回屏幕正中央遮挡主要交互。
			"spawn_region_normalized": normalized_region,
			"success": manifested,
			"visual_variant": StringName(event.get("visual_variant", &"default")),
			"failure_reason": &"" if manifested else (
				&"group_failed" if group_ready and not group_success
				else &"group_not_finalized" if not group_ready
				else &"no_constructive_intersection"
			),
		}
		_su_manifestations.append(result)
		_su_cursor += 1


func _collect_engine_records() -> void:
	var collected: Array[JudgmentRecord] = []
	collected.append_array(note_engine.drain_judgments())
	collected.append_array(tuning_engine.drain_judgments())
	collected.append_array(rapid_engine.drain_judgments())
	# 同一微秒完成的结果必须有稳定次序，否则 Replay 摘要会随容器遍历顺序变化。
	collected.sort_custom(func(a: JudgmentRecord, b: JudgmentRecord) -> bool:
		if a.finalized_at_us != b.finalized_at_us:
			return a.finalized_at_us < b.finalized_at_us
		var rank_a: int = _unit_rank(a.unit_kind)
		var rank_b: int = _unit_rank(b.unit_kind)
		if rank_a != rank_b:
			return rank_a < rank_b
		return a.unit_id < b.unit_id
	)
	for record in collected:
		# 判定记录一产生就立即计分、扣魂火。普通音符稍后被波击破只影响表现，
		# 不会再次改判或重复计分。
		record.sequence = _judgment_sequence
		_judgment_sequence += 1
		judgments.append(record)
		_pending_judgments.append(record)
		score_engine.apply_judgment(record)
		health_engine.apply_judgment(record)


func _collect_wave_events() -> void:
	_pending_wave_launches.append_array(wave_engine.drain_launches())
	_pending_wave_contacts.append_array(wave_engine.drain_contacts())
	_pending_note_arrivals.append_array(wave_engine.drain_arrivals())


static func _unit_rank(kind: StringName) -> int:
	match kind:
		&"tap": return 0
		&"hold": return 1
		&"tuning": return 2
		&"rapid": return 3
	return 99
