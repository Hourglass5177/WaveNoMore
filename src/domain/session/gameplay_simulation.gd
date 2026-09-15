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

## 同一次领域推进内复用只读运动状态；新输入或推进会整体替换缓存。
var _motion_cache: Dictionary = {}
## 本局编译谱；configure 后只读，所有机制共用其中的确定性微秒时间轴。
var compiled: CompiledChart
## 本局规则表；判定窗、计分、魂火和物理坐标均从此读取。
var rules: GameplayRuleSet
var pet_effect := PetEffectProfile.new()
## 实际伤害与随从表现事件分别排出，表现不反向参与结算。
var damages: Array[DamageRecord] = []
var _pending_damages: Array[DamageRecord] = []
## 只在 Hold 失败时生成剩余身体结算点，按微秒排序；不逐帧扫描全谱身体。
var _hold_body_damages: Array[DamageRecord] = []
var _hold_damage_cursor := 0
var _pending_pet_triggers: Array[Dictionary] = []
var _notes_by_id: Dictionary = {}
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
var boss_battle := BossBattleEngine.new()
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
var _su_prepare_order: Array[Dictionary] = []
var _su_prepare_cursor := 0
var _ghost_forecast := GhostWaveForecast.new()
## 素音预读等待表与已冻结的 UV 目标，均按事件 ID 独立保存。
var _su_events_by_id: Dictionary[String, Dictionary] = {}
var _su_prepared: Dictionary[String, Dictionary] = {}
var _su_resolved_ids: Dictionary[String, bool] = {}
## 分配给下一条 JudgmentRecord 的全局递增序号；同微秒也不会重复。
var _judgment_sequence: int = 0
## 最近一次输入的 InputOwner；NONE 表示未被任何机制消费。
var _last_input_owner: int = GameplayTypes.InputOwner.NONE
## 暂停后等待重新确认按键状态的标志；为 true 时拒收普通玩法输入。
var _paused_for_rearm: bool = false
## 非致死调试标志；为 true 时魂火可为负，但 HealthEngine 不进入 failed。
var _debug_nonlethal: bool = false
## 只累计新记录；实时 HUD 不必每帧重新扫描整局历史。
var _summary_judgments := 0
var _summary_strays := 0
var _summary_misses := 0
var _summary_nonperfect := 0
var _summary_stray_breaks := 0
var _su_results_snapshot: Array = []
var _su_targets_snapshot: Array = []


func configure(p_compiled: CompiledChart, p_rules: GameplayRuleSet, debug_nonlethal: bool = false, pet: PetEffectProfile = null) -> void:
	_motion_cache = {}
	compiled = p_compiled
	rules = p_rules
	_debug_nonlethal = debug_nonlethal
	pet_effect = pet.duplicate(true) as PetEffectProfile if pet != null else PetEffectProfile.new()
	damages.clear()
	_pending_damages.clear()
	_hold_body_damages.clear()
	_hold_damage_cursor = 0
	_notes_by_id.clear()
	_pending_pet_triggers.clear()
	for note: Dictionary in compiled.notes: _notes_by_id[str(note.id)] = note
	note_engine.configure(compiled, rules, pet_effect)
	tuning_engine.configure(compiled, rules)
	rapid_engine.configure(compiled, rules)
	wave_engine.configure(compiled, rules)
	carrier_engine.configure(rules)
	score_engine.configure(rules, pet_effect)
	health_engine.configure(rules, _debug_nonlethal, pet_effect)
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
	boss_battle.reset()
	strays.clear()
	_summary_judgments = 0; _summary_strays = 0
	_summary_misses = 0; _summary_nonperfect = 0; _summary_stray_breaks = 0
	_su_results_snapshot = []; _su_targets_snapshot = []
	_pending_judgments.clear()
	_pending_strays.clear()
	_pending_wave_launches.clear()
	_pending_wave_contacts.clear()
	_pending_note_arrivals.clear()
	_su_manifestations.clear()
	_su_cursor = 0
	_su_prepare_order.clear(); _su_prepare_cursor = 0
	_ghost_forecast.configure(compiled, rules)
	_su_events_by_id.clear()
	_su_prepared.clear()
	_su_resolved_ids.clear()
	for event: Dictionary in compiled.su_manifestations:
		var prepared_event := event.duplicate()
		prepared_event["prepare_at_us"] = int(event.get("preparation_base_us",event.time_us)) - roundi((rules.approach_duration_sec + rules.ghost_preview_extra_sec) * 1000000.0)
		# 旧资源没有路径关联时，用显式组或覆盖目标时刻的旧滑条作为关联。
		var ids := PackedStringArray(event.get("tuning_ids", []))
		if ids.is_empty():
			for slider: Dictionary in compiled.tuning_sliders:
				if (not str(event.get("group_id", "")).is_empty() and str(slider.group_id) == str(event.group_id)) or (str(event.get("group_id", "")).is_empty() and int(slider.start_us) <= int(event.time_us) and int(event.time_us) <= int(slider.end_us)):
					ids.append(str(slider.event_id))
		prepared_event["tuning_ids"] = ids
		_su_events_by_id[str(event.event_id)] = prepared_event
		_su_prepare_order.append(prepared_event)
	_su_prepare_order.sort_custom(func(a: Dictionary,b: Dictionary): return int(a.prepare_at_us)<int(b.prepare_at_us) if a.prepare_at_us != b.prepare_at_us else str(a.event_id)<str(b.event_id))
	_judgment_sequence = 0
	_last_input_owner = GameplayTypes.InputOwner.NONE
	_paused_for_rearm = false


