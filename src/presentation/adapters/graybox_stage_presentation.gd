class_name GrayboxStagePresentation
extends Node2D

## 关卡表现总装配器。把主题资源放入预留槽位，并把时钟与玩法事件分发给各表现组件。

## 每次玩法逻辑发出声波时触发；affinity 指明生钟或死钟，供角色敲击动画使用。
signal bell_struck(affinity: int)

@export_group("Scene Wiring")
## 灰盒底图节点路径；负责水平分界、占位角色和关卡整体状态。
@export var backdrop_path: NodePath = ^"Backdrop"
## 生界正式场景的挂载槽路径，位于上半画面。
@export var life_world_slot_path: NodePath = ^"BackgroundBase/WorldPair/LifeWorldSlot"
## 死界正式场景的挂载槽路径，位于下半画面并与生界中心对称。
@export var death_world_slot_path: NodePath = ^"BackgroundBase/WorldPair/DeathWorldSlot"
## 生者角色与生钟素材的挂载槽路径。
@export var life_actor_slot_path: NodePath = ^"ActorLayer/LifeActorSlot"
## 死者角色与死钟素材的挂载槽路径。
@export var death_actor_slot_path: NodePath = ^"ActorLayer/DeathActorSlot"
## 正式生死分界素材的挂载槽路径；为空时由 Backdrop 画水平线。
@export var boundary_slot_path: NodePath = ^"BoundarySlot"
## 双钟持续载波节点路径；任意一钟按住即可成波，双钟相叠才形成骨白相纹。
@export var tuning_interference_visual_path: NodePath = ^"WaveLayer/TuningInterferenceVisual"
## 疾振波包 Shader 节点路径，只接收有效疾振敲击。
@export var rapid_interference_visual_path: NodePath = ^"WaveLayer/RapidInterferenceVisual"
## 一般声波节点路径，显示普通红/黑波、无效灰波及红黑交叠的骨白点。
@export var wave_field_visual_path: NodePath = ^"WaveLayer/WaveFieldVisual"
## 音符、Hold、调频槽、疾振提示和对象池所在节点路径。
@export var note_visual_host_path: NodePath = ^"GameplayLayer/NoteVisualHost"
## 共同中心落点、路线提示和短暂判定印记所在节点路径。
@export var twin_gate_cue_visual_path: NodePath = ^"CueCanvas/GameplayCueLayer/TwinGateCueVisual"
## StageShow 演出事件接收节点路径；灰盒实现会画教学和简化闪光。
@export var show_cue_host_path: NodePath = ^"CueCanvas/ShowCueHost"

# 当前关卡定义用于读取歌曲、规则和视觉主题。
var stage_definition: StageDefinition
## 本关视差与配置动画的共享控制中心。
@onready var parallax_controller: ParallaxController = $ParallaxController
@onready var _background_base: CanvasLayer = $BackgroundBase
@onready var _cue_canvas: CanvasLayer = $CueCanvas
@onready var _judgment_canvas: CanvasLayer = $CueCanvas/GameplayCueLayer
@onready var _distortion: WaveDistortionVisual = $WaveDistortion
@onready var _tutorial_canvas: CanvasLayer = $CueCanvas/ShowCueHost/TutorialCanvas

## Tap/Hold 音符槽不随模拟摄像头移动；音符自身路线和身体动画照常推进。
const NOTE_PARALLAX_DEPTH: int = 0

@export_group("Parallax Camera")
## 试验开关：叠加手持晃动；关闭不影响主题配置的持续移动。
@export var handheld_camera_enabled: bool = true

@export_group("Actor Rhythm")
## 3 Hz 发波对应原速，每增减 1 Hz 只改变 0.15 倍敲击速度。
@export var attack_reference_hz: float = 3.0
@export var attack_rate_per_hz: float = 0.15
@export var attack_min_rate: float = 0.65
@export var attack_max_rate: float = 1.65
@export var attack_release_mix_sec: float = 0.1
## 重按只短暂接续旧姿势；过长混合会遮掉右侧向下砸的动作。
@export var attack_restart_mix_sec: float = 0.025
## 点按与长按共用敲击上限；多余输入照常判定，不积压角色动作。
@export var attack_max_strikes_per_sec: float = 2.0

# 以下引用在 _ready() 中按上面的路径取得，集中负责主题装配和事件转发。
var _backdrop: GrayboxBackdrop
# 生界美术内容的挂载槽，位于水平分界线上方。
var _life_world_slot: Node2D
# 死界美术内容的挂载槽，位于水平分界线下方。
var _death_world_slot: Node2D
# 生者角色素材的挂载槽；角色位于左上并朝共同中心行动。
var _life_actor_slot: Node2D
# 死者角色素材的挂载槽；角色位于右下并朝共同中心行动。
var _death_actor_slot: Node2D
## 保留角色实例引用，不依赖视差注册之后的父节点位置。
var _life_actor: Node
var _death_actor: Node
var _actor_bells: Dictionary[Node, BellVisual] = {}
var _life_attacking := false
var _death_attacking := false
## 写谱预览由歌曲时间推进角色，暂停与分批重演不使用墙钟时间。
var _preview_time_driven := false
var _preview_actor_time_sec := -INF
var _actor_snapshot_time_sec := -INF
## 新增伤害按领域时间排队，在下一次动作快照中先推进到事件边界再播放。
var _actor_events: Array[Dictionary] = []
var _locomotion: ActorLocomotion
var _locomotion_environment: StageEnvironmentSequence
# 水平生死分界线素材的挂载槽。
var _boundary_slot: Node2D
# 调频期间持续发波并生成相纹的表现节点。
var _tuning_interference_visual: TuningInterferenceVisual
# 双钟疾振期间用实体高速波纹生成相纹的表现节点。
var _rapid_interference_visual: RapidInterferenceVisual
# 普通敲钟波前的表现与屏幕内接触检测节点。
var _wave_field_visual: WaveFieldVisual
# 管理音符、Hold、区域提示和判定环实例的表现宿主。
var _note_visual_host: NoteVisualHost
# 在共同中心落点附近绘制生死输入门和接触提示的节点。
var _twin_gate_cue_visual: TwinGateCueVisual
# 播放教学文字、闪光等谱面演出指令的节点。
var _show_cue_host: Node2D
# 歌曲时长以秒保存，用来把 SongClock 时间换成 0～1 的分界线进度。
var _song_duration_sec: float = 1.0
# 运行中的时钟和会话只在 bind() 后有效；设置服务用于响应视觉频率选项变化。
var _clock: SongClock
# 当前关卡会话；表现层只读取其时间和结果，不自行决定判定。
var _session: StageSession
# 全局设置服务；在这里读取玩家可调的波纹显示参数。
var _settings_service: Node
# 试验用手持晃动驱动；纯函数式，只读取绝对歌曲时间。
var _handheld_camera: ParallaxHandheldDriver


