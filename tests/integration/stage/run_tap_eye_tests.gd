extends SceneTree
## GPU checks use a synthetic eye to measure screen-space displacement.
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)

func solid(color: Color) -> ImageTexture:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.texture = solid(Color.TRANSPARENT)
	var eye := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	eye.fill(Color.TRANSPARENT)
	eye.fill_rect(Rect2i(28, 28, 8, 8), Color.WHITE)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/materials/tap_eye.gdshader")
	material.set_shader_parameter("musk_texture", solid(Color.WHITE))
	material.set_shader_parameter("eye_ball_texture", ImageTexture.create_from_image(eye))
	# 旧断言隔离眼球机制；泛光在后面的独立像素检查中开启。
	material.set_shader_parameter("glow_enabled", false)
	sprite.material = material
	viewport.add_child(sprite)
	for dimensions in [Vector2i(640, 360), Vector2i(360, 640)]:
		viewport.size = dimensions
		var center := Vector2(dimensions) * 0.5
		for offset in [Vector2(-90, 0), Vector2(90, 0), Vector2(0, -90), Vector2(0, 90), Vector2.ZERO]:
			for angle in [0.0, PI]:
				for zoom in [1.0, 1.5]:
					sprite.position = center + offset
					sprite.rotation = angle
					sprite.scale = Vector2.ONE * zoom
					await process_frame
					await RenderingServer.frame_post_draw
					var image := viewport.get_texture().get_image()
					var weight := 0.0
					var sum := Vector2.ZERO
					for y in image.get_height():
						for x in image.get_width():
							var alpha := image.get_pixel(x, y).a
							weight += alpha
							sum += Vector2(x + 0.5, y + 0.5) * alpha
					# 当前机制在中心附近用 smoothstep 衰减，128 px 外保持 10 px 默认半径。
					var distance_px: float = Vector2(offset).length()
					var falloff: float = smoothstep(0.0, 128.0, distance_px)
					var expected_offset: float = 10.0 * falloff
					var expected: Vector2 = sprite.position - offset.normalized() * expected_offset
					var measured := sum / maxf(weight, 0.001)
					check(weight > 0.0 and measured.distance_to(expected) < 1.5, "Eye direction/scale: %s %s %s measured=%s expected=%s" % [offset, angle, zoom, measured, expected])
	viewport.size = Vector2i(640, 360)
	sprite.position = Vector2(180, 100)
	sprite.rotation = 0.0
	sprite.scale = Vector2.ONE
	sprite.texture = solid(Color(0, 0, 1, 0.5))
	material.set_shader_parameter("eye_ball_texture", solid(Color(1, 0, 0, 0.5)))
	material.set_shader_parameter("eye_offset_px", 0.0)
	for mask in [0.0, 0.5, 1.0]:
		material.set_shader_parameter("musk_texture", solid(Color(mask, mask, mask, 1)))
		await process_frame
		await RenderingServer.frame_post_draw
		var pixel := viewport.get_texture().get_image().get_pixel(180, 100)
		var expected_alpha: float = 0.5 * mask + 0.5 * (1.0 - 0.5 * mask)
		check(absf(pixel.a - expected_alpha) < 0.02, "Mask alpha: %s" % mask)
		check(pixel.b > 0.0 and (pixel.r > 0.0 if mask > 0 else pixel.r < 0.02), "Mask color: %s" % mask)
	material.set_shader_parameter("eye_offset_px", 1000.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var outside := viewport.get_texture().get_image().get_pixel(180, 100)
	check(outside.r < 0.02 and absf(outside.a - 0.5) < 0.02, "Out-of-bounds eye is transparent")
	var glow_source := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	glow_source.fill(Color.TRANSPARENT)
	glow_source.fill_rect(Rect2i(24, 24, 16, 16), Color(0.08, 0.08, 0.08, 1.0))
	sprite.texture = ImageTexture.create_from_image(glow_source)
	material.set_shader_parameter("musk_texture", solid(Color.BLACK))
	material.set_shader_parameter("eye_ball_texture", solid(Color.TRANSPARENT))
	material.set_shader_parameter("glow_enabled", true)
	material.set_shader_parameter("glow_color", Color(1.0, 0.1, 0.05, 1.0))
	material.set_shader_parameter("glow_width_px", 16.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var glow_image := viewport.get_texture().get_image()
	var body_pixel := glow_image.get_pixel(180, 100)
	var edge_pixel := glow_image.get_pixel(190, 100)
	check(body_pixel.r < 0.12 and body_pixel.a > 0.98, "Glow preserves opaque Tap body")
	check(edge_pixel.r > 0.2 and edge_pixel.a > 0.05, "Glow extends colored alpha outside Tap body")
	material.set_shader_parameter("glow_enabled", false)
	await process_frame
	await RenderingServer.frame_post_draw
	check(viewport.get_texture().get_image().get_pixel(190, 100).a < 0.02, "Disabled glow restores transparent edge")
	# Render the actual s08 textures using the production Tap visual.
	sprite.queue_free()
	viewport.size = Vector2i(640, 360)
	var theme := load("res://content/stages/s08/stage_visual_theme.tres") as StageVisualTheme
	check(theme.zhu_tap_material.get_shader_parameter("musk_texture") == load("res://assets/image/note/tap_musk.png"), "Production material binds the mask")
	check(theme.zhu_tap_material.get_shader_parameter("eye_ball_texture") == load("res://assets/image/note/tap_eye_ball.png"), "Production material binds the eye")
	var host := NoteVisualHost.new()
	host.visual_theme = theme
	host._pool_root = Node2D.new()
	root.add_child(host._pool_root)
	var scene := load("res://scenes/presentation/notes/graybox_note_visual.tscn") as PackedScene
	var first := host._acquire_visual(&"note_0", scene)
	var second := host._acquire_visual(&"note_1", scene)
	check(first.material != second.material and first.material != theme.zhu_tap_material, "Materials are per-instance")
	first.reset_for_pool()
	host._pools[&"note_0"] = [first]
	var reused := host._acquire_visual(&"note_0", scene)
	check(reused == first and reused.material.shader == theme.zhu_tap_material.shader, "Pool retains eye shader")
	host._pool_root.queue_free()
	host.free()
	for index in 2:
		var tap := GrayboxNoteVisual.new()
		tap.tap_texture = theme.zhu_tap_texture if index == 0 else theme.xuan_tap_texture
		tap.material = theme.zhu_tap_material.duplicate(false)
		tap.position = Vector2(180, 100) if index == 0 else Vector2(460, 260)
		tap.rotation = 0.0 if index == 0 else PI
		viewport.add_child(tap)
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://builds/tap-eye")
	viewport.get_texture().get_image().save_png("res://builds/tap-eye/s08-taps.png")
	print("Tap eye failures: ", failures)
	quit(1 if failures else 0)
