class_name NoteVisualHost
extends Node2D

## 音符表现的生成、更新与回收中心。头部由绝对时间定位，动态身体只在时钟帧尾推进。

## 调频附加动画独立场景，不注册为 Gameplay Note。
const TUNING_HOLD_SCENE: PackedScene = preload("res://scenes/presentation/notes/tuning_hold_visual.tscn")
# 正式主题缺少对应素材时使用的四种灰盒场景。
const DEFAULT_NOTE_SCENE: PackedScene = preload("res://scenes/presentation/notes/graybox_note_visual.tscn")
# 未配置正式素材时使用的 Hold 灰盒场景。
const DEFAULT_HOLD_SCENE: PackedScene = preload("res://scenes/presentation/notes/graybox_hold_visual.tscn")
# 未配置正式素材时使用的调频区域灰盒场景。
const DEFAULT_TUNING_SCENE: PackedScene = preload("res://scenes/presentation/fields/graybox_tuning_field.tscn")
# 未配置正式素材时使用的疾振区域灰盒场景。
const DEFAULT_RAPID_SCENE: PackedScene = preload("res://scenes/presentation/fields/graybox_rapid_field.tscn")
# 倒计时圆环也单独进入对象池；键名不能与音符场景的资源路径冲突。
const DEFAULT_TIMING_RING_SCENE: PackedScene = preload("res://scenes/presentation/notes/default_timing_ring.tscn")
# 判定进度环在对象池中的固定分类键，供创建和回收时找到同一池。
const TIMING_RING_POOL_KEY: StringName = &"timing_ring"

@export_group("Scene Wiring")
## 生音符活动节点的父级路径；只负责分组，不决定其世界坐标。
@export var life_note_slot_path: NodePath = ^"LifeNoteSlot"
## 死音符活动节点的父级路径。
@export var death_note_slot_path: NodePath = ^"DeathNoteSlot"
## 调频槽和疾振提示的父级路径；调频槽会在此坐标系内分居生、死两侧。
@export var field_slot_path: NodePath = ^"FieldSlot"
## 暂时不用的对象所停放的隐藏节点路径，避免频繁创建和释放。
@export var pool_root_path: NodePath = ^"PoolRoot"

@export_group("Art-safe Anchors")
# 生音符从右上、死音符从左下旋入同一个中心落点，两条路径保持中心对称。
## 生音符生成点，单位为画布像素；当前位于右上画面外侧。
@export var life_spawn: Vector2 = Vector2(2040.0, 220.0)
## 死音符生成点，单位为画布像素；当前位于左下画面外侧。
@export var death_spawn: Vector2 = Vector2(-120.0, 860.0)
## 生音符时机圆环闭合的位置，单位为画布像素；应保持在共同中心。
@export var life_target: Vector2 = Vector2(960.0, 540.0)
## 死音符时机圆环闭合的位置；与 life_target 相同才能形成共同落点。
@export var death_target: Vector2 = Vector2(960.0, 540.0)
## 生钟声波起点，单位为画布像素；音符越过中心后会继续朝这里飞。
@export var life_wave_origin: Vector2 = Vector2(350.0, 280.0)
## 死钟声波起点，单位为画布像素；与生钟起点关于画布中心对称。
@export var death_wave_origin: Vector2 = Vector2(1570.0, 800.0)
## 生成端控制点的横向弯曲量，单位为像素；数值越大，两条路线外侧弧度越明显。
@export_range(0.0, 600.0, 1.0) var curve_outer_bend_px: float = 220.0
## 共同中心附近控制点的弯曲量，单位为像素；数值越大，旋入中心的转向越强。
@export_range(0.0, 800.0, 1.0) var curve_center_handle_px: float = 360.0
## 是否让音符图形沿路线切线旋转；关闭后素材始终保持场景原始朝向。
@export var orient_notes_along_path: bool = true
# 调频和疾振共用中心场域，不依附任一侧普通音符轨道。
## 调频槽和疾振提示的中心位置，单位为画布像素。
@export var approach_origin: Vector2 = Vector2(960.0, 540.0)
## 音符从出现到圆环在中心闭合的秒数；数值越大，音符更早出现、移动更慢。
@export_range(0.1, 10.0, 0.01) var approach_duration_sec: float = 2.25

# SongClock 给出的绝对视觉秒数；每帧据此重算位置，不用 delta 累积。
var visual_time_sec: float = 0.0
# 当前关卡主题决定实例化哪套正式素材；空值时使用上面的灰盒场景。
var visual_theme: StageVisualTheme
# 最近一份玩法快照，提供 Hold、双钟独立滑条和疾振等显示数据。
var gameplay_snapshot: Dictionary = {}
# 当前关卡共用规则；调频视觉从中读取 Hz 范围、像素换算与引导宽容。
var gameplay_rules: GameplayRuleSet

