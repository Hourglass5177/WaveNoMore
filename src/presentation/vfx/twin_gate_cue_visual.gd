class_name TwinGateCueVisual
extends Node2D

## 生死两路音符共用的中心视觉锚点。类名沿用旧版以兼容场景与主题资源；
## 判定、计分及波与音符的接触仍由玩法逻辑层负责。

# 生钟操作提示：手柄 R1、鼠标右键或 J。
const LIFE_INPUT_LABEL: String = "R1 / 右键 / J"
# 死钟操作提示：手柄 L1、鼠标左键或 F。
const DEATH_INPUT_LABEL: String = "L1 / 左键 / F"

@export_group("Scene Wiring")
## 生侧中心锚点 Marker2D 的路径；默认与死侧锚点完全重合。
@export var life_gate_anchor_path: NodePath = ^"LifeGateAnchor"
## 死侧中心锚点 Marker2D 的路径。
@export var death_gate_anchor_path: NodePath = ^"DeathGateAnchor"

@export_group("Geometry")
## 设计画布尺寸，单位为像素；用于中心对称和路线坐标换算。
@export var canvas_size: Vector2 = Vector2(1920.0, 1080.0)
## 生侧落点坐标，单位为像素；当前与 death_gate 同为画布正中心。
@export var life_gate: Vector2 = Vector2(960.0, 540.0)
## 死侧落点坐标，单位为像素；保持与 life_gate 重合可形成单一共同落点。
@export var death_gate: Vector2 = Vector2(960.0, 540.0)
## 生钟波源坐标，单位为像素，位于左上。
@export var life_origin: Vector2 = Vector2(350.0, 280.0)
## 死钟波源坐标，单位为像素，位于右下。
@export var death_origin: Vector2 = Vector2(1570.0, 800.0)
## 生音符生成点，单位为像素，位于右上画面外侧。
@export var life_spawn: Vector2 = Vector2(2040.0, 220.0)
## 死音符生成点，单位为像素，位于左下画面外侧。
@export var death_spawn: Vector2 = Vector2(-120.0, 860.0)
## 路线生成端的外弯量，单位为像素；越大则两侧外段弧度越明显。
@export_range(0.0, 600.0, 1.0) var curve_outer_bend_px: float = 220.0
## 路线靠近中心时的控制柄长度，单位为像素；越大则旋入中心的转弯越强。
@export_range(0.0, 800.0, 1.0) var curve_center_handle_px: float = 360.0
## 共同中心门半径，单位为像素；越大则落点标记占用范围越大。
@export_range(32.0, 100.0, 1.0) var gate_radius: float = 66.0
## 敲钟后中心发射印记的秒数；越大则扩散淡出更慢。
@export_range(0.05, 0.5, 0.01) var launch_pulse_duration_sec: float = 0.20
## 波碰到音符后中心接触印记的秒数；越大则骨白反馈保留更久。
@export_range(0.05, 0.5, 0.01) var contact_pulse_duration_sec: float = 0.18
## 判定符号显示的秒数；越大则 Perfect/Good/Pass/Miss 印记淡出更慢。
@export_range(0.05, 0.6, 0.01) var grade_duration_sec: float = 0.28
## 谱面双押完成后骨白合印显示的秒数；越大则合印保留更久。
@export_range(0.05, 0.6, 0.01) var bridge_duration_sec: float = 0.24

@export_group("Palette")
## 生侧路线、落点半环和有效发射印记的红色。
@export var life_color: Color = Color("ba3b31")
## 死侧路线、落点半环和有效发射印记的冷黑色。
@export var death_color: Color = Color("7e879d")
## 波接触、双押合印和中心细节使用的骨白色。
@export var bone_color: Color = Color("fff0cf")
## 中心门底色，用于压住复杂背景。
@export var ink_color: Color = Color("090b12")
## 无效敲击和 Miss 使用的灰色。
@export var invalid_color: Color = Color("7b7e87")

