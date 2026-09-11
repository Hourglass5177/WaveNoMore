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
## 背景的 canvas_item Shader 材质；在 Inspector 的 Shader Parameters 中配置 uniforms。
## 空值使用默认绘制；运行时复制材质参数，Shader 与纹理资源继续共享。
@export var material: ShaderMaterial
## 是否沿素材矩形在两个方向无限拼接。
@export var infinite: bool = false
## 素材左上角的设计画布位置。
@export var position: Vector2 = Vector2.ZERO
## 素材自身的等比缩放倍率；与视差深度无关，不允许翻转。
@export_range(0.01, 10.0, 0.01, "or_greater") var uniform_scale: float = 1.0
