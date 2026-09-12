extends "res://tests/visual/measure_note_effects.gd"
## 同一进程交替开关，减少硬件频率与其他任务对独立进程对比的干扰。
func run() -> void:
	var phases := []
	var count := 4
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--phases="): count = int(arg.trim_prefix("--phases="))
	for index: int in count:
		effects_enabled = index % 2 == 1
		output = "res://builds/visual-review/note-effects/comparison-%d.json" % index
		phases.append(await measure_phase())
	print("COMPARISON ", JSON.stringify(phases))
	quit()
