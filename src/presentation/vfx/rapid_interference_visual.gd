class_name RapidInterferenceVisual
extends ColorRect

## 由有效疾振敲击形成的相纹表现。这里没有自动振荡器或预画曲线；
## 每个 RAPID wave_launched 事件只生成一个发出后不再改动的径向波包，判定仍由 RapidEngine 负责。

# 全屏疾振相纹 Shader；GDScript 只整理真实波包数据，不预画图案。
const FIELD_SHADER: Shader = preload("res://shaders/fields/rapid_wave_interference.gdshader")
# Shader 每侧固定数组最多容纳 16 个波包，必须与 gdshader 中的常量一致。
const MAX_SHADER_WAVEFRONTS := 16

@export_group("Field Geometry")
## 全屏 Shader 的画布尺寸，单位为像素；应与玩法波场尺寸一致。
@export var canvas_size: Vector2 = Vector2(1920.0, 1080.0)
## 波事件缺少速度时使用的备用速度，单位为像素/秒；越大则波前扩散越快。
@export_range(100.0, 5000.0, 1.0) var fallback_wave_speed_px_sec: float = 2400.0
## 波事件缺少碰撞半宽时使用的备用值，单位为像素；越大则主波带越厚。
@export_range(1.0, 120.0, 1.0) var fallback_half_width_px: float = 25.0

@export_group("Wave Packet")
## 每次敲击在主波前后方留下的波列长度，单位为像素；越大，单次波包拖尾越长。
@export_range(24.0, 140.0, 1.0) var packet_length_px: float = 72.0
## 波包内部明暗细纹的波长，单位为像素；越大，条纹越疏。
@export_range(10.0, 48.0, 0.5) var carrier_wavelength_px: float = 22.0
## 拖尾强度衰减到很弱所需的距离，单位为像素；越大，尾部保留越久。
@export_range(12.0, 120.0, 1.0) var packet_decay_px: float = 42.0
## 内部细纹相对主波前的强度，范围 0～1；0 只剩主波前，1 时拖尾最明显。
@export_range(0.0, 1.0, 0.01) var trail_strength: float = 0.52

@export_group("Appearance")
## 疾振中的生波颜色。
@export var life_color: Color = Color("bd3328")
## 疾振中的死波颜色。
@export var death_color: Color = Color("677087")
## 两侧相长叠加时的骨白颜色。
@export var overlap_color: Color = Color("fff1d1")
## 整体颜色和透明度倍率，0 为不可见，超过 1 会更亮。
@export_range(0.0, 1.5, 0.01) var field_strength: float = 1.02
## 产生骨白相长纹所需的最低叠加强度；数值越大，白色区域越少。
@export_range(0.0, 1.0, 0.001) var overlap_threshold: float = 0.045
## 骨白网点的单元尺寸，单位为像素；数值越大，颗粒越粗疏。
@export_range(3.0, 20.0, 0.5) var stipple_cell_px: float = 7.0
## 相长区域外围光晕倍率；0 关闭光晕，数值越大越亮。
@export_range(0.0, 2.0, 0.01) var glow_strength: float = 0.82

# 此材质实例只属于当前节点，避免多个关卡共享并互相覆盖 Shader 参数。
var _shader_material: ShaderMaterial
# 时钟提供绝对视觉秒数，会话提供真实有效的疾振 wave_launched 事件。
var _clock: SongClock
# 当前关卡会话；用于读取疾振状态与统一的视觉时间。
var _session: StageSession
# 当前与上一帧视觉时间用于识别向后跳转；generation 变化表示重新开始或跳转。
var _visual_time_sec: float = 0.0
# 上一帧的绝对视觉时间，单位秒；时间倒退时据此清空旧波前。
var _previous_visual_time_sec: float = -INF
# 当前时钟世代编号；暂停重试等导致时钟重建时用它识别并重置表现。
var _clock_generation: int = -1
# 生死波包分开保存，数组元素保留发射时刻、波源、速度、半宽和最大半径。
var _life_fronts: Array[Dictionary] = []
# 当前仍在屏幕内传播的死钟疾振波前；每项保存发射时刻等数据。
var _death_fronts: Array[Dictionary] = []
# 已见 ID 防止同一发波信号重复加入；三个计数只用于调试和测试。
var _seen_wave_ids: Dictionary[String, bool] = {}
# 已被疾振规则接受并进入表现的波次数，用于调试统计。
var _accepted_wave_count: int = 0
# 因不满足疾振输入规则而拒绝的波次数，用于调试统计。
var _rejected_wave_count: int = 0
# 因波前数组已满而未上传到 Shader 的波次数，用于发现容量不足。
var _dropped_wave_count: int = 0
# 只有波包数组变化时才重新上传给 GPU，减少每帧重复传输。
var _front_arrays_dirty: bool = true
# 本轮向 Shader 上传波前数组的次数，用于排查不必要的重复更新。
var _array_upload_count: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color.WHITE
	_ensure_material()
	_apply_canvas_size()
	_push_configuration()
	clear()


