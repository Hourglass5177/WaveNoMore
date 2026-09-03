class_name StageSession
extends Node

## 灰盒关没有正式歌曲时用于生成测试节拍音频的脚本类。
const GRAYBOX_CLICK_TRACK_FACTORY: GDScript = preload("res://src/presentation/audio/graybox_click_track_factory.gd")

## 一局关卡的运行时中枢。负责状态机、时钟、输入队列、玩法内核和表现调度的协作，
## 但不重复实现任何判定规则。
## 主流程：LOADING → READY → PREROLL → PLAYING → FINISHING/FAILING → RESULT；
## PAUSED 只临时保存并恢复此前可暂停的状态。

## 关卡生命周期状态改变时发出；前后值均为 GameplayTypes.StageState。
signal state_changed(previous: int, current: int, reason: StringName)
## 关卡数据校验或编译失败时发出，`report` 通常是 ValidationReport 或错误字典。
signal validation_failed(report: Variant)
## 谱面编译、音频和所有运行组件准备完成后发出。
signal prepared(stage_id: String)
## 新一轮实际游玩开始时发出；`run_id` 在同一会话内单调递增。
signal run_started(run_id: int)
## 真人输入与 Replay 输入模式互相切换时发出。
signal replay_mode_changed(enabled: bool)
## 开发工具或回放跳转歌曲时间后发出，单位为秒。
signal timeline_seeked(song_time_sec: float)
## 玩法内核产出判定时立即发出，适合日志；普通音符此时未必已被波前碰到。
signal judgment_recorded(record: JudgmentRecord)
## 判定到达玩家可见的物理时刻后发出，适合 HUD、音效和击碎反馈。
signal judgment_presented(record: JudgmentRecord)
## 无玩法对象接收的一次乱按被记录时发出。
signal stray_input_recorded(record: StrayInputRecord)
## 玩家敲钟生成实体声波时发出。
signal wave_launched(wave: Dictionary)
## 实体波前接触音符时发出。
signal wave_contacted(contact: Dictionary)
## 未被声波消灭的音符抵达角色钟位时发出。
signal note_arrived(arrival: Dictionary)
## 重试、准备或跳转使旧声波全部失效时发出。
signal waves_reset
## 每次玩法快照变化时发出，供表现和 HUD 读取。
signal gameplay_snapshot_changed(snapshot: Dictionary)
## 魂火变化时发出；`current` 在无敌调试关中允许低于 0。
signal health_changed(current: int, maximum: int)
## 分数或连击数变化时发出。
signal score_changed(score: int, combo: int)
## 暂停后恢复的倒计时变化时发出，单位为秒；0 表示即将恢复。
signal resume_countdown_changed(seconds_remaining: float)
## 本局进入 RESULT 状态后只发出一次的最终结算字典。
signal result_ready(result: Dictionary)
## 汇集时钟、输入、调度器和玩法状态的开发调试快照。
signal debug_snapshot_ready(snapshot: Dictionary)

@export_group("Scene Wiring")
## 相对于 StageSession 的歌曲播放器路径；必须指向 AudioStreamPlayer。
@export var song_player_path: NodePath = ^"../SongPlayer"
## 相对于 StageSession 的歌曲主时钟路径；必须指向 SongClock。
@export var song_clock_path: NodePath = ^"../SongClock"
## 相对于 StageSession 的语义输入路由路径；必须指向 InputRouter。
@export var input_router_path: NodePath = ^"../InputRouter"
## 相对于 StageSession 的视觉事件调度器路径；必须指向 ChartScheduler。
@export var chart_scheduler_path: NodePath = ^"../ChartScheduler"
## 相对于 StageSession 的玩法协调器路径；必须指向 GameplayCoordinator。
@export var gameplay_coordinator_path: NodePath = ^"../GameplayCoordinator"

@export_group("Lifecycle")
## 从暂停返回玩法前的保护倒计时，单位为秒。数值越大，玩家重新就位的时间越充裕。
@export_range(0.0, 5.0, 0.05) var resume_countdown_sec: float = 1.25
## 乐曲与玩法结束后等待物理视觉收尾的最短时间，单位为秒。
@export_range(0.0, 3.0, 0.05) var finish_settle_sec: float = 0.35
## 窗口失去焦点时是否自动暂停；关闭后仍会清空持续输入，避免卡键。
@export var pause_on_focus_loss: bool = true

## 当前关卡生命周期状态，使用 GameplayTypes.StageState 枚举。
var state: int = GameplayTypes.StageState.LOADING
## 当前装载的关卡聚合资源，组合歌曲、谱面、演出、主题、奖励和规则。
var stage_definition: StageDefinition
## 由 ChartCompiler 生成的只读运行谱，所有 tick 已换算为确定性微秒时间。
var compiled_chart: CompiledChart
## 当前关卡使用的判定、计分、魂火、波传播、调频和疾振规则。
var rule_set: GameplayRuleSet
## 本会话内的游玩轮次编号；每次 `start()` 加一，重试也会产生新编号。
var run_id: int = 0
## 本关是否因缺少正式歌曲而使用程序生成的灰盒节拍音频。
var uses_generated_graybox_audio: bool = false

