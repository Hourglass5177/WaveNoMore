extends Node2D
## 三口短促火焰使用嘴部权重跟随当前姿态，年龄由随从表现时钟提供。
const SHADER := preload("res://shaders/characters/snake_breath.gdshader")
var flames: Array[MeshInstance2D] = []
var _mouths: Array[Dictionary] = []

func setup(skeleton: SpineSprite, definitions: Array) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(38,24)
	quad.center_offset = Vector3(15,0,0)
	for index in definitions.size():
		var definition: Dictionary = definitions[index]
		var binds: Array[Dictionary] = []
		for bind: Dictionary in definition.bindings:
			binds.append({"bone":skeleton.get_skeleton().find_bone(bind.bone),"weight":bind.weight,"point":Vector2(bind.point[0],bind.point[1])})
		_mouths.append({"bindings":binds,"direction":Vector2(definition.direction[0],definition.direction[1]),"start":definition.start,"duration":definition.duration})
		var flame := MeshInstance2D.new()
		flame.mesh = quad
		var surface := ShaderMaterial.new()
		surface.shader = SHADER
		surface.set_shader_parameter("duration",definition.duration)
		surface.set_shader_parameter("length_px",definition.length_px)
		surface.set_shader_parameter("width_px",definition.width_px)
		surface.set_shader_parameter("phase",float(index)*1.7)
		flame.material = surface
		add_child(flame)
		flames.append(flame)
	sample(-1.0)

func sample(trigger_age: float) -> void:
	for index in flames.size():
		var mouth: Dictionary = _mouths[index]
		var flame := flames[index]
		var age := trigger_age-float(mouth.start)
		flame.visible = age>=0.0 and age<float(mouth.duration)
		(flame.material as ShaderMaterial).set_shader_parameter("age",age)
		if not flame.visible: continue
		var at := Vector2.ZERO
		var direction := Vector2.ZERO
		for bind: Dictionary in mouth.bindings:
			# Spine 返回包含显示比例的全局变换，回到此节点局部后才能正确镜像与缩放。
			var pose: Transform2D = bind.bone.get_global_transform()
			at += (pose*bind.point)*float(bind.weight)
			direction += (pose.x*mouth.direction.x+pose.y*mouth.direction.y)*float(bind.weight)
		flame.position = to_local(at)
		flame.rotation = (to_local(at+direction)-flame.position).angle()