func _ready() -> void:
	set_notify_transform(true)
	_sync_canvas_layers()
	preload("res://src/presentation/vfx/note_effect_warmup.gd").prepare(self)
	_backdrop = get_node(backdrop_path) as GrayboxBackdrop
	_life_world_slot = get_node(life_world_slot_path) as Node2D
	_death_world_slot = get_node(death_world_slot_path) as Node2D
	_life_actor_slot = get_node(life_actor_slot_path) as Node2D
	_death_actor_slot = get_node(death_actor_slot_path) as Node2D
	_boundary_slot = get_node(boundary_slot_path) as Node2D
	_tuning_interference_visual = get_node(tuning_interference_visual_path) as TuningInterferenceVisual
	_distortion.bind(_tuning_interference_visual)
	_rapid_interference_visual = get_node(rapid_interference_visual_path) as RapidInterferenceVisual
	_wave_field_visual = get_node(wave_field_visual_path) as WaveFieldVisual
	_note_visual_host = get_node(note_visual_host_path) as NoteVisualHost
	_twin_gate_cue_visual = get_node(twin_gate_cue_visual_path) as TwinGateCueVisual
	_show_cue_host = get_node(show_cue_host_path) as Node2D
	_settings_service = get_node_or_null("/root/SettingsService")
	_handheld_camera = ParallaxHandheldDriver.new()
	_apply_visual_settings()
	var callback := Callable(self, "_on_settings_changed")
	if is_instance_valid(_settings_service) and not _settings_service.is_connected(&"settings_changed", callback):
		_settings_service.connect(&"settings_changed", callback)


func _exit_tree() -> void:
	_disconnect_sources()
	var callback := Callable(self, "_on_settings_changed")
	if is_instance_valid(_settings_service) and _settings_service.is_connected(&"settings_changed", callback):
		_settings_service.disconnect(&"settings_changed", callback)
	_settings_service = null


func configure(stage: StageDefinition) -> void:
	# 换关前归还角色，随后由原槽位清理，避免运行时挂载对象残留。
	for actor in _parallax_actors:
		if is_instance_valid(actor):
			parallax_controller.unregister_object(actor)
	_parallax_actors.clear()
	_actor_bells.clear()
	_life_actor = null
	_death_actor = null
	_life_attacking = false
	_death_attacking = false
	stage_definition = stage
	_clear_slot(_life_world_slot)
	_clear_slot(_death_world_slot)
	_clear_slot(_life_actor_slot)
	_clear_slot(_death_actor_slot)
	_clear_slot(_boundary_slot)

	var visual_theme: StageVisualTheme = stage.visual_theme if stage != null else null
	_note_visual_host.configure_theme(visual_theme)
	_note_visual_host.configure_rules(stage.rule_set if stage != null else null)
	if stage != null and stage.rule_set != null:
		# 调度器、音符路径、圆环和波碰撞计算必须共用同一提前量与坐标，
		# 否则“看见的相遇”会偏离程序算出的接触时刻。
		var rules: GameplayRuleSet = stage.rule_set
		_note_visual_host.approach_duration_sec = rules.approach_duration_sec
		_note_visual_host.life_spawn = rules.life_note_spawn
		_note_visual_host.death_spawn = rules.death_note_spawn
		_note_visual_host.life_target = rules.life_note_cue
		_note_visual_host.death_target = rules.death_note_cue
		_note_visual_host.life_wave_origin = rules.life_wave_origin
		_note_visual_host.death_wave_origin = rules.death_wave_origin
		_note_visual_host.curve_outer_bend_px = rules.note_curve_outer_bend_px
		_note_visual_host.curve_center_handle_px = rules.note_curve_center_handle_px
		_tuning_interference_visual.configure_from_rules(rules)
		_rapid_interference_visual.configure_from_rules(rules)
		_wave_field_visual.canvas_size = rules.wave_canvas_size
		_twin_gate_cue_visual.configure_from_rules(rules)
		_backdrop.canvas_size = rules.wave_canvas_size
		_backdrop.life_bell_origin = rules.life_wave_origin
		_backdrop.death_bell_origin = rules.death_wave_origin
	_backdrop.set_placeholder_visibility(
		visual_theme == null or visual_theme.boundary_scene == null,
		visual_theme == null or visual_theme.life_actor_scene == null,
		visual_theme == null or visual_theme.death_actor_scene == null
	)
	if visual_theme != null:
		# 正式美术以 PackedScene 填入固定槽位；死界缺省时复用生界，再由场景节点旋转 180 度。
		_apply_palette(visual_theme)
		_instance_if_present(visual_theme.life_world_scene, _life_world_slot)
		_instance_if_present(
			visual_theme.death_world_scene if visual_theme.death_world_scene != null else visual_theme.life_world_scene,
			_death_world_slot
		)
		_life_actor = _instance_if_present(visual_theme.life_actor_scene, _life_actor_slot)
		_instance_if_present(visual_theme.life_bell_scene, _life_actor_slot)
		_death_actor = _instance_if_present(visual_theme.death_actor_scene, _death_actor_slot)
		_instance_if_present(visual_theme.death_bell_scene, _death_actor_slot)
		for actor in [_life_actor, _death_actor]:
			if not actor is Node2D: continue
			actor.position.x += visual_theme.actor_shift_px
			var bell := actor.get_node_or_null("Bell") as BellVisual
			if bell != null:
				bell.inset(visual_theme.bell_inset_px)
				bell.configure(GameplayTypes.Affinity.ZHU if actor == _life_actor else GameplayTypes.Affinity.XUAN,
					visual_theme.bell_float_height_px, visual_theme.bell_glow_strength)
				_actor_bells[actor] = bell
		_apply_lingjun_tint(_life_actor, visual_theme.life_lingjun_target_color, visual_theme.life_lingjun_color_strength)
		_apply_lingjun_tint(_death_actor, visual_theme.death_lingjun_target_color, visual_theme.death_lingjun_color_strength)
		_instance_if_present(visual_theme.boundary_scene, _boundary_slot)
	_reset_preview_actors()

	_song_duration_sec = _calculate_song_duration_sec()


