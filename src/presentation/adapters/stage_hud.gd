class_name StageHud
extends CanvasLayer

## 关卡 HUD。监听 Session 和 SongClock，显示魂火、得分、连击、判定与歌曲进度。

@export_group("Scene Wiring")
## 魂火进度条路径；其最大值和当前值来自 StageSession 的 health_changed。
@export var soul_fire_bar_path: NodePath = ^"Root/Margin/Layout/TopRow/SoulFireBar"
## 魂火数字 Label 路径，显示“当前值 / 上限”。
@export var soul_fire_value_path: NodePath = ^"Root/Margin/Layout/TopRow/SoulFireValue"
## 总分 Label 路径；画面会用 Tween 平滑追到真实整数分数。
@export var score_label_path: NodePath = ^"Root/Margin/Layout/TopRow/ScoreLabel"
## 连击 Label 路径；连击归零时隐藏文字。
@export var combo_label_path: NodePath = ^"Root/Margin/Layout/ComboLabel"
## 最近一次判定文字路径，位于共同中心附近并短暂淡出。
@export var judgment_label_path: NodePath = ^"Root/JudgmentLabel"
## 歌曲总进度条路径，取值为 0～100，不参与谱面判定。
@export var song_progress_path: NodePath = ^"Root/SongProgress"

# 这些字段缓存场景中的控件，避免每次刷新 HUD 都重新查找节点。
var _soul_fire_bar: ProgressBar
# 显示当前魂火数值的文字节点。
var _soul_fire_value: Label
# 显示当前得分的文字节点。
var _score_label: Label
# 显示当前连击数的文字节点。
var _combo_label: Label
# 短暂显示本次 Perfect、Good 或 Miss 结果的文字节点。
var _judgment_label: Label
# 显示歌曲播放进度的进度条节点；0 是开头，满值是关卡结束。
var _song_progress: ProgressBar
# 歌曲时长单位为秒，至少为 0.001；用于换算总进度条百分比。
var _song_duration_sec: float = 1.0
# 显示分数与真实分数分开保存，Tween 才能从当前画面值平滑过渡。
var _displayed_score: int = 0
# 保存正在运行的 Tween，下一次更新前先停止，避免多个动画同时改同一属性。
var _score_tween: Tween
# 当前判定文字的淡出补间；新判定出现前会停止旧补间。
var _judgment_tween: Tween


func _ready() -> void:
	layer = 10
	_soul_fire_bar = get_node(soul_fire_bar_path) as ProgressBar
	_soul_fire_value = get_node(soul_fire_value_path) as Label
	_score_label = get_node(score_label_path) as Label
	_combo_label = get_node(combo_label_path) as Label
	_judgment_label = get_node(judgment_label_path) as Label
	_song_progress = get_node(song_progress_path) as ProgressBar
	_soul_fire_bar.step = 0.0
	_song_progress.step = 0.0
	# HUD 只展示信息，必须让鼠标穿透到底层 InputRouter，否则左右鼠标敲钟会失效。
	_set_mouse_filter_recursive(self, Control.MOUSE_FILTER_IGNORE)


func configure(stage: StageDefinition) -> void:
	_song_duration_sec = 1.0
	if stage == null or stage.song == null:
		return
	if stage.song.audio_stream != null and stage.song.audio_stream.get_length() > 0.0:
		_song_duration_sec = maxf(stage.song.audio_stream.get_length() - stage.song.first_beat_offset_sec, 0.001)
	else:
		_song_duration_sec = maxf(stage.song.fallback_duration_sec, 0.001)


func set_song_duration(duration_sec: float) -> void:
	_song_duration_sec = maxf(duration_sec, 0.001)


func bind(session: StageSession, clock: SongClock) -> void:
	if not session.health_changed.is_connected(_on_health_changed):
		session.health_changed.connect(_on_health_changed)
	if not session.score_changed.is_connected(_on_score_changed):
		session.score_changed.connect(_on_score_changed)
	if not session.judgment_recorded.is_connected(_on_judgment_recorded):
		session.judgment_recorded.connect(_on_judgment_recorded)
	if not clock.sample_published.is_connected(_on_clock_sample):
		clock.sample_published.connect(_on_clock_sample)


func _on_health_changed(current: int, maximum: int) -> void:
	_soul_fire_bar.max_value = max(maximum, 1)
	_soul_fire_value.text = "%d / %d" % [current, maximum]
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_soul_fire_bar, "value", current, 0.18)


func _on_score_changed(score: int, combo: int) -> void:
	if _score_tween != null:
		_score_tween.kill()
	_score_tween = create_tween()
	_score_tween.set_trans(Tween.TRANS_QUAD)
	_score_tween.set_ease(Tween.EASE_OUT)
	_score_tween.tween_method(_set_displayed_score, float(_displayed_score), float(score), 0.22)
	_combo_label.text = "连响  %d" % combo if combo > 0 else ""
	if combo > 0 and combo % 10 == 0:
		_combo_label.scale = Vector2(1.20, 0.82)
		var combo_tween := create_tween()
		combo_tween.set_trans(Tween.TRANS_BACK)
		combo_tween.set_ease(Tween.EASE_OUT)
		combo_tween.tween_property(_combo_label, "scale", Vector2.ONE, 0.18)


func _on_judgment_recorded(record: JudgmentRecord) -> void:
	var grade_name: String = GameplayTypes.grade_name(record.grade)
	_judgment_label.text = grade_name
	_judgment_label.modulate = _grade_color(record.grade)
	_judgment_label.modulate.a = 1.0
	_judgment_label.scale = Vector2(1.25, 0.78)
	if _judgment_tween != null:
		_judgment_tween.kill()
	_judgment_tween = create_tween()
	_judgment_tween.set_parallel(true)
	_judgment_tween.tween_property(_judgment_label, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_judgment_tween.tween_property(_judgment_label, "modulate:a", 0.0, 0.42).set_delay(0.20)


func _on_clock_sample(sample: ClockSample) -> void:
	_song_progress.value = clampf(sample.song_time_sec / _song_duration_sec, 0.0, 1.0) * 100.0


func _set_displayed_score(value: float) -> void:
	_displayed_score = roundi(value)
	_score_label.text = "%08d" % _displayed_score


func _grade_color(grade: int) -> Color:
	match grade:
		GameplayTypes.JudgmentGrade.PERFECT:
			return Color("eee5ce")
		GameplayTypes.JudgmentGrade.GOOD:
			return Color("c7ad7b")
		GameplayTypes.JudgmentGrade.PASS:
			return Color("9d8972")
		_:
			return Color("6f7380")


func _set_mouse_filter_recursive(node: Node, filter: Control.MouseFilter) -> void:
	if node is Control:
		(node as Control).mouse_filter = filter
	for child: Node in node.get_children():
		_set_mouse_filter_recursive(child, filter)
