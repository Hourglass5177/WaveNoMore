class_name GrayboxFieldVisual
extends Node2D

## 调频滑条或疾振计数器的灰盒表现。
## 调频滑条只显示宽轨、填充、时间点列和旋向；判定仍由领域层负责。

const TUNING_ARC_GEOMETRY: GDScript = preload("res://src/domain/tuning/tuning_arc_geometry.gd")

# 曲线先高密度采样，再按弧长重采样。这样玩家走过相同的画面距离，
# 始终代表相同的调频量，不会在弯曲处忽快忽慢。
const CURVE_SAMPLE_COUNT: int = 49
const CURVE_DENSE_SAMPLE_COUNT: int = 193
# 本项目谱面固定使用 PPQ 480；这里只用它计算点状引导的轻微拍点呼吸。
const TICKS_PER_BEAT: float = 480.0
const GUIDE_DOT_SPACING_PX: float = 28.0
# 历史布局常量；运行时调频条圆心固定在画布中心，不再使用该分栏间距。
const CENTER_GUTTER_PX: float = 32.0

## 0 为调频滑条，1 为疾振计数器。
@export_enum("Tuning", "Rapid") var field_kind: int = 0
## 正式素材可参考的占位尺寸；程序绘制不会强行裁切到这个范围。
@export var extent: Vector2 = Vector2(720.0, 300.0)

@export_group("Tuning Slider")
## 滑条主体宽度；两端会自动绘制成同直径的圆帽。
@export_range(72.0, 144.0, 1.0) var tuning_rail_width: float = 104.0
## 主体外侧骨白描边厚度，不参与频率长度计算。
@export_range(2.0, 16.0, 1.0) var tuning_outline_width: float = 8.0
## 历史插槽参数；运行时调频条统一使用画布中心，该资源属性不再参与布局。
@export var life_slot_offset: Vector2 = Vector2(0.0, -188.0)
## 用于安全摆放滑条的设计画布尺寸；只平移插槽，绝不缩短轨道。
@export var canvas_size: Vector2 = Vector2(1920.0, 1080.0)
## 历史边界参数；运行时不再根据边界移动或缩放调频条。
@export_range(0.0, 180.0, 1.0) var slider_edge_margin_px: float = 72.0
## 每 1 Hz 对应的端点弦长；圆弧可以变弯，但同样频差的两端距离保持一致。
@export_range(40.0, 260.0, 1.0) var pixels_per_hz: float = 160.0
## 归一化频率轴两端对应的物理频率，仅用于把频率跨度换算成画面长度。
@export_range(0.1, 20.0, 0.1) var min_frequency_hz: float = 1.0
@export_range(0.1, 20.0, 0.1) var max_frequency_hz: float = 7.0
## 已弃用：自由调频仍使用“每圈多少 Hz”，计分滑条的形状改由等效圆几何决定。
## 暂时保留字段，避免旧场景资源失去属性。
@export_range(0.1, 60.0, 0.1) var rotary_hz_per_revolution: float = 32.0
## 点状时间引导的额外空间余量；只用于即时亮度反馈，不参与评分。
@export_range(0.0, 0.25, 0.005) var guide_space_margin: float = 0.08
## 时间提示余量，单位秒；会换算成当前滑条上的视觉引导范围。
@export_range(0.0, 0.5, 0.005) var guide_time_margin_sec: float = 0.18

