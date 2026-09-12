extends MeshInstance2D
## 跪地末姿在素材生成时烘焙；运行时复用音符碎片网格，不抓屏、不新建 SubViewport。
@export var frame_rect: Rect2
@export var start_sec: float = 1.4
@export var duration_sec: float = 0.65

func _ready() -> void:
	position = frame_rect.get_center()
	mesh = NoteFragmentHost._template(frame_rect.size, 48, 80)
	mesh.custom_aabb = AABB(Vector3(-frame_rect.size.x * 0.5 - 180.0, -frame_rect.size.y * 0.5 - 180.0, -1.0), Vector3(frame_rect.size.x + 360.0, frame_rect.size.y + 360.0, 2.0))
	var surface := ShaderMaterial.new()
	surface.shader = preload("res://shaders/characters/lingjun_ashes.gdshader")
	surface.set_shader_parameter("source_size", frame_rect.size)
	surface.set_shader_parameter("duration", duration_sec)
	material = surface
	visible = false

func set_death_age(seconds: float) -> void:
	var age := seconds - start_sec
	visible = age >= 0.0 and age < duration_sec
	(material as ShaderMaterial).set_shader_parameter("age", maxf(age, 0.0))
	# 只隐藏 Spine 槽位，本节点仍沿角色及所属世界的变换运动。
	var actor := get_parent() as SpineSprite
	actor.get_skeleton().set_color(Color(1.0, 1.0, 1.0, 0.0 if age >= 0.0 else 1.0))
