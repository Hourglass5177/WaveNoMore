extends SceneTree
## 正式输入事件、中心反馈和持续环方向共同回归，不移动声波的物理接触时间。
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func run() -> void:
	var viewport := SubViewport.new(); viewport.size = Vector2i(500, 500)
	viewport.transparent_bg = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var ring := TimingRingVisual.new(); viewport.add_child(ring)
	for side in 2:
		ring.prepare({"affinity":side}); ring.position = Vector2(250,250); ring.set_sustain_progress(0.25)
		await process_frame; await RenderingServer.frame_post_draw
		var picture := viewport.get_texture().get_image()
		var bright := picture.get_pixel(184 if side == 0 else 316,250)
		var dim := picture.get_pixel(316 if side == 0 else 184,250)
		check(bright.a > dim.a, "持续环：右生逆时针、左死顺时针 %d" % side)
		check(ring._glow.material.get_shader_parameter("sweep_direction") == (-1.0 if side == 0 else 1.0), "柔光与主线方向一致")
		DirAccess.make_dir_recursive_absolute("res://builds/feedback-review")
		picture.save_png("res://builds/feedback-review/hold-ring-%d.png" % side)
		ring.prepare({"affinity":side}); ring.set_timing(0.75,1.0)
		check(ring._sweep_direction() == 1.0, "对象池复用恢复接近环方向")
	ring.free(); viewport.free()
	# 待 Autoload 就绪再加载会话，和正式场景装配顺序一致。
	var gate = load("res://src/presentation/vfx/twin_gate_cue_visual.gd").new(); root.add_child(gate)
	var session = load("res://src/runtime/session/stage_session.gd").new(); root.add_child(session); gate.bind(null,session)
	for kind: int in [GameplayTypes.NoteKind.TAP,GameplayTypes.NoteKind.HOLD]:
		for error_us: int in [-80000,0,110000]:
			gate.clear()
			var chart := DomainFixtureFactory.base_chart("feedback",3840)
			var note := NoteEvent.new(); note.event_id = "note"; note.tick = 960; note.kind = kind
			note.duration_ticks = 960 if kind == GameplayTypes.NoteKind.HOLD else 0; chart.note_events.append(note)
			var rules := GameplayRuleSet.new(); var sim := GameplaySimulation.new()
			sim.configure(ChartCompiler.compile(chart,rules).compiled,rules,true)
			var input_us := 1000000 + error_us
			sim.accept_input(SemanticInputSample.create(input_us,1,GameplayTypes.SemanticInputKind.LIFE_A_PRESSED))
			var wave: Dictionary = sim.drain_wave_launches()[0]
			session.wave_launched.emit(wave)
			check(gate._contact_events.size() == 1 and gate._grade_events.size() == 1, "Tap／Hold 头判立即产生中心反馈")
			check(is_equal_approx(gate._contact_events[0].start_sec,float(input_us)/1000000), "反馈使用准确接受时间")
			check(wave.contact_us > input_us and sim.drain_wave_contacts().is_empty(), "此时声波尚未接触，物理接触未提前")
			session.wave_launched.emit(wave)
			sim.advance_to(int(wave.contact_us)); session.wave_contacted.emit({"affinity":0,"contact_us":wave.contact_us})
			check(gate._contact_events.size()==1, "重复发波与后续接触不重复播放")
			var record := JudgmentRecord.new(); record.unit_kind = &"hold" if kind == GameplayTypes.NoteKind.HOLD else &"tap"; record.grade = 0
			session.judgment_presented.emit(record)
			check(gate._grade_events.size()==1,"成功最终判定不再延迟重播中心印记")
		gate.clear(); session.wave_launched.emit({"affinity":0,"valid":false,"launch_us":0})
		check(gate._contact_events.is_empty(),"空按不产生正确命中反馈")
	gate.free(); session.free()
	print("反馈回归：",checks," 项，失败 ",failures); quit(1 if failures else 0)
