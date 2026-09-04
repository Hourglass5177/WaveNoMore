class_name TimingRingVisual
extends Node2D

## 音符外围的圆形倒计时。进度由 NoteVisualHost 按绝对视觉时间写入，
## 本节点既不自行累计时间，也不参与判定。

@export_group("Geometry")
## 普通音符倒计时环半径，单位为像素；数值越大，圆环离音符主体越远。
@export_range(24.0, 160.0, 1.0) var note_radius: float = 66.0
## 调频或疾振提示环半径，单位为像素；当前 Host 不为这两类事件创建通用圆环。
@export_range(24.0, 200.0, 1.0) var field_radius: float = 96.0
## 固定轨道和亮弧的线宽，单位为像素；数值越大越醒目。
@export_range(1.0, 16.0, 0.5) var track_width: float = 6.0
## 进场外圈相对固定轨道多出的半径，单位为像素；数值越大，收束运动越明显。
@export_range(0.0, 80.0, 1.0) var outer_approach_offset: float = 30.0
## 目标时刻过后仍允许圆环停留的秒数；数值越大，迟到反馈保留越久。
@export_range(0.0, 0.5, 0.01) var post_hit_linger_sec: float = 0.22

@export_group("Palette")
## 生音符圆环颜色，对应手柄 R1、右键或 J。
@export var life_color: Color = Color("fff0cf")
## 死音符圆环颜色，对应手柄 L1、左键或 F。
@export var death_color: Color = Color("d8e1ff")
## 生死共同事件的圆环颜色，使用骨白以区别单侧红黑提示。
@export var shared_color: Color = Color("fff8e8")
## 未填充轨道底色；透明度越高，背景上的圆环底轨越明显。
@export var track_color: Color = Color(0.03, 0.035, 0.05, 0.72)

# 当前事件身份：event_id 用于对象池配对，affinity 决定颜色，timing_kind 决定半径。
var event_id: String = ""
# 判定环所属阵营；决定使用生、死或素音的颜色语义。
var affinity: int = GameplayTypes.Affinity.SU
# 判定环提示的目标类型，例如普通音符或 Hold 尾部。
var timing_kind: StringName = &"note"

# 计时状态全部由 Host 写入。进度为 0～1，剩余时间和接近时长单位为秒。
var _progress: float = 0.0
# 距离目标判定时刻的秒数；正值尚未到达，0 表示正好卡点。
var _time_to_hit_sec: float = INF
# 进度环从出现到卡点的总秒数，用于把剩余时间换算成圆环比例。
var _approach_duration_sec: float = 1.0
# sustain_mode 表示 Hold 头已命中，此后圆环只展示剩余持续进度。
var _sustain_mode: bool = false
# 判定状态控制最终颜色和淡出；radius_offset 用像素错开同时出现的生死 Hold 环。
var _judged: bool = false
# 当前目标是否已经 Miss；为 true 时进度环切换失败颜色。
var _missed: bool = false
# 相对基础半径的像素偏移；正值把环向外扩，负值向内缩。
var _radius_offset: float = 0.0
# 保存当前反馈 Tween，节点回收到对象池时必须先停止它。
var _feedback_tween: Tween


func prepare(view_model: Dictionary) -> void:
	event_id = str(view_model.get("event_id", view_model.get("id", view_model.get("unit_id", ""))))
	affinity = int(view_model.get("affinity", GameplayTypes.Affinity.SU))
	timing_kind = StringName(view_model.get("_timing_kind", &"note"))
	_progress = 0.0
	_time_to_hit_sec = INF
	_approach_duration_sec = 1.0
	_sustain_mode = false
	_judged = false
	_missed = false
	_radius_offset = 0.0
	if _feedback_tween != null:
		_feedback_tween.kill()
	_feedback_tween = null
	visible = true
	modulate = Color.WHITE
	scale = Vector2.ONE
	queue_redraw()


func set_timing(time_to_hit_sec: float, approach_duration_sec: float) -> void:
	_time_to_hit_sec = time_to_hit_sec
	_approach_duration_sec = maxf(approach_duration_sec, 0.001)
	_sustain_mode = false
	# 每次都从 SongClock 给出的绝对视觉时间重算，不累计 delta；暂停、跳转、重试和帧率变化都不会令圆环漂移。
	_progress = clampf(1.0 - _time_to_hit_sec / _approach_duration_sec, 0.0, 1.0)
	if not _judged:
		visible = _time_to_hit_sec <= _approach_duration_sec and _time_to_hit_sec >= -post_hit_linger_sec
	queue_redraw()


