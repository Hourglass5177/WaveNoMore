class_name StageDebugHud
extends CanvasLayer

## 开发用运行时面板。集中显示时钟、输入所有权、调频、得分与内容哈希，便于复现音游时序问题。

## 调试文字 Label 相对本节点的路径；改场景树层级时要同步更新。
@export var label_path: NodePath = ^"Panel/Margin/Label"
## 是否随关卡默认显示。关闭后仍可由设置菜单或外部脚本重新打开。
@export var enabled_by_default: bool = true

# 缓存实际 Label 节点，避免每次收到调试快照都重新查找场景树。
var _label: Label


func _ready() -> void:
	layer = 30
	_label = get_node(label_path) as Label
	visible = enabled_by_default
	var panel := get_node_or_null(^"Panel") as Control
	if panel != null:
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(session: StageSession) -> void:
	if not session.debug_snapshot_ready.is_connected(_on_debug_snapshot):
		session.debug_snapshot_ready.connect(_on_debug_snapshot)


func set_debug_visible(value: bool) -> void:
	visible = value


func _on_debug_snapshot(snapshot: Dictionary) -> void:
	# X/Y 分别是生、死两路摇杆速率；频率值来自玩法快照，二者不要混为共同游标。
	var tuning_rate: Vector2 = snapshot.get("tuning_rate", Vector2.ZERO)
	var active_field_id: String = str(snapshot.get("active_tuning_field_id", ""))
	if active_field_id.is_empty():
		active_field_id = "-"
	_label.text = (
		"RUN %d  STATE %d  GEN %d\n"
		+ "AUDIO %8.4f  SONG %8.4f  JUDGE %8.4f  VIS %8.4f\n"
		+ "DRIFT %+7.2fms  OUT %+7.2fms  AUDIO %+7.2fms  INPUT %+7.2fms  VIS %+7.2fms\n"
		+ "OWNER %d  HELD 生:%s 死:%s  QUEUE %d\n"
		+ "FIELD %s  ACTIVE %s  SLIDERS %d\n"
		+ "生 VALUE %.3f  FREQ %.3fHz  RATE %+.2f\n"
		+ "死 VALUE %.3f  FREQ %.3fHz  RATE %+.2f\n"
		+ "SCORE %d  COMBO %d  SOUL %d  HASH %s"
	) % [
		int(snapshot.get("run_id", 0)),
		int(snapshot.get("stage_state", 0)),
		int(snapshot.get("clock_generation", 0)),
		float(snapshot.get("audio_time_raw_sec", 0.0)),
		float(snapshot.get("song_time_sec", 0.0)),
		float(snapshot.get("judge_time_sec", 0.0)),
		float(snapshot.get("visual_time_sec", 0.0)),
		float(snapshot.get("audio_drift_sec", 0.0)) * 1000.0,
		float(snapshot.get("output_latency_sec", 0.0)) * 1000.0,
		float(snapshot.get("audio_calibration_sec", 0.0)) * 1000.0,
		float(snapshot.get("input_compensation_sec", 0.0)) * 1000.0,
		float(snapshot.get("visual_lead_sec", 0.0)) * 1000.0,
		int(snapshot.get("input_owner", 0)),
		str(snapshot.get("life_held", false)),
		str(snapshot.get("death_held", false)),
		int(snapshot.get("pending_inputs", 0)),
		active_field_id,
		str(snapshot.get("tuning_field_active", false)),
		int(snapshot.get("active_tuning_slider_count", 0)),
		float(snapshot.get("life_tuning_value", 0.0)),
		float(snapshot.get("life_frequency_hz", 0.0)),
		tuning_rate.x,
		float(snapshot.get("death_tuning_value", 0.0)),
		float(snapshot.get("death_frequency_hz", 0.0)),
		tuning_rate.y,
		int(snapshot.get("score", 0)),
		int(snapshot.get("combo", 0)),
		int(snapshot.get("soul_fire", 0)),
		str(snapshot.get("content_hash", "")),
	]
