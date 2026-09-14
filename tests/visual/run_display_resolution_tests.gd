extends SceneTree
## 检查真实渲染纹理与设计坐标；不写入玩家设置。
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print(('PASS ' if ok else 'FAIL ') + message)
	if not ok: failures += 1
func run() -> void:
	var settings := root.get_node('SettingsService')
	check(settings.read_resolution(ConfigFile.new()) == Vector2i(2560,1440), '旧设置默认 2K')
	var marker := ColorRect.new(); marker.position = Vector2(350,280); marker.size = Vector2(12,12); marker.color = Color.MAGENTA
	root.add_child(marker)
	var clicks: Array[int] = [0]
	var button := Button.new(); button.position = marker.position; button.size = marker.size; button.modulate.a = 0.0
	button.pressed.connect(func(): clicks[0] += 1); root.add_child(button)
	for full in [false, true]:
		settings.fullscreen = full
		for resolution: Vector2i in settings.RESOLUTIONS:
			settings.resolution = resolution; settings.apply_display_settings()
			for frame in 5: await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			check(image.get_size() == resolution, '%s 纹理 %s，目标 %s' % ['全屏' if full else '窗口',image.get_size(),resolution])
			var point := Vector2(356,286) * Vector2(resolution)/Vector2(1920,1080)
			check(image.get_pixelv(Vector2i(point)).r > .95 and image.get_pixelv(Vector2i(point)).b > .95, '波源设计坐标像素落点一致')
			check(root.get_visible_rect().size == Vector2(1920,1080), '逻辑布局仍为设计画布')
			var count := clicks[0]
			var click := InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT; click.position = root.get_final_transform() * Vector2(356,286); click.pressed = true
			root.push_input(click, false); click.pressed = false; root.push_input(click, false)
			check(clicks[0] == count + 1, '鼠标点击与设计位置一致')
			var config := ConfigFile.new(); config.set_value('display','resolution',resolution)
			var restored := ConfigFile.new(); restored.parse(config.encode_to_text())
			check(settings.read_resolution(restored) == resolution, '设置序列化往返一致')
			print('TRANSFORM ', root.get_stretch_transform(), ' logical=',root.get_visible_rect(), ' window=',root.size)
	marker.free(); button.free()
	await check_root_refraction(settings)
	settings.fullscreen = false; settings.resolution = settings.DEFAULT_RESOLUTION; settings.apply_display_settings()
	quit(failures)

func check_root_refraction(settings: Node) -> void:
	# 在实际根窗口验证波源与取样偏移，而非只验证缩放后的参考点。
	var gradient := Image.create(1920, 1, false, Image.FORMAT_RGBA8)
	for x in 1920: gradient.set_pixel(x, 0, Color(float(x % 64) / 63.0, 0.3, 0.3))
	var art := Sprite2D.new(); art.centered = false; art.texture = ImageTexture.create_from_image(gradient); art.scale.y = 1080.0
	root.add_child(art)
	var warp := WaveDistortionVisual.new(); warp.style = WaveDistortionStyle.new(); root.add_child(warp)
	var hud := CanvasLayer.new(); hud.layer = 10; root.add_child(hud)
	var stable := ColorRect.new(); stable.position = Vector2(342, 572); stable.size = Vector2(16, 16); stable.color = Color.MAGENTA; hud.add_child(stable)
	var fronts := {"canvas_size":Vector2(1920,1080), "life_source":Vector2(350,280), "death_source":Vector2(1570,800),
		"visual_time_sec":1.0, "wave_speed_px_sec":2400.0, "max_radius_px":2400.0,
		"life_wavefront_count":1, "death_wavefront_count":0, "life_emission_times":PackedFloat32Array([0.875])}
	for resolution: Vector2i in [Vector2i(1280,720),Vector2i(2560,1440),Vector2i(3840,2160)]:
		settings.fullscreen = false; settings.resolution = resolution; settings.apply_display_settings()
		for frame in 5: await process_frame
		warp.set_fronts(fronts); warp.style.enabled = false; warp.refresh_style()
		await process_frame; await RenderingServer.frame_post_draw
		var base := root.get_texture().get_image()
		warp.style.enabled = true; warp.refresh_style()
		await process_frame; await RenderingServer.frame_post_draw
		var bent := root.get_texture().get_image()
		var scale := Vector2(resolution) / Vector2(1920,1080)
		var peak := Vector2i(Vector2(650,280)*scale)
		var shift := (bent.get_pixelv(peak).r - base.get_pixelv(peak).r) * 63.0
		check(shift > 8.0 and shift < 10.0, '%s 根窗口波前仍在源外 300 设计像素，位移 %.2f px' % [resolution,shift])
		check(warp.surface.get_shader_parameter(&'pixel_x').is_equal_approx(Vector2(scale.x,0)), '折射上传真实渲染比例')
		var outside := Vector2i(Vector2(750,280)*scale)
		check(bent.get_pixelv(outside) == base.get_pixelv(outside), '改变分辨率后波带外仍稳定')
		var hud_pixel := Vector2i(Vector2(350,580)*scale)
		check(bent.get_pixelv(hud_pixel) == Color.MAGENTA, '根窗口波前经过 HUD 时像素稳定')
	warp.free(); art.free(); hud.free()
