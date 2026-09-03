extends RefCounted

## 内容包集成测试。
## 它读取仓库里的真实 Catalog 和关卡资源，检查“文件存在”之外的跨资源关系。

## 已执行的内容合同断言数，用来发现用例意外提前返回。
var _checks := 0
## 跨目录关系检查的累计失败文本；整套内容跑完后统一汇总。
var _failures: PackedStringArray = []


func run() -> Dictionary:
	# 先看登记和资源结构，再确认这些数据能被正式运行时编译。
	_test_catalog_explicit_stage_entry()
	_test_stage_package()
	_test_tuning_lab_package()
	_test_schema_2_contract()
	_test_runtime_compilation()
	_test_tuning_lab_runtime_compilation()
	_test_cross_resource_validation()
	_test_show_contract()
	_test_visual_manifest()
	var ok := _failures.is_empty()
	if ok:
		print("CONTENT TESTS: %d checks passed." % _checks)
	else:
		printerr("CONTENT TESTS FAILED: %d/%d checks failed." % [_failures.size(), _checks])
		for failure: String in _failures:
			printerr("  - " + failure)
	return {"ok": ok, "checks": _checks, "failures": Array(_failures)}


func _test_catalog_explicit_stage_entry() -> void:
	var catalog := load("res://content/catalogs/mvp_catalog.tres") as ContentCatalogData
	_expect(catalog != null, "MVP content catalog loads")
	if catalog == null:
		return
	var stage_ids: Array[String] = []
	for stage: StageDefinition in catalog.stages:
		if stage != null:
			stage_ids.append(stage.stage_id)
	_expect(stage_ids.has("s01"), "MVP catalog explicitly registers playable test stage s01")
	_expect(stage_ids.has("s02"), "MVP catalog explicitly registers tuning experiment stage s02")


func _test_stage_package() -> void:
	var stage := load("res://content/stages/s01/stage_definition.tres") as StageDefinition
	_expect(stage != null, "s01 StageDefinition loads")
	if stage == null:
		return
	_expect(stage.resolve_dependencies_sync(ResourceLoader.CACHE_MODE_IGNORE), "s01 lazy composition resolves")
	_expect_equal(stage.stage_id, "s01", "stage ID is stable")
	_expect(stage.song != null and stage.chart != null and stage.stage_show != null, "stage composes song, chart and show")
	_expect(stage.visual_theme != null and stage.reward != null and stage.rule_set != null, "stage composes theme, reward and rules")
	_expect(stage.unlocked_by_default, "first stage is unlocked by default")
	_expect(stage.debug_nonlethal, "playable test stage enables nonlethal debug health")
	_expect_equal(stage.chart.ppq, 480, "chart uses PPQ 480")
	_expect(stage.chart.note_events.size() >= 8, "chart contains tap/chord/hold note events")
	var life_hold: NoteEvent
	var death_hold: NoteEvent
	var death_cross_tap: NoteEvent
	var life_cross_tap: NoteEvent
	for note: NoteEvent in stage.chart.note_events:
		match note.event_id:
			"n_hold_life": life_hold = note
			"n_hold_death": death_hold = note
			"n_death_during_life_hold": death_cross_tap = note
			"n_life_during_death_hold": life_cross_tap = note
	_expect(life_hold != null and death_cross_tap != null and death_cross_tap.tick > life_hold.tick and death_cross_tap.tick < life_hold.tick + life_hold.duration_ticks, "test chart covers Death Tap during Life Hold")
	_expect(death_hold != null and life_cross_tap != null and life_cross_tap.tick > death_hold.tick and life_cross_tap.tick < death_hold.tick + death_hold.duration_ticks, "test chart covers mirrored Life Tap during Death Hold")
	_expect_equal(stage.chart.tuning_fields.size(), 1, "chart contains one tuning field")
	_expect_equal(stage.chart.tuning_sliders.size(), 2, "chart contains paired life/death tuning sliders")
	_expect_equal(stage.chart.su_manifestations.size(), 1, "chart contains a dynamic Su manifestation")
	_expect_equal(stage.chart.rapid_regions.size(), 1, "chart contains rapid region")
	_expect(stage.reward.pet != null, "stage reward references a pet")