func _exit_tree() -> void:
	_disconnect_sources()


func bind(clock: SongClock, session: StageSession) -> void:
	_disconnect_sources()
	_visual_time_sec = 0.0
	_previous_visual_time_sec = -INF
	_clock_generation = -1
	_clear_wave_history()
	_clock = clock
	_session = session
	if is_instance_valid(_clock) and not _clock.sample_published.is_connected(_on_clock_sample):
		_clock.sample_published.connect(_on_clock_sample)
	if is_instance_valid(_session):
		if not _session.wave_launched.is_connected(_on_wave_launched):
			_session.wave_launched.connect(_on_wave_launched)
		if not _session.waves_reset.is_connected(_on_waves_reset):
			_session.waves_reset.connect(_on_waves_reset)


func configure_from_rules(rules: GameplayRuleSet) -> void:
	if rules == null:
		return
	canvas_size = rules.wave_canvas_size
	fallback_wave_speed_px_sec = rules.wave_speed_px_sec
	fallback_half_width_px = rules.wave_front_half_width_px
	_apply_canvas_size()
	_push_configuration()


func configure_palette(p_life_color: Color, p_death_color: Color, p_overlap_color: Color) -> void:
	life_color = p_life_color.lightened(0.18)
	death_color = p_death_color.lerp(Color("b8c0d2"), 0.72)
	overlap_color = p_overlap_color
	_push_configuration()


func set_clock_sample(sample: ClockSample) -> void:
	if sample == null:
		return
	if _clock_generation >= 0 and sample.generation != _clock_generation:
		_clear_wave_history()
	_clock_generation = sample.generation
	set_visual_time(sample.visual_time_sec)


func set_visual_time(value: float) -> void:
	if is_finite(_previous_visual_time_sec) and value < _previous_visual_time_sec - 0.001:
		_clear_wave_history()
	_visual_time_sec = value
	_previous_visual_time_sec = value
	_prune_finished_fronts(_life_fronts)
	_prune_finished_fronts(_death_fronts)
	_push_runtime_state()


func clear() -> void:
	_visual_time_sec = 0.0
	_previous_visual_time_sec = -INF
	_clock_generation = -1
	_clear_wave_history()


func debug_snapshot() -> Dictionary:
	return {
		"field_enabled": not _life_fronts.is_empty() or not _death_fronts.is_empty(),
		"dynamic_pattern_active": not _life_fronts.is_empty() or not _death_fronts.is_empty(),
		"visible": visible,
		"visual_time_sec": _visual_time_sec,
		"clock_generation": _clock_generation,
		"life_wavefront_count": _life_fronts.size(),
		"death_wavefront_count": _death_fronts.size(),
		"white_overlap_pair_count": _white_overlap_pair_count(),
		"accepted_wave_count": _accepted_wave_count,
		"rejected_wave_count": _rejected_wave_count,
		"dropped_wave_count": _dropped_wave_count,
		"array_upload_count": _array_upload_count,
		"wavefront_capacity": MAX_SHADER_WAVEFRONTS,
		"life_wavefronts": _debug_fronts(_life_fronts),
		"death_wavefronts": _debug_fronts(_death_fronts),
	}


func _on_clock_sample(sample: ClockSample) -> void:
	set_clock_sample(sample)


