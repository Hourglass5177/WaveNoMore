## ArtLab 预览画布：实例化交付场景本体，并在同一坐标系中标出边界、轴心和锚点。
class_name MingheArtLabCanvas
extends Control

## 当前预览的判定等级；赋值时同步通知素材并重绘辅助标记。
var judgment: int = GameplayTypes.JudgmentGrade.PERFECT:
	set(value):
		judgment = clampi(value, GameplayTypes.JudgmentGrade.PERFECT, GameplayTypes.JudgmentGrade.MISS)
		_apply_judgment()
		queue_redraw()
## 预览用的质量档位，只用于检查素材在不同特效密度下的表现。
var quality_level: int = 1:
	set(value):
		quality_level = clampi(value, 0, 2)
		if _preview_instance != null and _preview_instance.has_method("art_lab_set_quality"):
			_preview_instance.call("art_lab_set_quality", quality_level)
		queue_redraw()
## 模拟背景遮挡压力，数值越高，画布叠加的干扰元素越多。
var background_pressure: int = 1:
	set(value):
		background_pressure = clampi(value, 0, 2)
		queue_redraw()
## 是否画出屏幕安全区，便于检查重要内容会不会贴边或被裁切。
var show_safe_area: bool = true:
	set(value):
		show_safe_area = value
		queue_redraw()

## 当前选中的美术清单条目；为空表示尚未选择素材。
var _entry: VisualAssetEntry
## 从 `_entry.runtime_scene` 实例化的真实预览节点；替换条目时先释放旧实例。
var _preview_instance: Node
## 当前要求素材展示的状态名，例如 prepare、active 或 miss。
var _selected_state: StringName = &"prepare"
## 0～1 循环的演示相位，只驱动预览动画和辅助线，不代表歌曲时间。
var _pulse: float = 0.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout_preview_instance)
	set_process(true)


func _process(delta: float) -> void:
	_pulse = fposmod(_pulse + delta, 1.0)
	if _preview_instance != null and _preview_instance.has_method("art_lab_set_progress"):
		_preview_instance.call("art_lab_set_progress", _pulse)
	queue_redraw()


## 不画替代缩略图：只有 Manifest 指向的 runtime_scene 能实例化，预览才算成功。
func set_manifest_entry(entry) -> bool:
	_clear_preview_instance()
	_entry = entry
	if entry == null or entry.runtime_scene == null or not entry.runtime_scene.can_instantiate():
		queue_redraw()
		return false
	_preview_instance = entry.runtime_scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
	if _preview_instance == null or not _preview_instance is CanvasItem:
		_clear_preview_instance()
		queue_redraw()
		return false
	add_child(_preview_instance)
	if _preview_instance.has_method("configure_from_manifest"):
		_preview_instance.call("configure_from_manifest", entry)
	_selected_state = StringName(entry.required_states[0]) if not entry.required_states.is_empty() else &""
	_layout_preview_instance()
	apply_state(_selected_state)
	_apply_judgment()
	if _preview_instance.has_method("art_lab_set_quality"):
		_preview_instance.call("art_lab_set_quality", quality_level)
	queue_redraw()
	return true


## 角色状态优先通过 AnimationPlayer 播放；其他资源走统一状态接口，让美术可自由选择实现方式。
func apply_state(state: StringName) -> bool:
	_selected_state = state
	if _preview_instance == null:
		return false
	if _entry != null and _entry.category == &"actor":
		var player := _preview_instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player != null and player.has_animation(state):
			player.play(state)
			if _preview_instance.has_method("art_lab_set_state"):
				_preview_instance.call("art_lab_set_state", state, {})
			return true
	if _preview_instance.has_method("art_lab_set_state"):
		var accepted: Variant = _preview_instance.call("art_lab_set_state", state, {})
		return not (accepted is bool) or bool(accepted)
	return false


func get_preview_instance() -> Node:
	return _preview_instance


func get_manifest_entry() -> VisualAssetEntry:
	return _entry


func _apply_judgment() -> void:
	if _preview_instance != null and _preview_instance.has_method("art_lab_set_judgment"):
		_preview_instance.call("art_lab_set_judgment", judgment)


func _clear_preview_instance() -> void:
	if _preview_instance == null:
		return
	if _preview_instance.get_parent() == self:
		remove_child(_preview_instance)
	_preview_instance.free()
	_preview_instance = null


## 缩放依据 Manifest 声明的可视边界，不依赖源素材自身的像素尺寸。
func _layout_preview_instance() -> void:
	if _preview_instance == null or _entry == null or size.x <= 1.0 or size.y <= 1.0:
		return
	var bounds := _entry.visual_bounds
	var usable := Vector2(size.x * 0.48, size.y * 0.58)
	var fit_scale := minf(usable.x / maxf(bounds.size.x, 1.0), usable.y / maxf(bounds.size.y, 1.0))
	fit_scale = clampf(fit_scale, 0.18, 2.4)
	var origin := size * 0.5 - _entry.pivot * fit_scale
	if _preview_instance is Node2D:
		var node := _preview_instance as Node2D
		node.position = origin
		node.scale = Vector2.ONE * fit_scale
	elif _preview_instance is Control:
		var control := _preview_instance as Control
		control.position = origin
		control.scale = Vector2.ONE * fit_scale
	queue_redraw()