## 已解析并绑定的歌曲播放器。
var song_player: AudioStreamPlayer
## 已解析并绑定的歌曲主时钟。
var song_clock: SongClock
## 已解析并绑定的语义输入路由。
var input_router: InputRouter
## 已解析并绑定的视觉调度器。
var chart_scheduler: ChartScheduler
## 已解析并绑定的玩法内核协调器。
var gameplay_coordinator: GameplayCoordinator

## 尚未按时间送入玩法内核的语义输入；始终按时间戳和顺序号处理。
var _pending_inputs: Array[SemanticInputSample] = []
## 进入暂停前的生命周期状态，用于倒计时结束后恢复到原状态。
var _state_before_pause: int = GameplayTypes.StageState.PLAYING
## 暂停后恢复倒计时的剩余秒数；负值表示当前没有倒计时。
var _resume_countdown_remaining: float = -1.0
## 暂停时从玩法内核取得的 Hold/调频重武装状态，避免恢复瞬间误判松键。
var _resume_rearm_state: Dictionary = {}
## 防止同一帧由暂停键、失焦等来源重复进入暂停流程。
var _pause_in_progress: bool = false
## 是否由 ReplayInputDriver 接管输入；为 true 时真人输入会被禁用。
var _replay_mode: bool = false
## 本局是否已经发出最终结果，保证 `result_ready` 最多触发一次。
var _result_emitted: bool = false
## 本关应开始收尾的歌曲时间，单位为秒，由音频、兜底时长和谱面尾端共同决定。
var _end_song_time_sec: float = 0.0
## 进入 FAILING 状态时的歌曲时间，单位为秒，用于等待失败后的物理收尾。
var _fail_started_song_time_sec: float = 0.0
## 进入 FINISHING 状态时的歌曲时间，单位为秒，用于计算结算等待时间。
var _finish_started_song_time_sec: float = 0.0
## 上次已通过 `health_changed` 发布的魂火，-1 强制第一次快照发送信号。
var _last_health: int = -1
## 上次已发布的分数，-1 强制第一次快照发送信号。
var _last_score: int = -1
## 上次已发布的 Combo，-1 强制第一次快照发送信号。
var _last_combo: int = -1
## `teardown()` 是否已经执行，防止退出树和主动退出重复拆线。
var _teardown_done: bool = false
## 已在逻辑时间判定、但尚未到波接触/抵达时刻的普通音符等级，键为稳定音符 ID。
var _deferred_note_grades: Dictionary[String, int] = {}
## 与上一字典配套保存完整判定记录，等物理时刻到来后再展示。
var _deferred_note_records: Dictionary[String, JudgmentRecord] = {}
## 已经发出 `judgment_presented` 的音符 ID 集合，防止接触和抵达路径重复展示。
var _presented_note_ids: Dictionary[String, bool] = {}
## 已收到真实波前接触事件的音符 ID 集合。
var _contacted_note_ids: Dictionary[String, bool] = {}
## 已飞到角色钟位的音符 ID 集合。
var _arrived_note_ids: Dictionary[String, bool] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resolve_components()
	_connect_components()


func _exit_tree() -> void:
	teardown()


func _process(delta: float) -> void:
	if state == GameplayTypes.StageState.PAUSED:
		_process_resume_countdown(delta)
		return
	if state not in [
		GameplayTypes.StageState.PREROLL,
		GameplayTypes.StageState.PLAYING,
		GameplayTypes.StageState.FINISHING,
		GameplayTypes.StageState.FAILING,
	]:
		return
	if not is_instance_valid(song_clock):
		return
	step(song_clock.sample())


func bind_components(
	player: AudioStreamPlayer,
	clock: SongClock,
	router: InputRouter,
	scheduler: ChartScheduler,
	coordinator: GameplayCoordinator
) -> void:
	song_player = player
	song_clock = clock
	input_router = router
	chart_scheduler = scheduler
	gameplay_coordinator = coordinator
	_connect_components()


func configure(stage: StageDefinition) -> bool:
	_teardown_done = false
	stage_definition = stage
	_result_emitted = false
	_clear_physical_note_state()
	if stage_definition == null:
		validation_failed.emit({"errors": ["StageDefinition is null."]})
		return false
	if stage_definition.song == null or stage_definition.chart == null or stage_definition.rule_set == null:
		validation_failed.emit({"errors": ["Stage requires song, chart and rule_set resources."]})
		return false

	rule_set = stage_definition.rule_set
	return true


