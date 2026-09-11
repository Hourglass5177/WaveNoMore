class_name GrayboxBackdrop
extends Node2D

## 无素材的关卡背景占位。默认生死分界是一条水平时间轴，正式美术可通过 StageVisualTheme 替换。

## 设计画布尺寸，单位为像素。所有背景坐标都以左上角为 (0, 0)。
@export var canvas_size: Vector2 = Vector2(1920.0, 1080.0)
## 上半生界的底色；只影响灰盒背景，不改变生音符或声波的颜色。
@export var life_color: Color = Color("6f211f")
## 下半死界的底色；只影响灰盒背景。
@export var death_color: Color = Color("111522")
## 画布底层和角色剪影使用的深色。
@export var ink_color: Color = Color("07090f")
## 分界线、兵器等浅色细节使用的骨白色。
@export var bone_color: Color = Color("d9d0b7")

@export_group("Bell Strike Feedback")
## 生钟敲击反馈的圆心，单位为画布像素，通常与玩法规则中的生波源重合。
@export var life_bell_origin: Vector2 = Vector2(350.0, 280.0)
## 死钟敲击反馈的圆心，单位为画布像素，是生钟位置关于画布中心的对称点。
@export var death_bell_origin: Vector2 = Vector2(1570.0, 800.0)
## 一次钟面涟漪的可见时长，单位为秒；数值越大，涟漪扩散和淡出的过程越慢。
@export_range(0.1, 1.0, 0.01) var strike_duration_sec: float = 0.44
## 每口钟最多同时保留的涟漪数；数值越大，密集敲击时叠加越丰富，也会增加少量绘制开销。
@export_range(1, 8, 1) var max_strike_ripples: int = 5

# 由外部写入的关卡状态：歌曲和魂火均为 0～1，failed 控制失败后的整体压暗。
var song_progress: float = 0.0
# 当前魂火占最大魂火的比例；0 表示耗尽，1 表示满值，用于绘制魂火状态。
var soul_fire_ratio: float = 1.0
# 当前关卡是否已经失败；为 true 时背景切换到失败后的视觉状态。
var failed: bool = false
# 正式主题提供对应素材后，可分别关闭灰盒分界线和两个角色剪影。
var draw_placeholder_boundary: bool = true
# 是否绘制生者角色的灰盒占位图；正式角色素材存在时会关闭。
var draw_placeholder_life_actor: bool = true
# 是否绘制死者角色的灰盒占位图；正式角色素材存在时会关闭。
var draw_placeholder_death_actor: bool = true
# 数组中的浮点数是每道涟漪从 0 到 1 的播放进度；生死两侧独立保存。
var _life_strikes: Array[float] = []
# 死钟敲击残影的剩余强度列表；每个数值会随时间衰减直至移除。
var _death_strikes: Array[float] = []


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_advance_strikes(_life_strikes, delta)
	_advance_strikes(_death_strikes, delta)
	set_process(not _life_strikes.is_empty() or not _death_strikes.is_empty())
	queue_redraw()


func trigger_bell_strike(affinity: int) -> void:
	var strikes: Array[float] = _death_strikes if affinity == GameplayTypes.Affinity.XUAN else _life_strikes
	strikes.append(0.0)
	while strikes.size() > max_strike_ripples:
		strikes.pop_front()
	set_process(true)
	queue_redraw()


func clear_bell_strikes() -> void:
	_life_strikes.clear()
	_death_strikes.clear()
	set_process(false)
	queue_redraw()


func active_strike_count(affinity: int) -> int:
	return _death_strikes.size() if affinity == GameplayTypes.Affinity.XUAN else _life_strikes.size()


func set_placeholder_visibility(
	boundary_visible: bool,
	life_actor_visible: bool,
	death_actor_visible: bool
) -> void:
	draw_placeholder_boundary = boundary_visible
	draw_placeholder_life_actor = life_actor_visible
	draw_placeholder_death_actor = death_actor_visible
	queue_redraw()


func set_song_progress(value: float) -> void:
	song_progress = clampf(value, 0.0, 1.0)
	queue_redraw()


func set_soul_fire_ratio(value: float) -> void:
	soul_fire_ratio = clampf(value, 0.0, 1.0)
	queue_redraw()


func set_failed(value: bool) -> void:
	failed = value
	queue_redraw()


func _draw() -> void:
	var boundary: PackedVector2Array = _boundary_points()
	if draw_placeholder_boundary:
		_draw_boundary(boundary)
	if draw_placeholder_life_actor:
		_draw_actor_silhouette(Vector2(270.0, 235.0), false)
	if draw_placeholder_death_actor:
		_draw_actor_silhouette(canvas_size - Vector2(270.0, 235.0), true)
	_draw_strike_ripples(life_bell_origin, _life_strikes, life_color.lightened(0.48))
	_draw_strike_ripples(death_bell_origin, _death_strikes, bone_color)