# 四个槽位节点在 _ready() 中按导出路径取得。
var _life_note_slot: Node2D
# 死音符的显示容器；与生音符容器分开，便于保持上下世界层级。
var _death_note_slot: Node2D
# 调频和疾振区域提示的显示容器。
var _field_slot: Node2D
# 暂未使用实例的停放容器；对象回收后移到这里并隐藏，而非销毁。
var _pool_root: Node2D
# 活动表按事件 ID 保存节点、类型和谱面数据；对象池按素材类型保存可复用节点。
var _active: Dictionary[String, Dictionary] = {}
## 附加动画独立于滑条回收，按滑条 ID 保存节点、数据、抵达和待结算状态。
var _tuning_holds: Dictionary[String, Dictionary] = {}
## 调频使用输入开放的判定时间，不受视觉提前量影响。
var _judge_visual_time: float = 0.0
var _last_judge_visual_time: float = 0.0
## 首帧或 Seek 后只初始化，不补算旧时间线的积分。
var _clock_initialized: bool = false
# 从本次调度开始已经见过的调频 ID；直到 Seek、重试或换关清场前都拦截重复生成。
var _known_tuning_ids: Dictionary[String, bool] = {}
# 各类型可复用节点的对象池；键是场景类型，值是当前闲置实例数组。
var _pools: Dictionary[StringName, Array] = {}
# 调度器发出生成、判定、波接触和回收事件，是本 Host 唯一的音符事件来源。
var _scheduler: ChartScheduler
# 生死两条贝塞尔路线的采样结果及其配置键缓存；配置未变时不重复计算。
var _path_profiles: Dictionary[int, Dictionary] = {}
# 每条路径已排序的采样点键列表；缓存后可减少逐帧重复整理路径数据。
var _path_profile_keys: Dictionary[int, Array] = {}


func _ready() -> void:
	_life_note_slot = get_node(life_note_slot_path) as Node2D
	_death_note_slot = get_node(death_note_slot_path) as Node2D
	_field_slot = get_node(field_slot_path) as Node2D
	_pool_root = get_node(pool_root_path) as Node2D


func bind_scheduler(scheduler: ChartScheduler) -> void:
	clear()
	_disconnect_scheduler()
	_scheduler = scheduler
	if not is_instance_valid(_scheduler):
		return
	if not scheduler.visual_spawn_requested.is_connected(_on_visual_spawn_requested):
		scheduler.visual_spawn_requested.connect(_on_visual_spawn_requested)
	if not scheduler.visual_despawn_requested.is_connected(_on_visual_despawn_requested):
		scheduler.visual_despawn_requested.connect(_on_visual_despawn_requested)
	if not scheduler.visual_judged.is_connected(_on_visual_judged):
		scheduler.visual_judged.connect(_on_visual_judged)
	if not scheduler.visual_timing_confirmed.is_connected(_on_visual_timing_confirmed):
		scheduler.visual_timing_confirmed.connect(_on_visual_timing_confirmed)
	if not scheduler.visual_wave_contacted.is_connected(_on_visual_wave_contacted):
		scheduler.visual_wave_contacted.connect(_on_visual_wave_contacted)
	if not scheduler.visual_note_arrived.is_connected(_on_visual_note_arrived):
		scheduler.visual_note_arrived.connect(_on_visual_note_arrived)
	if not scheduler.scheduler_reset.is_connected(clear):
		scheduler.scheduler_reset.connect(clear)


func _exit_tree() -> void:
	_disconnect_scheduler()


func configure_theme(theme_resource: StageVisualTheme) -> void:
	if visual_theme != theme_resource:
		# 池中节点仍属于创建它的旧场景。换主题时若继续复用，会把上一关音符美术带进新关。
		clear()
		_free_pooled_visuals()
	visual_theme = theme_resource


func configure_rules(rules: GameplayRuleSet) -> void:
	gameplay_rules = rules
	# 通常配置发生在音符生成前；这段同步也让开发时热切换规则立即反映在活动滑条上。
	for active_entry: Dictionary in _active.values():
		if StringName(active_entry.get("kind", &"")) != ChartScheduler.KIND_TUNING:
			continue
		var visual: Node2D = active_entry.get("node") as Node2D
		if is_instance_valid(visual) and visual.has_method("configure_from_rules"):
			visual.call("configure_from_rules", gameplay_rules)


func set_clock_sample(sample: ClockSample) -> void:
	## 附加动画跟随判定时间；快照只设置状态，相同时间不重复积分。
	var delta_sec: float = maxf(sample.judge_time_sec - _last_judge_visual_time, 0.0) if _clock_initialized else 0.0
	_clock_initialized = true
	_last_judge_visual_time = sample.judge_time_sec
	_judge_visual_time = sample.judge_time_sec
	set_visual_time(sample.visual_time_sec)
	for hold_entry: Dictionary in _active.values():
		var hold_visual: Node2D = hold_entry["node"]
		if hold_visual is GrayboxHoldVisual:
			hold_visual.advance_body(delta_sec)
	for event_id: String in _tuning_holds.keys():
		var entry: Dictionary = _tuning_holds[event_id]
		var visual: TuningHoldVisual = entry["node"]
		var data: Dictionary = entry["data"]
		var canvas: Vector2 = gameplay_rules.wave_canvas_size
		if entry.has("pending_grade"):
			visual.settle(int(entry["pending_grade"]), _judge_visual_time)
			entry.erase("pending_grade")
		if visual.settled:
			visual.update_exit(_judge_visual_time, _approach_distance_px(data) / approach_duration_sec, canvas)
		else:
			var progress: float = clampf(1.0 + (_judge_visual_time - float(_start_usec(data)) / 1_000_000.0) / approach_duration_sec, 0.0, 1.0)
			visual.position = _sample_approach_path(data, progress)
			if not bool(entry.get("arrived", false)):
				visual.set_approach_progress(progress)
			if progress >= 1.0:
				entry["arrived"] = true
				visual.position = canvas * 0.5
				if _active.has(event_id):
					var field: Node2D = _active[event_id]["node"]
					if field.has_method("update_hold_heading"):
						field.call("update_hold_heading", visual)
			else:
				visual.set_head_heading(_sample_approach_tangent(data, progress).angle())
			visual.set_body_target(float(visual.visual_state_snapshot()["visible_length"]))
		visual.advance_body(delta_sec)
		if visual.done:
			visual.queue_free()
			_tuning_holds.erase(event_id)


