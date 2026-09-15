@tool
class_name StageBackgroundSubLayer
extends Resource

## 稳定的资源标识。
@export var sublayer_id: String = "default"
## 编辑器显示名称。
@export var display_name: String = "default"
## 设计像素每秒，分别控制 X/Y；实际位移为 velocity * 歌曲时间 / depth。
## 正深度时正 X 向右、正 Y 向下；负深度反向，零深度保持静止。
@export var velocity: Vector2 = Vector2.ZERO
## 此子层的背景素材。
@export var entries: Array[StageBackgroundEntry] = []
## 开启后将本子层素材按 X 轴随机串接并无限延伸。
@export var horizontal_random_repeat: bool = false
@export var repeat_gap_min: float = 0.0
@export var repeat_gap_max: float = 0.0
@export var repeat_seed: int = 0

@export_group("循环与衔接")
## 跨背景沿用的子层身份；留空时兼容旧的“深度＋子层 ID”。
@export var continuity_id: String = ""
## 零向量沿实际滚动方向；非零向量用于美术明确循环边界方向。
@export var cycle_direction: Vector2 = Vector2.ZERO
## 起终点沿循环方向投影，单位为设计像素；相等时从素材组合外框推导。
@export var cycle_start: float = 0.0
@export var cycle_end: float = 0.0

func continuity_key(depth: int) -> String:
	return continuity_id if not continuity_id.is_empty() else "%d/%s" % [depth, sublayer_id]

func cycle(depth: int, camera_velocity := Vector2.ZERO) -> Dictionary:
	var velocity_actual := (velocity - camera_velocity) / float(depth) if depth != 0 else Vector2.ZERO
	var direction := Vector2.RIGHT if horizontal_random_repeat else (cycle_direction.normalized() if not cycle_direction.is_zero_approx() else velocity_actual.normalized())
	if direction.is_zero_approx(): direction = Vector2.RIGHT
	var lower := INF
	var upper := -INF
	for entry in entries:
		var texture := entry.texture
		if texture == null and entry.sprite_frames != null and entry.sprite_frames.has_animation(entry.animation) and entry.sprite_frames.get_frame_count(entry.animation) > 0:
			texture = entry.sprite_frames.get_frame_texture(entry.animation, 0)
		if texture == null and entry.scene == null: continue
		var extent := texture.get_size() if texture != null else entry.scene_size()
		var box := Rect2(entry.position, extent * entry.uniform_scale)
		for point in [box.position, box.end, Vector2(box.position.x, box.end.y), Vector2(box.end.x, box.position.y)]:
			lower = minf(lower, direction.dot(point)); upper = maxf(upper, direction.dot(point))
	if not is_finite(lower): lower = 0.0; upper = 1920.0
	if cycle_end > cycle_start: lower = cycle_start; upper = cycle_end
	return {"direction": direction, "start": lower, "end": upper, "length": maxf(1.0, upper - lower), "horizontal_random_repeat": horizontal_random_repeat, "repeat_gap_min": repeat_gap_min, "repeat_gap_max": repeat_gap_max, "repeat_seed": repeat_seed}
