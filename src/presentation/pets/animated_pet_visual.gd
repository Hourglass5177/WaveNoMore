extends PetVisual
## 正式关卡与审看共用的随从播放器，只消费时间与表现事件。
@export var animation_id: String = ""
@export_range(0.0, 1.0, 0.01) var death_brightness := 0.65
@export_range(0.0, 1.0, 0.01) var death_desaturation := 1.0
const FOLDER := "res://assets/pets/animation_studies/"
const HIGHLIGHT := preload("res://shaders/characters/pet_study_highlight.gdshader")
const ASH_SHADER := preload("res://shaders/characters/pet_study_ashes.gdshader")
var config: Dictionary
var skeleton: SpineSprite
var ashes: MeshInstance2D
var breath: Node2D
var trigger_lights: Node2D
var events: Array[Dictionary] = []
var sampled_time := 0.0
var death_started := INF
var _event_cursor := 0
var _end_trigger := INF
var _dirty := true
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
		breath = load("res://src/presentation/pets/snake_breath.gd").new()
		add_child(breath)
		move_child(breath,0)
		breath.setup(skeleton,config.breath)
	if config.has("chest") or config.has("eyes"):
		trigger_lights = load("res://src/presentation/pets/pet_trigger_lights.gd").new()
		add_child(trigger_lights)
		trigger_lights.setup(skeleton,config,FOLDER+id+"/")
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
	_dirty = true
	sample(0.0)

## 再次触发不重启当前动作；向过去定位后新增事件会替换其后的审看历史。
func trigger(time: float) -> bool:
	_truncate_future(time)
	if not events.is_empty():
		var event: Dictionary = events.back()
		if event.kind == "death": return false
		if time < float(event.time) + float(config.trigger): return false
	events.append({"time": time, "kind": "trigger"})
	if time <= sampled_time: _dirty = true
	return true

func die(time: float) -> void:
	_truncate_future(time)
	if not events.is_empty() and events.back().kind == "death": return
	# 同刻死亡直接取代技能，不保留一个零时长的技能混合。
	if not events.is_empty() and float(events.back().time) == time: events.pop_back()
	events.append({"time": time, "kind": "death"})
	if time <= sampled_time: _dirty = true

func _truncate_future(time: float) -> void:
	while not events.is_empty() and float(events.back().time) > time:
		events.pop_back()
		_dirty = true

func bind(_pet: PetDefinition, _advanced: bool) -> void:
	setup(animation_id)

func _draw() -> void:
	pass

func set_state(song_time: float) -> void:
	sample(song_time)

func set_world(side: int) -> void:
	super.set_world(side)
	var gray := death_desaturation if side==GameplayTypes.Affinity.XUAN else 0.0
	var brightness := death_brightness if side==GameplayTypes.Affinity.XUAN else 1.0
	var surfaces: Array[ShaderMaterial] = [_surface]
	if ashes!=null: surfaces.append(ashes.material)
	if breath!=null:
		for flame in breath.flames: surfaces.append(flame.material)
	if trigger_lights!=null: surfaces.append_array(trigger_lights.surfaces)
	for surface in surfaces:
		surface.set_shader_parameter("world_gray",gray)
		surface.set_shader_parameter("world_brightness",brightness)

func _reset_playback(start: float) -> void:
	death_started = INF
	_event_cursor = 0
	_end_trigger = INF
	sampled_time = start
	skeleton.show()
	var state = skeleton.get_animation_state()
	state.clear_tracks()
	skeleton.get_skeleton().set_to_setup_pose()
	skeleton.get_skeleton().set_color(Color.WHITE)
	var idle = state.set_animation("idle",true,0)
	idle.set_mix_duration(0.0)
	idle.set_track_time(fposmod(start, float(config.idle)))
	skeleton.update_skeleton(0.0)
	_dirty = false

## 正向只推进新增时间；回拖或编辑历史才重演。正式会话定位会先重置再发送领域事件。
func sample(time: float) -> void:
	var target := time
	if _dirty or target<sampled_time:
		# 倒计时也按同一个常态相位推进，负时间的有效起手仍保留原始时间戳。
		var start := minf(target, 0.0)
		if not events.is_empty(): start = minf(start, float(events[0].time))
		_reset_playback(start)
	skeleton.show()
	var state = skeleton.get_animation_state()
	while _event_cursor<events.size():
		var event: Dictionary = events[_event_cursor]
		var at := float(event.time)
		if at>target: break
		_advance(sampled_time,at,_end_trigger)
		var entry = state.set_animation(str(event.kind),false,0)
		entry.set_mix_duration(.12 if event.kind=="death" else .08)
		skeleton.update_skeleton(0.0)
		sampled_time = at
		_end_trigger = at+float(config.trigger) if event.kind=="trigger" else INF
		if event.kind=="death": death_started = at
		_event_cursor += 1
	_advance(sampled_time,target,_end_trigger)
	sampled_time = target
	var track = state.get_track(0)
	# 光效直接用歌曲时间减事件时间，不读取 Spine 浮点累加的轨道年龄。
	var trigger_age: float = target-float(events[_event_cursor-1].time) if track.get_animation().get_name()=="trigger" else -1.0
	_sample_trigger_vfx(trigger_age)
	_update_ashes(target-death_started if is_finite(death_started) else -1.0)

func _sample_trigger_vfx(age: float) -> void:
	var envelope: Array = config.glow_envelope
	var glow := smoothstep(envelope[0],envelope[1],age)*(1.0-smoothstep(envelope[2],envelope[3],age)) if age>=0.0 else 0.0
	_surface.set_shader_parameter("amount",glow)
	if breath!=null: breath.sample(age)
	if trigger_lights!=null: trigger_lights.sample(age,glow)

func _advance(from: float, to: float, end_trigger: float) -> void:
	if end_trigger >= from and end_trigger <= to:
		_step(end_trigger - from)
		var idle = skeleton.get_animation_state().set_animation("idle", true, 0)
		idle.set_mix_duration(0.08)
		idle.set_track_time(fposmod(end_trigger, float(config.idle)))
		_step(to - end_trigger)
		_end_trigger = INF
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
	_dirty = true
	skeleton.show()
	var state = skeleton.get_animation_state()
	state.clear_tracks()
	skeleton.get_skeleton().set_to_setup_pose()
	skeleton.get_skeleton().set_color(Color.WHITE)
	state.set_animation(clip, clip == "idle", 0).set_track_time(time)
	skeleton.update_skeleton(0.0)
	_sample_trigger_vfx(time if clip=="trigger" else -1.0)
	_update_ashes(time if clip == "death" else -1.0)
