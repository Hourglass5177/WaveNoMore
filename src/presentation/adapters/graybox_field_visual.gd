class_name GrayboxFieldVisual
extends Node2D

## 调频滑条或疾振计数器的灰盒表现。
## 调频滑条只显示玩家真正需要看的信息；判定仍由领域层负责。

## 0 为调频滑条，1 为疾振计数器。
@export_enum("Tuning", "Rapid") var field_kind: int = 0
## 正式素材可参考的占位尺寸；程序绘制不会强行裁切到这个范围。
@export var extent: Vector2 = Vector2(720.0, 300.0)

@export_group("Tuning Slider")
## 滑条主体的默认宽度。72 px 足够让引导带和玩家游标同时保持清楚。
@export_range(48.0, 112.0, 1.0) var tuning_rail_width: float = 72.0
## 生滑条相对画面中心的插槽；死滑条自动取相反数，始终保持中心对称。
@export var life_slot_offset: Vector2 = Vector2(-205.0, -188.0)
## 用于安全摆放滑条的设计画布尺寸；只平移插槽，绝不缩短轨道。
@export var canvas_size: Vector2 = Vector2(1920.0, 1080.0)
## 滑条端点尽量与画布边缘保留的距离；轨道长于画布时会居中溢出而不会缩放。
@export_range(0.0, 180.0, 1.0) var slider_edge_margin_px: float = 72.0
## 每 1 Hz 对应的轨道长度，保证相同位移始终代表相同调频量。
@export_range(40.0, 260.0, 1.0) var pixels_per_hz: float = 160.0
## 归一化频率轴两端对应的物理频率，仅用于把频率跨度换算成画面长度。
@export_range(0.1, 20.0, 0.1) var min_frequency_hz: float = 1.8
@export_range(0.1, 20.0, 0.1) var max_frequency_hz: float = 6.9
## 连续跟随判定的额外空间余量。视觉引导带与领域判定使用同一默认值。
@export_range(0.0, 0.25, 0.005) var guide_space_margin: float = 0.08
## 时间宽容度，单位秒；会换算成当前滑条上的可见引导范围。
@export_range(0.0, 0.5, 0.005) var guide_time_margin_sec: float = 0.18

@export_group("Tuning Palette")
## 生钟滑条主色。
@export var life_color: Color = Color("c23b31")
## 死钟滑条主色。刻意比死界背景更亮，避免玄色信息消失。
@export var death_color: Color = Color("414a60")
## 滑条描边、引导带和贴合反馈使用的骨白色。
@export var bone_color: Color = Color("f2e6c9")
## 滑条最底层颜色，用于从复杂场景中托出交互区域。
@export var backing_color: Color = Color("080a10", 0.94)

@export_group("Rapid HUD")
## 疾振中心按键印记的半径。
@export_range(48.0, 140.0, 1.0) var rapid_core_radius: float = 70.0
## 疾振外侧倒计时环的半径。
@export_range(56.0, 170.0, 1.0) var rapid_time_radius: float = 88.0

# 当前谱面对象的稳定 ID；用于从 active_tuning_sliders 中找到本条滑条。
var event_id: String = ""
# 当前滑条所属调频场 ID；用来确认全局活动场确实包含本滑条。
var field_id: String = ""
# 调频滑条所属分组；同组的生、死滑条由领域层合并结算。
var group_id: String = ""
# 当前滑条阵营：朱为生、玄为死。
var affinity: int = GameplayTypes.Affinity.ZHU
# 当前事件已经进行的比例，0 是开头，1 是结尾。
var region_progress: float = 0.0
# 疾振完成比例，允许略高于 1 以保留超额敲击信息。
var rapid_ratio: float = 0.0
# -1 表示尚未结算；其余值使用 GameplayTypes.JudgmentGrade。
var judgment_grade: int = -1
# 是否已经判为 Miss；失败后滑条整体会转为低饱和灰色。
var missed: bool = false
# 当前这口钟是否在调频段内被按住。
var tuning_active: bool = false