@export_group("Tuning Palette")
## 生钟滑条主色。
@export var life_color: Color = Color("c23b31")
## 死钟滑条主色。刻意比死界背景更亮，避免玄色信息消失。
@export var death_color: Color = Color("414a60")
## 滑条描边、点状引导和贴合反馈使用的骨白色。
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
# 频率跨度先确定屏幕弦长，再由等效圆得到圆心角、半径和真实弧长。
var _slider_chord_px: float = 384.0
var _slider_length_px: float = 384.0
var _slider_sweep_rad: float = deg_to_rad(45.0)
var _slider_radius_px: float = 0.0
var _slider_center_distance_px: float = 0.0
# 谱面可把整段等效圆弧旋转到横向、斜向或近纵向；起手扇区使用同一角度。
var _arc_rotation_rad: float = 0.0
# 历史构图偏移；运行时视觉圆心固定在画布中心，不读取该值布局。
var _visual_offset_px: Vector2 = Vector2.ZERO
# 玩家填充前沿与时间引导在轨道上的空间位置，均为 0～1。
var _player_progress: float = 0.0
var _guide_progress: float = 0.0
# 当前点状引导带边界。若领域快照提供权威值，会覆盖本地预览计算。
var _guide_min_progress: float = 0.0
var _guide_max_progress: float = 0.0
var _has_authoritative_guide_range: bool = false
# 1 为顺时针，-1 为逆时针，0 表示当前无需继续旋转。
var _required_rotation_sign: int = 0
var _has_authoritative_rotation_sign: bool = false
# 当前单程端点的权威判定状态。它只改变端点提示颜色，不参与实际评分。
var _endpoint_has_state: bool = false
var _endpoint_target_progress: float = 1.0
var _endpoint_inside: bool = false
var _endpoint_captured: bool = false
var _endpoint_window_active: bool = false
var _endpoint_grade: int = GameplayTypes.JudgmentGrade.MISS
var _endpoint_best_error_us: int = 0
# 贴合状态只做很短的亮度缓动，不改变玩家填充的位置。
var _alignment_strength: float = 0.0
# 调频时间场是否已开启；普通段即使按住钟也不显示可操作态。
var _field_active: bool = false
# PREVIEW 只显示缩圈和起手提示；到权威起点后才进入可操作态。
var _interaction_open: bool = false
var _authoritative_traversal_index: int = 0
var _turnaround_pending: bool = false
# 调频区域接近事件起点的收束进度。
var _approach_progress: float = 0.0
# Host 按可见分组分配的小序号与预读层级；同组生死滑条共享序号。
var _preview_order_number: int = 0
var _preview_phase: int = 1
var _preview_alpha: float = 0.45
# 疾振要求次数和交替规则只参与疾振 HUD。
var _required_strikes: int = 1
var _must_alternate: bool = true
# 由频率低端指向高端的等弧长曲线，以及按事件起终点重排后的曲线。
var _frequency_curve_points: PackedVector2Array = PackedVector2Array()
var _event_curve_points: PackedVector2Array = PackedVector2Array()
# 当前圆弧相对插槽中心的包围盒，用来避开中线与屏幕边缘。
var _curve_min_relative: Vector2 = Vector2.ZERO
var _curve_max_relative: Vector2 = Vector2.ZERO


func configure_from_rules(rules: GameplayRuleSet) -> void:
	## 滑条的空间尺度与视觉提示直接读取关卡规则，避免预览和实机关卡表现不一致。
	if rules == null:
		return
	canvas_size = rules.wave_canvas_size
	pixels_per_hz = rules.tuning_pixels_per_hz
	min_frequency_hz = rules.tuning_min_frequency_hz
	max_frequency_hz = rules.tuning_max_frequency_hz
	rotary_hz_per_revolution = rules.tuning_hz_per_revolution
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
	_interaction_open = false
	_authoritative_traversal_index = 0
	_turnaround_pending = false
	_required_rotation_sign = 0
	_has_authoritative_rotation_sign = false
	_clear_endpoint_state()
	_alignment_strength = 0.0
	_approach_progress = 0.0
	_preview_order_number = 0
	_preview_phase = 1
	_preview_alpha = 0.45

	_start_value = clampf(float(view_model.get("start_value", 0.0)), 0.0, 1.0)
	_end_value = clampf(float(view_model.get("end_value", 1.0)), 0.0, 1.0)
	_arc_rotation_rad = deg_to_rad(float(view_model.get("arc_rotation_deg", 0.0)))
	_visual_offset_px = view_model.get("visual_offset_px", Vector2.ZERO)
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


func _process(delta: float) -> void:
	## 贴合反馈只缓动亮度；填充前沿始终直接使用领域层位置，绝不产生操作拖尾。
	if field_kind != 0 or not visible:
		return
	var target: float = 1.0 if tuning_active and _player_inside_guide() else 0.0
	var duration_sec: float = 0.06 if target > _alignment_strength else 0.10
	var previous: float = _alignment_strength
	_alignment_strength = move_toward(_alignment_strength, target, delta / duration_sec)
	if not is_equal_approx(previous, _alignment_strength):
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