func _draw() -> void:
	var area := Rect2(Vector2.ZERO, size)
	draw_rect(area, Color("090b11"))
	var life_polygon := PackedVector2Array([
		Vector2.ZERO,
		Vector2(size.x, 0),
		Vector2(size.x * 0.37, size.y * 0.63),
		Vector2(0, size.y),
	])
	draw_colored_polygon(life_polygon, Color("3b0b0a"))
	_draw_world_layers()
	_draw_boundary()
	if show_safe_area:
		draw_rect(Rect2(size * 0.05, size * 0.90), Color(0.95, 0.86, 0.68, 0.24), false, 2.0)
	_draw_entry_contract()
	_draw_metadata()


func _draw_world_layers() -> void:
	var layer_count := 2 + quality_level
	for index: int in layer_count:
		var t := float(index + 1) / float(layer_count + 1)
		var y := lerpf(size.y * 0.14, size.y * 0.45, t)
		var points := PackedVector2Array()
		for step: int in 9:
			var x := float(step) / 8.0 * size.x
			points.append(Vector2(x, y + sin(step * 1.6 + index) * (18.0 + index * 9.0)))
		draw_polyline(points, Color(0.76, 0.26, 0.20, 0.07 + index * 0.025), 8.0 + index * 5.0)
		var mirrored := PackedVector2Array()
		for point: Vector2 in points:
			mirrored.append(size - point)
		draw_polyline(mirrored, Color(0.40, 0.43, 0.56, 0.06 + index * 0.025), 8.0 + index * 5.0)
	if background_pressure >= 2:
		for index: int in 24:
			var seed := float(index * 97 % 101) / 101.0
			var point := Vector2(seed * size.x, fposmod(index * 67.0, size.y))
			draw_circle(point, 1.5 + float(index % 3), Color(0.92, 0.86, 0.72, 0.16))


func _draw_boundary() -> void:
	var points := PackedVector2Array()
	for step: int in 33:
		var t := float(step) / 32.0
		var x := lerpf(-40.0, size.x + 40.0, t)
		var base_y := lerpf(size.y * 0.82, size.y * 0.18, t)
		var wave := sin(t * TAU * 3.0 + _pulse * TAU) * (5.0 + background_pressure * 2.0)
		points.append(Vector2(x, base_y + wave))
	draw_polyline(points, Color(0.93, 0.87, 0.70, 0.48), 3.0, true)
	var marker_index := clampi(int(_pulse * 32.0), 0, 32)
	draw_circle(points[marker_index], 8.0, Color("f0e4bd"))


func _draw_entry_contract() -> void:
	if _entry == null or _preview_instance == null:
		return
	var bounds := _entry.visual_bounds
	var corners := PackedVector2Array([
		_root_point_to_canvas(bounds.position),
		_root_point_to_canvas(Vector2(bounds.end.x, bounds.position.y)),
		_root_point_to_canvas(bounds.end),
		_root_point_to_canvas(Vector2(bounds.position.x, bounds.end.y)),
	])
	draw_polyline(PackedVector2Array(corners + PackedVector2Array([corners[0]])), Color(0.96, 0.78, 0.35, 0.72), 2.0, true)
	var pivot_point := _root_point_to_canvas(_entry.pivot)
	draw_line(pivot_point - Vector2(12, 0), pivot_point + Vector2(12, 0), Color("f7f1d2"), 2.0)
	draw_line(pivot_point - Vector2(0, 12), pivot_point + Vector2(0, 12), Color("f7f1d2"), 2.0)
	for anchor_name: String in _entry.required_anchors:
		var anchor := _preview_instance.find_child(anchor_name, true, false) as CanvasItem
		if anchor == null:
			continue
		var anchor_point := _canvas_item_to_canvas(anchor)
		draw_circle(anchor_point, 6.0, Color("71d0c3"))
		draw_string(ThemeDB.fallback_font, anchor_point + Vector2(9, -7), anchor_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("bce9df"))


func _draw_metadata() -> void:
	if _entry == null:
		draw_string(ThemeDB.fallback_font, Vector2(24, 36), "未选择 Manifest 资产", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("d9cda8"))
		return
	var scene_path := _entry.runtime_scene.resource_path if _entry.runtime_scene != null else "<missing>"
	var lines := PackedStringArray([
		"%s · %s%s" % [_entry.asset_id, _entry.category, " · PLACEHOLDER" if _entry.placeholder else ""],
		"state: %s · judgment: %s" % [_selected_state, GameplayTypes.grade_name(judgment)],
		"scene: %s" % scene_path,
	])
	for index: int in lines.size():
		draw_string(ThemeDB.fallback_font, Vector2(24, 34 + index * 22), lines[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("d9cda8"))


func _root_point_to_canvas(point: Vector2) -> Vector2:
	if _preview_instance == null or not _preview_instance is CanvasItem:
		return point
	var root_transform := (_preview_instance as CanvasItem).get_global_transform_with_canvas()
	var canvas_inverse := get_global_transform_with_canvas().affine_inverse()
	return canvas_inverse * (root_transform * point)


func _canvas_item_to_canvas(item: CanvasItem) -> Vector2:
	var canvas_inverse := get_global_transform_with_canvas().affine_inverse()
	return canvas_inverse * item.get_global_transform_with_canvas().origin