# 谱面定义的频率起点与终点，都是 0～1 的统一频率轴值。
var _start_value: float = 0.0
var _end_value: float = 1.0
# 一次单程所需 tick 与总折返次数；总时长等于两者相乘。
var _traversal_ticks: int = 1
var _traversal_count: int = 1
# 整条事件的总时长和单程时长，供时间宽容度换算成空间带宽。
var _duration_sec: float = 1.0
var _traversal_duration_sec: float = 1.0
# 由频率跨度换算出的真实轨道长度。
var _slider_length_px: float = 384.0
# 玩家游标与时间引导在轨道上的空间位置，均为 0～1。
var _player_progress: float = 0.0
var _guide_progress: float = 0.0
# 当前可接受的内嵌引导带边界。若领域快照提供权威值，会覆盖本地预览计算。
var _guide_min_progress: float = 0.0
var _guide_max_progress: float = 0.0
var _has_authoritative_guide_range: bool = false
# 当前滑条有效采样覆盖率，用于轻量反馈和调试快照。
var _coverage: float = 0.0
# 调频时间场是否已开启；普通段即使按住钟也不显示可操作态。
var _field_active: bool = false
# 调频区域接近事件起点的收束进度。
var _approach_progress: float = 0.0
# 疾振要求次数和交替规则只参与疾振 HUD。
var _required_strikes: int = 1
var _must_alternate: bool = true


func configure_from_rules(rules: GameplayRuleSet) -> void:
	## 滑条的空间尺度与判定宽容必须直接读取关卡规则，避免画面提示和领域判定不一致。
	if rules == null:
		return
	canvas_size = rules.wave_canvas_size
	pixels_per_hz = rules.tuning_pixels_per_hz
	min_frequency_hz = rules.tuning_min_frequency_hz
	max_frequency_hz = rules.tuning_max_frequency_hz
	guide_space_margin = rules.tuning_spatial_margin
	guide_time_margin_sec = float(rules.tuning_guide_time_window_ms) / 1000.0
	_recalculate_slider_length()
	if not _has_authoritative_guide_range:
		_update_local_guide_range()
	queue_redraw()


func prepare(view_model: Dictionary) -> void:
	event_id = str(view_model.get("event_id", view_model.get("id", view_model.get("unit_id", ""))))
	field_id = str(view_model.get("field_id", ""))
	group_id = str(view_model.get("group_id", view_model.get("unit_id", event_id)))
	affinity = int(view_model.get("affinity", GameplayTypes.Affinity.ZHU))
	region_progress = 0.0
	rapid_ratio = 0.0
	judgment_grade = -1
	missed = false
	tuning_active = false
	_field_active = false
	_coverage = 0.0
	_approach_progress = 0.0

	_start_value = clampf(float(view_model.get("start_value", 0.0)), 0.0, 1.0)
	_end_value = clampf(float(view_model.get("end_value", 1.0)), 0.0, 1.0)
	_traversal_count = maxi(1, int(view_model.get("traversal_count", 1)))
	_traversal_ticks = maxi(1, int(view_model.get(
		"traversal_ticks",
		maxi(1, int(view_model.get("duration_ticks", 1)) / _traversal_count)
	)))
	var total_ticks: int = maxi(1, int(view_model.get(
		"duration_ticks",
		_traversal_ticks * _traversal_count
	)))
	var duration_us: int = int(view_model.get("duration_us", 0))
	if duration_us <= 0:
		duration_us = int(view_model.get("end_us", 0)) - int(view_model.get("start_us", 0))
	_duration_sec = float(duration_us) / 1_000_000.0 if duration_us > 0 else float(total_ticks) / 960.0
	_duration_sec = maxf(_duration_sec, 0.05)
	_traversal_duration_sec = maxf(_duration_sec / float(_traversal_count), 0.05)

	_recalculate_slider_length()
	_player_progress = 0.0
	_guide_progress = 0.0
	_update_local_guide_range()

	_required_strikes = maxi(1, int(view_model.get("required_strikes", 1)))
	_must_alternate = bool(view_model.get("must_alternate", true))
	visible = true
	queue_redraw()


