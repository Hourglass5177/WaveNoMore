extends RefCounted

## 真实内容包的轻量回归：确保五张测试关职责单一、可加载，并能进入正式编译与 Replay 流程。

const STAGE_IDS: PackedStringArray = ["s01", "s02", "s03", "s04", "s05"]
const EXPECTED_END_TICKS: PackedInt32Array = [23040, 49920, 49920, 61440, 76800]

var _checks: int = 0
var _failures: PackedStringArray = []


func run() -> Dictionary:
	_test_catalog()
	_test_shared_stage_contract()
	_test_specialized_tracks()
	_test_tuning_authorship()
	_test_perfect_replays()
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


func _test_catalog() -> void:
	var catalog := load("res://content/catalogs/mvp_catalog.tres") as ContentCatalogData
	_expect(catalog != null, "MVP content catalog loads")
	if catalog == null:
		return
	var actual_ids: PackedStringArray = []
	for stage: StageDefinition in catalog.stages:
		if stage != null:
			actual_ids.append(stage.stage_id)
	_expect_equal(actual_ids, STAGE_IDS, "catalog explicitly registers the five test stages in order")


func _test_shared_stage_contract() -> void:
	for index: int in STAGE_IDS.size():
		var stage_id: String = STAGE_IDS[index]
		var stage := _load_stage(stage_id)
		if stage == null:
			continue
		_expect(stage.resolve_dependencies_sync(ResourceLoader.CACHE_MODE_IGNORE), "%s resolves all lazy dependencies" % stage_id)
		if not stage.dependencies_resolved():
			continue
		_expect_equal(stage.stage_id, stage_id, "%s keeps its stable stage ID" % stage_id)
		_expect_equal(stage.order_index, index + 1, "%s keeps its selection order" % stage_id)
		_expect(stage.unlocked_by_default, "%s is immediately selectable for testing" % stage_id)
		_expect(stage.debug_nonlethal, "%s allows health to fall below zero without ending the test" % stage_id)
		_expect_equal(stage.chart.schema_version, SongChart.CURRENT_SCHEMA_VERSION, "%s uses the current chart schema" % stage_id)
		_expect_equal(stage.chart.ppq, 480, "%s uses PPQ 480" % stage_id)
		_expect_equal(stage.chart.end_tick, EXPECTED_END_TICKS[index], "%s has the planned test duration" % stage_id)
		_expect_equal(stage.song.first_beat_offset_sec, 2.0, "%s keeps a two-second count-in" % stage_id)
		_expect_equal(stage.chart.tempo_events.size(), 1, "%s has one constant tempo event" % stage_id)
		_expect_equal(stage.chart.tempo_events[0].bpm, 120.0, "%s runs at 120 BPM" % stage_id)
		_expect_equal(stage.chart.meter_events.size(), 1, "%s has one meter event" % stage_id)
		_expect(stage.chart.meter_events[0].numerator == 4 and stage.chart.meter_events[0].denominator == 4, "%s runs in 4/4" % stage_id)
		_expect_equal(stage.chart.rapid_regions.size(), 0, "%s contains no Rapid content in this prototype pass" % stage_id)
		_expect(stage.reward.pet == null, "%s grants no test-stage pet" % stage_id)
		_expect(not stage.reward.fc_grants_base_pet and not stage.reward.ap_grants_advanced_pet, "%s has no FC/AP reward side effects" % stage_id)
		var authored_duration_sec := stage.song.fallback_duration_sec - stage.song.first_beat_offset_sec
		var chart_duration_sec := float(stage.chart.end_tick) / 960.0
		_expect(authored_duration_sec >= chart_duration_sec, "%s click-track duration covers the whole chart" % stage_id)
		var report := ChartValidator.validate(stage.chart, stage.rule_set, int(round(authored_duration_sec * 1_000_000.0)))
		_expect(not report.has_errors(), "%s passes the shared chart contract: %s" % [stage_id, JSON.stringify(report.to_array())])


