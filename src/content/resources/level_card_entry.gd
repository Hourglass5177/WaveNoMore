@tool
class_name LevelCardEntry
extends Resource

@export var title: String = "未命名关卡"
@export var stage_id: String = ""
@export var image: Texture2D
## 卡片背景素材；为空时沿用 image。
@export var background: Texture2D
## 相对于背景素材原始尺寸的等比缩放；不影响卡片主图或文字。
@export_range(0.01, 10.0, 0.01, "or_greater") var background_scale: float = 1.0
@export var heading_texture: Texture2D
## 背景特效帧动画；每帧按 SpriteFrames 的纹理替换特效图层。
@export var background_effect_frames: SpriteFrames
@export var background_effect_animation: StringName = &"default"
@export_range(0.01, 10.0, 0.01, "or_greater") var background_effect_scale: float = 1.0
@export_multiline var description: String = ""
