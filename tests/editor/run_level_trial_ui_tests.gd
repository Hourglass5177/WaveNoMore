extends SceneTree
## 用已有配套游戏验证真实启动握手；只关闭本测试启动的子进程，不重新导出游戏。
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1;printerr("FAIL: "+label)
func _run() -> void:
	var workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate();workspace.offer_recovery_on_start=false;workspace.recovery_path="user://level-tests/trial-recovery.json";root.add_child(workspace)
	for frame in 5:await process_frame
	workspace._open_path("res://examples/level-studio/渡口演出/level.json")
	for frame in 20:await process_frame
	workspace.select_objects(PackedStringArray(["ferryman"]));workspace.set_object_field("name","未保存试玩快照")
	var before_cursor: int=workspace.document.cursor
	workspace._trial_executable=ProjectSettings.globalize_path("res://").path_join("../Levels/game/minghe.exe").simplify_path()
	workspace.playtest()
	var child_pid: int=workspace._trial_pid
	var start:=Time.get_ticks_msec()
	while workspace._trial_stage!="ready" and child_pid>0 and Time.get_ticks_msec()-start<15000:
		await create_timer(0.1).timeout
	check(workspace._trial_stage=="ready","实际游戏报告关卡已加载")
	check(workspace.document.dirty and workspace.document.cursor==before_cursor,"试玩不保存文档或改变历史")
	workspace._set_background(false)
	check(not workspace.preview.suspended,"试玩仍打开时可恢复编辑预览")
	workspace.set_object_field("name","试玩期间继续编辑")
	check(workspace.document.find("objects","ferryman").name=="试玩期间继续编辑","游戏打开时编辑命令有效")
	if child_pid>0:OS.kill(child_pid)
	await create_timer(0.6).timeout
	check(workspace._trial_pid<0 and not workspace._trial_button.disabled,"子进程退出后恢复试玩按钮")
	print("LEVEL REAL TRIAL: ",failures," failures; stage=",workspace._trial_stage)
	workspace.queue_free();await process_frame;await process_frame;quit(failures)
