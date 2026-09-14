extends SceneTree
## 真实 v2 双 Hold、多节点调频；预测位置与操作成绩分别验证。
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func simulate(compiled: CompiledChart, rules: GameplayRuleSet, step: int, tune: bool) -> GameplaySimulation:
	var sim := GameplaySimulation.new(); sim.configure(compiled,rules,true)
	var inputs := StudioPreviewInputs.build(compiled,rules)
	var cursor := 0; var time := -2000000
	while time < 8000000:
		time = mini(time+step,8000000)
		while cursor < inputs.size() and inputs[cursor].timestamp_us <= time:
			var sample: SemanticInputSample = inputs[cursor]
			if tune or sample.kind != GameplayTypes.SemanticInputKind.TUNING_DISPLACED: sim.accept_input(sample)
			cursor += 1
		sim.advance_to(time)
	return sim
func run() -> void:
	var doc := StudioDocument.new(); StudioProjectIO.open_project("res://tests/editor/fixtures/tuning/song.json",doc)
	var rules := GameplayRuleSet.new()
	var chart := ChartPathAdapter.project(doc.chart(),rules)
	var compiled: CompiledChart = ChartCompiler.compile(chart,rules).compiled
	check(compiled.su_manifestations[0].tuning_ids.size()==2,"v2 Ghost 双侧路径关联传入编译结果")
	var perfect := simulate(compiled,rules,16667,true)
	var missed := simulate(compiled,rules,33333,false)
	var results: Array = perfect.snapshot().su_manifestations
	check(not results.is_empty(),"正式调频谱产生 Ghost 结果")
	for result: Dictionary in results:
		check(result.success,"正确调频通过关联操作评价："+str(result.event_id))
		print("PREDICTED ",result.event_id," ",result.points.size(),"/",result.count)
		check(result.points.size()>0 and result.points.size()<=int(result.count),"未来理想改频生成合法目标："+str(result.event_id))
		check(str(result.generation_issue).is_empty() == (result.points.size()==int(result.count)),"足量与不足量均如实报告")
		check(perfect._su_prepared[str(result.event_id)].prepared_at_us < int(result.time_us),"目标在结算之前固定")
		check(perfect._su_prepared[str(result.event_id)].points == missed._su_prepared[str(result.event_id)].points,"预测之后错误调频不移动目标")
	check(missed.snapshot().su_manifestations[0].miss_count==2,"保持双 Hold 但不调频时该批两枚 Ghost 漏击")
	check(missed.damages.any(func(d: DamageRecord): return d.source_id.contains(":ghost:") and d.base_damage==10),"Ghost 按枚独立伤害")
	check(missed.damages.all(func(d: DamageRecord): return d.source_id.contains(":ghost:")),"成功持有时滑条失败不附加 Hold 或 Tuning 伤害")
	for step: int in [8333,33333,197777]:
		var other := simulate(compiled,rules,step,true)
		check(other.snapshot().su_manifestations==results,"预测与判定不随帧步改变 %d"%step)
	var source := CarrierWaveEngine.new(); source.configure(rules)
	source.set_held(0,true,0); source.set_held(1,true,100000); source.advance_to(2000000)
	var before := source.history_copy(); var snapshot := source.snapshot()
	var forecast := GhostWaveForecast.new(); forecast.configure(compiled,rules)
	var future := forecast.predict(source,2000000,5000000)
	check(source.history_copy()==before and source.snapshot()==snapshot,"预测不污染真实波、相位或发射队列")
	check(future.history_copy().any(func(w: Dictionary): return int(w.launch_us)>3500000 and absf(float(w.frequency_hz)-rules.tuning_base_frequency_hz)>0.1),"未来波确实跟随调频改变频率")
	for wave: Dictionary in before:
		if future.history_copy().any(func(w: Dictionary): return w.wave_id==wave.wave_id):
			var retained: Array = future.history_copy().filter(func(w: Dictionary): return w.wave_id==wave.wave_id)
			check(retained[0].launch_us==wave.launch_us and retained[0].speed_px_sec==wave.speed_px_sec,"预测保留已经发出波的真实时刻与波速")
	# 生成问题与玩家失败分开：故意使区域无交点，正确操作仍不能因此受伤。
	var impossible: CompiledChart = ChartCompiler.compile(chart,rules).compiled
	for event: Dictionary in impossible.su_manifestations: event.spawn_region_normalized=Rect2(0,0,0.000001,0.000001)
	var no_points := simulate(impossible,rules,16667,true)
	check(no_points.damages.is_empty() and no_points.snapshot().su_manifestations[0].success,"预测无合法位置不会伪装成玩家漏击扣血")
	check(not str(no_points.snapshot().su_manifestations[0].generation_issue).is_empty(),"无合法位置仍报告生成问题")
	print("GHOST PREDICTION: %d checks, %d failures"%[checks,failures]); quit(1 if failures else 0)
