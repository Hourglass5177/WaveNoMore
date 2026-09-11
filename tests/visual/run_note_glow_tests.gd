extends SceneTree

## 同一入口运行状态回归和真实 GPU 取样。截图只供审美检查，不做逐像素断言。
var failures := 0
const LIFE = GameplayTypes.Affinity.ZHU
const DEATH = GameplayTypes.Affinity.XUAN
const OUTPUT = "res://builds/visual-review/note-glow"

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", message)

func _note(id: String, side: int, tick: int, group := "", kind := "tap") -> Dictionary:
	return {"event_id": id, "id": id, "affinity": side, "tick": tick, "group_id": group, "unit_kind": StringName(kind), "start_us": tick * 1000, "end_us": (tick + (3000 if kind == "hold" else 0)) * 1000}

func _run() -> void:
	if DisplayServer.get_name() != "headless":
		var warmup = preload("res://src/presentation/vfx/note_effect_warmup.gd")
		warmup.prepare(root)
		warmup.prepare(root)
		_check(root.find_children("*NoteEffectWarmup*", "", false, false).size() == 1, "白光与 Ghost 只预热一次")
		await RenderingServer.frame_post_draw
		await process_frame
		_check(root.get_node_or_null("NoteEffectWarmup") == null, "首次绘制后释放预热视口")
	_test_pairs()
	_test_tap()
	_test_hold_control()
	await _test_preview()
	if DisplayServer.get_name() != "headless": await _render_samples()
	print("NOTE GLOW TESTS: ", failures)
	quit(1 if failures else 0)

func _test_pairs() -> void:
	var notes: Array = [_note("a", LIFE, 1000), _note("b", DEATH, 1000),
		_note("c", LIFE, 2000, "pair"), _note("d", DEATH, 3000, "pair"),
		_note("e", LIFE, 4000), _note("f", DEATH, 4000, "", "hold"),
		_note("g", LIFE, 5000, "same-side"), _note("h", LIFE, 5500, "same-side")]
	var before := notes.duplicate(true)
	var scheduler := ChartScheduler.new()
	root.add_child(scheduler)
	scheduler.configure({"notes": notes})
	var seen: Dictionary = {}
	scheduler.visual_spawn_requested.connect(func(_kind: StringName, data: Dictionary): seen[data.event_id] = data.double_tap)
	scheduler.advance(5.6, 5.6)
	_check(seen.a and seen.b, "同 tick、无组合的双侧 Tap 发光")
	_check(seen.c and seen.d, "同非空组合、不同 tick 的双侧 Tap 发光")
	_check(not seen.e and not seen.f and not seen.g and not seen.h, "Tap + Hold 与同侧组合不误亮")
	_check(notes == before, "双押表现标记不写回编译谱数据")
	scheduler.seek(0.85, 0.85)
	_check(scheduler._active.a.data.double_tap, "Seek 后仍从完整谱面识别双押")
	scheduler.queue_free()

func _test_tap() -> void:
	var tap := GrayboxNoteVisual.new()
	root.add_child(tap)
	var data := _note("tap", LIFE, 1000)
	data.double_tap = true
	tap.prepare(data)
	tap.set_note_glow_time(0.3, 0.7)
	_check(tap.glow_amount == 0.0, "接近前保持原样")
	tap.set_note_glow_time(0.475, 0.525)
	_check(is_equal_approx(tap.glow_amount, 0.5), "0.15 秒平滑渐亮中点")
	tap.set_note_glow_time(0.55, 0.45)
	_check(is_equal_approx(tap.glow_amount, 1.0), "判定前 0.45 秒达到全亮")
	tap.set_note_glow_time(0.55, 0.45)
	_check(is_equal_approx(tap.glow_amount, 1.0), "暂停／重复时钟不推进光效")
	tap.play_miss()
	tap.set_note_glow_time(0.59, 0.41)
	_check(is_equal_approx(tap.glow_amount, 0.5), "漏击后快速淡出")
	tap.set_note_glow_time(0.63, 0.37)
	_check(is_zero_approx(tap.glow_amount), "漏击后不再持续发光")
	tap.reset_for_pool()
	tap.prepare(_note("single", DEATH, 1000))
	tap.set_note_glow_time(1.0, 0.0)
	_check(tap.glow_amount == 0.0 and not tap._glow_visual.visible, "对象池复用到普通 Tap 清除白光")
	tap.queue_free()

