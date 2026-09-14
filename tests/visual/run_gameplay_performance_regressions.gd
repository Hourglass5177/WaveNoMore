extends SceneTree
const FullScan = preload('res://tests/visual/full_scan_tuning_reference.gd')
var failures := 0
func _initialize(): run.call_deferred()
func check(ok: bool, text: String):
	print(('PASS ' if ok else 'FAIL ') + text)
	if not ok: failures += 1
func run():
	var scheduler := ChartScheduler.new(); root.add_child(scheduler)
	scheduler._active["probe"] = {"kind":ChartScheduler.KIND_NOTE,"data":{"unit_kind":&"tap"},"resolved_us":-1}
	var event_times: Array[float] = []
	scheduler.visual_timing_confirmed.connect(func(_id, _grade): event_times.append(scheduler.visual_time_sec))
	scheduler.visual_judged.connect(func(_id, _grade): event_times.append(scheduler.visual_time_sec))
	scheduler.visual_time_sec = 0.48
	scheduler.mark_timing_confirmed("probe",0,0.503)
	scheduler.mark_judged("probe",0,0.727194)
	check(event_times == [0.503,0.727194] and scheduler.visual_time_sec == 0.48, '合批反馈使用精确事件时间，随后恢复帧时钟')
	check(scheduler._active.probe.resolved_us == 727194, '生命周期记录真实接触时刻')
	scheduler.free()
	var loaded := ChartProjectLoader.load_stage(ProjectSettings.globalize_path('res://../Charts/charts/test/song.json'))
	var rules: GameplayRuleSet = loaded.stage.rule_set
	var compiled: CompiledChart = ChartCompiler.compile(loaded.stage.chart, rules).compiled
	var inputs := StudioPreviewInputs.build(compiled, rules)
	var digest: Dictionary = {}
	for steps: PackedInt64Array in [PackedInt64Array([33333]),PackedInt64Array([16667]),PackedInt64Array([8333]),PackedInt64Array([7000,31000,11000,49000])]:
		var fast := GameplaySimulation.new(); var reference := GameplaySimulation.new()
		reference.tuning_engine = FullScan.new()
		fast.configure(compiled,rules,true); reference.configure(compiled,rules,true)
		var cursor := 0; var time := 0; var frame := 0; var equal := true
		while time <= compiled.end_time_us + 1000000:
			time += steps[frame % steps.size()]; frame += 1
			while cursor < inputs.size() and inputs[cursor].timestamp_us <= time:
				var at := inputs[cursor].timestamp_us
				for sim in [fast,reference]: sim.advance_to(at,false)
				while cursor < inputs.size() and inputs[cursor].timestamp_us == at:
					for sim in [fast,reference]: sim.accept_input(inputs[cursor])
					cursor += 1
				for sim in [fast,reference]: sim.advance_to(at,true)
			for sim in [fast,reference]: sim.advance_to(time,true)
			if frame % 19 == 0:
				equal = equal and fast.snapshot() == reference.snapshot()
		var snap := fast.snapshot()
		var result := fast.result_summary()
		check(equal, '活动索引与原全谱查询逐段一致 '+str(steps))
		check(snap.fc == result.full_combo and snap.ap == result.all_perfect and snap.miss_count == result.miss_count, '增量成绩与完整历史结算一致')
		var state := {'score':snap.score,'frequency':Vector2(snap.life_frequency_hz,snap.death_frequency_hz),'carrier':fast.carrier_engine.emission_count(),'ghost':snap.su_manifestations,'judgments':[]}
		for record: JudgmentRecord in fast.judgments: state.judgments.append([record.unit_id,record.grade,record.finalized_at_us])
		if digest.is_empty(): digest = state
		else: check(state == digest, '帧率与不规则步长不改变判定、载波与 Ghost')
	quit(failures)
