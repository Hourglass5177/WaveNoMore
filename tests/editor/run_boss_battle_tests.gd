extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; printerr(label)
func _initialize() -> void:
	var compiled := CompiledChart.new()
	compiled.tempo_map = TempoMap.new()
	compiled.notes = [{"id":"a","unit_kind":&"tap","end_us":1000000},{"id":"b","unit_kind":&"tap","end_us":2000000}]
	var battle := BossBattleEngine.new()
	battle.configure([{"id":"boss","name":"测试","note_ids":["a","b"],"phase_duration_us":300000}],compiled,GameplayRuleSet.new())
	var record := JudgmentRecord.new(); record.unit_id="a";record.grade=GameplayTypes.JudgmentGrade.PERFECT;record.finalized_at_us=1000000
	battle.observe(record); battle.observe(record)
	check(battle.states.boss.hp==600, "重复结果不得重复扣血")
	check(battle.states.boss.phase_us==1000000, "半血只触发一次阶段")
	record=JudgmentRecord.new();record.unit_id="b";record.grade=GameplayTypes.JudgmentGrade.PERFECT;record.finalized_at_us=2000000
	battle.observe(record)
	check(battle.states.boss.hp==0 and battle.states.boss.finish_us==-1, "零血先破防，不立刻死亡")
	# 判定成功后仍等待真实传播接触完成，不能只用判定时间结束战斗。
	battle.resolve_contact("a",1100000);battle.resolve_contact("b",2100000)
	battle.advance(3000000,true,NoteJudgeEngine.new(),TuningEngine.new())
	check(battle.states.boss.finish_us>2000000,"等待最后判定窗口结束")
	battle.reset();check(battle.states.boss.hp==1600 and battle.history.is_empty(),"重试清理状态")
	print("BOSS BATTLE failures=",failures);quit(failures)
