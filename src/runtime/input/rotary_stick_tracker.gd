class_name RotaryStickTracker
extends RefCounted

## 把摇杆绕中心的旋转转换为有符号角位移。
##
## 计分滑条采用“起点捕获、途中自由”的虚拟离合：第一次必须从滑条起点
## 附近接入；接入后只累计真实角位移，不再用屏幕圆弧限制拇指的物理位置。
## 回中换手只会松开离合，不会清掉滑条进度或重新要求寻找起点。
## Godot 屏幕坐标 Y 轴向下，因此正角度就是玩家看到的顺时针旋转。

const TUNING_ARC_GEOMETRY: GDScript = preload("res://src/domain/tuning/tuning_arc_geometry.gd")

# 接合与释放使用不同半径，拇指画圆时稍微内收不会反复断开。
const DEFAULT_ENGAGE_RADIUS: float = 0.55
const DEFAULT_RELEASE_RADIUS: float = 0.35
# 小于四分之一度的逐帧抖动先暂存，缓慢旋转仍会完整累计。
const DEFAULT_EMIT_STEP_RAD: float = deg_to_rad(0.25)
# 自由旋转允许较大的真实快速动作；更大的跳变通常是摇杆横穿中心。
const DEFAULT_MAX_FRAME_STEP_RAD: float = deg_to_rad(165.0)
# 有限弧遇到异常跳变时只重新定锚，绝不能把摇杆横穿中心误判成旋转。
const DEFAULT_FINITE_MAX_FRAME_STEP_RAD: float = deg_to_rad(110.0)
const PROGRESS_EPSILON: float = 0.000001

var engage_radius: float = DEFAULT_ENGAGE_RADIUS
var release_radius: float = DEFAULT_RELEASE_RADIUS
var emit_step_rad: float = DEFAULT_EMIT_STEP_RAD
var max_frame_step_rad: float = DEFAULT_MAX_FRAME_STEP_RAD
var finite_max_frame_step_rad: float = DEFAULT_FINITE_MAX_FRAME_STEP_RAD

var _tracking: bool = false
var _previous_direction: Vector2 = Vector2.RIGHT
var _pending_angle_rad: float = 0.0

# 计分滑条只把屏幕圆弧用于定义“起手方向”和“填满需要转多少角度”。
# progress 是最近一次已经交给领域层的位置；它不绑定摇杆的绝对角度。
var _finite_arc_enabled: bool = false
var _arc_affinity: int = GameplayTypes.Affinity.ZHU
var _arc_rotation_sign: int = 1
var _arc_sweep_rad: float = 0.0
var _arc_rotation_offset_rad: float = 0.0
var _arc_progress: float = 0.0
# 首次起手完成后，物理离合可以反复松开/接上，不再重走起点捕获。
var _initial_capture_completed: bool = false
var _current_leg_index: int = 0


## 只松开当前物理离合，不丢失有限弧配置、进度或首次捕获状态。
func reset() -> void:
	_tracking = false
	_previous_direction = Vector2.RIGHT
	_pending_angle_rad = 0.0


func disable_finite_arc() -> void:
	reset()
	_finite_arc_enabled = false
	_arc_affinity = GameplayTypes.Affinity.ZHU
	_arc_rotation_sign = 1
	_arc_sweep_rad = 0.0
	_arc_rotation_offset_rad = 0.0
	_arc_progress = 0.0
	_initial_capture_completed = false
	_current_leg_index = 0


## 为一张新滑条建立固定弧。rotation_sign 是从事件起点走向终点时的物理旋向：
## 1 为顺时针，-1 为逆时针。往返时只切换 leg，不重建弧。
func configure_finite_arc(
		affinity: int,
		rotation_sign: int,
		sweep_rad: float,
		initial_progress: float = 0.0,
		rotation_offset_rad: float = 0.0
) -> void:
	reset()
	_finite_arc_enabled = true
	_arc_affinity = affinity
	_arc_rotation_sign = signi(rotation_sign)
	_arc_sweep_rad = maxf(sweep_rad, 0.0)
	_arc_rotation_offset_rad = rotation_offset_rad
	_arc_progress = clampf(initial_progress, 0.0, 1.0)
	# 每个独立事件都有自己的摇杆手势会话。即使鼠标已改变频率，手柄第一次
	# 接管这条新滑条时也仍要经过它自己的起点扇区。
	_initial_capture_completed = false
	_current_leg_index = 0


func has_finite_arc() -> bool:
	return _finite_arc_enabled and _arc_rotation_sign != 0 and _arc_sweep_rad > PROGRESS_EPSILON


