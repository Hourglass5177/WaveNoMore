extends SceneTree
## 缓存不改变谱面、撤销或判定；同一场景可重复装入新编译结果。
var failures := 0
func _initialize() -> void:
	create_timer(90).timeout.connect(func(): push_error("预览缓存测试超时");quit(2))
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func run() -> void:
	var doc:=StudioDocument.new()
	StudioProjectIO.open_project("res://tests/editor/fixtures/tuning/song.json",doc)
	var view:=SubViewport.new();view.size=Vector2i(640,360);root.add_child(view)
	var preview=load("res://src/tools/chart_studio/preview_session.gd").new();root.add_child(preview)
	var prepared:=ChartProjectLoader.prepare_preview(doc.song,doc.chart())
	check(prepared.stage != null and not prepared.report.has_errors(),"共享准备结果可供问题列表与预览使用")
	check(prepared.report.count_by_severity(ValidationIssue.Severity.INFO)==0,"成功编译不产生占位问题")
	if prepared.stage == null: quit(1);return
	check(preview.load_preview(prepared.stage,view,prepared.compiled),"装载预编译结果")
	var root_id: int=preview.stage_root.get_instance_id()
	await preview.seek_preview(6200000)
	var digest: String=preview.stage_root.gameplay_coordinator.result_digest()
	var cache_bytes: int=preview.motion_cache.bytes
	check(cache_bytes > 0 and cache_bytes < 64*1024*1024,"活动长音生成内存运动缓存")
	await preview.seek_preview(4200000)
	await preview.seek_preview(6200000)
	check(preview.motion_cache.hits > 0 and preview.stage_root.gameplay_coordinator.result_digest()==digest,"来回定位命中缓存且成绩一致")
	prepared=ChartProjectLoader.prepare_preview(doc.song,doc.chart())
	preview.load_preview(prepared.stage,view,prepared.compiled)
	check(preview.stage_root.get_instance_id()==root_id,"重新装谱复用关卡实例")
	check(preview.motion_cache.bytes >= cache_bytes,"未修改依赖时保留运动缓存")
	var path:=doc.chart().tuning_paths[0]
	var original: float=path.points[-1].angle_deg
	path.points[-1].angle_deg+=1
	prepared=ChartProjectLoader.prepare_preview(doc.song,doc.chart())
	preview.load_preview(prepared.stage,view,prepared.compiled)
	var retained: Dictionary=preview.motion_cache.before("life_hold",6000000)
	check(retained.is_empty() or int(retained.at) < 3500000,"改变 Tuning 清除依赖之后的样本，允许保留更早样本")
	await preview.seek_preview(6200000)
	path.points[-1].angle_deg=original
	prepared=ChartProjectLoader.prepare_preview(doc.song,doc.chart())
	preview.load_preview(prepared.stage,view,prepared.compiled)
	await preview.seek_preview(6200000)
	check(preview.stage_root.gameplay_coordinator.result_digest()==digest,"恢复修改前内容后成绩恢复")
	# 直接核对淘汰顺序，不向真实谱面构造大量音符或节点。
	var cache=load("res://src/tools/chart_studio/preview_motion_cache.gd").new()
	var payload:=PackedByteArray();payload.resize(24*1024*1024)
	cache.put("a",0,{"data":payload});cache.put("b",500000,{"data":payload})
	cache.before("a",0);cache.put("c",1000000,{"data":payload})
	check(cache.bytes <= cache.LIMIT_BYTES and cache.before("b",500000).is_empty() and not cache.before("a",0).is_empty(),"64 MiB 预算淘汰最久未使用的样本")
	preview.queue_free();view.queue_free();await process_frame
	print("PREVIEW CACHE TESTS: ",failures);quit(1 if failures else 0)