## 在 configure 清空旧主题之后装配；随从锚点继承角色的生死变换。
func configure_pet(pet: PetDefinition, advanced: bool) -> Array[PetVisual]:
	var views: Array[PetVisual] = []
	if pet == null:
		return views
	for slot in [_life_actor_slot, _death_actor_slot]:
		var anchor := Node2D.new()
		anchor.name = "PetAnchor"
		anchor.position = pet.world_offset
		anchor.scale = Vector2.ONE * pet.world_scale
		if stage_definition != null and stage_definition.visual_theme != null:
			anchor.position.x += stage_definition.visual_theme.pet_shift_px
			anchor.scale *= stage_definition.visual_theme.pet_scale_multiplier
		slot.add_child(anchor)
		var scene := pet.visual_scene(advanced)
		var view := scene.instantiate() as PetVisual if scene != null else PetVisual.new()
		anchor.add_child(view)
		view.bind(pet, advanced)
		view.set_world(GameplayTypes.Affinity.ZHU if slot == _life_actor_slot else GameplayTypes.Affinity.XUAN)
		views.append(view)
	return views


func bind(clock: SongClock, session: StageSession, scheduler: ChartScheduler, _input_buffer: Node) -> void:
	_disconnect_sources()
	_clock = clock
	_session = session
	if not session.gameplay_coordinator.damage_recorded.is_connected(_queue_actor_damage):
		session.gameplay_coordinator.damage_recorded.connect(_queue_actor_damage)
	if not session.waves_reset.is_connected(_tuning_interference_visual.clear):
		session.waves_reset.connect(_tuning_interference_visual.clear)
	if not session.waves_reset.is_connected(_reset_preview_actors):
		session.waves_reset.connect(_reset_preview_actors)
	_note_visual_host.bind_scheduler(scheduler)
	_wave_field_visual.bind(clock, session)
	_rapid_interference_visual.bind(clock, session)
	_twin_gate_cue_visual.bind(clock, session)
	if not clock.sample_published.is_connected(_on_clock_sample):
		clock.sample_published.connect(_on_clock_sample)
	if not session.gameplay_snapshot_changed.is_connected(_on_gameplay_snapshot):
		session.gameplay_snapshot_changed.connect(_on_gameplay_snapshot)
	if not session.visual_frame_ready.is_connected(_on_visual_frame_ready):
		session.visual_frame_ready.connect(_on_visual_frame_ready)
	if not session.state_changed.is_connected(_on_stage_state_changed):
		session.state_changed.connect(_on_stage_state_changed)
	if not session.wave_launched.is_connected(_on_wave_launched):
		session.wave_launched.connect(_on_wave_launched)


func bind_show_director(director: Node) -> void:
	_show_cue_host.call("bind", director)


func clear() -> void:
	_reset_preview_actors()
	_note_visual_host.clear()
	_tuning_interference_visual.clear()
	_rapid_interference_visual.clear()
	_wave_field_visual.clear()
	_twin_gate_cue_visual.clear()
	_show_cue_host.call("clear")
	_backdrop.set_song_progress(0.0)
	_backdrop.set_soul_fire_ratio(1.0)
	_backdrop.set_failed(false)


func set_song_duration(duration_sec: float) -> void:
	_song_duration_sec = maxf(duration_sec, 0.001)


func _on_clock_sample(sample: ClockSample) -> void:
	_backdrop.set_song_progress(sample.song_time_sec / maxf(_song_duration_sec, 0.001))

func set_preview_time_driven() -> void:
	_preview_time_driven = true
	_note_visual_host.preview_time_driven = true
	_reset_preview_actors()


func restore_preview_motion(snapshot: Dictionary, sample: ClockSample) -> void:
	## 保留身体恢复的状态→目标→积分顺序；历史中间帧无需刷新 HUD、背景与相纹。
	_note_visual_host.restore_preview_motion(snapshot, sample)
	_update_actor_snapshot(snapshot)


func _on_visual_frame_ready(sample: ClockSample) -> void:
	## Gameplay 写入当前目标后推进身体；原始时钟信号仅设置视觉目标。
	_note_visual_host.set_clock_sample(sample)
	_note_visual_host.flush_hold_geometry()
	_tuning_interference_visual.set_frame(sample, _pending_wave_snapshot)
	if parallax_controller.environment != null: return
	parallax_controller.set_song_time(sample.song_time_sec)
	var camera_position := Vector2.ZERO
	if stage_definition != null and stage_definition.visual_theme != null:
		camera_position = stage_definition.visual_theme.camera_velocity * maxf(sample.song_time_sec, 0.0)
	if handheld_camera_enabled:
		camera_position += _handheld_camera.offset_at(sample.song_time_sec)
	parallax_controller.set_camera_position(camera_position)