func set_region_progress(value: float) -> void:
	region_progress = clampf(value, 0.0, 1.0)
	if not _has_authoritative_guide_range:
		_guide_progress = _guide_at_time_progress(region_progress)
		_update_local_guide_range()
	queue_redraw()


func set_approach_timing(time_to_start_sec: float, approach_duration_sec: float) -> void:
	_approach_progress = clampf(
		1.0 - time_to_start_sec / maxf(approach_duration_sec, 0.001),
		0.0,
		1.0
	)
	queue_redraw()


func set_gameplay_snapshot(snapshot: Dictionary) -> void:
	## 新系统入口：一份快照可同时携带两条独立滑条，本实例只读取与 event_id 相符的一条。
	var slider_state: Dictionary = _find_slider_state(snapshot.get("active_tuning_sliders", []))
	var active_field_id: String = str(snapshot.get("active_tuning_field_id", ""))
	var belongs_to_active_field: bool = (
		active_field_id.is_empty()
		or field_id.is_empty()
		or active_field_id == field_id
	)
	_field_active = (
		bool(snapshot.get("tuning_field_active", false))
		and belongs_to_active_field
	)
	var side_key: String = "life_held" if affinity == GameplayTypes.Affinity.ZHU else "death_held"
	tuning_active = _field_active and bool(snapshot.get(side_key, false))

	if not slider_state.is_empty():
		set_slider_state(slider_state)
	else:
		# 滑条会在正式起点前生成。此时用本钟的权威全局频率预定位，
		# 玩家在调频场空档移动后能立即看见真实位置，不会到开头才突然跳动。
		var value_key: String = (
			"life_tuning_value"
			if affinity == GameplayTypes.Affinity.ZHU
			else "death_tuning_value"
		)
		if snapshot.has(value_key):
			_player_progress = _progress_from_frequency_value(float(snapshot[value_key]))
		if not _has_authoritative_guide_range:
			_guide_progress = _guide_at_time_progress(region_progress)
			_update_local_guide_range()
	queue_redraw()


func set_slider_state(state: Dictionary) -> void:
	## 供预览器或 StageSession 直接推送单条滑条状态。
	if state.has("player_progress"):
		# 玩家可能尚在滑条范围外；保留超出 0～1 的真实位置，才能看见应往哪边预定位。
		_player_progress = float(state["player_progress"])
	elif state.has("player_value"):
		_player_progress = _progress_from_frequency_value(float(state["player_value"]))
	if state.has("guide_progress"):
		_guide_progress = clampf(float(state["guide_progress"]), 0.0, 1.0)
	if state.has("coverage"):
		_coverage = clampf(float(state["coverage"]), 0.0, 1.0)
	if state.has("held"):
		tuning_active = _field_active and bool(state["held"])

	var guide_min_key: String = "guide_min_progress" if state.has("guide_min_progress") else "guide_band_min"
	var guide_max_key: String = "guide_max_progress" if state.has("guide_max_progress") else "guide_band_max"
	_has_authoritative_guide_range = state.has(guide_min_key) and state.has(guide_max_key)
	if _has_authoritative_guide_range:
		_guide_min_progress = clampf(float(state[guide_min_key]), 0.0, 1.0)
		_guide_max_progress = clampf(float(state[guide_max_key]), 0.0, 1.0)
		if _guide_min_progress > _guide_max_progress:
			var swap: float = _guide_min_progress
			_guide_min_progress = _guide_max_progress
			_guide_max_progress = swap
	else:
		_update_local_guide_range()
	queue_redraw()


func set_tuning_active(active: bool) -> void:
	_field_active = active
	tuning_active = active
	queue_redraw()


