extends SceneTree

## `test_domain_core.gd` 的命令行启动壳。
## 把测试返回的 `ok` 转成进程退出码，供总入口和 CI 判断成功或失败。


func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var core_suite = load("res://tests/unit/domain/test_domain_core.gd").new()
	var tuning_arc_suite = load("res://tests/unit/domain/test_tuning_arc_assist.gd").new()
	var core_result: Dictionary = core_suite.run()
	var tuning_arc_result: Dictionary = tuning_arc_suite.run()
	quit(0 if bool(core_result["ok"]) and bool(tuning_arc_result["ok"]) else 1)
