class_name WaveFieldVisual
extends Node2D

## 一般声波的表现视图，显示玩法逻辑层已经生成的确定性波场。
## 波半径由绝对视觉时间和发射时间重建；本节点不累计 delta、不做碰撞，也不决定命中。

@export_group("Canvas")
## 波纹绘制画布尺寸，单位为像素，左上角是 (0, 0)；应与 GameplayRuleSet.wave_canvas_size 一致。
@export var canvas_size: Vector2 = Vector2(1920.0, 1080.0)

@export_group("Wave Drawing")
## 每个完整圆环使用的线段数；数值越大越圆滑，也会增加 CPU 绘制开销。
@export_range(32, 384, 1) var arc_segments: int = 192
## 真实碰撞带宽环的不透明度，范围 0～1；数值越大，波的厚度越明显。
@export_range(0.05, 1.0, 0.01) var band_alpha: float = 0.26
## 波前细亮线的不透明度，范围 0～1；数值越大，敲击边缘越清楚。
@export_range(0.05, 1.0, 0.01) var front_alpha: float = 0.88
## 波接近画布边缘时保留的透明度比例，范围 0～1；越大则远处衰减越慢。
@export_range(0.01, 1.0, 0.01) var far_edge_alpha_scale: float = 0.34
## 有效生波颜色，对应手柄 R1、右键或 J。
@export var life_wave_color: Color = Color("b93a31")
## 有效死波颜色，对应手柄 L1、左键或 F。
@export var death_wave_color: Color = Color("292d38")
## 时机不正确或无目标输入产生的普通灰波颜色。
@export var invalid_wave_color: Color = Color("747780")

@export_group("Life / Death Overlap")
## 有效生波和死波几何相交时使用的骨白颜色。
@export var overlap_color: Color = Color("f2ead7")
## 画出交叠点所需的最低波强，范围 0～1；数值越大，弱波越难产生白色效果。
@export_range(0.0, 1.0, 0.01) var overlap_threshold: float = 0.15
## 每个交叠点周围的小颗粒数量；数值越大，白色相纹更繁密。
@export_range(1, 7, 1) var overlap_satellite_count: int = 3
## 交叠颗粒离核心的最大散布距离，单位为像素；数值越大，白点团更松散。
@export_range(0.0, 32.0, 0.5) var overlap_spread_px: float = 12.0

@export_group("Contact Feedback")
## 波前真正碰到音符后，接触圆环保留的秒数；数值越大，反馈消失越慢。
@export_range(0.05, 1.0, 0.01) var contact_lifetime_sec: float = 0.24

# 绑定的时钟提供绝对视觉时间，会话提供真实发波、接触和重置信号。
var _clock: SongClock
# 当前关卡会话；提供敲钟事件、统一视觉时间和波前接触结果。
var _session: StageSession
# 当前绝对视觉时间，单位为秒；半径始终由它减去每条波的发射时间计算。
var _visual_time_sec: float = 0.0
# 活动波按稳定 wave_id 保存；接触数组只保存短暂反馈，二者互不代替。
var _waves: Dictionary[String, Dictionary] = {}
# 仍在短暂显示期内的波前接触记录；只负责反馈，不替代玩法判定。
var _contacts: Array[Dictionary] = []


func _exit_tree() -> void:
	_disconnect_sources()


func bind(clock: SongClock, session: StageSession) -> void:
	_disconnect_sources()
	_clock = clock
	_session = session

	var clock_callback := Callable(self, "_on_clock_sample")
	if is_instance_valid(_clock) and _clock.has_signal(&"sample_published"):
		if not _clock.is_connected(&"sample_published", clock_callback):
			_clock.connect(&"sample_published", clock_callback)

	if not is_instance_valid(_session):
		return
	var launch_callback := Callable(self, "_on_wave_launched")
	var contact_callback := Callable(self, "_on_wave_contacted")
	var reset_callback := Callable(self, "_on_waves_reset")
	if _session.has_signal(&"wave_launched") and not _session.is_connected(&"wave_launched", launch_callback):
		_session.connect(&"wave_launched", launch_callback)
	if _session.has_signal(&"wave_contacted") and not _session.is_connected(&"wave_contacted", contact_callback):
		_session.connect(&"wave_contacted", contact_callback)
	if _session.has_signal(&"waves_reset") and not _session.is_connected(&"waves_reset", reset_callback):
		_session.connect(&"waves_reset", reset_callback)