func set_rapid_ratio(value: float) -> void:
	rapid_ratio = clampf(value, 0.0, 1.4)
	queue_redraw()


func play_judgment(grade: int) -> void:
	judgment_grade = grade
	missed = grade == GameplayTypes.JudgmentGrade.MISS
	queue_redraw()


func play_miss() -> void:
	play_judgment(GameplayTypes.JudgmentGrade.MISS)


func reset_for_pool() -> void:
	visible = false
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE
	_approach_progress = 0.0
	_has_authoritative_guide_range = false


func visual_state_snapshot() -> Dictionary:
	var start_point: Vector2 = _slider_start_point()
	var end_point: Vector2 = _slider_end_point()
	return {
		"event_id": event_id,
		"field_id": field_id,
		"group_id": group_id,
		"affinity": affinity,
		"field_active": _field_active,
		"tuning_active": tuning_active,
		"start_value": _start_value,
		"end_value": _end_value,
		"traversal_count": _traversal_count,
		"slider_length_px": _slider_length_px,
		"player_progress": _player_progress,
		"guide_progress": _guide_progress,
		"guide_min_progress": _guide_min_progress,
		"guide_max_progress": _guide_max_progress,
		"coverage": _coverage,
		"inside_guide": _player_inside_guide(),
		"region_progress": region_progress,
		"approach_progress": _approach_progress,
		"slider_start_point": start_point,
		"slider_end_point": end_point,
		"current_cursor_point": _point_on_slider(_player_progress),
		# 显式为 0，便于测试确认新滑条没有沿途判定点。
		"target_count": 0,
		"duration_sec": _duration_sec,
		"arc_span_rad": 0.0,
		"rail_radius": 0.0,
		"rapid_ratio": rapid_ratio,
		"rapid_required_strikes": _required_strikes,
		"rapid_valid_strikes": mini(_required_strikes, roundi(rapid_ratio * float(_required_strikes))),
		"rapid_hud_only": field_kind == 1,
		"rapid_static_wave_count": 0,
	}


func _draw() -> void:
	if field_kind == 0:
		_draw_tuning_slider()
	else:
		_draw_rapid_field()


func _draw_tuning_slider() -> void:
	var side_color: Color = life_color if affinity == GameplayTypes.Affinity.ZHU else death_color
	if missed:
		side_color = Color("666a72")
	var start_point: Vector2 = _slider_start_point()
	var end_point: Vector2 = _slider_end_point()
	var active_strength: float = 1.0 if tuning_active else 0.62
	var aligned: bool = tuning_active and _player_inside_guide()

	# 一条粗轨道承担全部空间关系；黑底和骨白描边让它在两种世界背景上都可读。
	draw_line(start_point, end_point, backing_color, tuning_rail_width + 14.0, true)
	draw_circle(start_point, (tuning_rail_width + 14.0) * 0.5, backing_color)
	draw_circle(end_point, (tuning_rail_width + 14.0) * 0.5, backing_color)
	draw_line(start_point, end_point, Color(side_color, 0.42 * active_strength), tuning_rail_width, true)
	draw_circle(start_point, tuning_rail_width * 0.5, Color(side_color, 0.42 * active_strength))
	draw_circle(end_point, tuning_rail_width * 0.5, Color(side_color, 0.42 * active_strength))
	draw_line(start_point, end_point, Color(bone_color, 0.58), 3.0, true)

	# 可接受区间直接画在轨道内部。玩家无需猜测隐藏的时间窗或空间阈值。
	var guide_from: Vector2 = _point_on_slider(_guide_min_progress)
	var guide_to: Vector2 = _point_on_slider(_guide_max_progress)
	var guide_color: Color = Color(bone_color, 0.64 if aligned else 0.36)
	var guide_width: float = tuning_rail_width * (0.48 if aligned else 0.38)
	draw_line(guide_from, guide_to, guide_color, guide_width, true)
	draw_circle(guide_from, guide_width * 0.5, guide_color)
	draw_circle(guide_to, guide_width * 0.5, guide_color)

	# 已走轨迹只覆盖当前一趟，不把上一次往返留下的线堆在轨道上。
	var leg_start_progress: float = 0.0 if _current_traversal_index() % 2 == 0 else 1.0
	var leg_start: Vector2 = _point_on_slider(leg_start_progress)
	var player_point: Vector2 = _point_on_slider(_player_progress)
	var walked_point: Vector2 = _point_on_slider(clampf(_player_progress, 0.0, 1.0))
	draw_line(leg_start, walked_point, Color(side_color, 0.88 * active_strength), 10.0, true)

	_draw_slider_head_and_destination(start_point, end_point, side_color, aligned)
	_draw_player_cursor(player_point, side_color, aligned)
	_draw_start_progress_ring(start_point)