func reset() -> void:
	configure(compiled, rules, _debug_nonlethal, pet_effect)


func advance_to(time_us: int, inclusive: bool = true) -> void:
	if compiled == null or rules == null or time_us < current_time_us:
		return
	if not _paused_for_rearm and not health_engine.failed:
		var boundary_us: int = _next_boundary_us()
		while boundary_us < time_us and not health_engine.failed:
			_advance_systems_to(boundary_us, true)
			boundary_us = _next_boundary_us()
	_advance_systems_to(time_us, inclusive)


## 同刻先结算调频端点，再退出 Hold，最后同步拖动资格并应用频率变化。
func _advance_systems_to(time_us: int, inclusive: bool) -> void:
	_motion_cache = {}
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
	note_engine.advance_to(time_us, inclusive)
	tuning_engine.set_dual_holding_notes(note_engine.has_dual_holding_notes(), time_us)
	_apply_tuning_frequency_changes(time_us, inclusive)
	_process_su_manifestations(time_us, inclusive)
	_collect_engine_records()
	_collect_wave_events()
	boss_battle.advance(time_us, inclusive, note_engine, tuning_engine)
	while _hold_damage_cursor < _hold_body_damages.size():
		var damage := _hold_body_damages[_hold_damage_cursor]
		if damage.timestamp_us > time_us or (damage.timestamp_us == time_us and not inclusive): break
		_apply_damage(damage)
		_hold_damage_cursor += 1


func _next_boundary_us() -> int:
	var boundary := mini(note_engine.next_transition_us(), wave_engine.next_arrival_us())
	boundary = mini(boundary, boss_battle.next_boundary_us())
	if _hold_damage_cursor < _hold_body_damages.size(): boundary = mini(boundary, _hold_body_damages[_hold_damage_cursor].timestamp_us)
	if _su_cursor < compiled.su_manifestations.size(): boundary = mini(boundary, int(compiled.su_manifestations[_su_cursor].time_us))
	if _su_prepare_cursor < _su_prepare_order.size(): boundary = mini(boundary, int(_su_prepare_order[_su_prepare_cursor].prepare_at_us))
	return boundary


func last_damage_time_us() -> int:
	## 提前预留失败 Hold 的尾部飞行，歌曲/Replay 不可在身体扣血前结束。
	var result := wave_engine.last_arrival_us()
	for note: Dictionary in compiled.notes:
		if note.unit_kind == &"hold":
			result = maxi(result, int(note.end_us) + wave_engine.post_cue_travel_us(int(note.affinity)) + (rules.hold_sustain_grace_ms + pet_effect.hold_sustain_bonus_ms) * 1000 + 1)
	return result


