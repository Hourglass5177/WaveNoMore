class_name TuningInterferenceVisual
extends ColorRect

## 生、死双钟的持续载波与相纹表现。
## 每条波前只保存发射时刻，半径始终由“绝对时间差 × 固定波速”重建；
## 改变频率只会改变未来波前的发射间隔，绝不会拉伸或加速已经发出的波。

const FIELD_SHADER: Shader = preload("res://shaders/fields/interference_ink.gdshader")
const SU_OVERLAY_SCRIPT: Script = preload("res://src/presentation/vfx/su_manifestation_overlay.gd")
# 必须与 interference_ink.gdshader 中的固定数组长度一致。
const MAX_SHADER_WAVEFRONTS := 16
# 领域历史上限高于 Shader 上限；素音候选始终读取完整物理历史。
const MAX_PHYSICAL_WAVEFRONTS := 64
const PHASE_EPSILON := 0.0000001
# 与调频领域层一致，只吸收浮点换算误差，不把越过滑条端点的进度钳回合法范围。
const TRACKING_EPSILON := 0.001

@export_group("Field Geometry")
## 全屏相纹画布尺寸。
@export var canvas_size: Vector2 = Vector2(1920.0, 1080.0)
## 生钟位于左上，死钟位于右下，二者关于画面中心对称。
@export var life_source: Vector2 = Vector2(350.0, 280.0)
@export var death_source: Vector2 = Vector2(1570.0, 800.0)
## 所有波前共用的固定传播速度，单位为像素/秒。
@export_range(100.0, 4000.0, 1.0) var wave_speed_px_sec: float = 2400.0

@export_group("Source Frequency")
## 普通段按住钟时使用的统一基准频率。
@export_range(0.1, 20.0, 0.05) var base_frequency_hz: float = 3.0
## 调频段两端对应的频率范围。
@export_range(0.1, 20.0, 0.1) var min_frequency_hz: float = 1.0
@export_range(0.1, 20.0, 0.1) var max_frequency_hz: float = 7.0
## 相纹视觉强度。只调节明度和辉光，绝不能通过丢弃整圈波前来降密度。
@export_range(0.35, 1.0, 0.05) var visual_intensity: float = 0.85
## 单条可见波带的半宽。
@export_range(2.0, 80.0, 0.5) var band_half_width_px: float = 30.0

@export_group("Appearance")
@export var life_color: Color = Color("bd3328")
@export var death_color: Color = Color("677087")
@export var overlap_color: Color = Color("fff1d1")
@export_range(0.0, 1.5, 0.001) var field_strength: float = 1.02
@export_range(0.0, 1.0, 0.001) var overlap_threshold: float = 0.055
@export_range(3.0, 20.0, 0.5) var stipple_cell_px: float = 7.0
@export_range(0.0, 2.0, 0.01) var glow_strength: float = 1.20
## 游标处于有效引导带时，对应钟波带的宽度倍率；只增强表现，不改变物理接触范围。
@export_range(1.0, 1.8, 0.01) var aligned_band_scale: float = 1.22
## 游标处于有效引导带时，对应钟波前的亮度倍率。
@export_range(1.0, 1.8, 0.01) var aligned_brightness_scale: float = 1.24

@export_group("Su Manifestation")
## 素音候选点与两口钟保持的最小距离，避免凝现在角色和钟体内部。
@export_range(0.0, 320.0, 1.0) var su_source_clearance_px: float = 118.0
## 同一事件多个素音候选点之间的默认最小间距。
@export_range(0.0, 320.0, 1.0) var su_candidate_spacing_px: float = 96.0

# 当前 ShaderMaterial 必须为实例私有，避免多个关卡互相覆盖 uniform。
var _shader_material: ShaderMaterial
# 子节点负责画素音凝现，避免全屏相纹 Shader 改写其颜色。
var _su_overlay: Node2D

# SongClock 的绝对视觉时间与运行代次。
var _visual_time_sec: float = 0.0
var _previous_visual_time_sec: float = -INF
var _clock_generation: int = -1
# 正式运行时由 GameplaySnapshot 提供权威载波历史；独立视觉预览才使用本地发射回退。
var _using_authoritative_fronts: bool = false

# 当前是否位于允许调频的谱面区间；它只决定频率是否可偏离基准，不决定能否发波。
var _tuning_field_active: bool = false
var _active_field_id: String = ""
# 两口钟各自的按住、频率和归一化调频位置。
var _life_emitting: bool = false
var _death_emitting: bool = false
var _life_frequency_hz: float = 3.0
var _death_frequency_hz: float = 3.0
var _life_tuning_value: float = 0.5
var _death_tuning_value: float = 0.5
# 当前两侧游标是否贴合各自可见引导带；只驱动画面强调。
var _life_guide_aligned: bool = false
var _death_guide_aligned: bool = false
# 相纹的贴合强调使用与滑条一致的短缓动，避免判定带边缘让整屏波纹瞬间闪烁。
var _life_alignment_strength: float = 0.0
var _death_alignment_strength: float = 0.0

