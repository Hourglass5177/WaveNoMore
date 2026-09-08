class_name NoteHapticsFeedback
extends Node

## Tap 使用单次源，Hold 使用两侧独立的持续句柄；不拥有设备或计时器。

@export_group("Tap Pulse")
## 每次单次震动的持续时间，单位毫秒。
@export_range(1.0, 1000.0, 1.0, "or_greater") var pulse_duration_ms: float = 80.0
## 非 Perfect 的 Tap / Hold 头判共用基础强度；Perfect 使用 1.0，再统一应用管理层倍率。
@export_range(0.0, 1.0, 0.01) var pulse_strength: float = 0.35
## 请求频率 Hz；只有强度输出的设备忽略此值。
@export_range(1.0, 1000.0, 1.0, "or_greater") var pulse_frequency_hz: float = 120.0

@export_group("Hold Sustain")
## Hold 请求频率 = 对应侧钟的当前发波频率 × 此倍率；零值关闭 Hold 贡献。
## 后续仍参与管理层合并和全局倍率，只有频率后端实际采用请求频率。
@export_range(0.0, 100.0, 0.01, "or_greater") var hold_frequency_multiplier: float = 1.0

var _session: StageSession
var _haptics: ControllerHaptics
## 同侧任一真 Hold 处于逻辑 holding 即保留贡献；强引用让持续源存活。
var _life_hold_handle: HapticHandle
var _death_hold_handle: HapticHandle


func bind(session: StageSession, haptics: ControllerHaptics) -> void:
	## StageRoot 注入共享节点；Tap 旁听判定，Hold 旁听权威玩法快照。
	unbind()
	_session = session
	_haptics = haptics
	_session.judgment_recorded.connect(_on_judgment_recorded)
	_session.gameplay_snapshot_changed.connect(_on_gameplay_snapshot_changed)
	_session.state_changed.connect(_on_state_changed)
	_session.timeline_seeked.connect(_on_timeline_seeked)
	_session.run_started.connect(_on_run_started)


func unbind() -> void:
	## 只解除自身监听，不全局停止其他调用方的句柄或单次震动。
	if is_instance_valid(_session):
		_session.judgment_recorded.disconnect(_on_judgment_recorded)
		_session.gameplay_snapshot_changed.disconnect(_on_gameplay_snapshot_changed)
		_session.state_changed.disconnect(_on_state_changed)
		_session.timeline_seeked.disconnect(_on_timeline_seeked)
		_session.run_started.disconnect(_on_run_started)
	_release_hold_handles()
	_session = null
	_haptics = null


func _exit_tree() -> void:
	## 场景回收不残留会话信号。
	unbind()


func _on_judgment_recorded(record: JudgmentRecord) -> void:
	## 生左、死右。Hold 由快照驱动持续源，不在此处触发单次震动。
	if not is_instance_valid(_session) or _session.external_preview or not is_instance_valid(_haptics):
		return
	if _session.state not in [GameplayTypes.StageState.PREROLL, GameplayTypes.StageState.PLAYING]:
		return
	if record.unit_kind != &"tap" or record.grade == GameplayTypes.JudgmentGrade.MISS:
		return
	var strength: float = 1.0 if record.grade == GameplayTypes.JudgmentGrade.PERFECT else pulse_strength
	if record.affinity == GameplayTypes.Affinity.ZHU:
		_haptics.play_once(ControllerHaptics.MotorSide.LEFT, strength, pulse_frequency_hz, pulse_duration_ms)
	elif record.affinity == GameplayTypes.Affinity.XUAN:
		_haptics.play_once(ControllerHaptics.MotorSide.RIGHT, strength, pulse_frequency_hz, pulse_duration_ms)


func _on_gameplay_snapshot_changed(snapshot: Dictionary) -> void:
	## holding 包含松开宽限，不看物理 held；完成、Miss、取消后 ID 为空。
	## 快照频率与 Gameplay 提交 Carrier.set_all_frequencies() 的频率同源。
	if not is_instance_valid(_session) or not is_instance_valid(_haptics):
		return
	if _session.external_preview:
		_release_hold_handles()
		return
	if _session.state == GameplayTypes.StageState.PAUSED:
		return # 管理层暂停输出但保留持续句柄，恢复不补播单次源。
	if _session.state not in [GameplayTypes.StageState.PREROLL, GameplayTypes.StageState.PLAYING]:
		_release_hold_handles()
		return
	_life_hold_handle = _sync_hold_handle(
		_life_hold_handle, ControllerHaptics.MotorSide.LEFT,
		not str(snapshot.get("life_holding_note_id", "")).is_empty(),
		float(snapshot.get("life_frequency_hz", 0.0)) * hold_frequency_multiplier,
		1.0 if bool(snapshot.get("life_perfect_holding", false)) else pulse_strength
	)
	_death_hold_handle = _sync_hold_handle(
		_death_hold_handle, ControllerHaptics.MotorSide.RIGHT,
		not str(snapshot.get("death_holding_note_id", "")).is_empty(),
		float(snapshot.get("death_frequency_hz", 0.0)) * hold_frequency_multiplier,
		1.0 if bool(snapshot.get("death_perfect_holding", false)) else pulse_strength
	)


func _sync_hold_handle(handle: HapticHandle, side: int, is_holding: bool, frequency_hz: float, strength: float) -> HapticHandle:
	## 每侧一个源：同侧频率相同，头判 Perfect 的 1.0 优先于普通强度；不叠加。
	if not is_holding or not is_finite(frequency_hz) or frequency_hz <= 0.0 \
			or not is_finite(strength) or strength < 0.0 or strength > 1.0:
		if handle != null:
			handle.release()
		return null
	if handle == null or not handle.is_valid():
		# clear 后的旧句柄不复活；仅依据新快照重新申请。
		handle = _haptics.create_handle(side, strength, frequency_hz)
	else:
		handle.set_frequency(frequency_hz)
		handle.set_strength(strength)
	if handle != null:
		handle.set_enabled(true)
	return handle


func _release_hold_handles() -> void:
	## 不调用共享 clear/stop，Tap 和其他调用方的贡献不受此节点清理影响。
	if _life_hold_handle != null:
		_life_hold_handle.release()
		_life_hold_handle = null
	if _death_hold_handle != null:
		_death_hold_handle.release()
		_death_hold_handle = null


func _on_state_changed(_previous: int, current: int, _reason: StringName) -> void:
	## 暂停只由管理层门控；非运行状态释放本节点持有的源。
	if current not in [GameplayTypes.StageState.PREROLL, GameplayTypes.StageState.PLAYING, GameplayTypes.StageState.PAUSED]:
		_release_hold_handles()


func _on_timeline_seeked(_song_time_sec: float) -> void:
	## 新时间线不沿用旧 Hold；下一份权威快照再决定是否创建新句柄。
	_release_hold_handles()


func _on_run_started(_run_id: int) -> void:
	## 重试/新局清除强引用，不能自动重启上一局的持续贡献。
	_release_hold_handles()
