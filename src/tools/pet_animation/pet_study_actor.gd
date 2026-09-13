extends Node2D
## 审看用随从。时间与事件均由调用方提供，未接入正式 PetDefinition。
const FOLDER := "res://assets/pets/animation_studies/"
const HIGHLIGHT := preload("res://shaders/characters/pet_study_highlight.gdshader")
const ASH_SHADER := preload("res://shaders/characters/pet_study_ashes.gdshader")
var config: Dictionary
var skeleton: SpineSprite
var ashes: MeshInstance2D
var breath: Node2D
var events: Array[Dictionary] = []
var sampled_time := 0.0
var death_started := -1.0
var _surface: ShaderMaterial

func setup(id: String) -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string(FOLDER + id + "/animation.json"))
	skeleton = SpineSprite.new()
	skeleton.skeleton_data_res = load(FOLDER + id + "/pet.tres")
	skeleton.scale = Vector2.ONE * float(config.unit_scale)
	add_child(skeleton)
	skeleton.set_update_mode(SpineConstant.UpdateMode_Manual)
	_surface = ShaderMaterial.new()
	_surface.shader = HIGHLIGHT
	_surface.set_shader_parameter("pet_kind", ["bat", "snake", "sheep"].find(id))
	if config.has("highlight_region"):
		var rect: Array = config.highlight_region
		_surface.set_shader_parameter("detail_region", Vector4(rect[0],rect[1],rect[2],rect[3]))
	skeleton.normal_material = _surface
	if config.has("breath"):
		breath = load("res://src/tools/pet_animation/snake_breath.gd").new()
		add_child(breath)
		move_child(breath,0)
		breath.setup(skeleton,config.breath)
	var path := FOLDER + id + "/death_pose.png"
	if ResourceLoader.exists(path):
		ashes = MeshInstance2D.new()
		ashes.texture = load(path)
		ashes.mesh = NoteFragmentHost._template(Vector2(512, 512), 24, 24)
		ashes.scale = Vector2.ONE * 0.25
		var material := ShaderMaterial.new()
		material.shader = ASH_SHADER
		ashes.material = material
		add_child(ashes)
		ashes.hide()
	sample(0.0)

func clear_events() -> void:
	events.clear()
	sample(0.0)

## 再次触发不重启当前动作；向过去定位后新增事件会替换其后的审看历史。
func trigger(time: float) -> bool:
	_truncate_future(time)
	for event: Dictionary in events:
		if event.kind == "death": return false
		if time >= float(event.time) and time < float(event.time) + float(config.trigger): return false
	events.append({"time": time, "kind": "trigger"})
	return true

func die(time: float) -> void:
	_truncate_future(time)
	for event: Dictionary in events:
		if event.kind == "death": return
	events.append({"time": time, "kind": "death"})

func _truncate_future(time: float) -> void:
	while not events.is_empty() and float(events.back().time) > time: events.pop_back()

## 从最近的关键事件重建轨道混合；无物理约束，不依赖此前采样帧数。
func sample(time: float) -> void:
	sampled_time = maxf(time, 0.0)
	death_started = -1.0
	# 隐藏的 SpineSprite 不更新网格，回拖和重置先恢复本次采样资格。
	skeleton.show()
	var state = skeleton.get_animation_state()
	state.clear_tracks()
	skeleton.get_skeleton().set_to_setup_pose()
	skeleton.get_skeleton().set_color(Color.WHITE)
	state.set_animation("idle", true, 0).set_mix_duration(0.0)
	skeleton.update_skeleton(0.0)
	var cursor := 0.0
	var end_trigger := -1.0
	for event: Dictionary in events:
		var at := float(event.time)
		if at > sampled_time: break
		_advance(cursor, at, end_trigger)
		var entry = state.set_animation(str(event.kind), false, 0)
		entry.set_mix_duration(0.12 if event.kind == "death" else 0.08)
		skeleton.update_skeleton(0.0)
		cursor = at
		end_trigger = at + float(config.trigger) if event.kind == "trigger" else -1.0
		if event.kind == "death":
			death_started = at
			break
	_advance(cursor, sampled_time, end_trigger)
	var track = state.get_track(0)
	var glow := 0.0
	var trigger_age := -1.0
	if track.get_animation().get_name() == "trigger":
		var age: float = track.get_track_time()
		trigger_age = age
		glow = smoothstep(0.08, 0.20, age) * (1.0 - smoothstep(0.22, float(config.trigger), age))
	_surface.set_shader_parameter("amount", glow)
	if breath != null: breath.sample(trigger_age)
	_update_ashes(sampled_time - death_started if death_started >= 0.0 else -1.0)

func _advance(from: float, to: float, end_trigger: float) -> void:
	if end_trigger >= from and end_trigger <= to:
		_step(end_trigger - from)
		var idle = skeleton.get_animation_state().set_animation("idle", true, 0)
		idle.set_mix_duration(0.08)
		idle.set_track_time(end_trigger)
		_step(to - end_trigger)
	else:
		_step(to - from)
	skeleton.update_skeleton(0.0)

func _step(seconds: float) -> void:
	# Spine 的嵌套角度混合会记住旋转方向。只在短混合段细步推进，
	# 让直接定位与连续播放采用相同方向；纯动画段仍直接跳到目标时间。
	var remaining := seconds
	var track = skeleton.get_animation_state().get_track(0)
	while remaining > 0.0 and track.get_mixing_from() != null:
		var step := minf(remaining,1.0/120.0)
		skeleton.update_skeleton(step)
		remaining -= step
	if remaining > 0.0: skeleton.update_skeleton(remaining)

func _update_ashes(age: float) -> void:
	if ashes == null: return
	ashes.visible = age >= 1.4 and age < 2.05
	(ashes.material as ShaderMaterial).set_shader_parameter("age", maxf(age - 1.4, 0.0))
	# Spine 已在本次采样中提交绘制网格；节点可见性立即生效，不滞后一帧。
	skeleton.visible = age < 1.4

## 离线图集按独立动画采样，零帧保持原画基准，运行时预览另验过渡。
func sample_clip(clip: String, time: float) -> void:
	skeleton.show()
	var state = skeleton.get_animation_state()
	state.clear_tracks()
	skeleton.get_skeleton().set_to_setup_pose()
	skeleton.get_skeleton().set_color(Color.WHITE)
	state.set_animation(clip, clip == "idle", 0).set_track_time(time)
	skeleton.update_skeleton(0.0)
	_surface.set_shader_parameter("amount", smoothstep(.08, .20, time) * (1-smoothstep(.22, float(config.trigger), time)) if clip == "trigger" else 0.0)
	if breath != null: breath.sample(time if clip=="trigger" else -1.0)
	_update_ashes(time if clip == "death" else -1.0)
