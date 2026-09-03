extends SceneTree

## `test_art_manifest_contract.gd` 的命令行启动壳。
## 返回非零退出码时，构建流程应视为美术资源不符合接入规范。


func _init() -> void:
	var suite := preload("res://tests/integration/art/test_art_manifest_contract.gd").new()
	var result: Dictionary = suite.run()
	quit(0 if bool(result.get("ok", false)) else 1)
