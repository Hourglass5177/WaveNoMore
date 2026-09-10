class_name StageRoot
extends Node

## 单个关卡场景的组装根节点。负责解析固定子节点、绑定会话与表现系统并装载关卡资源，
## 不直接实现判定规则或具体美术效果。

## 关卡资源完成配置、编译并准备就绪后发出。
signal stage_loaded(stage_id: String)
## 关卡定义、资源校验或运行节点接线失败时发出。
signal stage_load_failed(message: String)
## StageSession 产生最终结算后发出，应用层据此进入结算页。
signal stage_finished(result: Dictionary)
## 本局 Replay 成功写入磁盘后发出；`path` 通常是 `user://` 路径。
signal replay_persisted(path: String)
## 玩家从暂停菜单要求退出本关时发出。
signal exit_requested

## 直接运行 StageRoot 场景时自动装载的关卡；正常应用流程会通过 `configure_stage()` 注入。
@export var initial_stage: StageDefinition
## `initial_stage` 存在时是否在准备完成后立即起播；关闭可供编辑器和测试手动控制。
@export var auto_start_initial_stage: bool = true
## 旧录制链路预留的装备标识；现行领域重演显式注入本局随从配置。
@export var active_loadout_hash: String = ""

@export_group("Scene Wiring")
## 歌曲播放器节点路径；相对于 StageRoot，必须指向 AudioStreamPlayer。
@export var song_player_path: NodePath = ^"Session/SongPlayer"
## 歌曲主时钟节点路径；必须指向 SongClock。
@export var song_clock_path: NodePath = ^"Session/SongClock"
## 提前生成与回收音符视觉对象的调度器节点路径；必须指向 ChartScheduler。
@export var chart_scheduler_path: NodePath = ^"Session/ChartScheduler"
## 场景树与纯玩法内核之间的协调器节点路径；必须指向 GameplayCoordinator。
@export var gameplay_coordinator_path: NodePath = ^"Session/GameplayCoordinator"
## 一局关卡生命周期中枢的节点路径；必须指向 StageSession。
@export var stage_session_path: NodePath = ^"Session/StageSession"
## 将 Replay 样本按判定时间注入会话的驱动器节点路径。
@export var replay_input_driver_path: NodePath = ^"Session/ReplayInputDriver"
## 旁听真人输入并持久化 Replay 的录制器节点路径。
@export var replay_recorder_path: NodePath = ^"Session/ReplayRecorder"
## 按 StageShow 触发镜头、角色和环境 Cue 的导演节点路径。
@export var stage_show_director_path: NodePath = ^"Session/StageShowDirector"
## 关卡主体表现适配器节点路径；当前灰盒实现必须是 GrayboxStagePresentation。
@export var presentation_path: NodePath = ^"Presentation/GrayboxStagePresentation"
## 分数、Combo、魂火和进度 HUD 的节点路径。
@export var hud_path: NodePath = ^"HudLayer"
## 暂停菜单覆盖层的节点路径。
@export var pause_path: NodePath = ^"PauseLayer"
## 开发调试信息覆盖层的节点路径。
@export var debug_hud_path: NodePath = ^"DebugLayer"
## 敲钟、判定和失败等听觉反馈导演的节点路径。
@export var audio_feedback_path: NodePath = ^"Presentation/AudioFeedbackDirector"
## 仅 Tap 命中触发短震动的独立反馈节点路径。
@export var note_haptics_feedback_path: NodePath = ^"Presentation/NoteHapticsFeedback"
## 关卡共享的多源震动管理节点，不归某一种反馈独占。
@export var controller_haptics_path: NodePath = ^"Presentation/ControllerHaptics"

## 从 `song_player_path` 解析出的歌曲播放器，供会话和时钟共用。
var song_player: AudioStreamPlayer
## 从 `song_clock_path` 解析出的歌曲时钟。
var song_clock: SongClock
## 全局输入事件缓冲单例。
var input_buffer: Node
## 从 `chart_scheduler_path` 解析出的视觉调度器。
var chart_scheduler: ChartScheduler
## 从 `gameplay_coordinator_path` 解析出的玩法协调器。
var gameplay_coordinator: GameplayCoordinator
## 从 `stage_session_path` 解析出的一局生命周期中枢。
var stage_session: StageSession
## 从场景路径解析出的 Replay 输入驱动器。
var replay_input_driver: ReplayInputDriver
## 从场景路径解析出的 Replay 录制器；保留为 Node 是为了降低可选模块耦合。
var replay_recorder: Node
## 从场景路径解析出的演出导演；通过稳定方法接口调用。
var stage_show_director: Node
## 当前关卡的灰盒表现根节点。
var presentation: GrayboxStagePresentation
## 当前关卡的常规 HUD。
var hud: StageHud
## 当前关卡的暂停覆盖层。
var pause_overlay: PauseOverlay
## 当前关卡的开发调试 HUD。
var debug_hud: StageDebugHud
## 当前关卡的声音反馈导演。
var audio_feedback: AudioFeedbackDirector
## 通过共享管理层请求单次震动的 Tap 反馈节点，生左死右。
var note_haptics_feedback: NoteHapticsFeedback
## 供其他模块申请句柄或单次震动的关卡共享节点。
var controller_haptics: ControllerHaptics
## 最近一次录制完成的 Replay，供开发工具或外部调用读取。
var last_replay: ReplayData
## 装配时复制技能参数；表现持有定义资源，只读美术配置。
var active_pet: PetDefinition
var pet_advanced: bool = false
var _pet_views: Array[PetVisual] = []