# 每侧独立保存相位推进时刻与未满一周期的余量。
var _life_phase_time_sec: float = 0.0
var _death_phase_time_sec: float = 0.0
var _life_phase_cycles: float = 0.0
var _death_phase_cycles: float = 0.0
# 最近一次开始和停止发波时刻只供调试，不参与传播计算。
var _life_emission_start_sec: float = 0.0
var _death_emission_start_sec: float = 0.0
var _life_emission_stop_sec: float = 0.0
var _death_emission_stop_sec: float = 0.0

# 完整物理历史：时间戳决定半径，递增序号用于稳定显示抽样和候选排序。
var _life_wavefront_times: Array[float] = []
var _death_wavefront_times: Array[float] = []
var _life_wavefront_serials: Array[int] = []
var _death_wavefront_serials: Array[int] = []
var _life_total_emitted: int = 0
var _death_total_emitted: int = 0
var _capacity_warning_emitted: bool = false
# 已经播放过的素音事件，防止后续快照重复重启动画。
var _presented_su_ids: Dictionary[String, bool] = {}
var _prepared_su_ids: Dictionary[String, bool] = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	_ensure_material()
	_ensure_su_overlay()
	_apply_canvas_size()
	_push_configuration()
	_validate_wavefront_capacity()
	clear()


func _process(delta: float) -> void:
	var previous_life: float = _life_alignment_strength
	var previous_death: float = _death_alignment_strength
	_life_alignment_strength = _approach_alignment_strength(
		_life_alignment_strength,
		1.0 if _life_guide_aligned else 0.0,
		delta
	)
	_death_alignment_strength = _approach_alignment_strength(
		_death_alignment_strength,
		1.0 if _death_guide_aligned else 0.0,
		delta
	)
	if (
		not is_equal_approx(previous_life, _life_alignment_strength)
		or not is_equal_approx(previous_death, _death_alignment_strength)
	):
		_push_runtime_state()


func configure_from_rules(rules: GameplayRuleSet) -> void:
	if rules == null:
		return
	canvas_size = rules.wave_canvas_size
	life_source = rules.life_wave_origin
	death_source = rules.death_wave_origin
	wave_speed_px_sec = rules.wave_speed_px_sec
	base_frequency_hz = _optional_rule_float(rules, &"tuning_base_frequency_hz", base_frequency_hz)
	min_frequency_hz = _optional_rule_float(rules, &"tuning_min_frequency_hz", min_frequency_hz)
	max_frequency_hz = _optional_rule_float(rules, &"tuning_max_frequency_hz", max_frequency_hz)
	_life_frequency_hz = base_frequency_hz
	_death_frequency_hz = base_frequency_hz
	_apply_canvas_size()
	_push_configuration()
	_validate_wavefront_capacity()


func configure_palette(p_life_color: Color, p_death_color: Color, p_overlap_color: Color) -> void:
	life_color = p_life_color.lightened(0.10)
	# 死界本身接近黑色，持续波需保留玄色倾向同时抬高亮度。
	death_color = p_death_color.lerp(Color("a8b0c2"), 0.62)
	overlap_color = p_overlap_color
	if is_instance_valid(_su_overlay):
		_su_overlay.set("bone_color", overlap_color)
		_su_overlay.set("canvas_size", canvas_size)
	_push_configuration()


func set_visual_intensity(value: float) -> void:
	visual_intensity = clampf(value, 0.35, 1.0)
	_push_configuration()


func set_visual_time(value: float) -> void:
	if is_finite(_previous_visual_time_sec) and value < _previous_visual_time_sec - 0.001:
		_reset_emission()
	if not _using_authoritative_fronts and value > _visual_time_sec:
		_advance_emission_to(value)
	_visual_time_sec = value
	_previous_visual_time_sec = value
	_prune_finished_wavefronts()
	_push_runtime_state()


func set_clock_sample(sample: ClockSample) -> void:
	if sample == null:
		return
	# generation 改变表示开始、重试或 Seek；不能在新时间线保留旧波前。
	if _clock_generation >= 0 and sample.generation != _clock_generation:
		_reset_emission()
	_clock_generation = sample.generation
	set_visual_time(sample.visual_time_sec)


