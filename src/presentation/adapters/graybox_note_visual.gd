class_name GrayboxNoteVisual
extends Node2D

## 可由 StageVisualTheme 注入的 Tap 图片；为空时继续使用程序绘制。
@export var tap_texture: Texture2D
## Tap 使用的 ShaderMaterial；运行时由主题注入并复制，避免修改共享资源。
@export var tap_material: ShaderMaterial

## 普通音符的程序绘制占位实现，用于验证旋入路径、时机确认、波接触和抵达钟的不同反馈。

# 谱面稳定 ID 用于查找和回收同一个视觉节点；affinity 决定生、死或素的颜色。
var event_id: String = ""
# 音符所属阵营；生音符使用红色语义，死音符使用黑色语义，素音使用白色语义。
var affinity: int = GameplayTypes.Affinity.ZHU
# approach/hold/proximity 均为 0～1 的显示进度，分别表示接近、持续消耗和贴近目标。
var approach_progress: float = 0.0
# Hold 已完成的比例；0 是头部刚命中，1 是持续段完整结束。
var hold_progress: float = 0.0
# 调频游标与目标的接近程度；0 表示很远，1 表示吻合。
var target_proximity: float = 0.0
# -1 表示尚未判定；其余布尔值区分按键确认、波接触和最终撞钟三个不同瞬间。
var judgment_grade: int = -1
# 音符是否已经漏掉；漏掉后切换为失败视觉。
var missed: bool = false
# 是否已有实体波前碰到音符；只有接触不能单独算作命中。
var wave_contacted: bool = false
# 波前接触时机是否落在判定窗内；需与接触状态共同确认命中。
var timing_confirmed: bool = false
# 音符是否已经到达共同中心落点；用于区分接近阶段和越过落点后的状态。
var note_arrived: bool = false

# 三条 Tween 分开保存，新的同类反馈到来时先停止旧动画，避免属性互相争抢。
var _feedback_tween: Tween
# 波前接触反馈当前使用的补间动画；重播反馈前会先停止旧动画。
var _wave_contact_tween: Tween
# 判定结果反馈当前使用的补间动画；避免连续结果互相叠加。
var _timing_tween: Tween
var preview_time_driven := false
var _preview_clock := -INF


func prepare(view_model: Dictionary) -> void:
	event_id = str(view_model.get("event_id", view_model.get("id", view_model.get("unit_id", ""))))
	affinity = int(view_model.get("affinity", GameplayTypes.Affinity.ZHU))
	approach_progress = 0.0
	hold_progress = 0.0
	target_proximity = 0.0
	judgment_grade = -1
	missed = false
	wave_contacted = false
	timing_confirmed = false
	note_arrived = false
	visible = true
	modulate = Color.WHITE
	scale = Vector2.ONE
	queue_redraw()


func set_approach_progress(value: float) -> void:
	approach_progress = clampf(value, 0.0, 1.0)
	var breath: float = sin(approach_progress * PI * 3.0) * 0.045
	scale = Vector2.ONE * (0.72 + approach_progress * 0.28 + breath)
	queue_redraw()


func set_hold_progress(value: float) -> void:
	hold_progress = clampf(value, 0.0, 1.0)
	queue_redraw()


func set_target_proximity(value: float) -> void:
	target_proximity = clampf(value, 0.0, 1.0)
	queue_redraw()


func play_judgment(grade: int) -> void:
	if timing_confirmed and judgment_grade == grade:
		return
	play_timing_confirmed(grade)


func play_timing_confirmed(grade: int) -> void:
	if timing_confirmed and judgment_grade == grade:
		return
	timing_confirmed = true
	judgment_grade = grade
	missed = grade == GameplayTypes.JudgmentGrade.MISS
	if _timing_tween != null:
		_timing_tween.kill()
	modulate = Color("a7a9af") if missed else Color("fff3cf")
	_timing_tween = _new_feedback_tween()
	_timing_tween.set_trans(Tween.TRANS_QUAD)
	_timing_tween.set_ease(Tween.EASE_OUT)
	_timing_tween.tween_property(self, "modulate", Color.WHITE, 0.16)
	_play_feedback()
	queue_redraw()


func play_miss() -> void:
	play_judgment(GameplayTypes.JudgmentGrade.MISS)


func play_wave_contact(_contact: Dictionary) -> void:
	wave_contacted = true
	if _wave_contact_tween != null:
		_wave_contact_tween.kill()
	modulate = Color("fff2cc")
	_wave_contact_tween = _new_feedback_tween()
	_wave_contact_tween.set_trans(Tween.TRANS_QUAD)
	_wave_contact_tween.set_ease(Tween.EASE_OUT)
	_wave_contact_tween.tween_property(self, "modulate", Color.WHITE, 0.18)
	if preview_time_driven: _wave_contact_tween.custom_step(maxf(0, _preview_clock - float(_contact.get("contact_us", 0)) / 1000000.0))
	queue_redraw()


