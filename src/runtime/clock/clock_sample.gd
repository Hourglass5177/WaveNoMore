class_name ClockSample
extends RefCounted

## SongClock 发布的一帧时间快照。对象按约定只读，同时携带音频、歌曲、判定和视觉
## 四种时间，消费者不应混用或回写字段。

## 生成快照时的单调系统时间，单位为微秒；来自 `Time.get_ticks_usec()`。
var capture_usec: int = 0
## 时钟世代号。每次重新起播、停止或跳转都会变化，用于识别旧时间线上的数据。
var generation: int = 0
## 取样时的 SongClock.State 枚举值，例如播放、暂停或停止。
var state: int = 0
## 从音频设备观测到的实际播放位置，单位为秒，只用于诊断漂移。
var audio_time_raw_sec: float = 0.0
## 由单调系统时钟推导的歌曲主时间，单位为秒；所有子时间轴都以它为基准。
var song_time_sec: float = 0.0
## 应用输入补偿后的判定时间，单位为秒；GameplaySimulation 使用这一字段。
var judge_time_sec: float = 0.0
## 应用画面提前量后的视觉时间，单位为秒；表现调度器使用这一字段。
var visual_time_sec: float = 0.0
## `audio_time_raw_sec - song_time_sec`，单位为秒；正值表示实际音频比主时钟靠前。
var audio_drift_sec: float = 0.0


func duplicate_sample() -> ClockSample:
	var copy := ClockSample.new()
	copy.capture_usec = capture_usec
	copy.generation = generation
	copy.state = state
	copy.audio_time_raw_sec = audio_time_raw_sec
	copy.song_time_sec = song_time_sec
	copy.judge_time_sec = judge_time_sec
	copy.visual_time_sec = visual_time_sec
	copy.audio_drift_sec = audio_drift_sec
	return copy
