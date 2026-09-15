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
## 可见笔画的统一高度；旧 scale 继续作为整体尺寸倍率。
@export var glyph_height: float = 480.0
## 每次判定选定一个微小位置，整段动画保持不动。
@export var position_jitter_px: float = 2.0
@export_range(0.0,1.0,0.01) var opacity: float = 0.7
## 设计画布像素，不随四张源图尺寸改变。
@export var glow_radius_px: float = 12.0
@export var glow_strength: float = 1.5
@export var perfect_color := Color("ffba48")
@export var good_color := Color("77d68d")
@export var pass_color := Color("8fa7bd")
@export var miss_color := Color("a5a5a5")

func grade_color(grade: int) -> Color:
	return [perfect_color,good_color,pass_color,miss_color][grade]
