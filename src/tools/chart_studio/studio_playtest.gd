class_name StudioPlaytest
extends Node
## 只跟踪自己启动的进程。窗口关闭后清理快照，不接管其他游戏窗口。
signal changed(busy: bool, caption: String)
signal notice(message: String)
signal executable_needed
signal finished
var executable := ""
var pid := -1
var busy := false
var temp_root := "user://chart_studio/trials"
var _snapshot_song: SongDefinition
var _snapshot_charts: Array[SongChart] = []
var _source_directory := ""
var _folder := ""
var _request := ""
var _task := -1
var _packed := {"error": ""}
var _started_ms := 0
var _last_stage := ""
var _timeout_reported := false
var _failure_message := ""

func _ready() -> void:
	var settings := ConfigFile.new()
	settings.load("user://chart_studio/settings.cfg")
	executable = str(settings.get_value("trial", "game_executable", ""))
	_cleanup_abandoned()

func start(doc: StudioDocument) -> void:
	if busy: return
	# 在等待选 EXE 或后台打包之前冻结编辑版本。
	_snapshot_song = doc.song.duplicate(true)
	_snapshot_charts.assign([doc.chart().duplicate(true)])
	_source_directory = doc.directory
	_set_state(true, "准备试玩…")
	if executable.is_empty():
		var bundled := OS.get_executable_path().get_base_dir().path_join("game/minghe.exe")
		if FileAccess.file_exists(bundled): executable = bundled
	if executable.is_empty() or not FileAccess.file_exists(executable): executable_needed.emit()
	else: _package()

func choose_executable(path: String) -> void:
	executable = path
	var settings := ConfigFile.new()
	settings.load("user://chart_studio/settings.cfg")
	settings.set_value("trial", "game_executable", path)
	DirAccess.make_dir_recursive_absolute("user://chart_studio")
	settings.save("user://chart_studio/settings.cfg")
	if busy and pid <= 0 and _task < 0: _package()

func cancel_selection() -> void:
	if pid <= 0 and _task < 0: _set_state(false, "在游戏中试玩")

func _package() -> void:
	_request = Crypto.new().generate_random_bytes(12).hex_encode()
	_folder = temp_root.path_join("trial_" + _request)
	DirAccess.make_dir_recursive_absolute(_folder)
	_set_state(true, "正在打包试玩…")
	_packed = {"error": ""}
	_task = WorkerThreadPool.add_task(func():
		_packed.error = ChartPackageWriter.write(_snapshot_song, _snapshot_charts, _source_directory, _folder.path_join("chart.zip")))

func _process(_delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if not _packed.error.is_empty():
			notice.emit(_packed.error); _remove_trial(_folder); _set_state(false, "在游戏中试玩")
		else: _launch()
	if pid <= 0: return
	_read_status()
	if not OS.is_process_running(pid):
		pid = -1
		var saved_log := "user://chart_studio/last-trial.log"
		if FileAccess.file_exists(_folder.path_join("game.log")): DirAccess.copy_absolute(_folder.path_join("game.log"), saved_log)
		_remove_trial(_folder)
		_set_state(false, "在游戏中试玩")
		finished.emit()
		if _last_stage == "ready": notice.emit("试玩已结束")
		else: notice.emit((_failure_message if not _failure_message.is_empty() else "游戏已退出但未完成加载；可在“试玩设置”重新选择配套游戏。") + "\n日志：" + ProjectSettings.globalize_path(saved_log))
	elif _last_stage.is_empty() and not _timeout_reported and Time.get_ticks_msec() - _started_ms > 15000:
		_timeout_reported = true
		notice.emit("游戏未响应或不支持一键试玩。请关闭刚启动的窗口，在“试玩设置”选择配套游戏。日志：" + ProjectSettings.globalize_path(_folder.path_join("game.log")))

func _launch() -> void:
	var args := PackedStringArray(["--log-file", ProjectSettings.globalize_path(_folder.path_join("game.log")), "--", "--play-chart", ProjectSettings.globalize_path(_folder.path_join("chart.zip")), "--difficulty", _snapshot_charts[0].difficulty_id, "--trial-status", ProjectSettings.globalize_path(_folder.path_join("status.json")), "--trial-request", _request, "--trial-log", ProjectSettings.globalize_path(_folder.path_join("game.log"))])
	pid = OS.create_process(executable, args, false)
	if pid <= 0:
		notice.emit("无法启动游戏：" + executable)
		_remove_trial(_folder); _set_state(false, "在游戏中试玩")
		return
	var owner_file := FileAccess.open(_folder.path_join("owner.json"), FileAccess.WRITE)
	if owner_file != null: owner_file.store_string(JSON.stringify({"pid": pid})); owner_file.close()
	_started_ms = Time.get_ticks_msec(); _last_stage = ""; _timeout_reported = false; _failure_message = ""
	_set_state(true, "正在启动游戏…")

func _read_status() -> void:
	var path := _folder.path_join("status.json")
	if not FileAccess.file_exists(path): return
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary or value.get("request_id") != _request or value.get("interface_version") != ChartTrialLaunch.INTERFACE_VERSION: return
	var stage := str(value.get("stage", ""))
	if stage == _last_stage: return
	_last_stage = stage
	if stage == "ready":
		_set_state(true, "试玩进行中")
		notice.emit("关闭试玩窗口后可再次启动；可以继续编辑，游戏使用启动时的谱面。")
	elif stage == "error":
		_failure_message = str(value.get("message", "加载失败"))
		_set_state(true, "试玩加载失败")
		notice.emit(str(value.get("message", "加载失败")) + "\n日志：" + ProjectSettings.globalize_path(_folder.path_join("game.log")))
	else: _set_state(true, "游戏正在加载…")

func _set_state(value: bool, caption: String) -> void:
	busy = value
	changed.emit(busy, caption)

func _cleanup_abandoned() -> void:
	if not DirAccess.dir_exists_absolute(temp_root): return
	for folder in DirAccess.get_directories_at(temp_root):
		if not folder.begins_with("trial_"): continue
		var path := temp_root.path_join(folder)
		var owner: Variant = JSON.parse_string(FileAccess.get_file_as_string(path.path_join("owner.json"))) if FileAccess.file_exists(path.path_join("owner.json")) else {}
		if owner is Dictionary and int(owner.get("pid", -1)) > 0 and OS.is_process_running(int(owner.pid)): continue
		_remove_trial(path)

func _remove_trial(path: String) -> void:
	# 临时目录由本模块生成，仅删除明确属于一次试玩的文件。
	for name in ["chart.zip", "chart.zip.tmp", "status.json", "status.json.tmp", "owner.json", "game.log"]:
		if FileAccess.file_exists(path.path_join(name)): DirAccess.remove_absolute(path.path_join(name))
	DirAccess.remove_absolute(path)

func _exit_tree() -> void:
	if _task >= 0: WorkerThreadPool.wait_for_task_completion(_task)
	# 运行中的子进程仍需读取快照；下一次启动再整理遗留文件。
