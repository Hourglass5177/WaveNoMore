extends SceneTree

## 实体声波交互的玩法逻辑层测试，可直接用下面的命令运行：
## Godot --headless --path Game -s res://tests/unit/domain/test_wave_interaction.gd
## 这里验证解析接触时间，不依赖画面帧率或 Godot 物理碰撞。

## 生钟波源在 1920×1080 设计画布中的像素坐标。
const LIFE_ORIGIN := Vector2(350.0, 280.0)
## 生音符经过中央判定点时的设计画布像素坐标。
const LIFE_CUE := Vector2(960.0, 540.0)
## 生音符进入画面时的设计画布像素坐标。
const LIFE_SPAWN := Vector2(2040.0, 220.0)
## 波前传播速度，单位为设计画布像素/秒。
const WAVE_SPEED_PX_SEC: float = 2400.0
## 音符从出生点运行到中央判定点的时间，单位为秒。
const APPROACH_DURATION_SEC: float = 2.25
## 贝塞尔路径靠画面外侧的控制柄长度，单位为设计画布像素。
const CURVE_OUTER_BEND_PX: float = 220.0
## 贝塞尔路径靠中央判定点的控制柄长度，单位为设计画布像素。
const CURVE_CENTER_HANDLE_PX: float = 360.0

## 整个脚本累计的失败文本，最终统一输出并转成进程退出码。
var _failures := PackedStringArray()
## 已执行断言总数，用于确认边界、到达和确定性用例没有被跳过。
var _checks: int = 0


func _init() -> void:
	var result: Dictionary = run()
	quit(0 if bool(result["ok"]) else 1)


func run() -> Dictionary:
	_test_contact_boundary_is_exact()
	_test_invalid_wave_never_contacts()
	_test_unopposed_note_arrives_at_actor()
	_test_one_wave_can_bind_at_most_one_target()
	_test_reset_clears_transient_state()
	_test_step_size_determinism()
	var passed: bool = _failures.is_empty()
	if passed:
		print("WAVE INTERACTION TESTS: %d checks passed." % _checks)
	else:
		printerr("WAVE INTERACTION TESTS FAILED: %d/%d checks failed." % [_failures.size(), _checks])
		for failure: String in _failures:
			printerr("  - " + failure)
	return {"ok": passed, "checks": _checks, "failures": Array(_failures)}


func _test_contact_boundary_is_exact() -> void:
	# 在接触时刻前 1 微秒不应触发，恰好到达时才触发。
	var compiled: CompiledChart = _compile(DomainFixtureFactory.one_tap_chart(), "contact boundary fixture compiles")
	if compiled == null:
		return
	var rules := DomainFixtureFactory.rules()
	var note: Dictionary = compiled.notes[0]
	var launch_us: int = int(note["start_us"])
	var expected_contact_us: int = _expected_life_contact_us(launch_us, launch_us)
	var engine := WaveInteractionEngine.new()
	engine.configure(compiled, rules)
	engine.advance_to(launch_us, false)
	engine.launch(_life_press(launch_us, 7), true, GameplayTypes.InputOwner.NOTE, note)

	var launches: Array[Dictionary] = engine.drain_launches()
	_expect_equal(launches.size(), 1, "a valid strike emits exactly one wave launch")
	if not launches.is_empty():
		_expect(bool(launches[0].get("valid", false)), "the bound ordinary strike is a valid wave")
		_expect_equal(str(launches[0].get("bound_note_id", "")), "tap_only", "the valid wave exposes its single bound note")
		_expect_equal(int(launches[0].get("contact_us", -1)), expected_contact_us, "launch announces the analytic contact time")

	engine.advance_to(expected_contact_us - 1, true)
	_expect_equal(engine.drain_contacts().size(), 0, "one microsecond before contact remains empty")
	engine.advance_to(expected_contact_us, true)
	var contacts: Array[Dictionary] = engine.drain_contacts()
	_expect_equal(contacts.size(), 1, "contact boundary is inclusive")
	if not contacts.is_empty():
		var contact: Dictionary = contacts[0]
		_expect_equal(str(contact.get("note_id", "")), "tap_only", "contact identifies the bound note")
		_expect_equal(int(contact.get("contact_us", -1)), expected_contact_us, "contact records canonical time, not frame time")
		var elapsed_from_cue_sec: float = float(expected_contact_us - launch_us) / 1_000_000.0
		var expected_position: Vector2 = LIFE_CUE + (LIFE_ORIGIN - LIFE_CUE).normalized() * _life_note_speed_px_sec() * elapsed_from_cue_sec
		_expect_vector_close(contact.get("position", Vector2.ZERO), expected_position, 0.001, "contact occurs at the analytic meeting point")

	engine.force_finish()
	_expect_equal(engine.drain_arrivals().size(), 0, "a contacted Tap never also arrives at the actor")