func _draw_slider_head_and_destination(
	start_point: Vector2,
	end_point: Vector2,
	side_color: Color,
	aligned: bool
) -> void:
	var destination_progress: float = 1.0 if _current_traversal_index() % 2 == 0 else 0.0
	var destination: Vector2 = end_point if destination_progress > 0.5 else start_point

	# 头尾仅用两个大端点表示，避免重新引入刻度和文字。
	draw_circle(start_point, tuning_rail_width * 0.34, Color(backing_color, 0.98))
	draw_circle(start_point, tuning_rail_width * 0.24, Color(side_color, 0.92))
	draw_circle(end_point, tuning_rail_width * 0.34, Color(backing_color, 0.98))
	draw_circle(end_point, tuning_rail_width * 0.24, Color(side_color, 0.70))
	draw_arc(
		destination,
		tuning_rail_width * 0.34,
		0.0,
		TAU,
		32,
		Color(bone_color, 0.96 if aligned else 0.74),
		4.0,
		true
	)

	# 还有下一趟时，目的端内部出现一个朝返回方向的简洁折返箭头。
	if _current_traversal_index() >= _traversal_count - 1:
		return
	var back_direction: Vector2 = (_point_on_slider(1.0 - destination_progress) - destination).normalized()
	var normal := Vector2(-back_direction.y, back_direction.x)
	var tip: Vector2 = destination + back_direction * 12.0
	var rear: Vector2 = destination - back_direction * 9.0
	var arrow := PackedVector2Array([
		tip,
		rear + normal * 9.0,
		rear - normal * 9.0,
	])
	draw_colored_polygon(arrow, Color(bone_color, 0.92))


func _draw_player_cursor(point: Vector2, side_color: Color, aligned: bool) -> void:
	var pulse: float = 1.0 + (0.10 if aligned else 0.0)
	draw_circle(point, 24.0 * pulse, Color(backing_color, 0.98))
	draw_circle(point, 18.0 * pulse, Color(side_color, 0.98))
	draw_arc(point, 20.0 * pulse, 0.0, TAU, 28, Color(bone_color, 0.98 if aligned else 0.70), 4.0, true)
	draw_circle(point, 5.0, Color(bone_color, 0.96 if aligned else 0.64))


func _draw_start_progress_ring(start_point: Vector2) -> void:
	if region_progress > 0.0001 or judgment_grade >= 0:
		return
	var cue_radius: float = lerpf(54.0, tuning_rail_width * 0.37, _approach_progress)
	draw_arc(start_point, cue_radius, 0.0, TAU, 40, Color(backing_color, 0.90), 9.0, true)
	draw_arc(
		start_point,
		cue_radius,
		-PI * 0.5,
		-PI * 0.5 + TAU * _approach_progress,
		40,
		Color(bone_color, 0.96),
		4.0,
		true
	)


func _find_slider_state(value: Variant) -> Dictionary:
	if value is Dictionary:
		var states: Dictionary = value
		if states.has(event_id) and states[event_id] is Dictionary:
			return (states[event_id] as Dictionary).duplicate(true)
		if str(states.get("event_id", states.get("id", ""))) == event_id:
			return states.duplicate(true)
	elif value is Array:
		for entry: Variant in value:
			if entry is not Dictionary:
				continue
			var state: Dictionary = entry
			if str(state.get("event_id", state.get("id", ""))) == event_id:
				return state.duplicate(true)
	return {}