func set_preview_presentation(order_number: int, phase: int, alpha: float) -> void:
	## phase 由 Host 统一计算：0 为当前、1 为未来、2 为已经结束的收尾。
	_preview_order_number = maxi(order_number, 0)
	_preview_phase = clampi(phase, 0, 2)
	_preview_alpha = clampf(alpha, 0.0, 1.0)
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
	tuning_active = _field_active and _interaction_open and bool(snapshot.get(side_key, false))

	if not slider_state.is_empty():
		set_slider_state(slider_state)
	else:
		_interaction_open = false
		_turnaround_pending = false
		_has_authoritative_rotation_sign = false
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
	_interaction_open = bool(state.get("interaction_open", true))
	_authoritative_traversal_index = maxi(0, int(state.get(
		"current_traversal_index",
		state.get("current_endpoint_index", 0)
	)))
	_turnaround_pending = bool(state.get(
		"turnaround_pending",
		_authoritative_traversal_index < _traversal_count - 1
	))
	if state.has("player_progress"):
		# 玩家可能尚在滑条范围外；保留超出 0～1 的真实位置，才能看见应往哪边预定位。
		_player_progress = float(state["player_progress"])
	elif state.has("player_value"):
		_player_progress = _progress_from_frequency_value(float(state["player_value"]))
	if state.has("guide_progress"):
		_guide_progress = clampf(float(state["guide_progress"]), 0.0, 1.0)
	if not _interaction_open:
		# 表现层也守住 PREVIEW 边界：即使上游热重载带来旧频率值，
		# 缩圈结束前仍只显示空槽，不让玩家误以为提前旋转有效。
		_player_progress = 0.0
		_guide_progress = 0.0
	if state.has("held"):
		tuning_active = _field_active and _interaction_open and bool(state["held"])
	_has_authoritative_rotation_sign = state.has("required_rotation_sign")
	if _has_authoritative_rotation_sign:
		_required_rotation_sign = clampi(int(state["required_rotation_sign"]), -1, 1)
	_endpoint_has_state = state.has("endpoint_target_progress")
	if _endpoint_has_state:
		_endpoint_target_progress = clampf(float(state["endpoint_target_progress"]), 0.0, 1.0)
		_endpoint_inside = bool(state.get("endpoint_inside", false))
		_endpoint_captured = bool(state.get("endpoint_captured", false))
		_endpoint_window_active = bool(state.get("endpoint_window_active", false))
		_endpoint_grade = int(state.get("endpoint_grade", GameplayTypes.JudgmentGrade.MISS))
		_endpoint_best_error_us = int(state.get("endpoint_best_error_us", 0))
	else:
		_clear_endpoint_state()

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
	_interaction_open = active
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
	_required_rotation_sign = 0
	_has_authoritative_rotation_sign = false
	_clear_endpoint_state()
	_alignment_strength = 0.0
	_interaction_open = false
	_authoritative_traversal_index = 0
	_turnaround_pending = false
	_preview_order_number = 0
	_preview_phase = 1
	_preview_alpha = 0.45


