extends SceneTree
## 使用真实载波验证候选池、随机抽样与整批预读，不用伪造点替代几何查询。
var failures := 0
const REGION := Rect2(0, 0, 1, 1)
const TARGET := 2_000_000

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures += 1

func engine(dense := false) -> CarrierWaveEngine:
	var result := CarrierWaveEngine.new()
	var rules := GameplayRuleSet.new()
	# 数量上限用较慢波速产生足量真实交点；不改正式规则资源。
	if dense: rules.wave_speed_px_sec = 1200.0
	result.configure(rules)
	result.set_all_frequencies(7.0, 7.0, 0)
	result.set_held(GameplayTypes.Affinity.ZHU, true, 0)
	result.set_held(GameplayTypes.Affinity.XUAN, true, 120_000)
	return result

func event(id: String, count: int) -> Dictionary:
	return {"event_id": id, "count": count, "time_us": TARGET, "spawn_region_normalized": REGION}

func run() -> void:
	var full := engine(true); full.advance_to(TARGET)
	var all := full.find_constructive_intersections(TARGET, REGION, 1000)
	print("AVAILABLE POINTS ", all.size())
	check(all.size() >= 16, "真实双钟高频载波提供至少 16 个有间距的交点")
	for count in [0, 1, 2, 3, 16]:
		var points := full.find_constructive_intersections(TARGET, REGION, count, 120.0, 123)
		check(points.size() == count, "按指定数量抽取 %d 个" % count)
		check(points == full.find_constructive_intersections(TARGET, REGION, count, 120.0, 123), "相同种子重复查询一致 %d" % count)
		var valid := true
		for i in points.size():
			valid = valid and all.has(points[i]) and REGION.grow(0.00001).has_point(full.canvas_position_to_uv(points[i]))
			for j in range(i): valid = valid and points[i].distance_to(points[j]) >= 119.999
		check(valid, "所有抽样均为区域内真实交点且不重叠 %d" % count)
	var different := false
	var first := full.find_constructive_intersections(TARGET, REGION, 3, 120.0, 1)
	for seed in range(2, 10):
		different = different or first != full.find_constructive_intersections(TARGET, REGION, 3, 120.0, seed)
	check(different, "不同事件种子可以选择不同交点")
	check(full.find_constructive_intersections(TARGET, Rect2(0, 0, 0.001, 0.001), 16).is_empty(), "区域无交点时不伪造目标")

	var reference: Array[Vector2] = []
	for step in [33_333, 16_667, 6_944, 197_777]:
		var simulation := GameplaySimulation.new(); simulation.carrier_engine = engine()
		var batch := event("three", 3)
		for at in range(120000, 250000, step):
			simulation.carrier_engine.advance_to(at)
		simulation.carrier_engine.advance_to(250000)
		simulation._try_prepare_su(batch,250000)
		check(simulation._su_prepared.has("three"), "命中前准备整批 %d" % step)
		if not simulation._su_prepared.has("three"): continue
		var points: Array[Vector2] = simulation._su_prepared.three.points
		check(points.size() == 3, "预读生成完整三个目标 %d" % step)
		if reference.is_empty(): reference = points
		check(points == reference, "不同逻辑帧步的随机位置一致 %d" % step)
		simulation.carrier_engine.advance_to(TARGET)
		simulation._try_prepare_su(batch, TARGET)
		check(simulation._su_prepared.three.points == points, "后续发波不改变已经冻结的目标 %d" % step)
		var direct := GameplaySimulation.new(); direct.carrier_engine = engine(); direct.carrier_engine.advance_to(250000)
		direct._try_prepare_su(batch, 250000)
		check(direct._su_prepared.three.points == points, "直接恢复与逐段预读选择相同目标 %d" % step)

	var shortage := GameplaySimulation.new(); shortage.carrier_engine = engine(); shortage.carrier_engine.advance_to(TARGET)
	var available := shortage.carrier_engine.find_constructive_intersections(TARGET, REGION, 1000).size()
	var impossible := event("shortage", 16)
	shortage._try_prepare_su(impossible, TARGET)
	check(shortage._su_prepared.has("shortage"), "预测不足也冻结并报告，不追随之后的错误操作补点")
	shortage.compiled = CompiledChart.new(); shortage.compiled.su_manifestations.append(impossible)
	shortage.rules = GameplayRuleSet.new(); shortage.health_engine.configure(shortage.rules, true)
	shortage._process_su_manifestations(TARGET, true)
	check(shortage._su_manifestations[0].points.size() == available and shortage._su_manifestations[0].generation_issue == &"insufficient_predicted_intersections", "到时不足保留预测点并报告指定数与实际数")
	print("GHOST SELECTION TESTS: ", failures)
	quit(1 if failures else 0)