func finite_arc_progress() -> float:
	return _arc_progress


## 接受 TuningEngine 的权威填充位置。同步进度不会替手柄完成首次起点捕获；
## 鼠标、触屏与手柄因此不会意外共用一份物理离合状态。
func sync_authoritative_progress(progress: float) -> void:
	if not has_finite_arc():
		return
	_arc_progress = clampf(progress, 0.0, 1.0)


## 折返点只清除尚未发出的微小角度。保持当前锚点，玩家反向一动即可回退。
func set_leg_index(leg_index: int) -> void:
	var resolved: int = maxi(leg_index, 0)
	if resolved == _current_leg_index:
		return
	_current_leg_index = resolved
	_pending_angle_rad = 0.0


## 自由调频：返回本帧累计出的真实有符号角位移。
func update(stick: Vector2) -> float:
	var radius: float = stick.length()
	if not _tracking:
		if radius < engage_radius:
			return 0.0
		_tracking = true
		_previous_direction = stick / radius
		_pending_angle_rad = 0.0
		return 0.0

	if radius <= release_radius:
		reset()
		return 0.0

	var direction: Vector2 = stick / radius
	var frame_angle: float = _signed_angle(_previous_direction, direction)
	_previous_direction = direction
	if absf(frame_angle) > max_frame_step_rad:
		_pending_angle_rad = 0.0
		return 0.0

	_pending_angle_rad += frame_angle
	if absf(_pending_angle_rad) < emit_step_rad:
		return 0.0
	var emitted: float = _pending_angle_rad
	_pending_angle_rad = 0.0
	return emitted


## 第一次在滑条起点扇区接合，之后从任意手位累计真实角位移。
## 端点外的同向位移直接丢弃，不形成“过冲债务”；下一次反向会立刻回退。
func update_finite_arc(stick: Vector2) -> float:
	if not has_finite_arc():
		return 0.0
	var radius: float = stick.length()
	if radius <= release_radius:
		reset()
		return 0.0
	if radius < engage_radius and not _tracking:
		return 0.0

	var direction: Vector2 = stick / radius
	var physical_angle: float = direction.angle()
	if not _initial_capture_completed:
		if not TUNING_ARC_GEOMETRY.angle_is_inside_start_window(
				physical_angle,
				_arc_affinity,
				_arc_rotation_sign,
				_arc_sweep_rad,
				TUNING_ARC_GEOMETRY.DEFAULT_START_WINDOW_EARLY_RAD,
				TUNING_ARC_GEOMETRY.DEFAULT_START_WINDOW_LATE_RAD,
				_arc_rotation_offset_rad
		):
			return 0.0
		_tracking = true
		_previous_direction = direction
		_pending_angle_rad = 0.0
		_initial_capture_completed = true
		# 起手帧只接合，不把预先摆杆的角度算成滑条位移。
		return 0.0

	if not _tracking:
		# 首次捕获后，回中再推出可以从任意舒服的手位重新接合。首帧仍只定锚，
		# 所以换手位不会凭空改变频率。
		_tracking = true
		_previous_direction = direction
		_pending_angle_rad = 0.0
		return 0.0

	var frame_angle: float = _signed_angle(_previous_direction, direction)
	_previous_direction = direction
	if absf(frame_angle) > finite_max_frame_step_rad:
		# 异常样本只重新定锚；下一帧仍可继续，不进入窄小的复接陷阱。
		_pending_angle_rad = 0.0
		return 0.0

	_pending_angle_rad += frame_angle * float(_arc_rotation_sign)
	if absf(_pending_angle_rad) < emit_step_rad:
		return 0.0
	var progress_delta: float = _pending_angle_rad / _arc_sweep_rad
	_pending_angle_rad = 0.0
	var next_progress: float = clampf(_arc_progress + progress_delta, 0.0, 1.0)
	var applied_delta: float = next_progress - _arc_progress
	_arc_progress = next_progress
	return applied_delta


## 旧调用方使用的“丢弃本帧并重定锚”。不会修改有限弧进度。
func discard_and_reanchor(stick: Vector2) -> void:
	var radius: float = stick.length()
	if radius <= release_radius:
		reset()
		return
	if not _tracking:
		return
	_previous_direction = stick / radius
	_pending_angle_rad = 0.0


func is_tracking() -> bool:
	return _tracking


func _signed_angle(from_direction: Vector2, to_direction: Vector2) -> float:
	return atan2(
		from_direction.cross(to_direction),
		from_direction.dot(to_direction)
	)