# 时钟和会话分别提供绝对视觉时间、发波、接触及判定事件。
var _clock: SongClock
# 当前关卡会话；用于读取判定事件和音符路径资料。
var _session: StageSession
# 当前统一视觉时间，单位秒；所有门与桥接动画都由此绝对时间计算。
var _visual_time_sec: float = 0.0
# 四组短暂事件各自保存开始时刻；绘制后按对应 duration 自动清理。
var _launch_events: Array[Dictionary] = []
# 尚在显示期内的波前接触事件，用于画落点接触反馈。
var _contact_events: Array[Dictionary] = []
# 尚在显示期内的判定等级事件，用于画 Perfect、Good、Miss 的门反馈。
var _grade_events: Array[Dictionary] = []
# 尚在显示期内的双界桥接事件，用于画穿过共同中心的连接效果。
var _bridge_events: Array[Dictionary] = []
# 双押的两侧判定可能分两次到达，按 group_id 暂存，齐全后才生成骨白合印。
var _pending_chord_sides: Dictionary[String, Dictionary] = {}
# Marker2D 让其他节点和美术场景可直接取得共同落点位置。
var _life_gate_anchor: Marker2D
# 死钟输入门的定位标记；与生钟门共同围绕中心落点布置。
var _death_gate_anchor: Marker2D
# 调频时降低中心门透明度；路径缓存避免相同几何配置重复采样。
var _tuning_active: bool = false
# 各路径编号对应的中心对称曲线路径资料。
var _path_profiles: Dictionary[int, Dictionary] = {}
# 各路径已排序的采样点键列表；缓存后供插值时快速查找相邻点。
var _path_profile_keys: Dictionary[int, Array] = {}


func _ready() -> void:
	_life_gate_anchor = get_node_or_null(life_gate_anchor_path) as Marker2D
	_death_gate_anchor = get_node_or_null(death_gate_anchor_path) as Marker2D
	_sync_markers()
	queue_redraw()


func configure_from_rules(rules: GameplayRuleSet) -> void:
	if rules == null:
		return
	canvas_size = rules.wave_canvas_size
	life_gate = rules.life_note_cue
	death_gate = rules.death_note_cue
	life_origin = rules.life_wave_origin
	death_origin = rules.death_wave_origin
	life_spawn = rules.life_note_spawn
	death_spawn = rules.death_note_spawn
	curve_outer_bend_px = rules.note_curve_outer_bend_px
	curve_center_handle_px = rules.note_curve_center_handle_px
	_path_profiles.clear()
	_path_profile_keys.clear()
	_sync_markers()
	queue_redraw()


func configure_palette(
		p_life_color: Color,
		p_death_color: Color,
		p_bone_color: Color,
		p_ink_color: Color
) -> void:
	life_color = p_life_color
	death_color = p_death_color
	bone_color = p_bone_color
	ink_color = p_ink_color
	queue_redraw()


func bind(clock: SongClock, session: StageSession) -> void:
	_disconnect_sources()
	clear()
	_clock = clock
	_session = session
	if is_instance_valid(_clock) and not _clock.sample_published.is_connected(_on_clock_sample):
		_clock.sample_published.connect(_on_clock_sample)
	if not is_instance_valid(_session):
		return
	if not _session.wave_launched.is_connected(_on_wave_launched):
		_session.wave_launched.connect(_on_wave_launched)
	if not _session.wave_contacted.is_connected(_on_wave_contacted):
		_session.wave_contacted.connect(_on_wave_contacted)
	if not _session.judgment_presented.is_connected(_on_judgment_presented):
		_session.judgment_presented.connect(_on_judgment_presented)
	if not _session.waves_reset.is_connected(clear):
		_session.waves_reset.connect(clear)


func clear() -> void:
	_launch_events.clear()
	_contact_events.clear()
	_grade_events.clear()
	_bridge_events.clear()
	_pending_chord_sides.clear()
	_tuning_active = false
	modulate = Color.WHITE
	queue_redraw()


func set_tuning_active(active: bool) -> void:
	if _tuning_active == active:
		return
	_tuning_active = active
	# 调频时由上下粗滑条承担主要引导，中心门只保留低透明提示，避免与游标和相纹争抢视线。
	modulate = Color(1.0, 1.0, 1.0, 0.22 if _tuning_active else 1.0)
	queue_redraw()


