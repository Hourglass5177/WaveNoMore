extends ConfirmationDialog
## 文件复制和压缩在后台执行，UI 只读取进度，不从工作线程触碰节点。
var _thread := Thread.new()
var _mutex := Mutex.new()
var _cancelled := false
var _progress := {"done":0,"total":1,"file":"准备依赖…"}

func _ready() -> void:
	get_ok_button().hide()
	canceled.connect(func():_mutex.lock();_cancelled=true;_mutex.unlock())
	close_requested.connect(func():_mutex.lock();_cancelled=true;_mutex.unlock())

func run_export(level: Dictionary, root: String, path: String) -> String:
	return await _run(func():return LevelProjectIO.export_zip(level,root,path,_report,_is_cancelled))

func run_copy(files: PackedStringArray, root: String, target: String) -> String:
	return await _run(func():return LevelProjectIO.copy_dependencies(files,root,target,_report,_is_cancelled))

func _run(work: Callable) -> String:
	var error:=_thread.start(work)
	if error!=OK:return "无法启动文件任务："+error_string(error)
	while _thread.is_alive():
		_mutex.lock();var state:=_progress.duplicate();var cancelled:=_cancelled;_mutex.unlock()
		%Status.text=("正在取消…" if cancelled else str(state.file))
		%Progress.value=100.0*float(state.done)/maxf(1,float(state.total))
		await get_tree().process_frame
	return str(_thread.wait_to_finish())

func _report(done: int, total: int, file: String) -> void:
	_mutex.lock();_progress={"done":done,"total":total,"file":file};_mutex.unlock()

func _is_cancelled() -> bool:
	_mutex.lock();var result:=_cancelled;_mutex.unlock();return result
