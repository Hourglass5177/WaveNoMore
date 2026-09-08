class_name PetEffectProfile
extends Resource
## 一局只读的随从参数。中性默认值表示未装备；不保存运行计数或访问存档。
@export_range(0.0, 1.0, 0.001) var perfect_score_bonus: float = 0.0
@export_range(0.0, 1.0, 0.001) var damage_reduction: float = 0.0
@export_range(0, 100, 1) var hold_head_bonus_ms: int = 0
@export_range(0, 200, 1) var hold_sustain_bonus_ms: int = 0
@export_range(0, 3, 1) var hold_grade_boost: int = 0

func promote(grade: int, unit_kind: StringName) -> int:
	return maxi(GameplayTypes.JudgmentGrade.PERFECT, grade - hold_grade_boost) if unit_kind == &"hold" else grade
