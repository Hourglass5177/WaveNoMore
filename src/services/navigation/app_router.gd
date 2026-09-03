extends Node

## 应用页面路由器。记录当前页面、上下文和返回历史，并发出切页请求；
## 真正的场景创建与销毁由 AppMain 负责。

## 请求 AppMain 实际切换页面时发出；此时目标场景还不一定已经挂载。
signal route_requested(route: StringName, context: Dictionary)
## AppMain 完成页面装载并确认路由后发出。
signal route_changed(route: StringName, context: Dictionary)

## 标题页的稳定路由名。
const ROUTE_TITLE: StringName = &"title"
## 选关页的稳定路由名。
const ROUTE_STAGE_SELECT: StringName = &"stage_select"
## 关卡异步加载页的稳定路由名。
const ROUTE_LOADING: StringName = &"loading"
## 实际关卡运行页的稳定路由名。
const ROUTE_STAGE: StringName = &"stage"
## 结算页的稳定路由名。
const ROUTE_RESULT: StringName = &"result"

## 当前已请求或已提交的路由名；空值表示应用尚未导航。
var current_route: StringName = &""
## 当前路由携带的数据副本，例如 `stage_id`、StageDefinition 或结算结果。
var current_context: Dictionary = {}
## 返回栈；每项保存上一页路由及其上下文，末项是最近页面。
var _history: Array[Dictionary] = []


func navigate(route: StringName, context: Dictionary = {}, remember_current: bool = true) -> void:
	if remember_current and not current_route.is_empty():
		_history.append({"route": current_route, "context": current_context.duplicate(true)})
	current_route = route
	current_context = context.duplicate(true)
	route_requested.emit(current_route, current_context)


func commit_route(route: StringName, context: Dictionary = {}) -> void:
	current_route = route
	current_context = context.duplicate(true)
	route_changed.emit(current_route, current_context)


func back(fallback: StringName = ROUTE_TITLE) -> void:
	if _history.is_empty():
		navigate(fallback, {}, false)
		return
	var previous: Dictionary = _history.pop_back()
	navigate(previous.get("route", fallback), previous.get("context", {}), false)


func clear_history() -> void:
	_history.clear()
