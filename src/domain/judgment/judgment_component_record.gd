class_name JudgmentComponentRecord
extends RefCounted

## 复合判定中的一个分量，例如 Hold 头尾、调频覆盖率或疾振完成度。
## JudgmentRecord 会取所有分量中的最差等级作为整项成绩。

## 子判定种类，例如 timing、sustain 或 release；决定其他字段的解释方式。
var kind: StringName = &"timing"
## 目标在谱面中的绝对 tick，供写谱器定位；数值越大位置越晚。
var target_tick: int = 0
## 目标在歌曲时间轴中的整数微秒。
var target_us: int = 0
## 实际输入或采样发生的歌曲微秒。
var observed_us: int = 0
## observed_us - target_us；单位微秒，负值表示早、正值表示晚。
var error_us: int = 0
## 非时间型机制使用的归一化误差值；数值越大表示偏离目标越多。
var error_value: float = 0.0
## 此分项的 JudgmentGrade 枚举值；数值越大判定越差。
var grade: int = GameplayTypes.JudgmentGrade.MISS
## 机制专属附加信息；不得依赖字典遍历顺序参与判定。
var metadata: Dictionary = {}


static func timing(
		p_kind: StringName,
		p_target_tick: int,
		p_target_us: int,
		p_observed_us: int,
		p_grade: int
) -> JudgmentComponentRecord:
	var component := JudgmentComponentRecord.new()
	component.kind = p_kind
	component.target_tick = p_target_tick
	component.target_us = p_target_us
	component.observed_us = p_observed_us
	component.error_us = p_observed_us - p_target_us
	component.grade = p_grade
	return component


static func value_error(
		p_kind: StringName,
		p_target_tick: int,
		p_target_us: int,
		p_error_value: float,
		p_grade: int
) -> JudgmentComponentRecord:
	var component := JudgmentComponentRecord.new()
	component.kind = p_kind
	component.target_tick = p_target_tick
	component.target_us = p_target_us
	component.observed_us = p_target_us
	component.error_value = p_error_value
	component.grade = p_grade
	return component


func to_dictionary() -> Dictionary:
	return {
		"kind": String(kind),
		"target_tick": target_tick,
		"target_us": target_us,
		"observed_us": observed_us,
		"error_us": error_us,
		"error_value": error_value,
		"grade": grade,
		"metadata": metadata.duplicate(true),
	}
