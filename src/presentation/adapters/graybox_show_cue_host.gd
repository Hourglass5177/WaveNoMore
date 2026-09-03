class_name GrayboxShowCueHost
extends Node2D

## StageShow 的无素材代理播放器。正式美术可替换这个节点，无需改演出数据或导演逻辑。

## 教学面板相对本节点的路径；接收 StageShow 中的教学轨事件。
@export var tutorial_panel_path: NodePath = ^"TutorialPanel"
## 教学文字 Label 的路径，必须位于上面的教学面板内。
@export var tutorial_label_path: NodePath = ^"TutorialPanel/Label"

# 缓存场景节点和当前 Tween，重复事件到来时可安全停止上一段淡入淡出。
var _tutorial_panel: Control
# 运行时创建的教学文字节点；只承载 StageShow 的短提示。
var _tutorial_label: Label
# 教学文字淡入淡出的补间动画；新提示出现时替换旧动画。
var _tutorial_tween: Tween
# 全屏闪光强度的补间动画；新闪光触发时替换旧动画。
var _flash_tween: Tween
# 持续演出按事件 ID 保存进度；瞬时演出只保存最近一条并用透明度淡出。
var _active_visual_cues: Dictionary[String, Dictionary] = {}
# 当前闪光演出指令的数据副本，例如颜色和持续时间。
var _flash_cue: Dictionary = {}
# 当前闪光的不透明度；0 完全透明，1 完全覆盖。
var _flash_alpha: float = 0.0


func _ready() -> void:
	_tutorial_panel = get_node(tutorial_panel_path) as Control
	_tutorial_label = get_node(tutorial_label_path) as Label
	_tutorial_panel.visible = false
	_tutorial_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE


func bind(director: Node) -> void:
	if not director.is_connected("cue_triggered", _on_cue_triggered):
		director.connect("cue_triggered", _on_cue_triggered)
	if not director.is_connected("cue_started", _on_cue_started):
		director.connect("cue_started", _on_cue_started)
	if not director.is_connected("cue_updated", _on_cue_updated):
		director.connect("cue_updated", _on_cue_updated)
	if not director.is_connected("cue_ended", _on_cue_ended):
		director.connect("cue_ended", _on_cue_ended)
	if not director.is_connected("director_reset", clear):
		director.connect("director_reset", clear)


func clear() -> void:
	_active_visual_cues.clear()
	_flash_cue.clear()
	_flash_alpha = 0.0
	if _tutorial_tween != null:
		_tutorial_tween.kill()
	if _flash_tween != null:
		_flash_tween.kill()
	_tutorial_panel.visible = false
	queue_redraw()