func _test_hold_control() -> void:
	var host := NoteVisualHost.new()
	for slot_name: String in ["LifeNoteSlot", "DeathNoteSlot", "FieldSlot", "PoolRoot"]:
		var slot := Node2D.new()
		slot.name = slot_name
		host.add_child(slot)
	root.add_child(host)
	var life := GrayboxHoldVisual.new()
	var death := GrayboxHoldVisual.new()
	var field := GrayboxFieldVisual.new()
	host.add_child(life); host.add_child(death); host.add_child(field)
	life.prepare(_note("life", LIFE, 1000, "", "hold"))
	death.prepare(_note("death", DEATH, 1000, "", "hold"))
	life.advance_body(0.0); death.advance_body(0.0)
	host._active = {"life": {"node": life, "kind": ChartScheduler.KIND_NOTE, "hold_anchor_distance": 1.0},
		"death": {"node": death, "kind": ChartScheduler.KIND_NOTE, "hold_anchor_distance": 1.0},
		"slider": {"node": field, "kind": ChartScheduler.KIND_TUNING, "data": {"event_id": "slider"}}}
	host.gameplay_snapshot = {"dual_holding_notes": true, "life_holding_note_id": "life", "death_holding_note_id": "death",
		"active_tuning_sliders": {"slider": {"affinity": LIFE, "interaction_open": true, "dragging": false}}}
	_step_control(host, 1.0)
	_step_control(host, 1.2)
	_check(life.glow_amount == 0.0, "进入窗口但未接管不亮")
	host.gameplay_snapshot.active_tuning_sliders.slider.dragging = true
	_step_control(host, 1.2); _step_control(host, 1.25)
	_check(is_equal_approx(life.glow_amount, 0.5), "接管 Hold 后平滑亮起")
	_step_control(host, 1.3)
	_check(is_equal_approx(life.glow_amount, 1.0) and death.glow_amount == 0.0, "仅所属侧 Hold 全亮，另一侧不误亮")
	_check(life._glow_visual.visible and life._body_glow.visible and life._tail_glow.visible, "头、身、尾同步发光")
	_check(life._glow_visual.material != death._glow_visual.material, "各实例参数独立")
	_step_control(host, 1.3)
	_check(is_equal_approx(life.glow_amount, 1.0), "稳定持有且不移动仍然发光")
	host.gameplay_snapshot.dual_holding_notes = false
	_step_control(host, 1.3); _step_control(host, 1.34)
	_check(is_equal_approx(life.glow_amount, 0.5), "松开后快速淡出")
	_step_control(host, 1.38)
	_check(is_zero_approx(life.glow_amount), "松开后完全熄灭")
	host.gameplay_snapshot.dual_holding_notes = true
	_step_control(host, 1.4); _step_control(host, 1.5)
	_check(is_equal_approx(life.glow_amount, 1.0), "有效重新接管后恢复白光")
	var second_field := GrayboxFieldVisual.new()
	host.add_child(second_field)
	host._active["second"] = {"node": second_field, "kind": ChartScheduler.KIND_TUNING, "data": {"event_id": "second"}}
	host.gameplay_snapshot.active_tuning_sliders["second"] = {"affinity": DEATH, "interaction_open": true, "dragging": true}
	_step_control(host, 1.5); _step_control(host, 1.6)
	_check(is_equal_approx(life.glow_amount, 1.0) and is_equal_approx(death.glow_amount, 1.0), "双侧接管时两条 Hold 同时发光")
	host.gameplay_snapshot.active_tuning_sliders.second.dragging = false
	host.gameplay_snapshot.active_tuning_sliders.second.interaction_open = false
	_step_control(host, 1.6); _step_control(host, 1.68)
	_check(is_zero_approx(death.glow_amount) and is_equal_approx(life.glow_amount, 1.0), "单侧窗口结束只熄灭对应 Hold")
	host._active.erase("slider")
	host._active["next"] = {"node": field, "kind": ChartScheduler.KIND_TUNING, "data": {"event_id": "next"}}
	host.gameplay_snapshot.active_tuning_sliders["next"] = host.gameplay_snapshot.active_tuning_sliders.slider
	host.gameplay_snapshot.active_tuning_sliders.erase("slider")
	_step_control(host, 1.68)
	_check(is_equal_approx(life.glow_amount, 1.0), "连续滑条换接时保持亮度")
	host._active.life.hold_failed = true
	life.play_miss()
	_step_control(host, 1.76)
	_check(is_zero_approx(life.glow_amount), "失败 Hold 不被残留拖动状态点亮")
	life.reset_for_pool()
	_check(not life._body_glow.visible and not life._tail_glow.visible, "回收清除身体及尾部光效")
	host._active.clear()
	host.queue_free()

func _step_control(host: NoteVisualHost, time: float) -> void:
	host._judge_visual_time = time
	host._update_tuning_hold_controls()

func _glow_state(preview: Node) -> Dictionary:
	var result := {}
	var host: NoteVisualHost = preview.stage_root.presentation._note_visual_host
	for id: String in host._active:
		var visual: Node2D = host._active[id].node
		if visual is GrayboxNoteVisual: result[id] = snappedf(visual.glow_amount, 0.0001)
	return result

