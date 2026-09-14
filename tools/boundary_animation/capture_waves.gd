extends SceneTree
## 第一轮动作样片：120 BPM 四小节，原生分辨率，使用真实 Compatibility 渲染。
func _initialize() -> void: run.call_deferred()

func run() -> void:
	var vp:=SubViewport.new(); vp.size=Vector2i(1920,1080)
	vp.size_2d_override=Vector2i(1920,1080);vp.size_2d_override_stretch=true
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(vp)
	var bg:=ColorRect.new();bg.size=Vector2(1920,1080);bg.color=Color("302d3d");vp.add_child(bg)
	var wave: BoundaryWaveScene=load("res://scenes/presentation/boundary_waves.tscn").instantiate()
	vp.add_child(wave);wave.position=Vector2(-49.9,-10.3);wave.scale=Vector2.ONE*BoundaryWaveScene.DESIGN_SCALE
	var line:=Line2D.new();line.width=2;line.default_color=Color("e5dfbd")
	for i in 129:line.add_point(Vector2(960,540)+Vector2.from_angle(i*TAU/128.0)*56)
	vp.add_child(line)
	var folder:="res://build/boundary-animation/v2/"
	var start:=0;var count:=240;var fps:=30.0;var bpm:=120.0
	for arg in OS.get_cmdline_user_args():
		if arg=="--no-guide":line.hide()
		if arg.begins_with("--start="):start=int(arg.trim_prefix("--start="))
		if arg.begins_with("--count="):count=int(arg.trim_prefix("--count="))
		if arg.begins_with("--fps="):fps=float(arg.trim_prefix("--fps="))
		if arg.begins_with("--bpm="):bpm=float(arg.trim_prefix("--bpm="))
		if arg.begins_with("--folder="):folder=arg.trim_prefix("--folder=").path_join("")
	DirAccess.make_dir_recursive_absolute(folder)
	var chart:=SongChart.new();var tempo:=TempoEvent.new();tempo.bpm=bpm;chart.tempo_events=[tempo]
	wave.driver.tempo_map=TempoMap.from_chart(chart)
	for i in range(start,start+count):
		wave.sample_background(i/fps)
		await process_frame;RenderingServer.force_draw()
		vp.get_texture().get_image().save_png(folder.path_join("%04d.png"%i))
		if i%30==0:print("WAVE FRAME ",i)
	print("WAVE CAPTURE COMPLETE ",start," + ",count)
	root.remove_child(vp);vp.free();quit()
