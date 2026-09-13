extends SceneTree
## 双押头部索引、Hold 独立白光及身体像素不变回归。
const OUTPUT := "res://builds/mixed-double-review"
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
	print("PASS " if ok else "FAIL ", message)
func note(id: String, side: int, kind: StringName, tick: int = 1000, group: String = "") -> Dictionary:
	return {"event_id": id, "affinity": side, "unit_kind": kind, "tick": tick, "group_id": group, "start_us": tick * 1000, "end_us": (tick + (3000 if kind == &"hold" else 0)) * 1000}
func snap(viewport: SubViewport) -> Image:
	await process_frame; await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	test_pairs()
	test_times()
	await test_pixels()
	await test_preview()
	print("MIXED DOUBLE: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
func test_pairs() -> void:
	for kinds: Array in [[&"tap", &"tap"], [&"hold", &"hold"], [&"tap", &"hold"], [&"hold", &"tap"]]:
		for grouped: bool in [false, true]:
			var scheduler := ChartScheduler.new(); root.add_child(scheduler)
			var notes := [note("a", 0, kinds[0], 1000, "pair" if grouped else ""), note("b", 1, kinds[1], 2000 if grouped else 1000, "pair" if grouped else "")]
			var before := notes.duplicate(true); scheduler.configure({"notes": notes}); scheduler.advance(0.5, 0.5)
			check(scheduler._active.a.data.double_press and scheduler._active.b.data.double_press, "头部配对 %s 组合=%s" % [kinds, grouped])
			check(notes == before, "双押索引不修改原谱数据")
			scheduler.seek(0.5, 0.5); check(scheduler._active.a.data.double_press, "定位重建保留完整谱面配对")
			scheduler.free()
	for notes: Array in [
		[note("a", 0, &"hold"), note("b", 0, &"tap")],
		[note("a", 0, &"hold", 1000, "one"), note("b", 0, &"hold", 2000, "one")],
		[note("a", 0, &"hold"), note("b", 1, &"tap", 4000)],
		[note("a", 0, &"hold"), note("b", 1, &"hold", 2000)],
		[note("a", 0, &"tap")]]:
		var scheduler := ChartScheduler.new(); root.add_child(scheduler); scheduler.configure({"notes": notes})
		check(scheduler._double_press_ids.is_empty(), "同侧、尾部相遇、持续重叠或单音不形成双押")
		scheduler.free()
func test_times() -> void:
	for side: int in 2:
		for hit: float in [0.475, 0.94, 1.0, 1.06]:
			for miss: bool in [false, true]:
				var hold := GrayboxHoldVisual.new(); root.add_child(hold)
				hold.effect_requested.connect(func(_key, _source, _at, _direction, _kind): pass)
				var data := note("hold", side, &"hold"); data.double_press = true; hold.prepare(data)
				hold.set_note_glow_time(0.3, 0.7); check(hold.head_double_glow == 0.0, "接近前头部不亮")
				hold.set_note_glow_time(0.475, 0.525); check(is_equal_approx(hold.head_double_glow, 0.5) and hold.glow_amount == 0.0, "渐亮中点仅头部有白光")
				hold.set_note_glow_time(hit, 1.0 - hit)
				var at_hit := hold.head_double_glow
				hold.play_timing_confirmed(GameplayTypes.JudgmentGrade.MISS if miss else GameplayTypes.JudgmentGrade.PERFECT)
				hold.set_note_glow_time(hit + 0.04, 0.0)
				check(is_equal_approx(hold.head_double_glow, at_hit * 0.5), "接受或漏击后 40 ms 从当时亮度减半")
				hold.play_timing_confirmed(GameplayTypes.JudgmentGrade.MISS if miss else GameplayTypes.JudgmentGrade.PERFECT)
				hold.set_note_glow_time(hit + 0.04, 0.0)
				check(is_equal_approx(hold.head_double_glow, at_hit * 0.5), "重复事件与暂停不重启淡出")
				hold.set_note_glow_time(hit + 0.08, 0.0); check(is_zero_approx(hold.head_double_glow), "80 ms 后双押光结束")
				hold.reset_for_pool(); hold.prepare(note("single", side, &"hold")); hold.set_note_glow_time(1.0, 0.0)
				check(hold.head_double_glow == 0.0 and hold.glow_amount == 0.0, "复用为单 Hold 清除全部白光")
				hold.free()
func test_pixels() -> void:
	var viewport := SubViewport.new(); viewport.size = Vector2i(800, 320); viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	for textured: bool in [false, true]:
		for side: int in 2:
			var hold := GrayboxHoldVisual.new(); viewport.add_child(hold)
			if textured:
				hold.head_texture = load("res://assets/image/note/hold_note.png")
				hold.body_texture = load("res://assets/image/note/hold_body.png")
			var data := note("pixel", side, &"hold"); data.double_press = true; hold.prepare(data)
			hold.position = Vector2(600, 160); hold.set_body_target(350); hold.advance_body(0.0)
			# 固定弯曲和长度，隔离光效变化，避免把身体运动计为颜色变化。
			for i: int in hold._path_spine.size(): hold._path_spine[i].y += sin(float(i) / (hold._path_spine.size() - 1) * PI) * 30.0
			hold._rebuild_body_mesh(); hold._update_body_material()
			hold.set_note_glow_time(0.3, 0.7); var off := await snap(viewport)
			var body_id := hold._body_mesh.get_instance_id() if hold._body_mesh != null else 0
			hold.set_note_glow_time(0.55, 0.45); var on := await snap(viewport)
			var changed := 0; var body_same := true
			for y: int in 320:
				for x: int in range(150, 710):
					if x < 510: body_same = body_same and off.get_pixel(x, y) == on.get_pixel(x, y)
					elif off.get_pixel(x, y) != on.get_pixel(x, y): changed += 1
			check(body_same and changed > 100, "双押仅改变头部像素，身体与尾部不变 %s/%s" % [side, textured])
			check(hold.tap_material.get_shader_parameter(&"condition_light") == 1.0 and hold.glow_amount == 0.0, "贴图头部与身体使用独立白光参数")
			check(hold._body_mesh == null or hold._body_mesh.get_instance_id() == body_id, "白光未新建身体网格")
			on.save_png(OUTPUT + "/head-on-%s-%s.png" % [side, textured]); off.save_png(OUTPUT + "/head-off-%s-%s.png" % [side, textured])
			hold.set_tuning_glow(true, 0.55); hold.set_tuning_glow(true, 0.60)
			check(is_equal_approx(hold.glow_amount, 0.5) and is_equal_approx(hold._surface_glow_amount(), 1.0), "调频半亮与双押全亮取最大值，不叠加")
			hold.set_tuning_glow(true, 0.65); hold.set_note_glow_time(0.65, 0.35); var tuning := await snap(viewport)
			check(tuning.get_data() != on.get_data(), "调频接管时身体开始提亮")
			hold.play_hold_finished(1.0); check(hold.head_double_glow == 0.0 and not hold.visible, "收尾清空头部白光")
			hold.free()
	viewport.free()
func test_preview() -> void:
	# 调频例谱保留现有 Hold/Tuning，增加一侧 Tap 与另一侧 Hold 头同刻。
	var stage: StageDefinition = ChartProjectLoader.load_stage("res://tests/editor/fixtures/tuning/song.json").stage
	var tap := NoteEvent.new(); tap.event_id = "mixed_tap"; tap.affinity = 1; tap.tick = 1920; stage.chart.note_events.append(tap)
	stage.visual_theme = load("res://content/stages/s08/stage_visual_theme.tres")
	stage.background = load("res://content/backgrounds/s00_grave_background.tres")
	var viewport := SubViewport.new(); viewport.size = Vector2i(1920, 1080); viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var preview = load("res://src/tools/chart_studio/preview_session.gd").new(); root.add_child(preview); preview.sound_enabled = false
	var loaded: bool = preview.load_preview(stage, viewport); check(loaded, "正式预览加载混合双押")
	if loaded:
		for at: float in [1.475, 1.55, 2.04, 2.09, 3.8]:
			await preview.seek_preview(roundi(at * 1000000.0)); var direct := preview_state(preview)
			(await snap(viewport)).save_png(OUTPUT + "/preview-%.3f.png" % at)
			await preview.seek_preview(0); var cursor := 0.0
			while cursor < at:
				cursor = minf(cursor + 0.013, at); preview.advance(cursor, false)
			var played := preview_state(preview)
			var same := direct.keys() == played.keys()
			for id: String in direct: same = same and played.has(id) and direct[id].is_equal_approx(played[id])
			check(same, "直接定位与连续播放的头部／调频光一致 %.3f" % at)
			if at == 1.55:
				check(direct.life_hold.x > 0.99 and direct.life_hold.y == 0.0 and direct.mixed_tap.x > 0.99, "实际混合双押双方头部亮起，Hold 身体不亮")
	preview.free(); viewport.free()
func preview_state(preview: Node) -> Dictionary:
	var result := {}
	for id: String in preview.stage_root.presentation._note_visual_host._active:
		var item: Node = preview.stage_root.presentation._note_visual_host._active[id].node
		if item is GrayboxNoteVisual: result[id] = Vector2(item._surface_glow_amount(), item.glow_amount)
	return result
