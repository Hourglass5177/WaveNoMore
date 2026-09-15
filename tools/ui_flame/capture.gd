extends SceneTree
const REVIEW=preload("res://tools/ui_flame/review.tscn")
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var args:=OS.get_cmdline_user_args();var mode:=0;var full:="--full" in args;var resolution:=Vector2i(1920,1080);var duration:=12.
	for arg in args:
		if arg.begins_with("--mode="):mode=int(arg.get_slice("=",1))
		if arg=="--720":resolution=Vector2i(1280,720)
		if arg=="--4k":resolution=Vector2i(3840,2160)
		if arg.begins_with("--seconds="):duration=float(arg.get_slice("=",1))
	var vp:=SubViewport.new();vp.size=resolution;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var r=REVIEW.instantiate();vp.add_child(r);r.set_anchors_preset(Control.PRESET_TOP_LEFT);r.size=Vector2(resolution);r.fit();r.playing=false;r.toolbar.hide();r.mode=mode;r.rebuild()
	var folder:="res://build/ui-flame/%d-%d/"%[mode,resolution.x];DirAccess.make_dir_recursive_absolute(folder)
	for frame in (roundi(duration*60.) if full else 12):
		r.sample(frame/60. if full else frame*.09)
		await process_frame;RenderingServer.force_draw()
		vp.get_texture().get_image().save_png(folder+"%04d.png"%frame)
	print("FLAME CAPTURE ",folder);quit()
