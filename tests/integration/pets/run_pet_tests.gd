extends SceneTree
## 使用现行 A/B 输入与真实关卡装配，覆盖技能、伤害时序、装备和白盒视图。
var failures := 0
var checks := 0
const K = GameplayTypes.SemanticInputKind
const G = GameplayTypes.JudgmentGrade

func _init() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL ", label)

func pet(id: String) -> PetDefinition:
	return load("res://content/pets/pet_%s.tres" % id) as PetDefinition

func chart(hold := true, count := 1) -> SongChart:
	var c := DomainFixtureFactory.base_chart("pet_fixture", (count + 2) * 960)
	for i in count:
		var n := NoteEvent.new()
		n.event_id = "pet_note_%d" % i
		n.kind = GameplayTypes.NoteKind.HOLD if hold else GameplayTypes.NoteKind.TAP
		n.affinity = GameplayTypes.Affinity.ZHU
		n.tick = 960 + i * 960
		n.duration_ticks = 480 if hold else 0
		c.note_events.append(n)
	return c

func sim(c: SongChart, effect: PetEffectProfile = null, nonlethal := false) -> GameplaySimulation:
	var r := GameplayRuleSet.new()
	var result := ChartCompiler.compile(c, r)
	check(result.ok, "测试谱面可编译")
	var s := GameplaySimulation.new(); s.configure(result.compiled, r, nonlethal, effect)
	return s

func press(s: GameplaySimulation, time: int, kind := K.LIFE_A_PRESSED) -> void:
	s.accept_input(SemanticInputSample.create(time, 0, kind))