## 仅在目标 CanvasItem 的绘制回调中调用；共享原颜色、尺寸和失败状态。
func draw_background(target: CanvasItem) -> void:
	target.draw_rect(Rect2(Vector2.ZERO, canvas_size), ink_color, true)

	var life_tint: Color = life_color.darkened(0.30 if failed else 0.0)
	var death_tint: Color = death_color.darkened(0.22 if failed else 0.0)
	var boundary: PackedVector2Array = _boundary_points()

	var life_polygon := PackedVector2Array([
		Vector2.ZERO,
		Vector2(canvas_size.x, 0.0),
		boundary[boundary.size() - 1],
	])
	for index: int in range(boundary.size() - 2, -1, -1):
		life_polygon.append(boundary[index])
	target.draw_colored_polygon(life_polygon, life_tint)

	var death_polygon := PackedVector2Array([boundary[0]])
	for index: int in range(1, boundary.size()):
		death_polygon.append(boundary[index])
	death_polygon.append(Vector2(canvas_size.x, canvas_size.y))
	death_polygon.append(Vector2(0.0, canvas_size.y))
	target.draw_colored_polygon(death_polygon, death_tint)

	_draw_scratches(target, true)
	_draw_scratches(target, false)


func _advance_strikes(strikes: Array[float], delta: float) -> void:
	var duration: float = maxf(strike_duration_sec, 0.001)
	for index: int in range(strikes.size() - 1, -1, -1):
		strikes[index] += delta / duration
		if strikes[index] >= 1.0:
			strikes.remove_at(index)


func _draw_strike_ripples(origin: Vector2, strikes: Array[float], color: Color) -> void:
	for progress: float in strikes:
		var eased: float = 1.0 - pow(1.0 - clampf(progress, 0.0, 1.0), 3.0)
		var radius: float = lerpf(34.0, 260.0, eased)
		var alpha: float = pow(1.0 - progress, 1.7) * 0.82
		var width: float = lerpf(11.0, 2.0, eased)
		draw_arc(origin, radius, 0.0, TAU, 96, Color(color, alpha), width, true)
		draw_arc(origin, radius * 0.73, 0.0, TAU, 72, Color(color, alpha * 0.34), maxf(width * 0.42, 1.0), true)


func _boundary_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	var count: int = 33
	var boundary_y: float = canvas_size.y * 0.5
	for index: int in range(count):
		var ratio: float = float(index) / float(count - 1)
		points.append(Vector2(ratio * canvas_size.x, boundary_y))
	return points


func _draw_boundary(points: PackedVector2Array) -> void:
	draw_polyline(points, Color(bone_color, 0.17), 7.0, true)

	# 歌曲进度沿水平分界线推进；保留点列形式，是为了将来替换成自定义边界时仍有稳定接口。
	if song_progress > 0.0:
		var boundary_y: float = canvas_size.y * 0.5
		draw_line(
			Vector2(0.0, boundary_y),
			Vector2(canvas_size.x * song_progress, boundary_y),
			Color(bone_color, 0.78),
			3.0 + soul_fire_ratio * 2.0,
			true
		)


func _draw_scratches(target: CanvasItem, life_side: bool) -> void:
	var color: Color = Color(bone_color, 0.055 if life_side else 0.045)
	var boundary_y: float = canvas_size.y * 0.5
	for index: int in range(24):
		var seed: float = float(index)
		var base_x: float = fmod(seed * 197.0 + (0.0 if life_side else 83.0), canvas_size.x)
		var base_y: float = fmod(seed * 113.0 + (47.0 if life_side else 211.0), canvas_size.y)
		if life_side and base_y > boundary_y - 28.0:
			continue
		if not life_side and base_y < boundary_y + 28.0:
			continue
		var length: float = 80.0 + fmod(seed * 37.0, 150.0)
		var direction := Vector2(1.0, -0.14 if life_side else 0.14).normalized()
		target.draw_line(Vector2(base_x, base_y), Vector2(base_x, base_y) + direction * length, color, 2.0, true)


func _draw_actor_silhouette(center: Vector2, rotated: bool) -> void:
	var direction: float = -1.0 if rotated else 1.0
	var body := PackedVector2Array([
		center + Vector2(-34.0 * direction, -68.0 * direction),
		center + Vector2(29.0 * direction, -54.0 * direction),
		center + Vector2(51.0 * direction, 17.0 * direction),
		center + Vector2(16.0 * direction, 108.0 * direction),
		center + Vector2(-58.0 * direction, 91.0 * direction),
		center + Vector2(-47.0 * direction, 4.0 * direction),
	])
	draw_colored_polygon(body, Color(ink_color, 0.91))
	var mallet_start: Vector2 = center + Vector2(10.0 * direction, -15.0 * direction)
	var mallet_end: Vector2 = center + Vector2(112.0 * direction, -78.0 * direction)
	draw_line(mallet_start, mallet_end, Color(bone_color, 0.42), 8.0, true)
	draw_line(
		mallet_end - Vector2(14.0 * direction, 8.0 * direction),
		mallet_end + Vector2(14.0 * direction, 8.0 * direction),
		Color(bone_color, 0.6),
		13.0,
		true
	)
