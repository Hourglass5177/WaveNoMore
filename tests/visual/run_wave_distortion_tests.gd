extends SceneTree

## 实际屏幕读取：有限波带、叠加上限、留边与 HUD，兼顾缩放后的 SubViewport。
var failures := 0
var checks := 0
const OUTPUT := "res://builds/visual-review/wave-distortion-focus"
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
				var radial_offset := point.distance_to(field.life_source) - 300.0
				if radial_offset > warp.style.band_half_width_px + 2.0 or radial_offset < -warp.style.band_half_width_px - warp.style.tail_length_px - 2.0: outside_stable = outside_stable and not different
				if x < 110 and y < 75: hud_stable = hud_stable and not different
				if different: changed += 1
		check(outside_stable, "波带之外及画布留边像素严格稳定 %s" % zoom)
		check(hud_stable, "HUD 像素严格稳定 %s" % zoom)
		check(changed > 5000 * zoom * zoom, "波带内确有折射 %s" % zoom)
		check((await snap(viewport)).get_data() == refracted.get_data(), "暂停时折射像素冻结")
		field.clear(); check(not warp.pass_rect.visible and warp.copy.copy_mode == 0, "重试清空旧波与绘制")
		field.set_visual_time(1.0)
		field.set_gameplay_snapshot({"carrier_wavefronts": [{"affinity": 0, "radius_px": 300.0, "wave_id": "0:1"}]}); field.visible = false
		check((await snap(viewport)).get_data() == refracted.get_data(), "直接恢复相同波前得到相同像素")
		base.save_png(OUTPUT + "/grid-off-%s.png" % zoom)
		refracted.save_png(OUTPUT + "/grid-on-%s.png" % zoom)
		# 从坐标渐变读取实际 GPU 采样位移，核对峰值贴波前、短尾反向且足够轻。
		var width: float = warp.style.band_half_width_px
		var tail_length: float = warp.style.tail_length_px
		var peak := radial_shift(base, refracted, pose, field.life_source, 300.0)
		var before := radial_shift(base, refracted, pose, field.life_source, 300.0 - width * 0.5)
		var after := radial_shift(base, refracted, pose, field.life_source, 300.0 + width * 0.5)
		var tail := radial_shift(base, refracted, pose, field.life_source, 300.0 - width - tail_length * 0.5)
		check(peak > 8.0 and peak < 10.0 and peak > before and peak > after, "单波最大折射位于真实波前，实测 %.3f px" % peak)
		check(tail < 0.0 and absf(tail) < peak * 0.08, "后方只有轻微反向短尾，实测 %.3f px" % tail)
		for radius: float in [300.0 - width - tail_length, 300.0 - width, 300.0 + width]:
			check(absf(radial_shift(base, refracted, pose, field.life_source, radius)) < 0.55, "主波带／短尾连接及外边界连续归零 %s" % radius)
		if zoom == 1.0:
			await test_local_pass(viewport, field, base, pose, width, tail_length)
		# 两个波源重合用于构造最大叠加，借 RGB 坐标渐变直接测量采样位移。
		field.death_source = field.life_source
		var dense := []
		for side: int in 2:
			for i: int in 16: dense.append({"affinity": side, "radius_px": 300.0, "wave_id": "%d:%d" % [side, i]})
		field.set_gameplay_snapshot({"carrier_wavefronts": dense}); field.visible = false
		var summed := await snap(viewport)
		var sample_point := Vector2i(pose * (field.life_source + Vector2(300, 0)))
		var c := summed.get_pixelv(sample_point); var original := base.get_pixelv(sample_point)
		var displacement := Vector2(c.r - original.r, c.g - original.g).length() * 63.0
		check(field.render_fronts.life_wavefront_count == 16 and field.render_fronts.death_wavefront_count == 16, "满载双侧共 32 条波前")
		check(displacement > 13.5 and displacement < 14.5, "最大叠加受限于 14 设计像素，实测 %.3f" % displacement)
		field.death_source = Vector2(1570, 800)
	viewport.free()
	await test_judgment_layers()
	print("WAVE DISTORTION: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

# 正式预览的判定层须跟随画布缩放，但不进入第 3 层的屏幕复制。
func test_judgment_layers() -> void:
	var document := StudioDocument.new()
	StudioProjectIO.open_project("res://tests/editor/fixtures/tuning/song.json", document)
	var viewport := SubViewport.new(); viewport.size = Vector2i(960, 540)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var preview = load("res://src/tools/chart_studio/preview_session.gd").new(); root.add_child(preview)
	check(preview.load_preview(ChartProjectLoader.make_stage(document.song, document.chart()), viewport), "装入正式预览检查判定层")
	await preview.seek_preview(500_000)
	var presentation: Node = preview.stage_root.presentation
	var host: NoteVisualHost = presentation._note_visual_host
	check(presentation._judgment_canvas.layer > presentation._distortion.layer and host._judgment_canvas.layer > presentation._distortion.layer, "中央判定框、时机环与调频界面在折射后绘制")
	check(presentation._tutorial_canvas.layer > host._judgment_canvas.layer, "教程面板仍覆盖判定提示")
	check(host._field_slot.get_canvas_layer_node() == host._judgment_canvas, "调频交互几何处于稳定层")
	for zoom: float in [0.5, 1.0]:
		presentation.scale = Vector2.ONE * zoom
		await process_frame
		host._on_visual_spawn_requested(ChartScheduler.KIND_NOTE, {"event_id": "layer_tap", "affinity": 0, "start_us": 1000000, "end_us": 1000000, "unit_kind": &"tap"})
		host.set_visual_time(0.5)
		var tap: Node2D = host._active.layer_tap.node
		var ring: Node2D = host._active.layer_tap.timing_ring
		check(tap.get_global_transform_with_canvas().origin.is_equal_approx(ring.get_global_transform_with_canvas().origin), "缩放与对象池复用后时机环仍对齐音符 %s" % zoom)
		check(ring.get_global_transform_with_canvas().get_scale().is_equal_approx(host.get_global_transform_with_canvas().get_scale()), "时机环不重复应用画布缩放 %s" % zoom)
		host.clear()
	host.hide(); await process_frame
	check(not host._judgment_canvas.visible, "隐藏表现宿主同时隐藏独立判定层")
	host.show(); await process_frame
	check(host._judgment_canvas.visible, "恢复表现宿主时恢复判定层")
	preview.free(); viewport.free()

# 渐变每 64 像素循环，采样点避开接缝；保留方向而非只取位移长度。
func radial_shift(base: Image, refracted: Image, pose: Transform2D, source: Vector2, radius: float) -> float:
	var pixel := Vector2i(pose * (source + Vector2(radius, 0.0)))
	return (refracted.get_pixelv(pixel).r - base.get_pixelv(pixel).r) * 63.0

func test_local_pass(viewport: SubViewport, field: TuningInterferenceVisual, base: Image, pose: Transform2D, width: float, tail_length: float) -> void:
	var shifts: Array[float] = []
	for radius: float in [300.0 - width, 300.0 - width * 0.5, 300.0, 300.0 + width * 0.5, 300.0 + width, 300.0 + width + tail_length * 0.25, 300.0 + width + tail_length * 0.5, 300.0 + width + tail_length * 0.75, 300.0 + width + tail_length, 300.0 + width + tail_length + 24.0]:
		field.set_gameplay_snapshot({"carrier_wavefronts": [{"affinity": 0, "radius_px": radius, "wave_id": "0:pass"}]}); field.visible = false
		shifts.append(radial_shift(base, await snap(viewport), pose, field.life_source, 300.0))
	check(shifts[2] > shifts[1] and shifts[2] > shifts[3] and shifts[1] > 0.0 and shifts[3] > 0.0, "单波经过固定位置时只出现一次明显主峰")
	check(shifts[5] <= 0.0 and shifts[6] < 0.0 and shifts[7] <= 0.0 and shifts[8] == 0.0 and shifts[9] == 0.0, "主峰之后一次弱回弹，随后完全恢复")
	field.set_gameplay_snapshot({"carrier_wavefronts": [{"affinity": 0, "radius_px": 300.0, "wave_id": "0:a"}, {"affinity": 0, "radius_px": 650.0, "wave_id": "0:b"}]}); field.visible = false
	var separate := await snap(viewport)
	check(radial_shift(base, separate, pose, field.life_source, 300.0) > 4.0 and radial_shift(base, separate, pose, field.life_source, 650.0) > 4.0, "连续发波各自保持局部主峰")
	check(radial_shift(base, separate, pose, field.life_source, 400.0) == 0.0, "连续波前之间的空隙恢复原画面")
