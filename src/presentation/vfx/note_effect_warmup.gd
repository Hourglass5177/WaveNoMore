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
	RenderingServer.frame_post_draw.connect(viewport.queue_free, CONNECT_ONE_SHOT)