func _schedule_hold_damage(record: JudgmentRecord) -> void:
	var note: Dictionary = _notes_by_id[record.unit_id]
	var tempo := compiled.tempo_map
	var from_us: int = int(record.metadata.unconsumed_from_us)
	var from_tick := clampf(tempo.us_to_tick(from_us), float(note.tick), float(note.end_tick))
	var segment_ticks := maxf(1.0, rules.hold_damage_segment_beats * tempo.ppq)
	# 未起手沿原路线抵达；断持后从失败时刻离圈，统一使用领域飞行时长。
	var arrival_us := (int(note.start_us) if record.missed_head() else record.finalized_at_us) + wave_engine.post_cue_travel_us(record.affinity)
	record.metadata["body_from_tick"] = from_tick
	record.metadata["body_arrival_us"] = arrival_us
	record.metadata["body_end_arrival_us"] = arrival_us + int(note.end_us) - from_us
	# 第一段和最后一段不足单位拍长时按实际拍长累计取整，避免每个碎段都向上扣血。
	var cursor_tick := from_tick
	var charged := 0
	var segment := floori((from_tick - float(note.tick)) / segment_ticks)
	while cursor_tick < float(note.end_tick):
		var end_tick := minf(float(note.end_tick), float(note.tick) + (segment + 1) * segment_ticks)
		var total := roundi((end_tick - from_tick) / segment_ticks * rules.hold_segment_damage)
		var amount := total - charged
		var tick_floor := floori(end_tick)
		var segment_end_us := tempo.tick_to_us(tick_floor) + roundi((end_tick - tick_floor) * (tempo.tick_to_us(tick_floor + 1) - tempo.tick_to_us(tick_floor)))
		if amount > 0:
			var id := "%s:body:%d" % [record.unit_id, segment]
			var group := "hold:%s:body:%d" % [record.damage_group_id, segment]
			_hold_body_damages.append(DamageRecord.create(id, group, maxi(record.finalized_at_us, arrival_us + segment_end_us - from_us), amount, record.affinity))
		charged = total
		cursor_tick = end_tick
		segment += 1
	# 已消费前缀不再排序，也不影响新失败音符的同刻稳定顺序。
	_hold_body_damages = _hold_body_damages.slice(_hold_damage_cursor)
	_hold_damage_cursor = 0
	_hold_body_damages.sort_custom(func(a: DamageRecord, b: DamageRecord) -> bool:
		return a.timestamp_us < b.timestamp_us if a.timestamp_us != b.timestamp_us else a.source_id < b.source_id)

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
			"control_vector": Vector2.ZERO,
			"raw_vector": Vector2.ZERO,
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
			var control_data: Dictionary = InputSemanticConverter.to_tuning_control(source, rules.tuning_stick_deadzone)
			if not bool(control_data.get("exists", false)):
				return
			operation_kind = (
				GameplayOperationKind.LIFE_TUNING_DISPLACED
				if semantic_kind == InputSemanticConverter.GameplayEvent.LIFE_TUNING_DISPLACED
				else GameplayOperationKind.DEATH_TUNING_DISPLACED
			)
			_set_operation(operation_kind, source.timestamp_us)
			var tuning_entry: Dictionary = _operation_table[operation_kind]
			tuning_entry["control_vector"] = control_data["control_vector"]
			tuning_entry["raw_vector"] = control_data["raw_vector"]
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
			var timestamp_us: int = int(entry["timestamp_us"])
			if timestamp_us < current_time_us:
				continue
			advance_to(timestamp_us, false)
			tuning_engine.set_stick_control(
				affinity,
				entry["control_vector"],
				timestamp_us
			)
			continue
		accept_input(SemanticInputSample.create(int(entry["timestamp_us"]), 0, semantic_kind, vector))
