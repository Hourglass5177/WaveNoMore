extends SceneTree
## 直接采样正式组件，图样、汇文排版和引线与游戏完全一致。
const GUIDE = preload("res://src/app/ui/instruction_guide.gd")
const OUT := "res://outputs/launch-guides"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var planning := PlanningParameters.read(PlanningParameters.WORKBOOK_PATH)
	if not planning.errors.is_empty():
		printerr(planning.errors)
		quit(1)
		return
	for key: String in ["fade_in_sec","hold_sec","fade_out_sec","headphones_hold_sec"]:
		if not planning.values.has("ui_guides/"+key):
			printerr("开屏参数未同步：",key)
			quit(1)
			return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for resolution: Vector2i in [Vector2i(1920,1080),Vector2i(3840,2160),Vector2i(1280,720)]:
		var viewport := SubViewport.new()
		viewport.size = resolution
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		for page: int in [GUIDE.Page.HEADPHONES,GUIDE.Page.CONTROLLER]:
			var guide := GUIDE.new()
			guide.page = page
			viewport.add_child(guide)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			var filename := "%s-%d.png" % ["headphones" if page == GUIDE.Page.HEADPHONES else "controller",resolution.x]
			image.save_png(OUT+"/"+filename)
			guide.queue_free()
			await process_frame
		viewport.queue_free()
		await process_frame
	print("Launch guides captured: ",OUT)
	quit()
