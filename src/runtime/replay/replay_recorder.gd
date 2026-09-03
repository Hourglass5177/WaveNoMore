class_name ReplayRecorder
extends Node

## 记录真人语义输入并保存带诊断信息的 Replay 数据包。它只旁听运行时信号，
## 录制和文件读写绝不回流到本局玩法。

## 新一局真人游玩开始录制时发出，并提供正在填充的 ReplayData。
signal recording_started(replay: ReplayData)
## Replay 与运行日志原子保存成功后发出。
signal replay_saved(path: String, replay: ReplayData, run_log: Dictionary)
## 保存失败时发出；`path` 是目标文件，`message` 是失败原因。
signal replay_save_failed(path: String, message: String)

## 未在场景中另行配置时使用的最后一局 Replay 路径，位于 Godot 用户数据目录。
const DEFAULT_OUTPUT_PATH: String = "user://minghe/replays/last_run.json"
## 未装备随从时参与哈希的稳定文本，避免“空字符串”含义不明确。
const EMPTY_LOADOUT_HASH: String = "loadout:none"

## Replay JSON 的保存位置。应使用 `user://` 等运行时可写路径；每局成功结算后覆盖该文件。
@export_file("*.json") var output_path: String = DEFAULT_OUTPUT_PATH

## 最近一次成功录制并保留在内存中的 Replay；不一定已经成功写入磁盘。
var last_replay: ReplayData
## 最近一局的诊断日志，包含各类哈希、校准量和结算结果。
var last_run_log: Dictionary = {}
## 当前是否应继续收集真人语义输入；回放模式、结算或废弃时间线时为 false。
var is_recording: bool = false

## 被旁听的关卡会话，用于取得关卡、规则、状态和结算信息。
var _session: StageSession
## 被旁听的输入路由，提供已经过时间补偿的语义输入样本。
var _input_router: InputRouter
## 当前一局正在填充的 ReplayData；结算后转移到 `last_replay`。
var _active_replay: ReplayData
## 当前装备组合的哈希。随从不改判定，但必须写入日志以复现实验环境。
var _loadout_hash: String = EMPTY_LOADOUT_HASH.sha256_text()
## 当前时间线是否应整体丢弃，例如本局本身就是回放，或录制期间发生不连续操作。
var _discard_current_run: bool = false


func bind(session: StageSession, input_router: InputRouter) -> void:
	_session = session
	_input_router = input_router
	if not session.run_started.is_connected(_on_run_started):
		session.run_started.connect(_on_run_started)
	if not session.replay_mode_changed.is_connected(_on_replay_mode_changed):
		session.replay_mode_changed.connect(_on_replay_mode_changed)
	if not session.result_ready.is_connected(_on_result_ready):
		session.result_ready.connect(_on_result_ready)
	if not session.timeline_seeked.is_connected(_on_timeline_seeked):
		session.timeline_seeked.connect(_on_timeline_seeked)
	if not input_router.semantic_input_emitted.is_connected(_on_semantic_input):
		input_router.semantic_input_emitted.connect(_on_semantic_input)


func set_loadout_hash(value: String) -> void:
	_loadout_hash = value if not value.is_empty() else EMPTY_LOADOUT_HASH.sha256_text()


func get_last_replay() -> ReplayData:
	return last_replay


func get_last_run_log() -> Dictionary:
	return last_run_log.duplicate(true)


func load_last() -> bool:
	var loaded: Dictionary = load_from_path(output_path)
	if not bool(loaded.get("ok", false)):
		return false
	last_replay = loaded.get("replay") as ReplayData
	last_run_log = Dictionary(loaded.get("run_log", {})).duplicate(true)
	return last_replay != null


static func load_from_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Replay file does not exist: %s" % path}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return {"ok": false, "error": "Replay file is not a JSON object."}
	var payload: Dictionary = parsed
	var replay_data: Variant = payload.get("replay")
	if not replay_data is Dictionary:
		return {"ok": false, "error": "Replay envelope has no replay object."}
	var stored_schema_version: int = int((replay_data as Dictionary).get("schema_version", 0))
	if stored_schema_version != ReplayData.CURRENT_SCHEMA_VERSION:
		return {
			"ok": false,
			"error": "Unsupported replay schema v%d; this build requires v%d." % [
				stored_schema_version,
				ReplayData.CURRENT_SCHEMA_VERSION,
			],
		}
	var replay := ReplayData.from_dictionary(replay_data)
	var stored_input_hash: String = String(payload.get("run_log", {}).get("input_hash", ""))
	if not stored_input_hash.is_empty() and replay.canonical_input_hash() != stored_input_hash:
		return {"ok": false, "error": "Replay input hash verification failed."}
	return {
		"ok": true,
		"replay": replay,
		"run_log": Dictionary(payload.get("run_log", {})).duplicate(true),
	}


func _on_run_started(run_id: int) -> void:
	if not is_instance_valid(_session) or _session.compiled_chart == null or _session.rule_set == null:
		return
	_active_replay = ReplayData.new()
	_active_replay.replay_id = "%s:%d:%d" % [
		_session.stage_definition.stage_id,
		run_id,
		int(Time.get_unix_time_from_system()),
	]
	_active_replay.chart_hash = _session.compiled_chart.content_hash
	_active_replay.rules_hash = ChartCompiler.rules_hash(_session.rule_set)
	_active_replay.song_timing_hash = _song_timing_hash()
	# InputRouter 的时间戳已经位于补偿后的判定轴，再设置 ReplayData 偏移会重复校准。
	_active_replay.captured_input_offset_us = 0
	_active_replay.loadout_hash = _loadout_hash
	_active_replay.build_id = _build_hash()
	_active_replay.inputs.clear()
	_discard_current_run = _session.is_replay_playback()
	is_recording = not _discard_current_run
	if is_recording:
		recording_started.emit(_active_replay)


