class_name ChartTrialLaunch
extends RefCounted
const INTERFACE_VERSION := 1

static func arguments() -> Dictionary:
	var args := OS.get_cmdline_user_args()
	var result := {}
	for i in args.size() - 1:
		match args[i]:
			"--play-chart": result.path = args[i + 1]
			"--play-level": result.path = args[i + 1]; result.level = true
			"--difficulty": result.difficulty_id = args[i + 1]
			"--trial-status": result.status_path = args[i + 1]
			"--trial-request": result.request_id = args[i + 1]
			"--trial-log": result.log_path = args[i + 1]
	if result.has("path"): result.origin = "trial"
	return result

static func report(context: Dictionary, stage: String, message := "") -> void:
	var path := str(context.get("status_path", ""))
	if path.is_empty(): return
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"interface_version": INTERFACE_VERSION, "request_id": context.get("request_id", ""), "stage": stage, "message": message, "log_path": str(context.get("log_path", ProjectSettings.globalize_path("user://logs/godot.log")))}))
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)
