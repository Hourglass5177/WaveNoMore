extends SceneTree
## 实际透明像素与正式预览：圆帽接合、端点裁切、阵营配色及往返填充。
const OUTPUT := "res://builds/visual-review/tuning-style"
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
	print("PASS " if ok else "FAIL ", message)
func snap(viewport: SubViewport) -> Image:
	await process_frame; await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var viewport := SubViewport.new(); viewport.size = Vector2i(700, 400)
	viewport.transparent_bg = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var field := GrayboxFieldVisual.new(); viewport.add_child(field); field.set_process(false); field.tuning_glow_enabled = false
	test_start_handoff(field)
	# 本段单独测轨道透明接合，避免起点新摇杆帽面影响圆帽中心像素。
	for side: int in 2:
		field.prepare({"event_id": "style", "affinity": side, "start_value": 0.2, "end_value": 0.8, "traversal_count": 2, "show_rotation_cue": false})
		# 一段直轨隔离透明叠画问题，避开引导点和方向箭头的像素。
		field._event_curve_points = PackedVector2Array([Vector2(150, 200), Vector2(550, 200)])
		field._slider_length_px = 400.0; field._cached_rail_width = -1.0
		field.set_approach_timing(-0.5, 2.25) # 隔离起手后的主体像素，避开 80 ms 余光。
		field._interaction_open = true; field._field_active = true
		field._player_progress = 0.5; field._guide_progress = 0.0
		field._has_authoritative_rotation_sign = true; field._required_rotation_sign = 0
		field.queue_redraw()
		var frame := await snap(viewport)
		var cap := frame.get_pixel(120, 200); var join := frame.get_pixel(170, 200); var body := frame.get_pixel(270, 200)
		check(absf(cap.a - body.a) < 0.02 and absf(join.a - body.a) < 0.02, "圆帽与条身接合处透明度一致 %s" % side)
		check(body.a > 0.69 and body.a < 0.74, "已填充部分仍半透明，实际 alpha %.3f" % body.a)
		check(frame.get_pixel(450, 200).a < 0.4, "未填充轨道不被实心描边托底覆盖")
		check(body.b > body.r if side == 0 else body.r > body.b, "生侧灰青、死侧赭红 %s" % side)
		check(frame.get_pixel(170, 160).a < 0.85, "接合区没有完整圆帽的内部亮轮廓")
		frame.save_png(OUTPUT + "/straight-%d.png" % side)
		field._authoritative_traversal_index = 1; field.queue_redraw()
		frame = await snap(viewport)
		check(frame.get_pixel(450, 200).a > 0.4 and frame.get_pixel(250, 200).a < 0.4, "往返第二程从另一端填充")
		field._interaction_open = false; field._approach_progress = 1.0
		field.queue_redraw(); frame = await snap(viewport)
		check(field._cue_segments[0].size() == 1 and field._cue_segments[0][0][0].is_equal_approx(field._cue_segments[0][0][-1]), "起手缩圈完整闭合，不再裁掉条身内半圈")
		var overlap := frame.get_pixel(202, 200)
		check(overlap.a > 0.8 and maxf(overlap.r, overlap.b) > 0.55, "缩圈内侧真实像素位于条身上方")
		frame.save_png(OUTPUT + "/start-ring-%d.png" % side)
		field._approach_progress = 0.0
		field._interaction_open = false; field._player_progress = 0.0; field._authoritative_traversal_index = 0
		field.queue_redraw(); frame = await snap(viewport)
		check(field._leg_fill_progress() == 0.0 and field._display_fill_progress() > 0.0, "预填只改变显示，真实调频进度仍为零")
		check(frame.get_pixel(170, 200).a > frame.get_pixel(450, 200).a, "预告起点已有阵营色填充")
		check(absf(frame.get_pixel(215, 200).a - frame.get_pixel(450, 200).a) < 0.02, "预填保持圆帽大小，不延伸成一段色条")
	# 正式圆弧覆盖小半径、旋转和方向相反的谱面；复用节点不能残留直轨缓存。
	for radius: float in [40.0, 80.0, 300.0, 720.0]:
		for side: int in 2:
			field.prepare({"event_id": "curve", "affinity": side, "start_value": 0.8, "end_value": 0.2, "visual_radius_px": radius, "arc_rotation_deg": 30.0})
			field._ensure_rail_geometry()
			var valid := not field._rail_polygons.is_empty()
			for polygon: PackedVector2Array in field._rail_polygons: valid = valid and not Geometry2D.triangulate_polygon(polygon).is_empty()
			check(valid, "复用后圆弧外形可绘制，半径 %s 阵营 %s" % [radius, side])
			await snap(viewport)
	viewport.free()
	await test_glow()
	await capture_preview()
	print("TUNING STYLE: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
func test_glow() -> void:
	var viewport := SubViewport.new(); viewport.size = Vector2i(960, 540)
	viewport.transparent_bg = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var field := GrayboxFieldVisual.new(); field.scale = Vector2.ONE * 0.5; viewport.add_child(field); field.set_process(false)
	for side: int in 2:
		field.prepare({"event_id": "glow", "affinity": side, "start_value": 0.2, "end_value": 0.8, "visual_radius_px": 300.0, "traversal_count": 2})
		field.scale = Vector2.ONE * 0.5
		field.set_approach_timing(-0.5, 2.25) # 隔离起手后的主体像素，避开 80 ms 余光。
		field._interaction_open = true; field._field_active = true; field._player_progress = 0.5
		field._guide_progress = 0.0; field._has_authoritative_rotation_sign = true; field._required_rotation_sign = 0
		field.tuning_glow_enabled = false; field.queue_redraw(); var off := await snap(viewport)
		field.tuning_glow_enabled = true; field.queue_redraw(); var on := await snap(viewport)
		var outside_light := 0
		for y: int in range(0, 540, 2):
			for x: int in range(0, 960, 2):
				if off.get_pixel(x, y).a < 0.01 and on.get_pixel(x, y).a > 0.02: outside_light += 1
		check(outside_light > 50, "轮廓外实际产生柔光 %s" % side)
		check(on.get_pixel(0, 0).a == 0.0 and on.get_pixel(480, 270).a == 0.0, "光晕包围盒空白处保持透明")
		var body_pixel := Vector2i(field._point_on_slider(0.25) * 0.5)
		var color := on.get_pixelv(body_pixel)
		check(color.a < 0.90 and (color.b > color.r if side == 0 else color.r > color.b), "填充发阵营色光仍保持透景")
		var before := field._tuning_glow_material.get_instance_id()
		field._authoritative_traversal_index = 1; field.queue_redraw(); await snap(viewport)
		check(field._tuning_glow_material.get_shader_parameter("fill_from") == 0.5 and field._tuning_glow_material.get_shader_parameter("fill_to") == 1.0, "折返光效与填充使用同一区间")
		check(before == field._tuning_glow_material.get_instance_id(), "切换方向复用同一材质")
		field.reset_for_pool(); check(not field._tuning_glow.visible, "回收立即关闭光效")
	field.free(); viewport.free()

func capture_preview() -> void:
	var document := StudioDocument.new()
	StudioProjectIO.open_project("res://tests/editor/fixtures/tuning/song.json", document)
	var stage := ChartProjectLoader.make_stage(document.song, document.chart())
	stage.visual_theme = load("res://content/stages/s08/stage_visual_theme.tres")
	stage.background = load("res://content/backgrounds/s00_grave_background.tres")
	var viewport := SubViewport.new(); viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var preview = load("res://src/tools/chart_studio/preview_session.gd").new(); root.add_child(preview)
	preview.sound_enabled = false
	check(preview.load_preview(stage, viewport), "载入正式写谱器预览")
	for time_us: int in [2500000, 3800000, 5750000]:
		await preview.seek_preview(time_us)
		(await snap(viewport)).save_png(OUTPUT + "/preview-%d.png" % time_us)
	preview.free(); viewport.free()


func test_start_handoff(field: GrayboxFieldVisual) -> void:
	## 以歌曲绝对时刻检查收束与开滑边界，避免暂停和定位重启缓动。
	field.prepare({"event_id": "handoff", "affinity": 0, "start_value": 0.2, "end_value": 0.8})
	field.set_preview_presentation(1, 1, 0.7)
	field.set_approach_timing(1.44, 1.44)
	check(field._start_cue_visible() and is_equal_approx(field._start_cue_radius_px(), field.cue_style.tuning_start_radius), "大圈与滑条同步出现")
	field.set_approach_timing(1.34, 1.44)
	check(field._start_cue_visible() and field._start_cue_radius_px() > field.cue_style.tuning_start_radius + 1.0, "出现后100毫秒已明显外扩，没有等待段")
	var radii: Array[float] = []
	for progress: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		field.set_approach_timing((1.0 - progress) * 1.44, 1.44)
		radii.append(field._start_cue_radius_px())
	check(radii[1] > radii[0] and radii[1] - radii[0] < 8.0, "出现后先小幅外扩")
	field.set_approach_timing(1.44 * 0.7, 1.44)
	var apex := field._start_cue_radius_px()
	check(apex > radii[2] and apex > radii[0], "连续外扩至原定最高点，随后约一秒收完")
	for i in range(1, 4):
		check(radii[i] - radii[i + 1] > radii[i - 1] - radii[i], "向外减速后转向，向内收束持续加速")
	check(is_equal_approx(radii[-1], field.tuning_rail_width * 0.5), "收束终点并入源泉外框")
	field.set_approach_timing(0.04, 1.44)
	check(field._preview_content_alpha() > 0.7 and field._preview_content_alpha() < 1.0, "开滑前轨道连续提亮")
	field.set_approach_timing(0.0, 1.44)
	var before_radius := field._start_cue_radius_px(); var before_alpha := field._preview_content_alpha()
	field._interaction_open = true
	check(is_equal_approx(before_radius, field._start_cue_radius_px()) and is_equal_approx(before_alpha, field._preview_content_alpha()), "开滑边界半径和亮度连续")
	check(field._start_cue_visible() and field._start_cue_handoff_alpha() == 1.0, "开滑与缩圈余光重叠，无等待")
	field.set_approach_timing(-0.04, 1.44)
	var middle := field._start_cue_handoff_alpha()
	check(middle > 0.0 and middle < 1.0, "余光在80毫秒内淡出")
	check(field._start_cue_handoff_alpha() == middle, "冻结时钟不会继续退光")
	field.set_approach_timing(-0.08, 1.44)
	check(not field._start_cue_visible(), "80毫秒后缩圈彻底退出")
	field.set_approach_timing(-0.04, 1.44)
	check(is_equal_approx(field._start_cue_handoff_alpha(), middle), "定位重演恢复同一余光状态")