func clear() -> void:
	_waves.clear()
	_contacts.clear()
	queue_redraw()


func set_visual_time(value: float) -> void:
	_visual_time_sec = value
	_prune_expired_waves()
	_prune_expired_contacts()
	queue_redraw()


func configure_palette(
	life_color: Color,
	death_color: Color,
	shared_color: Color,
	invalid_color: Color
) -> void:
	life_wave_color = life_color
	death_wave_color = death_color
	overlap_color = shared_color
	invalid_wave_color = invalid_color
	queue_redraw()


func active_wave_count() -> int:
	return _waves.size()


func debug_snapshot() -> Dictionary:
	var states: Array[Dictionary] = _wave_states()
	var rapid_shader_owned_ids: Dictionary[String, bool] = _rapid_shader_owned_ids(states)
	var cpu_states: Array[Dictionary] = states.filter(func(state: Dictionary) -> bool:
		return not rapid_shader_owned_ids.has(String(state["wave_id"]))
	)
	var overlaps: Array[Dictionary] = _overlap_points(cpu_states)
	var wave_debug: Array[Dictionary] = []
	for state: Dictionary in states:
		wave_debug.append({
			"wave_id": String(state["wave_id"]),
			"affinity": int(state["affinity"]),
			"valid": bool(state["valid"]),
			"owner": int(state.get("owner", GameplayTypes.InputOwner.NONE)),
			"strength": float(state["strength"]),
			"launch_us": int(state["launch_us"]),
			"launch_visual_sec": float(state["launch_visual_sec"]),
			"origin": state["origin"],
			"age_sec": float(state["age_sec"]),
			"radius_px": float(state["radius_px"]),
			"max_radius_px": float(state["max_radius_px"]),
			"half_width_px": float(state["half_width_px"]),
			"contact_count": int(state.get("contact_count", 0)),
		})
	return {
		"visual_time_sec": _visual_time_sec,
		"active_wave_count": _waves.size(),
		"visible_wave_count": states.size(),
		"overlap_point_count": overlaps.size(),
		"rapid_shader_owned_count": rapid_shader_owned_ids.size(),
		"rapid_cpu_fallback_count": _rapid_shader_candidate_count(states) - rapid_shader_owned_ids.size(),
		"contact_feedback_count": _contacts.size(),
		"waves": wave_debug,
	}


func _draw() -> void:
	var states: Array[Dictionary] = _wave_states()
	var rapid_shader_owned_ids: Dictionary[String, bool] = _rapid_shader_owned_ids(states)
	var cpu_states: Array[Dictionary] = []
	for state: Dictionary in states:
		# 有效疾振波交给专用 Shader 画成波包，这里跳过以免同一条波重复显示。
		if rapid_shader_owned_ids.has(String(state["wave_id"])):
			continue
		cpu_states.append(state)
		_draw_wave(state)
	for overlap: Dictionary in _overlap_points(cpu_states):
		_draw_overlap(overlap)
	_draw_contacts()


func _on_clock_sample(sample: ClockSample) -> void:
	set_visual_time(sample.visual_time_sec)


func _on_wave_launched(wave: Dictionary) -> void:
	var wave_id: String = str(wave.get("wave_id", ""))
	if wave_id.is_empty():
		push_warning("WaveFieldVisual ignored a wave without wave_id.")
		return
	var origin_value: Variant = wave.get("origin", Vector2.ZERO)
	if not origin_value is Vector2:
		push_warning("WaveFieldVisual ignored wave '%s' with a non-Vector2 origin." % wave_id)
		return
	var origin: Vector2 = origin_value
	var half_width: float = maxf(float(wave.get("half_width_px", 1.0)), 0.5)
	var speed: float = maxf(float(wave.get("speed_px_sec", 0.0)), 0.0)
	var launch_us: int = int(wave.get("launch_us", 0))
	_waves[wave_id] = {
		"wave_id": wave_id,
		"affinity": int(wave.get("affinity", GameplayTypes.Affinity.SU)),
		"valid": bool(wave.get("valid", false)),
		"owner": int(wave.get("owner", GameplayTypes.InputOwner.NONE)),
		"strength": clampf(float(wave.get("strength", 1.0)), 0.0, 1.0),
		"launch_us": launch_us,
		"launch_visual_sec": _timeline_us_to_visual_sec(launch_us),
		"origin": origin,
		"speed_px_sec": speed,
		"half_width_px": half_width,
		"max_radius_px": _max_visible_radius(origin, half_width),
		"contact_count": 0,
	}
	queue_redraw()


