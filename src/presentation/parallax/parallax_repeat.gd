## 控制中心内部使用的单对象拼接节点，不复制精灵、动画或业务脚本。
@tool
extends Node2D

var source: Node2D
var repeat: Parallax2D
var base_origin: Vector2
var camera_origin: Vector2
var depth: int
var infinite: bool
var _cell_size := Vector2.ZERO
var random_flip := false


## 检查当前精灵的矩形；无限动画必须具有统一帧画布。
static func cell_size(object: Node2D) -> Vector2:
	if object is Sprite2D:
		return object.get_rect().size if object.texture != null else Vector2.ZERO
	if object is AnimatedSprite2D:
		var frames: SpriteFrames = object.sprite_frames
		if frames == null or not frames.has_animation(object.animation):
			return Vector2.ZERO
		var size := Vector2.ZERO
		for index in frames.get_frame_count(object.animation):
			var texture := frames.get_frame_texture(object.animation, index)
			if texture == null:
				return Vector2.ZERO
			if index == 0:
				size = texture.get_size()
			elif size != texture.get_size():
				return Vector2.ZERO
		return size
	return Vector2.ZERO


## 接收控制中心坐标中的原变换，保持源对象的实际外观变换。
func configure(object: Node2D, pose: Transform2D, camera: Vector2, value: int, tiled: bool, flip: bool = false) -> void:
	source = object
	base_origin = pose.origin
	camera_origin = camera
	depth = value
	infinite = tiled
	random_flip = flip and tiled
	if not infinite:
		object.reparent(self) if object.get_parent() != null else add_child(object)
		object.transform = pose
		return
	# 旋转、缩放和斜切放在重复节点的父级，使拼接格沿素材自身两轴延伸。
	transform = Transform2D(pose.x, pose.y, Vector2.ZERO)
	repeat = Parallax2D.new()
	repeat.name = "Repeat"
	repeat.ignore_camera_scroll = true
	repeat.follow_viewport = false
	add_child(repeat)
	object.reparent(repeat) if object.get_parent() != null else repeat.add_child(object)
	object.transform = Transform2D.IDENTITY
	update_camera(camera)


## 有限对象平移；无限对象先换算到素材局部格，再由 Parallax2D 循环位置。
func update_camera(camera: Vector2) -> void:
	var displacement := Vector2.ZERO if depth == 0 else -(camera - camera_origin) / float(depth)
	if not infinite:
		position = displacement
		return
	var size := cell_size(source)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	if size != _cell_size:
		_cell_size = size
	repeat.repeat_size = size
	# 用实际视口在素材坐标中的包围范围计算重复数，支持小图、旋转和窗口变化。
	var inverse := get_global_transform_with_canvas().affine_inverse()
	var viewport_rect := get_viewport_rect()
	var bounds := Rect2(inverse * viewport_rect.position, Vector2.ZERO)
	for corner in [Vector2(viewport_rect.end.x, viewport_rect.position.y), viewport_rect.end, Vector2(viewport_rect.position.x, viewport_rect.end.y)]:
		bounds = bounds.expand(inverse * corner)
	var reach := bounds.position.abs().max(bounds.end.abs())
	# centered/offset 可让素材离开格原点；一并覆盖，不能假定贴图左上角为零。
	var source_offset: Vector2 = source.position + source.offset
	if source.centered:
		source_offset -= size * 0.5
	reach += source_offset.abs() + size * 2.0
	repeat.repeat_times = maxi(1, ceili(maxf(reach.x / size.x, reach.y / size.y)) * 2 + 1)
	repeat.scroll_offset = transform.affine_inverse() * (base_origin + displacement)
