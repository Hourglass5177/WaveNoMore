extends SceneTree

## `test_domain_core.gd` 的命令行启动壳。
## 把测试返回的 `ok` 转成进程退出码，供总入口和 CI 判断成功或失败。


func _init() -> void:
	var suite = preload("res://tests/unit/domain/test_domain_core.gd").new()
	var result: Dictionary = suite.run()
	quit(0 if bool(result["ok"]) else 1)
