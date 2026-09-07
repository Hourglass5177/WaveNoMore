class_name GameplayCoordinator
extends Node

## GameplaySimulation 与场景树之间的轻量连接层。这里只把玩法逻辑事件转成信号，
## 不放置判定、计分、魂火、调频或疾振规则。

## 玩法内核生成一条正式判定记录时发出。
signal judgment_recorded(record: JudgmentRecord)
## 一次输入没有被任何合法玩法对象接收时发出。
signal stray_input_recorded(record: StrayInputRecord)
## 生钟或死钟发出一个具有真实传播时间的声波时发出。
signal wave_launched(wave: Dictionary)
## 波前在物理时间线上接触音符时发出。
signal wave_contacted(contact: Dictionary)
## 音符未被波前消灭、继续飞到角色位置时发出。
signal note_arrived(arrival: Dictionary)
## 重开后所有旧波和接触记录均已失效，表现层应清空波纹。
signal waves_reset
## 可供 HUD 和表现层读取的玩法快照变化时发出；传出的是深拷贝。
signal snapshot_changed(snapshot: Dictionary)
## 当前输入所有权变化时发出；`owner` 是 GameplayTypes.InputOwner 枚举值。
signal input_owner_changed(owner: int)
## 调频开始或结束时发出；开始时同时给出当前游标的初值。
signal tuning_capture_changed(active: bool, initial_value: Vector2)
## 缺少编译谱或规则等致命配置问题时发出。
signal fatal_configuration_error(message: String)

## 不依赖场景树的确定性玩法内核，负责判定、波传播、分数、魂火、调频和疾振。
var simulation: GameplaySimulation
## `configure()` 是否已成功完成；为 false 时所有推进和输入接口都直接返回。
var configured: bool = false

## 最近一次从玩法内核取得的完整快照，向外返回时仍会复制，避免被表现层修改。
var _last_snapshot: Dictionary = {}
## 上次已发布的输入所有权，用于只在实际变化时发送信号。
var _last_owner: int = GameplayTypes.InputOwner.NONE
## 上次已发布的调频接管状态，防止每帧重复切换鼠标捕获。
var _tuning_capture_active: bool = false


func configure(compiled_chart: CompiledChart, rule_set: GameplayRuleSet, debug_nonlethal: bool = false) -> bool:
	configured = false
	if compiled_chart == null:
		fatal_configuration_error.emit("GameplayCoordinator requires a CompiledChart.")
		return false
	if rule_set == null:
		fatal_configuration_error.emit("GameplayCoordinator requires a GameplayRuleSet.")
		return false

	simulation = GameplaySimulation.new()
	if not simulation.has_method("configure"):
		fatal_configuration_error.emit("GameplaySimulation.configure() is unavailable.")
		return false

	simulation.configure(compiled_chart, rule_set, debug_nonlethal)
	configured = true
	_refresh_snapshot()
	return true


func reset() -> void:
	if not configured or simulation == null:
		return
	simulation.reset()
	waves_reset.emit()
	_last_snapshot = {}
	_last_owner = GameplayTypes.InputOwner.NONE
	_tuning_capture_active = false
	input_owner_changed.emit(_last_owner)
	tuning_capture_changed.emit(false, Vector2.ZERO)
	_refresh_snapshot()


func accept_input(sample: SemanticInputSample) -> void:
	if not configured or simulation == null or sample == null:
		return
	simulation.accept_input(sample)
	_drain_domain_events()
	_refresh_snapshot()

## 逻辑帧入口：玩法内核自主查询 InputEventBuffer 并处理当前帧物理输入。
func process_input_frame() -> void:
	#print("[GameplayCoordinator] process_input_frame configured=%s" % str(configured))
	if not configured or simulation == null:
		return
	simulation.process_input_frame()
	_drain_domain_events()
	_refresh_snapshot()


func advance_to(timestamp_us: int, inclusive: bool = true) -> void:
	if not configured or simulation == null:
		return
	simulation.advance_to(timestamp_us, inclusive)
	_drain_domain_events()
	_refresh_snapshot()