func debug_snapshot() -> Dictionary:
	return {
		"visual_time_sec": _visual_time_sec,
		"life_gate": life_gate,
		"death_gate": death_gate,
		"shared_gate": (life_gate + death_gate) * 0.5,
		"life_input_label": LIFE_INPUT_LABEL,
		"death_input_label": DEATH_INPUT_LABEL,
		"launch_count": _launch_events.size(),
		"contact_count": _contact_events.size(),
		"grade_count": _grade_events.size(),
		"fusion_count": _bridge_events.size(),
		"bridge_count": _bridge_events.size(), # Deprecated diagnostic alias.
		"pending_group_count": _pending_chord_sides.size(),
	}


func _exit_tree() -> void:
	_disconnect_sources()


func _on_clock_sample(sample: ClockSample) -> void:
	if sample.visual_time_sec + 0.000001 < _visual_time_sec:
		# 向后跳转时清掉旧的短暂特效，避免工具预览残留跳转前的画面。
		clear()
	_visual_time_sec = sample.visual_time_sec
	_prune_transients()
	queue_redraw()


func _on_wave_launched(wave: Dictionary) -> void:
	var affinity: int = int(wave.get("affinity", GameplayTypes.Affinity.SU))
	if affinity not in [GameplayTypes.Affinity.ZHU, GameplayTypes.Affinity.XUAN]:
		return
	_launch_events.append({
		"affinity": affinity,
		"valid": bool(wave.get("valid", false)),
		"start_sec": _timeline_us_to_visual_sec(int(wave.get("launch_us", 0))),
	})
	_trim_event_buffer(_launch_events)
	queue_redraw()


func _on_wave_contacted(contact: Dictionary) -> void:
	var affinity: int = int(contact.get("affinity", GameplayTypes.Affinity.SU))
	if affinity not in [GameplayTypes.Affinity.ZHU, GameplayTypes.Affinity.XUAN]:
		return
	_contact_events.append({
		"affinity": affinity,
		"start_sec": _timeline_us_to_visual_sec(int(contact.get("contact_us", 0))),
	})
	_trim_event_buffer(_contact_events)
	queue_redraw()


func _on_judgment_presented(record: JudgmentRecord) -> void:
	if record == null:
		return
	if record.unit_kind not in [&"tap", &"hold"]:
		return
	# 最终表现可以晚于按键：成功等真实波前接触，Miss 等未阻挡音符抵达钟。
	var start_sec: float = _visual_time_sec
	_grade_events.append({
		"affinity": record.affinity,
		"grade": record.grade,
		"start_sec": start_sec,
	})
	_trim_event_buffer(_grade_events)

	# 骨白合印只表示谱面写明的双押，不把两次普通快速输入误认成双押，疾振也因此保持独立读法。
	if not record.group_id.is_empty() and record.grade != GameplayTypes.JudgmentGrade.MISS:
		var sides: Dictionary = _pending_chord_sides.get(record.group_id, {})
		sides[record.affinity] = start_sec
		_pending_chord_sides[record.group_id] = sides
		if sides.has(GameplayTypes.Affinity.ZHU) and sides.has(GameplayTypes.Affinity.XUAN):
			_bridge_events.append({
				"group_id": record.group_id,
				"start_sec": maxf(
					float(sides[GameplayTypes.Affinity.ZHU]),
					float(sides[GameplayTypes.Affinity.XUAN])
				),
			})
			_pending_chord_sides.erase(record.group_id)
			_trim_event_buffer(_bridge_events)
	queue_redraw()


func _draw() -> void:
	_draw_route_scaffold()
	_draw_shared_gate((life_gate + death_gate) * 0.5)
	_draw_bridges()
	_draw_launch_pulses()
	_draw_contact_pulses()
	_draw_grade_seals()


