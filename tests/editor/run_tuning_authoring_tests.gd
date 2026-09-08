extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; push_error(label)

func run() -> void:
	var doc := StudioDocument.new(); doc.new_project()
	var life := NoteEvent.new(); life.event_id = "life"; life.kind = GameplayTypes.NoteKind.HOLD; life.tick = 960; life.duration_ticks = 5760
	var death := life.duplicate(true) as NoteEvent; death.event_id = "death"; death.affinity = 1; death.tick = 1440
	doc.execute("双 Hold", [], [life, death])
	var path := ChartEditEvents.new_path(doc.chart(), 0, 1680, 3360); path.event_id = "path"
	var middle := TuningPathPoint.new(); middle.event_id = "middle"; middle.offset_ticks = 720; middle.angle_deg = path.points[1].angle_deg
	path.points[1].angle_deg = path.points[0].angle_deg + 10
	path.points.insert(1, middle)
	doc.execute("Tuning", [], [path])
	var ghost := GhostEvent.new(); ghost.event_id = "ghost"; ghost.tick = 2160; ghost.count = 3; ghost.boss = true
	ChartEditEvents.rebind(doc.chart(), ghost); doc.execute("Ghost", [], [ghost])
	var rules: GameplayRuleSet = load("res://content/rules/default_gameplay_rules.tres")
	check(ChartPathAdapter.validate(doc.chart(), rules).is_empty(), "合法多节点谱")
	var raw := ChartJsonCodec.encode_chart(doc.chart())
	check(raw.format_version == 2 and raw.ghost_events[0].boss, "v2/BOSS")
	raw.tuning_paths[0].points[1]["future_data"] = {"x": 1}
	var decoded := ChartJsonCodec.decode_chart(raw)
	check(decoded.chart != null, "v2 可读取")
	check(ChartJsonCodec.encode_chart(decoded.chart).tuning_paths[0].points[1].future_data.x == 1, "节点未知字段往返")
	var projected := ChartPathAdapter.project(doc.chart(), rules)
	check(projected.tuning_sliders.size() == 2 and projected.su_manifestations.size() == 1, "临时投影保留事件")
	check(is_equal_approx(projected.tuning_sliders[0].end_value, projected.tuning_sliders[1].start_value), "转折频率连续")
	check(doc.chart().tuning_sliders.is_empty(), "不回写旧滑条")
	check(not ChartValidator.validate(projected, rules).has_errors(), "旧领域接受临时谱")
	var crossing := ChartEditEvents.new_path(doc.chart(), 0, 1680, 3360)
	crossing.points[0].angle_deg = 175; crossing.points[1].angle_deg = -145
	var values := ChartPathAdapter.frequency_values(crossing, rules)
	check(values.has("error"), "生侧不能进入角色连线另一侧")
	crossing.points[0].angle_deg = -20; crossing.points[1].angle_deg = 20
	values = ChartPathAdapter.frequency_values(crossing, rules)
	check(not values.has("error") and values.values[1] > values.values[0], "跨零度走顺时针 40 度短弧")
	crossing.affinity = 1; crossing.points[0].angle_deg = 175; crossing.points[1].angle_deg = -145
	values = ChartPathAdapter.frequency_values(crossing, rules)
	check(not values.has("error") and values.values[1] < values.values[0], "死侧角方向相同而频差符号相反")
	crossing.points[1].angle_deg = crossing.points[0].angle_deg + 28
	check(not ChartPathAdapter.frequency_values(crossing, rules).has("error"), "28 度边界")
	crossing.points[1].angle_deg = crossing.points[0].angle_deg + 27
	check(ChartPathAdapter.frequency_values(crossing, rules).has("error"), "小于最小跨度不暗中钳制")
	crossing.points[1].angle_deg = crossing.points[0].angle_deg + 100
	check(ChartPathAdapter.frequency_values(crossing, rules).has("error"), "实际频率上限不能当成 100 度")
	var overflow := path.duplicate(true) as TuningPathEvent
	for i in 3: overflow.points[i].angle_deg = -120 + i * 70
	check(ChartPathAdapter.frequency_values(overflow, rules).has("error"), "每段合法但累计频差越界")
	overflow.points[1].offset_ticks = 0
	check(ChartPathAdapter.frequency_values(overflow, rules).node == "middle", "节点次序错误定位到节点")
	var malformed := doc.chart().duplicate(true) as SongChart
	malformed.ghost_events[0].tuning_ids = PackedStringArray(["path", "path"])
	check(not ChartPathAdapter.validate(malformed, rules).is_empty(), "不能重复关联同一条 Tuning")
	var change := TempoEvent.new(); change.tick = 2400; change.bpm = 150
	var tempo_chart := doc.chart().duplicate(true) as SongChart; tempo_chart.tempo_events.append(change); tempo_chart.chart_offset_ticks = 120
	var compiled := ChartCompiler.compile(ChartPathAdapter.project(tempo_chart, rules), rules, 230000)
	var map := TempoMap.from_chart(tempo_chart, 230000)
	check(compiled.ok and compiled.compiled.tuning_sliders[-1].end_us == map.tick_to_us(path.tick + path.duration_ticks), "变 BPM 与全谱偏移使用共同时间映射")
	var ids := PackedStringArray(["life", "death", "path", "ghost"])
	doc.copy_notes(ids); var pasted := doc.paste(3840)
	check(pasted.size() == 4, "混合复制")
	var pasted_path = doc.find_note(pasted[2]); var pasted_ghost = doc.find_note(pasted[3])
	check(pasted_path.hold_id == pasted[0] and pasted_ghost.tuning_ids[0] == pasted[2], "复制引用重映射")
	doc.undo(); check(doc.chart().tuning_paths.size() == 1, "一步撤销")
	doc.undo(true); check(doc.chart().ghost_events.size() == 2, "重做")
	doc.undo()
	var data := ChartJsonCodec.encode_chart(doc.chart()); data.mapper = "测试"
	doc.change_metadata(data)
	check(doc.chart().tuning_paths.size() == 1 and doc.chart().ghost_events.size() == 1, "资料编辑不覆盖新轨")
	check(ChartEditEvents.moving_ids(doc.chart(), PackedStringArray(["life"])).has("ghost"), "单侧依赖随动")
	doc.add_difficulty("copy", true)
	check(ChartPathAdapter.validate(doc.chart(), rules).is_empty(), "复制难度引用完整")
	print("TUNING_AUTHORING: %d failures" % failures)
	quit(1 if failures else 0)
