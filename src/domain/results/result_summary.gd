class_name ResultSummary
extends RefCounted

## 一局结束后的结构化结果，供结算界面、存档和 Replay 摘要共同使用。

## 是否完成全部理论判定且未失败。
var cleared: bool = false
## 是否因魂火耗尽进入失败终态；与正常 cleared 互斥。
var failed: bool = false
## 是否判定数量完整、无 MISS 且没有会断连的乱按。
var full_combo: bool = false
## 是否在 Full Combo 基础上所有判定均为 PERFECT。
var all_perfect: bool = false
## 由各 JudgmentRecord 和 Combo 倍率累计的原始分。
var raw_score: int = 0
## 计分器实时累计的 Perfect 奖励分，结算不再重复计算。
var bonus_score: int = 0
## 最终分数，等于 raw_score + bonus_score。
var total_score: int = 0
## 本局达到的最高 Combo。
var max_combo: int = 0
## 结算时剩余魂火，可在非致死调试关中为负数。
var soul_fire: int = 0
## 实际生成的 JudgmentRecord 数量。
var judgment_count: int = 0
## CompiledChart 声明的理论判定单位总数；用于检查是否漏结算。
var expected_judgment_count: int = 0
## 最终等级为 MISS 的判定数量。
var miss_count: int = 0
## 按规则会断 Combo 的乱按数量。
var stray_break_count: int = 0
## 本次结算是否满足普通随从奖励条件；真正写存档由上层完成。
var grants_base_pet: bool = false
## 本次结算是否满足进阶随从奖励条件。
var grants_advanced_pet: bool = false
## 以 JudgmentGrade 枚举值为键的各档数量。
var grade_counts: Dictionary = {
	"PERFECT": 0,
	"GOOD": 0,
	"PASS": 0,
	"MISS": 0,
}


func to_dictionary() -> Dictionary:
	return {
		"cleared": cleared,
		"failed": failed,
		"full_combo": full_combo,
		"all_perfect": all_perfect,
		# 保留简写键，兼容已有 Replay 测试数据和旧 UI 数据迁移。
		"fc": full_combo,
		"ap": all_perfect,
		"raw_score": raw_score,
		"bonus_score": bonus_score,
		"score": total_score,
		"max_combo": max_combo,
		"soul_fire": soul_fire,
		"judgment_count": judgment_count,
		"expected_judgment_count": expected_judgment_count,
		"miss_count": miss_count,
		"stray_break_count": stray_break_count,
		"grade_counts": grade_counts.duplicate(true),
		"grants_base_pet": grants_base_pet,
		"grants_advanced_pet": grants_advanced_pet,
	}
