extends SceneTree
## 真实 XLSX 读入、规则副本和判定联动；不改交付表或玩家存档。
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var snapshot := PlanningParameters.read(PlanningParameters.WORKBOOK_PATH)
	check(snapshot.errors.is_empty(), str(snapshot.errors))
	check(snapshot.values.size() == JSON.parse_string(FileAccess.get_file_as_string(PlanningParameters.SCHEMA_PATH)).size(), "全部策划字段读入")
	var base := load(PlanningParameters.DEFAULT_RULES) as GameplayRuleSet
	var configured := PlanningParameters.rules_copy(base, snapshot)
	check(ChartCompiler.rules_hash(base) == ChartCompiler.rules_hash(configured), "交付默认表不得改变原型规则")
	var flow_changed:=snapshot.duplicate(true)
	flow_changed.values["boundary/flow_speed_px_sec"]=72.0
	flow_changed.values["boundary/flow_strength"]=.8
	flow_changed.values["boundary/vortex_width_px"]=128.0
	flow_changed.values["boundary/vortex_flow_speed_px_sec"]=110.0
	flow_changed.values["boundary/vortex_beat_push_px"]=0.0
	check(ChartCompiler.rules_hash(configured)==ChartCompiler.rules_hash(PlanningParameters.rules_copy(base,flow_changed)),"水流表现参数不进入 Replay 规则摘要")
	var flow_style:=BoundaryMotionStyle.new();PlanningParameters.apply_values(flow_style,"boundary",flow_changed)
	check(flow_style.flow_speed_px_sec==72.0 and is_equal_approx(flow_style.flow_strength,.8),"工作簿水流参数装入表现副本")
	check(flow_style.vortex_width_px==128.0 and flow_style.vortex_flow_speed_px_sec==110.0 and flow_style.vortex_beat_push_px==0.0,"卷流几何、流速和拍点开关装入表现副本")
	for entry: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(PlanningParameters.SCHEMA_PATH)):
		var actual: Variant
		if entry.target == "rules": actual = base.get(entry.key)
		elif entry.target == "boundary": actual = load("res://content/presentation/boundary_motion_style.tres").get(entry.key)
		elif entry.target == "actors": actual = StageVisualTheme.new().get(entry.key)
		elif entry.target == "boss":
			# 审看资源直接读取脚本默认，不创建尚未装配的表现节点。
			actual=load("res://"+entry.source).get_property_default_value(entry.key)
		else:
			var parts: PackedStringArray = entry.target.split(":")
			var pet := load("res://content/pets/pet_%s.tres" % parts[1]) as PetDefinition
			actual = pet.effect(parts[2] == "advanced").get(entry.key)
		check(actual == entry.default if entry.type == "string" else is_equal_approx(float(actual), float(entry.default)), "基线与实际资源一致：" + entry.key)
	var actor_theme := StageVisualTheme.new()
	PlanningParameters.apply_values(actor_theme, "actors", snapshot)
	check(actor_theme.death_movement_layer_key == snapshot.values["actors/death_movement_layer_key"], "参考层文本从实际 XLSX 读入")
	var actor_changed := snapshot.duplicate(true)
	actor_changed.values["actors/walk_period_sec"] = 2.4
	check(ChartCompiler.rules_hash(PlanningParameters.rules_copy(base, actor_changed)) == ChartCompiler.rules_hash(configured), "步频不进入 Replay 规则摘要")
	var changed := snapshot.duplicate(true)
	changed.values["rules/tap_miss_damage"] = 10
	changed.values["rules/perfect_window_ms"] = 60
	var variant := PlanningParameters.rules_copy(base, changed)
	check(base.tap_miss_damage == 20 and configured.perfect_window_ms == 45, "资源缓存与前一局副本不被覆盖")
	check(ChartCompiler.rules_hash(variant) != ChartCompiler.rules_hash(base), "规则变化进入现有 Replay 规则摘要")
	var health := HealthEngine.new()
	health.configure(variant)
	health.apply_damage(DamageRecord.create("a", "group", 1000, variant.tap_miss_damage))
	health.apply_damage(DamageRecord.create("b", "group", 2000, variant.tap_miss_damage))
	check(health.soul_fire == 90, "新伤害生效且同组不重复扣血")
	var event := PhysicalInputEvent.new()
	event.kind = GameplayTypes.PhysicalInputKind.GAMEPAD_LEFT_STICK_MOVED
	event.axis_value = Vector2(0.25, 0)
	check(InputSemanticConverter.to_tuning_control(event, 0.3).control_vector == Vector2.ZERO, "新死区内归零")
	check(is_equal_approx(InputSemanticConverter.to_tuning_control(event, 0.2).control_vector.x, 0.0625), "保留原死区默认响应")
	var malformed := _copy_with_value("bad.xlsx", 'r="B6"', "-1")
	check(not PlanningParameters.read(malformed).errors.is_empty(), "非法数字报告错误")
	var edited := _copy_with_value("edited.xlsx", 'r="B6"', "50")
	check(PlanningParameters.read(edited).values.get("rules/perfect_window_ms") == 50, "保存后的实际 XLSX 重新读取")
	var inconsistent := snapshot.duplicate(true)
	inconsistent.values["rules/perfect_window_ms"] = 200
	check(not PlanningParameters.validate_rules(PlanningParameters.rules_copy(base, inconsistent)).is_empty(), "窗口交叉检查")
	check(PlanningParameters.read("res://builds/planning/absent.xlsx").values.is_empty(), "未提供外部表时沿用原资源")
	var strings: Array[String] = ["rules", "perfect_window_ms"]
	var xml := '<worksheet><sheetData><row r="6"><c r="H6" t="s"><v>0</v></c><c r="I6" t="s"><v>1</v></c><c r="B6"><v>55</v></c></row></sheetData></worksheet>'
	var decoded := PlanningParameters._rows(xml.to_utf8_buffer(), strings)
	check(decoded.size() == 1 and decoded[0].H == "rules" and decoded[0].B == "55", "无前缀 XML 与共享字符串")
	xml = '<worksheet><sheetData><row r="8"><c r="H8" t="inlineStr"><is><t>rules</t></is></c><c r="B8"><f>40+5</f><v>45</v></c></row></sheetData></worksheet>'
	decoded = PlanningParameters._rows(xml.to_utf8_buffer(), [])
	check(decoded.size() == 1 and decoded[0].H == "rules" and decoded[0].B_formula, "内联字符串与公式标记")
	await _test_stage_and_preview()
	print("Planning parameters: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _copy_with_value(name: String, cell: String, value: String) -> String:
	var source := ZIPReader.new()
	source.open(PlanningParameters.WORKBOOK_PATH)
	var destination := "res://builds/planning/" + name
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	var target := ZIPPacker.new()
	target.open(destination)
	for file in source.get_files():
		var bytes := source.read_file(file)
		if file == "xl/worksheets/sheet2.xml":
			var xml := bytes.get_string_from_utf8()
			var start := xml.find(cell)
			var number_start := xml.find("<x:v>", start) + 5
			var number_end := xml.find("</x:v>", number_start)
			xml = xml.substr(0, number_start) + value + xml.substr(number_end)
			bytes = xml.to_utf8_buffer()
		target.start_file(file); target.write_file(bytes); target.close_file()
	target.close(); source.close()
	return destination

func _test_stage_and_preview() -> void:
	var expected := PlanningParameters.read()
	var source := load("res://content/stages/s02/stage_definition.tres") as StageDefinition
	check(source.resolve_dependencies_sync(), "正式关依赖可解析")
	var stage = load("res://scenes/stage/stage_root.tscn").instantiate()
	stage.auto_start_initial_stage = false; stage.initial_stage = null
	root.add_child(stage)
	stage.set_pet(load("res://content/pets/pet_gui_jin_yang.tres"), false)
	check(stage.load_stage(source, false), "正式 StageRoot 装入策划表")
	check(stage.stage_session.rule_set.perfect_window_ms == int(expected.values.get("rules/perfect_window_ms",45)), "正式判定使用本次保存的窗口")
	check(stage.stage_session.rule_set != source.rule_set and source.rule_set.perfect_window_ms == 45, "关卡原资源不被覆盖")
	check(stage.gameplay_coordinator.simulation.pet_effect.damage_reduction == 0.1, "装备形态读取策划随从数值")
	var rules: GameplayRuleSet = stage.stage_session.rule_set
	var chart := DomainFixtureFactory.base_chart("planning", 1920)
	var note := NoteEvent.new(); note.event_id = "tap"; note.tick = 960
	chart.note_events.append(note)
	var simulation := GameplaySimulation.new()
	var compiled := ChartCompiler.compile(chart, rules)
	simulation.configure(compiled.compiled, rules, true)
	simulation.accept_input(SemanticInputSample.create(1050000, 0, GameplayTypes.SemanticInputKind.LIFE_A_PRESSED))
	check(simulation.judgments.size() == 1, "真实判定接受 50 ms 延后输入")
	if not simulation.judgments.is_empty():
		check(simulation.judgments[0].grade == (GameplayTypes.JudgmentGrade.PERFECT if rules.perfect_window_ms >= 50 else GameplayTypes.JudgmentGrade.GOOD), "Excel 窗口改变真实判档")
	stage.teardown(); stage.queue_free()
	await process_frame
	var document := StudioDocument.new()
	StudioProjectIO.open_project("res://tests/editor/fixtures/tuning/song.json", document)
	var viewport := SubViewport.new(); viewport.size = Vector2i(640,360); root.add_child(viewport)
	var preview = load("res://src/tools/chart_studio/preview_session.gd").new(); root.add_child(preview)
	check(preview.load_preview(ChartProjectLoader.make_stage(document.song, document.chart()), viewport), "正式内嵌预览读取同一表")
	check(preview.stage_root.stage_session.rule_set.perfect_window_ms == rules.perfect_window_ms, "正式关与内嵌预览参数相同")
	preview.clear_preview(); preview.queue_free(); viewport.queue_free()
	await process_frame
