@tool
class_name ParallaxHandheldDriver
extends RefCounted

## 手持式模拟镜头：连续随机漂移、重新持稳时的修正与不规则细抖叠加。
## 纯函数：同一时间总是同一偏移，因此暂停自然冻结、Seek/重试可复现，
## 不逐帧累计、不依赖帧率。偏移单位是设计画布像素。

## 主晃动幅度，单位设计画布像素；两轴分别对应横向与纵向。
var amplitude_px: Vector2 = Vector2(96.0, 66.0)
## 慢漂移的时间尺度，单位秒；不是重复周期，减小会加快全部晃动。
var base_period_sec: float = 5.2
## 随机轨迹种子。同一种子和歌曲时间产生相同画面，支持预览、定位与重试。
var noise_seed: int = 73129:
	set(value):
		noise_seed = value
		_noise.seed = value

var _noise := FastNoiseLite.new()


func _init() -> void:
	_noise.seed = noise_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.fractal_type = FastNoiseLite.FRACTAL_NONE

## 返回 song_time_sec 对应的摄像头偏移；时间起点（t=0）偏移为零。
func offset_at(song_time_sec: float) -> Vector2:
	var t := maxf(song_time_sec, 0.0)
	var time := t / maxf(base_period_sec, 0.01)
	# 随机包络让镜头有松弛和紧张段落，避免持续等强度振动；不使用逐帧随机跳点。
	var activity := smoothstep(-0.45, 0.55, _noise.get_noise_2d(time * 0.7, 83.0))
	var drift := _sample_axes(time * 0.9, 13.0)
	var correction := _sample_axes(time * 1.8, 39.0)
	var tremor := _sample_axes(time * 4.0, 67.0)
	var offset := drift * 1.05 + correction * lerpf(0.12, 0.25, activity) + tremor * lerpf(0.005, 0.015, activity)
	# 开场平滑进入，负时间和零时刻保持原点；无积分，不会长期漂走。
	return offset * amplitude_px * smoothstep(0.0, 1.5, t)


func _sample_axes(time: float, channel: float) -> Vector2:
	return Vector2(_noise.get_noise_2d(time, channel), _noise.get_noise_2d(time + 119.0, channel + 27.0))