func set_gameplay_snapshot(snapshot: Dictionary) -> void:
	var has_authoritative_fronts: bool = snapshot.has("carrier_wavefronts")
	# 独立视觉预览没有领域波前时，才在本地按旧频率推进；正式玩法不维护第二套历史。
	if not has_authoritative_fronts:
		_advance_emission_to(_visual_time_sec)

	_tuning_field_active = bool(snapshot.get(
		"tuning_field_active",
		false
	))
	_active_field_id = str(snapshot.get("active_tuning_field_id", ""))
	_life_tuning_value = _snapshot_tuning_value(snapshot, true)
	_death_tuning_value = _snapshot_tuning_value(snapshot, false)
	_life_frequency_hz = _snapshot_frequency(snapshot, true, _life_tuning_value)
	_death_frequency_hz = _snapshot_frequency(snapshot, false, _death_tuning_value)

	var next_life_emitting: bool = bool(snapshot.get("life_held", false))
	var next_death_emitting: bool = bool(snapshot.get("death_held", false))
	_life_guide_aligned = _side_is_guide_aligned(snapshot, GameplayTypes.Affinity.ZHU)
	_death_guide_aligned = _side_is_guide_aligned(snapshot, GameplayTypes.Affinity.XUAN)
	if has_authoritative_fronts:
		_using_authoritative_fronts = true
		_life_emitting = next_life_emitting
		_death_emitting = next_death_emitting
		_consume_authoritative_wavefronts(snapshot.get("carrier_wavefronts", []))
	else:
		_using_authoritative_fronts = false
		_update_source_emission(true, next_life_emitting)
		_update_source_emission(false, next_death_emitting)
	_consume_su_manifestations(snapshot)
	_prune_finished_wavefronts()
	_push_runtime_state()


func clear() -> void:
	_visual_time_sec = 0.0
	_previous_visual_time_sec = -INF
	_clock_generation = -1
	_using_authoritative_fronts = false
	_tuning_field_active = false
	_active_field_id = ""
	_life_tuning_value = 0.5
	_death_tuning_value = 0.5
	_life_frequency_hz = base_frequency_hz
	_death_frequency_hz = base_frequency_hz
	_life_guide_aligned = false
	_death_guide_aligned = false
	_life_alignment_strength = 0.0
	_death_alignment_strength = 0.0
	_presented_su_ids.clear()
	_reset_emission()
	if is_instance_valid(_su_overlay):
		_su_overlay.call("clear")
	_push_runtime_state()


func resolve_su_candidate_points(
	spawn_region_normalized: Rect2,
	requested_count: int = 1,
	minimum_spacing_px: float = -1.0,
	exclusion_rects: Array = []
) -> PackedVector2Array:
	## 从当前真实波前的圆—圆交点中选择确定性候选，不制造不存在的白纹。
	var safe_count: int = maxi(requested_count, 0)
	if safe_count == 0:
		return PackedVector2Array()
	var normalized_region: Rect2 = spawn_region_normalized.intersection(Rect2(Vector2.ZERO, Vector2.ONE))
	if normalized_region.size.x <= 0.0 or normalized_region.size.y <= 0.0:
		return PackedVector2Array()
	var pixel_region := Rect2(
		normalized_region.position * canvas_size,
		normalized_region.size * canvas_size
	)
	var candidates: Array[Dictionary] = []

	for life_index: int in range(_life_wavefront_times.size()):
		var life_radius: float = _wavefront_radius(_life_wavefront_times[life_index])
		if life_radius <= 0.0 or life_radius > _max_visible_radius():
			continue
		for death_index: int in range(_death_wavefront_times.size()):
			var death_radius: float = _wavefront_radius(_death_wavefront_times[death_index])
			if death_radius <= 0.0 or death_radius > _max_visible_radius():
				continue
			var intersections: PackedVector2Array = _circle_intersections(
				life_source,
				life_radius,
				death_source,
				death_radius
			)
			for raw_point: Vector2 in intersections:
				var point := Vector2(
					roundf(raw_point.x * 100.0) / 100.0,
					roundf(raw_point.y * 100.0) / 100.0
				)
				if not pixel_region.has_point(point):
					continue
				if point.distance_to(life_source) < su_source_clearance_px:
					continue
				if point.distance_to(death_source) < su_source_clearance_px:
					continue
				if _point_inside_any_rect(point, exclusion_rects):
					continue
				candidates.append({
					"point": point,
					"center_distance_q": roundi(point.distance_squared_to(pixel_region.get_center()) * 100.0),
					"life_serial": _life_wavefront_serials[life_index],
					"death_serial": _death_wavefront_serials[death_index],
				})

	candidates.sort_custom(_candidate_less)
	var spacing: float = su_candidate_spacing_px if minimum_spacing_px < 0.0 else maxf(minimum_spacing_px, 0.0)
	var selected := PackedVector2Array()
	for candidate: Dictionary in candidates:
		var point: Vector2 = candidate["point"]
		if _too_close_to_selected(point, selected, spacing):
			continue
		selected.append(point)
		if selected.size() >= safe_count:
			break
	return selected