func set_pet(pet: PetDefinition, advanced: bool = false) -> void:
	active_pet = pet
	pet_advanced = advanced
	stage_session.pet_effect = pet.effect(advanced) if pet != null else PetEffectProfile.new()

func _setup_pet_views() -> void:
	_pet_views = presentation.configure_pet(active_pet, pet_advanced)

func _update_pet_views(sample: ClockSample) -> void:
	if active_pet == null: return
	var simulation := gameplay_coordinator.simulation
	for view in _pet_views:
		view.set_state(sample.song_time_sec, simulation.last_pet_trigger_us)



func _exit_tree() -> void:
	teardown()


func _ready() -> void:
	song_player = get_node(song_player_path) as AudioStreamPlayer
	song_clock = get_node(song_clock_path) as SongClock
	input_buffer = InputEventBuffer
	chart_scheduler = get_node(chart_scheduler_path) as ChartScheduler
	gameplay_coordinator = get_node(gameplay_coordinator_path) as GameplayCoordinator
	stage_session = get_node(stage_session_path) as StageSession
	replay_input_driver = null
	replay_recorder = null
	stage_show_director = get_node(stage_show_director_path)
	presentation = get_node(presentation_path) as GrayboxStagePresentation
	hud = get_node(hud_path) as StageHud
	pause_overlay = get_node(pause_path) as PauseOverlay
	debug_hud = get_node(debug_hud_path) as StageDebugHud
	audio_feedback = get_node(audio_feedback_path) as AudioFeedbackDirector
	note_haptics_feedback = get_node(note_haptics_feedback_path) as NoteHapticsFeedback
	controller_haptics = get_node(controller_haptics_path) as ControllerHaptics
	controller_haptics.set_output_enabled(false)

	stage_session.bind_components(
		song_player,
		song_clock,
		input_buffer,
		chart_scheduler,
		gameplay_coordinator
	)
	stage_show_director.call("bind", song_clock, stage_session)
	presentation.bind(song_clock, stage_session, chart_scheduler, input_buffer)
	presentation.bind_show_director(stage_show_director)
	hud.bind(stage_session, song_clock)
	pause_overlay.bind(stage_session)
	debug_hud.bind(stage_session)
	audio_feedback.bind(stage_session, input_buffer)
	stage_session.state_changed.connect(_on_haptics_stage_state_changed)
	stage_session.timeline_seeked.connect(_on_haptics_timeline_seeked)
	stage_session.run_started.connect(_on_haptics_run_started)
	stage_session.run_started.connect(_reset_parallax)
	note_haptics_feedback.bind(stage_session, controller_haptics)
	stage_session.result_ready.connect(_on_stage_result_ready)
	stage_session.visual_frame_ready.connect(_update_pet_views)
	pause_overlay.exit_requested.connect(_on_exit_requested)

	if initial_stage != null:
		load_stage(initial_stage, auto_start_initial_stage)


func load_stage(stage: StageDefinition, start_after_prepare: bool = true) -> bool:
	if not stage_session.configure(stage):
		stage_load_failed.emit("StageDefinition configuration failed.")
		return false
	presentation.configure(stage)
	var background_error := get_parallax_controller().configure(stage.background)
	if not background_error.is_empty():
		stage_load_failed.emit(background_error)
		return false
	audio_feedback.configure_from_rules(stage.rule_set)
	presentation.clear()
	hud.configure(stage)
	if not stage_session.prepare():
		stage_load_failed.emit("Stage validation or compilation failed.")
		return false
	_setup_pet_views()
	stage_show_director.call("configure", stage.stage_show, stage_session.compiled_chart.tempo_map)
	presentation.set_song_duration(stage_session.get_end_song_time_sec())
	hud.set_song_duration(stage_session.get_end_song_time_sec())
	stage_loaded.emit(stage.stage_id)
	if start_after_prepare:
		return stage_session.start()
	return true


func configure_stage(stage: StageDefinition) -> bool:
	# 应用层使用的稳定入口。灰盒关允许 AudioStream 为空：SongClock 仍以系统时钟推进，
	# 并使用 SongDefinition.fallback_duration_sec 决定关卡何时结束。
	return load_stage(stage, true)


