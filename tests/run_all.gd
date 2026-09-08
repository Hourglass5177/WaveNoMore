extends SceneTree

## 自动测试总入口。
## 每套测试都在独立的 Godot 子进程中运行，避免全局单例和暂停状态互相污染。

## 独立测试进程的入口清单；顺序从纯逻辑到编辑器工具，便于先看到根因较小的失败。
const SUITES: PackedStringArray = [
	"res://tests/unit/domain/run_domain_tests.gd",
	"res://tests/unit/domain/test_wave_interaction.gd",
	"res://tests/unit/domain/test_carrier_wave_engine.gd",
	"res://tests/integration/content/run_content_tests.gd",
	"res://tests/integration/art/run_art_tests.gd",
	"res://tests/integration/save/run_save_tests.gd",
	"res://tests/integration/pets/run_pet_tests.gd",
	"res://tests/integration/pets/run_menu_navigation_tests.gd",
	"res://tests/integration/input/run_input_replay_v3_tests.gd",
	"res://tests/integration/stage/run_stage_runtime_tests.gd",
	"res://tests/integration/app_flow/run_app_flow_smoke.gd",
	"res://tests/integration/app_flow/run_all_stage_entry_smoke.gd",
	"res://tests/editor/run_chart_editor_tests.gd",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	var godot_executable := OS.get_executable_path()
	var failed_suites: PackedStringArray = []
	for suite_path: String in SUITES:
		print("\n=== RUN %s ===" % suite_path)
		var output: Array = []
		# 第四个参数为 true：等待当前子进程退出并取得退出码，再串行运行下一套。
		var exit_code := OS.execute(
			godot_executable,
			PackedStringArray(["--headless", "--path", project_path, "--script", suite_path]),
			output,
			true
		)
		for block: String in output:
			print(block.trim_suffix("\n"))
		if exit_code != 0:
			failed_suites.append("%s (exit %d)" % [suite_path, exit_code])

	if failed_suites.is_empty():
		print("\nALL TEST SUITES PASSED: %d/%d" % [SUITES.size(), SUITES.size()])
		quit(0)
		return
	printerr("\nTEST SUITES FAILED: %d/%d" % [failed_suites.size(), SUITES.size()])
	for failure: String in failed_suites:
		printerr("  - " + failure)
	quit(1)