func _draw_route_scaffold() -> void:
	# 与 NoteVisualHost 采样同一条弧长路径；这里仅作低调路线提示，不是第二条判定线。
	var life_profile: Dictionary = _path_profile_for_affinity(GameplayTypes.Affinity.ZHU)
	var death_profile: Dictionary = _path_profile_for_affinity(GameplayTypes.Affinity.XUAN)
	_draw_curve_scaffold(life_profile, life_color)
	_draw_curve_scaffold(death_profile, death_color)
	_draw_dashed_tether(life_gate, life_origin, Color(life_color.lightened(0.28), 0.15))
	_draw_dashed_tether(death_gate, death_origin, Color(bone_color, 0.13))
	_draw_incoming_chevrons(life_profile, life_color)
	_draw_incoming_chevrons(death_profile, death_color)


func _draw_shared_gate(center: Vector2) -> void:
	draw_circle(center, gate_radius + 6.0, Color(ink_color, 0.30))
	draw_arc(center, gate_radius + 6.0, 0.0, TAU, 64, Color(bone_color, 0.20), 2.0, true)
	# 两段半环在同一中心相接，但生、死按键职责仍然分开。
	draw_arc(center, gate_radius, -PI * 0.75, PI * 0.25, 40, Color(life_color, 0.72), 6.0, true)
	draw_arc(center, gate_radius, PI * 0.25, PI * 1.25, 40, Color(death_color, 0.78), 6.0, true)
	draw_arc(center, gate_radius - 10.0, 0.0, TAU, 64, Color(bone_color, 0.22), 2.0, true)
	var split_axis := Vector2(1.0, -1.0).normalized()
	var split_normal := Vector2(-split_axis.y, split_axis.x)
	for side: float in [-1.0, 1.0]:
		var notch_center: Vector2 = center + split_axis * gate_radius * side
		draw_line(notch_center - split_normal * 9.0, notch_center + split_normal * 9.0, Color(bone_color, 0.72), 3.0, true)
	draw_circle(center + Vector2(10.0, -10.0), 7.0, Color(life_color.lightened(0.30), 0.90))
	draw_circle(center + Vector2(-10.0, 10.0), 7.0, Color(death_color.lightened(0.30), 0.92))
	draw_circle(center, 3.0, Color(bone_color, 0.92))
	draw_string(
		ThemeDB.fallback_font,
		center + Vector2(82.0, -68.0),
		LIFE_INPUT_LABEL,
		HORIZONTAL_ALIGNMENT_CENTER,
		84.0,
		15,
		Color(life_color.lightened(0.32), 0.92)
	)
	draw_string(
		ThemeDB.fallback_font,
		center + Vector2(-166.0, 82.0),
		DEATH_INPUT_LABEL,
		HORIZONTAL_ALIGNMENT_CENTER,
		88.0,
		15,
		Color(bone_color, 0.90)
	)


func _draw_curve_scaffold(profile: Dictionary, color: Color) -> void:
	var points: PackedVector2Array = profile.get("samples", PackedVector2Array())
	if points.size() < 2:
		return
	draw_polyline(points, Color(color, 0.13), 3.0, true)


func _draw_incoming_chevrons(profile: Dictionary, color: Color) -> void:
	for ratio: float in [0.70, 0.82, 0.92]:
		var center: Vector2 = NoteApproachPath.point_at_ratio(profile, ratio)
		var tangent: Vector2 = NoteApproachPath.tangent_at_ratio(profile, ratio)
		var normal := Vector2(-tangent.y, tangent.x)
		var tip: Vector2 = center + tangent * 10.0
		draw_line(center - tangent * 8.0 - normal * 8.0, tip, Color(color, 0.24), 2.0, true)
		draw_line(center - tangent * 8.0 + normal * 8.0, tip, Color(color, 0.24), 2.0, true)


func _draw_dashed_tether(from: Vector2, to: Vector2, color: Color) -> void:
	var segment_count: int = 18
	for index: int in range(segment_count):
		if index % 2 != 0:
			continue
		var start_ratio: float = float(index) / float(segment_count)
		var end_ratio: float = float(index + 1) / float(segment_count)
		draw_line(from.lerp(to, start_ratio), from.lerp(to, end_ratio), color, 2.0, true)


