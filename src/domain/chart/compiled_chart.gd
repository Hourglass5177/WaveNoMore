class_name CompiledChart
extends RefCounted

## SongChart 的只读运行时形态。所有关键 tick 已换算为整数微秒，
## 玩法引擎共享这份数据，避免各自重复解释谱面资源。

## 编译此谱时采用的 SongChart 结构版本，用于诊断缓存是否过期。
var schema_version: int = 0
## 来源谱面的稳定 ID；用于日志、Replay 身份和结果归档，不是显示名称。
var chart_id: String = ""
## 来源谱面的难度稳定 ID；同一歌曲的不同难度应使用不同值。
var difficulty_id: String = ""
## 每四分音符的 tick 数；运行时主要使用微秒，但保留它供编辑器和诊断反查节拍。
var ppq: int = 480
## 已累计所有 BPM 段与偏移的时间映射，负责 tick 与整数微秒双向换算。
var tempo_map: TempoMap
## 编译后的 Tap/Hold 数组；每项同时含稳定 ID、tick、start_us/end_us 和判定语义。
var notes: Array[Dictionary] = []
## 编译后的调频开放区域；只决定何时允许改变频率，本身不产生判定。
var tuning_fields: Array[Dictionary] = []
## 编译后的单侧调频滑条；同 unit_id 的生、死两条由 TuningEngine 合并结算。
var tuning_sliders: Array[Dictionary] = []
## 编译后的素音凝现事件；精确位置须在运行时由真实波前交点求得。
var su_manifestations: Array[Dictionary] = []
## 编译后的疾振区域；每项包含目标次数、防抖微秒与交替要求。
var rapid_regions: Array[Dictionary] = []
## 编译后的段落标记；只供教学、工具和演出定位，不产生判定。
var sections: Array[Dictionary] = []
## 作者声明的谱面结束绝对 tick；数值越大，谱面尾点越晚。
var end_tick: int = 0
## end_tick 经 TempoMap 换算后的歌曲微秒，不含额外 MISS 收尾窗口。
var end_time_us: int = 0
## 完整演奏应产生的 JudgmentRecord 数；用于检测漏结算并推导 FC/AP。
var theoretical_unit_count: int = 0
## 只覆盖影响玩法的规范化内容，用于校验 Replay 是否属于本谱。
var content_hash: String = ""


func gameplay_units_copy() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.append_array(notes.duplicate(true))
	# 双侧滑条共享 unit_id 时只代表一个判定单位，不能在结果统计中重复出现。
	var seen_tuning_units: Dictionary = {}
	for slider: Dictionary in tuning_sliders:
		var unit_id: String = str(slider.get("unit_id", slider.get("id", "")))
		if seen_tuning_units.has(unit_id):
			continue
		seen_tuning_units[unit_id] = true
		result.append(slider.duplicate(true))
	result.append_array(rapid_regions.duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["start_us"]) != int(b["start_us"]):
			return int(a["start_us"]) < int(b["start_us"])
		return String(a["id"]) < String(b["id"])
	)
	return result