func prepare() -> bool:
	# 第一阶段只检查“资源齐全”和“场景接线完整”，失败时不启动任何时钟或输入。
	if stage_definition == null:
		validation_failed.emit({"errors": ["StageDefinition is null."]})
		return false
	if rule_set == null and not configure(stage_definition):
		return false
	if not _components_are_ready():
		validation_failed.emit({"errors": ["StageSession scene wiring is incomplete."]})
		return false

	_transition_to(GameplayTypes.StageState.LOADING, &"prepare")
	var compiler := ChartCompiler.new()
	# 第二阶段把易编辑的 Resource 谱面编译成微秒时间轴；编译失败便保留在加载状态。
	# SongClock 已把音频文件时间映射到谱面 tick 0；编译时再次传首拍偏移会重复补偿。
	var compile_result: Dictionary = compiler.compile(stage_definition.chart, rule_set, 0)
	if not bool(compile_result.get("ok", false)):
		validation_failed.emit(compile_result.get("report", compile_result))
		return false

	compiled_chart = compile_result.get("compiled") as CompiledChart
	if compiled_chart == null:
		validation_failed.emit({"errors": ["ChartCompiler returned no CompiledChart."]})
		return false

	# 第三阶段让时钟、视觉调度和玩法内核共享同一份编译结果，再计算关卡真正结束时间。
	song_player.stream = _resolve_song_stream()
	song_clock.configure(song_player, stage_definition.song.first_beat_offset_sec)
	input_router.configure_from_rules(rule_set)
	chart_scheduler.configure(compiled_chart, rule_set.approach_duration_sec)
	chart_scheduler.note_visual_tail_sec = _maximum_post_cue_travel_sec() + chart_scheduler.resolved_note_tail_sec
	if not gameplay_coordinator.configure(compiled_chart, rule_set, stage_definition.debug_nonlethal):
		return false

	_end_song_time_sec = _calculate_end_song_time_sec()
	_transition_to(GameplayTypes.StageState.READY, &"prepared")
	prepared.emit(stage_definition.stage_id)
	return true


func start() -> bool:
	if state != GameplayTypes.StageState.READY:
		return false
	# 每一轮都清空上轮输入、展示缓存和子系统状态；关卡资源本身无需重新编译。
	run_id += 1
	_result_emitted = false
	_pending_inputs.clear()
	_resume_rearm_state.clear()
	_resume_countdown_remaining = -1.0
	_last_health = -1
	_last_score = -1
	_last_combo = -1
	_clear_physical_note_state()
	gameplay_coordinator.reset()
	chart_scheduler.reset()
	input_router.reset_for_run()
	# 先通知 ReplayRecorder 建立本轮记录，再开放输入并启动歌曲时钟。
	run_started.emit(run_id)
	input_router.set_mode(InputRouter.InputMode.REPLAY if _replay_mode else InputRouter.InputMode.GAMEPLAY)
	song_clock.start(0.0)
	var initial_sample: ClockSample = song_clock.sample()
	if initial_sample.song_time_sec < 0.0:
		_transition_to(GameplayTypes.StageState.PREROLL, &"start")
	else:
		_transition_to(GameplayTypes.StageState.PLAYING, &"start")
	step(initial_sample)
	return true


func step(clock_sample: ClockSample) -> void:
	if clock_sample == null or not _components_are_ready():
		return
	if state == GameplayTypes.StageState.PAUSED or state == GameplayTypes.StageState.RESULT:
		return

	# 先按 judge_time 处理确定性玩法，再按 visual_time 推进预见性表现；
	# 两条时间轴不能互换，否则视觉校准会改变真实判定。
	var judge_time_us: int = roundi(clock_sample.judge_time_sec * 1_000_000.0)
	_process_due_inputs(judge_time_us)
	gameplay_coordinator.advance_to(judge_time_us, true)
	chart_scheduler.advance(clock_sample.visual_time_sec)

	if state == GameplayTypes.StageState.PREROLL and clock_sample.song_time_sec >= 0.0:
		_transition_to(GameplayTypes.StageState.PLAYING, &"preroll_complete")

	var gameplay_snapshot: Dictionary = gameplay_coordinator.snapshot()
	_emit_snapshot_changes(gameplay_snapshot)

	if gameplay_coordinator.is_failed() and state in [
		GameplayTypes.StageState.PREROLL,
		GameplayTypes.StageState.PLAYING,
	]:
		_begin_failure(clock_sample.song_time_sec)

	if state == GameplayTypes.StageState.PLAYING and clock_sample.song_time_sec >= _end_song_time_sec:
		_begin_finishing(clock_sample.song_time_sec)
	elif state == GameplayTypes.StageState.FINISHING:
		if clock_sample.song_time_sec - _finish_started_song_time_sec >= finish_settle_sec:
			_complete_result(true)
	elif state == GameplayTypes.StageState.FAILING:
		var physical_failure_settle: float = maxf(
			rule_set.fail_settle_sec,
			_maximum_post_cue_travel_sec() - float(rule_set.miss_window_ms) / 1000.0
		)
		if clock_sample.song_time_sec - _fail_started_song_time_sec >= physical_failure_settle:
			_complete_result(false)

	debug_snapshot_ready.emit(_build_debug_snapshot(clock_sample, gameplay_snapshot))