func _draw_launch_pulses() -> void:
	var duration: float = maxf(launch_pulse_duration_sec, 0.001)
	for event: Dictionary in _launch_events:
		var age: float = _visual_time_sec - float(event["start_sec"])
		if age < 0.0 or age > duration:
			continue
		var progress: float = clampf(age / duration, 0.0, 1.0)
		var eased: float = 1.0 - pow(1.0 - progress, 3.0)
		var affinity: int = int(event["affinity"])
		var center: Vector2 = death_gate if affinity == GameplayTypes.Affinity.XUAN else life_gate
		var color: Color = _affinity_color(affinity) if bool(event["valid"]) else invalid_color
		var radius: float = gate_radius + lerpf(4.0, 46.0, eased)
		draw_arc(center, radius, 0.0, TAU, 64, Color(color, pow(1.0 - progress, 1.4) * 0.78), lerpf(8.0, 2.0, eased), true)


func _draw_contact_pulses() -> void:
	var duration: float = maxf(contact_pulse_duration_sec, 0.001)
	for event: Dictionary in _contact_events:
		var age: float = _visual_time_sec - float(event["start_sec"])
		if age < 0.0 or age > duration:
			continue
		var progress: float = clampf(age / duration, 0.0, 1.0)
		var eased: float = 1.0 - pow(1.0 - progress, 3.0)
		var center: Vector2 = death_gate if int(event["affinity"]) == GameplayTypes.Affinity.XUAN else life_gate
		var radius: float = lerpf(gate_radius * 0.42, gate_radius * 1.22, eased)
		draw_circle(center, lerpf(17.0, 4.0, eased), Color(bone_color, pow(1.0 - progress, 1.8) * 0.64))
		draw_arc(center, radius, 0.0, TAU, 56, Color(bone_color, pow(1.0 - progress, 1.3)), 5.0, true)


func _draw_grade_seals() -> void:
	var duration: float = maxf(grade_duration_sec, 0.001)
	for event: Dictionary in _grade_events:
		var age: float = _visual_time_sec - float(event["start_sec"])
		if age < 0.0 or age > duration:
			continue
		var progress: float = clampf(age / duration, 0.0, 1.0)
		var alpha: float = pow(1.0 - progress, 1.5)
		var centers: Array[Vector2] = _centers_for_affinity(int(event["affinity"]))
		for center: Vector2 in centers:
			_draw_grade_seal(center, int(event["grade"]), alpha)


func _draw_grade_seal(center: Vector2, grade: int, alpha: float) -> void:
	if grade == GameplayTypes.JudgmentGrade.MISS:
		var extent: float = gate_radius * 0.34
		draw_line(center - Vector2.ONE * extent, center + Vector2.ONE * extent, Color(invalid_color, alpha), 6.0, true)
		draw_line(center + Vector2(-extent, extent), center + Vector2(extent, -extent), Color(invalid_color, alpha), 6.0, true)
		return
	var arc_count: int = 1
	match grade:
		GameplayTypes.JudgmentGrade.PERFECT:
			arc_count = 3
		GameplayTypes.JudgmentGrade.GOOD:
			arc_count = 2
		GameplayTypes.JudgmentGrade.PASS:
			arc_count = 1
	for index: int in range(arc_count):
		var radius: float = gate_radius - 18.0 - float(index) * 9.0
		draw_arc(center, radius, -PI * 0.85, PI * 0.35, 32, Color(bone_color, alpha * (0.92 - float(index) * 0.14)), 4.0, true)


func _draw_bridges() -> void:
	var duration: float = maxf(bridge_duration_sec, 0.001)
	var center: Vector2 = (life_gate + death_gate) * 0.5
	for event: Dictionary in _bridge_events:
		var age: float = _visual_time_sec - float(event["start_sec"])
		if age < 0.0 or age > duration:
			continue
		var progress: float = clampf(age / duration, 0.0, 1.0)
		var alpha: float = pow(1.0 - progress, 1.35)
		# 两个锚点重合后，双押以短暂骨白“合印”表示，不再画一条长度为零的桥。
		draw_circle(center, lerpf(18.0, 5.0, progress), Color(bone_color, alpha * 0.92))
		for index: int in range(3):
			var radius: float = lerpf(28.0 + float(index) * 8.0, 58.0 + float(index) * 12.0, progress)
			var phase: float = float(index) * PI / 3.0 + progress * 0.45
			draw_arc(center, radius, phase, phase + PI * 0.72, 26, Color(bone_color, alpha * (0.70 - float(index) * 0.12)), 3.5, true)
			draw_arc(center, radius, phase + PI, phase + PI * 1.72, 26, Color(bone_color, alpha * (0.70 - float(index) * 0.12)), 3.5, true)