func set_visual_time(value: float) -> void:
	## 更新时间目标，不积分；快照和时钟重复通知不会让身体多走一步。
	visual_time_sec = value
	_update_active_visuals()


func set_gameplay_snapshot(snapshot: Dictionary) -> void:
	gameplay_snapshot = snapshot.duplicate(true)
	_update_active_visuals()


func clear() -> void:
	## Seek、重试、会话结束统一清除主视觉及独立调频附加动画。
	for entry: Dictionary in _tuning_holds.values():
		entry["node"].queue_free()
	_tuning_holds.clear()
	_clock_initialized = false
	_judge_visual_time = 0.0
	_last_judge_visual_time = 0.0
	var ids: Array[String] = []
	ids.assign(_active.keys())
	for event_id: String in ids:
		_release_visual(event_id)
	_known_tuning_ids.clear()


func _on_visual_spawn_requested(kind: StringName, event_data: Dictionary) -> void:
	var event_id: String = str(event_data.get("event_id", event_data.get("id", event_data.get("unit_id", ""))))
	if event_id.is_empty():
		return
	if kind == ChartScheduler.KIND_TUNING:
		# 调度器进入预读窗的每条滑条都立即拥有独立实例。是否可操作由
		# interaction_open 决定，不能再让前一条的视觉寿命阻塞后一条预告。
		if _known_tuning_ids.has(event_id) or _active.has(event_id):
			return
		_known_tuning_ids[event_id] = true
		_spawn_visual_now(kind, event_id, event_data)
		return
	if _active.has(event_id):
		return
	_spawn_visual_now(kind, event_id, event_data)


func _spawn_visual_now(kind: StringName, event_id: String, event_data: Dictionary) -> void:
	## 真正创建节点的唯一入口。每个调频 event_id 都有自己的完整视觉生命周期。

	var pool_key: StringName = _pool_key(kind, event_data)
	var scene: PackedScene = _scene_for(kind, event_data)
	var visual: Node2D = _acquire_visual(pool_key, scene)
	var parent_slot: Node2D = _slot_for(kind, event_data)
	if visual.get_parent() != parent_slot:
		visual.reparent(parent_slot)
	visual.modulate = Color.WHITE
	visual.z_index = 0
	visual.visible = true
	if kind == ChartScheduler.KIND_TUNING and visual.has_method("configure_from_rules"):
		visual.call("configure_from_rules", gameplay_rules)
	if visual.has_method("prepare"):
		visual.call("prepare", event_data)

	# 圆形时机提示故意与音符美术并列，而不是挂在音符下面；正式素材旋转缩放时不会把圆环压扁。
	# 调频和疾振已有各自的时间 UI，不再叠一层通用圆环遮住中心。
	var timing_ring: Node2D
	if kind not in [ChartScheduler.KIND_TUNING, ChartScheduler.KIND_RAPID]:
		timing_ring = _acquire_timing_ring(_timing_ring_scene())
		if timing_ring.get_parent() != parent_slot:
			timing_ring.reparent(parent_slot)
		timing_ring.visible = true
		var timing_view_model: Dictionary = event_data.duplicate(true)
		timing_view_model["_timing_kind"] = kind
		if timing_ring.has_method("prepare"):
			timing_ring.call("prepare", timing_view_model)

	_active[event_id] = {
		"node": visual,
		"timing_ring": timing_ring,
		"kind": kind,
		"pool_key": pool_key,
		"data": event_data.duplicate(true),
		"hold_visual_progress": 0.0,
		"timing_confirmed": false,
	}
	if kind == ChartScheduler.KIND_TUNING:
		_update_tuning_preview_presentation()
		var companion: TuningHoldVisual = TUNING_HOLD_SCENE.instantiate()
		_field_slot.add_child(companion)
		companion.prepare(event_data)
		_tuning_holds[event_id] = {"node": companion, "data": event_data.duplicate(true)}
	_update_visual(event_id, _active[event_id])


func _on_visual_despawn_requested(kind: StringName, event_id: String) -> void:
	if kind == ChartScheduler.KIND_TUNING or _known_tuning_ids.has(event_id):
		_release_visual(event_id)
		_update_tuning_preview_presentation()
		return
	_release_visual(event_id)