func accept_input(sample: SemanticInputSample) -> int:
	_motion_cache = {}
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
	if health_engine.failed: return GameplayTypes.InputOwner.NONE
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
	# 调频只消费位移，A/B 敲击仍交给 Hold；双 Hold 条件由领域状态同步。
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
	tuning_engine.set_dual_holding_notes(note_engine.has_dual_holding_notes(), sample.timestamp_us)
	if not consumed and sample.is_press():
		var stray := StrayInputRecord.create(sample, rules)
		strays.append(stray)
		_pending_strays.append(stray)
		score_engine.apply_stray(stray)
		if stray.damages:
			# 帧输入适配器可能复用 sequence；本局乱按记录序号区分每次独立受击。
			var damage_id := "stray:%d" % (strays.size() - 1)
			_apply_damage(DamageRecord.create(damage_id, damage_id, sample.timestamp_us, rules.stray_input_damage, sample.affinity()))
	# 所有按下都会产生真实传播的波。机制认可时发红/黑彩波，乱按发灰波；
	# 普通音符还会把唯一目标绑定给波，等待两者实际相遇。
	if sample.is_press():
		var bound_note: Dictionary = {}
		if consumed and _last_input_owner == GameplayTypes.InputOwner.NOTE:
			bound_note = note_engine.last_press_binding()
		# 起手绑定只在新接住音符时产生；续按、暂停重臂不会重复发出技能。
		if bound_note.get("unit_kind", &"") == &"hold" and (pet_effect.hold_head_bonus_ms > 0 or pet_effect.hold_sustain_bonus_ms > 0 or pet_effect.hold_grade_boost > 0):
			_queue_pet_trigger(sample.timestamp_us, int(bound_note.affinity))
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
	_motion_cache = {}
	if compiled == null:
		return
	# Hold 与调频都在谱面尾点完成；只有普通音符还需等待 Miss 窗。
	var settle_us: int = (rules.miss_window_ms + pet_effect.hold_head_bonus_ms) * 1000 + 1
	advance_to(maxi(compiled.end_time_us + settle_us, last_damage_time_us()), true)
	_collect_wave_events()


func begin_pause_rearm() -> Dictionary:
	_motion_cache = {}
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
	_motion_cache = {}
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
	# 最后一条 Hold 可以先取得 Pass，再抵达角色；伤害未结清时不能宣布通关。
	return ResultEvaluator.evaluate(judgments, strays, score_engine, health_engine,
		compiled.theoretical_unit_count, wave_engine.next_arrival_us() == 9223372036854775807 and _hold_damage_cursor == _hold_body_damages.size() and _su_cursor == compiled.su_manifestations.size())


func input_owner() -> int:
	if rapid_engine.is_active_at(current_time_us):
		return GameplayTypes.InputOwner.RAPID
	if tuning_engine.is_active():
		return GameplayTypes.InputOwner.TUNING
	if note_engine.has_active_hold():
		return GameplayTypes.InputOwner.NOTE
	return _last_input_owner


func motion_snapshot() -> Dictionary:
	## 重演身体只依赖当前控制状态，无需反复扫描整场成绩和载波历史。
	if not _motion_cache.is_empty(): return _motion_cache
	var profile_started := GameplayFrameProfile.begin()
	var result := {
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
		"dual_holding_notes": note_engine.has_dual_holding_notes(),
		"life_holding_note_id": note_engine.holding_note_id(GameplayTypes.Affinity.ZHU),
		"death_holding_note_id": note_engine.holding_note_id(GameplayTypes.Affinity.XUAN),
		"life_perfect_holding": note_engine.has_perfect_holding_note(GameplayTypes.Affinity.ZHU),
		"death_perfect_holding": note_engine.has_perfect_holding_note(GameplayTypes.Affinity.XUAN),
		"active_hold_ids": note_engine.active_hold_ids(),
		"held_hold_ids": note_engine.active_hold_ids(true),
	}

	GameplayFrameProfile.end(&"motion_snapshot", profile_started)
	_motion_cache = result
	return result


func snapshot() -> Dictionary:
	while _summary_judgments < judgments.size():
		var grade := judgments[_summary_judgments].grade
		if grade == GameplayTypes.JudgmentGrade.MISS: _summary_misses += 1
		if grade != GameplayTypes.JudgmentGrade.PERFECT: _summary_nonperfect += 1
		_summary_judgments += 1
	while _summary_strays < strays.size():
		if strays[_summary_strays].breaks_combo: _summary_stray_breaks += 1
		_summary_strays += 1
	if _su_results_snapshot.size() != _su_manifestations.size():
		_su_results_snapshot = _su_manifestations.duplicate(true)
	if _su_targets_snapshot.size() != _su_prepared.size():
		_su_targets_snapshot = _su_prepared.values().duplicate(true)
	var cleared := not health_engine.failed and judgments.size() == compiled.theoretical_unit_count and wave_engine.next_arrival_us() == 9223372036854775807 and _hold_damage_cursor == _hold_body_damages.size() and _su_cursor == compiled.su_manifestations.size()
	var full_combo := cleared and _summary_misses == 0 and _summary_stray_breaks == 0
	var result := motion_snapshot().duplicate(false)
	result.merge({
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
		"su_manifestations": _su_results_snapshot,
		"su_prepared_targets": _su_targets_snapshot,
		"paused_for_rearm": _paused_for_rearm,
		"cleared": cleared,
		"fc": full_combo,
		"ap": full_combo and not judgments.is_empty() and _summary_nonperfect == 0,
		"miss_count": _summary_misses,
		"expected_judgment_count": compiled.theoretical_unit_count,
		"content_hash": compiled.content_hash,
	})
	return result


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


