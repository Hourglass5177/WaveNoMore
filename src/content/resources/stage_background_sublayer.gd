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
