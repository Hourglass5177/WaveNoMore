## 一件关卡背景素材。位置以设计画布左上角为原点，不按深度缩放。
@tool
class_name StageBackgroundEntry
extends Resource

## 静态贴图，与 sprite_frames 二选一。
@export var texture: Texture2D
## 多帧动画，与 texture 二选一；无限动画的帧画布必须等大。
@export var sprite_frames: SpriteFrames
## SpriteFrames 中使用的动画，遵循其帧率、帧时长与循环设置。
@export var animation: StringName = &"default"
## 0 静止，非零位移为 -相机位移 / depth；负数位于玩法前方。
@export var depth: int = 1
## 是否沿素材矩形在两个方向无限拼接。
@export var infinite: bool = false
## 素材左上角的设计画布位置。
@export var position: Vector2 = Vector2.ZERO
