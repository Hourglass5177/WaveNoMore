extends SceneTree
## 对照完整骨骼与未位移分块的交接姿势，不用爆白掩盖贴图跳变。
const VISUAL=preload("res://tools/boss_animation/boss_visual.gd")
func _initialize() -> void:_run.call_deferred()
func _run() -> void:
	var vp:=SubViewport.new();vp.size=Vector2i(1024,1024);vp.transparent_bg=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var actor=VISUAL.new();vp.add_child(actor);actor.position=Vector2(512,512);actor.setup("goat_eye")
	actor.events.assign([{"kind":"death","time":0.}]);actor.dirty=true;actor.glow_strength=0.;actor.sample(2.1)
	await process_frame;RenderingServer.force_draw();var fragments:=vp.get_texture().get_image()
	actor.goat_fracture.hide();actor.skeleton.show();actor.skeleton.update_skeleton(0.)
	await process_frame;RenderingServer.force_draw();var skeleton:=vp.get_texture().get_image()
	var a:=fragments.get_data();var b:=skeleton.get_data();var bad:=0;var peak:=0
	for i in a.size():
		var difference:=absi(int(a[i])-int(b[i]));peak=maxi(peak,difference)
		if difference>12:bad+=1
	var path:="res://build/boss-audit/"
	fragments.save_png(path+"goat-handoff-fragments.png");skeleton.save_png(path+"goat-handoff-skeleton.png")
	print("GOAT handoff byte error >12: ",bad," / ",a.size(),"; peak=",peak)
	# 分块边缘会有亚像素采样差，主体不能有整块位置或颜色变化。
	quit(0 if float(bad)/a.size()<.01 else 1)
