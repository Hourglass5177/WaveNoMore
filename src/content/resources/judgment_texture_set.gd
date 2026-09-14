@tool
class_name JudgmentTextureSet
extends Resource

## 判定反馈图片配置；空纹理时对应等级不显示。
@export var perfect: Texture2D
@export var good: Texture2D
@export var pass_texture: Texture2D
@export var miss: Texture2D
## 判定图片的统一等比缩放。
@export_range(0.01, 10.0, 0.01, "or_greater") var scale: float = 1.0
## 相对于判定区域中心的像素偏移。
@export var offset: Vector2 = Vector2.ZERO
