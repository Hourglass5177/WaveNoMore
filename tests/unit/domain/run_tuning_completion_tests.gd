extends SceneTree
## 完成度四档边界、双侧折返、帧率、计分与零滑条伤害。
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func run() -> void:
	var fixture = load("res://tests/unit/domain/test_tuning_arc_assist.gd").new()
	var rules := GameplayRuleSet.new()
	# 输入会量化；端到端边界留出一个可表达步长，纯比例边界另行检查。
	for test: Array in [[1.0,0],[0.971,0],[0.969,1],[0.901,1],[0.899,2],[0.801,2],[0.799,3],[0.0,3]]:
		for side in 2:
			for step: int in [8333,33333,191777]:
				var compiled: CompiledChart = fixture._compile_single_slider(1.2,2,rules)
				compiled.tuning_sliders[0].affinity = side
				var slider: Dictionary = compiled.tuning_sliders[0]
				var engine := TuningEngine.new(); engine.configure(compiled,rules); engine.set_dual_holding_notes(true,0)
				engine.advance_to(0,true,true,true)
				for leg in 2:
					var begin := leg*1000000; var target := begin+1000000
					var vector := Vector2.ZERO
					vector[side] = (float(slider.end_value)-float(slider.start_value))*float(test[0])*(1.0 if leg==0 else -1.0)
					engine.advance_to(begin+1,false,true,true)
					engine.handle_input(SemanticInputSample.create(begin+1,leg,GameplayTypes.SemanticInputKind.TUNING_DISPLACED,vector),true,true)
					var time := begin+1
					while time < target:
						time = mini(time+step,target); engine.advance_to(time,true,true,true)
				var records := engine.drain_judgments()
				check(records.size()==1 and records[0].grade==int(test[1]),"完成度 %s / 侧 %d / 帧步 %d" % [test[0],side,step])
				if not records.is_empty():
					var score := ScoreEngine.new(); score.configure(rules); score.apply_judgment(records[0])
					check(score.raw_score == [1000,700,400,0][int(test[1])],"四档基础分生效")
					var health := HealthEngine.new(); health.configure(rules); health.apply_judgment(records[0])
					check(health.soul_fire==100,"各档 Tuning 自身均不扣血")
	var compiled: CompiledChart = fixture._compile_single_slider(1.2,1,rules)
	var engine := TuningEngine.new(); engine.configure(compiled,rules); engine.set_dual_holding_notes(true,0)
	for boundary: Array in [[0.97,0],[0.90,1],[0.80,2]]:
		check(engine.completion_grade(boundary[0])==boundary[1] and engine.completion_grade(boundary[0]-0.00001)==boundary[1]+1,"精确阈值包含边界")
	engine.advance_to(0,true,true,true)
	engine.handle_input(SemanticInputSample.create(1,1,GameplayTypes.SemanticInputKind.TUNING_DISPLACED,Vector2(0.2,0)),true,true)
	engine.advance_to(1000000,true,false,true)
	check(engine.drain_judgments()[0].grade==3,"即使完成，尾点未持有仍 Miss")
	rules.tuning_pass_completion=0.99
	check(not PlanningParameters.validate_rules(rules).is_empty(),"策划表报告倒序完成阈值")
	print("调频四档：",checks," 项，失败 ",failures); quit(1 if failures else 0)
