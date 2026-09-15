extends RefCounted
## 显示同一成绩的最高完成标记；历史成绩与当局结算共用，保留存档字段。
const FC = preload("res://assets/ui/art/clear_marks/fc.tres")
const AP = preload("res://assets/ui/art/clear_marks/ap.tres")
static func texture_for(result: Dictionary) -> Texture2D:
	if bool(result.get("all_perfect", result.get("ap", false))): return AP
	if bool(result.get("full_combo", result.get("fc", false))): return FC
	return null
