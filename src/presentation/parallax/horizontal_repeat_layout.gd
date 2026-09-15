@tool
class_name HorizontalRepeatLayout
extends RefCounted
## 确定性生成子层横向随机单元；单元与接缝只由资源配置和编号决定。

var entries: Array[StageBackgroundEntry] = []
var widths: Array[float] = []
var seed := 0
var gap_min := 0.0
var gap_max := 0.0
var units: Dictionary = {}
var first_index := 0
var last_index := 0

func configure(layer: StageBackgroundSubLayer) -> void:
	entries.assign(layer.entries)
	seed = layer.repeat_seed
	gap_min = layer.repeat_gap_min
	gap_max = layer.repeat_gap_max
	widths.clear(); units.clear(); first_index = 0; last_index = 0
	for entry in entries: widths.append(entry_size(entry).x * entry.uniform_scale)
	if not entries.is_empty(): units[0] = _unit(0, 0, entries[0].position.x)

static func entry_size(entry: StageBackgroundEntry) -> Vector2:
	if entry.texture != null: return entry.texture.get_size()
	if entry.sprite_frames != null and entry.sprite_frames.has_animation(entry.animation) and entry.sprite_frames.get_frame_count(entry.animation) > 0:
		var texture := entry.sprite_frames.get_frame_texture(entry.animation, 0)
		return texture.get_size() if texture != null else Vector2.ZERO
	return Vector2.ZERO

func _random(index: int, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + index * 1103515245 + salt * 12345
	return rng

func _entry_index(index: int) -> int:
	if index == 0: return 0
	return _random(index, 17).randi_range(0, entries.size() - 1)

func _gap(boundary_index: int) -> float:
	return _random(boundary_index, 31).randf_range(gap_min, gap_max)

func _unit(index: int, entry_index: int, left: float) -> Dictionary:
	var flip_rng := _random(index, 47)
	return {"index": index, "entry_index": entry_index, "left": left, "right": left + widths[entry_index], "flip_h": flip_rng.randi_range(0, 1) == 1, "flip_v": flip_rng.randi_range(0, 1) == 1}

func ensure_range(left: float, right: float) -> void:
	if entries.is_empty(): return
	while float(units[last_index].right) < right:
		var index := last_index + 1
		var entry_index := _entry_index(index)
		units[index] = _unit(index, entry_index, float(units[last_index].right) + _gap(last_index))
		last_index = index
	while float(units[first_index].left) > left:
		var index := first_index - 1
		var entry_index := _entry_index(index)
		var unit_right := float(units[first_index].left) - _gap(index)
		units[index] = _unit(index, entry_index, unit_right - widths[entry_index])
		first_index = index

func visible_units(left: float, right: float) -> Array[Dictionary]:
	ensure_range(left, right)
	var result: Array[Dictionary] = []
	for index in range(first_index, last_index + 1):
		var unit: Dictionary = units[index]
		if unit.right >= left and unit.left <= right: result.append(unit)
	return result

## 返回目标坐标左侧最近单元的起点，供换景选择真实随机接缝。
func boundary_before(value: float) -> float:
	ensure_range(value - 4096.0, value + 1.0)
	var result := float(units[first_index].left)
	for index in range(first_index, last_index + 1):
		var boundary := float(units[index].left)
		if boundary > value: break
		result = boundary
	return result
