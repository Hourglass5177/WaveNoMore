class_name RapidEngine
extends RefCounted

## 双钟疾振区域的计数判定器。区域内优先接管生死钟输入，
## 按防抖间隔和交替要求统计有效敲击，区域结束时只产出一条总判定。

## 本局规则引用；用于把最终有效敲击比例换算为判定档位。
var _rules: GameplayRuleSet
## 每个疾振区的已计次数、上次有效微秒、上次阵营和完成状态。
var _states: Array[Dictionary] = []
## 已完成但尚未由 GameplaySimulation 取走的疾振判定。
var _pending_records: Array[JudgmentRecord] = []
## 最近推进到的歌曲时间，单位微秒；极小值表示尚未开始。
var _current_time_us: int = -9_000_000_000_000_000
## 最近一次按下是否同时满足区域时段、防抖与交替要求；决定波的有效颜色。
var _last_press_qualified: bool = false


func configure(compiled: CompiledChart, rules: GameplayRuleSet) -> void:
	_rules = rules
	_states.clear()
	for region in compiled.rapid_regions:
		_states.append({
			"region": region.duplicate(true),
			"status": &"pending",
			"valid_strikes": 0,
			"invalid_strikes": 0,
			"last_valid_us": -1,
			"last_affinity": -1,
			"strike_times": [] as Array[int],
		})
	_pending_records.clear()
	_last_press_qualified = false
	_current_time_us = -9_000_000_000_000_000


func reset(compiled: CompiledChart, rules: GameplayRuleSet) -> void:
	configure(compiled, rules)


func can_consume(sample: SemanticInputSample) -> bool:
	if not sample.is_press() and not sample.is_release():
		return false
	return not _region_at(sample.timestamp_us).is_empty()


func handle_input(sample: SemanticInputSample) -> bool:
	_last_press_qualified = false
	var state: Dictionary = _region_at(sample.timestamp_us)
	if state.is_empty():
		return false
	if state["status"] == &"pending":
		state["status"] = &"active"
	if sample.is_release():
		return true
	var region: Dictionary = state["region"]
	if int(state["valid_strikes"]) >= int(region["required_strikes"]):
		return true
	var affinity: int = sample.affinity()
	var last_us: int = int(state["last_valid_us"])
	if last_us >= 0 and sample.timestamp_us - last_us < int(region["debounce_us"]):
		state["invalid_strikes"] = int(state["invalid_strikes"]) + 1
		return true
	if bool(region["must_alternate"]) and int(state["last_affinity"]) == affinity:
		state["invalid_strikes"] = int(state["invalid_strikes"]) + 1
		return true
	state["valid_strikes"] = int(state["valid_strikes"]) + 1
	state["last_valid_us"] = sample.timestamp_us
	state["last_affinity"] = affinity
	state["strike_times"].append(sample.timestamp_us)
	_last_press_qualified = true
	return true


func last_press_qualified() -> bool:
	return _last_press_qualified


func advance_to(time_us: int, _inclusive: bool = true) -> void:
	if time_us < _current_time_us:
		return
	_current_time_us = time_us
	for state in _states:
		var region: Dictionary = state["region"]
		if state["status"] == &"pending" and time_us >= int(region["start_us"]):
			state["status"] = &"active"
		if state["status"] == &"active" and time_us > int(region["end_us"]):
			_finalize_state(state, int(region["end_us"]), false)


func cancel_active(time_us: int) -> void:
	for state in _states:
		if state["status"] == &"active":
			_finalize_state(state, time_us, true)


func is_active_at(time_us: int) -> bool:
	return not _region_at(time_us).is_empty()


func is_active() -> bool:
	for state in _states:
		if state["status"] == &"active":
			return true
	return false


func current_ratio() -> float:
	for state in _states:
		if state["status"] != &"active":
			continue
		var required: int = maxi(1, int(state["region"]["required_strikes"]))
		return clampf(float(int(state["valid_strikes"])) / float(required), 0.0, 1.0)
	return 0.0


func drain_judgments() -> Array[JudgmentRecord]:
	var result: Array[JudgmentRecord] = _pending_records.duplicate()
	_pending_records.clear()
	return result


func _region_at(time_us: int) -> Dictionary:
	for state in _states:
		if state["status"] == &"judged":
			continue
		var region: Dictionary = state["region"]
		if time_us >= int(region["start_us"]) and time_us <= int(region["end_us"]):
			return state
	return {}


func _finalize_state(state: Dictionary, finalized_at_us: int, forced_miss: bool) -> void:
	if state["status"] == &"judged":
		return
	state["status"] = &"judged"
	var region: Dictionary = state["region"]
	var required: int = maxi(1, int(region["required_strikes"]))
	var valid: int = mini(int(state["valid_strikes"]), required)
	var ratio: float = float(valid) / float(required)
	var grade: int = GameplayTypes.JudgmentGrade.MISS
	if not forced_miss:
		if ratio >= _rules.rapid_perfect_ratio:
			grade = GameplayTypes.JudgmentGrade.PERFECT
		elif ratio >= _rules.rapid_good_ratio:
			grade = GameplayTypes.JudgmentGrade.GOOD
		elif ratio >= _rules.rapid_pass_ratio:
			grade = GameplayTypes.JudgmentGrade.PASS
	var component := JudgmentComponentRecord.value_error(&"rapid_count", int(region["end_tick"]), int(region["end_us"]), 1.0 - ratio, grade)
	component.metadata = {
		"valid_strikes": valid,
		"required_strikes": required,
		"invalid_strikes": int(state["invalid_strikes"]),
		"strike_times": state["strike_times"].duplicate(),
	}
	var record := JudgmentRecord.new()
	record.unit_id = String(region["id"])
	record.unit_kind = &"rapid"
	record.affinity = GameplayTypes.Affinity.SU
	record.start_tick = int(region["tick"])
	record.end_tick = int(region["end_tick"])
	record.finalized_at_us = finalized_at_us
	record.damage_group_id = String(region["damage_group_id"])
	record.components = [component] as Array[JudgmentComponentRecord]
	record.metadata = component.metadata.duplicate(true)
	record.recompute_grade()
	_pending_records.append(record)