func debug_snapshot() -> Dictionary:
	var life_display_times: Array[float] = _display_wavefront_times(_life_wavefront_times)
	var death_display_times: Array[float] = _display_wavefront_times(_death_wavefront_times)
	return {
		"field_enabled": _has_visible_wavefronts(),
		"visible": visible,
		"emitting": _life_emitting or _death_emitting,
		"life_emitting": _life_emitting,
		"death_emitting": _death_emitting,
		"clock_generation": _clock_generation,
		"tuning_field_active": _tuning_field_active,
		"active_field_id": _active_field_id,
		"emission_age_sec": _combined_emission_age_sec(),
		"emission_duration_sec": _combined_emission_duration_sec(),
		"life_tuning_value": _life_tuning_value,
		"death_tuning_value": _death_tuning_value,
		"visual_intensity": visual_intensity,
		"life_frequency_hz": _life_frequency_hz,
		"death_frequency_hz": _death_frequency_hz,
		"life_guide_aligned": _life_guide_aligned,
		"death_guide_aligned": _death_guide_aligned,
		"life_alignment_strength": _life_alignment_strength,
		"death_alignment_strength": _death_alignment_strength,
		"life_wavelength_px": wave_speed_px_sec / maxf(_life_frequency_hz, 0.001),
		"death_wavelength_px": wave_speed_px_sec / maxf(_death_frequency_hz, 0.001),
		"wave_speed_px_sec": wave_speed_px_sec,
		"source_separation_px": life_source.distance_to(death_source),
		"life_wavefront_count": _life_wavefront_times.size(),
		"death_wavefront_count": _death_wavefront_times.size(),
		"life_display_wavefront_count": life_display_times.size(),
		"death_display_wavefront_count": death_display_times.size(),
		"life_total_emitted": _life_total_emitted,
		"death_total_emitted": _death_total_emitted,
		"required_wavefront_capacity": _required_wavefront_capacity(),
		"wavefront_capacity": MAX_PHYSICAL_WAVEFRONTS,
		"shader_wavefront_capacity": MAX_SHADER_WAVEFRONTS,
		"life_phase_cycles": _life_phase_cycles,
		"death_phase_cycles": _death_phase_cycles,
		"life_wavefronts": _debug_wavefronts(_life_wavefront_times, _life_wavefront_serials),
		"death_wavefronts": _debug_wavefronts(_death_wavefront_times, _death_wavefront_serials),
		"su_overlay": _su_overlay.call("debug_snapshot") if is_instance_valid(_su_overlay) else {},
	}


func _snapshot_tuning_value(snapshot: Dictionary, life: bool) -> float:
	var key: String = "life_tuning_value" if life else "death_tuning_value"
	if snapshot.has(key):
		return clampf(float(snapshot[key]), 0.0, 1.0)
	return 0.5


func _snapshot_frequency(snapshot: Dictionary, life: bool, tuning_value: float) -> float:
	if not _tuning_field_active:
		return base_frequency_hz
	var key: String = "life_frequency_hz" if life else "death_frequency_hz"
	if snapshot.has(key):
		return clampf(float(snapshot[key]), 0.1, 30.0)
	return lerpf(min_frequency_hz, max_frequency_hz, clampf(tuning_value, 0.0, 1.0))


func _side_is_guide_aligned(snapshot: Dictionary, affinity: int) -> bool:
	if not _tuning_field_active:
		return false
	var raw_sliders: Variant = snapshot.get("active_tuning_sliders", [])
	var states: Array = []
	if raw_sliders is Array:
		states = raw_sliders as Array
	elif raw_sliders is Dictionary:
		states = (raw_sliders as Dictionary).values()
	for value: Variant in states:
		if value is not Dictionary:
			continue
		var state: Dictionary = value
		if int(state.get("affinity", GameplayTypes.Affinity.SU)) != affinity:
			continue
		if not bool(state.get("held", false)):
			continue
		var player_progress: float = float(state.get("player_progress", 0.0))
		var band_min: float = clampf(float(state.get("guide_band_min", 0.0)), 0.0, 1.0)
		var band_max: float = clampf(float(state.get("guide_band_max", 0.0)), 0.0, 1.0)
		if (
			player_progress >= minf(band_min, band_max) - TRACKING_EPSILON
			and player_progress <= maxf(band_min, band_max) + TRACKING_EPSILON
		):
			return true
	return false


