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

func test_vortex_schedule() -> void:
	var song:=chart(120)
	for setting in [Vector3i(1680,3,4),Vector3i(3360,7,8),Vector3i(5520,2,4)]:
		var meter:=MeterEvent.new();meter.tick=setting.x;meter.numerator=setting.y;meter.denominator=setting.z
		song.meter_events.append(meter)
	var motion:=BoundaryMotion.new();motion.tempo_map=TempoMap.from_chart(song);motion.meters=song.meter_events
	for bpm in [60,120,180,240]:
		song.tempo_events[0].bpm=bpm;motion.tempo_map=TempoMap.from_chart(song)
		var previous:=-INF
		var forward:=true
		for frame in range(-120,2400):
			var distance:=motion.vortex_distance_at(frame/120.0)
			forward=forward and distance>previous
			previous=distance
		check(forward,"%d BPM 和换拍号持续向前，不按小节回退"%bpm)
		for meter in song.meter_events:
			var seconds:=motion.tempo_map.tick_to_us(meter.tick)/1000000.0
			check(absf(motion.vortex_distance_at(seconds+.0001)-motion.vortex_distance_at(seconds-.0001))<.05,"换拍号时水纹位置连续")
	motion.style.vortex_beat_push_px=0
	check(is_equal_approx(motion.vortex_distance_at(3.25),3.25*motion.style.vortex_flow_speed_px_sec),"关闭拍点提速后仍连续恒速")
	# 实际顶点验证：不是靠圆形裁切掩盖侵入，也不能再次出现下垂根部。
	var minimum_radius:=INF
	var root_rises:=true
	var previous_y:=24.0
	for i in 321:
		var pair:=BoundaryVortexArm.edges(i/1000.0,88,112)
		root_rises=root_rises and pair[0].y<=previous_y+.0001
		previous_y=pair[0].y
	check(root_rises,"浪根下缘始终平顺上行，没有下坠鼓包")
	for i in 1001:
		var pair:=BoundaryVortexArm.edges(i/1000.0,88,112)
		minimum_radius=minf(minimum_radius,pair[0].length())
	check(minimum_radius>=78.0,"浪形自然留出判定圈和 12 px 观察空间")
	for radius in [80.0,88.0,110.0]:
		for width in [80.0,112.0,150.0]:
			var positive:=true
			for i in BoundaryVortexArm.STEPS:
				var a:=BoundaryVortexArm.edges(i/float(BoundaryVortexArm.STEPS),radius,width)
				var b:=BoundaryVortexArm.edges((i+1)/float(BoundaryVortexArm.STEPS),radius,width)
				a[1]=a[0]+(a[1]-a[0])*1.4
				b[1]=b[0]+(b[1]-b[0])*1.4
				positive=positive and (a[1]-a[0]).cross(b[0]-a[0])>=-.001
				positive=positive and (b[1]-a[1]).cross(b[0]-a[1])>=-.001
			check(positive,"内径 %.0f 宽度 %.0f 的连续网格不翻折"%[radius,width])