func _centers_for_affinity(affinity: int) -> Array[Vector2]:
	if affinity == GameplayTypes.Affinity.ZHU:
		return [life_gate]
	if affinity == GameplayTypes.Affinity.XUAN:
		return [death_gate]
	if life_gate.is_equal_approx(death_gate):
		return [life_gate]
	return [life_gate, death_gate]


func _affinity_color(affinity: int) -> Color:
	return death_color if affinity == GameplayTypes.Affinity.XUAN else life_color


func _prune_transients() -> void:
	_prune_events(_launch_events, launch_pulse_duration_sec)
	_prune_events(_contact_events, contact_pulse_duration_sec)
	_prune_events(_grade_events, grade_duration_sec)
	_prune_events(_bridge_events, bridge_duration_sec)
	var stale_groups: Array[String] = []
	for group_id: String in _pending_chord_sides.keys():
		var sides: Dictionary = _pending_chord_sides[group_id]
		var newest: float = -INF
		for side_time: Variant in sides.values():
			newest = maxf(newest, float(side_time))
		if _visual_time_sec - newest > 1.0:
			stale_groups.append(group_id)
	for group_id: String in stale_groups:
		_pending_chord_sides.erase(group_id)


func _prune_events(events: Array[Dictionary], duration_sec: float) -> void:
	for index: int in range(events.size() - 1, -1, -1):
		if _visual_time_sec - float(events[index]["start_sec"]) > duration_sec:
			events.remove_at(index)


func _trim_event_buffer(events: Array[Dictionary]) -> void:
	while events.size() > 16:
		events.pop_front()


func _sync_markers() -> void:
	if is_instance_valid(_life_gate_anchor):
		_life_gate_anchor.position = life_gate
	if is_instance_valid(_death_gate_anchor):
		_death_gate_anchor.position = death_gate


func _path_profile_for_affinity(affinity: int) -> Dictionary:
	var spawn: Vector2 = death_spawn if affinity == GameplayTypes.Affinity.XUAN else life_spawn
	var target: Vector2 = death_gate if affinity == GameplayTypes.Affinity.XUAN else life_gate
	var origin: Vector2 = death_origin if affinity == GameplayTypes.Affinity.XUAN else life_origin
	var cache_key: Array = [spawn, target, origin, curve_outer_bend_px, curve_center_handle_px]
	if not _path_profile_keys.has(affinity) or _path_profile_keys[affinity] != cache_key:
		_path_profiles[affinity] = NoteApproachPath.build_profile(
			spawn,
			target,
			origin,
			curve_outer_bend_px,
			curve_center_handle_px
		)
		_path_profile_keys[affinity] = cache_key
	return _path_profiles[affinity]


func _timeline_us_to_visual_sec(timestamp_us: int) -> float:
	return float(timestamp_us) / 1_000_000.0 + _visual_timeline_offset_sec()


func _visual_timeline_offset_sec() -> float:
	if not is_instance_valid(_clock):
		return 0.0
	return _clock.input_compensation_sec + _clock.visual_lead_sec


func _disconnect_sources() -> void:
	if is_instance_valid(_clock) and _clock.sample_published.is_connected(_on_clock_sample):
		_clock.sample_published.disconnect(_on_clock_sample)
	if is_instance_valid(_session):
		if _session.wave_launched.is_connected(_on_wave_launched):
			_session.wave_launched.disconnect(_on_wave_launched)
		if _session.wave_contacted.is_connected(_on_wave_contacted):
			_session.wave_contacted.disconnect(_on_wave_contacted)
		if _session.judgment_presented.is_connected(_on_judgment_presented):
			_session.judgment_presented.disconnect(_on_judgment_presented)
		if _session.waves_reset.is_connected(clear):
			_session.waves_reset.disconnect(clear)
	_clock = null
	_session = null