func _on_cue_triggered(cue: Dictionary) -> void:
	var parameters: Dictionary = cue.get("parameters", {})
	var tutorial_text: String = String(parameters.get("text", ""))
	if int(cue.get("track", -1)) == 5 or not tutorial_text.is_empty():
		_show_tutorial(tutorial_text, cue)
	if _is_visible_proxy_track(cue):
		_flash_cue = cue.duplicate(true)
		_flash_alpha = 1.0
		if _flash_tween != null:
			_flash_tween.kill()
		_flash_tween = create_tween()
		_flash_tween.tween_method(_set_flash_alpha, 1.0, 0.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_cue_started(cue: Dictionary) -> void:
	if not _is_visible_proxy_track(cue):
		return
	var entry: Dictionary = cue.duplicate(true)
	entry["progress"] = 0.0
	_active_visual_cues[String(cue.get("event_id", ""))] = entry
	queue_redraw()


func _on_cue_updated(cue: Dictionary, progress: float) -> void:
	var event_id: String = String(cue.get("event_id", ""))
	if not _active_visual_cues.has(event_id):
		return
	_active_visual_cues[event_id]["progress"] = clampf(progress, 0.0, 1.0)
	queue_redraw()


func _on_cue_ended(cue: Dictionary) -> void:
	_active_visual_cues.erase(String(cue.get("event_id", "")))
	queue_redraw()


func _show_tutorial(text: String, cue: Dictionary) -> void:
	if text.is_empty():
		return
	_tutorial_label.text = text
	_tutorial_panel.visible = true
	_tutorial_panel.modulate.a = 0.0
	if _tutorial_tween != null:
		_tutorial_tween.kill()
	var cue_duration_sec: float = float(int(cue.get("end_us", 0)) - int(cue.get("start_us", 0))) / 1_000_000.0
	var display_sec: float = maxf(float(cue.get("parameters", {}).get("display_sec", 2.4)), cue_duration_sec)
	_tutorial_tween = create_tween()
	_tutorial_tween.tween_property(_tutorial_panel, "modulate:a", 1.0, 0.16)
	_tutorial_tween.tween_interval(display_sec)
	_tutorial_tween.tween_property(_tutorial_panel, "modulate:a", 0.0, 0.32)
	_tutorial_tween.tween_callback(func() -> void: _tutorial_panel.visible = false)


func _set_flash_alpha(value: float) -> void:
	_flash_alpha = value
	queue_redraw()


func _is_visible_proxy_track(cue: Dictionary) -> bool:
	return int(cue.get("track", -1)) in [1, 2, 3]


func _draw() -> void:
	for cue: Dictionary in _active_visual_cues.values():
		_draw_cue_proxy(cue, float(cue.get("progress", 0.0)), 1.0)
	if not _flash_cue.is_empty() and _flash_alpha > 0.001:
		_draw_cue_proxy(_flash_cue, 0.5, _flash_alpha)


func _draw_cue_proxy(cue: Dictionary, progress: float, alpha: float) -> void:
	var parameters: Dictionary = cue.get("parameters", {})
	var intensity: float = clampf(float(parameters.get("intensity", 0.7)), 0.0, 1.5)
	var envelope: float = maxf(sin(clampf(progress, 0.0, 1.0) * PI), 0.18)
	var strength: float = clampf(intensity * envelope * alpha, 0.0, 1.0)
	if StringName(cue.get("cue_id", &"")) == &"open_tuning_rift":
		# 中央裂缝会和双侧粗滑条、游标抢视线。灰盒阶段暂不画它，把高对比信息留给操作本身。
		return
	var center: Vector2 = _target_center(StringName(cue.get("target_slot", &"world")))
	var seed: int = String(cue.get("event_id", "cue")).hash()
	var points := PackedVector2Array()
	for index: int in range(13):
		var ratio: float = float(index) / 12.0
		var x: float = lerpf(-430.0, 430.0, ratio)
		var jag: float = sin(float(index * 17 + abs(seed) % 31)) * (18.0 + strength * 35.0)
		points.append(center + Vector2(x, -x * 0.28 + jag))
	draw_polyline(points, Color(0.91, 0.86, 0.73, 0.20 + strength * 0.62), 2.0 + strength * 7.0, true)
	for shard_index: int in range(5):
		var anchor: Vector2 = points[2 + shard_index * 2]
		var sign_value: float = -1.0 if shard_index % 2 == 0 else 1.0
		var shard := PackedVector2Array([
			anchor,
			anchor + Vector2(20.0 + shard_index * 7.0, sign_value * (45.0 + strength * 70.0)),
			anchor + Vector2(56.0 + shard_index * 4.0, sign_value * 12.0),
		])
		draw_colored_polygon(shard, Color(0.58, 0.12, 0.11, strength * 0.16))


func _target_center(target_slot: StringName) -> Vector2:
	match target_slot:
		&"life", &"life_actor", &"life_world":
			return Vector2(430.0, 300.0)
		&"death", &"death_actor", &"death_world":
			return Vector2(1490.0, 780.0)
		&"boundary":
			return Vector2(960.0, 540.0)
		_:
			return Vector2(960.0, 540.0)
