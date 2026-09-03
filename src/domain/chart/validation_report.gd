class_name ValidationReport
extends RefCounted

## 一次迁移或校验产生的问题集合。ERROR 会阻止编译，WARNING 与 INFO
## 只向作者说明风险和编译结果。

var issues: Array[ValidationIssue] = []


func add_issue(issue: ValidationIssue) -> void:
	issues.append(issue)


func add_error(code: StringName, message: String, event_id: String = "", track: StringName = &"", tick: int = 0) -> void:
	add_issue(ValidationIssue.create(ValidationIssue.Severity.ERROR, code, message, event_id, track, tick))


func add_warning(code: StringName, message: String, event_id: String = "", track: StringName = &"", tick: int = 0) -> void:
	add_issue(ValidationIssue.create(ValidationIssue.Severity.WARNING, code, message, event_id, track, tick))


func add_info(code: StringName, message: String, event_id: String = "", track: StringName = &"", tick: int = 0) -> void:
	add_issue(ValidationIssue.create(ValidationIssue.Severity.INFO, code, message, event_id, track, tick))


func has_errors() -> bool:
	for issue in issues:
		if issue.severity == ValidationIssue.Severity.ERROR:
			return true
	return false


func count_by_severity(severity: int) -> int:
	var count: int = 0
	for issue in issues:
		if issue.severity == severity:
			count += 1
	return count


func to_array() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for issue in issues:
		result.append(issue.to_dictionary())
	return result
