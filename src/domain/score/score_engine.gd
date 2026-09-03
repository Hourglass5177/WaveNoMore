class_name ScoreEngine
extends RefCounted

## 分数与 Combo 的纯逻辑。每个 JudgmentRecord 只结算一次；乱按只按规则
## 决定是否断 Combo，不伪造额外判定。

## 当前关卡使用的只读规则引用。
var _rules: GameplayRuleSet
## 仅由 JudgmentRecord 累计的基础分，尚未包含随从等结算奖励。
var raw_score: int = 0
## 随从等外部系统追加的奖励分；不反向改变原始判定。
var bonus_score: int = 0
## 当前连续非 MISS 判定数；MISS 或规则指定的乱按会清零。
var combo: int = 0
## 本局曾达到的最高 Combo；当前 Combo 清零时不会下降。
var max_combo: int = 0
## 以 JudgmentGrade 枚举下标保存 PERFECT、GOOD、PASS、MISS 次数。
var grade_counts: PackedInt32Array = PackedInt32Array([0, 0, 0, 0])


func configure(rules: GameplayRuleSet) -> void:
	_rules = rules
	reset()


func reset() -> void:
	raw_score = 0
	bonus_score = 0
	combo = 0
	max_combo = 0
	grade_counts = PackedInt32Array([0, 0, 0, 0])


func apply_judgment(record: JudgmentRecord) -> int:
	if record.grade >= 0 and record.grade < grade_counts.size():
		grade_counts[record.grade] += 1
	if record.grade == GameplayTypes.JudgmentGrade.MISS:
		combo = 0
		raw_score += _rules.miss_score
		return _rules.miss_score
	combo += 1
	max_combo = maxi(max_combo, combo)
	var base: int = _base_score(record.grade)
	var progress: float = clampf(float(maxi(0, combo - 1)) / float(maxi(1, _rules.combo_steps_to_max)), 0.0, 1.0)
	var multiplier: float = lerpf(1.0, _rules.max_combo_multiplier, progress)
	var awarded: int = roundi(float(base) * multiplier)
	raw_score += awarded
	return awarded


func apply_stray(record: StrayInputRecord) -> void:
	if record.breaks_combo:
		combo = 0


func add_bonus(points: int) -> void:
	bonus_score += maxi(0, points)


func total_score() -> int:
	return raw_score + bonus_score


func snapshot() -> Dictionary:
	return {
		"raw_score": raw_score,
		"bonus_score": bonus_score,
		"score": total_score(),
		"combo": combo,
		"max_combo": max_combo,
		"grade_counts": Array(grade_counts),
	}


func _base_score(grade: int) -> int:
	match grade:
		GameplayTypes.JudgmentGrade.PERFECT: return _rules.perfect_score
		GameplayTypes.JudgmentGrade.GOOD: return _rules.good_score
		GameplayTypes.JudgmentGrade.PASS: return _rules.pass_score
	return _rules.miss_score
