extends SceneTree
## 用优化前查询逐点对照，覆盖完整候选池与预读早停；同时记录查询本身的耗时。
const REFERENCE = preload("res://tests/unit/domain/ghost_query_reference.gd")
var failures := 0

class CountingCarrier extends CarrierWaveEngine:
	var queries := 0
	func find_constructive_intersections(time_us: int, region: Rect2, count: int, spacing: float = 120.0, seed_value: int = 0, freeze: bool = false) -> Array[Vector2]:
		queries += 1
		return super(time_us, region, count, spacing, seed_value, freeze)

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", message)

func make_engine(speed: float, frequency: float) -> CountingCarrier:
	var engine := CountingCarrier.new()
	var rules := GameplayRuleSet.new()
	rules.wave_speed_px_sec = speed
	engine.configure(rules)
	engine.set_all_frequencies(frequency, frequency * 0.83, 0)
	engine.set_held(GameplayTypes.Affinity.ZHU, true, 0)
	engine.set_held(GameplayTypes.Affinity.XUAN, true, 120000)
	return engine

func run() -> void:
	var total := 0
	var old_us := 0
	var new_us := 0
	for speed: float in [600.0, 1200.0, 2400.0]:
		for frequency: float in [3.0, 15.0]:
			var engine := make_engine(speed, frequency)
			engine.advance_to(8000000)
			for at: int in [500000, 1700000, 2400000, 7000000, 9000000]:
				for region: Rect2 in [Rect2(0, 0, 1, 1), Rect2(0.2, 0.3, 0.3, 0.4), Rect2(0, 0, 0.01, 0.01)]:
					for count: int in [1, 3, 16, 1000]:
						for freeze: bool in [false, true]:
							var seed_value: int = total * 17
							var began := Time.get_ticks_usec()
							var expected: Array[Vector2] = REFERENCE.query(engine, at, region, count, 120.0, seed_value, freeze)
							old_us += Time.get_ticks_usec() - began
							began = Time.get_ticks_usec()
							var actual := engine.find_constructive_intersections(at, region, count, 120.0, seed_value, freeze)
							new_us += Time.get_ticks_usec() - began
							total += 1
							if expected != actual:
								check(false, "候选不一致 speed=%s hz=%s time=%s region=%s count=%s freeze=%s" % [speed, frequency, at, region, count, freeze])
	check(failures == 0, "%d 组查询与旧算法逐点、顺序完全一致" % total)
	# 固定随机用例补充同时发射、非默认坐标、改频、松开与不同间距。
	var random := RandomNumberGenerator.new()
	random.seed = 20260909
	for sample_index: int in 240:
		var rules := GameplayRuleSet.new()
		rules.wave_speed_px_sec = random.randf_range(300.0, 3000.0)
		rules.wave_canvas_size = Vector2(1280, 720) if sample_index % 2 else Vector2(1920, 1080)
		rules.life_wave_origin = Vector2(random.randf_range(0, 900), random.randf_range(0, 500))
		rules.death_wave_origin = Vector2(random.randf_range(900, 1920), random.randf_range(500, 1080))
		var engine := CarrierWaveEngine.new()
		engine.configure(rules)
		engine.set_all_frequencies(15.0, 15.0, 0)
		engine.set_held(GameplayTypes.Affinity.ZHU, true, 0)
		engine.set_held(GameplayTypes.Affinity.XUAN, true, 0)
		engine.set_all_frequencies(random.randf_range(1, 25), random.randf_range(1, 25), 1000000)
		engine.set_held(GameplayTypes.Affinity.XUAN, false, 2500000)
		engine.set_held(GameplayTypes.Affinity.XUAN, true, 3000000)
		engine.advance_to(10000000)
		var at: int = random.randi_range(-1, 11000000)
		var region := Rect2(random.randf_range(-0.1, 0.4), random.randf_range(-0.1, 0.4), 0.6, 0.6)
		var spacing: float = [0.0, 1.0, 60.0, 120.0, 300.0][sample_index % 5]
		var count: int = [1, 3, 16, 1000][sample_index % 4]
		var freeze: bool = sample_index % 2 == 0
		var expected := REFERENCE.query(engine, at, region, count, spacing, sample_index, freeze)
		var actual := engine.find_constructive_intersections(at, region, count, spacing, sample_index, freeze)
		if expected != actual or engine.visible_wavefronts(at) != REFERENCE.visible_wavefronts(engine, at):
			check(false, "混合输入查询不一致 sample=%d" % sample_index)
	check(failures == 0, "240 组混合输入、波源坐标和间距对照一致")
	var dense := make_engine(600.0, 60.0)
	dense.advance_to(8000000)
	var dense_old_us := 0
	var dense_new_us := 0
	for spacing: float in [20.0, 60.0, 120.0]:
		for count: int in [16, 1000]:
			for freeze: bool in [false, true]:
				var began := Time.get_ticks_usec()
				var expected := REFERENCE.query(dense, 7000000, Rect2(0, 0, 1, 1), count, spacing, 123, freeze)
				dense_old_us += Time.get_ticks_usec() - began
				began = Time.get_ticks_usec()
				var actual := dense.find_constructive_intersections(7000000, Rect2(0, 0, 1, 1), count, spacing, 123, freeze)
				dense_new_us += Time.get_ticks_usec() - began
				if expected != actual: check(false, "密集候选分格后坐标或顺序不一致")
	check(failures == 0, "12 组高密度波前与大候选池对照一致")
	var carrier := make_engine(2400.0, 3.0)
	var simulation := GameplaySimulation.new()
	simulation.carrier_engine = carrier
	var event := {"event_id": "cached", "time_us": 2000000, "count": 16, "spawn_region_normalized": Rect2(0, 0, 1, 1)}
	carrier.advance_to(250000)
	for i: int in 100: simulation._try_prepare_su(event, 250000 + i)
	check(carrier.queries == 1, "没有新波的 100 次预读仅查询一次")
	carrier.advance_to(500000)
	simulation._try_prepare_su(event, 500000)
	check(carrier.queries == 2, "新载波使候选缓存失效")
	carrier.advance_to(2000000)
	simulation._try_prepare_su(event, 1999999)
	var queries_before := carrier.queries
	simulation._try_prepare_su(event, 2000000)
	check(carrier.queries == queries_before, "不足量到期复用同批交点，不再次求交")
	check(simulation._su_prepared.has("cached"), "到期仍保留实际可用点")
	simulation.clear_su_targets()
	check(simulation._su_candidate_cache.is_empty(), "清场释放候选缓存")
	var report := {"cases": total, "additional_cases": 252, "legacy_ms": old_us / 1000.0, "optimized_ms": new_us / 1000.0,
		"dense_legacy_ms": dense_old_us / 1000.0, "dense_optimized_ms": dense_new_us / 1000.0, "failures": failures}
	DirAccess.make_dir_recursive_absolute("res://builds/visual-review/note-glow")
	FileAccess.open("res://builds/visual-review/note-glow/ghost-query-performance.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("GHOST QUERY PERFORMANCE ", JSON.stringify(report))
	print("GHOST QUERY TESTS: ", failures)
	quit(1 if failures else 0)
