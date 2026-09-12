extends SceneTree
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	if not value: failures += 1; print("FAIL ", label)
func background(color: Color, velocity := Vector2(480, 0)) -> StageBackgroundDefinition:
	var picture := Image.create(240, 1080, false, Image.FORMAT_RGBA8); picture.fill(color)
	var entry := StageBackgroundEntry.new(); entry.texture = ImageTexture.create_from_image(picture); entry.infinite = true
	var layer := StageBackgroundSubLayer.new(); layer.entries.append(entry); layer.velocity = velocity; layer.continuity_id = "ground"
	var depth := StageBackgroundLayer.new(); depth.depth = 1; depth.sublayers.append(layer)
	var result := StageBackgroundDefinition.new(); result.layers.append(depth); return result
func run() -> void:
	var a := background(Color.RED)
	var b := background(Color.BLUE, Vector2(960, 0))
	var c := background(Color.GREEN)
	var resources := {"a":a,"b":b,"c":c}
	var sequence := StageEnvironmentSequence.new()
	sequence.build(a,[{"id":"b","asset":"b","time_us":1000000,"effect":"fade"},{"id":"c","asset":"c","time_us":1100000}],func(id):return resources[id],"",Vector3i(0,30000000,0))
	check(sequence.transitions.size()==2,"两个请求均保留")
	var first: Dictionary = sequence.transitions[0]
	check(first.enter_us>=1000000,"渐变带不早于请求进入")
	check(sequence.transitions[1].enter_us>=first.finish_us,"排队不跳过场景")
	var position_before := StageEnvironmentSequence.travel(sequence.lanes[0],first.finish_us-1)
	var position_after := StageEnvironmentSequence.travel(sequence.lanes[0],first.finish_us)
	check(position_before.distance_to(position_after)<0.01,"换速位移连续")
	var view := SubViewport.new(); view.size=Vector2i(1920,1080); view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(view)
	var controller := ParallaxController.new(); view.add_child(controller); controller.configure(a);controller.set_environment(sequence)
	controller.sample_environment((first.enter_us+first.finish_us)/2)
	await process_frame; await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var screenshot := view.get_texture().get_image()
		var folder := ProjectSettings.globalize_path("res://../Levels/output/environment")
		DirAccess.make_dir_recursive_absolute(folder); screenshot.save_png(folder.path_join("seam.png"))
		var left:=screenshot.get_pixel(100,540);var right:=screenshot.get_pixel(1800,540)
		print("PIXELS ",left," ",right," center ",screenshot.get_pixel(960,540))
		check(left.b>0.8 and right.r>0.8,"真实画面接缝两侧不同来源")
	# 回看、反向、斜向、固定层和透明退出共用绝对时间求值。
	var first_finish:int=first.finish_us
	for direction in [Vector2(-480,0),Vector2(0,480),Vector2(320,240)]:
		var source:=background(Color.RED,direction);var target:=background(Color.BLUE,direction*1.5)
		var plan:=StageEnvironmentSequence.new();plan.build(source,[{"id":"next","asset":"b","time_us":1000000,"effect":"fade"}],func(_id):return target,"",Vector3i(0,30000000,0))
		var transition:Dictionary=plan.transitions[0]
		var middle:int=(int(transition.enter_us)+int(transition.finish_us))/2
		check(plan.visible_sources(plan.lanes[0],middle).size()==2,"双向 / 斜向接缝保持两侧来源")
		controller.set_environment(plan);controller.sample_environment(middle);await process_frame;await process_frame
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			var picture:=view.get_texture().get_image()
			var frame:=StageEnvironmentSequence.projected_frame(plan.lanes[0].direction)
			var axis:Vector2=plan.lanes[0].direction
			var head:=Vector2(960,540)-axis*200;var tail:=Vector2(960,540)+axis*200
			check(picture.get_pixelv(Vector2i(head)).b>0.8 and picture.get_pixelv(Vector2i(tail)).r>0.8,"实际反向 / 斜向来源方向正确")
			var center:=picture.get_pixel(960,540);check(center.g<0.02 and center.r+center.b>0.95,"渐变无白边和暗缝")
			controller.sample_environment(0);await process_frame;await process_frame
			controller.sample_environment(middle);await process_frame;await process_frame;await RenderingServer.frame_post_draw
			check(view.get_texture().get_image().get_data()==picture.get_data(),"回拖后实际像素一致")
	var fixed_a:=background(Color(1,0,0,0.4),Vector2.ZERO);var fixed_b:=background(Color(0,0,1,0.8),Vector2.ZERO)
	var fixed:=StageEnvironmentSequence.new();fixed.build(fixed_a,[{"id":"fade","asset":"b","time_us":1000000,"effect":"fade"}],func(_id):return fixed_b,"",Vector3i(0,30000000,0))
	check(fixed.transitions[0].enter_us==1000000 and fixed.transitions[0].finish_us==1500000,"固定装饰按请求淡化")
	view.transparent_bg=true;controller.set_environment(fixed);controller.sample_environment(1250000);await process_frame;await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var center:=view.get_texture().get_image().get_pixel(960,540)
		check(absf(center.a-0.6)<0.02,"半透明来源正确混合透明度")
	var empty:=StageBackgroundDefinition.new();var exiting:=StageEnvironmentSequence.new()
	exiting.build(a,[{"id":"empty","asset":"none","time_us":1000000}],func(_id):return empty,"",Vector3i(0,30000000,0))
	check(exiting.visible_sources(exiting.lanes[0],exiting.transitions[0].finish_us+1).is_empty(),"缺少的目标层完整退出")
	# 两个层的周期不相同；修改其中一层只重排该层，另一层保持原安排。
	var layered_a:=a.duplicate(true) as StageBackgroundDefinition
	var layered_b:=b.duplicate(true) as StageBackgroundDefinition
	var far_a:=background(Color.GREEN,Vector2(120,0)).layers[0].sublayers[0];far_a.continuity_id="far"
	var far_b:=background(Color.YELLOW,Vector2(240,0)).layers[0].sublayers[0];far_b.continuity_id="far"
	layered_a.layers[0].sublayers.append(far_a);layered_b.layers[0].sublayers.append(far_b)
	var layered:=StageEnvironmentSequence.new();var layered_cue:=LevelFormat.scene_cue(1000000,"b")
	layered.build(layered_a,[layered_cue],func(_id):return layered_b,"",Vector3i(0,30000000,0))
	check(layered.transitions[0].finish_us!=layered.transitions[1].finish_us,"不同周期的层独立完成")
	layered_cue.layers={"ground":{"effect":"fade","blend_px":256}}
	var revised:=StageEnvironmentSequence.new();revised.build(layered_a,[layered_cue],func(_id):return layered_b,"",Vector3i(0,30000000,0),Callable(),Vector2.ZERO,layered)
	check(is_same(revised.lanes[1],layered.lanes[1]) and not is_same(revised.lanes[0],layered.lanes[0]),"覆盖某层时复用不受影响的层")
	var deep_b:=b.duplicate(true) as StageBackgroundDefinition;deep_b.layers[0].depth=2
	var deep:=StageEnvironmentSequence.new();deep.build(a,[LevelFormat.scene_cue(1000000,"b")],func(_id):return deep_b,"",Vector3i(0,30000000,0),Callable(),Vector2(30,0))
	var change:int=deep.transitions[0].finish_us
	check(deep.displacement(deep.lanes[0],change-1).distance_to(deep.displacement(deep.lanes[0],change))<0.01,"深度与速度接续不跳位")
	var camera_plan:=StageEnvironmentSequence.new()
	var moving_camera:=func(at:int):return Vector2(-4000,0) if at<500000 else Vector2(40,0)*float(at)/1000000.0
	camera_plan.build(a,[LevelFormat.scene_cue(1000000,"b")],func(_id):return b,"",Vector3i(0,30000000,0),moving_camera)
	var before_request:=camera_plan.visible_sources(camera_plan.lanes[0],100000)
	check(before_request.size()==1 and before_request[0].index==0,"早于请求的镜头回看不出现未来场景")
	# 原生生死材质先绘制到来源画面，接缝只改变局部权重。
	var masked_a:=a.duplicate(true) as StageBackgroundDefinition;var masked_b:=b.duplicate(true) as StageBackgroundDefinition
	for bg in [masked_a,masked_b]:
		var material:=ShaderMaterial.new();material.shader=preload("res://shaders/materials/screen_half_material_split.gdshader")
		material.set_shader_parameter("upper_material",bg.layers[0].sublayers[0].entries[0].texture)
		material.set_shader_parameter("lower_material",c.layers[0].sublayers[0].entries[0].texture)
		bg.layers[0].sublayers[0].entries[0].material=material
	var masked:=StageEnvironmentSequence.new();masked.build(masked_a,[{"id":"mask","asset":"b","time_us":1000000,"effect":"fade"}],func(_id):return masked_b,"",Vector3i(0,30000000,0))
	controller.set_environment(masked);controller.sample_environment((masked.transitions[0].enter_us+masked.transitions[0].finish_us)/2);await process_frame;await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var image:=view.get_texture().get_image()
		check(image.get_pixel(100,200).b>0.9 and image.get_pixel(1800,200).r>0.9 and image.get_pixel(960,800).g>0.9,"生死分屏材质保持屏幕遮罩")
	var many:Array=[]
	for index in 120:many.append({"id":str(index),"asset":"b" if index%2==0 else "a","time_us":1000000+index*10000})
	var long_plan:=StageEnvironmentSequence.new();var started:=Time.get_ticks_usec()
	long_plan.build(a,many,func(id):return resources[id],"",Vector3i(0,900000000,0))
	check(long_plan.transitions.size()==120,"长工程不漏排队请求")
	print("PLAN 120 requests ms=",float(Time.get_ticks_usec()-started)/1000.0)
	controller.set_environment(long_plan);controller.sample_environment(500000000);check(controller.environment_views.ground.slices.size()<=2,"长工程仅保留当前可见来源")
	controller.set_environment(sequence);controller.sample_environment((first.enter_us+first.finish_us)/2)
	view.size_2d_override=Vector2i(1920,1080);view.size_2d_override_stretch=true;view.size=Vector2i(3840,2160)
	controller.sample_environment((first.enter_us+first.finish_us)/2);await process_frame;await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var picture:=view.get_texture().get_image()
		check(picture.get_pixel(200,1080).b>0.8 and picture.get_pixel(3600,1080).r>0.8,"200% 渲染分辨率接缝命中一致")
	check(sequence.transitions[0].finish_us==first_finish,"渲染分辨率不改变完成时间")
	controller.sample_environment(first_finish+1000,Vector2(100,0))
	check(controller.environment_views.ground.slices.size()==2,"镜头回看已完成接缝仍显示旧空间来源")
	check(sequence.transitions[0].finish_us==first_finish,"镜头晃动不重新排列换景")
	controller.clear(); view.queue_free();await process_frame
	print("ENVIRONMENT TESTS failures=",failures)
	quit(1 if failures else 0)