func enqueue_input(sample: SemanticInputSample) -> void:
	if sample == null:
		return
	if state == GameplayTypes.StageState.PAUSED:
		# 暂停恢复只观察 InputRouter 的当前按住快照，这些按键不是新的玩法判定。
		return
	if state not in [GameplayTypes.StageState.PREROLL, GameplayTypes.StageState.PLAYING]:
		return
	_pending_inputs.append(sample)
	_pending_inputs.sort_custom(func(a: SemanticInputSample, b: SemanticInputSample) -> bool:
		if a.timestamp_us != b.timestamp_us:
			return a.timestamp_us < b.timestamp_us
		return a.sequence < b.sequence
	)


func inject_replay_input(sample: SemanticInputSample) -> void:
	if not _replay_mode:
		return
	enqueue_input(sample)


func set_replay_mode(enabled: bool) -> void:
	if _replay_mode == enabled:
		return
	_replay_mode = enabled
	replay_mode_changed.emit(_replay_mode)
	if is_instance_valid(input_router):
		input_router.set_mode(InputRouter.InputMode.REPLAY if enabled else InputRouter.InputMode.GAMEPLAY)


func is_replay_playback() -> bool:
	return _replay_mode


func request_pause(reason: StringName = &"manual") -> bool:
	if _pause_in_progress:
		return false
	if state not in [GameplayTypes.StageState.PREROLL, GameplayTypes.StageState.PLAYING]:
		return false
	_pause_in_progress = true

	# 先精确推进到暂停按下的系统时刻，避免这一帧已经到期的输入或判定被漏掉。
	var now_usec: int = Time.get_ticks_usec()
	var pause_sample: ClockSample = song_clock.sample(now_usec)
	step(pause_sample)
	# 记录持续输入重武装信息后清键、冻钟，最后才暂停整棵 SceneTree。
	_state_before_pause = state
	_resume_rearm_state = gameplay_coordinator.begin_pause_rearm()
	input_router.cancel_all(InputRouter.CancelReason.PAUSE, false)
	song_clock.pause(now_usec)
	_transition_to(GameplayTypes.StageState.PAUSED, reason)
	input_router.set_mode(InputRouter.InputMode.RESUME_REARM)
	_resume_countdown_remaining = -1.0
	get_tree().paused = true
	_pause_in_progress = false
	return true


func request_resume() -> bool:
	if state != GameplayTypes.StageState.PAUSED:
		return false
	if _resume_countdown_remaining >= 0.0:
		return false
	_resume_countdown_remaining = resume_countdown_sec
	resume_countdown_changed.emit(_resume_countdown_remaining)
	if is_zero_approx(resume_countdown_sec):
		_complete_resume()
	return true


func retry() -> bool:
	if not _components_are_ready() or stage_definition == null:
		return false
	if get_tree().paused:
		get_tree().paused = false

	# 重试复用已经编译的关卡，但必须同时重置输入、物理波、判定和视觉游标。
	_resume_countdown_remaining = -1.0
	_resume_rearm_state.clear()
	_result_emitted = false
	input_router.set_mode(InputRouter.InputMode.DISABLED)
	input_router.cancel_all(InputRouter.CancelReason.RETRY, false)
	_pending_inputs.clear()
	_clear_physical_note_state()
	song_clock.stop()
	gameplay_coordinator.reset()
	chart_scheduler.reset()
	_transition_to(GameplayTypes.StageState.READY, &"retry_reset")
	return start()


func abort() -> void:
	if get_tree().paused:
		get_tree().paused = false
	_resume_countdown_remaining = -1.0
	input_router.set_mode(InputRouter.InputMode.DISABLED)
	input_router.cancel_all(InputRouter.CancelReason.SESSION_END, false)
	_pending_inputs.clear()
	chart_scheduler.reset()
	_complete_result(false, true)


func teardown() -> void:
	if _teardown_done:
		return
	_teardown_done = true
	if get_tree() != null and get_tree().paused:
		get_tree().paused = false
	_resume_countdown_remaining = -1.0
	_pending_inputs.clear()
	if is_instance_valid(input_router):
		input_router.cancel_all(InputRouter.CancelReason.SESSION_END, false)
		input_router.set_mode(InputRouter.InputMode.DISABLED)
	if is_instance_valid(chart_scheduler):
		chart_scheduler.reset()
	if is_instance_valid(song_clock):
		song_clock.stop()
	if is_instance_valid(song_player):
		song_player.stop()
		song_player.stream_paused = false
		song_player.stream = null


func current_snapshot() -> Dictionary:
	var result: Dictionary = gameplay_coordinator.snapshot() if is_instance_valid(gameplay_coordinator) else {}
	result["stage_state"] = state
	result["run_id"] = run_id
	result["song_time_sec"] = song_clock.song_time_sec if is_instance_valid(song_clock) else 0.0
	return result


func get_end_song_time_sec() -> float:
	return _end_song_time_sec


