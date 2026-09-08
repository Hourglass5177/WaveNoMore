class_name TuningArcGeometry
extends RefCounted

## 调频滑条与摇杆手势共用的圆弧几何。
## 新滑条把“频率跨度 × 每 Hz 像素数”视为弦长，再用一个较近的等效圆心
## 把过平的长条展开成更适合拇指操作的有限弧。

const LIFE_CENTER_ANGLE_RAD: float = -PI * 0.5
const DEATH_CENTER_ANGLE_RAD: float = PI * 0.5

# 1920 宽设计画布上约为 420 px。按画布宽度取比例，换分辨率时曲率不会变形。
const DEFAULT_CENTER_DISTANCE_RATIO: float = 0.21875
# 过短的角行程容易变成“轻轻一抖就满”；过长则不适合单次拇指画弧。
const DEFAULT_MIN_SWEEP_RAD: float = PI * 28.0 / 180.0
const DEFAULT_MAX_SWEEP_RAD: float = PI * 100.0 / 180.0
# 独立滑条第一次接合时，允许在屏幕起点两侧各偏约 15°。这个扇区只负责
# 帮玩家建立“从哪里、往哪边转”的直觉；接合后不再限制摇杆绝对方向。
const DEFAULT_START_WINDOW_EARLY_RAD: float = PI * 15.0 / 180.0
const DEFAULT_START_WINDOW_LATE_RAD: float = PI * 15.0 / 180.0
const GEOMETRY_EPSILON: float = 0.000001


static func center_angle_rad(affinity: int, rotation_offset_rad: float = 0.0) -> float:
	return wrapf((
		DEATH_CENTER_ANGLE_RAD
		if affinity == GameplayTypes.Affinity.XUAN
		else LIFE_CENTER_ANGLE_RAD
	) + rotation_offset_rad, -PI, PI)


static func chord_length_px(
		start_value: float,
		end_value: float,
		min_frequency_hz: float,
		max_frequency_hz: float,
		pixels_per_hz: float
) -> float:
	## 谱面仍保存归一化频率，进入几何层后才换算成屏幕上的弦长。
	var frequency_range_hz: float = maxf(max_frequency_hz - min_frequency_hz, 0.0)
	var frequency_span_hz: float = absf(end_value - start_value) * frequency_range_hz
	return frequency_span_hz * maxf(pixels_per_hz, 0.0)


static func equivalent_center_distance_px(
		design_width_px: float,
		center_distance_ratio: float = DEFAULT_CENTER_DISTANCE_RATIO
) -> float:
	## 这里的距离是“弦中点到圆心”，不是圆半径，也不是弧高。
	return maxf(design_width_px, 0.0) * maxf(center_distance_ratio, 0.0)


static func bounded_sweep_rad(
		raw_sweep_rad: float,
		min_sweep_rad: float = DEFAULT_MIN_SWEEP_RAD,
		max_sweep_rad: float = DEFAULT_MAX_SWEEP_RAD,
		start_window_early_rad: float = DEFAULT_START_WINDOW_EARLY_RAD
) -> float:
	## 零长度滑条保持为零；否则限制在易操作范围内，并为起点窗口留出半圆边界。
	if raw_sweep_rad <= GEOMETRY_EPSILON:
		return 0.0
	var outer_padding: float = clampf(start_window_early_rad, 0.0, PI * 0.5)
	var hemisphere_limit: float = maxf(PI - outer_padding * 2.0, 0.0)
	var upper: float = minf(clampf(max_sweep_rad, 0.0, PI), hemisphere_limit)
	var lower: float = minf(clampf(min_sweep_rad, 0.0, PI), upper)
	return clampf(raw_sweep_rad, lower, upper)


static func equivalent_sweep_from_chord_rad(
		chord_px: float,
		center_distance_px: float,
		min_sweep_rad: float = DEFAULT_MIN_SWEEP_RAD,
		max_sweep_rad: float = DEFAULT_MAX_SWEEP_RAD,
		start_window_early_rad: float = DEFAULT_START_WINDOW_EARLY_RAD
) -> float:
	## 固定弦长 c、弦中点到圆心距离 d 时，圆心角为 2*atan(c/(2d))。
	## 缩短 d 会让起点和终点绕固定中轴对称外移，而不是把整段弧平移。
	if chord_px <= GEOMETRY_EPSILON:
		return 0.0
	var safe_center_distance: float = maxf(center_distance_px, GEOMETRY_EPSILON)
	var raw_sweep: float = 2.0 * atan(chord_px / (2.0 * safe_center_distance))
	return bounded_sweep_rad(
		raw_sweep,
		min_sweep_rad,
		max_sweep_rad,
		start_window_early_rad
	)


