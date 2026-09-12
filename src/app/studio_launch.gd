class_name StudioLaunch
extends RefCounted
## 在 Autoload 启动前判断工具模式，避免读取玩家配置、创建成绩存档。
static func is_active() -> bool:
	if is_level_editor(): return true
	if OS.has_feature("minghe_chart_editor"): return true
	for argument in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument == "--chart-editor" or argument.ends_with("chart_studio/studio.tscn"): return true
	return false

static func is_level_editor() -> bool:
	if OS.has_feature("minghe_level_editor"): return true
	for argument in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument == "--level-editor" or argument.ends_with("level_studio/studio.tscn"): return true
	return false
