extends SceneTree
## 计时提示的实际像素、绝对时钟及正式宿主接入回归。
const OUTPUT := "res://builds/timing-cue-review"
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
	var viewport := SubViewport.new(); viewport.size = Vector2i(500, 500)
	viewport.transparent_bg = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var ring := TimingRingVisual.new(); viewport.add_child(ring)
	ring.cue_style = ring.cue_style.duplicate()
	for zoom: float in [1.0, 0.5]:
		for side: int in 2:
			ring.prepare({"event_id": "ring", "affinity": side}); ring.position = Vector2(250, 250); ring.scale = Vector2.ONE * zoom
			ring.set_timing(0.6, 1.0); ring.cue_style.glow_enabled = false; ring.queue_redraw()
			var line := ring._ring_color(); var body := ring.cue_style.note_style.base(side)
			check(line.h < body.h if side == 0 else line.h > body.h, "进度色略偏青绿／暖铜，与音符本体有区分")
			var off := await snap(viewport)
			ring.cue_style.glow_enabled = true; ring.queue_redraw(); var on := await snap(viewport)
			var core := on.get_pixelv(Vector2i(ring.position + Vector2(66, 0) * zoom))
			check(core.a > 0.85 and (core.b > core.r if side == 0 else core.r > core.b), "两侧进度亮线清楚且采用阵营色 %s/%s" % [side, zoom])
			check(is_equal_approx(ring.modulate.a, 0.9), "整套音符提示使用 90% 不透明度系数")
			ring.cue_style.note_opacity = 1.0; ring.set_visual_time(0.0); var opaque := await snap(viewport)
			check(opaque.get_pixelv(Vector2i(ring.position + Vector2(66, 0) * zoom)).a > core.a, "与原系数相比实际像素略透明，叠层仍保持清晰")
			ring.cue_style.note_opacity = 0.9; ring.set_visual_time(0.0)
			var lit := 0
			for y: int in range(130, 370, 2):
				for x: int in range(130, 370, 2):
					if off.get_pixel(x, y).a < 0.01 and on.get_pixel(x, y).a > 0.01: lit += 1
			check(lit > 40, "主线外存在连续柔光 %s/%s" % [side, zoom])
			check(on.get_pixel(250, 250).a == 0.0 and on.get_pixel(120, 250).a == 0.0, "光晕不覆盖环内及包围范围之外")
			var rebuilds := ring._glow.rebuild_count
			ring.set_timing(0.6, 1.0); var frozen := await snap(viewport)
			check(frozen.get_data() == on.get_data() and ring._glow.rebuild_count == rebuilds, "重复时间像素不变且不重建网格")
			ring.set_timing(0.0, 1.0); await snap(viewport)
			check(ring._progress == 1.0 and ring._glow.rebuild_count == rebuilds, "到点恰好闭合，运动只更新 uniform 不重建缓冲")
			ring.set_timing(0.6, 1.0); check((await snap(viewport)).get_data() == on.get_data(), "回退恢复同一像素")
			ring.set_visual_time(2.0); ring.play_miss(); await snap(viewport)
			check(not ring._glow.visible, "Miss 关闭阵营柔光")
			ring.set_visual_time(2.06); var feedback := await snap(viewport)
			var alpha := ring.modulate.a
			check(is_equal_approx(alpha, 0.9 * (1.0 - pow(0.06 / 0.15, 2.0))), "整体透明度与判定淡出相乘")
			ring.play_miss(); ring.set_visual_time(2.06)
			check(is_equal_approx(alpha, ring.modulate.a) and (await snap(viewport)).get_data() == feedback.get_data(), "重复事件与暂停不重播淡出")
			ring.set_visual_time(2.16); check(not ring.visible, "事件年龄结束时隐藏")
			ring.set_visual_time(2.06); check((await snap(viewport)).get_data() == feedback.get_data(), "事件年龄回退恢复反馈")
			var mesh_id := ring._glow.mesh.get_instance_id(); var material_id := ring._glow.material.get_instance_id()
			ring.reset_for_pool(); check(not ring.visible and not ring._glow.visible, "回收清除主线与光晕")
			ring.prepare({"event_id": "hold", "affinity": side}); ring.set_sustain_progress(0.4)
			check(not ring._judged and ring._sustain_mode and ring._progress == 0.4 and ring._glow.mesh.get_instance_id() == mesh_id and ring._glow.material.get_instance_id() == material_id, "复用保留资源，Hold 持续进度正常")
	viewport.free()
	await test_host()
	await capture_formal()
	print("TIMING CUE: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)

func test_host() -> void:
	var scheduler := ChartScheduler.new(); root.add_child(scheduler)
	var host := NoteVisualHost.new()
	for name: String in ["LifeNoteSlot", "DeathNoteSlot", "FieldSlot", "PoolRoot"]:
		var slot := Node2D.new(); slot.name = name; host.add_child(slot)
	root.add_child(host); host.bind_scheduler(scheduler); host.preview_time_driven = true
	var note := {"event_id": "hold", "id": "hold", "unit_kind": &"hold", "affinity": 0, "start_us": 1000000, "end_us": 3000000}
	scheduler.configure({"notes": [note]}); scheduler.advance(1.0, 1.0); host.set_visual_time(1.0)
	var ring: TimingRingVisual = host._active.hold.timing_ring
	scheduler.mark_timing_confirmed("hold", GameplayTypes.JudgmentGrade.PERFECT)
	host.set_gameplay_snapshot({"active_hold_ids": ["hold"], "held_hold_ids": ["hold"]}); host.set_visual_time(1.8)
	check(ring.visible and ring._sustain_mode and not ring._judged and is_equal_approx(ring._progress, 0.4), "正式 Host 的 Hold 头命中后持续环继续显示")
	check(ring.cue_style == host.TIMING_CUE_STYLE and ring.get_canvas_layer_node().layer == 5, "宿主注入全局样式，提示位于稳定 HUD 层")
	scheduler.advance(3.0, 3.0); host._on_visual_judged("hold", GameplayTypes.JudgmentGrade.PERFECT)
	host.set_visual_time(3.16); check(not ring.visible, "Hold 最终结果后的圆环正常结束")
	host.free(); scheduler.free()

func capture_formal() -> void:
	var stage: StageDefinition = ChartProjectLoader.load_stage("res://tests/editor/fixtures/tuning/song.json").stage
	stage.visual_theme = load("res://content/stages/s08/stage_visual_theme.tres")
	stage.background = load("res://content/backgrounds/s00_grave_background.tres")
	for side: int in 2:
		var tap := NoteEvent.new(); tap.event_id = "cue_%d" % side; tap.affinity = side; tap.tick = 1440
		stage.chart.note_events.append(tap)
	var viewport := SubViewport.new(); viewport.size = Vector2i(1920, 1080); viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var preview = load("res://src/tools/chart_studio/preview_session.gd").new(); root.add_child(preview); preview.sound_enabled = false
	var loaded: bool = preview.load_preview(stage, viewport)
	check(loaded, "正式预览加载新的全局提示")
	if not loaded:
		preview.free(); viewport.free(); return
	var presentation = preview.stage_root.presentation
	check(presentation._wave_field_visual.life_wave_color == GrayboxNoteVisual.EFFECT_STYLE.life_halo and presentation._wave_field_visual.death_wave_color == GrayboxNoteVisual.EFFECT_STYLE.death_halo, "正式敲击声波读取最新生青蓝／死赭红")
	check(presentation._tuning_interference_visual.life_color == GrayboxNoteVisual.EFFECT_STYLE.life_halo and presentation._tuning_interference_visual.death_color == GrayboxNoteVisual.EFFECT_STYLE.death_halo, "持续载波与敲击声波采用同一色板")
	for at: int in [800000, 1200000, 1400000, 3800000]:
		await preview.seek_preview(at); (await snap(viewport)).save_png(OUTPUT + "/after-%d.png" % at)
	preview.free(); viewport.free()