func _progress_from_frequency_value(value: float) -> float:
	var span: float = _end_value - _start_value
	if absf(span) <= 0.000001:
		return 0.0
	return (clampf(value, 0.0, 1.0) - _start_value) / span


func _recalculate_slider_length() -> void:
	var frequency_span_hz: float = (
		absf(_end_value - _start_value)
		* maxf(max_frequency_hz - min_frequency_hz, 0.0)
	)
	# 语义长度严格等于 Hz 跨度乘统一像素比例。即使很短或超出画布，也不能偷偷缩放，
	# 否则相同手部位移会在不同滑条上代表不同频率变化。
	_slider_length_px = frequency_span_hz * pixels_per_hz


func _guide_at_time_progress(time_progress: float) -> float:
	var clamped_progress: float = clampf(time_progress, 0.0, 1.0)
	if clamped_progress >= 1.0:
		return 1.0 if (_traversal_count - 1) % 2 == 0 else 0.0
	var traversal_position: float = clamped_progress * float(_traversal_count)
	var traversal_index: int = mini(floori(traversal_position), _traversal_count - 1)
	var local_progress: float = traversal_position - float(traversal_index)
	return local_progress if traversal_index % 2 == 0 else 1.0 - local_progress


func _update_local_guide_range() -> void:
	var time_margin_normalized: float = guide_time_margin_sec / maxf(_duration_sec, 0.001)
	var lower_time: float = clampf(region_progress - time_margin_normalized, 0.0, 1.0)
	var upper_time: float = clampf(region_progress + time_margin_normalized, 0.0, 1.0)
	var minimum: float = _guide_progress
	var maximum: float = _guide_progress
	# 临近折返点时，区间两端可能位于不同方向；多点采样可把整个合法范围如实包住。
	for sample_index: int in range(9):
		var ratio: float = float(sample_index) / 8.0
		var sampled: float = _guide_at_time_progress(lerpf(lower_time, upper_time, ratio))
		minimum = minf(minimum, sampled)
		maximum = maxf(maximum, sampled)
	_guide_min_progress = clampf(minimum - guide_space_margin, 0.0, 1.0)
	_guide_max_progress = clampf(maximum + guide_space_margin, 0.0, 1.0)


func _current_traversal_index() -> int:
	if region_progress >= 1.0:
		return _traversal_count - 1
	return mini(floori(region_progress * float(_traversal_count)), _traversal_count - 1)


func _player_inside_guide() -> bool:
	return _player_progress >= _guide_min_progress and _player_progress <= _guide_max_progress


func _slider_center() -> Vector2:
	var desired: Vector2 = life_slot_offset if affinity == GameplayTypes.Affinity.ZHU else -life_slot_offset
	# 只移动中心来尽量保住头尾；长度仍严格对应真实频率跨度。
	var maximum_center_x: float = maxf(
		canvas_size.x * 0.5 - slider_edge_margin_px - _slider_length_px * 0.5,
		0.0
	)
	desired.x = clampf(desired.x, -maximum_center_x, maximum_center_x)
	var maximum_center_y: float = maxf(
		canvas_size.y * 0.5 - slider_edge_margin_px - tuning_rail_width * 0.5,
		0.0
	)
	desired.y = clampf(desired.y, -maximum_center_y, maximum_center_y)
	return desired


func _frequency_axis() -> Vector2:
	# 两条轨道都采用“向右提高频率”，保证摇杆或手指向右时游标也向右。
	# 槽位中心仍保持中心对称；方向不镜像是为了避免操作反馈与手势相反。
	return Vector2.RIGHT