func _on_visual_judged(event_id: String, grade: int) -> void:
	if _tuning_holds.has(event_id):
		# 一个组成绩只终结一次；后续快照或重复通知不得重新开始收短/离场。
		var companion: TuningHoldVisual = _tuning_holds[event_id]["node"]
		if not companion.settled and not _tuning_holds[event_id].has("pending_grade"):
			_tuning_holds[event_id]["pending_grade"] = grade
	if not _active.has(event_id):
		return
	var active_entry: Dictionary = _active[event_id]
	var visual: Node2D = active_entry["node"]
	if StringName(active_entry["data"].get("unit_kind", &"")) == &"hold":
		if grade == GameplayTypes.JudgmentGrade.MISS:
			active_entry["hold_failed"] = true
			active_entry["hold_resume_time"] = visual_time_sec
		else:
			_pin_hold_visual(active_entry)
			active_entry["hold_finished"] = true
			active_entry["hold_visual_progress"] = 1.0
			visual.call("set_hold_progress", 1.0)
	var timing_ring: Node2D = active_entry.get("timing_ring") as Node2D
	var already_confirmed: bool = bool(active_entry.get("timing_confirmed", false))
	if grade == GameplayTypes.JudgmentGrade.MISS and visual.has_method("play_miss"):
		visual.call("play_miss")
	elif visual.has_method("play_judgment"):
		visual.call("play_judgment", grade)
	if is_instance_valid(timing_ring) and not already_confirmed:
		if grade == GameplayTypes.JudgmentGrade.MISS and timing_ring.has_method("play_miss"):
			timing_ring.call("play_miss")
		elif timing_ring.has_method("play_judgment"):
			timing_ring.call("play_judgment", grade)


func _on_visual_timing_confirmed(event_id: String, grade: int) -> void:
	if not _active.has(event_id):
		return
	var active_entry: Dictionary = _active[event_id]
	if bool(active_entry.get("timing_confirmed", false)):
		return
	active_entry["timing_confirmed"] = true
	if StringName(active_entry["data"].get("unit_kind", &"")) == &"hold" and grade != GameplayTypes.JudgmentGrade.MISS:
		_pin_hold_visual(active_entry)
	var visual: Node2D = active_entry["node"]
	var timing_ring: Node2D = active_entry.get("timing_ring") as Node2D
	if visual.has_method("play_timing_confirmed"):
		visual.call("play_timing_confirmed", grade)
	# 这里刻意不回退调用 play_judgment：旧正式素材可能把它用于销毁性的终结特效。
	# 自定义素材必须明确实现不会销毁音符的 play_timing_confirmed 接口。
	if is_instance_valid(timing_ring):
		if grade == GameplayTypes.JudgmentGrade.MISS and timing_ring.has_method("play_miss"):
			timing_ring.call("play_miss")
		elif timing_ring.has_method("play_judgment"):
			timing_ring.call("play_judgment", grade)


func _on_visual_wave_contacted(event_id: String, contact: Dictionary) -> void:
	if not _active.has(event_id):
		return
	var visual: Node2D = _active[event_id]["node"]
	if visual.has_method("play_wave_contact"):
		visual.call("play_wave_contact", contact)


func _on_visual_note_arrived(event_id: String, arrival: Dictionary) -> void:
	if not _active.has(event_id):
		return
	var visual: Node2D = _active[event_id]["node"]
	# 抵达钟与判定结果是两个事件。Miss 只经 visual_judged 播放一次，
	# 这里单纯表现物理撞钟，避免正式素材重复播放失败动画。
	if visual.has_method("play_note_arrival"):
		visual.call("play_note_arrival", arrival)


func _update_active_visuals() -> void:
	_update_tuning_preview_presentation()
	for event_id: String in _active.keys():
		_update_visual(event_id, _active[event_id])


func _update_tuning_preview_presentation() -> void:
	## 当前条与未来条可以同时存在；这里只分配层级、亮度和共享顺序号，
	## 不改变任何事件的位置、时序或判定状态。
	var groups: Dictionary[String, Dictionary] = {}
	for event_id: String in _active.keys():
		var entry: Dictionary = _active[event_id]
		if StringName(entry.get("kind", &"")) != ChartScheduler.KIND_TUNING:
			continue
		var data: Dictionary = entry["data"]
		var state: Dictionary = _active_tuning_slider_state(event_id)
		var start_us: int = _start_usec(data)
		var group_key: String = str(data.get("group_id", ""))
		if group_key.is_empty():
			group_key = event_id
		var phase: int = 2 # 0：当前；1：未来；2：已结束但仍在播放收尾。
		if bool(state.get("interaction_open", false)):
			phase = 0
		elif start_us > roundi(_judge_visual_time * 1_000_000.0):
			phase = 1
		if not groups.has(group_key):
			groups[group_key] = {
				"key": group_key,
				"start_us": start_us,
				"phase": phase,
				"event_ids": PackedStringArray(),
			}
		var group: Dictionary = groups[group_key]
		group["start_us"] = mini(int(group["start_us"]), start_us)
		group["phase"] = mini(int(group["phase"]), phase)
		var group_event_ids: PackedStringArray = group["event_ids"]
		group_event_ids.append(event_id)
		group["event_ids"] = group_event_ids

	var ordered_groups: Array[Dictionary] = []
	for group_value: Variant in groups.values():
		ordered_groups.append(group_value as Dictionary)
	ordered_groups.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if int(left["phase"]) != int(right["phase"]):
			return int(left["phase"]) < int(right["phase"])
		if int(left["start_us"]) != int(right["start_us"]):
			return int(left["start_us"]) < int(right["start_us"])
		return str(left["key"]) < str(right["key"])
	)

	var readable_order: int = 0
	var future_rank: int = 0
	for group: Dictionary in ordered_groups:
		var phase: int = int(group["phase"])
		var alpha: float = 0.24
		var layer: int = 0
		var order_number: int = 0
		if phase <= 1:
			readable_order += 1
			order_number = readable_order
		if phase == 0:
			alpha = 1.0
			layer = 30
		elif phase == 1:
			alpha = 0.70 if future_rank == 0 else 0.45
			layer = maxi(10, 20 - future_rank)
			future_rank += 1
		for event_id: String in group["event_ids"]:
			if not _active.has(event_id):
				continue
			var visual: Node2D = _active[event_id]["node"]
			visual.z_index = layer
			if visual.has_method("set_preview_presentation"):
				# 调频滑条需要把“退后的轨道”和“醒目的起手缩圈”分层绘制。
				# 因此不再把整个节点一并压暗，而是只把层级透明度交给滑条自身。
				visual.modulate = Color.WHITE
				visual.call("set_preview_presentation", order_number, phase, alpha)
			else:
				visual.modulate = Color(1.0, 1.0, 1.0, alpha)


