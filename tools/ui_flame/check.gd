extends SceneTree
## 直接读回像素，验证时间恢复、独立实例、留白及隐藏冻结。
const FIRE=preload("res://src/presentation/ui/flame_frame_visual.gd")
func _initialize() -> void:run.call_deferred()
func snapshot(vp:SubViewport) -> Image:
	await process_frame;RenderingServer.force_draw();return vp.get_texture().get_image()
func run() -> void:
	var vp:=SubViewport.new();vp.size=Vector2i(640,900);vp.transparent_bg=true;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var f=FIRE.new();f.position=Vector2(140,140);f.size=Vector2(360,620);f.random_seed=4;f.automatic=false;vp.add_child(f)
	f.sample(1.23);var a:Image=await snapshot(vp)
	# 火根下缘保持附着，火根以上的轮廓必须持续变化。
	var root_band:=a.get_region(Rect2i(180,148,280,4))
	var upper_band:=a.get_region(Rect2i(180,60,280,75))
	for sample_time in [0.,.31,.72,2.4,8.5]:
		f.sample(sample_time);var pose:Image=await snapshot(vp)
		assert(pose.get_region(Rect2i(180,148,280,4)).get_data()==root_band.get_data(),"火根发生升降或周期性消失")
		assert(pose.get_region(Rect2i(180,60,280,75)).get_data()!=upper_band.get_data(),"火苗轮廓没有继续燃烧")
	f.sample(1.23)
	var mesh=f.surface.mesh;var count:int=f.rebuilds
	for i in 1801:f.sample(i/60.)
	f.sample(1.23);var b:Image=await snapshot(vp)
	assert(a.get_data()==b.get_data(),"定位不能恢复相同像素")
	f.sample(1.23);assert((await snapshot(vp)).get_data()==a.get_data(),"暂停发生变化")
	# 正式菜单通过父控件 modulate 淡出；火芯和逸散火尖均须继承透明度。
	# 两次绘制的重叠 alpha 不线性，分别检查主体与火尖的半透明结果。
	for layer in [f.surface,f.embers]:
		f.surface.visible=layer==f.surface;f.embers.visible=layer==f.embers
		f.modulate.a=1.;var opaque:Image=await snapshot(vp)
		f.modulate.a=.5;var half:Image=await snapshot(vp)
		for y in range(0,900,3):
			for x in range(0,640,3):assert(absf(half.get_pixel(x,y).a-opaque.get_pixel(x,y).a*.5)<.012,"界面透明度未作用于全部火焰")
	f.surface.show();f.embers.show()
	f.modulate.a=0.;var faded:Image=await snapshot(vp)
	assert(faded.get_data().count(0)==faded.get_data().size(),"完全淡出后仍残留火光")
	f.automatic=true;var faded_time:float=f.elapsed;f._process(.1)
	assert(f.elapsed==faded_time,"完全淡出后仍推进火焰")
	f.automatic=false
	f.modulate=Color.WHITE
	f.sample(0.);f.sample(1.23);assert((await snapshot(vp)).get_data()==a.get_data(),"重置后相位变化")
	assert(f.surface.mesh==mesh&&f.rebuilds==count,"逐帧重建网格")
	f.hide();f.automatic=true;var time:float=f.elapsed;await process_frame;await process_frame;assert(f.elapsed==time,"隐藏仍推进")
	f.automatic=false;f.show()
	var second=FIRE.new();second.size=f.size;second.position=f.position;second.palette=1;second.automatic=false;vp.add_child(second);second.hide();second.sample(3.)
	assert(second.surface.material!=f.surface.material,"实例共享了时间参数")
	assert((await snapshot(vp)).get_data()==a.get_data(),"蓝色实例影响红色实例")
	# 底部约160 px留给加强后的火苗，正文区域到y=600仍须完全透明。
	for y in range(230,601):
		for x in range(230,410):assert(a.get_pixel(x,y).a==0.,"文字留白受侵入")
	for x in range(640):assert(a.get_pixel(x,0).a==0.&&a.get_pixel(x,899).a==0.,"垂直边缘裁切")
	for y in range(900):assert(a.get_pixel(0,y).a==0.&&a.get_pixel(639,y).a==0.,"横向边缘裁切")
	f.size=Vector2(420,620);assert(f.rebuilds==count+1,"尺寸变化未更新网格")
	f.speed=0.;f.sample(1.);var frozen:Image=await snapshot(vp);f.sample(12.);assert((await snapshot(vp)).get_data()==frozen.get_data(),"速度0没有冻结火形")
	f.glow_strength=0.;f.sample(12.);var dark:Image=await snapshot(vp);f.embers.hide();assert((await snapshot(vp)).get_data()==dark.get_data(),"关闭柔晕后留下黑色火星")
	var report:=PlanningParameters.read(PlanningParameters.WORKBOOK_PATH);assert(report.errors.is_empty(),str(report.errors))
	f.apply_planning(report);assert(f.speed==report.values['ui_flame/speed'],"未应用火框工作簿参数")
	f.automatic=true;var before_pause:float=f.elapsed;paused=true;await process_frame;await process_frame
	assert(f.elapsed>before_pause,"玩法暂停冻结了菜单火焰");paused=false
	print("FLAME CHECK: fixed roots / changing flames / seek/pause/reset/hidden/instances/30s/mesh/clearance OK");quit()
