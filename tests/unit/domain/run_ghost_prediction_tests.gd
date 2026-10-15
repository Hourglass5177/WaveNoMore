extends SceneTree
## 真实 v2 双 Hold、多节点调频；预测位置与操作成绩分别验证。
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func simulate(compiled: CompiledChart, rules: GameplayRuleSet, step: int, tune: bool, tuning_scale: float = 1.0, end_us: int = 8000000) -> GameplaySimulation:
	var sim := GameplaySimulation.new(); sim.configure(compiled,rules,true)
	var inputs := StudioPreviewInputs.build(compiled,rules)
	var cursor := 0; var time := -2000000
	while time < end_us:
		time = mini(time+step,end_us)
		while cursor < inputs.size() and inputs[cursor].timestamp_us <= time:
			var sample: SemanticInputSample = inputs[cursor]
			if sample.is_tuning() and tuning_scale != 1.0:
				sample = SemanticInputSample.create(sample.timestamp_us, sample.sequence, sample.kind, sample.tune_vector * tuning_scale)
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
	# 相同谱面与真实语义输入：第一枚Ghost处的较差侧落后约16.7%，属于Pass。
	var pass_results: Array = []
	for step: int in [8333, 16667, 33333, 197777]:
		var relaxed := simulate(compiled, rules, step, true, 0.75, 4500000)
		var current: Array = relaxed.snapshot().su_manifestations
		check(current.size() == 1 and current[0].grade == GameplayTypes.JudgmentGrade.PASS, "真实输入的Pass档Ghost保持实际评级")
		check(current[0].hit_count == 2 and current[0].miss_count == 0 and current[0].success, "Pass误差可击碎整批Ghost")
		check(relaxed.damages.is_empty(), "Pass档Ghost不扣血")
		if pass_results.is_empty(): pass_results = current
		else: check(current == pass_results, "Pass档Ghost跨帧步结果一致")
	# Ghost达到Pass不破FC，也不能把非Perfect击破算作AP。
	var perfect_record := JudgmentRecord.new(); perfect_record.grade = GameplayTypes.JudgmentGrade.PERFECT
	var summary := ResultEvaluator.evaluate([perfect_record], [], perfect.score_engine, perfect.health_engine, 1, true, pass_results, 2)
	check(summary.full_combo and summary.grants_base_pet, "Pass击破保留FC与基础奖励资格")
	check(not summary.all_perfect and not summary.grants_advanced_pet, "Pass击破不计入AP与进阶奖励")
	var outside := simulate(compiled, rules, 16667, true, 0.69, 4500000)
	check(outside.snapshot().su_manifestations[0].miss_count == 2, "超出Pass误差仍按枚漏击")
	check(outside.damages.size() == 2 and outside.damages.all(func(d: DamageRecord): return d.base_damage == rules.ghost_miss_damage), "Pass边界外保留原漏击伤害")
	var results: Array = perfect.snapshot().su_manifestations
	check(not results.is_empty(),"正式调频谱产生 Ghost 结果")
	for result: Dictionary in results:
		check(result.success,"正确调频通过关联操作评价："+str(result.event_id))
		print("PREDICTED ",result.event_id," ",result.points.size(),"/",result.count)
		check(result.points.size()>0 and result.points.size()<=int(result.count),"未来理想改频生成合法目标："+str(result.event_id))
		check(str(result.generation_issue).is_empty() == (result.points.size()==int(result.count)),"足量与不足量均如实报告")
		check(perfect._su_prepared[str(result.event_id)].prepared_at_us < int(result.time_us),"目标在结算之前固定")
		check(int(perfect._su_prepared[str(result.event_id)].visible_from_us) == int(result.time_us) - roundi((rules.approach_duration_sec + rules.ghost_preview_extra_sec) * 1000000.0), "Ghost 提前量接入可见时间")
		check(perfect._su_prepared[str(result.event_id)].points == missed._su_prepared[str(result.event_id)].points,"预测之后错误调频不移动目标")
	check(missed.snapshot().su_manifestations[0].miss_count==2,"保持双 Hold 但不调频时该批两枚 Ghost 漏击")
	check(missed.damages.any(func(d: DamageRecord): return d.source_id.contains(":ghost:") and d.base_damage==rules.ghost_miss_damage),"Ghost 按枚独立伤害")
	check(missed.damages.all(func(d: DamageRecord): return d.source_id.contains(":ghost:")),"成功持有时滑条失败不附加 Hold 或 Tuning 伤害")
	var old_rules := rules.duplicate() as GameplayRuleSet
	old_rules.ghost_preview_extra_sec = 0.0
	var old_timing := simulate(compiled, old_rules, 16667, true)
	check(ChartCompiler.rules_hash(old_rules) == ChartCompiler.rules_hash(rules), "视觉提前量不改变 Replay 规则哈希")
	check(ReplayRunner.result_digest(old_timing.judgments, old_timing.strays, old_timing.result_summary()) == ReplayRunner.result_digest(perfect.judgments, perfect.strays, perfect.result_summary()), "视觉提前量不改变 Replay 成绩摘要")
	for i in results.size():
		var old: Dictionary = old_timing.snapshot().su_manifestations[i]
		check(old.time_us == results[i].time_us and old.grade == results[i].grade and old.hit_count == results[i].hit_count, "提前预告不改变结算时刻或评级")
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
