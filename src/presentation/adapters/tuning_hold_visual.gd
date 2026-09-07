class_name TuningHoldVisual
extends GrayboxHoldVisual

## 调频附加灵体，独立于 Gameplay Note 与滑条节点的回收。
enum HeadingMode { RADIAL, TANGENT }
## RADIAL 指向游标；TANGENT 沿当前 traversal 的曲线切线。
@export var heading_mode: HeadingMode = HeadingMode.RADIAL
## 成功时从尾端收短并淡出的秒数。
@export_range(0.01, 2.0, 0.01) var finish_duration_sec: float = 0.22
var settled: bool = false
var failed_exit: bool = false
var done: bool = false
var _finish_time: float = 0.0
var _exit_origin := Vector2.ZERO
var _exit_heading: float = 0.0


func prepare(view_model: Dictionary) -> void:
	## 新实例只接收视觉数据，不建立领域 Note 或输入监听。
	super(view_model)
	settled = false
	failed_exit = false
	done = false
	_finish_time = 0.0
	_exit_origin = Vector2.ZERO
	_exit_heading = 0.0


func set_head_heading(angle_rad: float) -> void:
	## 接受画布方向角；结算后锁定最后朝向。
	if not settled:
		rotation = angle_rad


func settle(grade: int, time_sec: float) -> void:
	## 一次性开始收短或直线离场，不参与判定。
	if settled:
		return
	settled = true
	failed_exit = grade == GameplayTypes.JudgmentGrade.MISS
	_finish_time = time_sec
	_exit_origin = position
	_exit_heading = rotation
	play_judgment(grade)
	# 结果颜色仍由 grade 绘制，但淡出归 Gameplay 时钟所有，不能被颜色 Tween 覆盖。
	if _timing_tween != null:
		_timing_tween.kill()
		_timing_tween = null
	modulate = Color.WHITE


func update_exit(time_sec: float, speed: float, canvas_size: Vector2) -> void:
	## 使用绝对 Gameplay 时间计算离场目标；动态链由时钟单独推进。
	var elapsed: float = maxf(time_sec - _finish_time, 0.0)
	if failed_exit:
		position = _exit_origin + Vector2.from_angle(_exit_heading) * speed * elapsed
		rotation = _exit_heading
		set_body_target(body_length)
		# 以整个链长及绘制余量包围身体，整条灵体均在边界外才回收。
		done = not Rect2(Vector2.ZERO, canvas_size).grow(body_length + 120.0).has_point(position)
	else:
		var progress: float = clampf(elapsed / finish_duration_sec, 0.0, 1.0)
		set_hold_progress(progress)
		set_body_target(body_length * (1.0 - progress))
		modulate.a = 1.0 - progress
		done = progress >= 1.0
