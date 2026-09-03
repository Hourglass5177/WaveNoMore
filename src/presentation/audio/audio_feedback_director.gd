class_name AudioFeedbackDirector
extends Node

## 关卡内音效调度器。用播放器池承接密集敲钟与判定声，避免每次临时创建节点。

# 没有正式音频时，用这个工厂在内存中生成短促占位声。
const GRAYBOX_AUDIO_FACTORY: GDScript = preload("res://src/presentation/audio/graybox_click_track_factory.gd")

@export_group("Bell Transients")
## 生钟敲击音；对应手柄 R1、右键或 J 发出的生波，不要求素材带固定音高。
@export var life_strike: AudioStream
## 死钟敲击音；对应手柄 L1、左键或 F 发出的死波。
@export var death_strike: AudioStream

@export_group("Carrier Tone")
## 按住生钟时持续的轻量钟体底音；它只做听觉反馈，不参与判定。
@export var life_carrier_loop: AudioStream
## 按住死钟时持续的轻量钟体底音。
@export var death_carrier_loop: AudioStream
## 游标未贴住引导带时的载波音量，保持克制，避免盖过 BGM。
@export_range(-60.0, 0.0, 0.5) var carrier_idle_volume_db: float = -27.0
## 游标进入有效引导带时的载波音量；配合波纹变亮形成即时正反馈。
@export_range(-60.0, 0.0, 0.5) var carrier_aligned_volume_db: float = -18.0
## 规则中的基准发波频率；载波音高只按它做相对变化。
var _base_frequency_hz: float = 4.35

@export_group("Judgment")
## Perfect 判定短音；正式素材为空时由程序生成高亮占位音。
@export var perfect_sfx: AudioStream
## Good 判定短音。
@export var good_sfx: AudioStream
## Pass 判定短音。
@export var pass_sfx: AudioStream
## Miss 判定短音，宜与成功反馈有明显音色差异。
@export var miss_sfx: AudioStream

@export_group("Pool")
## 同时可轮转使用的播放器数量；数值越大，密集敲击越不易截断前一个声音，也会多占少量节点。
@export_range(2, 32, 1) var pool_size: int = 10
## 所有反馈音输出到的 Godot 音频总线名，必须与项目 Audio Bus Layout 一致。
@export var output_bus: StringName = &"GameplaySFX"
## 正式音频为空时是否自动生成占位音；关闭后缺少的音效保持静音。
@export var use_procedural_fallback: bool = true

# 固定播放器池和下一个轮转下标；播放时复用节点，不在密集输入中临时创建对象。
var _pool: Array[AudioStreamPlayer] = []
# 下一个可用播放器的下标；每次播放后轮转，避免密集音效切断前一个声音。
var _cursor: int = 0
# 生、死各一条循环播放器，不占用敲击瞬态的轮转池。
var _life_carrier_player: AudioStreamPlayer
var _death_carrier_player: AudioStreamPlayer


func _ready() -> void:
	_configure_fallback_streams()
	# 多个瞬态音可能在同一拍重叠，轮转池能让前一个声音继续播放。
	for index: int in range(pool_size):
		var player := AudioStreamPlayer.new()
		player.name = "Sfx%02d" % index
		player.bus = output_bus
		add_child(player)
		_pool.append(player)
	_life_carrier_player = _create_carrier_player("LifeCarrier", life_carrier_loop)
	_death_carrier_player = _create_carrier_player("DeathCarrier", death_carrier_loop)


func _exit_tree() -> void:
	for player: AudioStreamPlayer in _pool:
		player.stop()
		player.stream = null
	for player: AudioStreamPlayer in [_life_carrier_player, _death_carrier_player]:
		if is_instance_valid(player):
			player.stop()
			player.stream = null


func bind(session: StageSession, _input_router: InputRouter) -> void:
	if not session.judgment_recorded.is_connected(_on_judgment_recorded):
		session.judgment_recorded.connect(_on_judgment_recorded)
	if not session.wave_launched.is_connected(_on_wave_launched):
		session.wave_launched.connect(_on_wave_launched)
	if not session.gameplay_snapshot_changed.is_connected(_on_gameplay_snapshot_changed):
		session.gameplay_snapshot_changed.connect(_on_gameplay_snapshot_changed)
	if not session.state_changed.is_connected(_on_stage_state_changed):
		session.state_changed.connect(_on_stage_state_changed)


func configure_from_rules(rules: GameplayRuleSet) -> void:
	if rules != null:
		_base_frequency_hz = maxf(rules.tuning_base_frequency_hz, 0.001)


