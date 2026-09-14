extends SceneTree
## 节拍边界、场景素材往返、普通/环境时钟和真实渲染确定性。
const Document=preload("res://addons/parallax_background_editor/document.gd")
var checks:=0
var failures:=0
var vp:SubViewport
func _initialize() -> void: run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok: failures+=1;printerr("FAIL ",label)
func chart(bpm:float) -> SongChart:
	var result:=SongChart.new();var tempo:=TempoEvent.new();tempo.bpm=bpm
	result.tempo_events=[tempo];result.meter_events=[MeterEvent.new()];return result
func background() -> StageBackgroundDefinition:
	var bg:=StageBackgroundDefinition.new();var layer:=StageBackgroundLayer.new();layer.depth=0
	var sub:=StageBackgroundSubLayer.new();layer.sublayers=[sub];bg.layers=[layer]
	var entry:=StageBackgroundEntry.new();entry.scene=load("res://scenes/presentation/boundary_waves.tscn")
	entry.position=Vector2(-49.9,-10.3);entry.uniform_scale=BoundaryWaveScene.DESIGN_SCALE
	sub.entries=[entry];return bg
func shot() -> Image:
	await process_frame;RenderingServer.force_draw();return vp.get_texture().get_image()

func alpha_bytes(image:Image) -> PackedByteArray:
	var bytes:=image.get_data();var alpha:=PackedByteArray();alpha.resize(bytes.size()/4)
	for i in alpha.size():alpha[i]=bytes[i*4+3]
	return alpha

func test_wave_coverage(wave:BoundaryWaveScene) -> void:
	# 同一帧在中央用正式浪花材质绘制，应与直接绘制源贴图有相同覆盖。
	var view:=SubViewport.new();view.size=Vector2i(1920,1080);view.transparent_bg=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var frames:=wave.little[0].sprite_frames
	var material:ShaderMaterial=wave.little[0].material.duplicate()
	material.set_shader_parameter("wave_frame",65.0)
	for i in 2:
		var sprite:=Sprite2D.new();sprite.scale=Vector2.ONE*.5
		sprite.position=Vector2(500 if i==0 else 960,540)
		sprite.texture=frames.get_frame_texture(&"wave",65 if i==0 else 0)
		if i==1:sprite.material=material
		view.add_child(sprite)
	await process_frame;RenderingServer.force_draw()
	var image:=view.get_texture().get_image()
	var reference:=image.get_region(Rect2i(404,476,192,128))
	var center:=image.get_region(Rect2i(864,476,192,128))
	check(alpha_bytes(reference)==alpha_bytes(center),"中央浪花保留源贴图覆盖，不被圆形保护区截断")
	root.remove_child(view);view.free()

func test_flow(wave:BoundaryWaveScene) -> void:
	# 单独观察水带，避免活动浪头的透明度变化混入轮廓核对。
	for child in wave.animated.get_children():
		if child!=wave.band:child.hide()
	wave.driver.style.flow_enabled=false;wave.sample_background(0)
	var original:=await shot();var outline:=alpha_bytes(original)
	wave.band.material=null
	check(original.get_data()==(await shot()).get_data(),"关闭水流与当前厚底带原纹逐像素一致")
	wave.band.material=wave.flow_material;wave.driver.style.flow_enabled=true
	for time in [-.25,0.0,.5,1.99,2.0,1000.5]:
		wave.sample_background(time)
		check(outline==alpha_bytes(await shot()),"水流不改变透明轮廓："+str(time))
	wave.sample_background(.5);var flowing:=await shot()
	check(flowing.get_data()!=original.get_data(),"内部流动有实际颜色变化")
	check(flowing.get_data()==(await shot()).get_data(),"水流暂停冻结")
	wave.sample_background(888);wave.sample_background(.5)
	check(flowing.get_data()==(await shot()).get_data(),"水流远跳后定位恢复")
	wave.sample_background(2.5)
	check(flowing.get_data()==(await shot()).get_data(),"双阶段完整周期连续复现")
	var streak_strength:=wave.driver.style.streak_strength
	wave.driver.style.streak_strength=0;wave.sample_background(.5)
	check(flowing.get_data()!=(await shot()).get_data(),"关闭细水纹仅保留原纹流动")
	wave.driver.style.streak_strength=streak_strength
	for bpm in [60,120,240]:
		wave.driver.tempo_map=TempoMap.from_chart(chart(bpm));wave.sample_background(.5)
		check(flowing.get_data()==(await shot()).get_data(),"BPM 不改变基底每秒流速")
	wave.driver.tempo_map=TempoMap.from_chart(chart(120))
	for child in wave.animated.get_children():child.show()
