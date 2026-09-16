class_name ResultEvaluator
extends RefCounted

## 将整局判定、乱按、分数和魂火汇总为通关、FC、AP 与随从奖励结果。
## 这里只解释已有记录，不再修改任何玩法状态。

static func evaluate(
		judgments: Array[JudgmentRecord],
		strays: Array[StrayInputRecord],
		score: ScoreEngine,
		health: HealthEngine,
		expected_judgment_count: int,
		damage_settled: bool = true,
		ghost_results: Array[Dictionary] = [],
		expected_ghost_count: int = 0
) -> ResultSummary:
	var result := ResultSummary.new()
	result.failed = health.failed
	result.judgment_count = judgments.size()
	result.expected_judgment_count = expected_judgment_count
	var every_perfect: bool = not judgments.is_empty()
	for judgment in judgments:
		var grade_name := GameplayTypes.grade_name(judgment.grade)
		result.grade_counts[grade_name] = int(result.grade_counts.get(grade_name, 0)) + 1
		if judgment.grade == GameplayTypes.JudgmentGrade.MISS:
			result.miss_count += 1
		if judgment.grade != GameplayTypes.JudgmentGrade.PERFECT:
			every_perfect = false
	for stray in strays:
		if stray.breaks_combo:
			result.stray_break_count += 1
	result.cleared = damage_settled and not result.failed and judgments.size() == expected_judgment_count
	# Ghost 不重复授予音符基础分，但漏击必须影响 FC；Good 击破也不能算 AP。
	result.ghost_counts = ghost_counts(ghost_results)
	result.expected_ghost_count = expected_ghost_count
	result.full_combo = result.cleared and result.miss_count == 0 and result.stray_break_count == 0 and int(result.ghost_counts.MISS) == 0 and int(result.ghost_counts.PERFECT) + int(result.ghost_counts.GOOD) == expected_ghost_count
	every_perfect = every_perfect and int(result.ghost_counts.GOOD) == 0
	result.all_perfect = result.full_combo and every_perfect
	result.raw_score = score.raw_score
	result.bonus_score = score.bonus_score
	result.total_score = score.total_score()
	result.max_combo = score.max_combo
	result.soul_fire = health.soul_fire
	result.grants_base_pet = result.cleared and result.full_combo
	result.grants_advanced_pet = result.cleared and result.all_perfect
	return result


static func ghost_counts(results: Array[Dictionary]) -> Dictionary:
	var counts := {"PERFECT": 0, "GOOD": 0, "MISS": 0}
	for event: Dictionary in results:
		var key := "PERFECT" if int(event.get("grade", GameplayTypes.JudgmentGrade.PERFECT)) == GameplayTypes.JudgmentGrade.PERFECT else "GOOD"
		counts[key] += int(event.get("hit_count", 0))
		counts.MISS += int(event.get("miss_count", 0))
	return counts