func _consume_authoritative_wavefronts(value: Variant) -> void:
	_life_wavefront_times.clear()
	_death_wavefront_times.clear()
	_life_wavefront_serials.clear()
	_death_wavefront_serials.clear()
	if value is not Array:
		return
	var fronts: Array[Dictionary] = []
	for entry: Variant in value:
		if entry is Dictionary:
			fronts.append((entry as Dictionary).duplicate(true))
	fronts.sort_custom(_authoritative_front_less)

	for front: Dictionary in fronts:
		var affinity: int = int(front.get("affinity", GameplayTypes.Affinity.SU))
		if affinity not in [GameplayTypes.Affinity.ZHU, GameplayTypes.Affinity.XUAN]:
			continue
		var front_speed: float = maxf(float(front.get("speed_px_sec", wave_speed_px_sec)), 0.001)
		var radius_px: float = maxf(float(front.get("radius_px", 0.0)), 0.0)
		# radius_px 已由领域层用权威微秒时间计算。反推视觉发射时刻可保留当前半径，
		# 后续 ClockSample 只按固定速度继续扩散，不需要知道输入补偿的内部细节。
		var effective_emission_sec: float = _visual_time_sec - radius_px / front_speed
		var serial: int = _serial_from_wave_id(str(front.get("wave_id", front.get("id", ""))))
		if affinity == GameplayTypes.Affinity.ZHU:
			_life_wavefront_times.append(effective_emission_sec)
			_life_wavefront_serials.append(serial)
			_life_total_emitted = maxi(_life_total_emitted, serial + 1)
		else:
			_death_wavefront_times.append(effective_emission_sec)
			_death_wavefront_serials.append(serial)
			_death_total_emitted = maxi(_death_total_emitted, serial + 1)


func _consume_su_manifestations(snapshot: Dictionary) -> void:
	## 准备与结算分别去重，先创建后结算；UV 直到 Overlay 绘制才转成像素。
	_ensure_su_overlay()
	var judge_time_sec: float = float(snapshot.get("time_us", 0)) / 1_000_000.0
	_su_overlay.set("canvas_size", canvas_size)
	_su_overlay.call("set_visual_time", judge_time_sec)
	for target: Dictionary in snapshot.get("su_prepared_targets", []):
		var event_id: String = str(target["event_id"])
		if _prepared_su_ids.has(event_id):
			continue
		_prepared_su_ids[event_id] = true
		_su_overlay.call("prepare_targets", target)
	for result: Dictionary in snapshot.get("su_manifestations", []):
		var event_id: String = str(result["event_id"])
		if _presented_su_ids.has(event_id):
			continue
		_presented_su_ids[event_id] = true
		_su_overlay.call("resolve_targets", result)
	# 新建的终结条目也使用绝对时间过期，不靠固定帧延迟筛选。
	_su_overlay.call("set_visual_time", judge_time_sec)


func _authoritative_front_less(left: Dictionary, right: Dictionary) -> bool:
	var left_launch: int = int(left.get("launch_us", 0))
	var right_launch: int = int(right.get("launch_us", 0))
	if left_launch != right_launch:
		return left_launch < right_launch
	return str(left.get("wave_id", left.get("id", ""))) < str(right.get("wave_id", right.get("id", "")))


func _serial_from_wave_id(wave_id: String) -> int:
	var parts: PackedStringArray = wave_id.split(":")
	if parts.size() >= 2 and parts[1].is_valid_int():
		return parts[1].to_int()
	# 非标准 ID 仍通过稳定字符串哈希得到非负抽样序号。
	return absi(hash(wave_id))


func _update_source_emission(life: bool, should_emit: bool) -> void:
	var was_emitting: bool = _life_emitting if life else _death_emitting
	if should_emit == was_emitting:
		return
	if should_emit:
		_begin_source_emission(life)
	else:
		_end_source_emission(life)


func _begin_source_emission(life: bool) -> void:
	if life:
		_life_emitting = true
		_life_emission_start_sec = _visual_time_sec
		_life_phase_time_sec = _visual_time_sec
		_life_phase_cycles = 0.0
		_append_wavefront(true, _visual_time_sec)
	else:
		_death_emitting = true
		_death_emission_start_sec = _visual_time_sec
		_death_phase_time_sec = _visual_time_sec
		_death_phase_cycles = 0.0
		_append_wavefront(false, _visual_time_sec)


func _end_source_emission(life: bool) -> void:
	_advance_one_source_to(life, _visual_time_sec)
	if life:
		_life_emitting = false
		_life_emission_stop_sec = _visual_time_sec
	else:
		_death_emitting = false
		_death_emission_stop_sec = _visual_time_sec


