@tool
class_name LevelCardCatalog
extends Resource

## 卡片轮转的横向半径，单位为 1920×1080 设计像素。
@export_range(100.0, 750.0, 1.0) var horizontal_radius: float = 480.0

@export var cards: Array[Resource] = []