func _update_visual(event_id: String, active_entry: Dictionary) -> void:
	var visual: Node2D = active_entry["node"]
	var timing_ring: Node2D = active_entry.get("timing_ring") as Node2D
	var kind: StringName = active_entry["kind"]
	var data: Dictionary = active_entry["data"]
	var is_hold: bool = kind == ChartScheduler.KIND_NOTE and StringName(data.get("unit_kind", &"tap")) == &"hold"
	var hold_active: bool = is_hold and _snapshot_id_set_contains(&"active_hold_ids", event_id)
	var hold_held: bool = is_hold and _snapshot_id_set_contains(&"held_hold_ids", event_id)
	var tuning_state: Dictionary = (
		_active_tuning_slider_state(event_id)
		if kind == ChartScheduler.KIND_TUNING
		else {}
	)
	var start_sec: float = float(_start_usec(data)) / 1_000_000.0
	var end_sec: float = float(_end_usec(data)) / 1_000_000.0
	var presentation_time: float = _judge_visual_time if kind == ChartScheduler.KIND_TUNING else visual_time_sec
	var time_to_hit_sec: float = start_sec - presentation_time
	# approach 可以超过 1：圆环在中心闭合后，未解决音符仍会飞向钟，
	# 直到真实波前碰到它，或它抵达钟并成为 Miss。
	var approach: float = maxf(1.0 - time_to_hit_sec / approach_duration_sec, 0.0)
	var region_progress: float = 0.0
	if end_sec > start_sec:
		region_progress = clampf((presentation_time - start_sec) / (end_sec - start_sec), 0.0, 1.0)

	if is_hold:
		_update_hold_visual(event_id, active_entry, approach, region_progress, hold_active, hold_held)
		if not _active.has(event_id):
			return
	elif kind == ChartScheduler.KIND_NOTE:
		visual.position = _sample_approach_path(data, approach)
		# 不对称灰盒轮廓会沿路径切线转向，才能读成“旋入”；兄弟节点圆环仍保持正圆和正向。
		visual.rotation = _sample_approach_tangent(data, approach).angle() if orient_notes_along_path else 0.0
		if visual.has_method("set_approach_progress"):
			visual.call("set_approach_progress", approach)
		if visual.has_method("set_hold_progress"):
			var presented_hold_progress: float = float(active_entry.get("hold_visual_progress", 0.0))
			if hold_active and hold_held:
				# Hold 头成功且对应键仍按住时才消耗身体；提前松键进入宽限期时冻结长度，不会突然弹回。
				presented_hold_progress = maxf(presented_hold_progress, region_progress)
				active_entry["hold_visual_progress"] = presented_hold_progress
			visual.call("set_hold_progress", presented_hold_progress)
	elif kind == ChartScheduler.KIND_TUNING:
		# 调频视觉使用完整设计画布坐标绘制，FieldSlot 原点就是画布左上角；
		# 不再叠加以画布中心为值的 approach_origin，避免中心被平移到右下角。
		visual.position = Vector2.ZERO
		if visual.has_method("set_approach_timing"):
			visual.call("set_approach_timing", time_to_hit_sec, approach_duration_sec)
		if visual.has_method("set_region_progress"):
			visual.call("set_region_progress", region_progress)
		# 每个视觉实例只从 active_tuning_sliders 中取自己的权威填充、引导和端点状态。
		# 这样同组生、死滑条可以同时显示不同位置，不会退化成旧版共同游标。
		if visual.has_method("set_gameplay_snapshot"):
			visual.call("set_gameplay_snapshot", gameplay_snapshot)
		else:
			# 自定义美术场景至少按单条 slider_state 工作，不接收旧共同游标。
			if not tuning_state.is_empty() and visual.has_method("set_slider_state"):
				visual.call("set_slider_state", tuning_state)
	elif kind == ChartScheduler.KIND_RAPID:
		visual.position = approach_origin
		if visual.has_method("set_approach_timing"):
			visual.call("set_approach_timing", time_to_hit_sec, approach_duration_sec)
		if visual.has_method("set_region_progress"):
			visual.call("set_region_progress", region_progress)
		if visual.has_method("set_rapid_ratio"):
			visual.call("set_rapid_ratio", float(gameplay_snapshot.get("rapid_ratio", 0.0)))

	if is_instance_valid(timing_ring):
		# 圆环只认绝对剩余时间，因此回退、暂停和不同帧率会得到同一画面。
		# Hold 头被接受后，持续环固定在中心；灵体继续移动和缩短，也不会把视线从双键阅读区拉走。
		if is_hold and hold_active:
			var affinity: int = int(data.get("affinity", GameplayTypes.Affinity.ZHU))
			timing_ring.position = death_target if affinity == GameplayTypes.Affinity.XUAN else life_target
			if timing_ring.has_method("set_radius_offset"):
				# 生死 Hold 共用中心时改用两条同心持续环，避免互相遮挡。
				timing_ring.call("set_radius_offset", 10.0 if affinity == GameplayTypes.Affinity.XUAN else -10.0)
		else:
			timing_ring.position = visual.position
			if timing_ring.has_method("set_radius_offset"):
				timing_ring.call("set_radius_offset", 0.0)
		timing_ring.rotation = 0.0
		if is_hold and hold_active and timing_ring.has_method("set_sustain_progress"):
			timing_ring.call("set_sustain_progress", region_progress)
		elif timing_ring.has_method("set_timing"):
			timing_ring.call("set_timing", time_to_hit_sec, approach_duration_sec)
		elif timing_ring.has_method("set_approach_progress"):
			# 自定义美术场景可能只提供旧版进度接口，因此在这里兼容回退。
			timing_ring.call("set_approach_progress", approach)