func _test_tuning_lab_package() -> void:
	var stage := load("res://content/stages/s02/stage_definition.tres") as StageDefinition
	_expect(stage != null, "s02 tuning experiment StageDefinition loads")
	if stage == null:
		return
	_expect(stage.resolve_dependencies_sync(ResourceLoader.CACHE_MODE_IGNORE), "s02 lazy composition resolves")
	_expect_equal(stage.stage_id, "s02", "tuning experiment stage ID is stable")
	_expect(stage.song != null and stage.chart != null and stage.stage_show != null, "s02 composes song, chart and show")
	_expect(stage.visual_theme != null and stage.reward != null and stage.rule_set != null, "s02 composes theme, reward and rules")
	_expect(stage.unlocked_by_default, "tuning experiment is immediately selectable")
	_expect(stage.debug_nonlethal, "tuning experiment keeps running below zero health")
	_expect_equal(stage.chart.ppq, 480, "tuning experiment uses PPQ 480")
	_expect_equal(stage.chart.note_events.size(), 0, "tuning experiment contains no ordinary notes")
	_expect_equal(stage.chart.rapid_regions.size(), 0, "tuning experiment contains no rapid regions")
	_expect_equal(stage.chart.tuning_fields.size(), 2, "tuning experiment isolates two authored tuning fields")
	_expect_equal(stage.chart.tuning_sliders.size(), 6, "tuning experiment covers solo, paired and repeat sliders")
	_expect_equal(stage.chart.su_manifestations.size(), 2, "tuning experiment contains two dynamic Su manifestations")
	_expect(stage.reward.pet == null, "tuning experiment grants no pet")
	_expect(not stage.reward.fc_grants_base_pet and not stage.reward.ap_grants_advanced_pet, "tuning experiment has no FC/AP reward side effects")
	var fields_by_id: Dictionary = {}
	for field: TuningFieldRegion in stage.chart.tuning_fields:
		fields_by_id[field.event_id] = field
	var grouped_sliders: Dictionary = {}
	var has_solo: bool = false
	var has_repeat: bool = false
	for slider: TuningSliderEvent in stage.chart.tuning_sliders:
		_expect(fields_by_id.has(slider.field_id), "%s references an existing tuning field" % slider.event_id)
		_expect(slider.start_value >= 0.0 and slider.start_value <= 1.0 and slider.end_value >= 0.0 and slider.end_value <= 1.0, "%s uses normalized frequency endpoints" % slider.event_id)
		has_solo = has_solo or slider.group_id.is_empty()
		has_repeat = has_repeat or slider.traversal_count > 1
		if not slider.group_id.is_empty():
			if not grouped_sliders.has(slider.group_id):
				grouped_sliders[slider.group_id] = []
			grouped_sliders[slider.group_id].append(slider)
	_expect(has_solo, "tuning experiment includes an independent single-bell slider")
	_expect(has_repeat, "tuning experiment includes a return-arrow traversal")
	for group_id: String in grouped_sliders.keys():
		var members: Array = grouped_sliders[group_id]
		_expect_equal(members.size(), 2, "%s contains exactly two sides" % group_id)
		if members.size() == 2:
			_expect((members[0] as TuningSliderEvent).affinity != (members[1] as TuningSliderEvent).affinity, "%s pairs life and death" % group_id)
	for manifestation: SuManifestationEvent in stage.chart.su_manifestations:
		_expect(grouped_sliders.has(manifestation.group_id), "%s references an existing paired slider group" % manifestation.event_id)
		_expect(manifestation.spawn_region_normalized.size.x > 0.0 and manifestation.spawn_region_normalized.size.y > 0.0, "%s authors an area instead of a fixed target point" % manifestation.event_id)