func seek_song_time(target_song_time_sec: float) -> bool:
	if compiled_chart == null or not _components_are_ready():
		return false
	if state not in [
		GameplayTypes.StageState.READY,
		GameplayTypes.StageState.PREROLL,
		GameplayTypes.StageState.PLAYING,
		GameplayTypes.StageState.PAUSED,
	]:
		return false
	var was_running: bool = state in [
		GameplayTypes.StageState.PREROLL,
		GameplayTypes.StageState.PLAYING,
	]
	# Seek 会建立一条新的时间线：丢弃待处理输入，重置玩法状态和物理事件，
	# 再把玩法与视觉分别推进到目标判定时间和目标视觉时间。
	_pending_inputs.clear()
	_clear_physical_note_state()
	input_router.reset_for_run()
	gameplay_coordinator.reset()
	chart_scheduler.seek(target_song_time_sec + song_clock.visual_lead_sec)
	var target_judge_us: int = roundi((target_song_time_sec - song_clock.input_compensation_sec) * 1_000_000.0)
	gameplay_coordinator.advance_to(target_judge_us, false)
	song_clock.seek_song_time(target_song_time_sec)
	_last_health = -1
	_last_score = -1
	_last_combo = -1
	_emit_snapshot_changes(gameplay_coordinator.snapshot())
	if was_running:
		_transition_to(
			GameplayTypes.StageState.PREROLL if target_song_time_sec < 0.0 else GameplayTypes.StageState.PLAYING,
			&"timeline_seek"
		)
	timeline_seeked.emit(target_song_time_sec)
	return true


func _process_resume_countdown(delta: float) -> void:
	if _resume_countdown_remaining < 0.0:
		return
	_resume_countdown_remaining = maxf(_resume_countdown_remaining - delta, 0.0)
	resume_countdown_changed.emit(_resume_countdown_remaining)
	if is_zero_approx(_resume_countdown_remaining):
		_complete_resume()


func _complete_resume() -> void:
	if state != GameplayTypes.StageState.PAUSED:
		return
	_resume_countdown_remaining = -1.0
	var held_snapshot: Dictionary = input_router.get_held_snapshot()
	# 玩法逻辑层恢复只接受此刻真实按住状态；begin_pause_rearm 返回的 required 标志
	# 只用于 UI 提示，不能冒充玩家输入。
	gameplay_coordinator.apply_resume_rearm({
		"life_held": bool(held_snapshot.get("life_held", false)),
		"death_held": bool(held_snapshot.get("death_held", false)),
	})
	_resume_rearm_state.clear()
	song_clock.resume(Time.get_ticks_usec())
	input_router.set_mode(InputRouter.InputMode.REPLAY if _replay_mode else InputRouter.InputMode.GAMEPLAY)
	get_tree().paused = false
	_transition_to(_state_before_pause, &"resume")
	resume_countdown_changed.emit(0.0)


func _process_due_inputs(judge_time_us: int) -> void:
	while not _pending_inputs.is_empty():
		var sample: SemanticInputSample = _pending_inputs[0]
		if sample.timestamp_us > judge_time_us:
			break
		_pending_inputs.pop_front()
		gameplay_coordinator.accept_input(sample)


func _begin_failure(song_time: float) -> void:
	if state == GameplayTypes.StageState.FAILING:
		return
	_fail_started_song_time_sec = song_time
	input_router.set_mode(InputRouter.InputMode.DISABLED)
	input_router.cancel_all(InputRouter.CancelReason.SESSION_END, false)
	_transition_to(GameplayTypes.StageState.FAILING, &"soul_fire_empty")


func _begin_finishing(song_time: float) -> void:
	_finish_started_song_time_sec = song_time
	input_router.set_mode(InputRouter.InputMode.DISABLED)
	input_router.cancel_all(InputRouter.CancelReason.SESSION_END, false)
	_transition_to(GameplayTypes.StageState.FINISHING, &"song_complete")


func _complete_result(success: bool, aborted: bool = false) -> void:
	if _result_emitted:
		return
	_result_emitted = true
	if get_tree().paused:
		get_tree().paused = false
	# 先封住一切新输入；自然结束时让内核补齐尚未到期的单位，主动退出则不伪造结果。
	input_router.set_mode(InputRouter.InputMode.DISABLED)
	input_router.cancel_all(InputRouter.CancelReason.SESSION_END, false)
	if not aborted:
		gameplay_coordinator.force_finish()
	song_clock.stop()
	# 领域层提供成绩主体，会话层只补关卡身份、轮次、退出原因和可复验摘要。
	var result: Dictionary = gameplay_coordinator.result_summary()
	if result.is_empty():
		result = gameplay_coordinator.snapshot()
	result["success"] = success and bool(result.get("cleared", true))
	result["aborted"] = aborted
	result["stage_id"] = stage_definition.stage_id if stage_definition != null else ""
	result["run_id"] = run_id
	result["result_digest"] = gameplay_coordinator.result_digest()
	_transition_to(GameplayTypes.StageState.RESULT, &"result")
	result_ready.emit(result)


