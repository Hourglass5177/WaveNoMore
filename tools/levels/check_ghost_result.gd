extends SceneTree
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var rules := GameplayRuleSet.new()
	var health := HealthEngine.new(); health.configure(rules)
	var score := ScoreEngine.new(); score.configure(rules)
	var note := JudgmentRecord.new(); note.grade = GameplayTypes.JudgmentGrade.PERFECT
	var notes: Array[JudgmentRecord] = [note]
	var ghosts: Array[Dictionary] = [{"grade":GameplayTypes.JudgmentGrade.MISS,"hit_count":0,"miss_count":8}]
	for i in 8: health.apply_damage(DamageRecord.create(str(i),str(i),0,3))
	var result := ResultEvaluator.evaluate(notes,[],score,health,1,true,ghosts,8)
	assert(result.soul_fire == 76 and result.cleared and not result.full_combo and not result.grants_base_pet)
	assert(result.to_dictionary().ghost_counts.MISS == 8)
	ghosts[0] = {"grade":GameplayTypes.JudgmentGrade.GOOD,"hit_count":8,"miss_count":0}
	result = ResultEvaluator.evaluate(notes,[],score,health,1,true,ghosts,8)
	assert(result.full_combo and not result.all_perfect)
	ghosts[0].grade = GameplayTypes.JudgmentGrade.PERFECT
	result = ResultEvaluator.evaluate(notes,[],score,health,1,true,ghosts,8)
	assert(result.all_perfect)
	var screen = load("res://scenes/screens/result_screen.tscn").instantiate(); root.add_child(screen)
	screen.present(null,result.to_dictionary())
	assert(screen.get_node("%HitRate").text == "100.00%")
	screen.queue_free()
	var loading = load("res://scenes/screens/stage_loading_screen.tscn").instantiate(); root.add_child(loading)
	assert(loading.get_node("%Status").text == "路漫漫其修远兮，吾将上下而求索")
	loading.queue_free(); await process_frame
	print("GHOST RESULT AND LOADING TEXT PASS"); quit()