func begin_pause_rearm() -> Dictionary:
	if not configured or simulation == null:
		return {}
	var rearm_state: Dictionary = {}
	if simulation.has_method("begin_pause_rearm"):
		var result: Variant = simulation.call("begin_pause_rearm")
		if result is Dictionary:
			rearm_state = result
	elif simulation.has_method("suspend_for_pause"):
		var legacy_result: Variant = simulation.call("suspend_for_pause")
		if legacy_result is Dictionary:
			rearm_state = legacy_result
	_refresh_snapshot()
	return rearm_state


func apply_resume_rearm(held_snapshot: Dictionary) -> void:
	if not configured or simulation == null:
		return
	if simulation.has_method("apply_resume_rearm"):
		simulation.call("apply_resume_rearm", held_snapshot)
	elif simulation.has_method("resume_rearm"):
		simulation.call("resume_rearm", held_snapshot)
	_refresh_snapshot()


func snapshot() -> Dictionary:
	return _last_snapshot.duplicate(true)


func request_su_preparation(event_id: String) -> void:
	## 传递预读请求；实际几何计算只在核心逻辑推进中执行。
	if configured:
		simulation.request_su_preparation(event_id)


func reset_su_timeline(time_us: int) -> void:
	## Seek/清场丢弃旧目标并跳过新时间之前的素音事件。
	if configured:
		simulation.reset_su_timeline(time_us)
		_refresh_snapshot()


func clear_su_targets() -> void:
	## 会话终止后不再保留待生成目标或表现结果。
	if configured:
		simulation.clear_su_targets()
		_refresh_snapshot()


func get_input_owner() -> int:
	return _last_owner


func is_failed() -> bool:
	return bool(_last_snapshot.get("failed", _last_snapshot.get("is_failed", false)))


func force_finish() -> void:
	if not configured or simulation == null:
		return
	simulation.force_finish()
	_drain_domain_events()
	_refresh_snapshot()


func result_summary() -> Dictionary:
	if not configured or simulation == null:
		return {}
	var summary: ResultSummary = simulation.result_summary()
	return summary.to_dictionary() if summary != null else {}


func result_digest() -> String:
	if not configured or simulation == null:
		return ""
	var summary: ResultSummary = simulation.result_summary()
	return ReplayRunner.result_digest(simulation.judgments, simulation.strays, summary)


func _drain_domain_events() -> void:
	# 同帧内先发布波，再发布判定，使表现层总能先知道结果对应的物理原因。
	for wave: Dictionary in simulation.drain_wave_launches():
		wave_launched.emit(wave)

	for contact: Dictionary in simulation.drain_wave_contacts():
		wave_contacted.emit(contact)

	for arrival: Dictionary in simulation.drain_note_arrivals():
		note_arrived.emit(arrival)

	var judgments: Array[JudgmentRecord] = simulation.drain_judgments()
	for record: JudgmentRecord in judgments:
		judgment_recorded.emit(record)

	var strays: Array[StrayInputRecord] = simulation.drain_strays()
	for record: StrayInputRecord in strays:
		stray_input_recorded.emit(record)


func _refresh_snapshot() -> void:
	if not configured or simulation == null:
		return
	var next_snapshot: Dictionary = simulation.snapshot()
	_last_snapshot = next_snapshot.duplicate(true)

	var next_owner: int = int(next_snapshot.get(
		"input_owner",
		next_snapshot.get("active_input_owner", GameplayTypes.InputOwner.NONE)
	))
	if next_owner != _last_owner:
		_last_owner = next_owner
		input_owner_changed.emit(_last_owner)

	var next_tuning_active: bool = (
		bool(next_snapshot.get("tuning_field_active", false))
		and not bool(next_snapshot.get("paused_for_rearm", false))
	)
	if next_tuning_active != _tuning_capture_active:
		_tuning_capture_active = next_tuning_active
		var initial_value := Vector2(
			float(next_snapshot.get("life_tuning_value", 0.5)),
			float(next_snapshot.get("death_tuning_value", 0.5))
		)
		tuning_capture_changed.emit(_tuning_capture_active, initial_value)

	snapshot_changed.emit(_last_snapshot.duplicate(true))
