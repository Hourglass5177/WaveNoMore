class_name GrayboxNoteVisual
extends Node2D

## 可由 StageVisualTheme 注入的 Tap 图片；为空时继续使用程序绘制。
@export var tap_texture: Texture2D
## Tap 使用的 ShaderMaterial；运行时由主题注入并复制，避免修改共享资源。
@export var tap_material: ShaderMaterial

const SOFT_GLOW = preload("res://src/presentation/vfx/note_soft_glow.gd")

@export_group("White Glow")
## 局部轮廓向外延伸的设计像素；中心纹理仍然保留。
@export_range(1.0, 64.0, 0.5) var glow_width_px: float = 30.0
@export_range(0.0, 1.5, 0.05) var glow_strength: float = 1.0
## 双押 Tap 在判定前开始亮起，按绝对视觉时间求值。
@export_range(0.01, 1.0, 0.01) var tap_glow_lead_sec: float = 0.60
@export_range(0.01, 0.5, 0.01) var tap_glow_rise_sec: float = 0.15
@export_range(0.01, 0.5, 0.01) var hold_glow_rise_sec: float = 0.10
@export_range(0.01, 0.5, 0.01) var glow_fall_sec: float = 0.08
var glow_amount: float = 0.0
var _glow_visual: MeshInstance2D
var _edge_glow_visual: MeshInstance2D
var _edge_glow_enabled: bool = true
var _edge_glow_color: Color = Color.WHITE
var _double_tap := false
var _glow_time := 0.0
var _glow_target := false
var _glow_from := 0.0
var _glow_change_time := 0.0

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
## Tap 命中印记固定在按键位置，本体继续飞行；接触波前后才进入死亡阶段。
const TAP_FEEDBACK_SEC := 0.12
const TAP_BODY_BRIGHTNESS := 0.45
var _is_tap := true
var _tap_hit_time := INF
var _tap_death_time := INF
var _tap_hit_transform := Transform2D.IDENTITY


func configure_edge_glow(enabled: bool, color: Color) -> void:
	## Host 在每次创建或对象池复用时调用；贴图 Shader 和灰盒轮廓共享配置语义。
	_edge_glow_enabled = enabled
	_edge_glow_color = color
	if tap_material != null:
		if _edge_glow_visual != null:
			_edge_glow_visual.visible = false
		tap_material.set_shader_parameter(&"glow_enabled", enabled)
		tap_material.set_shader_parameter(&"glow_color", color)
		return
	if _edge_glow_visual == null:
		_edge_glow_visual = SOFT_GLOW.new()
		_edge_glow_visual.name = "EdgeGlow"
		_edge_glow_visual.show_behind_parent = true
		_edge_glow_visual.z_index = -1
		add_child(_edge_glow_visual)
	_edge_glow_visual.configure_style(color, true)
	_edge_glow_visual.set_light(1.0 if enabled else 0.0, 12.0)


func prepare(view_model: Dictionary) -> void:
	_is_tap = StringName(view_model.get("unit_kind", &"tap")) == &"tap"
	_tap_hit_time = INF
	_tap_death_time = INF
	if _glow_visual == null:
		_glow_visual = SOFT_GLOW.new()
		_glow_visual.name = "WhiteGlow"
		add_child(_glow_visual)
	_double_tap = bool(view_model.get("double_tap", false)) and StringName(view_model.get("unit_kind", &"tap")) == &"tap"
	_reset_glow()
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
	if _tap_body_only():
		scale = Vector2.ONE
		queue_redraw()
		return
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
	# 成功 Tap 的计分通知不能重播命中印记；Hold 与 Miss 仍走原反馈流程。
	if _tap_body_only(): return
	if timing_confirmed and judgment_grade == grade:
		return
	timing_confirmed = true
	judgment_grade = grade
	if grade == GameplayTypes.JudgmentGrade.MISS and not missed:
		_glow_from = glow_amount
		_glow_change_time = _glow_time
		_glow_target = false
	missed = grade == GameplayTypes.JudgmentGrade.MISS
	if _tap_body_only():
		_tap_hit_time = _glow_time
		_tap_hit_transform = global_transform
		modulate = Color.WHITE
		scale = Vector2.ONE
		_set_glow_amount(0.0)
		queue_redraw()
		return
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
	if _is_tap and wave_contacted: return
	wave_contacted = true
	if _tap_body_only():
		_tap_death_time = float(_contact["contact_us"]) / 1000000.0
		_update_tap_feedback()
		return
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
	_tap_hit_time = INF
	_tap_death_time = INF
	_reset_glow()
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
	if _is_tap:
		_glow_time = _preview_clock
		_update_tap_feedback()
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
		var extent := Vector2(96.0, 96.0)
		if tap_material == null and _edge_glow_visual != null and _edge_glow_enabled:
			_edge_glow_visual.texture_shape(tap_texture, Rect2(-extent * 0.5, extent))
		draw_texture_rect(tap_texture, Rect2(-extent * 0.5, extent), false, Color.WHITE)
		return
	var base_color: Color = _affinity_color()
	if missed:
		base_color = Color("5c606a")
	elif _tap_body_only():
		base_color = base_color.darkened(1.0 - TAP_BODY_BRIGHTNESS)
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
	if _edge_glow_visual != null and _edge_glow_enabled:
		_edge_glow_visual.polygon(shape)
	if _glow_visual != null and _glow_visual.visible:
		_glow_visual.polygon(shape)
	var death_progress: float = clampf((_glow_time - _tap_death_time) / TAP_FEEDBACK_SEC, 0.0, 1.0)
	# 灰盒死亡先收束、消散；正式怪物可在 play_wave_contact 接口替换为死亡动画。
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * (1.0 - death_progress * 0.25))
	draw_colored_polygon(shape, Color(base_color, 0.88 * (1.0 - death_progress)))
	if not _tap_body_only():
		draw_polyline(PackedVector2Array([shape[0], shape[2], shape[4], shape[6], shape[8]]), Color("e5ddc8"), 3.0, true)
	for index: int in range(4):
		var offset: float = -24.0 + float(index) * 15.0
		draw_line(Vector2(offset, -27.0), Vector2(offset + 23.0, 30.0), Color(0.02, 0.02, 0.03, 0.36 * (1.0 - death_progress)), 2.0, true)
	draw_set_transform(Vector2.ZERO)

	if _tap_body_only():
		_draw_tap_hit()
	elif wave_contacted:
		draw_arc(Vector2.ZERO, 72.0, 0.0, TAU, 56, Color("fff8e8", 0.92), 6.0, true)
	elif note_arrived:
		draw_arc(Vector2.ZERO, 70.0, 0.0, TAU, 48, Color("8b8e96", 0.72), 5.0, true)