## 环境安排只看稳定演出镜头；手持晃动由共用采样入口最后叠加。
func environment_camera_offset(song_seconds:float) -> Vector2:
	return _handheld_camera.offset_at(song_seconds) if handheld_camera_enabled else Vector2.ZERO


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_node_ready():
		_sync_canvas_layers()


func _sync_canvas_layers() -> void:
	# CanvasLayer 不继承父节点变换；底图与提示层都手动跟随表现根画布，
	# 屏幕震动、缩放和视差摄像头的变换才能一致作用。
	var pose := get_global_transform_with_canvas()
	_background_base.transform = pose
	_cue_canvas.transform = pose
	_judgment_canvas.transform = pose
	_distortion.sync_transform(pose)
	_tutorial_canvas.transform = pose


## 把生、死 Tap/Hold 音符槽注册进静止的深度 0 层。先装配背景，同深度音符在后绘制；
## 负深度装饰仍位于其前方，换关 clear 后自动归还原父节点。
var _parallax_actors: Array[Node2D] = []


## 附属编钟跟随角色进入视差层；随从和独立编钟场景继续保留在原槽位。
func attach_actors_to_parallax() -> void:
	if stage_definition == null or stage_definition.visual_theme == null or not stage_definition.visual_theme.actors_in_parallax:
		return
	for actor in [_life_actor, _death_actor]:
		if actor is Node2D and not _parallax_actors.has(actor):
			if parallax_controller.register_object(actor, 0, false, "actors"):
				_parallax_actors.append(actor)


func attach_notes_to_parallax() -> void:
	if _note_visual_host == null:
		return
	for slot_path: NodePath in [_note_visual_host.life_note_slot_path, _note_visual_host.death_note_slot_path]:
		var slot := _note_visual_host.get_node_or_null(slot_path) as Node2D
		if slot != null:
			parallax_controller.register_object(slot, NOTE_PARALLAX_DEPTH)


var _pending_wave_snapshot: Dictionary = {}

func _on_gameplay_snapshot(snapshot: Dictionary) -> void:
	_update_actor_snapshot(snapshot)
	_note_visual_host.set_gameplay_snapshot(snapshot)
	_pending_wave_snapshot = snapshot
	_twin_gate_cue_visual.set_tuning_active(bool(snapshot.get("tuning_field_active", false)))
	_twin_gate_cue_visual.set_bell_held(bool(snapshot.get("life_held", false)), bool(snapshot.get("death_held", false)))
	var soul_fire: float = float(snapshot.get("soul_fire", 0.0))
	var max_soul_fire: float = maxf(float(snapshot.get("max_soul_fire", 100.0)), 1.0)
	_backdrop.set_soul_fire_ratio(soul_fire / max_soul_fire)


func _on_stage_state_changed(_previous: int, current: int, _reason: StringName) -> void:
	_backdrop.set_failed(current == GameplayTypes.StageState.FAILING)
	if current == GameplayTypes.StageState.RESULT:
		_twin_gate_cue_visual.clear()
		_update_actor_attacks(false, false)
		for actor in [_life_actor, _death_actor]:
			if is_instance_valid(actor) and actor.has_meta("idle") and not actor.get_meta("_actor_dead", false):
				_start_actor_base(actor, _actor_snapshot_time_sec, 0.0)
		# 会话结束不保留动态链；正常收尾在 FINISHING/FAILING 阶段由时钟推进。
		_note_visual_host.clear()
		_tuning_interference_visual.clear()


func _on_wave_launched(wave: Dictionary) -> void:
	var affinity := int(wave.get("affinity", GameplayTypes.Affinity.ZHU))
	bell_struck.emit(affinity)


## 预览复用正式输入边界；普通游玩仍由 Spine 自身推进动画。
func _update_actor_snapshot(snapshot: Dictionary) -> void:
	# 重置后的领域哨兵不是歌曲时间；首份有效快照再建立静息相位。
	if int(snapshot.time_us) == -9_000_000_000_000_000: return
	var profile_started := GameplayFrameProfile.begin()
	var time_sec := float(snapshot.time_us) / 1000000.0
	_actor_events.sort_custom(func(a: Dictionary, b: Dictionary): return a.time < b.time)
	while not _actor_events.is_empty() and _actor_events[0].time <= time_sec:
		var event: Dictionary = _actor_events.pop_front()
		_advance_actor_time(event.time)
		for actor in [_life_actor, _death_actor]:
			var side := GameplayTypes.Affinity.ZHU if actor == _life_actor else GameplayTypes.Affinity.XUAN
			if event.affinity == GameplayTypes.Affinity.SU or event.affinity == side:
				_play_actor_reaction(actor, event.death)
	_advance_actor_time(time_sec)
	for actor in [_life_actor, _death_actor]:
		_record_actor_strike(actor)
		if _actor_bells.has(actor):
			_actor_bells[actor].set_visual_time(time_sec, actor.get_meta("_attack_last_hit_sec", -INF))
	_update_actor_attacks(bool(snapshot.get("life_held", false)), bool(snapshot.get("death_held", false)))
	# 先推进旧频率的时间区间，再接收边界上的新频率；变速保留当前动作相位。
	if _life_attacking: _continue_actor_attack(_life_actor, float(snapshot.get("life_frequency_hz", attack_reference_hz)))
	if _death_attacking: _continue_actor_attack(_death_actor, float(snapshot.get("death_frequency_hz", attack_reference_hz)))

	GameplayFrameProfile.end(&"actors", profile_started)


