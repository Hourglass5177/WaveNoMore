class_name GameplaySimulation
extends RefCounted

enum GameplayOperationKind {
	LIFE_A_PRESSED,
	LIFE_A_RELEASED,
	LIFE_B_PRESSED,
	LIFE_B_RELEASED,
	DEATH_A_PRESSED,
	DEATH_A_RELEASED,
	DEATH_B_PRESSED,
	DEATH_B_RELEASED,
	LIFE_PRESENT,
	DEATH_PRESENT,
	TUNING_DISPLACED,
	LIFE_TUNING_DISPLACED,
	DEATH_TUNING_DISPLACED,
	INPUT_CANCELLED,
	ENUM_MAX,
}

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
## 生钟当前是否由已记录的 A/B 通道持续按住；失焦时强制 false。
var life_held: bool = false
## 死钟当前是否由已记录的 A/B 通道持续按住；失焦时强制 false。
var death_held: bool = false
var _life_input_channel: int = GameplayTypes.BellInputChannel.NONE
var _death_input_channel: int = GameplayTypes.BellInputChannel.NONE
var _life_state_changed_us: int = -1
var _death_state_changed_us: int = -1
var _operation_table: Array[Dictionary] = []
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
	_life_input_channel = GameplayTypes.BellInputChannel.NONE
	_death_input_channel = GameplayTypes.BellInputChannel.NONE
	_life_state_changed_us = -1
	_death_state_changed_us = -1
	_operation_table.clear()
	for _index in range(GameplayOperationKind.ENUM_MAX):
		_operation_table.append({"exists": false, "timestamp_us": -1})
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

## 在逻辑帧内直接读取物理输入缓冲，并通过纯转换层得到玩法语义。
func process_input_frame(input_buffer: Node) -> void:
	#print("[GameplaySimulation] process_input_frame")
	_reset_operation_table()
	for physical_kind in range(GameplayTypes.PhysicalInputKind.ENUM_MAX):
		var result: Dictionary = input_buffer.query(physical_kind)
		if not bool(result.get("exists", false)):
			continue
		var physical := result.get("event") as PhysicalInputEvent
		var semantic: Dictionary = InputSemanticConverter.to_gameplay(physical)
		if not bool(semantic.get("exists", false)):
			continue
		var semantic_event: Dictionary = semantic.get("event", {})
		var source := semantic_event.get("source_event") as PhysicalInputEvent
		if source == null:
			continue
		var semantic_kind: int = int(semantic_event.get("kind", -1))
		#print("[SemanticConverter] physical=%d semantic=%d timestamp=%d sequence=%d" % [source.kind, semantic_kind, source.timestamp_us, source.sequence])
		_set_operation_from_semantic(semantic_kind, source)
	_process_operation_table()
	_set_present_operations()


func _reset_operation_table() -> void:
	for index in range(GameplayOperationKind.ENUM_MAX):
		_operation_table[index] = {"exists": false, "timestamp_us": -1}
	for kind: int in [
		GameplayOperationKind.LIFE_TUNING_DISPLACED,
		GameplayOperationKind.DEATH_TUNING_DISPLACED,
	]:
		_operation_table[kind].merge({
			"angle_rad": NAN,
			"raw_vector": Vector2.ZERO,
			"stick_released": false,
		})


func _set_operation_from_semantic(semantic_kind: int, source: PhysicalInputEvent) -> void:
	var operation_kind: int = -1
	match semantic_kind:
		InputSemanticConverter.GameplayEvent.LIFE_A_PRESSED: operation_kind = GameplayOperationKind.LIFE_A_PRESSED
		InputSemanticConverter.GameplayEvent.LIFE_A_RELEASED: operation_kind = GameplayOperationKind.LIFE_A_RELEASED
		InputSemanticConverter.GameplayEvent.LIFE_B_PRESSED: operation_kind = GameplayOperationKind.LIFE_B_PRESSED
		InputSemanticConverter.GameplayEvent.LIFE_B_RELEASED: operation_kind = GameplayOperationKind.LIFE_B_RELEASED
		InputSemanticConverter.GameplayEvent.DEATH_A_PRESSED: operation_kind = GameplayOperationKind.DEATH_A_PRESSED
		InputSemanticConverter.GameplayEvent.DEATH_A_RELEASED: operation_kind = GameplayOperationKind.DEATH_A_RELEASED
		InputSemanticConverter.GameplayEvent.DEATH_B_PRESSED: operation_kind = GameplayOperationKind.DEATH_B_PRESSED
		InputSemanticConverter.GameplayEvent.DEATH_B_RELEASED: operation_kind = GameplayOperationKind.DEATH_B_RELEASED
		InputSemanticConverter.GameplayEvent.TUNING_DISPLACED:
			_set_operation(GameplayOperationKind.TUNING_DISPLACED, source.timestamp_us, source.relative)
			return
		InputSemanticConverter.GameplayEvent.LIFE_TUNING_DISPLACED, InputSemanticConverter.GameplayEvent.DEATH_TUNING_DISPLACED:
			var angle_data: Dictionary = InputSemanticConverter.to_tuning_angle(source)
			if not bool(angle_data.get("exists", false)):
				return
			operation_kind = (
				GameplayOperationKind.LIFE_TUNING_DISPLACED
				if semantic_kind == InputSemanticConverter.GameplayEvent.LIFE_TUNING_DISPLACED
				else GameplayOperationKind.DEATH_TUNING_DISPLACED
			)
			_set_operation(operation_kind, source.timestamp_us)
			var tuning_entry: Dictionary = _operation_table[operation_kind]
			tuning_entry["angle_rad"] = float(angle_data["angle_rad"])
			tuning_entry["raw_vector"] = angle_data["raw_vector"]
			tuning_entry["stick_released"] = bool(angle_data.get("released", false))
			return
		InputSemanticConverter.GameplayEvent.INPUT_CANCELLED: operation_kind = GameplayOperationKind.INPUT_CANCELLED
	if operation_kind >= 0:
		_set_operation(operation_kind, source.timestamp_us)


