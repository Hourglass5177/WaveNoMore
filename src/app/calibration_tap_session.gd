class_name CalibrationTapSession
extends RefCounted
## 跟拍只估计玩家/输入链相对参考音的偏差，不把它解释成设备输出延迟。

const PREPARE_BEATS := 4
const SAMPLE_BEATS := 24
const MIN_SAMPLES := 12
const BEAT_SECONDS := 0.6
const LEAD_SECONDS := 0.5
const MATCH_WINDOW_SECONDS := 0.27

var base_input_ms := 0.0
var taps: Dictionary = {}

func begin(input_ms: float) -> void:
	base_input_ms = input_ms
	taps.clear()

func target_seconds(index: int) -> float:
	return LEAD_SECONDS + (PREPARE_BEATS + index) * BEAT_SECONDS

func finish_seconds() -> float:
	return target_seconds(SAMPLE_BEATS - 1) + BEAT_SECONDS

func add_tap(audio_seconds: float) -> bool:
	# 和 SongClock 相同：输入补偿正值把收到的按键映射到更早时刻。
	var judged_seconds := audio_seconds - base_input_ms / 1000.0
	var index := roundi((judged_seconds - target_seconds(0)) / BEAT_SECONDS)
	if index < 0 or index >= SAMPLE_BEATS or taps.has(index): return false
	var error_seconds := judged_seconds - target_seconds(index)
	if absf(error_seconds) > MATCH_WINDOW_SECONDS: return false
	# 一拍仅接收第一次有效输入，双键和重复敲击不会扩大样本权重。
	taps[index] = error_seconds * 1000.0
	return true

func result() -> Dictionary:
	var errors: Array[float] = []
	for value in taps.values(): errors.append(float(value))
	errors.sort()
	var center := _median(errors)
	var deviations: Array[float] = []
	for value in errors: deviations.append(absf(value - center))
	deviations.sort()
	var mad := _median(deviations)
	var inliers: Array[float] = []
	for value in errors:
		if absf(value - center) <= maxf(25.0, 3.0 * mad): inliers.append(value)
	var median_error := _median(inliers)
	var suggestion := roundi(base_input_ms + median_error)
	return {
		"count": errors.size(), "used": inliers.size(), "excluded": errors.size() - inliers.size(),
		"missing": SAMPLE_BEATS - errors.size(), "median_error_ms": median_error,
		"mad_ms": mad, "suggested_input_ms": suggestion,
		"can_apply": inliers.size() >= MIN_SAMPLES and absi(suggestion) <= 300,
	}

static func _median(values: Array[float]) -> float:
	if values.is_empty(): return 0.0
	var middle := values.size() / 2
	return values[middle] if values.size() % 2 else (values[middle - 1] + values[middle]) * 0.5

static func create_reference() -> AudioStreamWAV:
	# 提前把所有起音写入同一条 PCM，参考节拍不受渲染帧触发误差影响。
	var factory = preload("res://src/presentation/audio/graybox_click_track_factory.gd")
	var bright: AudioStreamWAV = factory.create_transient(470.0, 0.085, 0.25, 0.30)
	var dark: AudioStreamWAV = factory.create_transient(315.0, 0.095, 0.27, 0.55)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = bright.mix_rate
	var pcm := PackedByteArray()
	pcm.resize(ceili((LEAD_SECONDS + (PREPARE_BEATS + SAMPLE_BEATS) * BEAT_SECONDS + 0.6) * stream.mix_rate) * 2)
	for beat in PREPARE_BEATS + SAMPLE_BEATS:
		var transient := bright if beat % 4 == 0 else dark
		var offset := roundi((LEAD_SECONDS + beat * BEAT_SECONDS) * stream.mix_rate) * 2
		for index in transient.data.size(): pcm[offset + index] = transient.data[index]
	stream.data = pcm
	return stream
