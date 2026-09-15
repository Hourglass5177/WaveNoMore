extends SceneTree

## --script 的入口早于 Autoload 注册；延后加载依赖 SettingsService 的关卡测试。
func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	set_script(load("res://tests/integration/stage/run_stage_runtime_tests.gd"))
	call("_run")
