class_name GrayboxNoteVisual
extends Node2D

## 可由 StageVisualTheme 注入的 Tap 图片；为空时继续使用程序绘制。
@export var tap_texture: Texture2D
## Tap 使用的 ShaderMaterial；运行时由主题注入并复制，避免修改共享资源。
@export var tap_material: ShaderMaterial

signal effect_requested(key: String, source: Dictionary, at_sec: float, direction: Vector2, kind: StringName)
const EFFECT_STYLE: NoteEffectStyle = preload("res://content/presentation/note_effect_style.tres")
const SURFACE_SHADER: Shader = preload("res://shaders/notes/note_surface.gdshader")
const AURA = preload("res://src/presentation/vfx/note_aura.gd")
var effect_style: NoteEffectStyle = EFFECT_STYLE
var _aura: MeshInstance2D
var _standalone_effects: NoteFragmentHost
var _finished_effect := false
var _last_surface_state := Vector3(INF, INF, INF)
const SOFT_GLOW = preload("res://src/presentation/vfx/note_soft_glow.gd")

# 时间参数取自共享设计资源；保留只读状态接口供表现测试使用。
var glow_width_px: float = 12.0
var glow_strength: float = 1.0
var tap_glow_lead_sec: float = 0.60
var tap_glow_rise_sec: float = 0.15
var hold_glow_rise_sec: float = 0.10
var glow_fall_sec: float = 0.08
var glow_amount: float = 0.0
var _glow_visual: MeshInstance2D
var _edge_glow_visual: MeshInstance2D
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
var _is_tap := true
var _tap_hit_time := INF
var _tap_death_time := INF
var _tap_hit_transform := Transform2D.IDENTITY


func configure_effect_style(style: NoteEffectStyle, side: int) -> void:
	## ArtLab、正式游戏和写谱器都从同一资源读取设计参数。
	effect_style = style
	affinity = side
	tap_glow_lead_sec = style.tap_lead_sec
	tap_glow_rise_sec = style.tap_rise_sec
	hold_glow_rise_sec = style.hold_rise_sec
	glow_fall_sec = style.fall_sec
	if tap_material == null:
		tap_material = ShaderMaterial.new()
		tap_material.shader = SURFACE_SHADER
	material = tap_material if tap_texture != null else null
	style.apply_to(tap_material, side)
	_last_surface_state = Vector3(INF, INF, INF)
	if _aura == null:
		_aura = AURA.new()
		_aura.name = "AffinityAura"
		add_child(_aura)
	_aura.configure(style, side)
	if _edge_glow_visual == null:
		_edge_glow_visual = SOFT_GLOW.new()
		_edge_glow_visual.show_behind_parent = true
		add_child(_edge_glow_visual)
	_edge_glow_visual.configure_style(style.rim(side), true)
	_edge_glow_visual.set_light(style.halo_strength, style.halo_width_px)
	if _glow_visual != null: _glow_visual.configure_style(style.white_color, false)
	_sync_effect_surface()

func _sync_effect_surface() -> void:
	var active := effect_style.enabled and not _tap_body_only() and not missed and not _finished_effect
	var surface_state := Vector3(glow_amount, 1.0 if active else 0.0, effect_style.accepted_brightness if _tap_body_only() else 1.0)
	if tap_material != null and surface_state != _last_surface_state:
		tap_material.set_shader_parameter(&"condition_light", glow_amount)
		tap_material.set_shader_parameter(&"aura_amount", surface_state.y)
		tap_material.set_shader_parameter(&"body_brightness", surface_state.z)
		_last_surface_state = surface_state
	if _aura != null: _aura.visible = active and tap_texture != null
	if _edge_glow_visual != null: _edge_glow_visual.visible = active and tap_texture == null
	if _standalone_effects != null: _standalone_effects.set_time(_glow_time)

func effect_snapshot() -> Dictionary:
	var result := {"transform": global_transform, "texture": tap_texture, "size": Vector2(96, 96), "affinity": affinity}
	if tap_material != null and tap_material.get_shader_parameter(&"eye_ball_texture") is Texture2D:
		result.eye = tap_material.get_shader_parameter(&"eye_ball_texture")
		result.mask = tap_material.get_shader_parameter(&"musk_texture")
		# 冻结触发时眼球偏移，碎片散开后眼球不再跨片移动。
		var screen := get_global_transform_with_canvas()
		var delta := get_viewport_rect().size * 0.5 - screen.origin
		var radius := float(tap_material.get_shader_parameter(&"eye_offset_px"))
		var falloff := float(tap_material.get_shader_parameter(&"eye_falloff_radius_px"))
		result.eye_offset = screen.basis_xform_inv(delta.normalized() * radius * smoothstep(0.0, falloff, delta.length())) / Vector2(96, 96)
	return result

