## 一件关卡背景素材。位置以设计画布左上角为原点，不按深度缩放。
@tool
class_name StageBackgroundEntry
extends Resource

## 三种素材仅选择一项：静态贴图、SpriteFrames 或 Node2D 场景。
@export var texture: Texture2D
## 多帧动画，与 texture、scene 三选一；无限动画的帧画布必须等大。
@export var sprite_frames: SpriteFrames
## 组合背景场景。可实现 sample_background(seconds) 接收绝对歌曲时钟；当前仅支持有限素材。
@export var scene: PackedScene
## SpriteFrames 中使用的动画，遵循其帧率、帧时长与循环设置。
@export var animation: StringName = &"default"
## 背景的 canvas_item Shader 材质；在 Inspector 的 Shader Parameters 中配置 uniforms。
## 空值使用默认绘制；运行时复制材质参数，Shader 与纹理资源继续共享。
@export var material: ShaderMaterial
## 是否沿素材矩形在两个方向无限拼接。
@export var infinite: bool = false
## 无限拼接时让每个重复单元稳定随机水平/垂直翻转。
@export var random_flip: bool = false
## 从其他场景切入时，直接整层交叉淡化，不等待旧素材循环接缝。
@export var direct_transition: bool = false
## 素材左上角的设计画布位置。
@export var position: Vector2 = Vector2.ZERO
## 素材自身的等比缩放倍率；与视差深度无关，不允许翻转。
@export_range(0.01, 10.0, 0.01, "or_greater") var uniform_scale: float = 1.0

func source_count() -> int:
	return int(texture != null) + int(sprite_frames != null) + int(scene != null)

func source_resource() -> Resource:
	return texture if texture != null else (sprite_frames if sprite_frames != null else scene)

func scene_size() -> Vector2:
	var instance := scene.instantiate()
	var extent := Vector2(1920,1080)
	if instance.has_method("background_bounds"): extent=instance.background_bounds().size
	instance.free()
	return extent