func _queue_actor_damage(record: DamageRecord) -> void:
	if record.actual_damage <= 0: return
	_actor_events.append({"time": float(record.timestamp_us) / 1000000.0,
		"affinity": GameplayTypes.Affinity.SU if record.fatal else record.affinity, "death": record.fatal})


func _queue_actor_death(time: float, side: int = GameplayTypes.Affinity.SU) -> void:
	_actor_events.append({"time": time, "affinity": side, "death": true})


func _advance_actor_time(time: float) -> void:
	_prepare_locomotion()
	if _locomotion != null and _actors_can_move():
		if not is_finite(_preview_actor_time_sec):
			_advance_actor_segment(minf(0.0, time))
			_refresh_actor_bases(minf(0.0, time))
		for change: Dictionary in _locomotion.changes:
			if change.time > _preview_actor_time_sec and change.time <= time:
				_advance_actor_segment(change.time)
				_refresh_actor_bases(change.time)
	_advance_actor_segment(time)
	_refresh_actor_bases(time)


func _prepare_locomotion() -> void:
	if stage_definition == null or stage_definition.visual_theme == null: return
	var environment: StageEnvironmentSequence = parallax_controller.environment if is_instance_valid(parallax_controller) else null
	if _locomotion != null and environment == _locomotion_environment: return
	_locomotion_environment = environment
	if environment == null:
		environment = StageEnvironmentSequence.new()
		environment.build(stage_definition.background, [], Callable(), "", Vector3i(0, roundi(_song_duration_sec * 1000000.0), 0), Callable(), stage_definition.visual_theme.camera_velocity)
	_locomotion = ActorLocomotion.new()
	# 环境编排使用音频绝对时间；角色沿用判定快照时间，转换时补回已有映射量。
	var offset := 0.0
	if _locomotion_environment != null and stage_definition.song != null:
		offset = stage_definition.song.first_beat_offset_sec
		if is_instance_valid(_clock): offset += _clock.input_compensation_sec + _clock.visual_lead_sec
	_locomotion.configure(environment, stage_definition.visual_theme, offset)


func _actors_can_move() -> bool:
	return _session == null or _session.state in [GameplayTypes.StageState.PLAYING, GameplayTypes.StageState.FINISHING, GameplayTypes.StageState.FAILING, GameplayTypes.StageState.PAUSED]


func _actor_base_name(actor: Node, time: float) -> String:
	if _locomotion != null and _actors_can_move() and actor.has_meta("walk"):
		if _locomotion.moving_at(time)[0 if actor == _life_actor else 1]: return str(actor.get_meta("walk"))
	return str(actor.get_meta("idle"))


func _start_actor_base(actor: Node, time: float, mix: float) -> void:
	var name := _actor_base_name(actor, time)
	var track = actor.get_animation_state().set_animation(name, true, 0)
	var period: float = stage_definition.visual_theme.walk_period_sec if name == str(actor.get_meta("walk", "")) else 4.0
	track.set_time_scale(track.get_animation().get_duration() / period)
	track.set_track_time(fposmod(time, period) * track.get_time_scale())
	track.set_mix_duration(mix)
	_advance_actor_skeleton(actor, 0.0)


func _refresh_actor_bases(time: float) -> void:
	for actor in [_life_actor, _death_actor]:
		if not is_instance_valid(actor) or not actor.has_meta("idle") or actor.get_meta("_actor_dead", false): continue
		var track = actor.get_animation_state().get_track(0)
		if track == null or track.get_animation().get_name() in ["attack", str(actor.get_meta("attack_loop", "attack"))]: continue
		if track.get_animation().get_name() != _actor_base_name(actor, time):
			_start_actor_base(actor, time, stage_definition.visual_theme.walk_mix_sec)


func _advance_actor_segment(time: float) -> void:
	if time == _preview_actor_time_sec: return
	_actor_snapshot_time_sec = time
	var delta := maxf(time - _preview_actor_time_sec, 0.0) if is_finite(_preview_actor_time_sec) else 0.0
	for actor in [_life_actor, _death_actor]:
		if not is_instance_valid(actor) or not actor.is_class("SpineSprite"): continue
		if not _preview_time_driven and not actor.has_meta("idle"): continue
		if actor.get_animation_state().get_num_tracks() == 0: continue
		if not is_finite(_preview_actor_time_sec) and actor.has_meta("idle"):
			actor.get_animation_state().get_track(0).set_track_time(fposmod(time, 4.0))
		_advance_actor_preview(actor, delta, _life_attacking if actor == _life_actor else _death_attacking)
		if actor.get_meta("_actor_dead", false) and actor.has_node("Ashes"):
			actor.get_node("Ashes").set_death_age(actor.get_animation_state().get_track(0).get_track_time())
		# Spine 要在下一次 update 才清理混合；零增量也由基础轨道复位叠加属性。
		_advance_actor_skeleton(actor, 0.0)
		var state = actor.get_animation_state()
		if state.get_num_tracks() > 1 and state.get_track(1) != null and state.get_track(1).is_complete():
			state.clear_track(1)
			_advance_actor_skeleton(actor, 0.0)
	_preview_actor_time_sec = time