func run() -> void:
	test_vortex_schedule()
	vp=SubViewport.new();vp.size=Vector2i(1920,1080);vp.transparent_bg=true
	vp.size_2d_override=Vector2i(1920,1080);vp.size_2d_override_stretch=true
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var controller:=ParallaxController.new();vp.add_child(controller)
	var bg:=background();check(controller.configure(bg).is_empty(),"PackedScene 背景装配")
	var wave:BoundaryWaveScene=controller.get_configured_object(0)
	check(wave.big.size()==2 and wave.little.size()==6,"两股常驻厚浪与每侧三个小浪")
	check(wave.little[0].sprite_frames.get_frame_count(&"wave")==128,"小浪保留全部轮廓，未抽稀为 32 帧")
	check(wave.big[0].material!=wave.big[1].material and wave.little[0].material!=wave.little[1].material,"各浪独立采样年龄")
	var ids:=wave.big.map(func(item):return item.sprite.get_instance_id())
	for bpm in [60,120,180,240]:
		controller.configure_boundary(chart(bpm),0,{"values":{}})
		for bar in range(-2,6):
			controller.set_song_time(bar*4.0*60.0/bpm)
			check(is_equal_approx(wave.big[0].sprite.distance_px,controller.boundary_motion.vortex_distance_at(bar*4.0*60.0/bpm)),"%d BPM 小节首拍沿用累计路程"%bpm)
			check(wave.last_state.small.size()==3,"开场和负时间直接恢复小浪")
		for frame in 100: controller.set_song_time(frame*.073)
		check(ids==wave.big.map(func(item):return item.sprite.get_instance_id()),"持续运行复用网格实例")
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
		check(wave.last_state.small.size()<=3,"换 6/8 小浪保留收尾且数量有界")
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
	controller.configure_boundary(chart(120),0,{"values":{"boundary/vortex_width_px":128.0}})
	check(wave.driver.style.vortex_width_px==128 and BoundaryMotion.DEFAULT_STYLE.vortex_width_px==112,"表现参数不改共享资源")
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
		# 中央空间由浪形本身留出，不能靠界面遮盖穿入判定框的水体。
		var clear_eye:=true
		var closest_water:=100.0
		DirAccess.make_dir_recursive_absolute("res://build/boundary-animation/vortex-alpha")
		for phase in 16:
			controller.set_song_time(phase/8.0)
			var eye_image:=await shot()
			eye_image.save_png("res://build/boundary-animation/vortex-alpha/%02d.png"%phase)
			for y in range(464,617):
				for x in range(884,1037):
					if Vector2(x-960,y-540).length()<=76.0:
						clear_eye=clear_eye and eye_image.get_pixel(x,y).a<.01
						if eye_image.get_pixel(x,y).a>=.01:closest_water=minf(closest_water,Vector2(x-960,y-540).length())
		if not clear_eye:print("中央最近水体像素半径：",closest_water)
		check(clear_eye,"完整接替周期保留判定框内的单一空白区域")
		check(wave.big[0].sprite.distance_px==wave.big[1].sprite.distance_px,"两侧卷流共用同一路程")
		check(is_equal_approx(wave.big[1].sprite.get_parent().rotation-wave.big[0].sprite.get_parent().rotation,PI),"另一侧以 180 度旋转同一水臂，开口对称")
		controller.set_song_time(9.4);var ordinary:=await shot()
		controller.set_environment(sequence);controller.sample_environment(9400000,Vector2.ZERO,9.4)
		check(ordinary.get_data()==(await shot()).get_data(),"换景后场景几何、透明边缘与普通背景逐像素相同")
		controller.set_environment(null)
		controller.set_song_time(1.37);var expected:=await shot()
		check(expected.get_data()==(await shot()).get_data(),"暂停时纹样与图形冻结")
		for frame in 80:controller.set_song_time(frame*.041)
		controller.set_song_time(1.37)
		check(expected.get_data()==(await shot()).get_data(),"连续推进与直接定位像素相同")
		# 中央仅推进材质参数，网格与实例保持不变；小浪继续密集轮廓补间。
		var material:ShaderMaterial=wave.big[1].material
		var original_mesh:Mesh=wave.big[1].sprite.mesh
		wave.big[1].sprite.sample(100.0,wave.driver.style);var subframe_a:=await shot()
		wave.big[1].sprite.sample(100.5,wave.driver.style)
		check(subframe_a.get_data()!=(await shot()).get_data(),"水纹亚像素前进有实际像素变化")
		check(original_mesh==wave.big[1].sprite.mesh,"逐帧只更新材质，不重建网格")
		# 原纹和细沫的独立周期都能首尾相接，不允许隐藏的相位跳变。
		for key in ["ink_phase","foam_phase","crest_phase"]:
			material.set_shader_parameter(key,0.0);subframe_a=await shot()
			material.set_shader_parameter(key,1.0)
			var wrapped:=await shot()
			var delta:=0
			var a:=subframe_a.get_data();var b:=wrapped.get_data()
			for pixel in a.size():delta+=absi(int(a[pixel])-int(b[pixel]))
			check(delta/float(a.size())<.01,key+" 完整周期没有接缝跳变")
		material.set_shader_parameter("crest_phase",.2)
		var crest_outline:=alpha_bytes(await shot())
		material.set_shader_parameter("crest_phase",.4)
		check(crest_outline!=alpha_bytes(await shot()),"翻出的浪唇与空腔实际改变轮廓，不只是内部纹样滚动")
		material=wave.little[1].material
		material.set_shader_parameter("wave_frame",65.2);subframe_a=await shot()
		material.set_shader_parameter("wave_frame",65.8)
		check(subframe_a.get_data()!=(await shot()).get_data(),"小浪在相邻轮廓之间有实际像素过渡")
		controller.set_song_time(0);var first:=await shot();controller.set_song_time(6)
		check(first.get_region(Rect2i(0,400,600,240)).get_data()==(await shot()).get_region(Rect2i(0,400,600,240)).get_data(),"小浪区域轮转六秒循环无接缝")
		wave.driver.style.enabled=false;controller.set_song_time(1);var disabled:=await shot()
		var raw:=Sprite2D.new();raw.texture=wave.originals.texture;raw.centered=false;raw.transform=wave.transform
		wave.visible=false;wave.get_parent().add_child(raw)
		check(disabled.get_data()==(await shot()).get_data(),"关闭动画与原始 edge.png 逐像素一致")
		raw.free();wave.visible=true;wave.driver.style.enabled=true;controller.set_song_time(1.37)
		vp.size=Vector2i(1280,720);check((await shot()).get_used_rect().size.x>1200,"1280 下水带覆盖全宽")
	controller.clear();check(controller._background_scenes.is_empty(),"卸载释放场景引用")
	vp.queue_free();await process_frame
	print("BOUNDARY WAVES: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