func play(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if stream == null or _pool.is_empty():
		return
	var player: AudioStreamPlayer = _pool[_cursor]
	_cursor = (_cursor + 1) % _pool.size()
	player.stop()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()


func _on_wave_launched(wave: Dictionary) -> void:
	play(death_strike if int(wave.get("affinity", GameplayTypes.Affinity.ZHU)) == GameplayTypes.Affinity.XUAN else life_strike)


func _on_judgment_recorded(record: JudgmentRecord) -> void:
	_play_judgment_grade(record.grade)


func _on_gameplay_snapshot_changed(snapshot: Dictionary) -> void:
	_update_carrier_player(
		_life_carrier_player,
		bool(snapshot.get("life_held", false)),
		float(snapshot.get("life_frequency_hz", _base_frequency_hz)),
		_side_is_aligned(snapshot, GameplayTypes.Affinity.ZHU)
	)


func _on_stage_state_changed(_previous: int, current: int, _reason: StringName) -> void:
	# 暂停、重试、结算和卸载都必须立刻收掉持续底音；恢复后的首个快照会按真实按住状态重启。
	if current in [
		GameplayTypes.StageState.LOADING,
		GameplayTypes.StageState.READY,
		GameplayTypes.StageState.PAUSED,
		GameplayTypes.StageState.FINISHING,
		GameplayTypes.StageState.FAILING,
		GameplayTypes.StageState.RESULT,
	]:
		_stop_carrier_players()
	_update_carrier_player(
		_death_carrier_player,
		bool(snapshot.get("death_held", false)),
		float(snapshot.get("death_frequency_hz", _base_frequency_hz)),
		_side_is_aligned(snapshot, GameplayTypes.Affinity.XUAN)
	)


func _play_judgment_grade(grade: int) -> void:
	match grade:
		GameplayTypes.JudgmentGrade.PERFECT:
			play(perfect_sfx, -2.0)
		GameplayTypes.JudgmentGrade.GOOD:
			play(good_sfx, -3.0)
		GameplayTypes.JudgmentGrade.PASS:
			play(pass_sfx, -4.0)
		GameplayTypes.JudgmentGrade.MISS:
			play(miss_sfx, -1.0)
		_:
			pass


func _configure_fallback_streams() -> void:
	if not use_procedural_fallback:
		return
	if life_strike == null:
		life_strike = GRAYBOX_AUDIO_FACTORY.create_transient(470.0, 0.085, 0.25, 0.30)
	if death_strike == null:
		death_strike = GRAYBOX_AUDIO_FACTORY.create_transient(315.0, 0.095, 0.27, 0.55)
	if life_carrier_loop == null:
		life_carrier_loop = GRAYBOX_AUDIO_FACTORY.create_sustained_tone(220.0, 1.0, 0.09, 0.18)
	if death_carrier_loop == null:
		death_carrier_loop = GRAYBOX_AUDIO_FACTORY.create_sustained_tone(160.0, 1.0, 0.10, 0.62)
	if perfect_sfx == null:
		perfect_sfx = GRAYBOX_AUDIO_FACTORY.create_transient(1040.0, 0.055, 0.20, 0.05)
	if good_sfx == null:
		good_sfx = GRAYBOX_AUDIO_FACTORY.create_transient(790.0, 0.06, 0.18, 0.18)
	if pass_sfx == null:
		pass_sfx = GRAYBOX_AUDIO_FACTORY.create_transient(560.0, 0.07, 0.17, 0.36)
	if miss_sfx == null:
		miss_sfx = GRAYBOX_AUDIO_FACTORY.create_transient(145.0, 0.12, 0.25, 0.85)


func _create_carrier_player(node_name: String, stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = output_bus
	player.stream = stream
	player.volume_db = carrier_idle_volume_db
	add_child(player)
	return player


func _update_carrier_player(
	player: AudioStreamPlayer,
	held: bool,
	frequency_hz: float,
	aligned: bool
) -> void:
	if not is_instance_valid(player) or player.stream == null:
		return
	if not held:
		if player.playing:
			player.stop()
		return
	player.pitch_scale = clampf(frequency_hz / _base_frequency_hz, 0.55, 1.75)
	player.volume_db = carrier_aligned_volume_db if aligned else carrier_idle_volume_db
	if not player.playing:
		player.play()


func _stop_carrier_players() -> void:
	for player: AudioStreamPlayer in [_life_carrier_player, _death_carrier_player]:
		if is_instance_valid(player):
			player.stop()


func _side_is_aligned(snapshot: Dictionary, affinity: int) -> bool:
	if not bool(snapshot.get("tuning_field_active", false)):
		return false
	var states: Variant = snapshot.get("active_tuning_sliders", [])
	if states is not Array:
		return false
	for raw_state: Variant in states:
		if raw_state is not Dictionary:
			continue
		var state: Dictionary = raw_state
		if int(state.get("affinity", GameplayTypes.Affinity.SU)) != affinity:
			continue
		if not bool(state.get("held", false)):
			continue
		var player_progress: float = float(state.get("player_progress", 0.0))
		var band_min: float = float(state.get("guide_band_min", 0.0))
		var band_max: float = float(state.get("guide_band_max", 0.0))
		if player_progress >= minf(band_min, band_max) and player_progress <= maxf(band_min, band_max):
			return true
	return false