func _play_actor_reaction(actor: Node, death: bool) -> void:
	if not is_instance_valid(actor) or not actor.has_meta("death") or actor.get_meta("_actor_dead", false): return
	var state = actor.get_animation_state()
	if death:
		actor.set_meta("_actor_dead", true)
		state.clear_track(1)
		var track = state.set_animation(str(actor.get_meta("death")), false, 0)
		track.set_mix_duration(0.12)
		track.set_time_scale(1.0)
	else:
		if state.get_num_tracks() > 1 and state.get_track(1) != null and not state.get_track(1).is_complete(): return
		var resting: bool = state.get_track(0).get_animation().get_name() in [str(actor.get_meta("idle")), str(actor.get_meta("walk", ""))]
		var track = state.set_animation(str(actor.get_meta("hurt")), false, 1)
		track.set_additive(true)
		# 静息时允许更完整的收身；攻击期间保持原幅度，不干扰挥槌轨迹。
		track.set_alpha(1.2 if resting else 1.0)
		track.set_mix_duration(0.0)
	_advance_actor_skeleton(actor, 0.0)


func _advance_actor_preview(actor: Node, delta: float, held: bool) -> void:
	var track = actor.get_animation_state().get_track(0)
	if actor.get_meta("_actor_dead", false):
		_advance_actor_skeleton(actor, delta)
		return
	var attacking: bool = track.get_animation().get_name() in ["attack", str(actor.get_meta("attack_loop", "attack"))]
	if not attacking:
		_advance_actor_skeleton(actor, delta)
		return
	if not held and not track.get_loop() and actor.has_meta("idle"):
		var finish: float = maxf(track.get_animation_end() - track.get_track_time(), 0.0) / track.get_time_scale()
		if finish <= delta:
			_advance_actor_skeleton(actor, finish)
			_start_actor_base(actor, _actor_snapshot_time_sec - delta + finish, 0.15)
			_advance_actor_skeleton(actor, delta - finish)
			return
	if held and not track.get_loop() and delta > 0.0:
		# 限速期间重新按住：在收招与冷却都结束的准确时刻续招，不能等定位终点
		# 才重新播放，否则一次跨越几秒会与逐帧播放得到不同姿态。
		var target := _actor_snapshot_time_sec
		var start := target - delta
		var speed: float = track.get_time_scale()
		var phase: float = track.get_track_time()
		var resume_at := start + maxf(track.get_animation_end() - phase, 0.0) / speed
		var last_hit: float = actor.get_meta("_attack_last_hit_sec", -INF)
		for hit: float in actor.get_meta("attack_hit_times", PackedFloat32Array()):
			if hit > phase and hit <= track.get_animation_end(): last_hit = maxf(last_hit, start + (hit - phase) / speed)
		resume_at = maxf(resume_at, maxf(last_hit, actor.get_meta("_attack_last_start_sec", -INF)) + 1.0 / attack_max_strikes_per_sec)
		if resume_at <= target:
			_advance_actor_skeleton(actor, maxf(resume_at - start, 0.0))
			_actor_snapshot_time_sec = resume_at
			_record_actor_strike(actor)
			_set_actor_attack(actor, true)
			_advance_actor_skeleton(actor, target - resume_at)
			_actor_snapshot_time_sec = target
			return
	_advance_actor_skeleton(actor, delta)


func _continue_actor_attack(actor: Node, frequency: float) -> void:
	if not is_instance_valid(actor) or not actor.is_class("SpineSprite"): return
	if actor.get_meta("_actor_dead", false): return
	var track = actor.get_animation_state().get_track(0)
	# 限速内的新按下只保持当前动作；若随后一直按住，收招完成后自然续出招。
	if not track.get_loop() and track.is_complete(): _set_actor_attack(actor, true)
	_set_actor_frequency(actor, frequency)


func _set_actor_frequency(actor: Node, frequency: float) -> void:
	if is_instance_valid(actor) and actor.is_class("SpineSprite"):
		var track = actor.get_animation_state().get_track(0)
		if track.get_animation().get_name() in ["attack", str(actor.get_meta("attack_loop", "attack"))]: track.set_time_scale(_actor_frequency_rate(actor, frequency))

func _actor_frequency_rate(actor: Node, frequency: float) -> float:
	var rate := clampf(1.0 + (frequency - attack_reference_hz) * attack_rate_per_hz, attack_min_rate, attack_max_rate)
	if not is_instance_valid(actor) or not actor.is_class("SpineSprite"): return rate
	var hits: PackedFloat32Array = actor.get_meta("attack_hit_times", PackedFloat32Array())
	if hits.size() > 1:
		var duration: float = actor.get_skeleton().get_data().find_animation(str(actor.get_meta("attack_loop", "attack"))).get_duration()
		var gap := duration - hits[-1] + hits[0]
		for i in range(1, hits.size()): gap = minf(gap, hits[i] - hits[i - 1])
		rate = minf(rate, gap * attack_max_strikes_per_sec)
	return rate

var _preview_actor_controls: Array = []
var _preview_actor_raw_controls: Array = []

func restore_preview_actor_controls(snapshot: Dictionary, force := false) -> void:
	# 频率被挥槌上限限速后，许多摇杆采样并未改变动画速度；只在有效边界推进骨骼。
	var raw: Array = [snapshot.life_held, snapshot.death_held, snapshot.life_frequency_hz, snapshot.death_frequency_hz]
	if not force and raw == _preview_actor_raw_controls and _actor_events.is_empty(): return
	_preview_actor_raw_controls = raw
	var controls: Array = [snapshot.life_held, snapshot.death_held,
		_actor_frequency_rate(_life_actor, snapshot.life_frequency_hz), _actor_frequency_rate(_death_actor, snapshot.death_frequency_hz)]
	if force or controls != _preview_actor_controls or not _actor_events.is_empty():
		_update_actor_snapshot(snapshot)
		_preview_actor_controls = controls