func set_sustain_progress(region_progress: float) -> void:
	# Hold 头命中后，圆环改为尾段引导，并按谱面区间的绝对进度重新从 0 填到 1。
	_sustain_mode = true
	_progress = clampf(region_progress, 0.0, 1.0)
	if not _judged:
		visible = true
	queue_redraw()


func set_radius_offset(value: float) -> void:
	_radius_offset = value
	queue_redraw()


func play_judgment(grade: int) -> void:
	_judged = true
	_missed = grade == GameplayTypes.JudgmentGrade.MISS
	visible = true
	_progress = 1.0
	if _feedback_tween != null:
		_feedback_tween.kill()
	modulate = Color.WHITE
	scale = Vector2(1.10, 1.10) if _missed else Vector2(0.88, 0.88)
	_feedback_tween = create_tween()
	_feedback_tween.set_parallel(true)
	_feedback_tween.tween_property(self, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_feedback_tween.tween_property(self, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_feedback_tween.chain().tween_callback(func() -> void: visible = false)
	queue_redraw()


func play_miss() -> void:
	play_judgment(GameplayTypes.JudgmentGrade.MISS)


func reset_for_pool() -> void:
	if _feedback_tween != null:
		_feedback_tween.kill()
	_feedback_tween = null
	event_id = ""
	_progress = 0.0
	_time_to_hit_sec = INF
	_sustain_mode = false
	_judged = false
	_missed = false
	_radius_offset = 0.0
	visible = false
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE
	modulate = Color.WHITE


func _draw() -> void:
	var radius: float = field_radius if timing_kind == &"tuning" or timing_kind == &"rapid" else note_radius + _radius_offset
	var color: Color = _ring_color()
	if _missed:
		color = Color("8f929b")

	# 外圈在目标时刻收束到固定轨道，亮弧则从十二点方向顺时针填满。
	var outer_radius: float = radius + outer_approach_offset * (1.0 - _progress)
	draw_arc(Vector2.ZERO, outer_radius, 0.0, TAU, 72, Color(color, 0.18 + _progress * 0.12), 2.0, true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 72, track_color, track_width + 3.0, true)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 72, Color(color, 0.24), track_width, true)
	if _progress > 0.0001:
		var start_angle: float = -PI * 0.5
		var end_angle: float = start_angle + TAU * _progress
		var point_count: int = maxi(4, ceili(72.0 * _progress))
		draw_arc(Vector2.ZERO, radius, start_angle, end_angle, point_count, color, track_width, true)
		var leading_point := Vector2(cos(end_angle), sin(end_angle)) * radius
		draw_circle(leading_point, track_width * 0.62, color, true, -1.0, true)

	# 固定的十二点标记给出明确起点和闭合点，繁杂背景下也能看清。
	var top := Vector2(0.0, -radius)
	draw_circle(top, track_width * 0.72, Color("fff5d8"), true, -1.0, true)
	var marker := PackedVector2Array([
		Vector2(-6.0, -radius - 17.0),
		Vector2(6.0, -radius - 17.0),
		Vector2(0.0, -radius - 7.0),
	])
	draw_colored_polygon(marker, Color("fff5d8"))

	if _progress >= 0.999:
		draw_arc(Vector2.ZERO, radius - track_width * 1.35, 0.0, TAU, 72, Color(color.lightened(0.28), 0.62), 2.0, true)
	if _missed:
		var cross_extent: float = radius * 0.34
		draw_line(Vector2(-cross_extent, -cross_extent), Vector2(cross_extent, cross_extent), Color("d3d0c8"), 5.0, true)
		draw_line(Vector2(cross_extent, -cross_extent), Vector2(-cross_extent, cross_extent), Color("d3d0c8"), 5.0, true)


func _ring_color() -> Color:
	if timing_kind == &"tuning" or timing_kind == &"rapid":
		return shared_color
	match affinity:
		GameplayTypes.Affinity.ZHU:
			return life_color
		GameplayTypes.Affinity.XUAN:
			return death_color
		_:
			return shared_color