func _test_specialized_tracks() -> void:
	var empty := _resolved_stage("s01")
	var taps := _resolved_stage("s02")
	var holds := _resolved_stage("s03")
	var tuning := _resolved_stage("s04")
	var combined := _resolved_stage("s05")
	if empty != null:
		_expect(empty.chart.note_events.is_empty() and empty.chart.tuning_sliders.is_empty(), "s01 is genuinely empty gameplay space")
	if taps != null:
		_expect(taps.chart.note_events.size() >= 60, "s02 is long enough to exercise repeated Tap play")
		_expect(taps.chart.note_events.all(func(note: NoteEvent) -> bool: return note.kind == GameplayTypes.NoteKind.TAP), "s02 contains Tap notes only")
		_expect(taps.chart.tuning_fields.is_empty() and taps.chart.tuning_sliders.is_empty(), "s02 contains no tuning")
	if holds != null:
		_expect(holds.chart.note_events.size() >= 40, "s03 is long enough to exercise repeated Hold play")
		_expect(holds.chart.note_events.all(func(note: NoteEvent) -> bool: return note.kind == GameplayTypes.NoteKind.HOLD), "s03 contains Hold notes only")
		_expect(holds.chart.note_events.all(func(note: NoteEvent) -> bool: return not note.tail_requires_release), "every s03 Hold ignores release timing")
		_expect(holds.chart.tuning_fields.is_empty() and holds.chart.tuning_sliders.is_empty(), "s03 contains no tuning")
	if tuning != null:
		_expect(tuning.chart.note_events.is_empty(), "s04 contains no Tap or Hold notes")
		_expect(not tuning.chart.tuning_sliders.is_empty(), "s04 contains authored rotary sliders")
	if combined != null:
		var has_tap := combined.chart.note_events.any(func(note: NoteEvent) -> bool: return note.kind == GameplayTypes.NoteKind.TAP)
		var has_hold := combined.chart.note_events.any(func(note: NoteEvent) -> bool: return note.kind == GameplayTypes.NoteKind.HOLD)
		_expect(has_tap and has_hold and not combined.chart.tuning_sliders.is_empty(), "s05 combines Tap, Hold and Tuning")
		_expect(combined.chart.note_events.filter(func(note: NoteEvent) -> bool: return note.kind == GameplayTypes.NoteKind.HOLD).all(func(note: NoteEvent) -> bool: return not note.tail_requires_release), "s05 Hold notes also ignore release timing")


