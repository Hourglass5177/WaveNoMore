extends SceneTree
## 依赖失败、绝对时钟显隐及正式材质透明像素；不改变领域判定与伤害。
var checks := 0
var failures := 0
const OUTPUT := "res://builds/visual-review/tuning-lifecycle"

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)

func slider(id: String, start: float, finish: float, ids := PackedStringArray(["life", "death"])) -> Dictionary:
	return {"id": id, "event_id": id, "unit_kind": &"tuning", "affinity": 0,
		"start_us": roundi(start * 1000000), "end_us": roundi(finish * 1000000),
		"start_value": 0.2, "end_value": 0.8, "visual_hold_ids": ids}

func run() -> void:
	test_schedule()
	test_compiled_dependencies()
	await test_host()
	print("TUNING LIFECYCLE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func test_schedule() -> void:
	var scheduler := ChartScheduler.new()
	root.add_child(scheduler)
	var first := slider("first", 3.0, 5.0)
	var later := slider("later", 7.0, 9.0)
	var next := slider("next", 10.0, 12.0, PackedStringArray(["next_life", "next_death"]))
	scheduler.configure({"tuning_sliders": [first, later, next]}, 2.0)
	check(scheduler.tuning_visibility("first", first, 1.0) == 0.0, "进入预读窗从透明开始")
	check(is_equal_approx(scheduler.tuning_visibility("first", first, 1.06), 0.5), "60 ms 平滑淡入一半")
	check(is_equal_approx(scheduler.tuning_visibility("first", first, 1.12), 1.0), "120 ms 淡入完成")
	check(is_equal_approx(scheduler.tuning_visibility("first", first, 5.06), 0.5), "正常结束短暂淡出")
	check(scheduler.tuning_visibility("first", first, 5.12) < 0.00001, "正常收尾透明归零")
	for side: String in ["life", "death"]:
		scheduler.reset(); scheduler.advance(3.0, 3.0)
		scheduler.mark_judged(side, GameplayTypes.JudgmentGrade.MISS, 3.01)
		check(is_equal_approx(scheduler.tuning_visibility("first", first, 3.07), 0.5), "任一关联 Hold 失败，滑条淡出：" + side)
		scheduler.mark_judged(side, GameplayTypes.JudgmentGrade.MISS, 3.05)
		check(is_equal_approx(scheduler.tuning_visibility("first", first, 3.07), 0.5), "重复事件不重启淡出")
		scheduler.advance(3.14, 3.14)
		check(not scheduler._active.has("first"), "失败淡出后立即回收")
		scheduler.advance(7.5, 7.5)
		check(not scheduler._active.has("later"), "失败路径后续分段不再生成")
		scheduler.advance(10.1, 10.1)
		check(scheduler._active.has("next"), "另一组 Hold 的下一条不受影响")
	scheduler.reset(); scheduler.mark_judged("life", GameplayTypes.JudgmentGrade.MISS, 1.06)
	check(is_equal_approx(scheduler.tuning_visibility("first", first, 1.09), 0.421875), "淡入中断从已有亮度退出")
	scheduler.reset(); scheduler.advance(3.0, 3.0)
	scheduler.mark_judged("life", GameplayTypes.JudgmentGrade.GOOD, 3.0)
	scheduler.mark_judged("unrelated", GameplayTypes.JudgmentGrade.MISS, 3.0)
	check(scheduler.tuning_visibility("first", first, 3.06) == 1.0, "成功结果及无关失败不隐藏")
	scheduler.mark_judged("life", GameplayTypes.JudgmentGrade.MISS, 3.0)
	var played := scheduler.tuning_visibility("first", first, 3.06)
	scheduler.seek(3.06, 3.06)
	scheduler.mark_judged("life", GameplayTypes.JudgmentGrade.MISS, 3.0)
	check(is_equal_approx(played, scheduler.tuning_visibility("first", first, 3.06)), "定位重演与连续播放一致")
	scheduler.seek(2.0, 2.0)
	check(scheduler.tuning_visibility("first", first, 2.0) == 1.0, "回退清除旧失败")
	# 旧频率滑条没有显式关联，覆盖时间窗仍可找到依赖。
	var holds := []
	for side: int in 2:
		holds.append({"id": "legacy_%d" % side, "affinity": side, "unit_kind": &"hold", "start_us": 2000000, "end_us": 6000000})
	var legacy := slider("legacy", 3, 5, PackedStringArray())
	scheduler.configure({"notes": holds, "tuning_sliders": [legacy]}, 2)
	scheduler.mark_judged("legacy_1", 3, 3.0)
	check(scheduler.tuning_visibility("legacy", legacy, 3.13) == 0.0, "旧谱按双 Hold 覆盖区间关联")
	scheduler.free()

func test_compiled_dependencies() -> void:
	var document := StudioDocument.new()
	check(StudioProjectIO.open_project("res://tests/editor/fixtures/tuning/song.json", document).is_empty(), "正式多节点谱面读取")
	var rules := GameplayRuleSet.new()
	var projected := ChartPathAdapter.project(document.chart(), rules)
	var compiled: CompiledChart = ChartCompiler.compile(projected, rules).compiled
	for path: TuningPathEvent in document.chart().tuning_paths:
		for item: Dictionary in compiled.tuning_sliders:
			if str(item.id).begins_with(path.event_id + ":"):
				check(item.visual_hold_ids == PackedStringArray([path.hold_id, path.support_hold_id]), "每个编译分段保留明确双 Hold 依赖")
	for item: TuningSliderEvent in projected.tuning_sliders: item.visual_hold_ids.clear()
	var without: CompiledChart = ChartCompiler.compile(projected, rules).compiled
	check(compiled.content_hash == without.content_hash, "表现依赖不改变 Replay 内容哈希")
	var inputs := StudioPreviewInputs.build(compiled, rules)
	var replay := ReplayData.new(); replay.inputs = inputs
	check(ReplayRunner.run(compiled, rules, replay).digest == ReplayRunner.run(without, rules, replay).digest, "判定、伤害与 Ghost 结算保持一致")

func step(host: NoteVisualHost, scheduler: ChartScheduler, at: float) -> void:
	scheduler.advance(at + 0.3, at)
	var clock := ClockSample.new(); clock.judge_time_sec = at; clock.visual_time_sec = at + 0.3
	host.set_clock_sample(clock)

func test_host() -> void:
	var viewport := SubViewport.new(); viewport.size = Vector2i(960, 540)
	viewport.transparent_bg = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var host := NoteVisualHost.new(); host.scale = Vector2.ONE * 0.5
	for name: String in ["LifeNoteSlot", "DeathNoteSlot", "FieldSlot", "PoolRoot"]:
		var slot := Node2D.new(); slot.name = name; host.add_child(slot)
	viewport.add_child(host)
	var scheduler := ChartScheduler.new(); root.add_child(scheduler); host.bind_scheduler(scheduler)
	host.approach_duration_sec = 2.0
	var data := slider("rail", 3.0, 5.0)
	data.visual_radius_px = 300.0
	scheduler.configure({"tuning_sliders": [data]}, 2.0)
	step(host, scheduler, 1.06)
	var field: GrayboxFieldVisual = host._active.rail.node
	field.set_process(false)
	check(is_equal_approx(field.modulate.a, 0.5), "宿主使用判定时钟，不受画面提前量影响")
	for i in 4: step(host, scheduler, 1.06)
	check(is_equal_approx(field.modulate.a, 0.5), "暂停与重复快照不会反复乘透明度")
	step(host, scheduler, 1.2)
	var full: Image
	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(OUTPUT)
		await process_frame; await RenderingServer.frame_post_draw
		full = viewport.get_texture().get_image(); full.save_png(OUTPUT + "/visible.png")
	scheduler.mark_judged("life", 3, 1.2)
	step(host, scheduler, 1.26)
	check(is_equal_approx(field.modulate.a, 0.5), "未到起点的 Hold 失败也淡出完整滑条")
	if full != null:
		await process_frame; await RenderingServer.frame_post_draw
		var half := viewport.get_texture().get_image(); half.save_png(OUTPUT + "/fading.png")
		var energy_full := 0.0; var energy_half := 0.0
		for y: int in range(0, 540, 2):
			for x: int in range(0, 960, 2):
				energy_full += full.get_pixel(x, y).a; energy_half += half.get_pixel(x, y).a
		check(energy_full > 20.0 and energy_half / energy_full > 0.4 and energy_half / energy_full < 0.7, "实际轨道、提示与光晕像素同步衰减")
	step(host, scheduler, 1.33)
	check(not host._active.has("rail") and not field.visible, "淡出后节点进入对象池")
	scheduler.reset(); step(host, scheduler, 1.12)
	check(host._active.rail.node == field and is_equal_approx(field.modulate.a, 1.0), "复用原节点无残留透明度")
	viewport.free(); scheduler.free()