func _on_wave_launched(wave: Dictionary) -> void:
	# 只接管有效疾振波；无效敲击仍由一般波场画成灰色，给玩家留下清楚反馈。
	if int(wave.get("owner", GameplayTypes.InputOwner.NONE)) != GameplayTypes.InputOwner.RAPID:
		return
	var wave_id: String = str(wave.get("wave_id", ""))
	if wave_id.is_empty() or _seen_wave_ids.has(wave_id):
		return
	_seen_wave_ids[wave_id] = true
	if not bool(wave.get("valid", false)):
		_rejected_wave_count += 1
		return
	var affinity: int = int(wave.get("affinity", GameplayTypes.Affinity.SU))
	if affinity not in [GameplayTypes.Affinity.ZHU, GameplayTypes.Affinity.XUAN]:
		_rejected_wave_count += 1
		return
	var origin_value: Variant = wave.get("origin", Vector2.ZERO)
	if not origin_value is Vector2:
		_rejected_wave_count += 1
		return
	var front := {
		"wave_id": wave_id,
		"affinity": affinity,
		"launch_us": int(wave.get("launch_us", 0)),
		"launch_visual_sec": _timeline_us_to_visual_sec(int(wave.get("launch_us", 0))),
		"origin": origin_value as Vector2,
		"speed_px_sec": maxf(float(wave.get("speed_px_sec", fallback_wave_speed_px_sec)), 0.001),
		"half_width_px": maxf(float(wave.get("half_width_px", fallback_half_width_px)), 1.0),
	}
	front["max_radius_px"] = _max_radius_for(front)
	var target: Array[Dictionary] = _death_fronts if affinity == GameplayTypes.Affinity.XUAN else _life_fronts
	target.append(front)
	target.sort_custom(_sort_fronts)
	while target.size() > MAX_SHADER_WAVEFRONTS:
		# 超出每侧 GPU 容量时舍弃最旧波包；一般波场仍可为未接管的波提供简化回退。
		target.pop_front()
		_dropped_wave_count += 1
	_accepted_wave_count += 1
	_front_arrays_dirty = true
	_push_runtime_state()


func _on_waves_reset() -> void:
	_clear_wave_history()


func _clear_wave_history() -> void:
	_seen_wave_ids.clear()
	_accepted_wave_count = 0
	_rejected_wave_count = 0
	_dropped_wave_count = 0
	_array_upload_count = 0
	_reset_wavefronts()


func _reset_wavefronts() -> void:
	_life_fronts.clear()
	_death_fronts.clear()
	_front_arrays_dirty = true
	_push_runtime_state()


func _prune_finished_fronts(fronts: Array[Dictionary]) -> void:
	for index: int in range(fronts.size() - 1, -1, -1):
		var front: Dictionary = fronts[index]
		var age_sec: float = _visual_time_sec - float(front["launch_visual_sec"])
		if age_sec < 0.0:
			continue
		var radius_px: float = age_sec * float(front["speed_px_sec"])
		if radius_px > float(front.get("max_radius_px", _max_radius_for(front))):
			fronts.remove_at(index)
			_front_arrays_dirty = true