func run() -> void:
	vp=SubViewport.new();vp.size=Vector2i(1920,1080);vp.transparent_bg=true
	vp.size_2d_override=Vector2i(1920,1080);vp.size_2d_override_stretch=true
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var controller:=ParallaxController.new();vp.add_child(controller)
	var bg:=background();check(controller.configure(bg).is_empty(),"PackedScene 背景装配")
	var wave:BoundaryWaveScene=controller.get_configured_object(0)
	check(wave.big.size()==4 and wave.little.size()==6,"每侧两个大浪与三个小浪常驻")
	check(wave.little[0].sprite_frames.get_frame_count(&"wave")==128,"小浪保留全部轮廓，未抽稀为 32 帧")
	check(wave.big[0].material!=wave.big[1].material and wave.little[0].material!=wave.little[1].material,"各浪独立采样年龄")
	var ids:=wave.big.map(func(item):return item.sprite.get_instance_id())
	for bpm in [60,120,180,240]:
		controller.configure_boundary(chart(bpm),0,{"values":{}})
		for bar in range(-2,6):
			controller.set_song_time(bar*4.0*60.0/bpm)
			check(wave.last_state.large.any(func(w):return absf(w.phase-.75)<.00001),"%d BPM 小节首拍触水"%bpm)
			check(wave.last_state.large.size()==2 and wave.last_state.small.size()==3,"开场和负时间直接恢复接替浪")
		for frame in 100: controller.set_song_time(frame*.073)
		check(ids==wave.big.map(func(item):return item.sprite.get_instance_id()),"持续运行复用 Spine 实例")
	var varying:=chart(60);var tempo:=TempoEvent.new();tempo.tick=960;tempo.bpm=180;varying.tempo_events.append(tempo)
	controller.configure_boundary(varying,70.25,{"values":{}});controller.set_song_time(3)
	check(is_equal_approx(wave.last_state.quarter,5),"变 BPM 连续拍位")
	varying.chart_offset_ticks=240
	controller.configure_boundary(varying,70.25,{"values":{}});controller.set_song_time(.5)
	check(is_zero_approx(wave.last_state.quarter),"全谱偏移与节拍器作者 tick 对齐")
	var meter:=MeterEvent.new();meter.tick=1920;meter.numerator=6;meter.denominator=8;varying.meter_events.append(meter)
	controller.configure_boundary(varying,70.25,{"values":{}})
	for tick in [1919,1920,1921,2160,3360,4800]:
		controller.set_song_time(controller.boundary_motion.tempo_map.tick_to_us(tick)/1000000.0)
		check(wave.last_state.large.size()<=2 and wave.last_state.small.size()<=3,"换 6/8 保留收尾且数量有界")
	controller.configure_boundary(chart(120),0,{"values":{}})
	controller.set_song_time(1.37);var pose:=wave.last_state.duplicate(true)
	controller.set_song_time(100);controller.set_song_time(-3);controller.set_song_time(1.37)
	check(pose==wave.last_state,"远跳和回拖恢复相同出生点及阶段")
	var sequence:=StageEnvironmentSequence.new()
	sequence.build(bg,[{"id":"next","asset":"next","time_us":8000000,"effect":"fade"}],func(_id):return bg.duplicate(true),"",Vector3i(0,20000000,0))
	controller.set_environment(sequence)
	for offset in [-1.25,70.25]:
		controller.configure_boundary(chart(120),offset,{"values":{}})
		controller.sample_environment(roundi((offset+4.2)*1000000),Vector2.ZERO,4.0)
		for view in controller.environment_views.values():
			for slice in view.slices.values():
				for object in slice.background_scenes:
					check(is_equal_approx(object.last_state.quarter,8),"环境沿用主时钟，不使用局部时间或画面提前量")
	controller.set_environment(null)
	controller.configure_boundary(chart(120),0,{"values":{"boundary/wave_height_px":170.0}})
	check(wave.driver.style.wave_height_px==170 and BoundaryMotion.DEFAULT_STYLE.wave_height_px==165,"表现参数不改共享资源")
	controller.configure_boundary(chart(120),0,{"values":{}})
	var document=Document.new();document.add_asset(bg.layers[0].sublayers[0].entries[0].scene,Vector2(10,20))
	check(document.validation_error().is_empty() and document.items[0].entry.scene!=null,"编辑器接受场景素材")
	document.history.undo();check(document.items.is_empty(),"场景添加撤销")
	document.history.redo();check(document.items[0].entry.scene!=null,"场景添加重做")
	var path:="res://build/boundary-animation/roundtrip.tres"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	ResourceSaver.save(bg,path)
	var reopened:StageBackgroundDefinition=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened.layers[0].sublayers[0].entries[0].scene!=null,"保存重开保留场景源")
	if DisplayServer.get_name()!="headless":
		await test_wave_coverage(wave)
		await test_flow(wave)
		controller.set_song_time(9.4);var ordinary:=await shot()
		controller.set_environment(sequence);controller.sample_environment(9400000,Vector2.ZERO,9.4)
		check(ordinary.get_data()==(await shot()).get_data(),"换景后场景几何、透明边缘与普通背景逐像素相同")
		controller.set_environment(null)
		controller.set_song_time(1.37);var expected:=await shot()
		check(expected.get_data()==(await shot()).get_data(),"暂停时骨骼与图形冻结")
		for frame in 80:controller.set_song_time(frame*.041)
		controller.set_song_time(1.37)
		check(expected.get_data()==(await shot()).get_data(),"连续推进与直接定位像素相同")
		# 固定骨骼和位置，仅改变同一整数帧内的年龄，证明轮廓不再整帧跳变。
		var material:ShaderMaterial=wave.big[1].material
		material.set_shader_parameter("wave_frame",65.2);var subframe_a:=await shot()
		material.set_shader_parameter("wave_frame",65.8)
		check(subframe_a.get_data()!=(await shot()).get_data(),"大浪在相邻轮廓之间有实际像素过渡")
		material=wave.little[1].material
		material.set_shader_parameter("wave_frame",65.2);subframe_a=await shot()
		material.set_shader_parameter("wave_frame",65.8)
		check(subframe_a.get_data()!=(await shot()).get_data(),"小浪在相邻轮廓之间有实际像素过渡")
		controller.set_song_time(0);var first:=await shot();controller.set_song_time(6)
		check(first.get_data()==(await shot()).get_data(),"小浪区域轮转六秒循环无接缝")
		wave.driver.style.enabled=false;controller.set_song_time(1);var disabled:=await shot()
		var raw:=Sprite2D.new();raw.texture=wave.originals.texture;raw.centered=false;raw.transform=wave.transform
		wave.visible=false;wave.get_parent().add_child(raw)
		check(disabled.get_data()==(await shot()).get_data(),"关闭动画与原始 edge.png 逐像素一致")
		raw.free();wave.visible=true;wave.driver.style.enabled=true;controller.set_song_time(1.37)
		vp.size=Vector2i(1280,720);check((await shot()).get_used_rect().size.x>1200,"1280 下水带覆盖全宽")
	controller.clear();check(controller._background_scenes.is_empty(),"卸载释放场景引用")
	vp.queue_free();await process_frame
	print("BOUNDARY WAVES: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
