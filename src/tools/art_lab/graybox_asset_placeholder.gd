## 正式美术尚未接入时使用的通用占位场景；它模拟交付接口，但不规定最终素材结构。
@tool
class_name MingheGrayboxAssetPlaceholder
extends Node2D

## 占位素材承诺支持的状态全集，用它补齐角色 AnimationPlayer 中的空动画。
const SUPPORTED_STATES := [
	"idle_loop", "strike", "hold_start", "hold_loop", "hold_release",
	"rapid_loop", "damage", "fail", "stage_intro", "stage_outro",
	"prepare", "approach", "target_near", "hold", "release", "active",
	"perfect", "good", "pass", "miss", "trigger", "obtain", "advanced_idle",
]

## 灰盒主色，可在 Inspector 中覆盖；判定状态会在此颜色基础上混色。
@export var tint: Color = Color("e7dfca")
## 模拟的素材类别，如 actor、note、field；它决定 `_draw()` 选择哪种轮廓。
@export var asset_kind: StringName = &"note"

## 当前清单中的稳定素材 ID；默认值只用于尚未配置的独立预览。
var _asset_id: String = "graybox"
## Manifest 声明的本地可视范围，单位为设计画布像素。
var _visual_bounds := Rect2(-128.0, -128.0, 256.0, 256.0)
## 素材的本地对齐轴心，绘制前作为变换原点使用。
var _pivot := Vector2.ZERO
## ArtLab 最近一次施加的表现状态。
var _current_state: StringName = &"prepare"
## 最近一次判定等级，使用 `GameplayTypes.JudgmentGrade` 的整数值。
var _judgment: int = GameplayTypes.JudgmentGrade.PERFECT
## 0～1 的机制演示进度，例如 Hold 游标或场域扩散进度。
var _progress: float = 0.0
## 0、1、2 三档预览质量；只改变灰盒细节量，不改变合同。
var _quality_level: int = 1
## 独立循环的视觉相位，只驱动呼吸和波纹，不参与玩法时间。
var _pulse: float = 0.0


func _ready() -> void:
	_ensure_state_animations()
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_pulse = fposmod(_pulse + delta, 1.0)
	queue_redraw()


func configure_from_manifest(entry: VisualAssetEntry) -> void:
	if entry == null:
		return
	_asset_id = entry.asset_id
	asset_kind = entry.category
	_visual_bounds = entry.visual_bounds
	_pivot = entry.pivot
	for anchor_name: String in entry.anchors:
		var anchor := find_child(anchor_name, true, false) as Node2D
		if anchor != null:
			anchor.position = Vector2(entry.anchors[anchor_name])
	_tint_for_entry()
	_ensure_state_animations()
	queue_redraw()


func art_lab_set_state(state: StringName, _payload: Dictionary = {}) -> bool:
	if String(state) not in SUPPORTED_STATES:
		return false
	_current_state = state
	var player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player != null and player.has_animation(state):
		player.play(state)
	queue_redraw()
	return true


func art_lab_set_judgment(grade: int) -> bool:
	if grade < GameplayTypes.JudgmentGrade.PERFECT or grade > GameplayTypes.JudgmentGrade.MISS:
		return false
	_judgment = grade
	_current_state = GameplayTypes.grade_name(grade).to_lower()
	queue_redraw()
	return true


func art_lab_set_progress(value: float) -> void:
	_progress = clampf(value, 0.0, 1.0)
	queue_redraw()


func art_lab_set_quality(level: int) -> void:
	_quality_level = clampi(level, 0, 2)
	queue_redraw()


func art_lab_supported_states() -> PackedStringArray:
	return PackedStringArray(SUPPORTED_STATES)


func _ensure_state_animations() -> void:
	# 占位角色也必须满足真实动画接入要求，因此补空动画，而不在校验器中为它开后门。
	var player := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player == null:
		return
	var library: AnimationLibrary
	if player.has_animation_library(&""):
		library = player.get_animation_library(&"")
	else:
		library = AnimationLibrary.new()
		player.add_animation_library(&"", library)
	for state: String in SUPPORTED_STATES:
		if library.has_animation(state):
			continue
		var animation := Animation.new()
		animation.resource_name = state
		animation.length = 0.36 if state != "idle_loop" else 1.0
		animation.loop_mode = Animation.LOOP_LINEAR if state.ends_with("loop") else Animation.LOOP_NONE
		library.add_animation(state, animation)


func _tint_for_entry() -> void:
	if _asset_id.contains("zhu") or _asset_id.contains("life"):
		tint = Color("d64b3c")
	elif _asset_id.contains("xuan") or _asset_id.contains("death"):
		tint = Color("66708e")
	elif _asset_id.contains("su") or asset_kind == &"field":
		tint = Color("e7ddba")
	else:
		tint = Color("d6c391")