func _emit_snapshot_changes(snapshot: Dictionary) -> void:
	var current_health: int = int(snapshot.get("soul_fire", snapshot.get("health", 0)))
	var max_health: int = int(snapshot.get("max_soul_fire", rule_set.max_soul_fire if rule_set != null else 0))
	if current_health != _last_health:
		_last_health = current_health
		health_changed.emit(current_health, max_health)

	var current_score: int = int(snapshot.get("score", 0))
	var current_combo: int = int(snapshot.get("combo", 0))
	if current_score != _last_score or current_combo != _last_combo:
		_last_score = current_score
		_last_combo = current_combo
		score_changed.emit(current_score, current_combo)

	gameplay_snapshot_changed.emit(snapshot.duplicate(true))


func _on_judgment_recorded(record: JudgmentRecord) -> void:
	# 进入这里前，玩法逻辑已经完成计分和扣魂火；下面的延迟队列只决定普通音符何时演出结果。
	if record.unit_kind in [&"tap", &"hold"]:
		chart_scheduler.mark_timing_confirmed(record.unit_id, record.grade)
		_deferred_note_grades[record.unit_id] = record.grade
		_deferred_note_records[record.unit_id] = record
		var should_present_now: bool = false
		if record.grade == GameplayTypes.JudgmentGrade.MISS:
			# 头部 MISS 的音符没有对向波，会在抵达钟时解决。Hold 头即使已接触，
			# 尾部仍可能 MISS；这种结果属于先前接触路径，不会再产生 arrival。
			should_present_now = (
				bool(_arrived_note_ids.get(record.unit_id, false))
				or (
					record.unit_kind == &"hold"
					and bool(_contacted_note_ids.get(record.unit_id, false))
				)
			)
		else:
			# 精度在输入时确定，但成功击破效果要等彩色波前真正接触音符后才播放。
			should_present_now = bool(_contacted_note_ids.get(record.unit_id, false))
		if should_present_now:
			_present_note_judgment(record.unit_id)
	else:
		if record.unit_kind == &"tuning":
			# 成组调频用 group_id 结算，但画面上的两条滑槽仍以各自 event_id 注册。
			# 因此一次成绩要同时通知生、死两侧视觉，Combo/扣血仍只发生一次。
			var visual_ids := _tuning_visual_event_ids(record)
			for event_id: String in visual_ids:
				chart_scheduler.mark_judged(event_id, record.grade)
		else:
			chart_scheduler.mark_judged(record.unit_id, record.grade)
		judgment_presented.emit(record)
	judgment_recorded.emit(record)


func _tuning_visual_event_ids(record: JudgmentRecord) -> PackedStringArray:
	var result := PackedStringArray()
	var sides: Dictionary = record.metadata.get("sides", {})
	# 固定生、死顺序，避免 Dictionary 遍历顺序影响视觉和测试。
	for side_name: String in ["life", "death"]:
		var side: Dictionary = sides.get(side_name, {})
		var event_id: String = str(side.get("event_id", ""))
		if not event_id.is_empty() and not result.has(event_id):
			result.append(event_id)
	if result.is_empty() and not record.unit_id.is_empty():
		result.append(record.unit_id)
	return result


func _on_stray_input_recorded(record: StrayInputRecord) -> void:
	stray_input_recorded.emit(record)


func _on_wave_launched(wave: Dictionary) -> void:
	wave_launched.emit(wave.duplicate(true))


func _on_wave_contacted(contact: Dictionary) -> void:
	var note_id: String = str(contact.get("note_id", ""))
	if not note_id.is_empty():
		_contacted_note_ids[note_id] = true
		chart_scheduler.mark_wave_contacted(note_id, contact)
		if _deferred_note_grades.has(note_id):
			var grade: int = int(_deferred_note_grades[note_id])
			var record: JudgmentRecord = _deferred_note_records.get(note_id) as JudgmentRecord
			var is_contacted_hold_miss: bool = (
				grade == GameplayTypes.JudgmentGrade.MISS
				and record != null
				and record.unit_kind == &"hold"
			)
			if grade != GameplayTypes.JudgmentGrade.MISS or is_contacted_hold_miss:
				_present_note_judgment(note_id)
	wave_contacted.emit(contact.duplicate(true))


func _on_note_arrived(arrival: Dictionary) -> void:
	var note_id: String = str(arrival.get("note_id", ""))
	if not note_id.is_empty():
		_arrived_note_ids[note_id] = true
		chart_scheduler.mark_note_arrived(note_id, arrival)
		if _deferred_note_grades.has(note_id):
			var grade: int = int(_deferred_note_grades[note_id])
			if grade == GameplayTypes.JudgmentGrade.MISS:
				_present_note_judgment(note_id)
	note_arrived.emit(arrival.duplicate(true))


func _on_waves_reset() -> void:
	_clear_physical_note_state()
	waves_reset.emit()


func _on_input_cancelled(reason: int) -> void:
	if _pause_in_progress:
		return
	if reason == InputRouter.CancelReason.FOCUS_LOST and pause_on_focus_loss:
		request_pause(&"focus_lost")


func _on_pause_requested() -> void:
	if state == GameplayTypes.StageState.PAUSED:
		request_resume()
	else:
		request_pause(&"manual")