func _debug_fronts(fronts: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for front: Dictionary in fronts:
		var copy: Dictionary = front.duplicate(true)
		var age_sec: float = maxf(_visual_time_sec - float(front["launch_visual_sec"]), 0.0)
		copy["age_sec"] = age_sec
		copy["radius_px"] = age_sec * float(front["speed_px_sec"])
		result.append(copy)
	return result


func _white_overlap_pair_count() -> int:
	var count: int = 0
	for life: Dictionary in _life_fronts:
		for death: Dictionary in _death_fronts:
			var life_radius: float = maxf(_visual_time_sec - float(life["launch_visual_sec"]), 0.0) * float(life["speed_px_sec"])
			var death_radius: float = maxf(_visual_time_sec - float(death["launch_visual_sec"]), 0.0) * float(death["speed_px_sec"])
			var separation: float = (life["origin"] as Vector2).distance_to(death["origin"] as Vector2)
			if separation <= life_radius + death_radius and separation >= absf(life_radius - death_radius):
				count += 1
	return count


func _sort_fronts(a: Dictionary, b: Dictionary) -> bool:
	if int(a["launch_us"]) != int(b["launch_us"]):
		return int(a["launch_us"]) < int(b["launch_us"])
	return String(a["wave_id"]) < String(b["wave_id"])


func _max_radius_for(front: Dictionary) -> float:
	var origin: Vector2 = front["origin"]
	var farthest: float = 0.0
	for corner: Vector2 in PackedVector2Array([
		Vector2.ZERO,
		Vector2(canvas_size.x, 0.0),
		canvas_size,
		Vector2(0.0, canvas_size.y),
	]):
		farthest = maxf(farthest, origin.distance_to(corner))
	return farthest + packet_length_px + float(front["half_width_px"])


func _timeline_us_to_visual_sec(timestamp_us: int) -> float:
	var offset_sec: float = 0.0
	if is_instance_valid(_clock):
		offset_sec = _clock.input_compensation_sec + _clock.visual_lead_sec
	return float(timestamp_us) / 1_000_000.0 + offset_sec


func _disconnect_sources() -> void:
	if is_instance_valid(_clock) and _clock.sample_published.is_connected(_on_clock_sample):
		_clock.sample_published.disconnect(_on_clock_sample)
	if is_instance_valid(_session):
		if _session.wave_launched.is_connected(_on_wave_launched):
			_session.wave_launched.disconnect(_on_wave_launched)
		if _session.waves_reset.is_connected(_on_waves_reset):
			_session.waves_reset.disconnect(_on_waves_reset)
	_clock = null
	_session = null


func _ensure_material() -> void:
	if is_instance_valid(_shader_material):
		return
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = FIELD_SHADER
	material = _shader_material


func _apply_canvas_size() -> void:
	position = Vector2.ZERO
	size = canvas_size
	custom_minimum_size = canvas_size


func _push_configuration() -> void:
	if not is_inside_tree():
		return
	_ensure_material()
	_shader_material.set_shader_parameter(&"field_size_px", canvas_size)
	_shader_material.set_shader_parameter(&"packet_length_px", packet_length_px)
	_shader_material.set_shader_parameter(&"carrier_wavelength_px", carrier_wavelength_px)
	_shader_material.set_shader_parameter(&"packet_decay_px", packet_decay_px)
	_shader_material.set_shader_parameter(&"trail_strength", trail_strength)
	_shader_material.set_shader_parameter(&"life_color", life_color)
	_shader_material.set_shader_parameter(&"death_color", death_color)
	_shader_material.set_shader_parameter(&"overlap_color", overlap_color)
	_shader_material.set_shader_parameter(&"field_strength", field_strength)
	_shader_material.set_shader_parameter(&"overlap_threshold", overlap_threshold)
	_shader_material.set_shader_parameter(&"stipple_cell_px", stipple_cell_px)
	_shader_material.set_shader_parameter(&"glow_strength", glow_strength)


func _push_runtime_state() -> void:
	if not is_inside_tree():
		return
	_ensure_material()
	var field_enabled: bool = not _life_fronts.is_empty() or not _death_fronts.is_empty()
	visible = field_enabled
	_shader_material.set_shader_parameter(&"field_enabled", 1.0 if field_enabled else 0.0)
	_shader_material.set_shader_parameter(&"visual_time_sec", _visual_time_sec)
	_shader_material.set_shader_parameter(&"life_wavefront_count", _life_fronts.size())
	_shader_material.set_shader_parameter(&"death_wavefront_count", _death_fronts.size())
	if _front_arrays_dirty:
		_push_front_arrays(&"life", _life_fronts)
		_push_front_arrays(&"death", _death_fronts)
		_front_arrays_dirty = false
		_array_upload_count += 1


func _push_front_arrays(prefix: StringName, fronts: Array[Dictionary]) -> void:
	var times := PackedFloat32Array()
	var speeds := PackedFloat32Array()
	var widths := PackedFloat32Array()
	var max_radii := PackedFloat32Array()
	var origins := PackedVector2Array()
	times.resize(MAX_SHADER_WAVEFRONTS)
	speeds.resize(MAX_SHADER_WAVEFRONTS)
	widths.resize(MAX_SHADER_WAVEFRONTS)
	max_radii.resize(MAX_SHADER_WAVEFRONTS)
	origins.resize(MAX_SHADER_WAVEFRONTS)
	for index: int in range(mini(fronts.size(), MAX_SHADER_WAVEFRONTS)):
		var front: Dictionary = fronts[index]
		times[index] = float(front["launch_visual_sec"])
		speeds[index] = float(front["speed_px_sec"])
		widths[index] = float(front["half_width_px"])
		max_radii[index] = float(front["max_radius_px"])
		origins[index] = front["origin"]
	_shader_material.set_shader_parameter(StringName("%s_emission_times" % prefix), times)
	_shader_material.set_shader_parameter(StringName("%s_wave_speeds" % prefix), speeds)
	_shader_material.set_shader_parameter(StringName("%s_half_widths" % prefix), widths)
	_shader_material.set_shader_parameter(StringName("%s_max_radii" % prefix), max_radii)
	_shader_material.set_shader_parameter(StringName("%s_origins" % prefix), origins)