func set_note_glow_time(seconds: float, time_to_hit: float) -> void:
	_glow_time = seconds
	_update_tap_feedback()
	if _tap_body_only():
		_set_glow_amount(0.0)
	elif missed:
		_set_glow_amount(_glow_from * (1.0 - smoothstep(0.0, glow_fall_sec, seconds - _glow_change_time)))
	else:
		_set_glow_amount(smoothstep(0.0, tap_glow_rise_sec, tap_glow_lead_sec - time_to_hit) if _double_tap else 0.0)

func _tap_body_only() -> bool:
	return _is_tap and timing_confirmed and not missed

func _update_tap_feedback() -> void:
	if not _tap_body_only(): return
	visible = _glow_time < _tap_death_time + TAP_FEEDBACK_SEC
	queue_redraw()

func _draw_tap_hit() -> void:
	var age: float = _glow_time - _tap_hit_time
	if age < 0.0 or age >= TAP_FEEDBACK_SEC: return
	var progress: float = age / TAP_FEEDBACK_SEC
	var fade: float = pow(1.0 - progress, 2.0)
	# 逆变换抵消本体继续移动、旋转和缩放，印记始终留在按键被接受的位置。
	draw_set_transform_matrix(global_transform.affine_inverse() * _tap_hit_transform)
	draw_circle(Vector2.ZERO, 9.0 * (1.0 - progress), Color(1.0, 0.96, 0.85, fade * 0.8))
	for index: int in 4:
		var direction := Vector2.from_angle(PI * 0.25 + float(index) * PI * 0.5)
		var distance: float = lerpf(24.0, 54.0, progress)
		draw_line(direction * distance, direction * (distance + 15.0 * (1.0 - progress)), Color(1.0, 0.96, 0.85, fade), 3.0, true)
	draw_set_transform(Vector2.ZERO)


func set_tuning_glow(active: bool, seconds: float) -> void:
	## 同一时间重复快照不会推进过渡；转向从当前亮度开始，避免松开再接管时跳闪。
	_glow_time = seconds
	var duration: float = hold_glow_rise_sec if _glow_target else glow_fall_sec
	var value: float = lerpf(_glow_from, 1.0 if _glow_target else 0.0, smoothstep(0.0, duration, seconds - _glow_change_time))
	active = active and not missed
	if active != _glow_target:
		_glow_from = value
		_glow_change_time = seconds
		_glow_target = active
	_set_glow_amount(value)


func _set_glow_amount(value: float) -> void:
	glow_amount = value
	if _glow_visual != null: _glow_visual.set_light(value * glow_strength, glow_width_px)
	queue_redraw()


func _reset_glow() -> void:
	_glow_time = 0.0
	_glow_target = false
	_glow_from = 0.0
	_glow_change_time = 0.0
	_set_glow_amount(0.0)


func _affinity_color() -> Color:
	match affinity:
		GameplayTypes.Affinity.XUAN:
			return Color("7e879d")
		GameplayTypes.Affinity.SU:
			return Color("ddd4ba")
		_:
			return Color("ba3b31")
