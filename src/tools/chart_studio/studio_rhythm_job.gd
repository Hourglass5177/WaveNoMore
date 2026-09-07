class_name StudioRhythmJob
extends Node
## 一个任务独占解码器和子进程；序号隔离换歌、取消后的旧结果。
signal updated(message: String)
signal completed(result: Dictionary)
const VERSION := "beat-this-final0-v1"
const FIT_VERSION := "local-grid-v3"
var busy := false
var _request := 0
var _pid := -1
var _thread: Thread
var _cancel: Array[bool] = [false]
var _folder := ""
var _cache := ""
var _fit_span: Array = []
var _phase := ""
var _poll := 0.0
var _model := ""
var _exe := ""

func start(path: String, span: Vector2, force := false) -> void:
	cancel()
	var request := _request
	while _thread != null:
		await get_tree().process_frame
		if request != _request: return
	_remove_pcm()
	var base := OS.get_executable_path().get_base_dir()
	if not OS.has_feature("minghe_chart_editor"):
		base = ProjectSettings.globalize_path("res://builds/chart-studio")
	_exe = base.path_join("rhythm_analyzer/rhythm_analyzer.exe")
	_model = base.path_join("rhythm_analyzer/models/final0.ckpt")
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null: updated.emit("无法读取音乐文件"); return
	var key := "%s|%s|%s|%s|%s" % [path, FileAccess.get_modified_time(path), source.get_length(), span, VERSION]
	_cache = "user://chart_studio/cache/rhythm_%s.json" % key.sha256_text()
	_fit_span = []
	if force: _discard_fit_caches()
	if not force and FileAccess.file_exists(_cache):
		var cached: Variant = JSON.parse_string(FileAccess.get_file_as_string(_cache))
		if cached is Dictionary and cached.has("beats"):
			# 旧版结果中的原始检测点仍有效；换拟合算法不再解码或加载模型。
			if _use_fit_cache(cached): return
			if str(cached.get("fit_version", "")) == FIT_VERSION:
				_store_result(cached); completed.emit(cached); updated.emit("已读取节奏分析缓存"); return
			_start_refit(cached); return
	if not FileAccess.file_exists(_exe) or not FileAccess.file_exists(_model):
		updated.emit("识别组件缺失，请使用包含 rhythm_analyzer 文件夹的完整开发包"); return
	_folder = "user://chart_studio/rhythm_jobs/%s_%s" % [Time.get_ticks_usec(), request]
	DirAccess.make_dir_recursive_absolute(_folder)
	busy = true; _cancel = [false]; _phase = "解码音频"; updated.emit(_phase)
	_thread = Thread.new()
	_thread.start(_decode.bind(path, span, _folder.path_join("audio.wav"), _cancel, AudioServer.get_mix_rate(), request))

func refit(raw: Dictionary, span: Vector2) -> void:
	cancel()
	var request := _request
	while _thread != null:
		await get_tree().process_frame
		if request != _request: return
	_remove_pcm()
	_fit_span = [span.x, span.y]
	if _use_fit_cache(raw): return
	_start_refit(raw)

func _fit_cache_path() -> String:
	return _cache.trim_suffix(".json") + ".%s.%s.json" % [FIT_VERSION, JSON.stringify(_fit_span).sha256_text().left(12)]

func _discard_fit_caches() -> void:
	# 明确要求重新识别后，旧全曲与选区拟合都失效；原始缓存仍保留到成功完成。
	var folder := _cache.get_base_dir()
	if not DirAccess.dir_exists_absolute(folder): return
	var prefix := _cache.get_file().trim_suffix(".json") + "."
	for file in DirAccess.get_files_at(folder):
		if file != _cache.get_file() and file.begins_with(prefix) and file.ends_with(".json"):
			DirAccess.remove_absolute(folder.path_join(file))

func _use_fit_cache(raw: Dictionary) -> bool:
	if _cache.is_empty() or not FileAccess.file_exists(_fit_cache_path()): return false
	var fitting: Variant = JSON.parse_string(FileAccess.get_file_as_string(_fit_cache_path()))
	if fitting is not Dictionary or str(fitting.get("fit_version", "")) != FIT_VERSION: return false
	var result := raw.duplicate(true); result.merge(fitting, true)
	completed.emit(result); updated.emit("已读取拍点与当前拟合缓存"); return true