func visual_state_snapshot() -> Dictionary:
	var start_point: Vector2 = _slider_start_point()
	var end_point: Vector2 = _slider_end_point()
	var cue_angles: Vector2 = _rotation_cue_angles()
	var arc_sweep: float = _gesture_sweep_rad()
	return {
		"event_id": event_id,
		"field_id": field_id,
		"group_id": group_id,
		"affinity": affinity,
		"field_active": _field_active,
		"interaction_open": _interaction_open,
		"tuning_active": tuning_active,
		"start_value": _start_value,
		"end_value": _end_value,
		"traversal_count": _traversal_count,
		"slider_chord_px": _slider_chord_px,
		"slider_length_px": _slider_length_px,
		"curve_length_px": _polyline_length(_event_curve_points),
		"curve_sample_count": _event_curve_points.size(),
		"curve_points": _event_curve_points,
		"player_progress": _player_progress,
		"fill_progress": _leg_fill_progress(),
		"guide_progress": _guide_progress,
		"guide_dot_count": _guide_dot_count(),
		"guide_min_progress": _guide_min_progress,
		"guide_max_progress": _guide_max_progress,
		"inside_guide": _player_inside_guide(),
		"region_progress": region_progress,
		"approach_progress": _approach_progress,
		"start_cue_visible": _start_cue_visible(),
		"start_cue_radius_px": _start_cue_radius_px(),
		"start_cue_progress_stroke_px": 8.0,
		"preview_order_number": _preview_order_number,
		"preview_phase": _preview_phase,
		"preview_alpha": _preview_alpha,
		"arc_rotation_deg": rad_to_deg(_arc_rotation_rad),
		"visual_offset_px": _visual_offset_px,
		"current_traversal_index": _authoritative_traversal_index,
		"turnaround_pending": _turnaround_pending,
		"slider_start_point": start_point,
		"slider_end_point": end_point,
		"current_cursor_point": _point_on_slider(_player_progress),
		"required_rotation_sign": _effective_rotation_sign(),
		"rotation_cue_sweep_rad": absf(cue_angles.y - cue_angles.x),
		"rotation_cue_start_direction": Vector2.from_angle(cue_angles.x),
		"rotation_cue_end_direction": Vector2.from_angle(cue_angles.y),
		"endpoint_target_progress": _endpoint_target_progress,
		"endpoint_inside": _endpoint_inside,
		"endpoint_captured": _endpoint_captured,
		"endpoint_window_active": _endpoint_window_active,
		"endpoint_grade": _endpoint_grade,
		"endpoint_best_error_us": _endpoint_best_error_us,
		# 显式为 0，便于测试确认新滑条没有沿途判定点。
		"target_count": 0,
		"duration_sec": _duration_sec,
		"arc_span_rad": arc_sweep,
		"rail_radius": _slider_radius_px,
		"equivalent_center_distance_px": _slider_center_distance_px,
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
	if _event_curve_points.is_empty():
		return
	var presentation_alpha: float = _preview_content_alpha()

	# 粗轨道只有描边、底色和一层玩家填充；点状时间引导不会干预玩家位置。
	var outline_color := Color(bone_color, 0.72 if not missed else 0.38)
	outline_color.a *= presentation_alpha
	var rail_color := side_color.darkened(0.58)
	rail_color.a = 0.82 if _field_active else 0.66
	rail_color.a *= presentation_alpha
	_draw_round_polyline(
		_event_curve_points,
		outline_color,
		tuning_rail_width + tuning_outline_width * 2.0
	)
	_draw_round_polyline(_event_curve_points, rail_color, tuning_rail_width)

	# 填充按本程计量：换程时领域把频率值重置到新程起点，本程填充前沿
	# 自然归零；奇数程从曲线终点反向回填，不再沿整条事件曲线续画。
	var leg_fill_progress: float = _leg_fill_progress()
	if _interaction_open and leg_fill_progress > 0.0001:
		var fill_color := side_color.lightened(0.16 + 0.08 * _alignment_strength)
		fill_color.a = lerpf(0.80, 0.98, _alignment_strength)
		_draw_round_polyline(_partial_leg_fill_curve(leg_fill_progress), fill_color, tuning_rail_width)

	if _interaction_open:
		_draw_guide_dots()
	_draw_rotation_cue()
	_draw_turnaround_hint()
	_draw_start_progress_ring(_slider_start_point())
	_draw_order_number(_slider_start_point())


func _draw_order_number(start_point: Vector2) -> void:
	if _preview_order_number <= 0:
		return
	var label: String = str(_preview_order_number)
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 24
	var text_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := start_point + Vector2(-text_size.x * 0.5, text_size.y * 0.34)
	# 序号压在起点圆帽中央，仅帮助读取先后，不再增加一层独立徽章。
	var cue_alpha: float = _start_cue_alpha() if not _interaction_open else 1.0
	draw_string(
		font,
		baseline + Vector2(2.0, 2.0),
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		Color(backing_color, 0.94 * cue_alpha)
	)
	draw_string(
		font,
		baseline,
		label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size,
		Color(bone_color, 0.98 * cue_alpha)
	)


func _draw_guide_dots() -> void:
	var dot_count: int = _guide_dot_count()
	if dot_count <= 0:
		return
	var total_ticks: float = float(_traversal_ticks * _traversal_count)
	var elapsed_beats: float = region_progress * total_ticks / TICKS_PER_BEAT
	var beat_fraction: float = elapsed_beats - floorf(elapsed_beats)
	var distance_to_beat: float = minf(beat_fraction, 1.0 - beat_fraction)
	# 亮度峰值落在整数拍，而不是落在拍后四分之一处；每四拍再加一次克制的强拍强调。
	var beat_pulse: float = 1.0 - smoothstep(0.0, 0.22, distance_to_beat)
	var beat_index: int = floori(elapsed_beats + 0.0001)
	var measure_accent: float = 1.0 if posmod(beat_index, 4) == 0 else 0.0
	var dot_color := Color(
		bone_color,
		0.68 + beat_pulse * (0.18 + measure_accent * 0.10) + 0.04 * _alignment_strength
	)
	var dot_radius: float = 4.6 + beat_pulse * (0.8 + measure_accent * 0.4)
	var guide_distance: float = clampf(_guide_progress, 0.0, 1.0) * _slider_length_px
	for index: int in range(dot_count):
		var distance: float = minf(float(index) * GUIDE_DOT_SPACING_PX, guide_distance)
		var progress: float = distance / maxf(_slider_length_px, 0.001)
		var point: Vector2 = _point_on_slider(progress)
		# 深色托底保证虚线经过明亮场景时仍然清楚，白点本身仍保持单层、简洁。
		draw_circle(point, dot_radius + 2.5, Color(backing_color, 0.72))
		draw_circle(point, dot_radius, dot_color)


func _draw_rotation_cue() -> void:
	var rotation_sign: int = _effective_rotation_sign()
	if rotation_sign == 0:
		return
	var destination_progress: float = (
		_endpoint_target_progress
		if _endpoint_has_state
		else (1.0 if _current_traversal_index() % 2 == 0 else 0.0)
	)
	# 预备阶段先在起点旁直接说明如何起手；正式操作后，提示才移动到当前目的端。
	var center: Vector2 = (
		_slider_start_point()
		if not _interaction_open
		else _point_on_slider(destination_progress)
	)
	var turnaround_pulse: float = _turnaround_pulse()
	var radius: float = tuning_rail_width * (0.66 + turnaround_pulse * 0.035)
	var cue_angles: Vector2 = _rotation_cue_angles()
	var start_angle: float = cue_angles.x
	var sweep: float = cue_angles.y - cue_angles.x
	var points := PackedVector2Array()
	for index: int in range(19):
		var ratio: float = float(index) / 18.0
		var angle: float = start_angle + sweep * ratio
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	# 如果玩家很早便顶住端点且没有退回重进，就用灰色克制地提示“这里尚未卡拍”。
	# 玩家退离端点后提示恢复骨白，提醒其在窗口内重新进入；不额外弹文字打断视线。
	var waiting_for_reentry: bool = (
		_endpoint_has_state
		and _endpoint_inside
		and _endpoint_captured
		and _endpoint_grade == GameplayTypes.JudgmentGrade.MISS
	)
	var cue_color := (
		Color("8b8e94", 0.76)
		if waiting_for_reentry
		else Color(bone_color, lerpf(0.72, 0.98, _alignment_strength))
	)
	if not _interaction_open:
		cue_color.a *= _start_cue_alpha()
	draw_polyline(points, cue_color, 7.0, true)
	# 小圆点标起手端，箭头标落手端；不要求玩家精确瞄准，只传达自然手势方向。
	draw_circle(points[0], 4.5, cue_color)

	# 箭头沿圆弧切线收尾；正号在 Godot 的屏幕坐标中就是视觉顺时针。
	var end_angle: float = start_angle + sweep
	var tip: Vector2 = points[-1]
	var tangent := Vector2(-sin(end_angle), cos(end_angle)) * float(rotation_sign)
	var normal := Vector2(-tangent.y, tangent.x)
	draw_colored_polygon(
		PackedVector2Array([
			tip + tangent * 2.0,
			tip - tangent * 18.0 + normal * 10.0,
			tip - tangent * 18.0 - normal * 10.0,
		]),
		cue_color
	)



func _draw_turnaround_hint() -> void:
	## 往返只在折返点显示一枚“转回来”的弧形箭头，不重新播放起手缩圈。
	if not _interaction_open or _traversal_count <= 1:
		return
	var turnaround_pulse: float = _turnaround_pulse()
	var leg_index: int = _current_traversal_index()
	var traversal_position: float = region_progress * float(_traversal_count)
	var local_progress: float = clampf(traversal_position - float(leg_index), 0.0, 1.0)
	var approaching_turn: bool = _turnaround_pending and local_progress >= 0.45
	if not approaching_turn and turnaround_pulse <= 0.001:
		return

	var boundary_index: int
	if turnaround_pulse > 0.001:
		boundary_index = clampi(roundi(traversal_position), 1, _traversal_count - 1)
	else:
		boundary_index = leg_index + 1
	var boundary_progress: float = 1.0 if boundary_index % 2 == 1 else 0.0
	var center: Vector2 = _point_on_slider(boundary_progress)
	var alpha: float = maxf(
		smoothstep(0.45, 0.88, local_progress) if approaching_turn else 0.0,
		turnaround_pulse
	)
	# 抵达前画当前旋向的反向；越过强拍后，权威旋向已经翻转，直接沿新方向画。
	var return_sign: int = (
		_effective_rotation_sign()
		if turnaround_pulse > 0.001 and leg_index >= boundary_index
		else -_effective_rotation_sign()
	)
	if return_sign == 0:
		return
	var middle_angle: float = TUNING_ARC_GEOMETRY.center_angle_rad(
		affinity,
		_arc_rotation_rad
	)
	var sweep: float = deg_to_rad(58.0) * float(return_sign)
	var start_angle: float = middle_angle - sweep * 0.5
	var radius: float = tuning_rail_width * 0.90
	var points := PackedVector2Array()
	for index: int in range(17):
		var ratio: float = float(index) / 16.0
		points.append(center + Vector2.from_angle(start_angle + sweep * ratio) * radius)
	var color := Color(bone_color, 0.30 + 0.64 * alpha)
	draw_polyline(points, color, 6.0, true)
	var tip: Vector2 = points[-1]
	var end_angle: float = start_angle + sweep
	var tangent := Vector2(-sin(end_angle), cos(end_angle)) * float(return_sign)
	var normal := Vector2(-tangent.y, tangent.x)
	draw_colored_polygon(
		PackedVector2Array([
			tip + tangent * 2.0,
			tip - tangent * 16.0 + normal * 9.0,
			tip - tangent * 16.0 - normal * 9.0,
		]),
		color
	)


func _draw_start_progress_ring(start_point: Vector2) -> void:
	# 一条往返滑槽只有事件开始前出现一次缩圈；折返点只使用回转箭头。
	if not _start_cue_visible():
		return
	var cue_radius: float = _start_cue_radius_px()
	var cue_alpha: float = _start_cue_alpha()
	# 深色托底、完整骨白圈和计时亮弧共享同一半径。圈从轨道外明显收进端帽，
	# 即使场景很亮或滑条还处在第二预读层，也能一眼看出何时开始。
	draw_arc(start_point, cue_radius, 0.0, TAU, 48, Color(backing_color, 0.94 * cue_alpha), 14.0, true)
	draw_arc(start_point, cue_radius, 0.0, TAU, 48, Color(bone_color, 0.52 * cue_alpha), 8.0, true)
	draw_arc(
		start_point,
		cue_radius,
		-PI * 0.5,
		-PI * 0.5 + TAU * _approach_progress,
		48,
		Color(bone_color, 0.99 * cue_alpha),
		8.0,
		true
	)


func _preview_content_alpha() -> float:
	## 当前条完全显示；未来与收尾条只压暗轨道，不连带压暗起手提示。
	if _interaction_open or _preview_phase == 0:
		return 1.0
	return _preview_alpha


func _start_cue_visible() -> bool:
	return not _interaction_open and judgment_grade < 0


func _start_cue_radius_px() -> float:
	# 104px 宽轨道的端帽半径为52px；终点缩到其内部，收束动作会比旧24px幅度明显得多。
	return lerpf(106.0, 38.0, smoothstep(0.0, 1.0, _approach_progress))


func _start_cue_alpha() -> float:
	# 最近未来条约0.95，更远条约0.70；轨道仍保持Host给出的0.70/0.45层级。
	return clampf(_preview_alpha + 0.25, 0.62, 1.0)


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
	# 屏幕端点距离仍严格服从“频率跨度 × pixels_per_hz”。圆弧只向弦的
	# 中垂线方向鼓起，因此改变曲率不会偷偷改变玩家理解的调频跨度。
	_slider_chord_px = TUNING_ARC_GEOMETRY.chord_length_px(
		_start_value,
		_end_value,
		min_frequency_hz,
		max_frequency_hz,
		pixels_per_hz
	)
	var requested_center_distance_px: float = TUNING_ARC_GEOMETRY.equivalent_center_distance_px(
		canvas_size.x
	)
	_slider_sweep_rad = TUNING_ARC_GEOMETRY.equivalent_sweep_from_chord_rad(
		_slider_chord_px,
		requested_center_distance_px
	)
	_slider_radius_px = TUNING_ARC_GEOMETRY.equivalent_radius_from_chord_px(
		_slider_chord_px,
		_slider_sweep_rad
	)
	# 极短或极长滑条会触发角度上下限；调试值应报告钳制后真实圆的弦心距。
	_slider_center_distance_px = (
		_slider_radius_px * cos(_slider_sweep_rad * 0.5)
		if _slider_radius_px > 0.0
		else 0.0
	)
	_slider_length_px = _slider_radius_px * _slider_sweep_rad
	_rebuild_slider_curves()


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
	if _interaction_open:
		return clampi(_authoritative_traversal_index, 0, _traversal_count - 1)
	if region_progress >= 1.0:
		return _traversal_count - 1
	return mini(floori(region_progress * float(_traversal_count)), _traversal_count - 1)


func _player_inside_guide() -> bool:
	return _player_progress >= _guide_min_progress and _player_progress <= _guide_max_progress


func update_hold_control(visual: GrayboxHoldVisual, control_center: Vector2, radius_px: float) -> void:
	## 使用实际绘制游标的方向，同时设置真 Hold 的朝向和反侧圆周目标。
	## Host 仅在领域拖动为 true 时调用；此处不推进插值或动态尾部。
	var cursor: Vector2 = _point_on_slider(clampf(_player_progress, 0.0, 1.0))
	var direction: Vector2 = (cursor - control_center).normalized()
	visual.set_head_heading(direction.angle())
	visual.set_head_position(control_center - direction * radius_px)


func _slider_center() -> Vector2:
	# FieldSlot 的局部坐标以设计画布左上角为原点。曲线采样点以弦中点为
	# 基准，而不是圆心；因此先补偿弦中点到真实圆心的法向距离。
	# visual_offset_px、life_slot_offset、CENTER_GUTTER_PX 与
	# slider_edge_margin_px 保留在数据/编辑器中，但运行时不参与布局。
	return canvas_size * 0.5 - _arc_center_offset()


func _arc_center_offset() -> Vector2:
	## 返回真实圆心相对弦中点的向量；与曲线采样复用相同的旋转和镜像。
	var center_distance: float = (
		_slider_radius_px * cos(_slider_sweep_rad * 0.5)
		if _slider_radius_px > 0.0
		else 0.0
	)
	return _transform_curve_relative(Vector2(0.0, center_distance))


func _slider_start_point() -> Vector2:
	if _event_curve_points.is_empty():
		return _slider_center()
	return _event_curve_points[0]


func _slider_end_point() -> Vector2:
	if _event_curve_points.is_empty():
		return _slider_center()
	return _event_curve_points[-1]


func _point_on_slider(progress: float) -> Vector2:
	# 调试快照允许玩家位置落在 0～1 之外；此时沿端点切线延长，
	# 轨道和填充本身仍严格限制在曲线范围内。
	if _event_curve_points.size() < 2:
		return _slider_center()
	if progress <= 0.0:
		var start_tangent: Vector2 = (_event_curve_points[1] - _event_curve_points[0]).normalized()
		return _event_curve_points[0] + start_tangent * (_slider_length_px * progress)
	if progress >= 1.0:
		var end_index: int = _event_curve_points.size() - 1
		var end_tangent: Vector2 = (_event_curve_points[end_index] - _event_curve_points[end_index - 1]).normalized()
		return _event_curve_points[end_index] + end_tangent * (_slider_length_px * (progress - 1.0))
	var scaled_index: float = progress * float(_event_curve_points.size() - 1)
	var lower_index: int = floori(scaled_index)
	var upper_index: int = mini(lower_index + 1, _event_curve_points.size() - 1)
	return _event_curve_points[lower_index].lerp(
		_event_curve_points[upper_index],
		scaled_index - float(lower_index)
	)


func _rebuild_slider_curves() -> void:
	## 先构造“左低右高”的标准圆弧，再根据谱面升降频方向决定事件采样顺序。
	## 弦长表示频率跨度；圆心角来自同一份等效圆规格，也就是摇杆的完整手势行程。
	var frequency_relative := PackedVector2Array()
	for index: int in range(CURVE_DENSE_SAMPLE_COUNT):
		var t: float = float(index) / float(CURVE_DENSE_SAMPLE_COUNT - 1)
		# _relative_curve_point() 是阵营镜像和死侧反向采样的唯一入口。
		frequency_relative.append(_relative_curve_point(t))
	_update_curve_bounds(frequency_relative)

	var dense_world := PackedVector2Array()
	var center: Vector2 = _slider_center()
	for relative: Vector2 in frequency_relative:
		dense_world.append(center + relative)
	_frequency_curve_points = _resample_polyline(dense_world, CURVE_SAMPLE_COUNT)

	_event_curve_points = PackedVector2Array()
	var increasing: bool = _end_value >= _start_value
	for index: int in range(_frequency_curve_points.size()):
		var source_index: int = index if increasing else _frequency_curve_points.size() - 1 - index
		_event_curve_points.append(_frequency_curve_points[source_index])


func _update_curve_bounds(points: PackedVector2Array) -> void:
	## 使用旋转后真实采样点的包围盒，不能再拿弧长或水平半宽估算。
	if points.is_empty():
		_curve_min_relative = Vector2.ZERO
		_curve_max_relative = Vector2.ZERO
		return
	_curve_min_relative = points[0]
	_curve_max_relative = points[0]
	for point: Vector2 in points:
		_curve_min_relative.x = minf(_curve_min_relative.x, point.x)
		_curve_min_relative.y = minf(_curve_min_relative.y, point.y)
		_curve_max_relative.x = maxf(_curve_max_relative.x, point.x)
		_curve_max_relative.y = maxf(_curve_max_relative.y, point.y)


func _normalized_curve_point(t: float) -> Vector2:
	return TUNING_ARC_GEOMETRY.normalized_chord_arc_point(t, _gesture_sweep_rad())


func _relative_curve_point(t: float) -> Vector2:
	## 将标准圆弧点统一应用旋转和死侧中心反演。
	var sample_t: float = 1.0 - t if affinity == GameplayTypes.Affinity.XUAN else t
	var standard_relative: Vector2 = _normalized_curve_point(sample_t) * _slider_chord_px
	return _transform_curve_relative(standard_relative)


func _transform_curve_relative(standard_relative: Vector2) -> Vector2:
	## 曲线采样点与圆心偏移必须共享同一坐标变换，避免圆心补偿方向分叉。
	return TUNING_ARC_GEOMETRY.transform_curve_relative(standard_relative, affinity, _arc_rotation_rad)


func _resample_polyline(source: PackedVector2Array, target_count: int) -> PackedVector2Array:
	if source.is_empty() or target_count <= 0:
		return PackedVector2Array()
	if source.size() == 1 or target_count == 1:
		return PackedVector2Array([source[0]])
	var cumulative := PackedFloat32Array([0.0])
	for index: int in range(1, source.size()):
		cumulative.append(cumulative[-1] + source[index - 1].distance_to(source[index]))
	var total_length: float = cumulative[-1]
	if total_length <= 0.0001:
		return PackedVector2Array([source[0], source[-1]])

	var result := PackedVector2Array()
	var source_index: int = 1
	for index: int in range(target_count):
		var target_distance: float = total_length * float(index) / float(target_count - 1)
		while source_index < cumulative.size() - 1 and cumulative[source_index] < target_distance:
			source_index += 1
		var segment_start: float = cumulative[source_index - 1]
		var segment_length: float = maxf(cumulative[source_index] - segment_start, 0.0001)
		var ratio: float = (target_distance - segment_start) / segment_length
		result.append(source[source_index - 1].lerp(source[source_index], ratio))
	return result


func _leg_fill_progress() -> float:
	## 填充前沿按本程计量：0 是本程起点、1 是本程终点。
	## 偶数程从曲线起点（start_value）向外增长；奇数程从曲线终点反向回填，
	## 因此上一程结束后填充归零，并从本程起点重新接受输入增长。
	var curve_progress: float = clampf(_player_progress, 0.0, 1.0)
	return curve_progress if _current_traversal_index() % 2 == 0 else 1.0 - curve_progress


func _partial_leg_fill_curve(leg_fill: float) -> PackedVector2Array:
	## 偶数程取曲线起点一侧，奇数程取曲线终点一侧；填充始终从本程起点长出。
	if _current_traversal_index() % 2 == 0:
		return _partial_event_curve(leg_fill)
	return _partial_event_curve_from_end(leg_fill)


func _partial_event_curve_from_end(fill_progress: float) -> PackedVector2Array:
	## _partial_event_curve 的镜像：保留曲线末端 fill_progress 比例的一段，
	## 供奇数程从本程起点（曲线终点）反向回填使用。
	var clamped_progress: float = clampf(fill_progress, 0.0, 1.0)
	if _event_curve_points.size() < 2 or clamped_progress <= 0.0:
		return PackedVector2Array()
	var scaled_index: float = (1.0 - clamped_progress) * float(_event_curve_points.size() - 1)
	var first_whole_index: int = ceili(scaled_index)
	var result := PackedVector2Array()
	for index: int in range(first_whole_index, _event_curve_points.size()):
		result.append(_event_curve_points[index])
	if first_whole_index > 0 and not is_equal_approx(scaled_index, float(first_whole_index)):
		result.insert(0, _event_curve_points[first_whole_index - 1].lerp(
			_event_curve_points[first_whole_index],
			scaled_index - float(first_whole_index - 1)
		))
	return result


func _partial_event_curve(progress: float) -> PackedVector2Array:
	var clamped_progress: float = clampf(progress, 0.0, 1.0)
	if _event_curve_points.size() < 2 or clamped_progress <= 0.0:
		return PackedVector2Array()
	var scaled_index: float = clamped_progress * float(_event_curve_points.size() - 1)
	var last_whole_index: int = floori(scaled_index)
	var result := PackedVector2Array()
	for index: int in range(last_whole_index + 1):
		result.append(_event_curve_points[index])
	if last_whole_index < _event_curve_points.size() - 1 and not is_equal_approx(scaled_index, float(last_whole_index)):
		result.append(_event_curve_points[last_whole_index].lerp(
			_event_curve_points[last_whole_index + 1],
			scaled_index - float(last_whole_index)
		))
	return result


func _draw_round_polyline(points: PackedVector2Array, color: Color, width: float) -> void:
	if points.is_empty() or width <= 0.0:
		return
	if points.size() > 1:
		draw_polyline(points, color, width, true)
	draw_circle(points[0], width * 0.5, color)
	draw_circle(points[-1], width * 0.5, color)


func _polyline_length(points: PackedVector2Array) -> float:
	var result: float = 0.0
	for index: int in range(1, points.size()):
		result += points[index - 1].distance_to(points[index])
	return result


func _guide_dot_count() -> int:
	var guide_distance: float = clampf(_guide_progress, 0.0, 1.0) * _slider_length_px
	if guide_distance <= 0.001:
		return 0
	return maxi(1, floori(guide_distance / GUIDE_DOT_SPACING_PX) + 1)


func _effective_rotation_sign() -> int:
	if _has_authoritative_rotation_sign:
		return _required_rotation_sign
	if region_progress >= 1.0 or is_equal_approx(_start_value, _end_value):
		return 0
	var frequency_sign: int = 1 if _end_value > _start_value else -1
	var visual_mirror: int = -1 if affinity == GameplayTypes.Affinity.XUAN else 1
	var gesture_sign: int = frequency_sign * visual_mirror
	return gesture_sign if _current_traversal_index() % 2 == 0 else -gesture_sign


func _rotation_cue_angles() -> Vector2:
	var rotation_sign: int = _effective_rotation_sign()
	# 生槽位于上半屏，推荐手势沿摇杆上半弧；死槽位于下半屏，则沿下半弧。
	# 正号按 Godot 屏幕坐标从右向左经过下方（视觉顺时针），正好覆盖用户最直觉的
	# “下弧右端 -> 左端”动作；负号沿同一条弧反向返回。
	return TUNING_ARC_GEOMETRY.symmetric_directed_angles(
		affinity,
		rotation_sign,
		_gesture_sweep_rad(),
		_arc_rotation_rad
	)


func _gesture_sweep_rad() -> float:
	return _slider_sweep_rad


func _clear_endpoint_state() -> void:
	_endpoint_has_state = false
	_endpoint_target_progress = 1.0
	_endpoint_inside = false
	_endpoint_captured = false
	_endpoint_window_active = false
	_endpoint_grade = GameplayTypes.JudgmentGrade.MISS
	_endpoint_best_error_us = 0


func _turnaround_pulse() -> float:
	if _traversal_count <= 1 or _traversal_duration_sec <= 0.0:
		return 0.0
	var traversal_position: float = region_progress * float(_traversal_count)
	var nearest_boundary: int = roundi(traversal_position)
	if nearest_boundary <= 0 or nearest_boundary >= _traversal_count:
		return 0.0
	var distance_sec: float = (
		absf(traversal_position - float(nearest_boundary))
		* _traversal_duration_sec
	)
	return 1.0 - smoothstep(0.0, 0.12, distance_sec)


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