func set_loadout_hash(value: String) -> void:
	active_loadout_hash = value
	if is_instance_valid(replay_recorder):
		replay_recorder.call("set_loadout_hash", active_loadout_hash)


func get_last_replay() -> ReplayData:
	if last_replay != null:
		return last_replay
	if is_instance_valid(replay_recorder):
		return replay_recorder.call("get_last_replay") as ReplayData
	return null


func get_last_run_log() -> Dictionary:
	if not is_instance_valid(replay_recorder):
		return {}
	return replay_recorder.call("get_last_run_log") as Dictionary


func seek_tick(tick: int) -> bool:
	if stage_session.compiled_chart == null or stage_session.compiled_chart.tempo_map == null:
		return false
	var target_us: int = stage_session.compiled_chart.tempo_map.tick_to_us(tick)
	var target_song_time_sec: float = float(target_us) / 1_000_000.0
	stage_show_director.call("set_clock_updates_enabled", false)
	var succeeded: bool = stage_session.seek_song_time(target_song_time_sec)
	if succeeded:
		if stage_session.is_replay_playback() and is_instance_valid(replay_input_driver):
			var target_judge_us: int = roundi(
				(target_song_time_sec - song_clock.input_compensation_sec) * 1_000_000.0
			)
			replay_input_driver.seek(target_judge_us)
		stage_show_director.call("seek", target_song_time_sec)
	stage_show_director.call("set_clock_updates_enabled", true)
	return succeeded


func retry() -> bool:
	return stage_session.retry()


## 其他对象通过此入口注册视差或驱动模拟摄像头，不接触内部深度层。
func get_parallax_controller() -> ParallaxController:
	return presentation.parallax_controller


func _reset_parallax(_run_id: int) -> void:
	get_parallax_controller().set_camera_position(Vector2.ZERO)
	get_parallax_controller().set_song_time(0.0)


func teardown() -> void:
	if is_instance_valid(presentation) and is_instance_valid(presentation.parallax_controller) and presentation.parallax_controller.is_inside_tree():
		presentation.parallax_controller.clear()
	if is_instance_valid(controller_haptics):
		controller_haptics.set_output_enabled(false)
		controller_haptics.clear()
	if is_instance_valid(stage_session):
		if stage_session.state_changed.is_connected(_on_haptics_stage_state_changed):
			stage_session.state_changed.disconnect(_on_haptics_stage_state_changed)
			stage_session.timeline_seeked.disconnect(_on_haptics_timeline_seeked)
			stage_session.run_started.disconnect(_on_haptics_run_started)
	if is_instance_valid(note_haptics_feedback):
		note_haptics_feedback.unbind()
	if is_instance_valid(replay_input_driver):
		# 先停止 Replay 注入，再让 StageSession 禁用输入；活动回放的 stop() 可能恢复真人模式。
		replay_input_driver.stop()
	if is_instance_valid(stage_show_director):
		stage_show_director.call("reset")
	if is_instance_valid(stage_session):
		stage_session.teardown()


func set_debug_visible(value: bool) -> void:
	debug_hud.set_debug_visible(value)


func get_controller_haptics() -> ControllerHaptics:
	## 返回本关唯一管理节点；调用方保存句柄，不直接访问 C++ 四参数输出。
	return controller_haptics


func _on_haptics_stage_state_changed(_previous: int, current: int, _reason: StringName) -> void:
	## 暂停仅屏蔽输出；新局准备/结束永久清理。预览始终不选设备、不输出。
	var active: bool = current in [GameplayTypes.StageState.PREROLL, GameplayTypes.StageState.PLAYING]
	controller_haptics.set_output_enabled(active and not stage_session.external_preview)
	if not active and current != GameplayTypes.StageState.PAUSED:
		controller_haptics.clear()


func _on_haptics_timeline_seeked(_song_time_sec: float) -> void:
	## Seek 建立新时间线，旧句柄不能恢复。
	controller_haptics.clear()


func _on_haptics_run_started(_run_id: int) -> void:
	## 重试不得复用旧局句柄，暂停恢复不经过此入口。
	controller_haptics.clear()


func _on_exit_requested() -> void:
	teardown()
	exit_requested.emit()


func _on_stage_result_ready(result: Dictionary) -> void:
	var final := result.duplicate(true)
	final.equipped_pet_id = active_pet.pet_id if active_pet != null else ""
	final.pet_name = active_pet.display_name if active_pet != null else ""
	final.pet_advanced = pet_advanced
	stage_finished.emit(final)


func _on_replay_saved(path: String, replay: ReplayData, _run_log: Dictionary) -> void:
	last_replay = replay
	replay_persisted.emit(path)
