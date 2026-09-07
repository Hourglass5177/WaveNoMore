class_name CarrierWaveEngine
extends RefCounted

## 双钟持续载波的确定性领域模型。
##
## Strike Wave 仍由 WaveInteractionEngine 负责命中普通音符；这里的波只服务于
## 调频相纹和素音凝现。每个波前都保存自己的发射时刻与固定传播速度，后续改频
## 只会改变下一批波的间距，不会拉伸或加速已经发出的波。

const NEVER_TIME_US: int = -9_000_000_000_000_000
const USEC_PER_SEC: float = 1_000_000.0
const DEFAULT_BASE_FREQUENCY_HZ: float = 3.0
const DEFAULT_WAVE_SPEED_PX_SEC: float = 2400.0
const DEFAULT_CANVAS_SIZE: Vector2 = Vector2(1920.0, 1080.0)
const DEFAULT_LIFE_ORIGIN: Vector2 = Vector2(350.0, 280.0)
const DEFAULT_DEATH_ORIGIN: Vector2 = Vector2(1570.0, 800.0)

var _rules: GameplayRuleSet
var _current_time_us: int = NEVER_TIME_US
var _wave_speed_px_sec: float = DEFAULT_WAVE_SPEED_PX_SEC
var _canvas_size: Vector2 = DEFAULT_CANVAS_SIZE
var _history: Array[Dictionary] = []
var _pending_emissions: Array[Dictionary] = []
var _serial: int = 0

## 两个波源按固定顺序保存，避免 Dictionary 的遍历顺序影响 Replay。
var _sources: Dictionary[int, Dictionary] = {}


func configure(rules: GameplayRuleSet) -> void:
	_rules = rules
	reset()


func reset() -> void:
	_current_time_us = NEVER_TIME_US
	_wave_speed_px_sec = maxf(_rule_float(&"wave_speed_px_sec", DEFAULT_WAVE_SPEED_PX_SEC), 0.001)
	_canvas_size = _rule_vector(&"wave_canvas_size", DEFAULT_CANVAS_SIZE)
	_history.clear()
	_pending_emissions.clear()
	_serial = 0
	_sources = {
		GameplayTypes.Affinity.ZHU: _new_source(
			GameplayTypes.Affinity.ZHU,
			_rule_vector(&"life_wave_origin", DEFAULT_LIFE_ORIGIN)
		),
		GameplayTypes.Affinity.XUAN: _new_source(
			GameplayTypes.Affinity.XUAN,
			_rule_vector(&"death_wave_origin", DEFAULT_DEATH_ORIGIN)
		),
	}


func advance_to(time_us: int, inclusive: bool = true) -> void:
	if time_us < _current_time_us:
		return
	# 不能先把某一口钟的所有波补完、再补另一口钟：这种写法会让波 ID 顺序
	# 随一次 advance 跨过了多少帧而变化。这里始终选择全局最早的下一次发射，
	# 同时刻固定“生后死”，保证一次推进和分帧推进得到完全相同的历史。
	while true:
		var next_affinity: int = -1
		var next_time_us: int = NEVER_TIME_US
		for affinity: int in [GameplayTypes.Affinity.ZHU, GameplayTypes.Affinity.XUAN]:
			var source: Dictionary = _sources[affinity]
			if not bool(source["held"]):
				continue
			var candidate_us: int = int(source["next_emit_us"])
			if (
				candidate_us == NEVER_TIME_US
				or candidate_us > time_us
				or (candidate_us == time_us and not inclusive)
			):
				continue
			if next_affinity < 0 or candidate_us < next_time_us:
				next_affinity = affinity
				next_time_us = candidate_us
		if next_affinity < 0:
			break
		var selected: Dictionary = _sources[next_affinity]
		_emit(selected, next_time_us)
		selected["last_emit_us"] = next_time_us
		selected["next_emit_us"] = next_time_us + _period_us(float(selected["frequency_hz"]))
	for affinity: int in [GameplayTypes.Affinity.ZHU, GameplayTypes.Affinity.XUAN]:
		_sources[affinity]["last_update_us"] = time_us
	_current_time_us = time_us