func _on_replay_mode_changed(enabled: bool) -> void:
	if enabled and _active_replay != null:
		_discard_current_run = true
		is_recording = false


func _on_semantic_input(sample: SemanticInputSample) -> void:
	if not is_recording or _discard_current_run or sample == null or not is_instance_valid(_session):
		return
	if _session.state not in [GameplayTypes.StageState.PREROLL, GameplayTypes.StageState.PLAYING]:
		return
	_active_replay.inputs.append(SemanticInputSample.create(
		sample.timestamp_us,
		sample.sequence,
		sample.kind,
		sample.tune_vector
	))


func _on_timeline_seeked(_song_time_sec: float) -> void:
	# Seek 前后的输入不属于同一条连续时间线。当前格式尚未记录回放起点，
	# 因此只能丢弃 Seek 前样本，避免把两段时间线拼成一份数据。
	if _active_replay != null and is_recording:
		_active_replay.inputs.clear()


func _on_result_ready(result: Dictionary) -> void:
	is_recording = false
	if _active_replay == null or _discard_current_run:
		_active_replay = null
		return
	var result_digest: String = String(result.get("result_digest", ""))
	if not bool(result.get("aborted", false)):
		_active_replay.expected_result_digest = result_digest
	last_replay = _active_replay
	last_run_log = {
		"saved_at_unix_sec": int(Time.get_unix_time_from_system()),
		"stage_id": _session.stage_definition.stage_id,
		"run_id": int(result.get("run_id", _session.run_id)),
		"chart_hash": _active_replay.chart_hash,
		"rules_hash": _active_replay.rules_hash,
		"build_hash": _active_replay.build_id,
		"loadout_hash": _active_replay.loadout_hash,
		"song_timing_hash": _active_replay.song_timing_hash,
		"audio_calibration_us": roundi(_session.song_clock.audio_calibration_sec * 1_000_000.0),
		"input_compensation_us": roundi(_session.song_clock.input_compensation_sec * 1_000_000.0),
		"input_hash": _active_replay.canonical_input_hash(),
		"result_digest": result_digest,
		"result": result.duplicate(true),
	}
	var save_result: Dictionary = _save_atomic(output_path, {
		"replay": _active_replay.to_dictionary(),
		"run_log": last_run_log,
	})
	if bool(save_result.get("ok", false)):
		replay_saved.emit(output_path, last_replay, last_run_log.duplicate(true))
	else:
		replay_save_failed.emit(output_path, String(save_result.get("error", "Unknown replay save error.")))
	_active_replay = null


func _song_timing_hash() -> String:
	var song: SongDefinition = _session.stage_definition.song
	return ReplayData.compute_song_timing_hash(
		song.song_id,
		song.first_beat_offset_sec,
		_session.compiled_chart.content_hash
	)


func _build_hash() -> String:
	var application_version: String = String(ProjectSettings.get_setting("application/config/version", "dev"))
	return ("%s|%s" % [application_version, JSON.stringify(Engine.get_version_info())]).sha256_text()


func _save_atomic(path: String, payload: Dictionary) -> Dictionary:
	# 先写临时文件并自校验，再用备份进行替换；任何一步失败都尽量恢复旧 Replay。
	var absolute_directory: String = ProjectSettings.globalize_path(path.get_base_dir())
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "error": "Cannot create replay directory: %s" % error_string(directory_error)}

	var temp_path: String = path + ".tmp"
	var backup_path: String = path + ".bak"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Cannot open replay temp file: %s" % FileAccess.get_open_error()}
	file.store_string(JSON.stringify(payload, "\t", true))
	file.flush()
	file = null

	var temp_verification: Dictionary = load_from_path(temp_path)
	if not bool(temp_verification.get("ok", false)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
		return {"ok": false, "error": "Replay temp verification failed: %s" % temp_verification.get("error", "")}

	var absolute_path: String = ProjectSettings.globalize_path(path)
	var absolute_temp: String = ProjectSettings.globalize_path(temp_path)
	var absolute_backup: String = ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(absolute_backup)
	var had_previous: bool = FileAccess.file_exists(path)
	if had_previous:
		var backup_error: Error = DirAccess.rename_absolute(absolute_path, absolute_backup)
		if backup_error != OK:
			DirAccess.remove_absolute(absolute_temp)
			return {"ok": false, "error": "Cannot stage previous replay: %s" % error_string(backup_error)}

	var replace_error: Error = DirAccess.rename_absolute(absolute_temp, absolute_path)
	if replace_error != OK:
		if had_previous:
			DirAccess.rename_absolute(absolute_backup, absolute_path)
		return {"ok": false, "error": "Cannot replace replay file: %s" % error_string(replace_error)}

	var final_verification: Dictionary = load_from_path(path)
	if not bool(final_verification.get("ok", false)):
		DirAccess.remove_absolute(absolute_path)
		if had_previous:
			DirAccess.rename_absolute(absolute_backup, absolute_path)
		return {"ok": false, "error": "Final replay verification failed: %s" % final_verification.get("error", "")}
	if had_previous:
		DirAccess.remove_absolute(absolute_backup)
	return {"ok": true}
