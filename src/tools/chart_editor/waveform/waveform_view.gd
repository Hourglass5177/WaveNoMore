## 独立波形绘制控件，可供其他工具复用；当前主时间线有自己的叠加式波形绘制。
@tool
class_name MingheWaveformView
extends Control

## 当前要绘制的多级峰值缓存；为空时 `_draw()` 直接返回。
var waveform: MingheWaveformCache
## 视口最左侧对应的音频时间，单位为秒。
var view_start_sec: float = 0.0
## 横向缩放，单位为「像素/秒」；数值越大选择的缓存层级越细。
var pixels_per_second: float = 120.0
## 波形竖线的绘制颜色和透明度。
var tint: Color = Color(0.77, 0.79, 0.82, 0.72)


func set_waveform(value: MingheWaveformCache) -> void:
	waveform = value
	queue_redraw()


func set_view(start_sec: float, px_per_second: float) -> void:
	view_start_sec = start_sec
	pixels_per_second = maxf(10.0, px_per_second)
	queue_redraw()


func _draw() -> void:
	if waveform == null or waveform.sample_rate <= 0 or waveform.levels.is_empty():
		return
	var frames_per_pixel := float(waveform.sample_rate) / pixels_per_second
	var level_index := waveform.choose_level(frames_per_pixel)
	if level_index < 0:
		return
	var peaks: PackedVector2Array = waveform.levels[level_index]
	var block_frames := int(waveform.block_sizes[level_index])
	var center_y := size.y * 0.5
	var amplitude := size.y * 0.46
	var start_frame := maxi(0, floori(view_start_sec * float(waveform.sample_rate)))
	var first_peak := start_frame / block_frames
	var end_sec := view_start_sec + size.x / pixels_per_second
	var last_peak := mini(peaks.size() - 1, ceili(end_sec * float(waveform.sample_rate) / float(block_frames)))
	for peak_index in range(first_peak, last_peak + 1):
		var peak_time := float(peak_index * block_frames) / float(waveform.sample_rate)
		var x := (peak_time - view_start_sec) * pixels_per_second
		var peak := peaks[peak_index]
		draw_line(Vector2(x, center_y - peak.y * amplitude), Vector2(x, center_y - peak.x * amplitude), tint, 1.0)