func _test_tuning_authorship() -> void:
	for stage_id: String in ["s04", "s05"]:
		var stage := _resolved_stage(stage_id)
		if stage == null:
			continue
		var rules: GameplayRuleSet = stage.rule_set
		var frequency_range_hz: float = rules.tuning_max_frequency_hz - rules.tuning_min_frequency_hz
		var base_value: float = inverse_lerp(
			rules.tuning_min_frequency_hz,
			rules.tuning_max_frequency_hz,
			rules.tuning_base_frequency_hz
		)
		_expect_near(rules.tuning_min_frequency_hz, 1.0, 0.000001, "%s uses the calmer 1 Hz lower bound" % stage_id)
		_expect_near(rules.tuning_base_frequency_hz, 3.0, 0.000001, "%s uses the calmer 3 Hz carrier" % stage_id)
		_expect_near(rules.tuning_max_frequency_hz, 7.0, 0.000001, "%s reaches the visibly denser 7 Hz upper bound" % stage_id)
		_expect_near(rules.tuning_hz_per_revolution, 32.0, 0.000001, "%s keeps the intended free-tuning sensitivity" % stage_id)
		var groups: Dictionary = {}
		var sliders_by_affinity: Dictionary = {}
		var sliders_by_field_and_affinity: Dictionary = {}
		var has_full_span_climax: bool = false
		for slider: TuningSliderEvent in stage.chart.tuning_sliders:
			var is_authored_link: bool = stage_id == "s04" and slider.event_id.contains("_link_")
			if is_authored_link:
				_expect_equal(slider.traversal_ticks, 960, "%s/%s uses a two-beat linked traversal" % [stage_id, slider.event_id])
				_expect_equal(slider.tick % 960, 0, "%s/%s starts on a half-bar pulse" % [stage_id, slider.event_id])
			else:
				_expect(slider.traversal_ticks in [1920, 3840], "%s/%s uses a four- or eight-beat traversal" % [stage_id, slider.event_id])
				_expect_equal(slider.tick % 1920, 0, "%s/%s starts on a bar downbeat" % [stage_id, slider.event_id])
			_expect(slider.start_value >= 0.0 and slider.start_value <= 1.0 and slider.end_value >= 0.0 and slider.end_value <= 1.0, "%s/%s keeps normalized frequency endpoints" % [stage_id, slider.event_id])
			var span_hz: float = absf(slider.end_value - slider.start_value) * frequency_range_hz
			if is_authored_link:
				_expect_near(span_hz, 1.0, 0.00001, "%s/%s uses a compact 1 Hz linked arc" % [stage_id, slider.event_id])
			elif is_equal_approx(span_hz, 4.0):
				has_full_span_climax = true
				_expect_near(span_hz, 4.0, 0.00001, "%s/%s uses the 4 Hz / 45-degree climax span" % [stage_id, slider.event_id])
				_expect_equal(slider.traversal_ticks, 3840, "%s/%s gives the long span eight beats" % [stage_id, slider.event_id])
			else:
				_expect_near(span_hz, 2.0, 0.00001, "%s/%s uses the ordinary 2 Hz span" % [stage_id, slider.event_id])
			if not sliders_by_affinity.has(slider.affinity):
				sliders_by_affinity[slider.affinity] = []
			(sliders_by_affinity[slider.affinity] as Array).append(slider)
			var field_side_key: String = "%s:%d" % [slider.field_id, slider.affinity]
			if not sliders_by_field_and_affinity.has(field_side_key):
				sliders_by_field_and_affinity[field_side_key] = []
			(sliders_by_field_and_affinity[field_side_key] as Array).append(slider)
			if not slider.group_id.is_empty():
				if not groups.has(slider.group_id):
					groups[slider.group_id] = []
				groups[slider.group_id].append(slider)
		_expect(has_full_span_climax, "%s contains at least one clearly larger 4 Hz climax slider" % stage_id)
		for affinity: Variant in sliders_by_affinity:
			var side_sliders: Array = sliders_by_affinity[affinity]
			side_sliders.sort_custom(func(a: TuningSliderEvent, b: TuningSliderEvent) -> bool: return a.tick < b.tick)
			for index: int in range(1, side_sliders.size()):
				var previous: TuningSliderEvent = side_sliders[index - 1]
				var current: TuningSliderEvent = side_sliders[index]
				var previous_end_tick: int = previous.tick + previous.traversal_ticks * previous.traversal_count
				var is_authored_link: bool = stage_id == "s04" and current.event_id.contains("_link_")
				var minimum_gap_ticks: int = 0 if is_authored_link else 480
				_expect(current.tick - previous_end_tick >= minimum_gap_ticks, "%s keeps intentional same-side slider spacing" % stage_id)
		# 每个独立场域从基频起步；同一场域的后续滑条从上一条真实终点继续，
		# 这样加密练习不会在两条之间无提示跳频。
		for field_side_key: String in sliders_by_field_and_affinity:
			var field_sliders: Array = sliders_by_field_and_affinity[field_side_key]
			field_sliders.sort_custom(func(a: TuningSliderEvent, b: TuningSliderEvent) -> bool: return a.tick < b.tick)
			_expect_near((field_sliders[0] as TuningSliderEvent).start_value, base_value, 0.000001, "%s/%s starts its field at base frequency" % [stage_id, field_side_key])
			for index: int in range(1, field_sliders.size()):
				var previous: TuningSliderEvent = field_sliders[index - 1]
				var current: TuningSliderEvent = field_sliders[index]
				var previous_terminal: float = previous.start_value if previous.traversal_count % 2 == 0 else previous.end_value
				_expect_near(current.start_value, previous_terminal, 0.000001, "%s/%s continues from the previous frequency endpoint" % [stage_id, current.event_id])
		for group_id: String in groups:
			var members: Array = groups[group_id]
			_expect_equal(members.size(), 2, "%s/%s owns exactly one slider per bell" % [stage_id, group_id])
			if members.size() == 2:
				_expect((members[0] as TuningSliderEvent).affinity != (members[1] as TuningSliderEvent).affinity, "%s/%s pairs Life and Death" % [stage_id, group_id])
		for manifestation: SuManifestationEvent in stage.chart.su_manifestations:
			_expect(groups.has(manifestation.group_id), "%s/%s references a paired slider group" % [stage_id, manifestation.event_id])
	if _resolved_stage("s04") != null:
		var chart: SongChart = _resolved_stage("s04").chart
		_expect(chart.su_manifestations.all(func(event: SuManifestationEvent) -> bool: return event.tick >= chart.end_tick / 2), "s04 introduces Su only in its latter half")
		_expect(chart.tuning_sliders.any(func(slider: TuningSliderEvent) -> bool: return slider.group_id.is_empty()), "s04 begins with independent single-bell sliders")
		_expect(chart.tuning_sliders.any(func(slider: TuningSliderEvent) -> bool: return slider.traversal_count > 1), "s04 includes visible reversal practice")
		var early_single_sliders: Array[TuningSliderEvent] = []
		var later_grouped_sliders: Array[TuningSliderEvent] = []
		for slider: TuningSliderEvent in chart.tuning_sliders:
			if slider.group_id.is_empty():
				early_single_sliders.append(slider)
			else:
				later_grouped_sliders.append(slider)
		_expect(early_single_sliders.size() >= 4, "s04 includes initial and return practice for both individual bells")
		for initial_id: String in ["s04_life_horizontal", "s04_death_horizontal"]:
			var matches: Array[TuningSliderEvent] = early_single_sliders.filter(func(slider: TuningSliderEvent) -> bool: return slider.event_id == initial_id)
			_expect_equal(matches.size(), 1, "s04 contains the %s first lesson" % initial_id)
			if not matches.is_empty():
				_expect_equal(matches[0].traversal_ticks, 1920, "s04/%s keeps an unhurried four-beat first lesson" % initial_id)
				_expect_near(absf(matches[0].end_value - matches[0].start_value) * 6.0, 2.0, 0.00001, "s04/%s teaches one ordinary 2 Hz arc" % initial_id)
		_expect(later_grouped_sliders.any(func(slider: TuningSliderEvent) -> bool: return slider.traversal_ticks == 1920), "s04 later combinations introduce four-beat ordinary arcs")
		_expect(later_grouped_sliders.any(func(slider: TuningSliderEvent) -> bool: return is_equal_approx(absf(slider.end_value - slider.start_value) * 6.0, 4.0)), "s04 retains one clearly longer 4 Hz contrast arc")
		var linked_sliders: Array[TuningSliderEvent] = chart.tuning_sliders.filter(func(slider: TuningSliderEvent) -> bool: return slider.event_id.contains("_link_"))
		_expect_equal(linked_sliders.size(), 5, "s04 keeps two short linked chains without restoring the old density spike")