func request_su_preparation(_event_id: String) -> void:
	## 保留表现调度器旧接口；生成时刻已由领域固定时间线掌管。
	pass


func reset_su_timeline(time_us: int) -> void:
	_su_results_snapshot = []; _su_targets_snapshot = []
	## Seek/清场丢弃旧目标；早于新时间的事件不再生成结果或打印历史 Miss。
	_su_prepared.clear()
	_su_manifestations.clear()
	_su_resolved_ids.clear()
	_su_cursor = 0
	while _su_cursor < compiled.su_manifestations.size():
		var event: Dictionary = compiled.su_manifestations[_su_cursor]
		if int(event["time_us"]) >= time_us:
			break
		_su_resolved_ids[str(event["event_id"])] = true
		_su_cursor += 1
	# 无输入的自由定位从新暂态预测尚未结算的事件；完整 Replay 仍从头重演固定边界。
	_su_prepare_order = _su_prepare_order.filter(func(event: Dictionary): return int(event.time_us) >= time_us)
	_su_prepare_cursor = 0
	for event: Dictionary in _su_prepare_order: event.prepare_at_us = maxi(time_us,int(event.prepare_at_us))


func clear_su_targets() -> void:
	_su_results_snapshot = []; _su_targets_snapshot = []
	## 会话结束释放预读请求、目标、结果和去重状态，不改变其他玩法数据。
	_su_prepared.clear()
	_su_manifestations.clear()
	_su_resolved_ids.clear()
	_su_prepare_cursor = _su_prepare_order.size()


func _try_prepare_su(event: Dictionary, prepared_at_us: int) -> void:
	## 固定暂态只预测一次，包含理想调频的未来发波；正式载波与输入不被改写。
	var event_id: String = str(event["event_id"])
	if _su_prepared.has(event_id):
		return
	var forecast := _ghost_forecast.predict(carrier_engine, prepared_at_us, int(event.time_us))
	var points := forecast.find_constructive_intersections(int(event.time_us), event.spawn_region_normalized, int(event.count), 120.0, hash("%s:%d" % [event_id,int(event.time_us)]), true)
	var points_uv: Array[Vector2] = []
	for point: Vector2 in points:
		points_uv.append(carrier_engine.canvas_position_to_uv(point))
	var target: Dictionary = event.duplicate(true)
	target["points"] = points_uv
	target["requested_count"] = int(event["count"])
	target["prepared_at_us"] = prepared_at_us
	target["visible_from_us"] = int(event.time_us) - roundi((rules.approach_duration_sec + rules.ghost_preview_extra_sec) * 1000000.0) if rules != null else prepared_at_us
	target["generation_issue"] = &"insufficient_predicted_intersections" if points.size() < int(event.count) else &""
	_su_prepared[event_id] = target


