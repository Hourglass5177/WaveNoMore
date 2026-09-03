class_name HealthEngine
extends RefCounted

## 魂火与失败状态的纯逻辑。按 damage_group_id 去重，保证同一组双押漏击
## 只扣一次血；调试关可启用 nonlethal，让魂火降到负数但不结束关卡。

## 当前规则引用；读取满魂火、MISS 伤害和乱按伤害开关。
var _rules: GameplayRuleSet
## 当前魂火整数值；正常关最低为 0，非致死调试关允许继续降为负数。
var soul_fire: int = 0
## 是否已因魂火耗尽失败；一旦为 true，本局不再接收玩法输入。
var failed: bool = false
## 已扣过血的 damage_group_id 集合，防止同一组合判定重复伤害。
var _damaged_groups: Dictionary = {}
## 调试关开关：保留扣血数值，但不把魂火耗尽转成 failed。
var _nonlethal: bool = false


func configure(rules: GameplayRuleSet, nonlethal: bool = false) -> void:
	_rules = rules
	_nonlethal = nonlethal
	reset()


func reset() -> void:
	soul_fire = _rules.max_soul_fire if _rules != null else 0
	failed = soul_fire <= 0 and not _nonlethal
	_damaged_groups.clear()


func apply_judgment(record: JudgmentRecord) -> int:
	if record.grade != GameplayTypes.JudgmentGrade.MISS:
		return 0
	var damage_group: String = record.damage_group_id if not record.damage_group_id.is_empty() else record.unit_id
	return _apply_damage_group(damage_group, _rules.miss_damage)


func apply_stray(record: StrayInputRecord) -> int:
	if not record.damages:
		return 0
	return _apply_damage_group("stray:%d" % record.sequence, _rules.miss_damage)


func heal(amount: int) -> int:
	if amount <= 0 or failed:
		return 0
	var before: int = soul_fire
	soul_fire = mini(_rules.max_soul_fire, soul_fire + amount)
	return soul_fire - before


func has_damage_group(group_id: String) -> bool:
	return _damaged_groups.has(group_id)


func snapshot() -> Dictionary:
	return {
		"soul_fire": soul_fire,
		"max_soul_fire": _rules.max_soul_fire,
		"failed": failed,
		"nonlethal": _nonlethal,
		"damaged_group_count": _damaged_groups.size(),
	}


func _apply_damage_group(group_id: String, damage: int) -> int:
	if _damaged_groups.has(group_id):
		return 0
	_damaged_groups[group_id] = true
	var requested_damage: int = maxi(0, damage)
	if _nonlethal:
		soul_fire -= requested_damage
		failed = false
		return requested_damage
	var actual: int = mini(soul_fire, requested_damage)
	soul_fire -= actual
	if soul_fire <= 0:
		soul_fire = 0
		failed = true
	return actual