static func equivalent_sweep_rad(
		start_value: float,
		end_value: float,
		min_frequency_hz: float,
		max_frequency_hz: float,
		pixels_per_hz: float,
		design_width_px: float,
		center_distance_ratio: float = DEFAULT_CENTER_DISTANCE_RATIO,
		min_sweep_rad: float = DEFAULT_MIN_SWEEP_RAD,
		max_sweep_rad: float = DEFAULT_MAX_SWEEP_RAD,
		start_window_early_rad: float = DEFAULT_START_WINDOW_EARLY_RAD
) -> float:
	var chord_px: float = chord_length_px(
		start_value,
		end_value,
		min_frequency_hz,
		max_frequency_hz,
		pixels_per_hz
	)
	var center_distance_px: float = equivalent_center_distance_px(
		design_width_px,
		center_distance_ratio
	)
	return equivalent_sweep_from_chord_rad(
		chord_px,
		center_distance_px,
		min_sweep_rad,
		max_sweep_rad,
		start_window_early_rad
	)


static func equivalent_radius_from_chord_px(chord_px: float, sweep: float) -> float:
	## 已知弦长和圆心角，供表现层恢复同一个等效圆；零长度输入返回零。
	if chord_px <= GEOMETRY_EPSILON or sweep <= GEOMETRY_EPSILON:
		return 0.0
	return chord_px / (2.0 * sin(clampf(sweep, GEOMETRY_EPSILON, PI) * 0.5))


static func symmetric_directed_angles(
		affinity: int,
		rotation_sign: int,
		sweep: float,
		rotation_offset_rad: float = 0.0
) -> Vector2:
	var middle: float = center_angle_rad(affinity, rotation_offset_rad)
	if rotation_sign == 0:
		return Vector2(middle, middle)
	var half_sweep: float = maxf(sweep, 0.0) * 0.5
	return Vector2(
		middle - half_sweep * float(rotation_sign),
		middle + half_sweep * float(rotation_sign)
	)


static func start_window_angles(
		affinity: int,
		rotation_sign: int,
		sweep: float,
		early_padding_rad: float = DEFAULT_START_WINDOW_EARLY_RAD,
		late_padding_rad: float = DEFAULT_START_WINDOW_LATE_RAD,
		rotation_offset_rad: float = 0.0
) -> Vector2:
	## 返回沿操作方向排列的窗口边界：x 在起点之前，y 在起点之后。
	var sign_value: int = signi(rotation_sign)
	var start_angle: float = symmetric_directed_angles(
		affinity,
		sign_value,
		sweep,
		rotation_offset_rad
	).x
	if sign_value == 0:
		return Vector2(start_angle, start_angle)
	return Vector2(
		start_angle - float(sign_value) * maxf(early_padding_rad, 0.0),
		start_angle + float(sign_value) * maxf(late_padding_rad, 0.0)
	)


static func angle_is_inside_start_window(
		angle_rad: float,
		affinity: int,
		rotation_sign: int,
		sweep: float,
		early_padding_rad: float = DEFAULT_START_WINDOW_EARLY_RAD,
		late_padding_rad: float = DEFAULT_START_WINDOW_LATE_RAD,
		rotation_offset_rad: float = 0.0
) -> bool:
	var sign_value: int = signi(rotation_sign)
	if sign_value == 0:
		return false
	var start_angle: float = symmetric_directed_angles(
		affinity,
		sign_value,
		sweep,
		rotation_offset_rad
	).x
	var directed_offset: float = (
		wrapf(angle_rad - start_angle, -PI, PI)
		* float(sign_value)
	)
	return (
		directed_offset >= -maxf(early_padding_rad, 0.0) - GEOMETRY_EPSILON
		and directed_offset <= maxf(late_padding_rad, 0.0) + GEOMETRY_EPSILON
	)