func _on_tuning_capture_changed(active: bool, initial_value: Vector2) -> void:
	input_router.set_tuning_capture_active(active, initial_value)


func _build_debug_snapshot(clock_sample: ClockSample, gameplay_snapshot: Dictionary) -> Dictionary:
	var active_sliders: Array = []
	var raw_active_sliders: Variant = gameplay_snapshot.get("active_tuning_sliders", [])
	if raw_active_sliders is Array:
		active_sliders = (raw_active_sliders as Array).duplicate(true)
	return {
		"run_id": run_id,
		"stage_state": state,
		"clock_generation": clock_sample.generation,
		"audio_time_raw_sec": clock_sample.audio_time_raw_sec,
		"song_time_sec": clock_sample.song_time_sec,
		"judge_time_sec": clock_sample.judge_time_sec,
		"visual_time_sec": clock_sample.visual_time_sec,
		"audio_drift_sec": clock_sample.audio_drift_sec,
		"output_latency_sec": song_clock.get_cached_output_latency_sec(),
		"audio_calibration_sec": song_clock.audio_calibration_sec,
		"input_compensation_sec": song_clock.input_compensation_sec,
		"visual_lead_sec": song_clock.visual_lead_sec,
		"input_owner": gameplay_coordinator.get_input_owner(),
		"life_held": input_router.life_held,
		"death_held": input_router.death_held,
		# 这里是两根摇杆的瞬时移动速率，不是旧版共同调频游标。
		"tuning_rate": input_router.tune_vector,
		"tuning_field_active": gameplay_snapshot.get("tuning_field_active", false),
		"active_tuning_field_id": gameplay_snapshot.get("active_tuning_field_id", ""),
		"life_tuning_value": gameplay_snapshot.get("life_tuning_value", 0.0),
		"death_tuning_value": gameplay_snapshot.get("death_tuning_value", 0.0),
		"life_frequency_hz": gameplay_snapshot.get("life_frequency_hz", 0.0),
		"death_frequency_hz": gameplay_snapshot.get("death_frequency_hz", 0.0),
		"active_tuning_sliders": active_sliders,
		"active_tuning_slider_count": active_sliders.size(),
		"pending_inputs": _pending_inputs.size(),
		"score": gameplay_snapshot.get("score", 0),
		"combo": gameplay_snapshot.get("combo", 0),
		"soul_fire": gameplay_snapshot.get("soul_fire", 0),
		"content_hash": _read_compiled_member(&"content_hash", ""),
		"uses_generated_graybox_audio": uses_generated_graybox_audio,
	}


func _calculate_end_song_time_sec() -> float:
	# 取谱面尾、最后一枚音符飞到钟的时刻和音频尾三者中的最大值，
	# 避免音乐或仍在飞行的实体被结算页提前截断。
	var compiled_end_sec: float = float(_read_compiled_member(&"end_time_us", 0)) / 1_000_000.0
	var physical_note_end_sec: float = 0.0
	if compiled_chart != null:
		for note: Dictionary in compiled_chart.notes:
			physical_note_end_sec = maxf(
				physical_note_end_sec,
				float(note.get("start_us", 0)) / 1_000_000.0
					+ _post_cue_travel_sec(int(note.get("affinity", GameplayTypes.Affinity.ZHU)))
			)
	var audio_length_sec: float = 0.0
	if stage_definition.song.audio_stream != null:
		audio_length_sec = stage_definition.song.audio_stream.get_length()
	if audio_length_sec <= 0.0:
		audio_length_sec = stage_definition.song.fallback_duration_sec
	var audio_end_song_time: float = maxf(
		audio_length_sec - stage_definition.song.first_beat_offset_sec,
		0.0
	)
	return maxf(maxf(compiled_end_sec, physical_note_end_sec), audio_end_song_time)


func _maximum_post_cue_travel_sec() -> float:
	return maxf(
		_post_cue_travel_sec(GameplayTypes.Affinity.ZHU),
		_post_cue_travel_sec(GameplayTypes.Affinity.XUAN)
	)


func _post_cue_travel_sec(affinity: int) -> float:
	if rule_set == null:
		return 1.3
	var origin: Vector2 = rule_set.death_wave_origin if affinity == GameplayTypes.Affinity.XUAN else rule_set.life_wave_origin
	var cue: Vector2 = rule_set.death_note_cue if affinity == GameplayTypes.Affinity.XUAN else rule_set.life_note_cue
	var spawn: Vector2 = rule_set.death_note_spawn if affinity == GameplayTypes.Affinity.XUAN else rule_set.life_note_spawn
	var approach_profile: Dictionary = NoteApproachPath.build_profile(
		spawn,
		cue,
		origin,
		rule_set.note_curve_outer_bend_px,
		rule_set.note_curve_center_handle_px
	)
	var approach_distance: float = maxf(NoteApproachPath.length(approach_profile), 0.001)
	var note_speed: float = approach_distance / maxf(rule_set.approach_duration_sec, 0.001)
	return cue.distance_to(origin) / maxf(note_speed, 0.001)