func _test_invalid_wave_never_contacts() -> void:
	var compiled: CompiledChart = _compile(DomainFixtureFactory.one_tap_chart(), "invalid-wave fixture compiles")
	if compiled == null:
		return
	var rules := DomainFixtureFactory.rules()
	var note: Dictionary = compiled.notes[0]
	var launch_us: int = int(note["start_us"])
	var engine := WaveInteractionEngine.new()
	engine.configure(compiled, rules)
	engine.advance_to(launch_us, false)
	# 乱按产生的灰波可以继续显示，但不能占有任何玩法目标。
	engine.launch(_life_press(launch_us, 11), false, GameplayTypes.InputOwner.NONE, note)
	var launches: Array[Dictionary] = engine.drain_launches()
	_expect_equal(launches.size(), 1, "a grey strike still emits a visible launch")
	if not launches.is_empty():
		_expect(not bool(launches[0].get("valid", true)), "grey launch is explicitly invalid")
		_expect_equal(str(launches[0].get("bound_note_id", "")), "", "invalid launch cannot retain a target binding")
		_expect_equal(StringName(launches[0].get("color_role", &"")), &"invalid", "grey launch has a distinct presentation role")

	engine.force_finish()
	_expect_equal(engine.drain_contacts().size(), 0, "grey wave never contacts a gameplay target")
	var arrivals: Array[Dictionary] = engine.drain_arrivals()
	_expect_equal(arrivals.size(), 1, "the unprotected note still arrives after a grey wave")


func _test_unopposed_note_arrives_at_actor() -> void:
	var compiled: CompiledChart = _compile(DomainFixtureFactory.one_tap_chart(), "arrival fixture compiles")
	if compiled == null:
		return
	var rules := DomainFixtureFactory.rules()
	var note: Dictionary = compiled.notes[0]
	var cue_us: int = int(note["start_us"])
	var expected_arrival_us: int = cue_us + roundi(LIFE_CUE.distance_to(LIFE_ORIGIN) / _life_note_speed_px_sec() * 1_000_000.0)
	var engine := WaveInteractionEngine.new()
	engine.configure(compiled, rules)

	engine.advance_to(expected_arrival_us - 1, true)
	_expect_equal(engine.drain_arrivals().size(), 0, "one microsecond before arrival remains empty")
	engine.advance_to(expected_arrival_us, true)
	var arrivals: Array[Dictionary] = engine.drain_arrivals()
	_expect_equal(arrivals.size(), 1, "arrival boundary is inclusive")
	if not arrivals.is_empty():
		var arrival: Dictionary = arrivals[0]
		_expect_equal(str(arrival.get("note_id", "")), "tap_only", "arrival identifies the unresolved note")
		_expect_equal(int(arrival.get("arrival_us", -1)), expected_arrival_us, "arrival records canonical time, not frame time")
		_expect_vector_close(arrival.get("position", Vector2.ZERO), LIFE_ORIGIN, 0.001, "unopposed note reaches the life actor")
	_expect_equal(engine.drain_contacts().size(), 0, "an unopposed arrival has no phantom contact")


func _test_one_wave_can_bind_at_most_one_target() -> void:
	var chart := DomainFixtureFactory.one_tap_chart()
	chart.chart_id = "wave_one_target"
	chart.end_tick = 1920
	var second := NoteEvent.new()
	second.event_id = "tap_second"
	second.tick = 960
	second.kind = GameplayTypes.NoteKind.TAP
	second.affinity = GameplayTypes.Affinity.ZHU
	chart.note_events.append(second)
	var compiled: CompiledChart = _compile(chart, "two-target fixture compiles")
	if compiled == null:
		return
	var rules := DomainFixtureFactory.rules()
	var first: Dictionary = compiled.notes[0]
	var launch_us: int = int(first["start_us"])
	var engine := WaveInteractionEngine.new()
	engine.configure(compiled, rules)
	engine.advance_to(launch_us, false)
	engine.launch(_life_press(launch_us, 19), true, GameplayTypes.InputOwner.NOTE, first)
	var launches: Array[Dictionary] = engine.drain_launches()
	var wave_id: String = str(launches[0].get("wave_id", "")) if not launches.is_empty() else ""
	engine.force_finish()
	var contacts: Array[Dictionary] = engine.drain_contacts()
	var matching_contacts: int = 0
	for contact: Dictionary in contacts:
		if str(contact.get("wave_id", "")) == wave_id:
			matching_contacts += 1
	_expect_equal(matching_contacts, 1, "one wave produces at most one target contact")
	if not contacts.is_empty():
		_expect_equal(str(contacts[0].get("note_id", "")), "tap_only", "wave contacts only its explicit binding")
	var arrivals: Array[Dictionary] = engine.drain_arrivals()
	_expect(arrivals.any(func(item: Dictionary) -> bool: return str(item.get("note_id", "")) == "tap_second"), "unbound second note continues to the actor")