func set_held(affinity: int, held: bool, time_us: int) -> void:
	if not _sources.has(affinity):
		return
	# 输入发生在时间戳 T 时，先只补到 T 之前；T 时刻是否发波，要等新的
	# 按住状态生效后再由外层做一次包含端点的推进。
	advance_to(time_us, false)
	var source: Dictionary = _sources[affinity]
	if not held:
		source["input_channel"] = GameplayTypes.BellInputChannel.NONE
	if bool(source["held"]) == held:
		return
	source["held"] = held
	source["last_update_us"] = time_us
	if held:
		# 按下瞬间先产生一个载波波前；之后按当前周期稳定续发。
		_emit(source, time_us)
		source["last_emit_us"] = time_us
		source["next_emit_us"] = time_us + _period_us(float(source["frequency_hz"]))
		source["paused_remaining_us"] = -1
	else:
		source["last_emit_us"] = NEVER_TIME_US
		source["next_emit_us"] = NEVER_TIME_US
		source["paused_remaining_us"] = -1


func begin_pause(time_us: int) -> void:
	## 暂停会冻结歌曲时间，因此这里只保存每口钟距离下一圈还剩多久，不能补发新圈。
	advance_to(time_us, false)
	for affinity: int in [GameplayTypes.Affinity.ZHU, GameplayTypes.Affinity.XUAN]:
		var source: Dictionary = _sources[affinity]
		if bool(source["held"]) and int(source["next_emit_us"]) != NEVER_TIME_US:
			source["paused_remaining_us"] = maxi(1, int(source["next_emit_us"]) - time_us)
		else:
			source["paused_remaining_us"] = -1
		source["held"] = false
		source["next_emit_us"] = NEVER_TIME_US


## 处理一次 A/B 敲钟操作。首次按下记录持续来源，非匹配释放不会停止载波。
func handle_bell_input(sample: SemanticInputSample) -> void:
	if sample == null or (not sample.is_press() and not sample.is_release()):
		return
	var affinity: int = sample.affinity()
	if not _sources.has(affinity):
		return
	var source: Dictionary = _sources[affinity]
	var channel: int = sample.input_channel()
	if sample.is_press() and int(source["input_channel"]) == GameplayTypes.BellInputChannel.NONE:
		source["input_channel"] = channel
		set_held(affinity, true, sample.timestamp_us)
	elif sample.is_release() and int(source["input_channel"]) == channel:
		set_held(affinity, false, sample.timestamp_us)


func resume_after_pause(life_channel: int, death_channel: int, time_us: int) -> void:
	## 恢复只重启原本仍被玩家按住的波源，并延续暂停前的剩余周期；不会在恢复点凭空发波。
	advance_to(time_us)
	_resume_source_after_pause(GameplayTypes.Affinity.ZHU, life_channel, time_us)
	_resume_source_after_pause(GameplayTypes.Affinity.XUAN, death_channel, time_us)


func set_frequency(affinity: int, frequency_hz: float, time_us: int) -> void:
	if not _sources.has(affinity):
		return
	# 与按键输入相同，改频先于同时间戳的发射生效。
	advance_to(time_us, false)
	var source: Dictionary = _sources[affinity]
	var old_frequency: float = maxf(float(source["frequency_hz"]), 0.001)
	var next_frequency: float = maxf(frequency_hz, 0.001)
	if is_equal_approx(old_frequency, next_frequency):
		return

	# next_emit_us 已经包含此前每次改频后的相位。用“旧周期还剩多少”换算成
	# 新周期的剩余比例，连续多次改频也不会退回 last_emit_us 重新估算而漂移。
	if bool(source["held"]) and int(source["next_emit_us"]) != NEVER_TIME_US:
		var old_period: int = _period_us(old_frequency)
		var remaining_old_us: int = maxi(0, int(source["next_emit_us"]) - time_us)
		var remaining_cycle: float = clampf(
			float(remaining_old_us) / float(maxi(1, old_period)),
			0.0,
			1.0
		)
		source["next_emit_us"] = time_us + maxi(
			0,
			roundi(remaining_cycle * float(_period_us(next_frequency)))
		)
	source["frequency_hz"] = next_frequency
	source["last_update_us"] = time_us


func set_all_frequencies(life_hz: float, death_hz: float, time_us: int) -> void:
	# 固定按生、死顺序更新，确保同一时间戳下生成相同的稳定 ID 顺序。
	set_frequency(GameplayTypes.Affinity.ZHU, life_hz, time_us)
	set_frequency(GameplayTypes.Affinity.XUAN, death_hz, time_us)