func _draw() -> void:
	var state_scale := 1.0
	if _current_state in [&"strike", &"perfect", &"trigger"]:
		state_scale = 1.08 + 0.04 * sin(_pulse * TAU)
	elif _current_state in [&"miss", &"fail", &"damage"]:
		state_scale = 0.92
	var state_color := tint
	match _judgment:
		GameplayTypes.JudgmentGrade.GOOD:
			state_color = tint.lerp(Color("c3a56d"), 0.35)
		GameplayTypes.JudgmentGrade.PASS:
			state_color = tint.lerp(Color("7f776b"), 0.48)
		GameplayTypes.JudgmentGrade.MISS:
			state_color = tint.lerp(Color("751720"), 0.64)

	draw_set_transform(_pivot, 0.0, Vector2.ONE * state_scale)
	match asset_kind:
		&"actor":
			_draw_actor(state_color)
		&"field":
			_draw_field(state_color)
		&"follower":
			_draw_follower(state_color)
		_:
			if _asset_id.contains("hold"):
				_draw_hold(state_color)
			else:
				_draw_note(state_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_actor(color: Color) -> void:
	var bounds := _visual_bounds.grow(-maxf(12.0, minf(_visual_bounds.size.x, _visual_bounds.size.y) * 0.06))
	var body := PackedVector2Array([
		Vector2(bounds.position.x + bounds.size.x * 0.22, bounds.end.y),
		Vector2(bounds.position.x + bounds.size.x * 0.30, bounds.position.y + bounds.size.y * 0.30),
		Vector2(bounds.position.x + bounds.size.x * 0.50, bounds.position.y),
		Vector2(bounds.position.x + bounds.size.x * 0.72, bounds.position.y + bounds.size.y * 0.34),
		Vector2(bounds.position.x + bounds.size.x * 0.82, bounds.end.y),
	])
	draw_colored_polygon(body, Color(color, 0.22))
	draw_polyline(PackedVector2Array(body + PackedVector2Array([body[0]])), color, 4.0, true)
	var bell_center := Vector2(bounds.end.x - bounds.size.x * 0.12, bounds.position.y + bounds.size.y * 0.55)
	draw_arc(bell_center, bounds.size.x * 0.20, PI, TAU, 24, color, 5.0, true)
	draw_line(bell_center + Vector2(-bounds.size.x * 0.20, 0), bell_center + Vector2(bounds.size.x * 0.20, 0), color, 5.0)
	if _quality_level > 0:
		var radius := bounds.size.x * (0.24 + _pulse * 0.30)
		draw_arc(bell_center, radius, 0.0, TAU, 48, Color(color, 0.34 * (1.0 - _pulse)), 3.0, true)


func _draw_note(color: Color) -> void:
	var radius := minf(_visual_bounds.size.x, _visual_bounds.size.y) * 0.34
	var center := _visual_bounds.get_center()
	var points := PackedVector2Array()
	for index: int in 8:
		var angle := TAU * float(index) / 8.0 + PI * 0.125
		var length := radius if index % 2 == 0 else radius * 0.58
		points.append(center + Vector2.from_angle(angle) * length)
	draw_colored_polygon(points, Color(color, 0.26))
	draw_polyline(PackedVector2Array(points + PackedVector2Array([points[0]])), color, 4.0, true)
	draw_circle(center, radius * (0.24 + _progress * 0.18), Color(color, 0.58), false, 3.0)


func _draw_hold(color: Color) -> void:
	var bounds := _visual_bounds.grow(-12.0)
	var start := Vector2(bounds.position.x, bounds.get_center().y)
	var finish := Vector2(bounds.end.x, bounds.get_center().y)
	var half_height := bounds.size.y * 0.28
	var ribbon := PackedVector2Array([
		start + Vector2(0, -half_height), start + Vector2(0, half_height),
		finish + Vector2(0, half_height), finish + Vector2(0, -half_height),
	])
	draw_colored_polygon(ribbon, Color(color, 0.22))
	draw_polyline(PackedVector2Array([start, finish]), color, 5.0, true)
	draw_circle(start, half_height * 1.15, color, false, 4.0)
	draw_circle(start.lerp(finish, _progress), half_height * 0.52, Color(color, 0.86))


func _draw_field(color: Color) -> void:
	var center := _visual_bounds.get_center()
	var radius := minf(_visual_bounds.size.x, _visual_bounds.size.y) * 0.42
	for ring: int in 3 + _quality_level:
		var phase := fposmod(_pulse + float(ring) / float(3 + _quality_level), 1.0)
		draw_arc(center, radius * phase, 0.0, TAU, 64, Color(color, 0.48 * (1.0 - phase)), 3.0, true)
	for spoke: int in 10:
		var angle := TAU * float(spoke) / 10.0 + _pulse * 0.3
		draw_line(center, center + Vector2.from_angle(angle) * radius, Color(color, 0.12), 2.0)


func _draw_follower(color: Color) -> void:
	var center := _visual_bounds.get_center()
	var scale_hint := minf(_visual_bounds.size.x, _visual_bounds.size.y) / 256.0
	var body := PackedVector2Array([
		center + Vector2(-72, 50) * scale_hint,
		center + Vector2(-48, -34) * scale_hint,
		center + Vector2(-10, -64) * scale_hint,
		center + Vector2(12, -24) * scale_hint,
		center + Vector2(54, -58) * scale_hint,
		center + Vector2(76, 44) * scale_hint,
	])
	draw_colored_polygon(body, Color(color, 0.23))
	draw_polyline(PackedVector2Array(body + PackedVector2Array([body[0]])), color, 4.0, true)
	if _current_state == &"advanced_idle":
		draw_arc(center, 92.0 * scale_hint, 0.0, TAU, 48, Color(color, 0.38), 3.0, true)
