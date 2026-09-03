class_name ReplayInputDriver
extends Node

## 确定性语义 Replay 的实时注入桥。正确性验证属于 domain/ReplayRunner，
## 本节点只按时把样本送入 StageSession，不自行计算结果。

## 回放开始向 StageSession 注入输入时发出。
signal replay_started
## 最后一条回放输入已注入时发出；歌曲和关卡可以继续运行到自然结算。
signal replay_finished

## 当前载入的回放数据，包含谱面校验信息和语义输入序列。
var replay_data: ReplayData
## 接收回放输入的关卡会话。
var stage_session: StageSession
## 提供当前判定时间的时钟；驱动器据此判断本帧应注入哪些样本。
var song_clock: SongClock
## 是否正在注入回放输入。
var playing: bool = false
## 最近一次无法开始回放的原因；供调试HUD或调用方显示，不参与玩法。
var last_validation_error: String = ""

## 从 `replay_data` 取出并按时间戳、顺序号稳定排序后的输入数组。
var _inputs: Array[SemanticInputSample] = []
## `_inputs` 中下一条尚未注入的输入索引。
var _cursor: int = 0


func _ready() -> void:
	process_priority = -100


func _process(_delta: float) -> void:
	if not playing or not is_instance_valid(song_clock):
		return
	# process_priority 保证本节点先于 StageSession 运行。这里读取时钟的精确单调映射，
	# 而非上一帧快照，否则本帧刚跨过的输入会在模拟越过其时间戳后才注入。
	advance_to(roundi(song_clock.judge_time_at_usec(Time.get_ticks_usec()) * 1_000_000.0))


func bind(session: StageSession, clock: SongClock) -> void:
	stage_session = session
	song_clock = clock


func load_replay(data: ReplayData) -> bool:
	last_validation_error = ""
	replay_data = null
	_inputs.clear()
	_cursor = 0
	playing = false
	if data == null:
		last_validation_error = "Replay data is null."
		return false
	# v1 的共享调频向量无法推断为生钟或死钟，禁止静默按 v2 播放。
	if data.schema_version != ReplayData.CURRENT_SCHEMA_VERSION:
		last_validation_error = "Unsupported Replay schema."
		return false
	replay_data = data
	var source_inputs: Variant = replay_data.get("inputs")
	if not source_inputs is Array:
		last_validation_error = "Replay inputs are not an array."
		replay_data = null
		return false
	for entry: Variant in source_inputs:
		if entry is SemanticInputSample:
			_inputs.append(entry)
	_inputs.sort_custom(func(a: SemanticInputSample, b: SemanticInputSample) -> bool:
		if a.timestamp_us != b.timestamp_us:
			return a.timestamp_us < b.timestamp_us
		return a.sequence < b.sequence
	)
	return true


func start() -> bool:
	last_validation_error = ""
	if (
		replay_data == null
		or replay_data.schema_version != ReplayData.CURRENT_SCHEMA_VERSION
		or not is_instance_valid(stage_session)
	):
		last_validation_error = "Replay or bound stage session is unavailable."
		return false
	if not _matches_current_stage(replay_data):
		return false
	_cursor = 0
	playing = true
	stage_session.set_replay_mode(true)
	replay_started.emit()
	return true


func _matches_current_stage(data: ReplayData) -> bool:
	## load_replay()可以先于关卡装载；真正播放前必须对已经准备好的关卡做完整身份校验。
	if stage_session.compiled_chart == null or stage_session.rule_set == null:
		last_validation_error = "The bound stage has not been prepared."
		return false
	if data.chart_hash.is_empty() or data.chart_hash != stage_session.compiled_chart.content_hash:
		last_validation_error = "Replay chart hash mismatch."
		return false
	var expected_rules_hash: String = ChartCompiler.rules_hash(stage_session.rule_set)
	if data.rules_hash.is_empty() or data.rules_hash != expected_rules_hash:
		last_validation_error = "Replay rules hash mismatch."
		return false
	if stage_session.stage_definition == null or stage_session.stage_definition.song == null:
		last_validation_error = "The bound stage has no SongDefinition."
		return false
	var song: SongDefinition = stage_session.stage_definition.song
	var expected_song_timing_hash: String = ReplayData.compute_song_timing_hash(
		song.song_id,
		song.first_beat_offset_sec,
		stage_session.compiled_chart.content_hash
	)
	if data.song_timing_hash.is_empty() or data.song_timing_hash != expected_song_timing_hash:
		last_validation_error = "Replay song timing hash mismatch."
		return false
	return true


func stop() -> void:
	playing = false
	if is_instance_valid(stage_session):
		stage_session.set_replay_mode(false)


func seek(timestamp_us: int) -> void:
	_cursor = 0
	while _cursor < _inputs.size() and _inputs[_cursor].timestamp_us < timestamp_us:
		_cursor += 1


func advance_to(timestamp_us: int) -> void:
	if not playing or not is_instance_valid(stage_session):
		return
	while _cursor < _inputs.size():
		var sample: SemanticInputSample = _inputs[_cursor]
		if sample.timestamp_us > timestamp_us:
			break
		stage_session.inject_replay_input(sample)
		_cursor += 1
	if _cursor >= _inputs.size():
		playing = false
		replay_finished.emit()
