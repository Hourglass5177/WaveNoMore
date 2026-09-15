extends SceneTree
## 用渲染器时间戳比较同尺寸静态原画和新火框；不含截图/编码耗时。
const FIRE=preload("res://src/presentation/ui/flame_frame_visual.gd")
func _initialize() -> void:run.call_deferred()
func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED);Engine.max_fps=0
	var vp:=SubViewport.new();vp.size=Vector2i(1920,1080);vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(),true)
	var report:={}
	for count in [1,5]:
		for animated in [false,true]:
			var nodes:Array=[]
			for i in count:
				var extent:=Vector2(1040,620) if count==1 else Vector2(230,610)
				var at:=Vector2(440,240) if count==1 else Vector2(180+i*330,250)
				if animated:
					var f=FIRE.new();f.size=extent;f.position=at;f.random_seed=i*19+4;f.palette=i%2;f.automatic=false;vp.add_child(f);nodes.append(f)
				else:
					var s:=TextureRect.new();s.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;s.texture=load("res://assets/ui/flame_frame/red_registered.png");s.position=at-Vector2(70,70);s.size=extent+Vector2(140,140);vp.add_child(s);nodes.append(s)
			var gpu:Array[float]=[];var cpu:Array[float]=[];var script:Array[float]=[];var calls:=0
			for frame in 300:
				var started:=Time.get_ticks_usec()
				if animated:
					for f in nodes:f.sample(frame/60.)
				var script_ms:float=(Time.get_ticks_usec()-started)/1000.
				await process_frame
				if frame<120:continue
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()))
				cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp.get_viewport_rid()))
				script.append(script_ms)
				calls=vp.get_render_info(Viewport.RENDER_INFO_TYPE_CANVAS,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
			gpu.sort();cpu.sort();script.sort()
			var key:="%d_%s"%[count,"flame" if animated else "static"]
			report[key]={"gpu_median_ms":gpu[90],"gpu_p95_ms":gpu[171],"cpu_render_median_ms":cpu[90],"cpu_render_p95_ms":cpu[171],"cpu_script_median_ms":script[90],"cpu_script_p95_ms":script[171],"draw_calls":calls}
			print(key," ",report[key])
			for node in nodes:node.free()
	report.environment={"gpu":RenderingServer.get_video_adapter_name(),"renderer":"Compatibility","resolution":[1920,1080],"warmup_frames":120,"measured_frames":180,"shared_effect_textures_rgba8_bytes":256*256*4+256*4*4+256*1*4*2}
	DirAccess.make_dir_recursive_absolute("res://build/ui-flame")
	FileAccess.open("res://build/ui-flame/performance.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	quit()
