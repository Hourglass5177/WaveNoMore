@tool
class_name StageBackgroundLayer
extends Resource

## 该层的有符号深度；零层不产生任何视差或主动位移。
@export var depth: int = 1
## 同深度下按数组顺序绘制的子层。
@export var sublayers: Array[StageBackgroundSubLayer] = []