func reset_frequencies_to_base(time_us: int) -> void:
	var base_hz: float = _rule_float(&"tuning_base_frequency_hz", DEFAULT_BASE_FREQUENCY_HZ)
	set_all_frequencies(base_hz, base_hz, time_us)


func frequency_hz(affinity: int) -> float:
	if not _sources.has(affinity):
		return DEFAULT_BASE_FREQUENCY_HZ
	return float(_sources[affinity]["frequency_hz"])


func is_held(affinity: int) -> bool:
	return _sources.has(affinity) and bool(_sources[affinity]["held"])


func drain_emissions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for emission: Dictionary in _pending_emissions:
		result.append(emission.duplicate(true))
	_pending_emissions.clear()
	return result


func visible_wavefronts(time_us: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var max_radius: float = _canvas_size.length() * 1.15
	for emission: Dictionary in _history:
		var age_us: int = time_us - int(emission["launch_us"])
		if age_us < 0:
			continue
		var radius: float = float(age_us) / USEC_PER_SEC * float(emission["speed_px_sec"])
		if radius > max_radius:
			continue
		var front: Dictionary = emission.duplicate(true)
		front["radius_px"] = radius
		result.append(front)
	return result


func history_copy() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for emission: Dictionary in _history:
		result.append(emission.duplicate(true))
	return result


func emission_count() -> int:
	return _history.size()


func snapshot(time_us: int = NEVER_TIME_US) -> Dictionary:
	var target_us: int = _current_time_us if time_us == NEVER_TIME_US else time_us
	return {
		"time_us": target_us,
		"life_held": is_held(GameplayTypes.Affinity.ZHU),
		"death_held": is_held(GameplayTypes.Affinity.XUAN),
		"life_frequency_hz": frequency_hz(GameplayTypes.Affinity.ZHU),
		"death_frequency_hz": frequency_hz(GameplayTypes.Affinity.XUAN),
		"visible_wavefronts": visible_wavefronts(target_us),
		"emission_count": _history.size(),
	}


func find_constructive_intersections(
		time_us: int,
		normalized_region: Rect2,
		count: int,
		minimum_spacing_px: float = 120.0
) -> Array[Vector2]:
	## 素音只受谱面显式区域约束，包含四条边界；HUD 和波源不构成隐藏禁区。
	var life_fronts: Array[Dictionary] = []
	var death_fronts: Array[Dictionary] = []
	for front: Dictionary in visible_wavefronts(time_us):
		if int(front["affinity"]) == GameplayTypes.Affinity.ZHU:
			life_fronts.append(front)
		elif int(front["affinity"]) == GameplayTypes.Affinity.XUAN:
			death_fronts.append(front)

	var allowed := Rect2(
		Vector2(normalized_region.position.x * _canvas_size.x, normalized_region.position.y * _canvas_size.y),
		Vector2(normalized_region.size.x * _canvas_size.x, normalized_region.size.y * _canvas_size.y)
	)
	var center: Vector2 = allowed.get_center()
	var candidates: Array[Dictionary] = []
	for life: Dictionary in life_fronts:
		for death: Dictionary in death_fronts:
			for point: Vector2 in _circle_intersections(
				life["origin"], float(life["radius_px"]),
				death["origin"], float(death["radius_px"])
			):
				# Rect2.has_point 不包含右边和下边，因此显式比较闭区间。
				# 不钳制坐标：屏幕外或谱面区域外的真实交点仍然拒绝。
				if (
					point.x < allowed.position.x or point.x > allowed.end.x
					or point.y < allowed.position.y or point.y > allowed.end.y
				):
					continue
				candidates.append({
					"point": point,
					"distance_to_center": point.distance_squared_to(center),
					"life_id": str(life["wave_id"]),
					"death_id": str(death["wave_id"]),
				})
	candidates.sort_custom(_sort_intersection_candidates)

	var selected: Array[Vector2] = []
	for candidate: Dictionary in candidates:
		var point: Vector2 = candidate["point"]
		var spaced: bool = true
		for existing: Vector2 in selected:
			if point.distance_squared_to(existing) < minimum_spacing_px * minimum_spacing_px:
				spaced = false
				break
		if not spaced:
			continue
		selected.append(point)
		if selected.size() >= maxi(0, count):
			break
	return selected


func canvas_position_to_uv(position_px: Vector2) -> Vector2:
	## 使用本局实际画布归一化交点；不裁剪坐标掩盖越界。
	return position_px / _canvas_size


func _new_source(affinity: int, origin: Vector2) -> Dictionary:
	return {
		"affinity": affinity,
		"origin": origin,
		"held": false,
		"input_channel": GameplayTypes.BellInputChannel.NONE,
		"frequency_hz": _rule_float(&"tuning_base_frequency_hz", DEFAULT_BASE_FREQUENCY_HZ),
		"last_update_us": NEVER_TIME_US,
		"last_emit_us": NEVER_TIME_US,
		"next_emit_us": NEVER_TIME_US,
		"paused_remaining_us": -1,
	}


func _resume_source_after_pause(affinity: int, channel: int, time_us: int) -> void:
	var source: Dictionary = _sources[affinity]
	var remaining_us: int = int(source.get("paused_remaining_us", -1))
	source["paused_remaining_us"] = -1
	var should_hold: bool = channel != GameplayTypes.BellInputChannel.NONE
	source["input_channel"] = channel
	source["held"] = should_hold
	source["last_update_us"] = time_us
	if not should_hold:
		source["last_emit_us"] = NEVER_TIME_US
		source["next_emit_us"] = NEVER_TIME_US
		return
	if remaining_us <= 0:
		remaining_us = _period_us(float(source["frequency_hz"]))
	source["next_emit_us"] = time_us + remaining_us


func _emit(source: Dictionary, launch_us: int) -> void:
	var affinity: int = int(source["affinity"])
	var emission: Dictionary = {
		"id": "carrier:%010d:%d" % [_serial, affinity],
		"wave_id": "carrier:%010d:%d" % [_serial, affinity],
		"affinity": affinity,
		"origin": source["origin"],
		"launch_us": launch_us,
		"frequency_hz": float(source["frequency_hz"]),
		"speed_px_sec": _wave_speed_px_sec,
		"carrier": true,
	}
	_serial += 1
	_history.append(emission)
	_pending_emissions.append(emission.duplicate(true))


func _period_us(frequency_hz: float) -> int:
	return maxi(1, roundi(USEC_PER_SEC / maxf(frequency_hz, 0.001)))


func _circle_intersections(c0: Vector2, r0: float, c1: Vector2, r1: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var delta: Vector2 = c1 - c0
	var distance: float = delta.length()
	if distance <= 0.000001 or distance > r0 + r1 or distance < absf(r0 - r1):
		return result
	var along: float = (r0 * r0 - r1 * r1 + distance * distance) / (2.0 * distance)
	var height_squared: float = r0 * r0 - along * along
	if height_squared < -0.001:
		return result
	var midpoint: Vector2 = c0 + delta / distance * along
	var perpendicular := Vector2(-delta.y, delta.x) / distance
	var height: float = sqrt(maxf(height_squared, 0.0))
	result.append(midpoint + perpendicular * height)
	if height > 0.001:
		result.append(midpoint - perpendicular * height)
	return result


func _sort_intersection_candidates(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(float(a["distance_to_center"]), float(b["distance_to_center"])):
		return float(a["distance_to_center"]) < float(b["distance_to_center"])
	if str(a["life_id"]) != str(b["life_id"]):
		return str(a["life_id"]) < str(b["life_id"])
	if str(a["death_id"]) != str(b["death_id"]):
		return str(a["death_id"]) < str(b["death_id"])
	var point_a: Vector2 = a["point"]
	var point_b: Vector2 = b["point"]
	if not is_equal_approx(point_a.y, point_b.y):
		return point_a.y < point_b.y
	return point_a.x < point_b.x


func _rule_float(property_name: StringName, fallback: float) -> float:
	var value: Variant = _rule_property(property_name, fallback)
	return float(value) if value is float or value is int else fallback


func _rule_vector(property_name: StringName, fallback: Vector2) -> Vector2:
	var value: Variant = _rule_property(property_name, fallback)
	return value if value is Vector2 else fallback


func _rule_property(property_name: StringName, fallback: Variant) -> Variant:
	if _rules == null:
		return fallback
	for property_data: Dictionary in _rules.get_property_list():
		if StringName(property_data.get("name", &"")) == property_name:
			return _rules.get(property_name)
	return fallback
