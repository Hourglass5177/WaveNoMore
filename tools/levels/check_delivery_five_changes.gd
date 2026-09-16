extends SceneTree
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var save=root.get_node("SaveService")
	save.data=save.default_data()
	var before=save.data.duplicate(true)
	save.toggle_developer_unlock()
	assert(save.pet_state("nu_tu_fu").advanced)
	assert(save.is_stage_unlocked(root.get_node("ContentCatalog").get_stage("level3")))
	save.equip_pet("nu_tu_fu")
	assert(save.equipped_pet_id()=="nu_tu_fu")
	save.toggle_developer_unlock()
	assert(save.data==before and not save.pet_state("nu_tu_fu").get("owned",false))
	var pet=load("res://scenes/ui/modals/pet_select_modal.tscn").instantiate();root.add_child(pet)
	assert(pet.get_node("%UnknownName").visible)
	save.toggle_developer_unlock()
	assert(not pet.get_node("%UnknownName").visible)
	save.toggle_developer_unlock()
	assert(pet.get_node("%UnknownName").visible)
	pet.queue_free();await process_frame
	var rules=PlanningParameters.rules_copy(load(PlanningParameters.DEFAULT_RULES),PlanningParameters.read())
	assert(rules.tap_miss_damage==12 and is_equal_approx(rules.hold_segment_damage,1.2) and rules.ghost_miss_damage==3)
	var tuning := TuningEngine.new()
	tuning._slider_by_id = {"a": 0}
	tuning._slider_states = [{"slider": {}, "finished": true, "grade": GameplayTypes.JudgmentGrade.GOOD}]
	assert(tuning.ghost_grade(PackedStringArray(["a"]), 0) == GameplayTypes.JudgmentGrade.GOOD)
	tuning._slider_states[0].grade = GameplayTypes.JudgmentGrade.PASS
	assert(tuning.ghost_grade(PackedStringArray(["a"]), 0) == GameplayTypes.JudgmentGrade.MISS)
	var ghost := SuManifestationOverlay.new(); root.add_child(ghost)
	ghost.prepare_targets({"event_id":"check", "time_us":1000000, "points":[Vector2(0.5,0.5)]})
	ghost.set_visual_time(1.0)
	ghost.resolve_targets({"event_id":"check", "hit_count":1})
	assert(ghost._fragments._active.size() == 1)
	ghost.set_visual_time(1.7)
	assert(ghost._fragments._active.is_empty())
	ghost.queue_free()
	var game=load("res://scenes/stage/stage_root.tscn").instantiate();root.add_child(game)
	var stage=root.get_node("ContentCatalog").get_stage("tutorial2");stage.resolve_dependencies_sync()
	assert(game.load_stage(stage,false))
	for path in game.level_show_player.boss_emissions.values():
		if not path.has("arc_profile"):continue
		assert(int(path.join_lead_us) >= int(stage.rule_set.approach_duration_sec * 0.79 * 1000000))
		var finish=BossEmissionPath.sample(path,int(path.duration_us))
		assert(absf(finish.distance-float(path.arc_profile.length_px))<0.1)
		var begin=BossEmissionPath.sample(path,0)
		assert(begin.distance==0.0)
	game.queue_free();await process_frame
	print("FIVE CHANGES PASS");quit()

