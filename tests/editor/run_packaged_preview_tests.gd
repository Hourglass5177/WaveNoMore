extends SceneTree
## 用 --main-pack <发布EXE> 加载真正发布资源，而非工作区源码。
func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("发布预览检查超时");quit(2))
	run.call_deferred()
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	var path: String=args[args.find("--project")+1]
	var config:=PlanningParameters.read()
	if config.path != PlanningParameters.BUNDLED_PATH or not config.errors.is_empty():
		push_error(JSON.stringify(config));quit(1);return
	var doc:=StudioDocument.new()
	var error:=StudioProjectIO.open_project(path,doc)
	if not error.is_empty():push_error(error);quit(1);return
	var prepared:=ChartProjectLoader.prepare_preview(doc.song,doc.chart())
	if prepared.stage==null:push_error(JSON.stringify(prepared.report.to_array()));quit(1);return
	var view:=SubViewport.new();view.size=Vector2i(960,540);root.add_child(view)
	var preview=load("res://src/tools/chart_studio/preview_session.gd").new();root.add_child(preview)
	if not preview.load_preview(prepared.stage,view,prepared.compiled):quit(1);return
	await preview.seek_preview(191050998)
	var digest: String=preview.stage_root.gameplay_coordinator.result_digest()
	await preview.seek_preview(120000000);await preview.seek_preview(191050998)
	var same: bool=preview.stage_root.gameplay_coordinator.result_digest()==digest
	print("PACKAGED PREVIEW ",JSON.stringify({"same_result":same,"parameter_count":config.values.size(),"notes":doc.chart().note_events.size(),"tuning":doc.chart().tuning_paths.size(),"cache_hits":preview.motion_cache.hits}))
	preview.queue_free();view.queue_free();await process_frame;quit(0 if same else 1)
