extends SceneTree
## 双 Hold 调频接入与外部时钟的合并回归，不改变正式判定参数。
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, description: String) -> void:
	if not value:
		failures += 1
		push_error(description)
	else:
		print("PASS ", description)

func run() -> void:
	var rules := DomainFixtureFactory.rules()
	var chart := DomainFixtureFactory.tuning_only_chart()
	chart.su_manifestations.clear()
	for side in [GameplayTypes.Affinity.ZHU, GameplayTypes.Affinity.XUAN]:
		var note := NoteEvent.new()
		note.event_id = "merge_hold_%d" % side
		note.kind = GameplayTypes.NoteKind.HOLD
		note.affinity = side
		note.tick = 0 if side == GameplayTypes.Affinity.ZHU else 240
		note.duration_ticks = 960 if side == GameplayTypes.Affinity.ZHU else 480
		chart.note_events.append(note)
	var result := ChartCompiler.compile(chart, rules)
	check(result.ok, "共享校验允许 Hold 与调频联动重叠")
	var compiled: CompiledChart = result.compiled
	var simulation := GameplaySimulation.new()
	simulation.configure(compiled, rules, true)
	simulation.accept_input(SemanticInputSample.create(0, 0, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED))
	check(not simulation.note_engine.has_dual_holding_notes(), "单侧 Hold 不开放双侧调频")
	simulation.accept_input(SemanticInputSample.create(250000, 1, GameplayTypes.SemanticInputKind.DEATH_A_PRESSED))
	simulation.advance_to(600000)
	check(simulation.note_engine.has_dual_holding_notes(), "错开起手的双 Hold 在重合窗口内可调频")
	var before := Vector2(simulation.tuning_engine.life_tuning_value(), simulation.tuning_engine.death_tuning_value())
	simulation.accept_input(SemanticInputSample.create(600000, 2, GameplayTypes.SemanticInputKind.TUNING_DISPLACED, Vector2(0.1, 0.0)))
	check(simulation.tuning_engine.life_tuning_value() > before.x, "调频位移仍控制所属生钟")
	check(simulation.tuning_engine.death_tuning_value() == before.y, "单侧位移不改变另一侧频率")
	simulation.advance_to(800000)
	check(not simulation.note_engine.has_dual_holding_notes(), "较短 Hold 结束后关闭调频资格")
	before = Vector2(simulation.tuning_engine.life_tuning_value(), simulation.tuning_engine.death_tuning_value())
	simulation.accept_input(SemanticInputSample.create(800000, 3, GameplayTypes.SemanticInputKind.TUNING_DISPLACED, Vector2(0.1, 0.0)))
	check(Vector2(simulation.tuning_engine.life_tuning_value(), simulation.tuning_engine.death_tuning_value()) == before, "超出双 Hold 重合窗口的位移不生效")
	var hold_interval := {"side": 0, "start": 0, "end": 100, "type": "hold"}
	var tuning_interval := {"side": 0, "start": 0, "end": 100, "type": "tuning"}
	check(not ChartValidator.input_intervals_conflict(hold_interval, tuning_interval), "草稿查询遵循新的 Hold/调频例外")
	check(not ChartValidator.input_intervals_conflict(tuning_interval, hold_interval), "交换区间顺序不改变共享校验结果")
	var clock := SongClock.new()
	root.add_child(clock)
	clock.configure(null, 2.0)
	var external := clock.publish_external_time(4.2)
	check(external.judge_time_sec == 4.2 and external.visual_time_sec == 4.2, "外部帧尾沿用 Transport 采样而不读回内部时钟")
	clock.queue_free()
	await process_frame
	print("DEVELOP MERGE TESTS: ", failures)
	quit(1 if failures else 0)
