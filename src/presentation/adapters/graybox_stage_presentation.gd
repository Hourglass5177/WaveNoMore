class_name GrayboxStagePresentation
extends Node2D

## 关卡表现总装配器。把主题资源放入预留槽位，并把时钟与玩法事件分发给各表现组件。

## 每次玩法逻辑发出声波时触发；affinity 指明生钟或死钟，供角色敲击动画使用。
signal bell_struck(affinity: int)

@export_group("Scene Wiring")
## 灰盒底图节点路径；负责水平分界、占位角色和关卡整体状态。
@export var backdrop_path: NodePath = ^"Backdrop"
## 生界正式场景的挂载槽路径，位于上半画面。
@export var life_world_slot_path: NodePath = ^"WorldPair/LifeWorldSlot"
## 死界正式场景的挂载槽路径，位于下半画面并与生界中心对称。
@export var death_world_slot_path: NodePath = ^"WorldPair/DeathWorldSlot"
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
@export var twin_gate_cue_visual_path: NodePath = ^"GameplayCueLayer/TwinGateCueVisual"
## StageShow 演出事件接收节点路径；灰盒实现会画教学和简化闪光。
@export var show_cue_host_path: NodePath = ^"ShowCueHost"

# 当前关卡定义用于读取歌曲、规则和视觉主题。
var stage_definition: StageDefinition

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


func _ready() -> void:
	_backdrop = get_node(backdrop_path) as GrayboxBackdrop
	_life_world_slot = get_node(life_world_slot_path) as Node2D
	_death_world_slot = get_node(death_world_slot_path) as Node2D
	_life_actor_slot = get_node(life_actor_slot_path) as Node2D
	_death_actor_slot = get_node(death_actor_slot_path) as Node2D
	_boundary_slot = get_node(boundary_slot_path) as Node2D
	_tuning_interference_visual = get_node(tuning_interference_visual_path) as TuningInterferenceVisual
	_rapid_interference_visual = get_node(rapid_interference_visual_path) as RapidInterferenceVisual
	_wave_field_visual = get_node(wave_field_visual_path) as WaveFieldVisual
	_note_visual_host = get_node(note_visual_host_path) as NoteVisualHost
	_twin_gate_cue_visual = get_node(twin_gate_cue_visual_path) as TwinGateCueVisual
	_show_cue_host = get_node(show_cue_host_path) as Node2D
	_settings_service = get_node_or_null("/root/SettingsService")
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
		_instance_if_present(visual_theme.life_actor_scene, _life_actor_slot)
		_instance_if_present(visual_theme.life_bell_scene, _life_actor_slot)
		_instance_if_present(visual_theme.death_actor_scene, _death_actor_slot)
		_instance_if_present(visual_theme.death_bell_scene, _death_actor_slot)
		_instance_if_present(visual_theme.boundary_scene, _boundary_slot)

	_song_duration_sec = _calculate_song_duration_sec()


func bind(clock: SongClock, session: StageSession, scheduler: ChartScheduler, _input_buffer: Node) -> void:
	_disconnect_sources()
	_clock = clock
	_session = session
	_note_visual_host.bind_scheduler(scheduler)
	_wave_field_visual.bind(clock, session)
	_rapid_interference_visual.bind(clock, session)
	_twin_gate_cue_visual.bind(clock, session)
	if not clock.sample_published.is_connected(_on_clock_sample):
		clock.sample_published.connect(_on_clock_sample)
	if not session.gameplay_snapshot_changed.is_connected(_on_gameplay_snapshot):
		session.gameplay_snapshot_changed.connect(_on_gameplay_snapshot)
	if not session.state_changed.is_connected(_on_stage_state_changed):
		session.state_changed.connect(_on_stage_state_changed)
	if not session.wave_launched.is_connected(_on_wave_launched):
		session.wave_launched.connect(_on_wave_launched)


func bind_show_director(director: Node) -> void:
	_show_cue_host.call("bind", director)


func clear() -> void:
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
	_note_visual_host.set_visual_time(sample.visual_time_sec)
	_tuning_interference_visual.set_clock_sample(sample)
	_backdrop.set_song_progress(sample.song_time_sec / maxf(_song_duration_sec, 0.001))

func set_preview_time_driven() -> void:
	_note_visual_host.preview_time_driven = true


func _on_gameplay_snapshot(snapshot: Dictionary) -> void:
	_note_visual_host.set_gameplay_snapshot(snapshot)
	_tuning_interference_visual.set_gameplay_snapshot(snapshot)
	_twin_gate_cue_visual.set_tuning_active(bool(snapshot.get("tuning_field_active", false)))
	var soul_fire: float = float(snapshot.get("soul_fire", 0.0))
	var max_soul_fire: float = maxf(float(snapshot.get("max_soul_fire", 100.0)), 1.0)
	_backdrop.set_soul_fire_ratio(soul_fire / max_soul_fire)


func _on_stage_state_changed(_previous: int, current: int, _reason: StringName) -> void:
	_backdrop.set_failed(current == GameplayTypes.StageState.FAILING)


func _on_wave_launched(wave: Dictionary) -> void:
	bell_struck.emit(int(wave.get("affinity", GameplayTypes.Affinity.ZHU)))


func _on_settings_changed() -> void:
	_apply_visual_settings()


func _apply_visual_settings() -> void:
	if is_instance_valid(_tuning_interference_visual) and is_instance_valid(_settings_service):
		_tuning_interference_visual.set_visual_intensity(float(_settings_service.get("tuning_wave_intensity")))


func _apply_palette(visual_theme: StageVisualTheme) -> void:
	_backdrop.life_color = visual_theme.life_color
	_backdrop.death_color = visual_theme.death_color
	_backdrop.ink_color = visual_theme.ink_color
	_backdrop.bone_color = visual_theme.su_color
	_wave_field_visual.configure_palette(
		visual_theme.life_color,
		visual_theme.death_color,
		visual_theme.su_color,
		visual_theme.paper_color
	)
	_tuning_interference_visual.configure_palette(
		visual_theme.life_color,
		visual_theme.death_color,
		visual_theme.su_color
	)
	_rapid_interference_visual.configure_palette(
		visual_theme.life_color,
		visual_theme.death_color,
		visual_theme.su_color
	)
	_twin_gate_cue_visual.configure_palette(
		visual_theme.life_color,
		visual_theme.death_color,
		visual_theme.su_color,
		visual_theme.ink_color
	)
	_backdrop.queue_redraw()


func _instance_if_present(scene: PackedScene, target: Node2D) -> void:
	if scene == null:
		return
	var instance: Node = scene.instantiate()
	target.add_child(instance)


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
		if _session.gameplay_snapshot_changed.is_connected(_on_gameplay_snapshot):
			_session.gameplay_snapshot_changed.disconnect(_on_gameplay_snapshot)
		if _session.state_changed.is_connected(_on_stage_state_changed):
			_session.state_changed.disconnect(_on_stage_state_changed)
		if _session.wave_launched.is_connected(_on_wave_launched):
			_session.wave_launched.disconnect(_on_wave_launched)
	_clock = null
	_session = null
