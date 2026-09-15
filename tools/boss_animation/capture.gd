extends SceneTree
## 60 fps 审看采样与死亡末姿烘焙，均走实际 Compatibility 渲染。
const VISUAL := preload("res://tools/boss_animation/boss_visual.gd")
var output := "res://build/boss-animation/"
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var args:=OS.get_cmdline_user_args();var selected:="";var selected_clip:="";var from_frame:=0;var to_frame:=2147483647
	for arg in args:
		if arg.begins_with("--id="):selected=arg.get_slice("=",1)
		if arg.begins_with("--clip="):selected_clip=arg.get_slice("=",1)
		if arg.begins_with("--from-frame="):from_frame=int(arg.get_slice("=",1))
		if arg.begins_with("--to-frame="):to_frame=int(arg.get_slice("=",1))
	var vp:=SubViewport.new();vp.size=Vector2i(1024,1024) if "--bake" in args else Vector2i(1536,1280);vp.transparent_bg=true
	vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(vp)
	var flash_layer:=CanvasLayer.new();flash_layer.layer=8;vp.add_child(flash_layer)
	var white:=ColorRect.new();white.size=Vector2(vp.size);white.color=Color(1,1,1,0);flash_layer.add_child(white)
	for id: String in ["bat","snake","goat","goat_eye"]:
		if not selected.is_empty() and selected!=id:continue
		var actor=VISUAL.new();actor.position=Vector2(vp.size)*.5;vp.add_child(actor);actor.setup(id)
		if "--audit" in args:
			actor.events.assign([{"kind":"start","time":.4},{"kind":"hurt","time":1.5}]);actor.dirty=true
			for time: float in [1.35,1.58,2.2,3.4]:
				actor.glow_strength=1.;actor.sample(time)
				await _image(vp,output+id+"/alignment/%04d-full.png" % roundi(time*60))
				var points=[]
				for item in actor.eyes+actor.mouths:points.append([item.node.position.x+actor.position.x,item.node.position.y+actor.position.y])
				FileAccess.open(output+id+"/alignment/%04d.json" % roundi(time*60),FileAccess.WRITE).store_string(JSON.stringify(points))
				actor.glow_strength=0.;actor._sample_effects()
				await _image(vp,output+id+"/alignment/%04d-body.png" % roundi(time*60))
		elif "--bake" in args:
			actor.sample_clip("death",float(actor.config["break"]))
			await _image(vp,"res://assets/bosses/animation_studies/"+id+"/death_pose.png")
			if id=="goat_eye":
				# 同姿势单独烘焙眼罩，裂解时跟随各骨片移动，强度仍可独立调整。
				var state=actor.skeleton.get_animation_state()
				for value in [0,1]:
					state.set_animation("eye_stencil",false,2).set_track_time(float(value))
					actor.skeleton.update_skeleton(0.)
					await _image(vp,"res://assets/bosses/animation_studies/"+id+"/death_eyes_"+("white" if value==1 else "black")+".png")
		elif "--poses" in args:
			for phase: String in ["attack_start","attack_loop","attack_end","death"]:
				for i in 5:
					var duration:float=actor.config.get(phase.get_slice("_",1),actor.config.death) if phase!="death" else actor.config.death
					actor.sample_clip(phase,duration*i/4.)
					await _image(vp,output+id+"/poses/%s-%d.png" % [phase,i])
		else:
			var clips: Array[String]=["attack","hurt","death","combo"]
			if id=="goat":clips.append_array(["phase_break","two_phase"])
			for clip: String in clips:
				if not selected_clip.is_empty() and selected_clip!=clip:continue
				actor.reset()
				var end:=3.
				if clip in ["attack","combo"]:
					actor.events.assign([{"kind":"start","time":.4},{"kind":"end","time":.4+float(actor.config.start)+float(actor.config.loop)*1.1}])
					end=.4+float(actor.config.start)+float(actor.config.loop)*2.+float(actor.config.end)+.4
					if clip=="combo":
						actor.events.insert(1,{"kind":"hurt","time":1.0});actor.events.insert(2,{"kind":"hurt","time":1.1})
				elif clip=="hurt":actor.events.assign([{"kind":"hurt","time":.7}]);end=1.8
				elif clip=="phase_break" or clip=="death" and id=="goat":actor.events.assign([{"kind":"phase_break","time":.4}]);end=4.2
				elif clip=="two_phase":
					actor.events.assign([{"kind":"phase_break","time":.4},{"kind":"start","time":3.7},{"kind":"end","time":4.6},{"kind":"death","time":6.7}]);end=14.
				else:actor.events.assign([{"kind":"death","time":.4}]);end=.4+float(actor.config.death)+.3
				actor.dirty=true
				for i in ceili(end*60):
					if i<from_frame or i>=to_frame:continue
					if "--quick" in args and i not in [18,60,90,130,180]:continue
					actor.sample(i/60.)
					white.color=Color(1,1,1,actor.white_flash)
					await _image(vp,output+id+"/"+clip+"/%04d.png" % i)
				print("CAPTURE ",id," ",clip," ",end," sec")
		actor.free()
	quit()
func _image(vp: SubViewport,path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	await process_frame;RenderingServer.force_draw()
	vp.get_texture().get_image().save_png(path)