func _reset_emission() -> void:
	_presented_su_ids.clear()
	_prepared_su_ids.clear()
	_life_emitting = false
	_death_emitting = false
	_life_phase_time_sec = _visual_time_sec
	_death_phase_time_sec = _visual_time_sec
	_life_phase_cycles = 0.0
	_death_phase_cycles = 0.0
	_life_emission_start_sec = _visual_time_sec
	_death_emission_start_sec = _visual_time_sec
	_life_emission_stop_sec = _visual_time_sec
	_death_emission_stop_sec = _visual_time_sec
	_life_wavefront_times.clear()
	_death_wavefront_times.clear()
	_life_wavefront_serials.clear()
	_death_wavefront_serials.clear()
	_life_total_emitted = 0
	_death_total_emitted = 0
	if is_instance_valid(_su_overlay):
		_su_overlay.call("clear")


func _advance_emission_to(target_visual_sec: float) -> void:
	_advance_one_source_to(true, target_visual_sec)
	_advance_one_source_to(false, target_visual_sec)


func _advance_one_source_to(life: bool, target_visual_sec: float) -> void:
	var emitting: bool = _life_emitting if life else _death_emitting
	var from_visual_sec: float = _life_phase_time_sec if life else _death_phase_time_sec
	if not emitting or target_visual_sec <= from_visual_sec:
		return
	var initial_phase: float = _life_phase_cycles if life else _death_phase_cycles
	var frequency_hz: float = _life_frequency_hz if life else _death_frequency_hz
	var next_phase: float = _advance_source_phase(
		life,
		initial_phase,
		frequency_hz,
		from_visual_sec,
		target_visual_sec
	)
	if life:
		_life_phase_cycles = next_phase
		_life_phase_time_sec = target_visual_sec
	else:
		_death_phase_cycles = next_phase
		_death_phase_time_sec = target_visual_sec


func _advance_source_phase(
	life: bool,
	initial_phase: float,
	frequency_hz: float,
	from_visual_sec: float,
	to_visual_sec: float
) -> float:
	var safe_frequency: float = maxf(frequency_hz, 0.001)
	var elapsed_sec: float = maxf(to_visual_sec - from_visual_sec, 0.0)
	var accumulated_cycles: float = initial_phase + elapsed_sec * safe_frequency
	var crossing_count: int = floori(accumulated_cycles + PHASE_EPSILON)
	for crossing_index: int in range(crossing_count):
		var cycles_until_crossing: float = float(crossing_index + 1) - initial_phase
		var emitted_at_sec: float = from_visual_sec + cycles_until_crossing / safe_frequency
		_append_wavefront(life, emitted_at_sec)
	var remaining_phase: float = accumulated_cycles - float(crossing_count)
	if remaining_phase < PHASE_EPSILON or remaining_phase > 1.0 - PHASE_EPSILON:
		return 0.0
	return clampf(remaining_phase, 0.0, 1.0 - PHASE_EPSILON)


func _append_wavefront(life: bool, emitted_at_sec: float) -> void:
	var times: Array[float] = _life_wavefront_times if life else _death_wavefront_times
	var serials: Array[int] = _life_wavefront_serials if life else _death_wavefront_serials
	var serial: int = _life_total_emitted if life else _death_total_emitted
	times.append(emitted_at_sec)
	serials.append(serial)
	if life:
		_life_total_emitted += 1
	else:
		_death_total_emitted += 1
	while times.size() > MAX_PHYSICAL_WAVEFRONTS:
		times.pop_front()
		serials.pop_front()


func _prune_finished_wavefronts() -> void:
	_prune_source_wavefronts(_life_wavefront_times, _life_wavefront_serials)
	_prune_source_wavefronts(_death_wavefront_times, _death_wavefront_serials)


func _prune_source_wavefronts(wavefront_times: Array[float], serials: Array[int]) -> void:
	var max_radius: float = _max_visible_radius()
	while not wavefront_times.is_empty():
		var age_sec: float = _visual_time_sec - wavefront_times[0]
		if age_sec < 0.0 or age_sec * wave_speed_px_sec <= max_radius:
			break
		wavefront_times.pop_front()
		serials.pop_front()


func _has_visible_wavefronts() -> bool:
	return not _life_wavefront_times.is_empty() or not _death_wavefront_times.is_empty()


func _display_wavefront_times(times: Array[float]) -> Array[float]:
	# 当前规则下每侧同时可见的波前少于 Shader 容量。即使以后超过容量，也只截取
	# 最近的固定上限，绝不能再依据生死共用序号成段抽掉某一侧的波。
	var result: Array[float] = times.duplicate()
	while result.size() > MAX_SHADER_WAVEFRONTS:
		result.pop_front()
	return result


func _required_wavefront_capacity() -> int:
	var maximum_travel_sec: float = _max_visible_radius() / maxf(wave_speed_px_sec, 0.001)
	return ceili(max_frequency_hz * maximum_travel_sec) + 2