func _process_su_manifestations(time_us: int, inclusive: bool) -> void:
	## 预测由领域固定边界驱动；表现请求和渲染帧不能决定暂态采样时刻。
	if compiled == null:
		return
	while _su_prepare_cursor < _su_prepare_order.size():
		var event: Dictionary = _su_prepare_order[_su_prepare_cursor]
		var prepare_us := int(event.prepare_at_us)
		if prepare_us > time_us or (prepare_us == time_us and not inclusive): break
		if not _su_resolved_ids.has(str(event.event_id)): _try_prepare_su(event,prepare_us)
		_su_prepare_cursor += 1
	while _su_cursor < compiled.su_manifestations.size():
		var original: Dictionary = compiled.su_manifestations[_su_cursor]
		var event: Dictionary = _su_events_by_id.get(str(original.event_id),original)
		var event_us: int = int(event["time_us"])
		if event_us > time_us or (event_us == time_us and not inclusive):
			break
		var event_id: String = str(event["event_id"])
		var result: Dictionary = event.duplicate(true)
		var target: Dictionary = _su_prepared.get(event_id, {})
		result["points"] = target.get("points", []).duplicate()
		result["requested_count"] = int(event["count"])
		result["generation_issue"] = target.get("generation_issue", &"prediction_not_prepared")
		# 数量与失败原因已在快照中；控制台可能阻塞主线程，诊断仅在 --verbose 时输出。
		if not String(result["generation_issue"]).is_empty():
			print_verbose("[SuManifestation] target_shortage event=%s requested=%d actual=%d reason=%s" % [event_id, int(event["count"]), result["points"].size(), result["generation_issue"]])
		# 固定编排数量按关联调频操作共同评价；缺少预测坐标只报告生成问题，不能变成扣血依据。
		var grade := tuning_engine.ghost_grade(PackedStringArray(event.get("tuning_ids",[])),event_us)
		result["grade"] = grade
		result["hit_count"] = int(event.count) if grade != GameplayTypes.JudgmentGrade.MISS else 0
		result["miss_count"] = int(event.count) - int(result.hit_count)
		result["success"] = int(result["miss_count"]) == 0
		result["failure_reason"] = &"" if result["success"] else &"tuning_incomplete"
		for index: int in range(int(result["hit_count"]), int(event["count"])):
			var damage_id := "%s:ghost:%d" % [event_id, index]
			_apply_damage(DamageRecord.create(damage_id, damage_id, event_us, rules.ghost_miss_damage))
		_su_manifestations.append(result)
		_su_resolved_ids[event_id] = true
		if not bool(result["success"]):
			print_verbose("[SuManifestation] note_miss event=%s requested=%d actual=%d reason=%s uv=none" % [
				event_id, int(event["count"]), result["points"].size(), result["failure_reason"]
			])
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
		if health_engine.failed: break
		# 得分提档只发生一次，机械结果保留给受击和表现；未起手音符等待实际抵达。
		record.sequence = _judgment_sequence
		_judgment_sequence += 1
		record.base_grade = record.grade
		record.grade = pet_effect.promote(record.base_grade, record.unit_kind)
		judgments.append(record)
		boss_battle.observe(record)
		_pending_judgments.append(record)
		var old_bonus := score_engine.bonus_score
		score_engine.apply_judgment(record)
		if score_engine.bonus_score > old_bonus: _queue_pet_trigger(record.finalized_at_us, record.affinity)
		if record.base_grade == GameplayTypes.JudgmentGrade.MISS and record.unit_kind == &"hold":
			_schedule_hold_damage(record)
		# Tuning 只计分，不造成伤害；Tap 等待抵达，Hold 等待剩余身体逐段抵达。


func _collect_wave_events() -> void:
	_pending_wave_launches.append_array(wave_engine.drain_launches())
	for contact: Dictionary in wave_engine.drain_contacts():
		_pending_wave_contacts.append(contact)
		boss_battle.resolve_contact(str(contact.note_id),int(contact.contact_us))
	for arrival: Dictionary in wave_engine.drain_arrivals():
		_pending_note_arrivals.append(arrival)
		boss_battle.resolve_contact(str(arrival.note_id),int(arrival.arrival_us))
		var note: Dictionary = _notes_by_id[str(arrival.note_id)]
		if note.unit_kind == &"tap":
			_apply_damage(DamageRecord.create(str(arrival.note_id), "tap:" + str(note.damage_group_id), int(arrival.arrival_us), rules.tap_miss_damage, int(note.affinity)))


static func _unit_rank(kind: StringName) -> int:
	match kind:
		&"tap": return 0
		&"hold": return 1
		&"tuning": return 2
		&"rapid": return 3
	return 99


func _apply_damage(record: DamageRecord) -> void:
	if health_engine.failed or health_engine.has_damage_group(record.group_id): return
	health_engine.apply_damage(record)
	record.fatal = health_engine.failed
	damages.append(record)
	_pending_damages.append(record)
	if not record.fatal and pet_effect.damage_reduction > 0.0 and record.base_damage > record.actual_damage:
		_queue_pet_trigger(record.timestamp_us, record.affinity)


func drain_damages() -> Array[DamageRecord]:
	var result := _pending_damages
	_pending_damages = []
	return result


func _queue_pet_trigger(time_us: int, side: int) -> void:
	_pending_pet_triggers.append({"timestamp_us": time_us, "affinity": side})


func drain_pet_triggers() -> Array[Dictionary]:
	var result := _pending_pet_triggers
	_pending_pet_triggers = []
	return result
