class_name PlanningParameters
extends RefCounted
## 策划表在装载时读取，一局内使用独立规则副本。不会在玩法帧内访问磁盘。
const SCHEMA_PATH := "res://content/rules/planning_parameters.json"
const WORKBOOK_PATH := "res://outputs/planning/策划参数.xlsx"
const DEFAULT_RULES := "res://content/rules/default_gameplay_rules.tres"

static func workbook_path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--planning-sheet="): return argument.trim_prefix("--planning-sheet=")
	if OS.has_feature("editor"): return WORKBOOK_PATH
	return OS.get_executable_path().get_base_dir().path_join("planning/策划参数.xlsx")

static func read(path: String = "") -> Dictionary:
	if path.is_empty(): path = workbook_path()
	var result := {"values": {}, "errors": [], "path": path}
	if not FileAccess.file_exists(path): return result
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		result.errors.append("无法读取策划表：" + path)
		return result
	var shared: Array[String] = []
	if zip.file_exists("xl/sharedStrings.xml"):
		var parser := XMLParser.new()
		parser.open_buffer(zip.read_file("xl/sharedStrings.xml"))
		var item := ""
		var in_text := false
		while parser.read() == OK:
			if parser.get_node_type() == XMLParser.NODE_ELEMENT:
				if parser.get_node_name().split(":")[-1] == "si": item = ""
				in_text = parser.get_node_name().split(":")[-1] == "t"
			elif parser.get_node_type() == XMLParser.NODE_TEXT and in_text: item += parser.get_node_data()
			elif parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
				in_text = false
				if parser.get_node_name().split(":")[-1] == "si": shared.append(item)
	var schema: Dictionary = {}
	for entry: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(SCHEMA_PATH)):
		schema[entry.target + "/" + entry.key] = entry
	for file in zip.get_files():
		if not file.begins_with("xl/worksheets/") or not file.ends_with(".xml"): continue
		for cells: Dictionary in _rows(zip.read_file(file), shared):
			var target := str(cells.get("H", ""))
			if target not in ["rules", "boundary"] and not target.begins_with("pet:"): continue
			var id := target + "/" + str(cells.get("I", ""))
			if not schema.has(id):
				result.errors.append("未知策划字段：" + id)
				continue
			var entry: Dictionary = schema[id]
			var value := str(cells.get("B", ""))
			if result.values.has(id): result.errors.append("策划字段重复：" + id)
			elif cells.get("B_formula", false): result.errors.append(entry.name + "：当前值请直接填写数字，不使用公式")
			elif not value.is_valid_float(): result.errors.append(entry.name + "：当前值缺失或不是数字")
			elif not is_finite(float(value)) or float(value) < float(entry.minimum) or float(value) > float(entry.maximum):
				result.errors.append("%s：允许范围 %s～%s" % [entry.name, entry.minimum, entry.maximum])
			elif entry.type in ["int", "bool"] and float(value) != floorf(float(value)):
				result.errors.append(entry.name + "：请填写整数")
			else:
				result.values[id] = bool(int(value)) if entry.type == "bool" else (int(value) if entry.type == "int" else float(value))
	zip.close()
	if result.values.size() != schema.size(): result.errors.append("策划表需要保留全部 %d 个参数行" % schema.size())
	if result.errors.is_empty():
		result.errors.append_array(validate_rules(rules_copy(load(DEFAULT_RULES), result)))
	return result

static func _rows(bytes: PackedByteArray, shared: Array[String]) -> Array[Dictionary]:
	# 只读取单元格值，兼容 Excel/WPS 的共享字符串及内联字符串；格式、批注不参与配置。
	var parser := XMLParser.new()
	if parser.open_buffer(bytes) != OK: return []
	var result: Array[Dictionary] = []
	var cells: Dictionary = {}
	var column := ""
	var cell_type := ""
	var value := ""
	var in_value := false
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				match parser.get_node_name().split(":")[-1]:
					"row": cells = {}
					"c":
						column = parser.get_named_attribute_value_safe("r").rstrip("0123456789")
						cell_type = parser.get_named_attribute_value_safe("t")
						value = ""
					"v", "t": in_value = true
					"f": cells[column + "_formula"] = true
			XMLParser.NODE_TEXT:
				if in_value: value += parser.get_node_data()
			XMLParser.NODE_ELEMENT_END:
				match parser.get_node_name().split(":")[-1]:
					"v", "t": in_value = false
					"c":
						cells[column] = shared[int(value)] if cell_type == "s" and int(value) < shared.size() else value
					"row": result.append(cells)
	return result

static func apply_values(resource: Resource, target: String, snapshot: Dictionary) -> void:
	for id: String in snapshot.values:
		if id.begins_with(target + "/"): resource.set(id.trim_prefix(target + "/"), snapshot.values[id])

static func rules_copy(base: GameplayRuleSet, snapshot: Dictionary) -> GameplayRuleSet:
	var rules := base.duplicate(true) as GameplayRuleSet
	apply_values(rules, "rules", snapshot)
	return rules

static func default_rules() -> GameplayRuleSet:
	var snapshot := read()
	var base := load(DEFAULT_RULES) as GameplayRuleSet
	if not snapshot.errors.is_empty():
		push_error("；".join(snapshot.errors))
		return base
	return rules_copy(base, snapshot)

static func validate_rules(rules: GameplayRuleSet) -> Array[String]:
	var errors: Array[String] = []
	if not (rules.perfect_window_ms <= rules.good_window_ms and rules.good_window_ms <= rules.pass_window_ms and rules.pass_window_ms <= rules.miss_window_ms):
		errors.append("判定窗口须满足 Perfect ≤ Good ≤ Pass ≤ Miss")
	if not (rules.tuning_min_frequency_hz < rules.tuning_max_frequency_hz and rules.tuning_min_frequency_hz <= rules.tuning_base_frequency_hz and rules.tuning_base_frequency_hz <= rules.tuning_max_frequency_hz):
		errors.append("频率须满足 最低 ≤ 基准 ≤ 最高，且最低小于最高")
	if not (rules.tuning_pass_completion <= rules.tuning_good_completion and rules.tuning_good_completion <= rules.tuning_perfect_completion):
		errors.append("调频完成度须满足 Pass ≤ Good ≤ Perfect")
	return errors
