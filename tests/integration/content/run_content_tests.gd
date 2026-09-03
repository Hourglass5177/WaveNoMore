extends SceneTree

## `test_content_package.gd` 的命令行启动壳。
## 只负责加载测试类并把结果转成退出码。


func _init() -> void:
	var suite := preload("res://tests/integration/content/test_content_package.gd").new()
	var result: Dictionary = suite.run()
	quit(0 if bool(result["ok"]) else 1)
