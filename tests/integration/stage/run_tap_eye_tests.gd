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
	material.set_shader_parameter("surface_strength", 0.0)
	material.set_shader_parameter("effects_enabled", false)
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
	# 独立量测可动暗眼球的放大与褪白，眼眶以外的像素必须保持不变。
	sprite.position = Vector2(320, 180)
	sprite.texture = solid(Color(0.2, 0.2, 0.2))
	material.set_shader_parameter("eye_offset_px", 0.0)
	eye.fill(Color.TRANSPARENT); eye.fill_rect(Rect2i(28, 28, 8, 8), Color(0.1, 0.1, 0.1))
	material.set_shader_parameter("eye_ball_texture", ImageTexture.create_from_image(eye))
	var aperture := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	aperture.fill(Color.BLACK); aperture.fill_rect(Rect2i(22, 22, 20, 20), Color.WHITE)
	material.set_shader_parameter("musk_texture", ImageTexture.create_from_image(aperture))
	material.set_shader_parameter("eye_hit_progress", 1.0)
	await process_frame; await RenderingServer.frame_post_draw
	var expanded := viewport.get_texture().get_image()
	var lit_width := 0
	for x: int in range(300, 340):
		if expanded.get_pixel(x, 180).r > 0.6: lit_width += 1
	check(lit_width >= 9 and lit_width <= 11, "命中眼球由 8 px 放大至约 9.6 px 并变白")
	var cropped := true
	for y: int in range(149, 211):
		for x: int in range(289, 351):
			if abs(x - 320) > 11 or abs(y - 180) > 11:
				cropped = cropped and absf(expanded.get_pixel(x, y).r - 0.2) < 0.02
	check(cropped, "放大与变白始终裁切在眼睛内部")
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
	await check_conditional_eye_light()
	print("Tap eye failures: ", failures)
	quit(1 if failures else 0)

func check_conditional_eye_light() -> void:
	# 正式贴图关闭眼球偏移，按素材遮罩独立取样眼部、瞳孔与睫毛。
	var theme := load("res://content/stages/s08/stage_visual_theme.tres") as StageVisualTheme
	var style := load("res://content/presentation/note_effect_style.tres") as NoteEffectStyle
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.texture = theme.zhu_tap_texture
	sprite.position = Vector2(128, 128)
	sprite.scale = Vector2(256, 256) / sprite.texture.get_size()
	var material := theme.zhu_tap_material.duplicate(false) as ShaderMaterial
	sprite.material = material
	material.set_shader_parameter("eye_offset_px", 0.0)
	viewport.add_child(sprite)
	var mask := (material.get_shader_parameter("musk_texture") as Texture2D).get_image()
	var lashes := (material.get_shader_parameter("lash_texture") as Texture2D).get_image()
	var pupil := (material.get_shader_parameter("eye_ball_texture") as Texture2D).get_image()
	var comparison := Image.create(768, 512, false, Image.FORMAT_RGBA8)
	for side in 2:
		style.apply_to(material, side)
		var frames: Array[Image] = []
		for light in [0.0, 0.5, 1.0]:
			material.set_shader_parameter("condition_light", light)
			await process_frame
			await RenderingServer.frame_post_draw
			frames.append(viewport.get_texture().get_image())
			comparison.blit_rect(frames.back(), Rect2i(0, 0, 256, 256), Vector2i((frames.size() - 1) * 256, side * 256))
		var eye_count := 0; var pupil_count := 0; var lash_count := 0
		var eye_gain := 0.0; var pupil_gain := 0.0
		var progressive := true; var neutral_lashes := true; var stable_alpha := true
		for y in range(2, 254):
			for x in range(2, 254):
				var uv := Vector2(x + 0.5, y + 0.5) / 256.0
				var m := sample_mask(mask, uv)
				var l := sample_mask(lashes, uv)
				var p := pupil.get_pixelv(Vector2i(uv * Vector2(pupil.get_size())))
				var off := frames[0].get_pixel(x, y)
				var half := frames[1].get_pixel(x, y)
				var full := frames[2].get_pixel(x, y)
				stable_alpha = stable_alpha and absf(off.a - full.a) < 0.005
				if off.a < 0.99: continue
				if m > 0.99 and l < 0.01:
					eye_count += 1
					eye_gain += full.get_luminance() - off.get_luminance()
					progressive = progressive and half.get_luminance() >= off.get_luminance() - 0.005 and full.get_luminance() >= half.get_luminance() - 0.005
					# 原素材暗眼球的透明度约 0.85～0.92，不能当作不透明贴片取样。
					if p.a > 0.8 and p.get_luminance() < 0.35:
						pupil_count += 1
						pupil_gain += full.get_luminance() - off.get_luminance()
				if l > 0.999 and m < 0.001:
					lash_count += 1
					neutral_lashes = neutral_lashes and absf(full.r - off.r) < 0.02 and absf(full.g - off.g) < 0.02 and absf(full.b - off.b) < 0.02
		print("眼部取样 side=%d eye=%d gain=%.4f pupil=%d gain=%.4f lashes=%d stable=%s" % [side, eye_count, eye_gain / maxf(eye_count, 1), pupil_count, pupil_gain / maxf(pupil_count, 1), lash_count, neutral_lashes])
		check(eye_count > 20 and eye_gain / maxf(eye_count, 1) > 0.10, "阵营 %d 正式眼部参与白光" % side)
		check(pupil_count > 20 and pupil_gain / maxf(pupil_count, 1) > 0.15, "阵营 %d 暗瞳孔明显提亮" % side)
		check(progressive, "阵营 %d 眼部随白光渐亮且眼白不被压暗" % side)
		check(lash_count > 20 and neutral_lashes, "阵营 %d 白光保留中性睫毛" % side)
		check(stable_alpha, "阵营 %d 白光不改变眼睛透明轮廓" % side)
		material.set_shader_parameter("effects_enabled", false)
		await process_frame
		await RenderingServer.frame_post_draw
		var disabled := viewport.get_texture().get_image()
		material.set_shader_parameter("condition_light", 0.0)
		await process_frame
		await RenderingServer.frame_post_draw
		check(disabled.get_data() == viewport.get_texture().get_image().get_data(), "阵营 %d 关闭特效时眼部不受白光影响" % side)
	comparison.save_png("res://builds/tap-eye/conditional-eye-light.png")
	viewport.queue_free()

func sample_mask(image: Image, uv: Vector2) -> float:
	# 与正式 shader 的线性采样一致，排除睫毛遮罩边缘混入本体的像素。
	var texel := uv * Vector2(image.get_size()) - Vector2(0.5, 0.5)
	var origin := Vector2i(texel.floor())
	var fraction := texel - Vector2(origin)
	return lerpf(lerpf(image.get_pixelv(origin).r, image.get_pixelv(origin + Vector2i.RIGHT).r, fraction.x), lerpf(image.get_pixelv(origin + Vector2i.DOWN).r, image.get_pixelv(origin + Vector2i.ONE).r, fraction.x), fraction.y)