func _test_schema_2_contract() -> void:
	var stage := load("res://content/stages/s02/stage_definition.tres") as StageDefinition
	_expect(stage != null and stage.resolve_dependencies_sync(ResourceLoader.CACHE_MODE_IGNORE), "s02 resolves for Schema 2 contract checks")
	if stage == null or not stage.dependencies_resolved():
		return
	_expect_equal(stage.chart.schema_version, SongChart.CURRENT_SCHEMA_VERSION, "authored tuning chart uses the current schema")
	var compiled_result := ChartCompiler.compile(stage.chart, stage.rule_set)
	_expect(bool(compiled_result.get("ok", false)), "Schema 2 tuning chart compiles before contract checks")
	if bool(compiled_result.get("ok", false)):
		var compiled := compiled_result["compiled"] as CompiledChart
		_expect_equal(compiled.theoretical_unit_count, 4, "paired sliders count once and Su manifestations do not count")
		_expect_equal(str(compiled.tuning_sliders[1]["unit_id"]), str(compiled.tuning_sliders[2]["unit_id"]), "paired slider sides share one compiled unit ID")
		var reordered := stage.chart.duplicate(true) as SongChart
		reordered.tuning_fields.reverse()
		reordered.tuning_sliders.reverse()
		reordered.su_manifestations.reverse()
		var reordered_result := ChartCompiler.compile(reordered, stage.rule_set)
		_expect(bool(reordered_result.get("ok", false)), "reordered authoring arrays remain valid")
		if bool(reordered_result.get("ok", false)):
			_expect_equal((reordered_result["compiled"] as CompiledChart).content_hash, compiled.content_hash, "compiler sorting makes Schema 2 hash independent of authoring array order")

	var legacy := stage.chart.duplicate(true) as SongChart
	legacy.schema_version = 1
	var migration: Dictionary = ChartMigrator.migrate(legacy)
	_expect(not bool(migration.get("ok", false)), "Schema 1 shared-curve tuning is rejected instead of guessed")
	_expect(_report_has_code(migration["report"], &"schema.v1_tuning_requires_reauthoring"), "Schema 1 rejection explains that tuning needs reauthoring")

	var missing_field := stage.chart.duplicate(true) as SongChart
	missing_field.tuning_sliders[0].field_id = "missing_field"
	_expect(_report_has_code(ChartValidator.validate(missing_field, stage.rule_set), &"tuning_slider.field_missing"), "validator rejects a slider whose tuning field is missing")

	var unreachable_start := stage.chart.duplicate(true) as SongChart
	unreachable_start.tuning_sliders[0].tick = unreachable_start.tuning_fields[0].tick
	unreachable_start.tuning_sliders[0].start_value = 0.1
	_expect(_report_has_code(ChartValidator.validate(unreachable_start, stage.rule_set), &"tuning_slider.unreachable_field_start"), "validator rejects a field-opening slider that cannot start from base frequency")

	var invalid_group := stage.chart.duplicate(true) as SongChart
	invalid_group.tuning_sliders[1].group_id = "orphan_group"
	_expect(_report_has_code(ChartValidator.validate(invalid_group, stage.rule_set), &"tuning_slider.group_size"), "validator rejects incomplete paired-slider groups")

	var invalid_region := stage.chart.duplicate(true) as SongChart
	invalid_region.su_manifestations[0].spawn_region_normalized = Rect2(0.9, 0.9, 0.2, 0.2)
	_expect(_report_has_code(ChartValidator.validate(invalid_region, stage.rule_set), &"su_manifestation.spawn_region"), "validator rejects a Su spawn area outside the normalized canvas")