func _resolve_song_stream() -> AudioStream:
	uses_generated_graybox_audio = stage_definition.song.audio_stream == null
	if not uses_generated_graybox_audio:
		return stage_definition.song.audio_stream
	return GRAYBOX_CLICK_TRACK_FACTORY.create(
		stage_definition.song.fallback_duration_sec,
		_first_chart_bpm(),
		stage_definition.song.first_beat_offset_sec,
		_first_chart_meter_numerator()
	)


func _first_chart_bpm() -> float:
	if stage_definition.chart.tempo_events.is_empty():
		return 120.0
	var earliest: TempoEvent = stage_definition.chart.tempo_events[0]
	for candidate: TempoEvent in stage_definition.chart.tempo_events:
		if candidate.tick < earliest.tick:
			earliest = candidate
	return earliest.bpm


func _first_chart_meter_numerator() -> int:
	if stage_definition.chart.meter_events.is_empty():
		return 4
	var earliest: MeterEvent = stage_definition.chart.meter_events[0]
	for candidate: MeterEvent in stage_definition.chart.meter_events:
		if candidate.tick < earliest.tick:
			earliest = candidate
	return earliest.numerator


func _read_compiled_member(member_name: StringName, fallback: Variant) -> Variant:
	if compiled_chart == null:
		return fallback
	for property_data: Dictionary in compiled_chart.get_property_list():
		if property_data.get("name", &"") == member_name:
			return compiled_chart.get(member_name)
	return fallback


func _transition_to(next_state: int, reason: StringName) -> void:
	if next_state == state:
		return
	var previous: int = state
	state = next_state
	state_changed.emit(previous, state, reason)


func _resolve_components() -> void:
	if not is_instance_valid(song_player):
		song_player = get_node_or_null(song_player_path) as AudioStreamPlayer
	if not is_instance_valid(song_clock):
		song_clock = get_node_or_null(song_clock_path) as SongClock
	if not is_instance_valid(input_router):
		input_router = get_node_or_null(input_router_path) as InputRouter
	if not is_instance_valid(chart_scheduler):
		chart_scheduler = get_node_or_null(chart_scheduler_path) as ChartScheduler
	if not is_instance_valid(gameplay_coordinator):
		gameplay_coordinator = get_node_or_null(gameplay_coordinator_path) as GameplayCoordinator


func _connect_components() -> void:
	if is_instance_valid(input_router):
		if not input_router.semantic_input_emitted.is_connected(enqueue_input):
			input_router.semantic_input_emitted.connect(enqueue_input)
		if not input_router.cancelled.is_connected(_on_input_cancelled):
			input_router.cancelled.connect(_on_input_cancelled)
		if not input_router.pause_requested.is_connected(_on_pause_requested):
			input_router.pause_requested.connect(_on_pause_requested)
		if is_instance_valid(song_clock):
			input_router.bind_clock(song_clock)
	if is_instance_valid(gameplay_coordinator):
		if not gameplay_coordinator.judgment_recorded.is_connected(_on_judgment_recorded):
			gameplay_coordinator.judgment_recorded.connect(_on_judgment_recorded)
		if not gameplay_coordinator.stray_input_recorded.is_connected(_on_stray_input_recorded):
			gameplay_coordinator.stray_input_recorded.connect(_on_stray_input_recorded)
		if not gameplay_coordinator.wave_launched.is_connected(_on_wave_launched):
			gameplay_coordinator.wave_launched.connect(_on_wave_launched)
		if not gameplay_coordinator.wave_contacted.is_connected(_on_wave_contacted):
			gameplay_coordinator.wave_contacted.connect(_on_wave_contacted)
		if not gameplay_coordinator.note_arrived.is_connected(_on_note_arrived):
			gameplay_coordinator.note_arrived.connect(_on_note_arrived)
		if not gameplay_coordinator.waves_reset.is_connected(_on_waves_reset):
			gameplay_coordinator.waves_reset.connect(_on_waves_reset)
		if not gameplay_coordinator.tuning_capture_changed.is_connected(_on_tuning_capture_changed):
			gameplay_coordinator.tuning_capture_changed.connect(_on_tuning_capture_changed)


func _components_are_ready() -> bool:
	return (
		is_instance_valid(song_player)
		and is_instance_valid(song_clock)
		and is_instance_valid(input_router)
		and is_instance_valid(chart_scheduler)
		and is_instance_valid(gameplay_coordinator)
	)


func _clear_physical_note_state() -> void:
	_deferred_note_grades.clear()
	_deferred_note_records.clear()
	_presented_note_ids.clear()
	_contacted_note_ids.clear()
	_arrived_note_ids.clear()


func _present_note_judgment(note_id: String) -> void:
	if note_id.is_empty() or bool(_presented_note_ids.get(note_id, false)):
		return
	if not _deferred_note_records.has(note_id):
		return
	var record: JudgmentRecord = _deferred_note_records[note_id]
	_presented_note_ids[note_id] = true
	chart_scheduler.mark_judged(note_id, record.grade)
	judgment_presented.emit(record)