func _pin_hold_visual(entry: Dictionary) -> void:
	## 第一次接受头判时固定当前视觉路线坐标；续按不更换锚点。
	if entry.has("hold_anchor_distance") or bool(entry.get("hold_failed", false)):
		return
	var data: Dictionary = entry["data"]
	var visual: Node2D = entry["node"]
	var approach: float = maxf(1.0 + (visual_time_sec - float(_start_usec(data)) / 1_000_000.0) / approach_duration_sec, 0.0)
	entry["hold_anchor_distance"] = approach * _approach_distance_px(data)
	entry["hold_anchor_rotation"] = _sample_approach_tangent(data, approach).angle() if orient_notes_along_path else 0.0
	# 命中后头身尾完整显露；后续不再用进场缩放覆盖命中反馈。
	visual.call("set_approach_progress", 1.0)


func _update_hold_visual(
		event_id: String, entry: Dictionary, approach: float, region_progress: float,
		hold_active: bool, hold_held: bool
) -> void:
	## 独立推进 Hold 的固定、宽限冻结和失败续行，不改变领域判定。
	var visual: Node2D = entry["node"]
	var data: Dictionary = entry["data"]
	var failed: bool = bool(entry.get("hold_failed", false))
	var finished: bool = bool(entry.get("hold_finished", false))
	if hold_active and not failed:
		_pin_hold_visual(entry)
	var pinned: bool = entry.has("hold_anchor_distance")
	var route_length: float = _approach_distance_px(data)
	var distance: float = approach * route_length
	if pinned:
		distance = float(entry["hold_anchor_distance"])
		if failed:
			distance += maxf(visual_time_sec - float(entry["hold_resume_time"]), 0.0) * route_length / approach_duration_sec
		visual.rotation = float(entry["hold_anchor_rotation"])
	else:
		visual.call("set_approach_progress", approach)
	if not pinned or failed:
		visual.rotation = _sample_approach_tangent(data, distance / maxf(route_length, 0.001)).angle() if orient_notes_along_path else 0.0
	var affinity: int = int(data.get("affinity", GameplayTypes.Affinity.ZHU))
	visual.position = _sample_route_distance(affinity, distance)
	var consumed: float = float(entry.get("hold_visual_progress", 0.0))
	if finished:
		consumed = 1.0
	elif hold_active and hold_held and not failed:
		consumed = maxf(consumed, region_progress)
	entry["hold_visual_progress"] = consumed
	visual.call("set_hold_progress", consumed)
	var state: Dictionary = visual.call("visual_state_snapshot")
	var remaining_length: float = float(state["visible_length"])
	if failed:
		var target: Vector2 = death_target if affinity == GameplayTypes.Affinity.XUAN else life_target
		var origin: Vector2 = death_wave_origin if affinity == GameplayTypes.Affinity.XUAN else life_wave_origin
		# 头部在钟位停止，之后按原路线速度从尾端裁短动态身体。
		remaining_length = maxf(remaining_length - maxf(distance - route_length - target.distance_to(origin), 0.0), 0.0)
		if remaining_length <= 0.0:
			_scheduler.finish_hold_visual(event_id)
			return
	visual.call("set_body_target", remaining_length, hold_active and not hold_held and not failed and not finished)


func _active_tuning_slider_state(event_id: String) -> Dictionary:
	var raw_states: Variant = gameplay_snapshot.get("active_tuning_sliders", [])
	if raw_states is Dictionary:
		var states: Dictionary = raw_states
		if states.has(event_id) and states[event_id] is Dictionary:
			return states[event_id]
	if raw_states is Array:
		for value: Variant in raw_states:
			if value is not Dictionary:
				continue
			var state: Dictionary = value
			if str(state.get("event_id", state.get("id", ""))) == event_id:
				return state
	return {}