func _validate_wavefront_capacity() -> void:
	var required_capacity: int = _required_wavefront_capacity()
	if required_capacity <= MAX_PHYSICAL_WAVEFRONTS or _capacity_warning_emitted:
		return
	_capacity_warning_emitted = true
	push_warning(
		"TuningInterferenceVisual needs %d physical fronts, but history capacity is %d." % [
			required_capacity,
			MAX_PHYSICAL_WAVEFRONTS,
		]
	)


func _combined_emission_age_sec() -> float:
	var starts: Array[float] = []
	if _life_emitting:
		starts.append(_life_emission_start_sec)
	if _death_emitting:
		starts.append(_death_emission_start_sec)
	if starts.is_empty():
		return 0.0
	return maxf(_visual_time_sec - starts.min(), 0.0)


func _combined_emission_duration_sec() -> float:
	var life_duration: float = (
		maxf(_visual_time_sec - _life_emission_start_sec, 0.0)
		if _life_emitting
		else maxf(_life_emission_stop_sec - _life_emission_start_sec, 0.0)
	)
	var death_duration: float = (
		maxf(_visual_time_sec - _death_emission_start_sec, 0.0)
		if _death_emitting
		else maxf(_death_emission_stop_sec - _death_emission_start_sec, 0.0)
	)
	return maxf(life_duration, death_duration)