func _set_operation(kind: int, timestamp_us: int, displacement: Vector2 = Vector2.ZERO) -> void:
	var entry: Dictionary = _operation_table[kind]
	if not bool(entry.get("exists", false)) or timestamp_us < int(entry.get("timestamp_us", -1)):
		entry["exists"] = true
		entry["timestamp_us"] = timestamp_us
		if kind == GameplayOperationKind.TUNING_DISPLACED:
			entry["displacement"] = displacement


func _set_present_operations() -> void:
	_set_operation(GameplayOperationKind.LIFE_PRESENT, _life_state_changed_us if life_held else -1)
	_operation_table[GameplayOperationKind.LIFE_PRESENT]["exists"] = life_held
	_set_operation(GameplayOperationKind.DEATH_PRESENT, _death_state_changed_us if death_held else -1)
	_operation_table[GameplayOperationKind.DEATH_PRESENT]["exists"] = death_held
	_operation_table[GameplayOperationKind.LIFE_PRESENT]["exists"] = life_held
	_operation_table[GameplayOperationKind.LIFE_PRESENT]["timestamp_us"] = _life_state_changed_us
	_operation_table[GameplayOperationKind.DEATH_PRESENT]["exists"] = death_held
	_operation_table[GameplayOperationKind.DEATH_PRESENT]["timestamp_us"] = _death_state_changed_us


func _process_operation_table() -> void:
	var operations: Array[int] = [
		GameplayOperationKind.LIFE_A_PRESSED,
		GameplayOperationKind.LIFE_A_RELEASED,
		GameplayOperationKind.LIFE_B_PRESSED,
		GameplayOperationKind.LIFE_B_RELEASED,
		GameplayOperationKind.DEATH_A_PRESSED,
		GameplayOperationKind.DEATH_A_RELEASED,
		GameplayOperationKind.DEATH_B_PRESSED,
		GameplayOperationKind.DEATH_B_RELEASED,
		GameplayOperationKind.TUNING_DISPLACED,
		GameplayOperationKind.LIFE_TUNING_DISPLACED,
		GameplayOperationKind.DEATH_TUNING_DISPLACED,
		GameplayOperationKind.INPUT_CANCELLED,
	]
	operations = operations.filter(func(kind: int) -> bool:
		return bool(_operation_table[kind].get("exists", false))
	)
	operations.sort_custom(func(a: int, b: int) -> bool:
		var a_time: int = int(_operation_table[a]["timestamp_us"])
		var b_time: int = int(_operation_table[b]["timestamp_us"])
		return a < b if a_time == b_time else a_time < b_time
	)
	for operation_kind in operations:
		var entry: Dictionary = _operation_table[operation_kind]
		if not bool(entry.get("exists", false)):
			continue
		var semantic_kind: int = GameplayTypes.SemanticInputKind.FOCUS_CANCELLED
		match operation_kind:
			GameplayOperationKind.LIFE_A_PRESSED: semantic_kind = GameplayTypes.SemanticInputKind.LIFE_A_PRESSED
			GameplayOperationKind.LIFE_A_RELEASED: semantic_kind = GameplayTypes.SemanticInputKind.LIFE_A_RELEASED
			GameplayOperationKind.LIFE_B_PRESSED: semantic_kind = GameplayTypes.SemanticInputKind.LIFE_B_PRESSED
			GameplayOperationKind.LIFE_B_RELEASED: semantic_kind = GameplayTypes.SemanticInputKind.LIFE_B_RELEASED
			GameplayOperationKind.DEATH_A_PRESSED: semantic_kind = GameplayTypes.SemanticInputKind.DEATH_A_PRESSED
			GameplayOperationKind.DEATH_A_RELEASED: semantic_kind = GameplayTypes.SemanticInputKind.DEATH_A_RELEASED
			GameplayOperationKind.DEATH_B_PRESSED: semantic_kind = GameplayTypes.SemanticInputKind.DEATH_B_PRESSED
			GameplayOperationKind.DEATH_B_RELEASED: semantic_kind = GameplayTypes.SemanticInputKind.DEATH_B_RELEASED
			GameplayOperationKind.TUNING_DISPLACED: semantic_kind = GameplayTypes.SemanticInputKind.TUNING_DISPLACED
		var vector: Vector2 = entry.get("displacement", Vector2.ZERO)
		#print("[GameplayTable] operation=%d timestamp=%d" % [operation_kind, int(entry["timestamp_us"])])
		if operation_kind == GameplayOperationKind.TUNING_DISPLACED:
			accept_input(SemanticInputSample.create(int(entry["timestamp_us"]), 0, semantic_kind, vector))
			continue
		if operation_kind in [
			GameplayOperationKind.LIFE_TUNING_DISPLACED,
			GameplayOperationKind.DEATH_TUNING_DISPLACED,
		]:
			var affinity: int = (
				GameplayTypes.Affinity.ZHU
				if operation_kind == GameplayOperationKind.LIFE_TUNING_DISPLACED
				else GameplayTypes.Affinity.XUAN
			)
			tuning_engine.apply_absolute_side(
				affinity,
				float(entry.get("angle_rad", NAN)),
				int(entry["timestamp_us"]),
				life_held if affinity == GameplayTypes.Affinity.ZHU else death_held,
				bool(entry.get("stick_released", false))
			)
			continue
		accept_input(SemanticInputSample.create(int(entry["timestamp_us"]), 0, semantic_kind, vector))
