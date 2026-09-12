extends RefCounted

## 首次装配关卡时实际绘制一次，提前准备白光和 Ghost 的 GPU 程序。
## 整个进程只创建一个临时小视口，绘制完成即释放，不参与玩法或持续渲染。
const GLOW = preload("res://src/presentation/vfx/note_soft_glow.gd")
const GHOST = preload("res://src/presentation/vfx/su_manifestation_overlay.gd")
static var _prepared := false

static func prepare(host: Node) -> void:
	if _prepared or DisplayServer.get_name() == "headless": return
	_prepared = true
	var viewport := SubViewport.new()
	viewport.name = "NoteEffectWarmup"
	viewport.size = Vector2i(32, 32)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var shape := GLOW.new()
	shape.position = Vector2(8, 8)
	shape.scale = Vector2(0.2, 0.2)
	shape.set_light(1.0, 30.0)
	shape.polygon(PackedVector2Array([Vector2(-20, -20), Vector2(20, 0), Vector2(-20, 20)]))
	viewport.add_child(shape)
	var body := GLOW.new()
	body.position = Vector2(8, 22)
	body.scale = Vector2(0.2, 0.2)
	body.set_light(1.0, 30.0)
	body.body(PackedVector2Array([Vector2.ZERO, Vector2(40, 0)]), PackedFloat32Array([12, 12]))
	viewport.add_child(body)
	var ghost := GHOST.new()
	ghost.canvas_size = Vector2(32, 32)
	ghost.prepare_targets({"event_id": "warmup", "time_us": 0, "points": [Vector2(0.5, 0.5)]})
	viewport.add_child(ghost)
	host.add_child(viewport)
	# 使用正式材质绘制一次，首次击碎不再临时编译眼球、柔光与碎片程序。
	var tap := GrayboxNoteVisual.new()
	tap.tap_texture = load("res://assets/image/note/tap_base.png")
	tap.tap_material = (load("res://shaders/materials/tap_eye.tres") as ShaderMaterial).duplicate(false)
	viewport.add_child(tap)
	tap.prepare({"event_id": "warmup_tap", "affinity": 0})
	tap.position = Vector2(16, 16)
	tap.scale = Vector2(0.1, 0.1)
	var fragments := NoteFragmentHost.new()
	viewport.add_child(fragments)
	fragments.burst("warmup", tap.effect_snapshot(), 0.0, Vector2.RIGHT)
	var ashes := MeshInstance2D.new()
	ashes.mesh = NoteFragmentHost._template(Vector2(96, 96), 48, 80)
	ashes.texture = tap.tap_texture
	ashes.position = Vector2(16, 16)
	ashes.scale = Vector2.ONE * 0.08
	var ash_material := ShaderMaterial.new()
	ash_material.shader = preload("res://shaders/characters/lingjun_ashes.gdshader")
	ash_material.set_shader_parameter("source_size", Vector2(96, 96))
	ash_material.set_shader_parameter("age", 0.15)
	ashes.material = ash_material
	viewport.add_child(ashes)
	var hold := GrayboxHoldVisual.new()
	hold.head_texture = load("res://assets/image/note/hold_note.png")
	hold.body_texture = load("res://assets/image/note/hold_body.png")
	viewport.add_child(hold)
	hold.prepare({"event_id": "warmup_hold", "unit_kind": &"hold"})
	hold.position = Vector2(22, 22)
	hold.scale = Vector2(0.04, 0.04)
	hold.advance_body(0.0)
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	viewport.add_child(copy)
	var refraction := ColorRect.new()
	refraction.size = Vector2(32, 32)
	var refraction_material := ShaderMaterial.new()
	refraction_material.shader = preload("res://shaders/fields/wave_distortion.gdshader")
	refraction.material = refraction_material
	viewport.add_child(refraction)
	RenderingServer.frame_post_draw.connect(viewport.queue_free, CONNECT_ONE_SHOT)
