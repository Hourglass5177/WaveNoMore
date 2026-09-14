extends Node2D
## 固定网格只更新骨骼变换和显式年龄；三眼遮罩与胸纹不依赖屏幕坐标。
const RING := preload("res://shaders/characters/pet_chest_wave.gdshader")
const EYES := preload("res://shaders/characters/pet_eyes.gdshader")
var surfaces: Array[ShaderMaterial] = []
var _pieces: Array[Dictionary] = []

func setup(skeleton: SpineSprite, config: Dictionary, folder: String) -> void:
	if config.has("chest"):
		var chest: Dictionary = config.chest
		for start in chest.starts:
			var piece := _piece(skeleton,chest,Vector2.ONE*78.0,RING)
			piece.start = start
			piece.duration = chest.duration
			piece.unit = float(config.unit_scale)
			piece.surface.set_shader_parameter("duration",chest.duration)
			piece.surface.set_shader_parameter("radius_from",chest.radius_from)
			piece.surface.set_shader_parameter("radius_to",chest.radius_to)
			_pieces.append(piece)
	if config.has("eyes"):
		var eyes: Dictionary = config.eyes
		var piece := _piece(skeleton,eyes,Vector2(eyes.size[0],eyes.size[1]),EYES)
		piece.node.texture = load(folder+str(eyes.texture))
		piece.unit = 1.0
		piece.start = 0.0
		piece.duration = config.trigger
		_pieces.append(piece)
	sample(-1.0,0.0)

func _piece(skeleton: SpineSprite, definition: Dictionary, size: Vector2, shader: Shader) -> Dictionary:
	var node := MeshInstance2D.new()
	var quad := QuadMesh.new()
	quad.size = size
	node.mesh = quad
	var surface := ShaderMaterial.new()
	surface.shader = shader
	node.material = surface
	add_child(node)
	surfaces.append(surface)
	return {"node":node,"surface":surface,"bone":skeleton.get_skeleton().find_bone(definition.bone),
		"point":Vector2(definition.point[0],definition.point[1])}

func sample(age: float, intensity: float) -> void:
	for piece in _pieces:
		var local_age: float = age-float(piece.start)
		piece.node.visible = age>=0.0 and local_age>=0.0 and local_age<float(piece.duration)
		piece.surface.set_shader_parameter("age",local_age)
		piece.surface.set_shader_parameter("amount",intensity)
		if not piece.node.visible: continue
		var pose: Transform2D = global_transform.affine_inverse()*piece.bone.get_global_transform()
		# 骨骼坐标以原图像素存储；胸波尺寸用显示基准，眼罩则保留原图像素。
		pose.origin = pose*piece.point
		pose.x /= float(piece.unit)
		pose.y /= float(piece.unit)
		piece.node.transform = pose