func _sample_approach_path(data: Dictionary, progress: float) -> Vector2:
	var affinity: int = int(data.get("affinity", GameplayTypes.Affinity.ZHU))
	var target: Vector2 = death_target if affinity == GameplayTypes.Affinity.XUAN else life_target
	var sampled_progress: float = maxf(progress, 0.0)
	var profile: Dictionary = _path_profile_for_affinity(affinity)
	# 用近似弧长采样曲线，音符经过急弯时也保持稳定可读的速度。
	if sampled_progress <= 1.0:
		return NoteApproachPath.point_at_ratio(profile, sampled_progress)
	# 音符越过共同落点仍未解决时，沿末端方向继续飞向对应钟；这段直线与玩法逻辑层的接触路径一致。
	var origin: Vector2 = death_wave_origin if affinity == GameplayTypes.Affinity.XUAN else life_wave_origin
	var post_cue_distance_px: float = (sampled_progress - 1.0) * NoteApproachPath.length(profile)
	return target.move_toward(origin, post_cue_distance_px)


func _sample_approach_tangent(data: Dictionary, progress: float) -> Vector2:
	var affinity: int = int(data.get("affinity", GameplayTypes.Affinity.ZHU))
	var target: Vector2 = death_target if affinity == GameplayTypes.Affinity.XUAN else life_target
	if progress < 1.0:
		return NoteApproachPath.tangent_at_ratio(_path_profile_for_affinity(affinity), maxf(progress, 0.0))
	var origin: Vector2 = death_wave_origin if affinity == GameplayTypes.Affinity.XUAN else life_wave_origin
	return (origin - target).normalized()


func _approach_distance_px(data: Dictionary) -> float:
	var affinity: int = int(data.get("affinity", GameplayTypes.Affinity.ZHU))
	return NoteApproachPath.length(_path_profile_for_affinity(affinity))


func _path_profile_for_affinity(affinity: int) -> Dictionary:
	var spawn: Vector2 = death_spawn if affinity == GameplayTypes.Affinity.XUAN else life_spawn
	var target: Vector2 = death_target if affinity == GameplayTypes.Affinity.XUAN else life_target
	var origin: Vector2 = death_wave_origin if affinity == GameplayTypes.Affinity.XUAN else life_wave_origin
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


func _sample_route_distance(affinity: int, route_distance_px: float) -> Vector2:
	var profile: Dictionary = _path_profile_for_affinity(affinity)
	var approach_length_px: float = NoteApproachPath.length(profile)
	if route_distance_px <= approach_length_px:
		var ratio: float = route_distance_px / maxf(approach_length_px, 0.001)
		return NoteApproachPath.point_at_ratio(profile, clampf(ratio, 0.0, 1.0))
	var target: Vector2 = death_target if affinity == GameplayTypes.Affinity.XUAN else life_target
	var origin: Vector2 = death_wave_origin if affinity == GameplayTypes.Affinity.XUAN else life_wave_origin
	return target.move_toward(origin, route_distance_px - approach_length_px)


func _snapshot_id_set_contains(key: StringName, event_id: String) -> bool:
	var values: Variant = gameplay_snapshot.get(key, [])
	if values is PackedStringArray:
		return (values as PackedStringArray).has(event_id)
	if values is Array:
		return (values as Array).has(event_id)
	return false


func _release_visual(event_id: String) -> void:
	if not _active.has(event_id):
		return
	var active_entry: Dictionary = _active[event_id]
	var visual: Node2D = active_entry["node"]
	var timing_ring: Node2D = active_entry.get("timing_ring") as Node2D
	var pool_key: StringName = active_entry["pool_key"]
	_active.erase(event_id)
	if visual.has_method("reset_for_pool"):
		visual.call("reset_for_pool")
	visual.modulate = Color.WHITE
	visual.z_index = 0
	if visual.get_parent() != _pool_root:
		visual.reparent(_pool_root)
	visual.visible = false
	var pool: Array = _pools.get(pool_key, [])
	pool.append(visual)
	_pools[pool_key] = pool
	if is_instance_valid(timing_ring):
		if timing_ring.has_method("reset_for_pool"):
			timing_ring.call("reset_for_pool")
		else:
			timing_ring.visible = false
			timing_ring.position = Vector2.ZERO
			timing_ring.rotation = 0.0
			timing_ring.scale = Vector2.ONE
			timing_ring.modulate = Color.WHITE
		if timing_ring.get_parent() != _pool_root:
			timing_ring.reparent(_pool_root)
		timing_ring.visible = false
		var ring_pool: Array = _pools.get(TIMING_RING_POOL_KEY, [])
		ring_pool.append(timing_ring)
		_pools[TIMING_RING_POOL_KEY] = ring_pool


func _acquire_visual(pool_key: StringName, scene: PackedScene) -> Node2D:
	var pool: Array = _pools.get(pool_key, [])
	if not pool.is_empty():
		var pooled: Node2D = pool.pop_back() as Node2D
		_pools[pool_key] = pool
		return pooled
	var instance: Node = scene.instantiate()
	if not instance is Node2D:
		instance.queue_free()
		push_error("Note visual scene root must inherit Node2D.")
		# 若素材场景的根节点不是 Node2D，则用灰盒音符兜底，避免整关无法运行。
		var fallback := GrayboxNoteVisual.new()
		_pool_root.add_child(fallback)
		return fallback
	_pool_root.add_child(instance)
	return instance as Node2D