func _record_actor_strike(actor: Node) -> void:
	if not is_instance_valid(actor) or not actor.has_meta("attack_hit_times"): return
	var state = actor.get_animation_state()
	if state.get_num_tracks() == 0: return
	var track = state.get_track(0)
	if not track.get_animation().get_name() in ["attack", str(actor.get_meta("attack_loop", "attack"))]: return
	var phase: float = track.get_track_time()
	var previous: float = actor.get_meta("_attack_sample_phase", phase)
	var last_hit := -INF
	var duration: float = track.get_animation().get_duration()
	for hit: float in actor.get_meta("attack_hit_times"):
		var crossed := floorf((phase - hit) / duration) * duration + hit if track.get_loop() else hit
		if crossed <= phase and (track.get_loop() or crossed <= track.get_animation_end()): last_hit = maxf(last_hit, crossed)
	if last_hit > previous:
		# 大步定位可能越过多次敲击，只记录最近一次；不逐圈补播，也不影响真实发波。
		actor.set_meta("_attack_last_hit_sec", _actor_snapshot_time_sec - (phase - last_hit) / track.get_time_scale())
	actor.set_meta("_attack_sample_phase", phase)


func _reset_preview_actors() -> void:
	_locomotion = null
	_locomotion_environment = null
	_preview_actor_controls.clear()
	_preview_actor_raw_controls.clear()
	_actor_events.clear()
	_preview_actor_time_sec = -INF
	_life_attacking = false
	_death_attacking = false
	for actor in [_life_actor, _death_actor]:
		if _actor_bells.has(actor): _actor_bells[actor].reset_pose()
		if is_instance_valid(actor) and actor.is_class("SpineSprite"):
			for key in ["_attack_sample_phase", "_attack_last_hit_sec", "_attack_last_start_sec", "_actor_dead"]:
				if actor.has_meta(key): actor.remove_meta(key)
			if _preview_time_driven or actor.has_meta("idle"): actor.set_update_mode(SpineConstant.UpdateMode_Manual)
			actor.get_animation_state().clear_tracks()
			if actor.has_node("Ashes"): actor.get_node("Ashes").set_death_age(-1.0)
			actor.get_skeleton().set_to_setup_pose()
			actor.get_skeleton().set_time(0.0)
			actor.get_skeleton().update_world_transform(SpineConstant.Physics_Reset)
			if actor.has_meta("idle"): actor.get_animation_state().set_animation(str(actor.get_meta("idle")), true, 0)
			_advance_actor_skeleton(actor, 0.0)


## 只在按住状态变化时操作轨道，避免每份快照将循环动画重置到首帧。
func _update_actor_attacks(life_held: bool, death_held: bool) -> void:
	if life_held != _life_attacking:
		_set_actor_attack(_life_actor, life_held)
		_life_attacking = life_held
	if death_held != _death_attacking:
		_set_actor_attack(_death_actor, death_held)
		_death_attacking = death_held


## 松开收完当前单招；新的按下边界重新出招，通过短混合保留瞬间姿态连续性。
func _set_actor_attack(actor: Node, held: bool) -> void:
	if is_instance_valid(actor) and actor.is_class("SpineSprite"):
		if actor.get_meta("_actor_dead", false): return
		var state = actor.get_animation_state()
		var track = state.get_track(0) if state.get_num_tracks() > 0 else null
		if held:
			var cooldown := 1.0 / attack_max_strikes_per_sec
			var last_start: float = actor.get_meta("_attack_last_start_sec", -INF)
			var last_hit: float = actor.get_meta("_attack_last_hit_sec", -INF)
			if _actor_snapshot_time_sec + 0.000001 < maxf(last_start, last_hit) + cooldown: return
			var was_attack: bool = track != null and track.get_animation().get_name() in ["attack", str(actor.get_meta("attack_loop", "attack"))]
			var restarting: bool = was_attack and (not track.is_complete() or track.get_mixing_from() != null)
			var next = state.set_animation(str(actor.get_meta("attack_loop", "attack")), true, 0)
			# 从右侧抬槌姿势进入下砸，保留一小段可见的下行轨迹。
			next.set_track_time(float(actor.get_meta("attack_start_sec", 0.0)))
			next.set_time_scale(track.get_time_scale() if track != null else 1.0)
			actor.set_meta("_attack_sample_phase", next.get_track_time())
			actor.set_meta("_attack_last_start_sec", _actor_snapshot_time_sec)
			next.set_mix_duration(attack_restart_mix_sec if restarting else 0.0)
		elif track != null and track.get_loop() and track.get_animation().get_name() in ["attack", str(actor.get_meta("attack_loop", "attack"))]:
			# attack 由等长的独立招式组成，每段末尾均收回站姿。松开截到当前段末，
			# 不连带播放下一招；保留原生时间轴，使正式播放与预览跨帧定位完全一致。
			var duration: float = track.get_animation().get_duration()
			var section: float = duration / int(actor.get_meta("attack_segments", 1))
			var local_time := fposmod(track.get_track_time(), duration)
			if actor.has_meta("attack_loop"):
				var speed: float = track.get_time_scale()
				track = state.set_animation("attack", false, 0)
				track.set_mix_duration(attack_release_mix_sec)
				track.set_time_scale(speed)
			track.set_animation_end(minf((floorf(local_time / section) + 1.0) * section, duration))
			track.set_track_time(local_time)
			actor.set_meta("_attack_sample_phase", local_time)
			track.set_loop(false)
		if _preview_time_driven:
			_advance_actor_skeleton(actor, 0.0)


func _on_settings_changed() -> void:
	_apply_visual_settings()


func _apply_visual_settings() -> void:
	if is_instance_valid(_tuning_interference_visual) and is_instance_valid(_settings_service):
		_tuning_interference_visual.set_visual_intensity(float(_settings_service.get("tuning_wave_intensity")))


func update_preview_palette(visual_theme: StageVisualTheme) -> void:
	_apply_palette(visual_theme)

