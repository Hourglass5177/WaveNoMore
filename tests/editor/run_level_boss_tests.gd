extends SceneTree
var failures := 0
var checks := 0

func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: " + message)

func _run() -> void:
	var stage := load("res://content/stages/s02/stage_definition.tres").duplicate(true) as StageDefinition
	stage.resolve_dependencies_sync()
	stage.chart = SongChart.new(); stage.chart.chart_id = "boss_test"; stage.chart.end_tick = 19200
	var tempo := TempoEvent.new(); tempo.bpm = 120; stage.chart.tempo_events.append(tempo)
	stage.chart.meter_events.append(MeterEvent.new())
	var note := NoteEvent.new(); note.event_id = "boss_tap"; note.tick = 11520; note.boss = true
	stage.chart.note_events.append(note)
	var hold := NoteEvent.new(); hold.event_id = "boss_hold"; hold.tick = 12000; hold.boss = true
	hold.kind = GameplayTypes.NoteKind.HOLD; hold.duration_ticks = 960; hold.affinity = GameplayTypes.Affinity.XUAN
	stage.chart.note_events.append(hold)
	stage.song = SongDefinition.new(); stage.song.first_beat_offset_sec = 0.35; stage.song.fallback_duration_sec = 25
	var level := LevelFormat.new_level()
	var actor := LevelFormat.object("actor"); actor.fields.position = [650, 320]
	level.show.objects = [actor]
	var motion := LevelFormat.track(actor.id, "position"); motion.keys = [LevelFormat.key(0, [650, 320]), LevelFormat.key(20000000, [1050, 720])]
	level.show.tracks = [motion]
	level.show.bindings = [{"id": "tap_binding", "object_id": actor.id, "difficulty": "normal", "note_ids": [note.event_id], "action": "attack", "release_sec": 0.2}, {"id": "hold_binding", "object_id": actor.id, "difficulty": "normal", "note_ids": [hold.event_id], "return_us": 2000000}]
	stage.stage_show = StageShow.new(); stage.stage_show.level_data = level.show
	stage.set_meta("level", level)
	var viewport := SubViewport.new(); viewport.size = Vector2i(1920,1080); root.add_child(viewport)
	var stage_root = load("res://scenes/stage/stage_root.tscn").instantiate()
	stage_root.auto_start_initial_stage = false; stage_root.initial_stage = null; viewport.add_child(stage_root)
	stage_root.set_process(false)
	stage_root.audio_feedback.preview_muted=true;stage_root.audio_feedback.preview_strikes_muted=true
	stage_root.stage_session.external_preview = true; stage_root.stage_session.set_process(false); stage_root.song_clock.set_process(false)
	check(stage_root.load_stage(stage, false), "BOSS 关卡装配正式 StageRoot")
	var emissions: Dictionary = stage_root.chart_scheduler.boss_emissions
	check(emissions.size() == 2, "Tap 与 Hold 均建立发射段")
	if emissions.size() != 2: viewport.queue_free(); await process_frame; quit(1); return
	var path: Dictionary = emissions[note.event_id]
	check(path.release_us == 9150000 and path.entry_us == 9750000, "拍点 12 秒保留完整 2.25 秒常规进场")
	var actor_state := LevelShowSampler.object_state(level.show, actor, "song", 9500000, "normal")
	check(path.controls[0].is_equal_approx(LevelFormat.vec(actor_state.position)), "发射锚点取出手时刻并包含首拍偏移")
	var end := BossEmissionPath.sample(path, 600000)
	var rules := stage.rule_set
	var profile := NoteApproachPath.build_profile(rules.life_note_spawn, rules.life_note_cue, rules.life_wave_origin, rules.note_curve_outer_bend_px, rules.note_curve_center_handle_px)
	var normal_velocity := NoteApproachPath.tangent_at_ratio(profile, 0) * NoteApproachPath.length(profile) / rules.approach_duration_sec
	check(end.position.is_equal_approx(rules.life_note_spawn) and end.velocity.is_equal_approx(normal_velocity), "入轨端位置和速度连续")
	check(stage_root.stage_session.compiled_chart.notes[0].id == note.event_id, "提前生成排序不改变领域编译谱")
	var scheduler: ChartScheduler = stage_root.chart_scheduler
	scheduler.advance(8.3, 8.3)
	check(scheduler.get_active_events().size() == 1 and scheduler.get_active_events()[0].data.id == hold.event_id, "长回转的后拍 Hold 可以先生成")
	scheduler.advance(9.16, 9.16)
	check(scheduler.get_active_events().size() == 2, "Tap 到发射时刻只生成一次")
	var host := stage_root.presentation.get_node(stage_root.presentation.note_visual_host_path) as NoteVisualHost
	var instance_id: int = host._active[note.event_id].node.get_instance_id()
	host.set_visual_time(9.5)
	check(host._active[note.event_id].node.position.is_equal_approx(BossEmissionPath.sample(path, 350000).position), "正式音符沿提前段移动")
	scheduler.advance(9.75, 9.75); host.set_visual_time(9.75)
	check(host._active[note.event_id].node.get_instance_id() == instance_id, "入轨保留同一音符实例")
	check(host._active[note.event_id].node.position.is_equal_approx(rules.life_note_spawn), "Host 入轨位置吻合常规入口")
	var original_start: Vector2 = path.controls[0]
	stage_root.level_show_player.seek("song", 19000000)
	check(path.controls[0].is_equal_approx(original_start), "BOSS 后续移动不拖走已发射音符")
	# 生命周期在正式 StageRoot 检查，演出区段不向谱面写偏移，也不重复结算。
	level.intro_us = 1000000; level.outro_us = 250000; stage.set_meta("level", level)
	stage_root.stage_session.external_preview = false
	check(stage_root.load_stage(stage, true), "含片头片尾的关卡能够启动")
	var run_before: int = stage_root.stage_session.run_id
	stage_root._process(0.5)
	check(stage_root.stage_session.state == GameplayTypes.StageState.READY and stage_root.stage_session.run_id == run_before, "片头期间尚未开放歌曲判定")
	stage_root._process(0.5)
	check(stage_root.stage_session.run_id == run_before + 1 and is_equal_approx(stage.song.first_beat_offset_sec, 0.35), "片头结束只启动一次且不改首拍偏移")
	var results: Array = []
	stage_root.stage_finished.connect(func(result): results.append(result))
	stage_root.stage_session._complete_result(true)
	check(results.is_empty() and stage_root.stage_session.state == GameplayTypes.StageState.RESULT, "成绩先固定，再进入曲后演出")
	stage_root._process(0.25); stage_root._process(0.25)
	check(results.size() == 1, "片尾结束只发布一次最终结算")
	viewport.queue_free(); await process_frame
	print("LEVEL BOSS TESTS: %d (%d checks)" % [failures, checks]); quit(1 if failures else 0)
