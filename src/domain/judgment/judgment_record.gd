class_name JudgmentRecord
extends RefCounted

## 一个完整玩法单位的最终判定记录。除等级外还保存稳定 ID、伤害组和各分量，
## 是计分、扣血、HUD、音效与 Replay 结果校验共同读取的事实来源。

## 全局递增序号确保同一微秒产生的多个结果仍有确定顺序。
var sequence: int = 0
## 被结算单位的全谱稳定 ID；与编译谱事件 ID 对应。
var unit_id: String = ""
## 机制类型键，例如 tap、hold、tuning、su 或 rapid。
var unit_kind: StringName = &"tap"
## 阵营枚举：ZHU 为生、XUAN 为死、SU 为双钟调频目标。
var affinity: int = GameplayTypes.Affinity.SU
## 判定单位头部的绝对谱面 tick。
var start_tick: int = 0
## 判定单位尾部的绝对谱面 tick；Tap 与 start_tick 相同。
var end_tick: int = 0
## 此记录最终生成时的歌曲微秒，不一定等于目标 tick 对应时间。
var finalized_at_us: int = 0
## 汇总后的 JudgmentGrade；通常取各必要分项中最差档。
var grade: int = GameplayTypes.JudgmentGrade.MISS
## 谱面逻辑组 ID，例如双押组；空值表示无组合。
var group_id: String = ""
## 扣血去重组 ID；相同值的多个 MISS 最多扣一次魂火。
var damage_group_id: String = ""
## 构成总等级的分项记录，例如 Hold 的头、持续和尾。
var components: Array[JudgmentComponentRecord] = []
## 机制专属附加数据；不得依赖字典遍历顺序参与确定性结果。
var metadata: Dictionary = {}


func recompute_grade() -> int:
	grade = GameplayTypes.JudgmentGrade.PERFECT
	for component in components:
		grade = maxi(grade, component.grade)
	return grade


func to_dictionary() -> Dictionary:
	var component_data: Array[Dictionary] = []
	for component in components:
		component_data.append(component.to_dictionary())
	return {
		"sequence": sequence,
		"unit_id": unit_id,
		"unit_kind": String(unit_kind),
		"affinity": affinity,
		"start_tick": start_tick,
		"end_tick": end_tick,
		"finalized_at_us": finalized_at_us,
		"grade": grade,
		"group_id": group_id,
		"damage_group_id": damage_group_id,
		"components": component_data,
		"metadata": metadata.duplicate(true),
	}


func canonical_line() -> String:
	var values := PackedStringArray([
		str(sequence), unit_id, String(unit_kind), str(affinity), str(start_tick), str(end_tick),
		str(finalized_at_us), str(grade), group_id, damage_group_id,
	])
	for component in components:
		values.append("%s:%d:%d:%d:%d:%.9f:%d" % [
			component.kind,
			component.target_tick,
			component.target_us,
			component.observed_us,
			component.error_us,
			component.error_value,
			component.grade,
		])
	return "|".join(values)