func _test_reset_clears_transient_state() -> void:
	var compiled: CompiledChart = _compile(DomainFixtureFactory.one_tap_chart(), "reset fixture compiles")
	if compiled == null:
		return
	var rules := DomainFixtureFactory.rules()
	var note: Dictionary = compiled.notes[0]
	var engine := WaveInteractionEngine.new()
	engine.configure(compiled, rules)
	engine.launch(_life_press(int(note["start_us"]), 23), true, GameplayTypes.InputOwner.NOTE, note)
	engine.reset()
	_expect_equal(engine.drain_launches().size(), 0, "reset clears undrained launches")
	_expect_equal(engine.drain_contacts().size(), 0, "reset clears undrained contacts")
	_expect_equal(engine.drain_arrivals().size(), 0, "reset clears undrained arrivals")
	var state: Dictionary = engine.snapshot()
	_expect_equal(int(state.get("wave_count", -1)), 0, "reset removes every active wave")


func _test_step_size_determinism() -> void:
	var compiled: CompiledChart = _compile(DomainFixtureFactory.chord_only_chart(), "determinism fixture compiles")
	if compiled == null:
		return
	var at_30: Dictionary = _simulate_paired_waves(compiled, 33_333)
	var at_60: Dictionary = _simulate_paired_waves(compiled, 16_667)
	var at_120: Dictionary = _simulate_paired_waves(compiled, 8_333)
	var irregular: Dictionary = _simulate_paired_waves(compiled, 0, PackedInt64Array([7_000, 11_000, 23_000]))
	_expect_equal(at_30, at_60, "30 and 60 FPS wave outputs match")
	_expect_equal(at_30, at_120, "30 and 120 FPS wave outputs match")
	_expect_equal(at_30, irregular, "irregular frame steps produce the same wave outputs")


func _simulate_paired_waves(
		compiled: CompiledChart,
		fixed_step_us: int,
		irregular_steps: PackedInt64Array = PackedInt64Array()
) -> Dictionary:
	var rules := DomainFixtureFactory.rules()
	var engine := WaveInteractionEngine.new()
	engine.configure(compiled, rules)
	var launch_us: int = int(compiled.notes[0]["start_us"])
	engine.advance_to(launch_us, false)
	var sequence: int = 0
	for note: Dictionary in compiled.notes:
		var kind: int = GameplayTypes.SemanticInputKind.LIFE_PRESSED if int(note["affinity"]) == GameplayTypes.Affinity.ZHU else GameplayTypes.SemanticInputKind.DEATH_PRESSED
		engine.launch(SemanticInputSample.create(launch_us, sequence, kind), true, GameplayTypes.InputOwner.NOTE, note)
		sequence += 1
	var cursor_us: int = launch_us
	var finish_us: int = launch_us + 2_000_000
	var step_index: int = 0
	while cursor_us < finish_us:
		var step_us: int = fixed_step_us
		if not irregular_steps.is_empty():
			step_us = int(irregular_steps[step_index % irregular_steps.size()])
			step_index += 1
		cursor_us = mini(finish_us, cursor_us + step_us)
		engine.advance_to(cursor_us, true)
	engine.force_finish()
	return {
		"launches": engine.drain_launches(),
		"contacts": engine.drain_contacts(),
		"arrivals": engine.drain_arrivals(),
		"snapshot": engine.snapshot(),
	}


func _compile(chart: SongChart, label: String) -> CompiledChart:
	var result: Dictionary = ChartCompiler.compile(chart, DomainFixtureFactory.rules())
	_expect(bool(result.get("ok", false)), label)
	if not bool(result.get("ok", false)):
		return null
	return result.get("compiled") as CompiledChart


func _life_press(timestamp_us: int, sequence: int) -> SemanticInputSample:
	return SemanticInputSample.create(timestamp_us, sequence, GameplayTypes.SemanticInputKind.LIFE_PRESSED)


func _expected_life_contact_us(launch_us: int, cue_us: int) -> int:
	var distance_px: float = LIFE_CUE.distance_to(LIFE_ORIGIN)
	var note_speed_px_sec: float = _life_note_speed_px_sec()
	return roundi(
		(distance_px * 1_000_000.0 + WAVE_SPEED_PX_SEC * float(launch_us) + note_speed_px_sec * float(cue_us))
		/ (WAVE_SPEED_PX_SEC + note_speed_px_sec)
	)


func _life_note_speed_px_sec() -> float:
	var profile: Dictionary = NoteApproachPath.build_profile(
		LIFE_SPAWN,
		LIFE_CUE,
		LIFE_ORIGIN,
		CURVE_OUTER_BEND_PX,
		CURVE_CENTER_HANDLE_PX
	)
	return NoteApproachPath.length(profile) / APPROACH_DURATION_SEC


func _expect_vector_close(actual: Variant, expected: Vector2, tolerance: float, message: String) -> void:
	var actual_vector: Vector2 = actual if actual is Vector2 else Vector2(INF, INF)
	_expect(actual_vector.distance_to(expected) <= tolerance, "%s (actual=%s expected=%s)" % [message, actual_vector, expected])


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	_expect(actual == expected, "%s (actual=%s expected=%s)" % [message, var_to_str(actual), var_to_str(expected)])
