extends SceneTree
## 对照按键、波接触与回收三条时间边界，并用正式预览验证 Seek。
var failures := 0
var checks := 0
const OUTPUT := "res://builds/visual-review/tap-radius"
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", message)
func note(side: int, pair := true) -> Dictionary:
	return {"event_id": "tap", "id": "tap", "unit_kind": &"tap", "affinity": side, "tick": 960, "start_us": 1000000, "end_us": 1000000, "double_tap": pair}
func run() -> void:
	for side: int in [0, 1]:
		for pair: bool in [false, true]:
			for hit: float in [0.94, 1.0, 1.06]: test_host(side, pair, hit)
	await test_preview()
	if DisplayServer.get_name() != "headless": await render_samples()
	print("TAP FEEDBACK TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func test_host(side: int, pair: bool, hit: float) -> void:
	var scheduler := ChartScheduler.new(); root.add_child(scheduler)
	var host := NoteVisualHost.new()
	for slot_name: String in ["LifeNoteSlot", "DeathNoteSlot", "FieldSlot", "PoolRoot"]:
		var slot := Node2D.new(); slot.name = slot_name; host.add_child(slot)
	root.add_child(host); host.bind_scheduler(scheduler)
	host.preview_time_driven = true
	scheduler.configure({"notes": [note(side, pair)]})
	scheduler.advance(hit, hit)
	host.set_visual_time(hit)
	var tap: GrayboxNoteVisual = host._active.tap.node
	tap._double_tap = pair
	tap.set_note_glow_time(hit, 1.0 - hit)
	var ring: Node2D = host._active.tap.timing_ring
	var accepted := tap.global_transform
	var grade := GameplayTypes.JudgmentGrade.PERFECT if hit == 1.0 else GameplayTypes.JudgmentGrade.GOOD
	scheduler.mark_timing_confirmed("tap", grade)
	check(not ring.visible and tap.glow_amount == 0.0 and tap._tap_body_only(), "命中后隐藏圆环和白光，进入暗淡本体阶段")
	check(tap._tap_hit_transform.is_equal_approx(accepted), "命中印记记录按键位置")
	host.set_visual_time(hit + 0.04)
	check(tap.global_position.distance_to(accepted.origin) > 0.1 and tap._tap_hit_transform.is_equal_approx(accepted), "本体继续移动，印记不跟随")
	scheduler.mark_timing_confirmed("tap", grade); tap.play_judgment(grade)
	check(is_equal_approx(tap._tap_hit_time, hit), "重复判定不重播印记")
	var contact := {"contact_us": roundi((hit + 0.09) * 1000000.0), "position": Vector2(880, 510)}
	scheduler.mark_wave_contacted("tap", contact)
	host.set_visual_time(hit + 0.15)
	check(tap.position == contact.position and tap.visible, "波接触后在实际位置消散")
	var before := tap._glow_time
	host.set_visual_time(hit + 0.15)
	check(tap._glow_time == before and tap.position == contact.position, "暂停保持消散进度和位置")
	scheduler.mark_wave_contacted("tap", {"contact_us": contact.contact_us + 20000, "position": Vector2.ZERO})
	check(tap.position == contact.position and is_equal_approx(tap._tap_death_time, hit + 0.09), "重复接触不改变死亡位置和时间")
	host.set_visual_time(hit + 0.211)
	check(not tap.visible and not ring.visible and tap.glow_amount == 0.0, "接触 0.12 秒后隐藏本体")
	host.clear()
	host._on_visual_spawn_requested(ChartScheduler.KIND_NOTE, note(side, false))
	tap = host._active.tap.node
	check(tap.visible and not tap.timing_confirmed and not tap.wave_contacted and is_inf(tap._tap_hit_time) and is_inf(tap._tap_death_time), "对象池复用清除命中与死亡状态")
	tap.play_miss()
	check(tap.missed and not tap._tap_body_only() and is_inf(tap._tap_death_time), "漏击仍使用原反馈")
	host.free(); scheduler.free()

func state(preview: Node) -> Dictionary:
	var result := {}
	var host: NoteVisualHost = preview.stage_root.presentation._note_visual_host
	for id: String in host._active:
		if not id.begins_with("feedback_"): continue
		var item: Dictionary = host._active[id]
		var tap: GrayboxNoteVisual = item.node
		result[id] = {"position": tap.position, "rotation": tap.rotation, "hit_time": tap._tap_hit_time,
			"anchor": tap._tap_hit_transform, "death_time": tap._tap_death_time, "visible": tap.visible,
			"ring": item.timing_ring.visible, "glow": tap.glow_amount}
	return result

func test_preview() -> void:
	var stage: StageDefinition = ChartProjectLoader.load_stage("res://tests/editor/fixtures/tuning/song.json").stage
	for side: int in [0, 1]:
		var tap := NoteEvent.new(); tap.event_id = "feedback_%d" % side; tap.affinity = side; tap.tick = 480
		stage.chart.note_events.append(tap)
	var viewport := SubViewport.new(); viewport.size = Vector2i(1920, 1080); root.add_child(viewport)
	var preview = load("res://src/tools/chart_studio/preview_session.gd").new(); root.add_child(preview); preview.sound_enabled = false
	check(preview.load_preview(stage, viewport), "加载正式预览")
	for target: float in [0.49, 0.5, 0.54, 0.6, 0.7, 0.8, 0.86, 1.0]:
		await preview.seek_preview(roundi(target * 1000000.0))
		var direct := state(preview)
		await preview.seek_preview(0)
		var cursor := 0.0
		while cursor < target:
			cursor = minf(cursor + 0.013, target); preview.advance(cursor, false)
		var played := state(preview)
		# 浮点步进仅在最后一位有舍入差；关键空间量按近似比较，其余状态严格比较。
		var same := direct.keys() == played.keys()
		for id: String in direct:
			if not played.has(id): same = false; continue
			for key: String in direct[id]:
				var a: Variant = direct[id][key]; var b: Variant = played[id][key]
				if a is Vector2 or a is Transform2D: same = same and a.is_equal_approx(b)
				elif a is float: same = same and (a == b or is_equal_approx(a, b))
				else: same = same and a == b
		if not same: print("SEEK DIFF ", target, " direct=", direct, " played=", played)
		check(same, "连续播放与直接定位一致 %.3f" % target)
		preview.advance(target, false); check(state(preview) == played, "暂停冻结阶段 %.3f" % target)
	preview.free(); viewport.free()

func label(text: String, at: Vector2) -> void:
	var item := Label.new(); item.text = text; item.position = at; item.add_theme_font_size_override("font_size", 24); root.add_child(item)

func render_samples() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var bg := ColorRect.new(); bg.size = Vector2(1280, 720); bg.color = Color("211e27"); root.add_child(bg)
	label("Tap 命中与消散", Vector2(40, 24))
	for i: int in 4:
		var x := 165.0 + i * 310.0
		label(["接近", "按键命中", "暗淡续行", "波接触消散"][i], Vector2(x - 64, 100))
		for side: int in [0, 1]:
			var tap := GrayboxNoteVisual.new(); root.add_child(tap); tap.prepare(note(side))
			tap.position = Vector2(x, 230 + side * 250); tap.set_approach_progress(1)
			tap.set_note_glow_time(1, 0)
			if i > 0:
				tap.play_timing_confirmed(GameplayTypes.JudgmentGrade.PERFECT)
				tap.position.x += 18
				tap.set_note_glow_time(1.025 if i == 1 else 1.2, 0)
			if i == 3:
				tap.play_wave_contact({"contact_us": 1200000})
				tap.set_note_glow_time(1.24, 0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = size; await process_frame; await process_frame; await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT + "/tap-feedback-%d.png" % size.x)
