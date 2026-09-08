extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	print("PASS " if ok else "FAIL ", message)
	if not ok: failures += 1
func run() -> void:
	var launcher = load("res://src/tools/chart_studio/studio_playtest.gd").new()
	launcher.temp_root = "user://chart_studio/tests/launcher_" + str(Time.get_ticks_usec())
	root.add_child(launcher)
	launcher._folder = launcher.temp_root.path_join("trial_running")
	DirAccess.make_dir_recursive_absolute(launcher._folder)
	StudioProjectIO.write_json(launcher._folder.path_join("owner.json"), {"pid": OS.get_process_id()})
	launcher._cleanup_abandoned()
	check(FileAccess.file_exists(launcher._folder.path_join("owner.json")), "整理遗留目录时保留运行中进程的文件")
	var abandoned: String = launcher.temp_root.path_join("trial_abandoned")
	StudioProjectIO.write_json(abandoned.path_join("owner.json"), {"pid": -1})
	launcher._cleanup_abandoned()
	check(not DirAccess.dir_exists_absolute(abandoned), "清理已结束的本机临时目录")
	launcher._request = "latest"
	StudioProjectIO.write_json(launcher._folder.path_join("status.json"), {"request_id": "old", "interface_version": 1, "stage": "ready"})
	launcher._read_status()
	check(launcher._last_stage.is_empty(), "旧请求不能报告本次启动成功")
	StudioProjectIO.write_json(launcher._folder.path_join("status.json"), {"request_id": "latest", "interface_version": 99, "stage": "ready"})
	launcher._read_status()
	check(launcher._last_stage.is_empty(), "不匹配的接口不能冒充启动成功")
	var notices: Array[String] = []
	launcher.notice.connect(func(message: String): notices.append(message))
	launcher.pid = OS.get_process_id()
	launcher._started_ms = Time.get_ticks_msec() - 16000
	launcher._process(0)
	check(notices.size() == 1 and notices[0].contains("不支持一键试玩"), "进程存在但无握手时明确提示")
	launcher.pid = -1
	StudioProjectIO.write_json(launcher._folder.path_join("status.json"), {"request_id": "latest", "interface_version": 1, "stage": "error", "message": "难度 hard：缺少音乐"})
	launcher._read_status()
	check(launcher._failure_message.contains("hard") and launcher._last_stage == "error", "游戏加载错误保留具体原因")
	launcher.cancel_selection()
	check(not launcher.busy, "取消选程序恢复按钮状态")
	launcher.queue_free()
	await process_frame
	print("TRIAL LAUNCHER TESTS: ", failures)
	quit(1 if failures else 0)
