extends SceneTree

## 实际屏幕读取：有限波带、叠加上限、留边与 HUD，兼顾缩放后的 SubViewport。
var failures := 0
var checks := 0
const OUTPUT := "res://builds/visual-review/wave-distortion"
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
	print("PASS " if ok else "FAIL ", message)

func snap(viewport: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage := Node2D.new(); viewport.add_child(stage)
	var pattern := Image.create(1920, 1080, false, Image.FORMAT_RGBA8)
	for y: int in 1080:
		for x: int in 1920: pattern.set_pixel(x, y, Color(float(x % 64) / 63.0, float(y % 64) / 63.0, 0.3))
	var art := Sprite2D.new(); art.centered = false; art.texture = ImageTexture.create_from_image(pattern); stage.add_child(art)
	var field := TuningInterferenceVisual.new(); stage.add_child(field); field.set_process(false)
	var warp := WaveDistortionVisual.new(); warp.style = WaveDistortionStyle.new(); viewport.add_child(warp); warp.bind(field)
	var hud := CanvasLayer.new(); hud.layer = 10; viewport.add_child(hud)
	var hud_rect := TextureRect.new(); hud_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hud_rect.texture = art.texture; hud_rect.size = Vector2(110, 75); hud.add_child(hud_rect)
	for zoom: float in [1.0, 0.5]:
		var pose := Transform2D(0.0, Vector2(20, 30)).scaled_local(Vector2.ONE * zoom)
		viewport.size = Vector2i(Vector2(1920, 1080) * zoom + Vector2(40, 60))
		stage.transform = pose; warp.sync_transform(pose)
		field.set_visual_time(1.0)
		field.set_gameplay_snapshot({"carrier_wavefronts": [{"affinity": 0, "radius_px": 300.0, "wave_id": "0:1"}]})
		field.visible = false
		check(warp.copy.copy_mode == BackBufferCopy.COPY_MODE_VIEWPORT, "存在波前时启用一次屏幕复制")
		check(warp.surface.get_shader_parameter(&"life_emission_times") == field._shader_material.get_shader_parameter(&"life_emission_times"), "折射与相纹共用同一批波前")
		warp.style.enabled = false; warp.refresh_style()
		var base := await snap(viewport)
		check(warp.copy.copy_mode == BackBufferCopy.COPY_MODE_DISABLED, "关闭效果同时停用复制")
		warp.style.enabled = true; warp.refresh_style()
		var refracted := await snap(viewport)
		var outside_stable := true; var hud_stable := true; var changed := 0
		for y: int in range(0, viewport.size.y, 3):
			for x: int in range(0, viewport.size.x, 3):
				var different := base.get_pixel(x, y) != refracted.get_pixel(x, y)
				var point := pose.affine_inverse() * Vector2(x + 0.5, y + 0.5)
				if absf(point.distance_to(field.life_source) - 300.0) > 26.0: outside_stable = outside_stable and not different
				if x < 110 and y < 75: hud_stable = hud_stable and not different
				if different: changed += 1
		check(outside_stable, "波带之外及画布留边像素严格稳定 %s" % zoom)
		check(hud_stable, "HUD 像素严格稳定 %s" % zoom)
		check(changed > 30, "波带内确有折射 %s" % zoom)
		check((await snap(viewport)).get_data() == refracted.get_data(), "暂停时折射像素冻结")
		field.clear(); check(not warp.pass_rect.visible and warp.copy.copy_mode == 0, "重试清空旧波与绘制")
		field.set_visual_time(1.0)
		field.set_gameplay_snapshot({"carrier_wavefronts": [{"affinity": 0, "radius_px": 300.0, "wave_id": "0:1"}]}); field.visible = false
		check((await snap(viewport)).get_data() == refracted.get_data(), "直接恢复相同波前得到相同像素")
		base.save_png(OUTPUT + "/grid-off-%s.png" % zoom)
		refracted.save_png(OUTPUT + "/grid-on-%s.png" % zoom)
		# 两个波源重合用于构造最大叠加，借 RGB 坐标渐变直接测量采样位移。
		field.death_source = field.life_source
		var dense := []
		for side: int in 2:
			for i: int in 16: dense.append({"affinity": side, "radius_px": 300.0, "wave_id": "%d:%d" % [side, i]})
		field.set_gameplay_snapshot({"carrier_wavefronts": dense}); field.visible = false
		var summed := await snap(viewport)
		var sample_point := Vector2i(pose * (field.life_source + Vector2(310, 0)))
		var c := summed.get_pixelv(sample_point); var original := base.get_pixelv(sample_point)
		var displacement := Vector2(c.r - original.r, c.g - original.g).length() * 63.0
		check(field.render_fronts.life_wavefront_count == 16 and field.render_fronts.death_wavefront_count == 16, "满载双侧共 32 条波前")
		check(displacement > 2.7 and displacement < 3.3, "最大叠加受限于 3 设计像素，实测 %.3f" % displacement)
		field.death_source = Vector2(1570, 800)
	viewport.free()
	print("WAVE DISTORTION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
