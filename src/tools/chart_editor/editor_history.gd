## 写谱器 Undo/Redo。每条记录保存修改前后的完整 Chart/Show 快照，换取简单且确定的恢复行为。
@tool
class_name MingheChartEditorHistory
extends RefCounted

## 历史栈变化后通知按钮刷新可用状态及下一步操作名称。
signal history_changed(can_undo: bool, can_redo: bool, undo_label: String, redo_label: String)

## 最多保留 200 次编辑，避免完整 Resource 快照长期占用过多内存。
const MAX_ENTRIES := 200

## 历史条目数组；每项含标签及修改前后的 Chart/Show 深拷贝。
var _entries: Array[Dictionary] = []
## 指向下一次 Redo 条目的下标；0 表示没有可 Undo 的内容。
var _cursor: int = 0


func clear() -> void:
	_entries.clear()
	_cursor = 0
	_emit_state()


func push(label: String, before: Dictionary, after: Dictionary) -> void:
	# 内容签名相同代表操作没有真正改动谱面，不应占用一次撤销位置。
	if before.get("signature", "") == after.get("signature", ""):
		return
	if _cursor < _entries.size():
		# 撤销后又产生新编辑时，旧的 Redo 分支已经不再可达。
		_entries.resize(_cursor)
	_entries.append({
		"label": label,
		"before_chart": before.chart,
		"before_show": before.stage_show,
		"after_chart": after.chart,
		"after_show": after.stage_show,
	})
	if _entries.size() > MAX_ENTRIES:
		_entries.pop_front()
	else:
		_cursor += 1
	_emit_state()


func undo(document: MingheChartEditorDocument) -> bool:
	if not can_undo():
		return false
	_cursor -= 1
	var entry := _entries[_cursor]
	document.replace_working_copy(entry.before_chart, entry.before_show, "undo")
	_emit_state()
	return true


func redo(document: MingheChartEditorDocument) -> bool:
	if not can_redo():
		return false
	var entry := _entries[_cursor]
	_cursor += 1
	document.replace_working_copy(entry.after_chart, entry.after_show, "redo")
	_emit_state()
	return true


func can_undo() -> bool:
	return _cursor > 0


func can_redo() -> bool:
	return _cursor < _entries.size()


func undo_label() -> String:
	return String(_entries[_cursor - 1].label) if can_undo() else ""


func redo_label() -> String:
	return String(_entries[_cursor].label) if can_redo() else ""


func _emit_state() -> void:
	history_changed.emit(can_undo(), can_redo(), undo_label(), redo_label())
