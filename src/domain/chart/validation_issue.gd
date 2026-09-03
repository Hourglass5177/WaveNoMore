class_name ValidationIssue
extends RefCounted

## 一条可定位到轨道、事件和 tick 的校验问题，供写谱器、日志和构建检查共用。

enum Severity {
	INFO,
	WARNING,
	ERROR,
}

## 严重度：ERROR 会阻止编译/运行，WARNING 允许继续但提示作者检查。
var severity: int = Severity.ERROR
## 供工具稳定识别问题类型的机器码，例如 `duplicate_event_id`。
var code: StringName = &"unknown"
## 供谱师阅读的具体问题说明，可直接显示在校验面板中。
var message: String = ""
## 出错事件的稳定 ID；空字符串表示问题属于整张谱而非单个事件。
var event_id: String = ""
## 出错事件所属的谱面轨道名，用于让编辑器定位到正确轨道。
var track: StringName = &""
## 出错位置的绝对谱面 tick；0 也可能表示无法缩小到更具体的位置。
var tick: int = 0


static func create(
		p_severity: int,
		p_code: StringName,
		p_message: String,
		p_event_id: String = "",
		p_track: StringName = &"",
		p_tick: int = 0
) -> ValidationIssue:
	var issue := ValidationIssue.new()
	issue.severity = p_severity
	issue.code = p_code
	issue.message = p_message
	issue.event_id = p_event_id
	issue.track = p_track
	issue.tick = p_tick
	return issue


func to_dictionary() -> Dictionary:
	return {
		"severity": severity,
		"code": String(code),
		"message": message,
		"event_id": event_id,
		"track": String(track),
		"tick": tick,
	}
