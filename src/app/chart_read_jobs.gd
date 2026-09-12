class_name ChartReadJobs
extends Node
## 页面取消只使请求失效。后台不接触节点，完成后主线程才发布资源。
signal completed(request: int, result: Dictionary)
var _serial := 0
var _tasks: Array[Dictionary] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func request(path: String, difficulty: String = "", inspect_all := false) -> int:
	_serial += 1
	var holder := {"result": {}}
	var scene_ids := ChartSceneLibrary.shared().scene_ids()
	var task := WorkerThreadPool.add_task(func() -> void:
		holder.result = LevelPackageReader.read(path, difficulty, inspect_all, scene_ids))
	_tasks.append({"id": _serial, "task": task, "holder": holder, "inspect_all": inspect_all, "cancelled": false})
	return _serial

func _process(_delta: float) -> void:
	for i in range(_tasks.size() - 1, -1, -1):
		var item: Dictionary = _tasks[i]
		if WorkerThreadPool.is_task_completed(item.task):
			WorkerThreadPool.wait_for_task_completion(item.task)
			_tasks.remove_at(i)
			if item.cancelled: continue
			var result := LevelPackageReader.finish(item.holder.result,item.inspect_all)
			completed.emit(item.id, result)

func _exit_tree() -> void:
	for item in _tasks: WorkerThreadPool.wait_for_task_completion(item.task)

func cancel_request(id: int) -> void:
	for item in _tasks:
		if item.id == id: item.cancelled = true
