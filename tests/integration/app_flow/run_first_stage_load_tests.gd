extends SceneTree
## 旧版策划表缺少新增字段时仍可开局；实际填写错误不能被默认值掩盖。
var failures := 0
var checks := 0
func _initialize(): run.call_deferred()
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		printerr(message)
func fixture(name: String, value: String) -> String:
	var path := "user://" + name
	var zip := ZIPPacker.new()
	zip.open(path)
	zip.start_file("xl/worksheets/sheet1.xml")
	zip.write_file(('<worksheet><sheetData><row r="6"><c r="H6" t="inlineStr"><is><t>rules</t></is></c><c r="I6" t="inlineStr"><is><t>perfect_window_ms</t></is></c><c r="B6"><v>%s</v></c></row></sheetData></worksheet>' % value).to_utf8_buffer())
	zip.close_file()
	zip.close()
	return path
func run():
	var old_path := fixture("load-regression-old.xlsx", "55")
	var old := PlanningParameters.read(old_path)
	check(old.errors.is_empty(), "旧表不应因新增参数缺行而阻止载入：" + str(old.errors))
	check(old.values["rules/perfect_window_ms"] == 55, "保留策划已调整的数值")
	for row: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(PlanningParameters.SCHEMA_PATH)):
		if row.target + "/" + row.key != "rules/perfect_window_ms":
			check(old.values[row.target + "/" + row.key] == row.default, "缺少字段使用登记默认值：" + row.key)
	var invalid_path := fixture("load-regression-invalid.xlsx", "-1")
	check(not PlanningParameters.read(invalid_path).errors.is_empty(), "非法已填数值仍须报错")
	var current := PlanningParameters.read()
	check(current.errors.is_empty(), "当前交付表可读取：" + str(current.errors))
	var app = load("res://scenes/app/app_main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var router = root.get_node("AppRouter")
	for attempt in 2:
		router.navigate(&"loading", {"stage_id":"tutorial2"}, false)
		var deadline := Time.get_ticks_msec() + 15000
		while router.current_route != &"stage" and Time.get_ticks_msec() < deadline:
			await process_frame
		var host = app.get_node_or_null("ScreenHost/StageRoot")
		check(host != null, "第一关实际应用入口挂载成功，第 %d 次" % (attempt+1))
		if host != null:
			check(host.stage_session.compiled_chart != null, "第一关完成谱面编译")
			var before: float = host.song_clock.song_time_sec
			await create_timer(.5).timeout
			check(host.song_clock.song_time_sec > before, "第一关时钟实际推进")
		router.navigate(&"stage_select", {}, false)
		await process_frame
	app.queue_free()
	await process_frame
	DirAccess.remove_absolute(old_path)
	DirAccess.remove_absolute(invalid_path)
	print("FIRST STAGE LOAD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