func _emit_effect(suffix: String, at_sec: float, kind: StringName, direction := Vector2.RIGHT, source: Dictionary = {}) -> void:
	if source.is_empty(): source = effect_snapshot()
	if effect_requested.get_connections().is_empty():
		# 单独实例化的 ArtLab 素材也能预览；正式宿主会接管此信号。
		if _standalone_effects == null:
			_standalone_effects = NoteFragmentHost.new()
			_standalone_effects.top_level = true
			# 与本体并列，避免本体隐藏时连带隐藏仍在消散的碎片。
			get_parent().add_child(_standalone_effects)
		_standalone_effects.burst(event_id + suffix, source, at_sec, (source.transform as Transform2D).basis_xform_inv(direction), kind)
	else:
		effect_requested.emit(event_id + suffix, source, at_sec, direction, kind)

func _exit_tree() -> void:
	if is_instance_valid(_standalone_effects): _standalone_effects.queue_free()


func prepare(view_model: Dictionary) -> void:
	_finished_effect = false
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
	configure_effect_style(EFFECT_STYLE, affinity)
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
	_sync_effect_surface()
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
		_emit_effect(":hit", _glow_time, &"hit")
		_sync_effect_surface()
		queue_redraw()
		return
	if not missed: _emit_effect(":hit", _glow_time, &"hit")
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
		_emit_effect(":break", _tap_death_time, &"tap", _contact.get("effect_direction", Vector2.RIGHT))
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
	if _standalone_effects != null: _standalone_effects.clear()
	_finished_effect = false
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
	_glow_time = _preview_clock
	_update_tap_feedback()
	_sync_effect_surface()
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
		var rect := Rect2(Vector2(-48, -48), Vector2(96, 96))
		if _aura != null and effect_style.enabled and not _tap_body_only() and not missed:
			_aura.shape(tap_texture, rect)
		if _glow_visual != null: _glow_visual.visible = false
		draw_texture_rect(tap_texture, rect, false, Color.WHITE)
		return
	var base_color: Color = _affinity_color()
	if missed:
		base_color = Color("5c606a")
	elif _tap_body_only():
		base_color = base_color.darkened(1.0 - effect_style.accepted_brightness)
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
	if _edge_glow_visual != null and _edge_glow_visual.visible:
		_edge_glow_visual.polygon(shape)
	if _glow_visual != null and _glow_visual.visible:
		_glow_visual.polygon(shape)
	# 完整灰盒也由独立碎片替换，不在此继续播放第二套死亡动画。
	draw_colored_polygon(shape, Color(base_color, 0.88))
	if not _tap_body_only():
		draw_polyline(PackedVector2Array([shape[0], shape[2], shape[4], shape[6], shape[8]]), Color("e5ddc8"), 3.0, true)
	for index: int in range(4):
		var offset: float = -24.0 + float(index) * 15.0
		draw_line(Vector2(offset, -27.0), Vector2(offset + 23.0, 30.0), Color(0.02, 0.02, 0.03, 0.36), 2.0, true)
	draw_set_transform(Vector2.ZERO)

	if wave_contacted and not _tap_body_only():
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
	# 完整本体由独立碎片替换，音符生命周期仍由原调度器结束。
	visible = _glow_time < _tap_death_time
	queue_redraw()



func set_tuning_glow(active: bool, seconds: float) -> void:
	## 同一时间重复快照不会推进过渡；转向从当前亮度开始，避免松开再接管时跳闪。
	_glow_time = seconds
	if _finished_effect:
		_set_glow_amount(0.0)
		return
	var duration: float = hold_glow_rise_sec if _glow_target else glow_fall_sec
	var value: float = lerpf(_glow_from, 1.0 if _glow_target else 0.0, smoothstep(0.0, duration, seconds - _glow_change_time))
	active = active and not missed
	if active != _glow_target:
		_glow_from = value
		_glow_change_time = seconds
		_glow_target = active
	_set_glow_amount(value)


func _set_glow_amount(value: float) -> void:
	if not effect_style.enabled: value = 0.0
	glow_amount = value
	if _glow_visual != null: _glow_visual.set_light(value * glow_strength, glow_width_px)
	_sync_effect_surface()
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
			return effect_style.life_base