func _debug_wavefronts(times: Array[float], serials: Array[int]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index: int in range(mini(times.size(), serials.size())):
		var emitted_at_sec: float = times[index]
		var age_sec: float = maxf(_visual_time_sec - emitted_at_sec, 0.0)
		result.append({
			"serial": serials[index],
			"emitted_at_sec": emitted_at_sec,
			"age_sec": age_sec,
			"radius_px": age_sec * wave_speed_px_sec,
		})
	return result


func _wavefront_radius(emitted_at_sec: float) -> float:
	return maxf(_visual_time_sec - emitted_at_sec, 0.0) * wave_speed_px_sec


func _circle_intersections(
	first_center: Vector2,
	first_radius: float,
	second_center: Vector2,
	second_radius: float
) -> PackedVector2Array:
	var result := PackedVector2Array()
	var center_delta: Vector2 = second_center - first_center
	var distance: float = center_delta.length()
	if distance <= 0.00001:
		return result
	if distance > first_radius + second_radius + 0.001:
		return result
	if distance < absf(first_radius - second_radius) - 0.001:
		return result

	var along_distance: float = (
		first_radius * first_radius
		- second_radius * second_radius
		+ distance * distance
	) / (2.0 * distance)
	var height_squared: float = first_radius * first_radius - along_distance * along_distance
	if height_squared < -0.01:
		return result
	var direction: Vector2 = center_delta / distance
	var midpoint: Vector2 = first_center + direction * along_distance
	var height: float = sqrt(maxf(height_squared, 0.0))
	var perpendicular := Vector2(-direction.y, direction.x)
	result.append(midpoint + perpendicular * height)
	if height > 0.01:
		result.append(midpoint - perpendicular * height)
	return result


func _candidate_less(left: Dictionary, right: Dictionary) -> bool:
	var left_distance: int = int(left.get("center_distance_q", 0))
	var right_distance: int = int(right.get("center_distance_q", 0))
	if left_distance != right_distance:
		return left_distance < right_distance
	var left_life: int = int(left.get("life_serial", 0))
	var right_life: int = int(right.get("life_serial", 0))
	if left_life != right_life:
		return left_life < right_life
	var left_death: int = int(left.get("death_serial", 0))
	var right_death: int = int(right.get("death_serial", 0))
	if left_death != right_death:
		return left_death < right_death
	var left_point: Vector2 = left.get("point", Vector2.ZERO)
	var right_point: Vector2 = right.get("point", Vector2.ZERO)
	if not is_equal_approx(left_point.x, right_point.x):
		return left_point.x < right_point.x
	return left_point.y < right_point.y


func _too_close_to_selected(point: Vector2, selected: PackedVector2Array, spacing: float) -> bool:
	var spacing_squared: float = spacing * spacing
	for existing: Vector2 in selected:
		if point.distance_squared_to(existing) < spacing_squared:
			return true
	return false


func _point_inside_any_rect(point: Vector2, rects: Array) -> bool:
	for value: Variant in rects:
		if value is Rect2 and (value as Rect2).has_point(point):
			return true
	return false


func _max_visible_radius() -> float:
	var corners := PackedVector2Array([
		Vector2.ZERO,
		Vector2(canvas_size.x, 0.0),
		canvas_size,
		Vector2(0.0, canvas_size.y),
	])
	var farthest: float = 0.0
	for corner: Vector2 in corners:
		farthest = maxf(farthest, life_source.distance_to(corner))
		farthest = maxf(farthest, death_source.distance_to(corner))
	return farthest + band_half_width_px


func _optional_rule_float(rules: Object, property_name: StringName, fallback: float) -> float:
	for property: Dictionary in rules.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return float(rules.get(property_name))
	return fallback


func _ensure_material() -> void:
	if is_instance_valid(_shader_material):
		return
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = FIELD_SHADER
	material = _shader_material


func _ensure_su_overlay() -> void:
	if is_instance_valid(_su_overlay):
		return
	_su_overlay = SU_OVERLAY_SCRIPT.new() as Node2D
	_su_overlay.name = "SuManifestationOverlay"
	# Ghost 是可判分目标，不能继承背景波纹层而被前景 Tuning（最高 Z=35）盖住。
	# 使用画布绝对层级；HUD 的独立 CanvasLayer 仍在其上方。
	_su_overlay.z_as_relative = false
	_su_overlay.z_index = 50
	_su_overlay.set("bone_color", overlap_color)
	add_child(_su_overlay)


func _apply_canvas_size() -> void:
	position = Vector2.ZERO
	size = canvas_size
	custom_minimum_size = canvas_size


func _push_configuration() -> void:
	if not is_inside_tree():
		return
	_ensure_material()
	_shader_material.set_shader_parameter(&"field_size_px", canvas_size)
	_shader_material.set_shader_parameter(&"life_source_px", life_source)
	_shader_material.set_shader_parameter(&"death_source_px", death_source)
	_shader_material.set_shader_parameter(&"wave_speed_px_sec", wave_speed_px_sec)
	_shader_material.set_shader_parameter(&"max_visible_radius_px", _max_visible_radius())
	_shader_material.set_shader_parameter(&"band_half_width_px", band_half_width_px)
	_shader_material.set_shader_parameter(&"life_color", life_color)
	_shader_material.set_shader_parameter(&"death_color", death_color)
	_shader_material.set_shader_parameter(&"overlap_color", overlap_color)
	_shader_material.set_shader_parameter(&"field_strength", field_strength * visual_intensity)
	_shader_material.set_shader_parameter(&"overlap_threshold", overlap_threshold)
	_shader_material.set_shader_parameter(&"stipple_cell_px", stipple_cell_px)
	# visual_intensity 已在最终场强中乘过一次；辉光不能再次相乘，否则低强度会平方衰减。
	_shader_material.set_shader_parameter(&"glow_strength", glow_strength)
	_shader_material.set_shader_parameter(&"aligned_band_scale", aligned_band_scale)
	_shader_material.set_shader_parameter(&"aligned_brightness_scale", aligned_brightness_scale)


func _push_runtime_state() -> void:
	if not is_inside_tree():
		return
	_ensure_material()
	var life_display_times: Array[float] = _display_wavefront_times(_life_wavefront_times)
	var death_display_times: Array[float] = _display_wavefront_times(_death_wavefront_times)
	var field_enabled: bool = not life_display_times.is_empty() or not death_display_times.is_empty()
	var overlay_active: bool = (
		is_instance_valid(_su_overlay)
		and bool(_su_overlay.call("has_active_entries"))
	)
	# 没有波前也没有素音反馈时隐藏整层，可完全跳过全屏像素 Shader。
	visible = field_enabled or overlay_active
	_shader_material.set_shader_parameter(&"field_enabled", 1.0 if field_enabled else 0.0)
	_shader_material.set_shader_parameter(&"visual_time_sec", _visual_time_sec)
	_shader_material.set_shader_parameter(&"life_wavefront_count", life_display_times.size())
	_shader_material.set_shader_parameter(&"death_wavefront_count", death_display_times.size())
	_shader_material.set_shader_parameter(&"life_guide_aligned", _life_alignment_strength)
	_shader_material.set_shader_parameter(&"death_guide_aligned", _death_alignment_strength)
	_shader_material.set_shader_parameter(&"life_emission_times", _padded_wavefront_times(life_display_times))
	_shader_material.set_shader_parameter(&"death_emission_times", _padded_wavefront_times(death_display_times))


func _padded_wavefront_times(wavefront_times: Array[float]) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(MAX_SHADER_WAVEFRONTS)
	for index: int in range(mini(wavefront_times.size(), MAX_SHADER_WAVEFRONTS)):
		result[index] = wavefront_times[index]
	return result


func _approach_alignment_strength(current: float, target: float, delta: float) -> float:
	var duration_sec: float = 0.06 if target > current else 0.10
	return move_toward(current, target, maxf(delta, 0.0) / duration_sec)