func _acquire_timing_ring(scene: PackedScene) -> Node2D:
	var pool: Array = _pools.get(TIMING_RING_POOL_KEY, [])
	if not pool.is_empty():
		var pooled: Node2D = pool.pop_back() as Node2D
		_pools[TIMING_RING_POOL_KEY] = pool
		return pooled
	var instance: Node = scene.instantiate() if scene != null else null
	if not instance is Node2D or (not instance.has_method("set_timing") and not instance.has_method("set_approach_progress")):
		if instance != null:
			instance.queue_free()
		push_warning("Timing ring scene root must be Node2D and expose a timing progress method; using the default timing ring.")
		instance = DEFAULT_TIMING_RING_SCENE.instantiate()
	_pool_root.add_child(instance)
	return instance as Node2D


func _free_pooled_visuals() -> void:
	for pool_value: Variant in _pools.values():
		if not pool_value is Array:
			continue
		for candidate: Variant in pool_value:
			if candidate is Node and is_instance_valid(candidate):
				(candidate as Node).queue_free()
	_pools.clear()


func _scene_for(kind: StringName, data: Dictionary) -> PackedScene:
	if kind == ChartScheduler.KIND_TUNING:
		return visual_theme.tuning_scene if visual_theme != null and visual_theme.tuning_scene != null else DEFAULT_TUNING_SCENE
	if kind == ChartScheduler.KIND_RAPID:
		return visual_theme.rapid_scene if visual_theme != null and visual_theme.rapid_scene != null else DEFAULT_RAPID_SCENE
	if StringName(data.get("unit_kind", &"tap")) == &"hold":
		return visual_theme.hold_scene if visual_theme != null and visual_theme.hold_scene != null else DEFAULT_HOLD_SCENE
	var affinity: int = int(data.get("affinity", GameplayTypes.Affinity.ZHU))
	if visual_theme != null:
		if affinity == GameplayTypes.Affinity.XUAN and visual_theme.xuan_note_scene != null:
			return visual_theme.xuan_note_scene
		if affinity == GameplayTypes.Affinity.SU and visual_theme.su_note_scene != null:
			return visual_theme.su_note_scene
		if affinity == GameplayTypes.Affinity.ZHU and visual_theme.zhu_note_scene != null:
			return visual_theme.zhu_note_scene
	return DEFAULT_NOTE_SCENE


func _timing_ring_scene() -> PackedScene:
	if visual_theme != null and visual_theme.timing_ring_scene != null:
		return visual_theme.timing_ring_scene
	return DEFAULT_TIMING_RING_SCENE


func _slot_for(kind: StringName, data: Dictionary) -> Node2D:
	if kind == ChartScheduler.KIND_TUNING or kind == ChartScheduler.KIND_RAPID:
		return _field_slot
	return _death_note_slot if int(data.get("affinity", GameplayTypes.Affinity.ZHU)) == GameplayTypes.Affinity.XUAN else _life_note_slot


func _pool_key(kind: StringName, data: Dictionary) -> StringName:
	if kind != ChartScheduler.KIND_NOTE:
		return kind
	if StringName(data.get("unit_kind", &"tap")) == &"hold":
		return &"hold"
	return StringName("note_%d" % int(data.get("affinity", GameplayTypes.Affinity.ZHU)))


func _start_usec(data: Dictionary) -> int:
	return int(data.get("start_us", data.get("start_time_us", data.get("time_us", 0))))


func _end_usec(data: Dictionary) -> int:
	var start_usec: int = _start_usec(data)
	return int(data.get("end_us", data.get("end_time_us", start_usec + int(data.get("duration_us", 0)))))


func _disconnect_scheduler() -> void:
	if not is_instance_valid(_scheduler):
		_scheduler = null
		return
	if _scheduler.visual_spawn_requested.is_connected(_on_visual_spawn_requested):
		_scheduler.visual_spawn_requested.disconnect(_on_visual_spawn_requested)
	if _scheduler.visual_despawn_requested.is_connected(_on_visual_despawn_requested):
		_scheduler.visual_despawn_requested.disconnect(_on_visual_despawn_requested)
	if _scheduler.visual_judged.is_connected(_on_visual_judged):
		_scheduler.visual_judged.disconnect(_on_visual_judged)
	if _scheduler.visual_timing_confirmed.is_connected(_on_visual_timing_confirmed):
		_scheduler.visual_timing_confirmed.disconnect(_on_visual_timing_confirmed)
	if _scheduler.visual_wave_contacted.is_connected(_on_visual_wave_contacted):
		_scheduler.visual_wave_contacted.disconnect(_on_visual_wave_contacted)
	if _scheduler.visual_note_arrived.is_connected(_on_visual_note_arrived):
		_scheduler.visual_note_arrived.disconnect(_on_visual_note_arrived)
	if _scheduler.scheduler_reset.is_connected(clear):
		_scheduler.scheduler_reset.disconnect(clear)
	_scheduler = null
