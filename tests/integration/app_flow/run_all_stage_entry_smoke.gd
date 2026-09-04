extends SceneTree

## 依次走真实应用路由进入五张测试关，防止只测 s01 时漏掉某张正式谱的入口阻塞。

const STAGE_IDS: PackedStringArray = ["s01", "s02", "s03", "s04", "s05"]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var app_scene := load("res://scenes/app/app_main.tscn") as PackedScene
	if app_scene == null:
		printerr("ALL-STAGE ENTRY: AppMain failed to load")
		quit(1)
		return
	var app := app_scene.instantiate()
	root.add_child(app)
	await process_frame
	await process_frame
	var router := root.get_node("AppRouter")
	for stage_id: String in STAGE_IDS:
		var started_us := Time.get_ticks_usec()
		router.call("navigate", &"loading", {"stage_id": stage_id}, false)
		var entered := false
		for _frame: int in 600:
			await process_frame
			if router.get("current_route") == &"stage":
				entered = true
				break
		if not entered:
			printerr("ALL-STAGE ENTRY: %s did not enter within 600 frames" % stage_id)
			quit(1)
			return
		# 入口后的首批实际帧也必须能继续推进，不能只完成场景实例化。
		for _frame: int in 12:
			await process_frame
		var elapsed_ms := float(Time.get_ticks_usec() - started_us) / 1000.0
		var stage_root := app.get_node_or_null("ScreenHost/StageRoot")
		if stage_root == null:
			printerr("ALL-STAGE ENTRY: %s mounted no StageRoot" % stage_id)
			quit(1)
			return
		var session := stage_root.get_node_or_null("Session/StageSession")
		var stage_state := int(session.get("state")) if session != null else -1
		if stage_state not in [GameplayTypes.StageState.PREROLL, GameplayTypes.StageState.PLAYING]:
			printerr("ALL-STAGE ENTRY: %s remained in invalid state %d" % [stage_id, stage_state])
			quit(1)
			return
		print("ALL-STAGE ENTRY: %s entered in %.2f ms (state=%d)" % [stage_id, elapsed_ms, stage_state])
		router.call("navigate", &"stage_select", {}, false)
		await process_frame
		await process_frame
	app.queue_free()
	await process_frame
	print("ALL-STAGE ENTRY: PASS")
	quit(0)