func _on_wave_contacted(contact: Dictionary) -> void:
	var wave_id: String = str(contact.get("wave_id", ""))
	if _waves.has(wave_id):
		var wave: Dictionary = _waves[wave_id]
		wave["contact_count"] = int(wave.get("contact_count", 0)) + 1
		wave["last_contact_us"] = int(contact.get(
			"contact_us",
			roundi((_visual_time_sec - _visual_timeline_offset_sec()) * 1_000_000.0)
		))

	var position_value: Variant = contact.get("position", contact.get("contact_position", null))
	if position_value is Vector2:
		var contact_us: int = int(contact.get(
			"contact_us",
			roundi((_visual_time_sec - _visual_timeline_offset_sec()) * 1_000_000.0)
		))
		_contacts.append({
			"wave_id": wave_id,
			"position": position_value,
			"start_sec": _timeline_us_to_visual_sec(contact_us),
		})
	queue_redraw()


func _on_waves_reset() -> void:
	clear()


func _disconnect_sources() -> void:
	var clock_callback := Callable(self, "_on_clock_sample")
	if is_instance_valid(_clock) and _clock.has_signal(&"sample_published"):
		if _clock.is_connected(&"sample_published", clock_callback):
			_clock.disconnect(&"sample_published", clock_callback)
	var launch_callback := Callable(self, "_on_wave_launched")
	var contact_callback := Callable(self, "_on_wave_contacted")
	var reset_callback := Callable(self, "_on_waves_reset")
	if is_instance_valid(_session):
		if _session.has_signal(&"wave_launched") and _session.is_connected(&"wave_launched", launch_callback):
			_session.disconnect(&"wave_launched", launch_callback)
		if _session.has_signal(&"wave_contacted") and _session.is_connected(&"wave_contacted", contact_callback):
			_session.disconnect(&"wave_contacted", contact_callback)
		if _session.has_signal(&"waves_reset") and _session.is_connected(&"waves_reset", reset_callback):
			_session.disconnect(&"waves_reset", reset_callback)
	_clock = null
	_session = null


func _prune_expired_waves() -> void:
	var expired_ids: Array[String] = []
	for wave_id: String in _waves.keys():
		var wave: Dictionary = _waves[wave_id]
		var age_sec: float = _visual_time_sec - float(wave["launch_visual_sec"])
		if age_sec < 0.0:
			continue
		var radius: float = age_sec * float(wave["speed_px_sec"])
		if radius > float(wave["max_radius_px"]):
			expired_ids.append(wave_id)
	for wave_id: String in expired_ids:
		_waves.erase(wave_id)


func _prune_expired_contacts() -> void:
	for index: int in range(_contacts.size() - 1, -1, -1):
		var age_sec: float = _visual_time_sec - float(_contacts[index]["start_sec"])
		if age_sec > contact_lifetime_sec:
			_contacts.remove_at(index)


func _wave_states() -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	for wave_id: String in _waves.keys():
		var wave: Dictionary = _waves[wave_id]
		var age_sec: float = _visual_time_sec - float(wave["launch_visual_sec"])
		if age_sec < 0.0:
			continue
		var state: Dictionary = wave.duplicate(true)
		state["age_sec"] = age_sec
		state["radius_px"] = age_sec * float(wave["speed_px_sec"])
		state["alpha"] = _wave_alpha(state)
		states.append(state)
	states.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["launch_us"]) != int(b["launch_us"]):
			return int(a["launch_us"]) < int(b["launch_us"])
		return String(a["wave_id"]) < String(b["wave_id"])
	)
	return states