func _run() -> void:
	_test_scores_health()
	_test_hold()
	_test_time()
	await _test_flow()
	print("PET TESTS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _test_scores_health() -> void:
	for advanced in [false, true]:
		var profile := pet("nu_tu_fu").effect(advanced)
		var score := ScoreEngine.new(); var rules := GameplayRuleSet.new()
		rules.perfect_score = 101
		score.configure(rules, profile)
		var perfect_points := 0
		for i in 121:
			var record := JudgmentRecord.new(); record.grade = G.PERFECT if i % 3 else G.GOOD
			var award := score.apply_judgment(record)
			if record.grade == G.PERFECT: perfect_points += award
		check(score.bonus_score == roundi(perfect_points * (0.03 if advanced else 0.02)), "Perfect 含 Combo 的奖励累计后取整")
		check(score.total_score() == score.raw_score + score.bonus_score, "实时总分使用唯一计分器")
		var h := HealthEngine.new(); h.configure(rules, false, pet("gui_jin_yang").effect(advanced))
		var expected := 16 if advanced else 18
		var damage := DamageRecord.create("a", "dual", 1, 20)
		check(h.apply_damage(damage) == expected and damage.actual_damage == expected, "鬼金羊减伤")
		check(h.apply_damage(DamageRecord.create("b", "dual", 1, 20)) == 0, "同组双押只扣一次")
		check(h.apply_damage(DamageRecord.create("round", "round", 1, 15)) == (12 if advanced else 14), "独立伤害按四舍五入取整")
		for i in 10: h.apply_damage(DamageRecord.create(str(i), str(i), i + 2, 20))
		check(h.failed and h.soul_fire == 0, "正常关致死截断到零")
		h.configure(rules, true, pet("gui_jin_yang").effect(advanced))
		for i in 10: h.apply_damage(DamageRecord.create(str(i), str(i), i, 20))
		check(not h.failed and h.soul_fire == 100 - 10 * expected, "非致死模式保留负魂火及减伤")

	var stray := sim(chart(), pet("gui_jin_yang").effect(false))
	stray.rules.stray_input_damages = true
	press(stray, 0); press(stray, 100000); press(stray, 200000)
	check(stray.damages.size() == 3 and stray.health_engine.soul_fire == 46, "复用输入序号的独立乱按仍逐次减伤与扣血")

func _test_hold() -> void:
	for advanced in [false, true]:
		var effect := pet("yi_huo_she").effect(advanced)
		check(effect.hold_head_bonus_ms == 10 and effect.hold_sustain_bonus_ms == 20, "两种形态宽限相同")
		for boundary in [55000, 100000, 145000, 190000]:
			for side in [-1, 1]:
				for delta in [-1, 0, 1]:
					var error: int = boundary + delta
					var s := sim(chart(), effect)
					press(s, 1000000 + side * error)
					s.force_finish()
					var raw := G.PERFECT if error <= 55000 else G.GOOD if error <= 100000 else G.PASS if error <= 145000 else G.MISS
					check(s.judgments[0].base_grade == raw, "Hold 边界内外 1 微秒 %d" % error)
					check(s.judgments[0].grade == (maxi(0, raw - 1) if advanced else raw), "整条 Hold 仅提档一次")
		var missed := sim(chart(), effect)
		missed.advance_to(1190000)
		check(missed.judgments.is_empty(), "Hold 超时边界仍等待")
		missed.advance_to(1190001, false)
		check(missed.judgments.is_empty(), "排除端点的推进不提前结算超时")
		missed.advance_to(1190001)
		check(missed.judgments[0].base_grade == G.MISS, "Hold 超时后一微秒结算")
		check(missed.health_engine.soul_fire == 100, "头部失误尚未抵达不扣血")
		check(not missed.result_summary().cleared, "等待抵达伤害结清后才允许通关")
		var arrival := missed.wave_engine.next_arrival_us()
		missed.advance_to(arrival - 1); check(missed.health_engine.soul_fire == 100, "抵达前一微秒无伤害")
		missed.advance_to(arrival)
		check(missed.health_engine.soul_fire == 80 and missed.damages[0].timestamp_us == arrival, "精确抵达时扣血")
		check(missed.judgments[0].grade == (G.PASS if advanced else G.MISS), "完全未按也按形态提档")
		check(missed.result_summary().full_combo == advanced and not missed.result_summary().all_perfect, "受伤 Pass 可以 FC，但不是 AP")
		for gap in [119999, 120000, 120001]:
			var s := sim(chart(), effect)
			press(s, 1000000); press(s, 1100000, K.LIFE_A_RELEASED); press(s, 1100000 + gap)
			s.force_finish()
			var raw := G.PASS if gap <= 120000 else G.MISS
			check(s.judgments[0].base_grade == raw, "断持续按宽限 %d" % gap)
			if gap > 120000:
				check(s.damages.size() == 1 and s.damages[0].timestamp_us == 1220001, "断持按失败时间扣血且不重复抵达伤害")
		var tap := sim(chart(false), effect)
		press(tap, 1045001); tap.force_finish()
		check(tap.judgments[0].grade == G.GOOD, "Tap 不受宽限和提档影响")
		var short_chart := chart(); short_chart.note_events[0].duration_ticks = 48
		var short := sim(short_chart, effect)
		press(short, 1000000); press(short, 1010000, K.LIFE_A_RELEASED); short.force_finish()
		check(short.judgments[0].base_grade == G.PERFECT, "短 Hold 尾点在宽限内自动完成")
		var paused := sim(chart(), effect)
		press(paused, 1000000)
		var rearm := paused.begin_pause_rearm()
		rearm.life_a_held = true
		paused.apply_resume_rearm(rearm); paused.force_finish()
		check(paused.judgments[0].grade == G.PERFECT, "暂停重臂不丢失随从配置")
	var dual := chart()
	var other: NoteEvent = dual.note_events[0].duplicate(true)
	other.event_id = "other"; other.affinity = GameplayTypes.Affinity.XUAN
	dual.note_events.append(other)
	var s := sim(dual, pet("yi_huo_she").effect(true))
	press(s, 1100000); press(s, 1100000, K.DEATH_A_PRESSED); s.force_finish()
	check(s.judgments.size() == 2 and s.result_summary().all_perfect, "双侧 Hold Good 分别升级并计入 AP")
	check(s.damages.is_empty() and not s.drain_wave_contacts().is_empty(), "成功起手的实体波接触不产生抵达伤害")
	s.reset(); check(s.damages.is_empty() and s.score_engine.total_score() == 0 and s.pet_effect.hold_grade_boost == 1, "重试清空结果并保留本局技能")

	for shared in [false, true]:
		var damage_chart := dual.duplicate(true) as SongChart
		if shared:
			for note: NoteEvent in damage_chart.note_events: note.damage_group_id = "pair"
		var damaged := sim(damage_chart, pet("gui_jin_yang").effect(false))
		damaged.force_finish()
		check(damaged.damages.size() == (1 if shared else 2), "两界同刻受击按伤害组去重")
		check(damaged.health_engine.soul_fire == (82 if shared else 64), "两界不会重复应用同一随从的减伤")
	var profile := pet("yi_huo_she").effect(true)
	var copied := sim(chart(), profile)
	profile.hold_grade_boost = 0
	check(copied.pet_effect.hold_grade_boost == 1 and copied.rules.perfect_window_ms == 45, "本局技能独立复制且不改共享规则")
	var neutral := sim(DomainFixtureFactory.tuning_only_chart())
	var with_snake := sim(DomainFixtureFactory.tuning_only_chart(), pet("yi_huo_she").effect(true))
	neutral.force_finish(); with_snake.force_finish()
	check(ReplayRunner.result_digest(neutral.judgments, neutral.strays, neutral.result_summary()) == ReplayRunner.result_digest(with_snake.judgments, with_snake.strays, with_snake.result_summary()), "翼火蛇不修改调频和素音结果")

func _test_time() -> void:
	var c := chart(true, 10)
	var effect := pet("yi_huo_she").effect(true)
	var baseline := sim(c, effect)
	baseline.force_finish()
	check(baseline.health_engine.failed and not baseline.result_summary().full_combo, "提档不阻止魂火耗尽失败")
	var traces := []
	for step in [8333, 16667, 5000000]:
		var s := sim(c, effect)
		var time := 0
		while time < 15000000:
			time += step; s.advance_to(time)
		var trace := []
		for damage in s.damages: trace.append(damage.to_dictionary())
		traces.append(trace)
		check(s.score_engine.total_score() == baseline.score_engine.total_score() and s.judgments.size() == baseline.judgments.size(), "大帧步不计入死亡之后的成绩")
	check(traces[0] == traces[1] and traces[1] == traces[2], "伤害时刻与帧率无关")
	var r := GameplayRuleSet.new()
	var compiled: CompiledChart = ChartCompiler.compile(c, r).compiled
	var replay := ReplayData.new()
	var a := ReplayRunner.run(compiled, r, replay, 8333, effect)
	var b := ReplayRunner.run(compiled, r, replay, 5000000, effect)
	check(a.ok and b.ok and a.digest == b.digest, "领域重演显式注入随从配置")
	var early_death := sim(c, effect)
	early_death.rules.max_soul_fire = 20
	early_death.health_engine.soul_fire = 20
	press(early_death, 9000000)
	check(early_death.health_engine.failed and early_death.judgments.all(func(record: JudgmentRecord) -> bool: return record.finalized_at_us <= early_death.damages[0].timestamp_us), "晚输入跨过致死抵达后不再参与判定")

func _test_flow() -> void:
	var catalog := ContentCatalogData.new()
	catalog.pets = [pet("nu_tu_fu"), pet("gui_jin_yang"), pet("yi_huo_she")]
	check(ContentPackageValidator.validate_catalog(catalog).is_empty(), "内容校验器接受三类资源化被动效果")
	var save = root.get_node("SaveService")
	var service = load("res://src/services/save/save_service.gd").new()
	service.configure_storage_paths("user://pets_test.json", "user://pets_test.tmp", "user://pets_test.bak")
	service.data = service.default_data()
	var stage := StageDefinition.new()
	stage.stage_id = "pet_reward"; stage.display_name = "随从测试"
	stage.chart = chart(); stage.rule_set = GameplayRuleSet.new()
	stage.song = SongDefinition.new(); stage.song.song_id = "pet_song"; stage.song.fallback_duration_sec = 5
	stage.reward = RewardDefinition.new(); stage.reward.pet = pet("yi_huo_she")
	stage.reward.fc_grants_base_pet = true; stage.reward.ap_grants_advanced_pet = true
	service.record_stage_result(stage, {"cleared": true, "full_combo": true, "all_perfect": true})
	check(service.pet_state("yi_huo_she").owned and service.pet_state("yi_huo_she").advanced, "首次 AP 同时解锁基础和进阶")
	service.record_stage_result(stage, {"cleared": true, "full_combo": true, "all_perfect": false})
	check(service.pet_state("yi_huo_she").advanced, "重复 FC 不降级")
	check(service.equip_pet("yi_huo_she"), "已获得随从可以装备")
	service.load_or_create(); check(service.equipped_pet_id() == "yi_huo_she", "保存重开保留装备")
	service.data.pets["horned_soul"] = {"owned": true, "advanced": true}
	service.data.equipped_pet_id = "horned_soul"
	check(service.equipped_pet_id().is_empty(), "旧占位装备按未装备处理")
	check(not service.equip_pet("missing"), "未登记随从不能装备")
	var scored := sim(chart(false), pet("nu_tu_fu").effect(true))
	press(scored, 1000000)
	scored.force_finish()
	var score_result := scored.result_summary().to_dictionary()
	service.record_stage_result(stage, score_result)
	service.load_or_create()
	check(service.stage_result(stage.stage_id).last_result.score == scored.score_engine.total_score(), "实时得分、结算和保存重开一致")
	check(service.pet_state("horned_soul").advanced, "保存重开保留旧随从历史条目")
	check(service.stage_result(stage.stage_id).last_result.bonus_score == scored.score_engine.bonus_score, "随从附加分原值保存")
	service.free()
	# 主单例切到隔离存档后测试页面，退出不触及玩家正式存档。
	save.configure_storage_paths("user://pets_ui_test.json", "user://pets_ui_test.tmp", "user://pets_ui_test.bak")
	save.data = save.default_data()
	save.debug_grant_pet("yi_huo_she", true)
	save.debug_grant_pet("yi_huo_she", false)
	check(save.pet_state("yi_huo_she").advanced and not save.equipped_pet_advanced(), "开发基础测试不降级已获得进阶")
	var modal = load("res://scenes/ui/modals/pet_select_modal.tscn").instantiate()
	root.add_child(modal)
	await process_frame
	check(modal._list.get_child_count() == 3, "菜单显示三只随从")
	await screenshot("pets-menu")
	save.data = save.default_data()
	modal._build_list()
	await process_frame
	check(root.gui_get_focus_owner() == modal._back_button, "全未解锁时仍可用键盘和手柄导航")
	modal.queue_free(); await process_frame
	var scene = load("res://scenes/stage/stage_root.tscn").instantiate()
	root.add_child(scene)
	scene.set_pet(pet("yi_huo_she"), true)
	check(scene.load_stage(stage, false), "真实关卡接入随从")
	check(scene._pet_views.size() == 2, "两界各一处白盒表现")
	var first: Vector2 = scene._pet_views[0].global_position
	var second: Vector2 = scene._pet_views[1].global_position
	check((first + second).distance_to(Vector2(1920, 1080)) < 0.01, "随从位置中心对称")
	var core: GameplaySimulation = scene.gameplay_coordinator.simulation
	# 由正式调度器生成、判定并推进漏按 Hold，校验表现链路而非直接伪造信号。
	scene.set_debug_visible(false)
	scene.stage_session.external_preview = true
	scene.stage_session.reset_preview()
	for time in range(0, 1200001, 10000):
		scene.stage_session.advance_preview(time)
	check(scene.stage_session._deferred_note_grades["pet_note_0"] == G.MISS and core.judgments[0].grade == G.PASS, "受击表现读取机械 Miss，HUD 读取 Pass")
	var active: Dictionary = scene.presentation._note_visual_host._active
	check(active.has("pet_note_0") and active["pet_note_0"].get("hold_failed", false), "提档后的漏按 Hold 仍沿失败路径移动")
	check(scene._pet_views[0]._trigger_age < 0.35, "技能反馈按歌曲时间采样")
	await screenshot("pets-missed-hold")
	var arrival := core.wave_engine.next_arrival_us()
	scene.stage_session.advance_preview(arrival)
	check(core.health_engine.soul_fire == 80 and scene.hud._soul_fire_value.text == "80 / 100", "抵达时真实扣血并刷新 HUD")
	check(scene.hud._judgment_label.text.to_lower() == "pass", "受伤时保留最终 Pass 判定文字")
	await screenshot("pets-stage")
	scene.stage_session.reset_preview()
	scene.stage_session.advance_preview(0)
	check(core.damages.is_empty() and scene._pet_views[0]._trigger_age > 1.0, "定位重建清除旧伤害与技能反馈")
	for time in range(0, 1200001, 10000):
		scene.stage_session.advance_preview(time)
	check(core.judgments.size() == 1 and core.score_engine.combo == 1, "重复定位不累加旧成绩")
	var settled := {}
	scene.stage_finished.connect(func(result: Dictionary) -> void: settled.merge(result))
	scene._on_stage_result_ready(core.result_summary().to_dictionary())
	check(settled.pet_name == "翼火蛇" and settled.pet_advanced, "结算记录本局装备")
	scene.queue_free(); await process_frame

func screenshot(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/pet-review/%s.png" % name)