func _slider_start_point() -> Vector2:
	var direction_sign: float = 1.0 if _end_value >= _start_value else -1.0
	return _slider_center() - _frequency_axis() * (_slider_length_px * 0.5 * direction_sign)


func _slider_end_point() -> Vector2:
	var direction_sign: float = 1.0 if _end_value >= _start_value else -1.0
	return _slider_center() + _frequency_axis() * (_slider_length_px * 0.5 * direction_sign)


func _point_on_slider(progress: float) -> Vector2:
	# 玩家游标允许沿同一频率轴跑到滑条外；轨道和引导带自身仍只占 0～1。
	return _slider_start_point().lerp(_slider_end_point(), progress)


func _draw_rapid_field() -> void:
	var bone: Color = Color("eee4ca") if not missed else Color("6d7078")
	var life: Color = Color("c53a31") if not missed else Color("686b73")
	var death: Color = Color("727b91") if not missed else Color("555861")
	var background := Color("080a10", 0.88)
	var start_angle: float = -PI * 0.5
	var active: bool = _approach_progress >= 0.999 and judgment_grade < 0

	# 疾振只画紧凑的时间与计数，不预制任何静态波纹。
	draw_circle(Vector2.ZERO, rapid_time_radius + 13.0, Color("07090e", 0.70))
	draw_arc(Vector2.ZERO, rapid_time_radius, 0.0, TAU, 72, Color(bone, 0.16), 4.0, true)
	if not active and judgment_grade < 0:
		draw_arc(
			Vector2.ZERO,
			rapid_time_radius,
			start_angle,
			start_angle + TAU * _approach_progress,
			maxi(4, ceili(72.0 * _approach_progress)),
			Color(bone, 0.92),
			5.0,
			true
		)
	else:
		var remaining: float = clampf(1.0 - region_progress, 0.0, 1.0)
		if remaining > 0.001:
			draw_arc(
				Vector2.ZERO,
				rapid_time_radius,
				start_angle + TAU * region_progress,
				start_angle + TAU,
				maxi(4, ceili(72.0 * remaining)),
				Color(bone, 0.82),
				5.0,
				true
			)

	draw_circle(Vector2.ZERO, rapid_core_radius - 7.0, background)
	draw_arc(Vector2.ZERO, rapid_core_radius, PI * 0.5, PI * 1.5, 36, Color(death, 0.92), 9.0, true)
	draw_arc(Vector2.ZERO, rapid_core_radius, -PI * 0.5, PI * 0.5, 36, Color(life, 0.92), 9.0, true)
	draw_line(Vector2(0.0, -rapid_core_radius + 8.0), Vector2(0.0, rapid_core_radius - 8.0), Color(bone, 0.30), 2.0, true)

	var clamped_ratio: float = clampf(rapid_ratio, 0.0, 1.0)
	if clamped_ratio > 0.001:
		draw_arc(
			Vector2.ZERO,
			rapid_core_radius - 13.0,
			start_angle,
			start_angle + TAU * clamped_ratio,
			maxi(4, ceili(64.0 * clamped_ratio)),
			Color(bone, 0.96),
			5.0,
			true
		)

	var valid_strikes: int = mini(_required_strikes, roundi(clamped_ratio * float(_required_strikes)))
	var count_label: String = "%d / %d" % [valid_strikes, _required_strikes]
	if judgment_grade >= 0:
		count_label = "未成" if missed else "成纹"
	draw_string(ThemeDB.fallback_font, Vector2(-68.0, 7.0), count_label, HORIZONTAL_ALIGNMENT_CENTER, 136.0, 24, Color(bone, 0.96))
	var instruction: String = "准备疾振" if not active else ("左右交替" if _must_alternate else "双钟连击")
	if judgment_grade >= 0:
		instruction = ""
	draw_string(ThemeDB.fallback_font, Vector2(-110.0, rapid_time_radius + 42.0), instruction, HORIZONTAL_ALIGNMENT_CENTER, 220.0, 18, Color(bone, 0.78))