func accept_input(sample: SemanticInputSample) -> int:
	if sample == null or compiled == null or rules == null or health_engine.failed or _paused_for_rearm:
		return GameplayTypes.InputOwner.NONE
	#print("[GameplayCore] semantic kind=%d timestamp=%d" % [sample.kind, sample.timestamp_us])
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
		_life_input_channel = GameplayTypes.BellInputChannel.NONE
		_death_input_channel = GameplayTypes.BellInputChannel.NONE
		note_engine.cancel_active(sample.timestamp_us)
		tuning_engine.cancel_active(sample.timestamp_us)
		rapid_engine.cancel_active(sample.timestamp_us)
		_last_input_owner = GameplayTypes.InputOwner.NONE
		_collect_engine_records()
		return _last_input_owner
	_update_held_state(sample)
	carrier_engine.handle_bell_input(sample)
	tuning_engine.handle_bell_input(sample)
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
		#print("[NoteDispatch] consumed=%s owner=%d timestamp=%d" % [str(consumed), _last_input_owner, sample.timestamp_us])
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
		#print("[WaveDispatch] qualified=%s owner=%d timestamp=%d" % [str(wave_qualified), _last_input_owner, sample.timestamp_us])
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
	_life_input_channel = _rearm_channel(rearm_state, true, _life_input_channel)
	_death_input_channel = _rearm_channel(rearm_state, false, _death_input_channel)
	life_held = _life_input_channel != GameplayTypes.BellInputChannel.NONE
	death_held = _death_input_channel != GameplayTypes.BellInputChannel.NONE
	carrier_engine.resume_after_pause(_life_input_channel, _death_input_channel, current_time_us)
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
	if not sample.is_press() and not sample.is_release():
		return
	var affinity: int = sample.affinity()
	var channel: int = sample.input_channel()
	if affinity == GameplayTypes.Affinity.ZHU:
		if sample.is_press() and _life_input_channel == GameplayTypes.BellInputChannel.NONE:
			_life_input_channel = channel
			life_held = true
			_life_state_changed_us = sample.timestamp_us
		elif sample.is_release() and _life_input_channel == channel:
			_life_input_channel = GameplayTypes.BellInputChannel.NONE
			life_held = false
			_life_state_changed_us = sample.timestamp_us
	elif affinity == GameplayTypes.Affinity.XUAN:
		if sample.is_press() and _death_input_channel == GameplayTypes.BellInputChannel.NONE:
			_death_input_channel = channel
			death_held = true
			_death_state_changed_us = sample.timestamp_us
		elif sample.is_release() and _death_input_channel == channel:
			_death_input_channel = GameplayTypes.BellInputChannel.NONE
			death_held = false
			_death_state_changed_us = sample.timestamp_us


## 暂停恢复只重新建立暂停前记录的通道，不让另一通道抢占持续状态。
func _rearm_channel(rearm_state: Dictionary, life: bool, required_channel: int) -> int:
	if required_channel == GameplayTypes.BellInputChannel.NONE:
		return GameplayTypes.BellInputChannel.NONE
	var prefix: String = "life" if life else "death"
	var suffix: String = "a" if required_channel == GameplayTypes.BellInputChannel.A else "b"
	return required_channel if bool(rearm_state.get(prefix + "_" + suffix + "_held", false)) else GameplayTypes.BellInputChannel.NONE


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