func _test_runtime_compilation() -> void:
	var stage := load("res://content/stages/s01/stage_definition.tres") as StageDefinition
	if stage == null:
		return
	_expect(stage.resolve_dependencies_sync(ResourceLoader.CACHE_MODE_IGNORE), "s01 dependencies resolve for compilation")
	var report := ChartValidator.validate(stage.chart, stage.rule_set)
	_expect(not report.has_errors(), "s01 passes shared ChartValidator: %s" % JSON.stringify(report.to_array()))
	var result := ChartCompiler.compile(stage.chart, stage.rule_set)
	_expect(bool(result.get("ok", false)), "s01 compiles with shared ChartCompiler")
	if not bool(result.get("ok", false)):
		return
	var compiled := result["compiled"] as CompiledChart
	_expect(not compiled.content_hash.is_empty(), "compiled chart has deterministic hash")
	var replay := ReplayRunner.build_perfect_replay(compiled, stage.rule_set)
	var run_result := ReplayRunner.run(compiled, stage.rule_set, replay, 16_667)
	_expect(bool(run_result.get("ok", false)), "Perfect Replay runs")
	if bool(run_result.get("ok", false)):
		var summary := run_result["summary"] as ResultSummary
		_expect(summary.cleared and summary.full_combo and summary.all_perfect, "Perfect Replay clears s01 with FC/AP")
		var result_data := summary.to_dictionary()
		_expect(bool(result_data.get("full_combo", false)) and bool(result_data.get("all_perfect", false)), "result dictionary exposes canonical FC/AP fields")
		var counts: Dictionary = result_data.get("grade_counts", {})
		_expect_equal(int(counts.get("PERFECT", 0)), summary.judgment_count, "result dictionary exposes grade counts")


func _test_tuning_lab_runtime_compilation() -> void:
	var stage := load("res://content/stages/s02/stage_definition.tres") as StageDefinition
	if stage == null:
		return
	_expect(stage.resolve_dependencies_sync(ResourceLoader.CACHE_MODE_IGNORE), "s02 dependencies resolve for compilation")
	var chart_report := ChartValidator.validate(stage.chart, stage.rule_set)
	_expect(not chart_report.has_errors(), "s02 passes shared ChartValidator: %s" % JSON.stringify(chart_report.to_array()))
	var package_issues := ContentPackageValidator.validate_stage(stage)
	var package_errors := package_issues.filter(func(issue: Dictionary) -> bool: return issue.get("severity") == "error")
	_expect_equal(package_errors.size(), 0, "s02 passes cross-resource package validation: %s" % JSON.stringify(package_errors))
	var result := ChartCompiler.compile(stage.chart, stage.rule_set)
	_expect(bool(result.get("ok", false)), "s02 compiles with shared ChartCompiler")
	if not bool(result.get("ok", false)):
		return
	var compiled := result["compiled"] as CompiledChart
	var replay := ReplayRunner.build_perfect_replay(compiled, stage.rule_set)
	var at_30 := ReplayRunner.run(compiled, stage.rule_set, replay, 33_333)
	var at_60 := ReplayRunner.run(compiled, stage.rule_set, replay, 16_667)
	var at_120 := ReplayRunner.run(compiled, stage.rule_set, replay, 8_333)
	_expect(bool(at_30.get("ok", false)) and bool(at_60.get("ok", false)) and bool(at_120.get("ok", false)), "s02 Perfect Replay executes at 30/60/120 FPS steps")
	if not bool(at_60.get("ok", false)):
		return
	var summary := at_60["summary"] as ResultSummary
	_expect(summary.cleared and summary.full_combo and summary.all_perfect, "s02 Perfect Replay clears all independent and paired sliders with FC/AP")
	_expect_equal(summary.judgment_count, 4, "s02 counts each solo slider and each paired group exactly once")
	_expect_equal(at_30["digest"], at_60["digest"], "s02 result is deterministic between 30 and 60 FPS steps")
	_expect_equal(at_60["digest"], at_120["digest"], "s02 result is deterministic between 60 and 120 FPS steps")