func _apply_palette(visual_theme: StageVisualTheme) -> void:
	if visual_theme == null:
		return
	# 波与音符共享全局阵营色；世界背景继续使用场景自身的对照配色。
	var note_style: NoteEffectStyle = GrayboxNoteVisual.EFFECT_STYLE
	_backdrop.life_color = visual_theme.life_color
	_backdrop.death_color = visual_theme.death_color
	_backdrop.ink_color = visual_theme.ink_color
	_backdrop.bone_color = visual_theme.su_color
	_wave_field_visual.configure_palette(
		note_style.life_halo,
		note_style.death_halo,
		visual_theme.su_color,
		visual_theme.paper_color
	)
	_tuning_interference_visual.configure_palette(
		note_style.life_halo,
		note_style.death_halo,
		visual_theme.su_color
	)
	_rapid_interference_visual.configure_palette(
		note_style.life_halo,
		note_style.death_halo,
		visual_theme.su_color
	)
	_twin_gate_cue_visual.configure_palette(
		visual_theme.life_color,
		visual_theme.death_color,
		visual_theme.su_color,
		visual_theme.ink_color
	)
	_apply_lingjun_tint(_life_actor, visual_theme.life_lingjun_target_color, visual_theme.life_lingjun_color_strength)
	_apply_lingjun_tint(_death_actor, visual_theme.death_lingjun_target_color, visual_theme.death_lingjun_color_strength)
	_backdrop.queue_redraw()


## 将主题色偏同步到角色本体和其独立的灰烬材质；不触碰灰烬生命周期参数。
func _apply_lingjun_tint(actor: Node, target_color: Color, strength: float) -> void:
	if not is_instance_valid(actor):
		return
	# SpineSprite 的骨架绘制走 normal_material；普通 CanvasItem 才使用 material。
	# 优先处理 Spine 通道，否则设置到根节点 material 不会影响实际骨架绘制。
	var is_spine_actor := actor.is_class("SpineSprite")
	var body_material := actor.get("normal_material") as ShaderMaterial if is_spine_actor else actor.get("material") as ShaderMaterial
	var body_material_property: StringName = &"normal_material" if is_spine_actor else &"material"
	# 旧角色场景可能把材质写在根 material；迁移到 Spine 的实际绘制通道。
	if is_spine_actor and body_material == null:
		body_material = actor.get("material") as ShaderMaterial
	if body_material != null and body_material.shader != null:
		if not actor.has_meta("_lingjun_tint_materialized"):
			body_material = body_material.duplicate(false) as ShaderMaterial
			actor.set(body_material_property, body_material)
			actor.set_meta("_lingjun_tint_materialized", true)
		body_material.set_shader_parameter(&"stength", clampf(strength, 0.0, 1.0))
		body_material.set_shader_parameter(&"target_color", target_color)
	var ashes := actor.get_node_or_null("Ashes") as MeshInstance2D
	if ashes == null:
		return
	var ashes_material := ashes.material as ShaderMaterial
	if ashes_material == null or ashes_material.shader == null:
		return
	if not ashes.has_meta("_lingjun_tint_materialized"):
		ashes_material = ashes_material.duplicate(false) as ShaderMaterial
		ashes.material = ashes_material
		ashes.set_meta("_lingjun_tint_materialized", true)
	ashes_material.set_shader_parameter(&"stength", clampf(strength, 0.0, 1.0))
	ashes_material.set_shader_parameter(&"target_color", target_color)


func _instance_if_present(scene: PackedScene, target: Node2D) -> Node:
	if scene == null:
		return null
	var instance: Node = scene.instantiate()
	target.add_child(instance)
	return instance


func _clear_slot(slot: Node) -> void:
	for child: Node in slot.get_children():
		child.queue_free()


func _calculate_song_duration_sec() -> float:
	if stage_definition == null or stage_definition.song == null:
		return 1.0
	if stage_definition.song.audio_stream != null:
		var length_sec: float = stage_definition.song.audio_stream.get_length()
		if length_sec > 0.0:
			return maxf(length_sec - stage_definition.song.first_beat_offset_sec, 0.001)
	return maxf(stage_definition.song.fallback_duration_sec, 0.001)


func _disconnect_sources() -> void:
	if is_instance_valid(_clock) and _clock.sample_published.is_connected(_on_clock_sample):
		_clock.sample_published.disconnect(_on_clock_sample)
	if is_instance_valid(_session):
		if _session.gameplay_coordinator.damage_recorded.is_connected(_queue_actor_damage):
			_session.gameplay_coordinator.damage_recorded.disconnect(_queue_actor_damage)
		if _session.waves_reset.is_connected(_reset_preview_actors):
			_session.waves_reset.disconnect(_reset_preview_actors)
		if _session.waves_reset.is_connected(_tuning_interference_visual.clear):
			_session.waves_reset.disconnect(_tuning_interference_visual.clear)
		if _session.visual_frame_ready.is_connected(_on_visual_frame_ready):
			_session.visual_frame_ready.disconnect(_on_visual_frame_ready)
		if _session.gameplay_snapshot_changed.is_connected(_on_gameplay_snapshot):
			_session.gameplay_snapshot_changed.disconnect(_on_gameplay_snapshot)
		if _session.state_changed.is_connected(_on_stage_state_changed):
			_session.state_changed.disconnect(_on_stage_state_changed)
		if _session.wave_launched.is_connected(_on_wave_launched):
			_session.wave_launched.disconnect(_on_wave_launched)
	_clock = null
	_session = null

var preview_defer_actor_mesh := false

func _advance_actor_skeleton(actor: Node, delta: float) -> void:
	if preview_defer_actor_mesh:
		# 历史推进保留 Spine 动画轨道、混合及骨骼局部姿态，最终帧才更新世界变换与网格。
		var skeleton = actor.get_skeleton()
		skeleton.update(delta)
		actor.get_animation_state().update(delta)
		actor.get_animation_state().apply(skeleton)
	else:
		actor.update_skeleton(delta)
