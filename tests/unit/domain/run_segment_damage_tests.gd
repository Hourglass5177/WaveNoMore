extends SceneTree
## 分段伤害的音乐边界、身体抵达、分帧一致性及独立伤害来源。
var checks := 0
var failures := 0
const K := GameplayTypes.SemanticInputKind
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func make_sim(hold := true, variable_bpm := false, damage := 2) -> GameplaySimulation:
	var chart := DomainFixtureFactory.base_chart("body_damage", 3840)
	var note := NoteEvent.new(); note.event_id = "note"; note.tick = 960
	note.kind = GameplayTypes.NoteKind.HOLD if hold else GameplayTypes.NoteKind.TAP
	note.duration_ticks = 960 if hold else 0
	chart.note_events.append(note)
	if variable_bpm:
		var tempo := TempoEvent.new(); tempo.tick = 1440; tempo.bpm = 240.0; chart.tempo_events.append(tempo)
	var rules := GameplayRuleSet.new(); rules.hold_segment_damage = damage
	var sim := GameplaySimulation.new(); sim.configure(ChartCompiler.compile(chart, rules).compiled, rules, true)
	return sim
func press(sim: GameplaySimulation, time: int, kind: int = K.LIFE_A_PRESSED) -> void:
	sim.accept_input(SemanticInputSample.create(time, time, kind))
func run() -> void:
	var sim := make_sim()
	var first := 1000000 + sim.wave_engine.post_cue_travel_us(0) + 125000
	sim.advance_to(first - 1)
	check(sim.damages.is_empty(), "头判漏击及头部抵达均不额外扣血")
	sim.advance_to(first, false); check(sim.damages.is_empty(), "非包含边界不提前扣血")
	sim.advance_to(first); check(sim.damages.size() == 1 and sim.damages[0].base_damage == 2, "四分之一拍身体抵达才扣第一段")
	sim.force_finish(); check(sim.damages.size() == 8 and sim.health_engine.soul_fire == 84, "两拍漏 Hold 共八段、十六点")
	sim.force_finish(); check(sim.damages.size() == 8, "重复推进不重复伤害")
	sim.reset(); sim.force_finish(); check(sim.damages.size() == 8, "重试重建分段队列")
	var slow := make_sim(true, true); slow.force_finish()
	check(slow.damages.size() == 8 and slow.health_engine.soul_fire == 84, "变 BPM 不改变拍长总伤害")
	check(slow.damages[4].timestamp_us - slow.damages[3].timestamp_us == 62500, "变速后的分段间隔随 TempoMap 缩短")
	var tap := make_sim(false); tap.force_finish()
	check(tap.damages.size() == 1 and tap.damages[0].base_damage == 20, "Tap 独立二十点")
	var success := make_sim(); press(success, 1000000); success.force_finish()
	check(success.damages.is_empty(), "成功 Hold 不受伤")
	var brief := make_sim(); press(brief, 1000000); press(brief, 1200000, K.LIFE_A_RELEASED); press(brief, 1250000); brief.force_finish()
	check(brief.damages.is_empty(), "宽限内续接不损失身体")
	var traces: Array = []
	for steps: Array in [[33333], [16667], [8333], [7100, 43000, 1200, 79000]]:
		var broken := make_sim(); press(broken, 1000000); press(broken, 1250000, K.LIFE_A_RELEASED)
		var time := 1250000; var index := 0
		while time < broken.last_damage_time_us():
			time = mini(time + int(steps[index % steps.size()]), broken.last_damage_time_us()); index += 1; broken.advance_to(time)
		check(broken.health_engine.soul_fire == 88 and broken.damages.size() == 6, "断持仅剩余一拍半身体扣血")
		check(broken.damages[0].timestamp_us > 1350001 + broken.wave_engine.post_cue_travel_us(0), "断持伤害等待离圈及第一段身体抵达")
		traces.append(broken.damages.map(func(d: DamageRecord) -> Dictionary: return d.to_dictionary()))
	check(traces.all(func(trace: Array) -> bool: return trace == traces[0]), "30/60/120 与不规则帧间隔伤害完全一致")
	var paused := make_sim(); paused.advance_to(first - 1); var rearm := paused.begin_pause_rearm()
	paused.advance_to(first); check(paused.damages.is_empty(), "暂停不结算身体")
	paused.apply_resume_rearm(rearm); paused.advance_to(first); check(paused.damages.size() == 1, "恢复后同刻只结算一次")
	var ghost := make_sim(false)
	ghost.compiled.su_manifestations.append({"event_id":"ghost", "time_us":500000, "count":3, "spawn_region_normalized":Rect2(0,0,1,1)})
	ghost.advance_to(500000)
	check(ghost.damages.size() == 3 and ghost.health_engine.soul_fire == 70, "无载波时每枚 Ghost 独立十点")
	ghost.advance_to(500000); check(ghost.damages.size() == 3, "Ghost 不重复结算")
	var health := HealthEngine.new(); health.configure(GameplayRuleSet.new())
	var tuning := JudgmentRecord.new(); tuning.unit_kind = &"tuning"
	health.apply_judgment(tuning); check(health.soul_fire == 100, "Tuning 评分失败不直接伤害")
	print("SEGMENT DAMAGE: %d checks, %d failures" % [checks, failures]); quit(1 if failures else 0)