func _test_cross_resource_validation() -> void:
	var stage := load("res://content/stages/s01/stage_definition.tres") as StageDefinition
	_expect(stage != null and stage.resolve_dependencies_sync(ResourceLoader.CACHE_MODE_IGNORE), "s01 resolves for package validation")
	if stage == null or not stage.dependencies_resolved():
		return
	var issues := ContentPackageValidator.validate_stage(stage)
	var errors := issues.filter(func(issue: Dictionary) -> bool: return issue.get("severity") == "error")
	_expect_equal(errors.size(), 0, "s01 passes cross-resource package validation: %s" % JSON.stringify(errors))

	# 先深复制再制造错误，避免改到 ResourceLoader 缓存中的正式关卡并污染后续测试。
	var invalid_stage := stage.duplicate(true) as StageDefinition
	invalid_stage.stage_show = stage.stage_show.duplicate(true) as StageShow
	invalid_stage.stage_show.cues[-1].tick = stage.chart.end_tick + 1
	var show_issues := ContentPackageValidator.validate_stage(invalid_stage)
	_expect(show_issues.any(func(issue: Dictionary) -> bool: return str(issue.get("message", "")).contains("超出谱面结尾")), "package validator rejects a show cue beyond chart end")

	invalid_stage = stage.duplicate(true) as StageDefinition
	invalid_stage.song = stage.song.duplicate(true) as SongDefinition
	invalid_stage.song.fallback_duration_sec = invalid_stage.song.first_beat_offset_sec + 1.0
	var duration_issues := ContentPackageValidator.validate_stage(invalid_stage)
	_expect(duration_issues.any(func(issue: Dictionary) -> bool: return str(issue.get("message", "")).contains("authored song duration")), "package validator rejects a chart beyond authored song duration")


func _test_show_contract() -> void:
	var show := load("res://content/stages/s01/stage_show.tres") as StageShow
	_expect(show != null, "StageShow loads")
	if show == null:
		return
	var ids: Dictionary = {}
	var previous_tick := -1
	var intro_text: String = ""
	for cue: ShowCue in show.cues:
		_expect(cue != null and not cue.event_id.is_empty(), "every show cue has stable ID")
		if cue == null:
			continue
		_expect(not ids.has(cue.event_id), "show cue ID is unique: %s" % cue.event_id)
		ids[cue.event_id] = true
		if cue.event_id == "show_intro":
			intro_text = str(cue.parameters.get("text", ""))
		_expect(cue.tick >= previous_tick, "show cues are stored in timeline order")
		previous_tick = cue.tick
	_expect(intro_text.contains("右上红音→右键/J"), "intro tutorial maps the upper-right life stream to the right control")
	_expect(intro_text.contains("左下黑音→左键/F"), "intro tutorial maps the lower-left death stream to the left control")


func _test_visual_manifest() -> void:
	var manifest := load("res://content/visual/graybox_manifest.tres") as VisualAssetManifest
	_expect(manifest != null, "Graybox visual manifest loads")
	if manifest == null:
		return
	var mvp_issues := ArtManifestValidator.validate(manifest, true)
	var mvp_errors := mvp_issues.filter(func(issue: Dictionary) -> bool: return issue.get("severity") == "error")
	_expect_equal(mvp_errors.size(), 0, "Graybox manifest has no structural errors")
	var release_issues := ArtManifestValidator.validate(manifest, false)
	var strict_errors := release_issues.filter(func(issue: Dictionary) -> bool: return issue.get("severity") == "error")
	_expect_equal(strict_errors.size(), manifest.entries.size(), "strict release validation rejects every placeholder")


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, var_to_str(actual), var_to_str(expected)])


func _expect_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s (actual=%f expected=%f)" % [message, actual, expected])


func _report_has_code(report: ValidationReport, code: StringName) -> bool:
	if report == null:
		return false
	for issue: ValidationIssue in report.issues:
		if issue.code == code:
			return true
	return false