func _wave_alpha(state: Dictionary) -> float:
	var max_radius: float = maxf(float(state["max_radius_px"]), 0.001)
	var edge_ratio: float = clampf(float(state["radius_px"]) / max_radius, 0.0, 1.0)
	return lerpf(1.0, far_edge_alpha_scale, smoothstep(0.0, 1.0, edge_ratio)) * float(state.get("strength", 1.0))


func _draw_wave(state: Dictionary) -> void:
	var radius: float = float(state["radius_px"])
	if radius <= 0.5:
		return
	var half_width: float = float(state["half_width_px"])
	var color: Color = _wave_color(state)
	var alpha: float = float(state["alpha"])
	var segments: int = maxi(arc_segments, 32)
	# 半透明宽环对应真实碰撞带，窄亮前沿则在波扩散到全屏时仍保留清脆的敲击感。
	draw_arc(
		state["origin"], radius, 0.0, TAU, segments,
		Color(color, band_alpha * alpha), maxf(half_width * 2.0, 1.0), true
	)
	draw_arc(
		state["origin"], radius, 0.0, TAU, segments,
		Color(color.lightened(0.10), front_alpha * alpha), maxf(half_width * 0.16, 1.5), true
	)


func _wave_color(state: Dictionary) -> Color:
	if not bool(state["valid"]):
		return invalid_wave_color
	return death_wave_color if int(state["affinity"]) == GameplayTypes.Affinity.XUAN else life_wave_color


func _is_rapid_shader_candidate(state: Dictionary) -> bool:
	return (
		bool(state.get("valid", false))
		and int(state.get("owner", GameplayTypes.InputOwner.NONE)) == GameplayTypes.InputOwner.RAPID
	)


func _rapid_shader_candidate_count(states: Array[Dictionary]) -> int:
	var count: int = 0
	for state: Dictionary in states:
		if _is_rapid_shader_candidate(state):
			count += 1
	return count


func _rapid_shader_owned_ids(states: Array[Dictionary]) -> Dictionary[String, bool]:
	var life: Array[Dictionary] = []
	var death: Array[Dictionary] = []
	for state: Dictionary in states:
		if not _is_rapid_shader_candidate(state):
			continue
		if int(state["affinity"]) == GameplayTypes.Affinity.XUAN:
			death.append(state)
		else:
			life.append(state)
	var sorter := func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["launch_us"]) != int(b["launch_us"]):
			return int(a["launch_us"]) < int(b["launch_us"])
		return String(a["wave_id"]) < String(b["wave_id"])
	life.sort_custom(sorter)
	death.sort_custom(sorter)
	var capacity: int = RapidInterferenceVisual.MAX_SHADER_WAVEFRONTS
	var result: Dictionary[String, bool] = {}
	for source: Array[Dictionary] in [life, death]:
		var first_owned_index: int = maxi(0, source.size() - capacity)
		for index: int in range(first_owned_index, source.size()):
			result[String(source[index]["wave_id"])] = true
	return result


func _overlap_points(states: Array[Dictionary]) -> Array[Dictionary]:
	var life_waves: Array[Dictionary] = []
	var death_waves: Array[Dictionary] = []
	for state: Dictionary in states:
		if not bool(state["valid"]):
			continue
		match int(state["affinity"]):
			GameplayTypes.Affinity.ZHU:
				life_waves.append(state)
			GameplayTypes.Affinity.XUAN:
				death_waves.append(state)

	var result: Array[Dictionary] = []
	var visible_bounds := Rect2(Vector2.ZERO, canvas_size).grow(overlap_spread_px * 2.0)
	for life: Dictionary in life_waves:
		for death: Dictionary in death_waves:
			var intensity: float = float(life["alpha"]) * float(death["alpha"])
			if intensity <= overlap_threshold:
				continue
			var points: PackedVector2Array = _circle_intersections(
				life["origin"], float(life["radius_px"]),
				death["origin"], float(death["radius_px"])
			)
			var spread: float = clampf(
				sqrt(float(life["half_width_px"]) * float(death["half_width_px"])) * 0.48,
				4.0,
				20.0
			)
			var pair_seed: int = ("%s|%s" % [life["wave_id"], death["wave_id"]]).hash()
			for point: Vector2 in points:
				if visible_bounds.has_point(point):
					result.append({
						"position": point,
						"intensity": intensity,
						"spread": spread,
						"seed": pair_seed,
						"life_wave_id": life["wave_id"],
						"death_wave_id": death["wave_id"],
					})
	return result