static func stick_can_engage_at_start(
		stick: Vector2,
		affinity: int,
		rotation_sign: int,
		sweep: float,
		engage_radius: float,
		early_padding_rad: float = DEFAULT_START_WINDOW_EARLY_RAD,
		late_padding_rad: float = DEFAULT_START_WINDOW_LATE_RAD,
		rotation_offset_rad: float = 0.0
) -> bool:
	if stick.length() < maxf(engage_radius, 0.0):
		return false
	return angle_is_inside_start_window(
		stick.angle(),
		affinity,
		rotation_sign,
		sweep,
		early_padding_rad,
		late_padding_rad,
		rotation_offset_rad
	)


static func progress_from_angle(
		angle_rad: float,
		affinity: int,
		rotation_sign: int,
		sweep: float,
		rotation_offset_rad: float = 0.0
) -> float:
	## 把摇杆绝对极角投影到固定圆弧。越界只截断，反向移动会自然退回。
	var sign_value: int = signi(rotation_sign)
	if sign_value == 0 or sweep <= GEOMETRY_EPSILON:
		return 0.0
	var start_angle: float = symmetric_directed_angles(
		affinity,
		sign_value,
		sweep,
		rotation_offset_rad
	).x
	var directed_angle: float = (
		wrapf(angle_rad - start_angle, -PI, PI)
		* float(sign_value)
	)
	return clampf(directed_angle / sweep, 0.0, 1.0)


static func angle_at_progress(
		progress: float,
		affinity: int,
		rotation_sign: int,
		sweep: float,
		rotation_offset_rad: float = 0.0
) -> float:
	var sign_value: int = signi(rotation_sign)
	var start_angle: float = symmetric_directed_angles(
		affinity,
		sign_value,
		sweep,
		rotation_offset_rad
	).x
	return start_angle + float(sign_value) * maxf(sweep, 0.0) * clampf(progress, 0.0, 1.0)


static func transform_curve_relative(relative: Vector2, affinity: int, rotation_rad: float) -> Vector2:
	## 曲线、圆心补偿和切线共享设计画布旋转/中心反演；不反转采样顺序。
	var rotated: Vector2 = relative.rotated(rotation_rad)
	return -rotated if affinity == GameplayTypes.Affinity.XUAN else rotated


static func slider_tangent(progress: float, affinity: int, start_value: float, end_value: float, sweep: float, rotation_rad: float) -> Vector2:
	## 对 normalized_chord_arc_point 求导，再应用视觉层相同的采样顺序与变换。
	## 方向始终表示事件 start_value → end_value，不随 traversal 重复反转。
	var increasing: bool = end_value >= start_value
	var frequency_t: float = clampf(progress, 0.0, 1.0) if increasing else 1.0 - clampf(progress, 0.0, 1.0)
	var death: bool = affinity == GameplayTypes.Affinity.XUAN
	var sample_t: float = 1.0 - frequency_t if death else frequency_t
	var angle: float = (sample_t - 0.5) * clampf(sweep, GEOMETRY_EPSILON, PI - GEOMETRY_EPSILON)
	var tangent := Vector2(cos(angle), sin(angle))
	if death:
		tangent = -tangent # 死侧反向采样的导数。
	if not increasing:
		tangent = -tangent # 频率递减时事件点列反序。
	return transform_curve_relative(tangent, affinity, rotation_rad)


static func normalized_chord_arc_point(t: float, sweep: float) -> Vector2:
	## 返回弦长严格为 1 的上拱圆弧。表现层乘以 chord_length_px() 后，
	## 屏幕端点距离就与谱面频率跨度严格一致。
	var clamped_t: float = clampf(t, 0.0, 1.0)
	if sweep <= GEOMETRY_EPSILON:
		return Vector2(lerpf(-0.5, 0.5, clamped_t), 0.0)
	var safe_sweep: float = clampf(sweep, GEOMETRY_EPSILON, PI - GEOMETRY_EPSILON)
	var half_sweep: float = safe_sweep * 0.5
	var radius: float = 0.5 / sin(half_sweep)
	var angle: float = lerpf(-half_sweep, half_sweep, clamped_t)
	return Vector2(
		radius * sin(angle),
		radius * (cos(half_sweep) - cos(angle))
	)