func _test_perfect_replays() -> void:
	for stage_id: String in ["s02", "s03", "s04", "s05"]:
		var stage := _resolved_stage(stage_id)
		if stage == null:
			continue
		var compiled_result := ChartCompiler.compile(stage.chart, stage.rule_set)
		_expect(bool(compiled_result.get("ok", false)), "%s compiles for Replay" % stage_id)
		if not bool(compiled_result.get("ok", false)):
			continue
		var compiled := compiled_result["compiled"] as CompiledChart
		var replay := ReplayRunner.build_perfect_replay(compiled, stage.rule_set)
		var at_60 := ReplayRunner.run(compiled, stage.rule_set, replay, 16_667)
		_expect(bool(at_60.get("ok", false)), "%s Perfect Replay executes" % stage_id)
		if bool(at_60.get("ok", false)):
			var summary := at_60["summary"] as ResultSummary
			_expect(summary.cleared and summary.full_combo and summary.all_perfect, "%s can obtain FC/AP through the real state machines" % stage_id)
		if stage_id in ["s04", "s05"]:
			var at_30 := ReplayRunner.run(compiled, stage.rule_set, replay, 33_333)
			var at_120 := ReplayRunner.run(compiled, stage.rule_set, replay, 8_333)
			_expect_equal(at_30.get("digest", ""), at_60.get("digest", ""), "%s is deterministic between 30 and 60 FPS steps" % stage_id)
			_expect_equal(at_60.get("digest", ""), at_120.get("digest", ""), "%s is deterministic between 60 and 120 FPS steps" % stage_id)


func _test_show_contract() -> void:
	for stage_id: String in STAGE_IDS:
		var stage := _resolved_stage(stage_id)
		if stage == null:
			continue
		var ids: Dictionary = {}
		var previous_tick: int = -1
		for cue: ShowCue in stage.stage_show.cues:
			_expect(cue != null and not cue.event_id.is_empty(), "%s show cue has a stable ID" % stage_id)
			if cue == null:
				continue
			_expect(not ids.has(cue.event_id), "%s show cue ID is unique: %s" % [stage_id, cue.event_id])
			ids[cue.event_id] = true
			_expect(cue.tick >= previous_tick, "%s show cues stay in timeline order" % stage_id)
			previous_tick = cue.tick


func _test_visual_manifest() -> void:
	var manifest := load("res://content/visual/graybox_manifest.tres") as VisualAssetManifest
	_expect(manifest != null, "Graybox visual manifest loads")
	if manifest == null:
		return
	var issues := ArtManifestValidator.validate(manifest, true)
	var errors := issues.filter(func(issue: Dictionary) -> bool: return issue.get("severity") == "error")
	_expect_equal(errors.size(), 0, "Graybox manifest has no structural errors")


func _load_stage(stage_id: String) -> StageDefinition:
	var stage := load("res://content/stages/%s/stage_definition.tres" % stage_id) as StageDefinition
	_expect(stage != null, "%s StageDefinition loads" % stage_id)
	return stage


func _resolved_stage(stage_id: String) -> StageDefinition:
	var stage := _load_stage(stage_id)
	if stage == null:
		return null
	_expect(stage.resolve_dependencies_sync(ResourceLoader.CACHE_MODE_IGNORE), "%s resolves for specialized checks" % stage_id)
	return stage if stage.dependencies_resolved() else null


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, var_to_str(actual), var_to_str(expected)])


func _expect_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	_expect(absf(actual - expected) <= tolerance, "%s (actual=%f expected=%f)" % [message, actual, expected])