func _circle_intersections(
	center_a: Vector2,
	radius_a: float,
	center_b: Vector2,
	radius_b: float
) -> PackedVector2Array:
	var result := PackedVector2Array()
	var center_delta: Vector2 = center_b - center_a
	var center_distance: float = center_delta.length()
	if center_distance <= 0.0001:
		return result
	if center_distance > radius_a + radius_b:
		return result
	if center_distance < absf(radius_a - radius_b):
		return result

	var along: float = (
		radius_a * radius_a - radius_b * radius_b + center_distance * center_distance
	) / (2.0 * center_distance)
	var height_squared: float = radius_a * radius_a - along * along
	if height_squared < -0.01:
		return result
	var unit: Vector2 = center_delta / center_distance
	var base: Vector2 = center_a + unit * along
	var height: float = sqrt(maxf(height_squared, 0.0))
	if height <= 0.01:
		result.append(base)
		return result
	var perpendicular := Vector2(-unit.y, unit.x) * height
	result.append(base + perpendicular)
	result.append(base - perpendicular)
	return result


func _draw_overlap(overlap: Dictionary) -> void:
	var position_value: Vector2 = overlap["position"]
	var intensity: float = clampf(float(overlap["intensity"]), 0.0, 1.0)
	var spread: float = float(overlap["spread"])
	var core_radius: float = lerpf(3.5, 8.5, intensity)
	# 先画柔和光晕，再画较实的骨白核心；即使下面是红黑两色，叠加点仍明确读成白色。
	draw_circle(position_value, core_radius * 2.4, Color(overlap_color, intensity * 0.12))
	draw_circle(position_value, core_radius, Color(overlap_color, 0.62 + intensity * 0.34))

	var seed: int = absi(int(overlap["seed"]))
	for index: int in range(overlap_satellite_count):
		var phase_seed: int = posmod(seed + index * 7919, 10007)
		var angle: float = TAU * float(phase_seed) / 10007.0
		var distance: float = spread * (0.42 + 0.58 * float(index + 1) / float(overlap_satellite_count + 1))
		var dot_position: Vector2 = position_value + Vector2.from_angle(angle) * distance
		var dot_radius: float = lerpf(1.3, 2.7, intensity) * (1.0 - float(index) * 0.09)
		draw_circle(dot_position, dot_radius, Color(overlap_color, intensity * 0.58))


func _draw_contacts() -> void:
	var duration: float = maxf(contact_lifetime_sec, 0.001)
	for contact: Dictionary in _contacts:
		var age_sec: float = _visual_time_sec - float(contact["start_sec"])
		if age_sec < 0.0 or age_sec > duration:
			continue
		var progress: float = clampf(age_sec / duration, 0.0, 1.0)
		var eased: float = 1.0 - pow(1.0 - progress, 3.0)
		var radius: float = lerpf(8.0, 46.0, eased)
		var alpha: float = pow(1.0 - progress, 1.6)
		draw_arc(contact["position"], radius, 0.0, TAU, 48, Color(overlap_color, alpha), 4.0, true)


func _max_visible_radius(origin: Vector2, half_width: float) -> float:
	var corners := PackedVector2Array([
		Vector2.ZERO,
		Vector2(canvas_size.x, 0.0),
		canvas_size,
		Vector2(0.0, canvas_size.y),
	])
	var farthest: float = 0.0
	for corner: Vector2 in corners:
		farthest = maxf(farthest, origin.distance_to(corner))
	# 必须等波带内缘越过最远角落，整条声波才算完全离开画布。
	return farthest + half_width


func _timeline_us_to_visual_sec(timestamp_us: int) -> float:
	return float(timestamp_us) / 1_000_000.0 + _visual_timeline_offset_sec()


func _visual_timeline_offset_sec() -> float:
	if not is_instance_valid(_clock):
		return 0.0
	# 输入和玩法接触使用校准后的判定时间轴。这里统一换到视觉时间原点，
	# 即使输入补偿或画面提前量不为零，波半径与接触特效仍能对齐。
	return _clock.input_compensation_sec + _clock.visual_lead_sec
