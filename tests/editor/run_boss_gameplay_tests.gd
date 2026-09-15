extends SceneTree
var failures:=0
const K=GameplayTypes.SemanticInputKind
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1;printerr(label)
func make_sim() -> GameplaySimulation:
	var chart:=DomainFixtureFactory.base_chart("boss_damage",3840)
	var note:=NoteEvent.new();note.event_id="hold";note.tick=960;note.kind=GameplayTypes.NoteKind.HOLD;note.duration_ticks=1200;chart.note_events.append(note)
	var rules:=GameplayRuleSet.new()
	var sim:=GameplaySimulation.new();sim.configure(ChartCompiler.compile(chart,rules).compiled,rules,true)
	sim.boss_battle.configure([{"id":"boss","name":"BOSS","note_ids":["hold"],"health_ratio":0.8,"phase_duration_us":300000}],sim.compiled,rules)
	return sim
func _initialize() -> void:
	var traces: Array=[]
	for frame in [8333,33333,900000]:
		var sim:=make_sim();sim.accept_input(SemanticInputSample.create(1000000,0,K.LIFE_A_PRESSED))
		var at:=1000000
		while at<3000000:at=mini(3000000,at+frame);sim.advance_to(at)
		check(sim.boss_battle.states.boss.maximum==3600,"Hold 头尾和两拍半理论伤害")
		check(sim.boss_battle.states.boss.hp==0,"成功持续削血")
		traces.append(JSON.stringify(sim.boss_battle.history))
		check(sim.judgments.size()==1 and sim.judgments[0].grade==GameplayTypes.JudgmentGrade.PERFECT,"不改变原 Hold 判定")
	check(traces[0]==traces[1] and traces[1]==traces[2],"不同帧率血量历史一致")
	var broken:=make_sim();broken.accept_input(SemanticInputSample.create(1000000,0,K.LIFE_A_PRESSED));broken.accept_input(SemanticInputSample.create(1200000,1,K.LIFE_A_RELEASED));broken.advance_to(3000000)
	check(broken.boss_battle.states.boss.hp==2600,"断持仅保留成功头判伤害")
	broken.reset();broken.advance_to(3000000);check(broken.boss_battle.states.boss.hp==3600,"重试全 Miss 不残留伤害")
	var fixture:=make_sim();var replay:=ReplayRunner.build_perfect_replay(fixture.compiled,fixture.rules)
	var original:=ReplayRunner.run(fixture.compiled,fixture.rules,replay)
	replay.boss_battles=fixture.boss_battle.definitions.duplicate(true)
	var restored:=ReplayData.from_dictionary(replay.to_dictionary())
	var fast:=ReplayRunner.run(fixture.compiled,fixture.rules,restored,8333)
	var slow:=ReplayRunner.run(fixture.compiled,fixture.rules,restored,33333)
	check(original.digest==fast.digest and fast.digest==slow.digest,"增加 BOSS 状态不改变判定摘要")
	check(JSON.stringify(fast.simulation.boss_battle.history)==JSON.stringify(slow.simulation.boss_battle.history),"Replay 扩展保留战斗配置和确定性伤害")
	print("BOSS GAMEPLAY failures=",failures);quit(failures)