func play_note_arrival(_arrival: Dictionary) -> void:
	# Miss 判定另有且只有一次表现；这里仅强调未被阻挡的音符真正撞到钟的物理时刻。
	note_arrived = true
	if _wave_contact_tween != null:
		_wave_contact_tween.kill()
	modulate = Color("777a83")
	_wave_contact_tween = _new_feedback_tween()
	_wave_contact_tween.set_trans(Tween.TRANS_QUAD)
	_wave_contact_tween.set_ease(Tween.EASE_OUT)
	_wave_contact_tween.tween_property(self, "modulate", Color.WHITE, 0.16)
	if preview_time_driven: _wave_contact_tween.custom_step(maxf(0, _preview_clock - float(_arrival.get("arrival_us", 0)) / 1000000.0))
	queue_redraw()


func reset_for_pool() -> void:
	if _feedback_tween != null:
		_feedback_tween.kill()
	if _wave_contact_tween != null:
		_wave_contact_tween.kill()
	if _timing_tween != null:
		_timing_tween.kill()
	_feedback_tween = null
	_wave_contact_tween = null
	_timing_tween = null
	visible = false
	position = Vector2.ZERO
	rotation = 0.0
	scale = Vector2.ONE
	modulate = Color.WHITE
	_preview_clock = -INF

func set_preview_time(seconds: float) -> void:
	preview_time_driven = true
	var elapsed := maxf(0, seconds - _preview_clock) if is_finite(_preview_clock) else 0.0
	_preview_clock = maxf(_preview_clock, seconds)
	for tween in [_feedback_tween, _wave_contact_tween, _timing_tween]:
		if tween != null and tween.is_valid(): tween.custom_step(elapsed)

func _new_feedback_tween() -> Tween:
	var tween := create_tween()
	if preview_time_driven: tween.pause()
	return tween


func _play_feedback() -> void:
	if _feedback_tween != null:
		_feedback_tween.kill()
	var impact_scale: Vector2 = Vector2(1.35, 0.72) if not missed else Vector2(0.82, 1.16)
	scale *= impact_scale
	_feedback_tween = _new_feedback_tween()
	_feedback_tween.set_trans(Tween.TRANS_BACK)
	_feedback_tween.set_ease(Tween.EASE_OUT)
	_feedback_tween.tween_property(self, "scale", Vector2.ONE, 0.16)


func _draw() -> void:
	if tap_texture != null:
		var size := tap_texture.get_size()
		var extent := Vector2(96.0, 96.0)
		draw_texture_rect(tap_texture, Rect2(-extent * 0.5, extent), false, Color.WHITE)
		return
	var base_color: Color = _affinity_color()
	if missed:
		base_color = Color("5c606a")
	elif judgment_grade == GameplayTypes.JudgmentGrade.PERFECT:
		base_color = base_color.lightened(0.35)

	var pulse: float = 1.0 + target_proximity * 0.18
	var shape := PackedVector2Array([
		Vector2(-52.0, -9.0) * pulse,
		Vector2(-25.0, -45.0) * pulse,
		Vector2(9.0, -33.0) * pulse,
		Vector2(46.0, -56.0) * pulse,
		Vector2(34.0, -3.0) * pulse,
		Vector2(57.0, 28.0) * pulse,
		Vector2(12.0, 22.0) * pulse,
		Vector2(-17.0, 51.0) * pulse,
		Vector2(-31.0, 16.0) * pulse,
	])
	draw_colored_polygon(shape, Color(base_color, 0.88))
	draw_polyline(PackedVector2Array([shape[0], shape[2], shape[4], shape[6], shape[8]]), Color("e5ddc8"), 3.0, true)
	for index: int in range(4):
		var offset: float = -24.0 + float(index) * 15.0
		draw_line(Vector2(offset, -27.0), Vector2(offset + 23.0, 30.0), Color(0.02, 0.02, 0.03, 0.36), 2.0, true)

	# 按键时先锁定精度，实际消灭仍等待波前接触；小印记用来区分这两个时刻。
	if timing_confirmed and not missed and not wave_contacted:
		draw_arc(Vector2.ZERO, 64.0, 0.0, TAU, 48, Color("fff0cf", 0.74), 3.0, true)
		for angle: float in [0.0, PI * 0.5, PI, PI * 1.5]:
			var direction := Vector2.from_angle(angle)
			draw_line(direction * 57.0, direction * 69.0, Color("fff0cf", 0.82), 3.0, true)
	if wave_contacted:
		draw_arc(Vector2.ZERO, 72.0, 0.0, TAU, 56, Color("fff8e8", 0.92), 6.0, true)
	elif note_arrived:
		draw_arc(Vector2.ZERO, 70.0, 0.0, TAU, 48, Color("8b8e96", 0.72), 5.0, true)


func _affinity_color() -> Color:
	match affinity:
		GameplayTypes.Affinity.XUAN:
			return Color("7e879d")
		GameplayTypes.Affinity.SU:
			return Color("ddd4ba")
		_:
			return Color("ba3b31")