func _test_preview() -> void:
	var loaded := ChartProjectLoader.load_stage("res://tests/editor/fixtures/tuning/song.json")
	var stage: StageDefinition = loaded.stage
	_check(stage != null, "通过正式共享入口加载调频测试谱")
	if stage == null: return
	for side: int in [LIFE, DEATH]:
		var tap := NoteEvent.new()
		tap.event_id = "glow_tap_%d" % side
		tap.affinity = side
		tap.tick = 480
		stage.chart.note_events.append(tap)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	# 在自动加载节点初始化后加载运行场景，与现有写谱器测试入口保持一致。
	var preview = load("res://src/tools/chart_studio/preview_session.gd").new()
	root.add_child(preview)
	preview.sound_enabled = false
	_check(preview.load_preview(stage, viewport), "白光接入正式 StageRoot 与自动预览")
	for target: float in [0.225, 0.3, 3.55, 3.8, 4.15, 5.75]:
		await preview.seek_preview(roundi(target * 1000000.0))
		var direct := _glow_state(preview)
		if is_equal_approx(target, 0.225):
			_check(direct.get("glow_tap_0", 0.0) > 0.4 and direct.get("glow_tap_1", 0.0) > 0.4, "实际谱面双押 Tap 接近时亮起")
		if is_equal_approx(target, 3.8):
			_check(direct.values().any(func(value: float): return value > 0.9), "实际调频输入驱动 Hold 白光")
		if DisplayServer.get_name() != "headless" and target in [0.225, 3.8, 4.15]:
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
			await process_frame
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png(OUTPUT + "/stage-%.3f.png" % target)
		await preview.seek_preview(0)
		var at := 0.0
		while at < target:
			at = minf(at + 0.025, target)
			preview.advance(at, false)
		var played := _glow_state(preview)
		if direct != played: print("GLOW DIFF ", target, " seek=", direct, " play=", played)
		_check(direct == played, "白光直接定位与连续播放一致 %.3f" % target)
		preview.advance(target, false)
		_check(_glow_state(preview) == played, "预览暂停保持光效 %.3f" % target)
	preview.queue_free()
	viewport.queue_free()
	await process_frame

func _label(text: String, position: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size", 23)
	root.add_child(label)
	label.add_to_group("glow_sample")

func _render_samples() -> void:
	await process_frame
	root.content_scale_size = Vector2i(1280, 900)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.size = Vector2i(1280, 900)
	var background := ColorRect.new()
	background.color = Color("291c23")
	background.size = Vector2(1280, 900)
	root.add_child(background)
	background.add_to_group("glow_sample")
	_label("Tap / Hold · 白光效果检查", Vector2(36, 18))
	for column: int in range(3):
		var x: float = 210.0 + column * 420.0
		_label(["原样", "渐亮中", "全亮"][column], Vector2(x - 42, 64))
		for side: int in [LIFE, DEATH]:
			var tap := GrayboxNoteVisual.new()
			root.add_child(tap)
			tap.add_to_group("glow_sample")
			var data := _note("sample", side, 1000)
			data.double_tap = true
			tap.prepare(data)
			tap.position = Vector2(x + (-74 if side == LIFE else 74), 170)
			tap.set_note_glow_time(1.0, [0.7, 0.525, 0.45][column])
	for row: int in range(3):
		_label(["Hold · 程序轮廓", "Hold · 身体贴图", "Hold · 透明贴图 / 缩短"][row], Vector2(36, 265 + row * 205))
		for column: int in range(2):
			var hold := GrayboxHoldVisual.new()
			root.add_child(hold)
			hold.add_to_group("glow_sample")
			if row > 0: hold.body_texture = load("res://assets/image/fish.png")
			if row == 2:
				hold.head_texture = load("res://assets/pets/yi_huo_she.svg")
				hold.tail_texture = load("res://assets/pets/yi_huo_she.svg")
			hold.prepare(_note("sample_hold", LIFE if column == 0 else DEATH, 0, "", "hold"))
			hold.position = Vector2(560 + column * 620, 360 + row * 205)
			hold.set_body_target(390 if row < 2 else 190)
			hold.advance_body(0.0)
			# 弯曲取样沿正式脊线接口生成，检查截面边缘与头尾衔接。
			for i: int in hold._path_spine.size():
				hold._path_spine[i].y += sin(float(i) / (hold._path_spine.size() - 1) * PI) * 32
			hold._rebuild_body_mesh()
			hold._update_body_material()
			hold.set_tuning_glow(column == 1, 0.0)
			hold.set_tuning_glow(column == 1, 0.1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for size: Vector2i in [Vector2i(1280, 900), Vector2i(1920, 1080)]:
		root.size = size
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT + "/glow-%d.png" % size.x)
	for item: Node in get_nodes_in_group("glow_sample"): item.queue_free()
	await process_frame
	root.size = Vector2i(1280, 900)
	for row: int in range(2):
		var backdrop := ColorRect.new()
		backdrop.position = Vector2(0, row * 450)
		backdrop.size = Vector2(1280, 450)
		backdrop.color = Color("96252c") if row == 0 else Color("17171d")
		root.add_child(backdrop)
		for i: int in range(24):
			var tap := GrayboxNoteVisual.new()
			root.add_child(tap)
			var data := _note("dense_%d" % i, i % 2, 1000)
			data.double_tap = true
			tap.prepare(data)
			tap.position = Vector2(76 + (i % 8) * 160, row * 450 + 95 + (i / 8) * 128)
			tap.rotation = i * 0.23
			tap.set_note_glow_time(0.8, 0.2)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT + "/dense-backgrounds.png")