func _start_refit(raw: Dictionary) -> void:
	if not FileAccess.file_exists(_exe): updated.emit("缺少节奏分析器，请重新解压完整开发包"); return
	_folder = "user://chart_studio/rhythm_jobs/%s_%s" % [Time.get_ticks_usec(), _request]
	DirAccess.make_dir_recursive_absolute(_folder)
	busy = true; _phase = "重新拟合已有拍点"; updated.emit(_phase)
	var input := {"request_id": _request, "raw": raw}
	if not _fit_span.is_empty(): input.fit_range = _fit_span
	_launch(input)

func _launch(input: Dictionary) -> void:
	StudioProjectIO.write_json(_folder.path_join("request.json"), input)
	_pid = OS.create_process(_exe, PackedStringArray(["--request", ProjectSettings.globalize_path(_folder.path_join("request.json")), "--result", ProjectSettings.globalize_path(_folder.path_join("result.json"))]), false)
	if _pid < 0: busy = false; updated.emit("无法启动节奏分析器")

func _store_result(data: Dictionary) -> void:
	if _cache.is_empty(): return
	# 原始检测和可替换的拟合结果分别保存；拟合版本不进入音频缓存键。
	var detection := data.duplicate(true)
	for key in ["fit", "fit_version", "fit_range", "refit_seconds"]: detection.erase(key)
	StudioProjectIO.write_json(_cache, detection)
	StudioProjectIO.write_json(_fit_cache_path(), {"fit": data.fit, "fit_version": FIT_VERSION, "fit_range": _fit_span})

func cancel() -> void:
	_request += 1; _cancel[0] = true
	if _pid > 0 and OS.is_process_running(_pid): OS.kill(_pid)
	_pid = -1; busy = false
	if _thread == null: _remove_pcm()
	updated.emit("已取消分析")

func _process(delta: float) -> void:
	if _thread != null and not _thread.is_alive():
		var result: Dictionary = _thread.wait_to_finish(); _thread = null
		if result.request_id == _request and busy:
			if result.has("error"): busy = false; updated.emit(result.error); return
			var input := {"request_id": _request, "audio": ProjectSettings.globalize_path(_folder.path_join("audio.wav")), "model": _model, "start": result.start}
			_launch(input)
	if not busy or _pid < 0: return
	_poll += delta
	if _poll < 0.1: return
	_poll = 0
	var output := _folder.path_join("result.json")
	if FileAccess.file_exists(output):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(output))
		if data is Dictionary and int(data.get("request_id", -1)) == _request:
			var phase := str(data.get("phase", ""))
			if phase != _phase: _phase = phase; updated.emit(str(data.get("error", phase)))
			if phase in ["完成", "失败"]:
				busy = false
				if phase == "完成":
					if str(data.get("fit_version", "")) != FIT_VERSION:
						updated.emit("识别组件版本过旧，请重新解压本次完整开发包"); _remove_pcm(); return
					_store_result(data); completed.emit(data)
				_remove_pcm(); return
	if not OS.is_process_running(_pid): busy = false; updated.emit("分析器提前退出，请查看组件是否完整"); _remove_pcm()

func _remove_pcm() -> void:
	var path := _folder.path_join("audio.wav")
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)

func _exit_tree() -> void:
	cancel()
	if _thread != null: _thread.wait_to_finish()
	_remove_pcm()

static func _decode(path: String, span: Vector2, target: String, cancelled: Array[bool], rate: float, request: int) -> Dictionary:
	var result := {"request_id": request, "start": maxf(0, span.x)}
	var stream := ChartJsonCodec.load_audio(path)
	if stream == null: result.error = "无法解码音乐"; return result
	var end := minf(stream.get_length(), span.y)
	if end <= result.start: result.error = "请选择有效的分析区间"; return result
	var player := stream.instantiate_playback(); player.start(result.start)
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null: result.error = "无法写入分析临时音频"; return result
	var frames := floori((end - result.start) * rate)
	file.store_buffer("RIFF".to_ascii_buffer()); file.store_32(36 + frames * 2)
	file.store_buffer("WAVEfmt ".to_ascii_buffer()); file.store_32(16)
	file.store_16(1); file.store_16(1); file.store_32(int(rate)); file.store_32(int(rate) * 2)
	file.store_16(2); file.store_16(16); file.store_buffer("data".to_ascii_buffer()); file.store_32(frames * 2)
	for start_frame in range(0, frames, 4096):
		if cancelled[0]: player.stop(); return result
		var samples := player.mix_audio(1, mini(4096, frames - start_frame))
		var bytes := PackedByteArray(); bytes.resize(samples.size() * 2)
		for i in samples.size(): bytes.encode_s16(i * 2, clampi(roundi((samples[i].x + samples[i].y) * 16383.5), -32768, 32767))
		file.store_buffer(bytes)
	player.stop(); file.close()
	return result
