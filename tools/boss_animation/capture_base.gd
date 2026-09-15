extends SceneTree
## 实际运行时采样基础动画，同时输出骨骼标记，供分件与光效定位。
func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1000, 900)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	for id: String in ["bat", "snake", "goat", "goat_eye"]:
		var folder := "res://assets/bosses/animation_studies/"+id+"/"
		var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder+"animation.json"))
		var actor=load("res://tools/boss_animation/boss_visual.gd").new()
		actor.position=Vector2(500,450);vp.add_child(actor);actor.setup(id)
		var samples=[]
		for t: float in [0.,.5,1.,1.5,2.,3.,3.999]:
			actor.sample_clip(config.idle,t)
			await process_frame
			var bones={}
			var definitions:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"boss.spine-json"))
			var index:=0
			for bone in actor.skeleton.get_skeleton().get_bones():
				var transform:Transform2D=bone.get_global_transform()
				bones[definitions.bones[index].name]=[transform.x.x,transform.x.y,transform.y.x,transform.y.y,transform.origin.x,transform.origin.y];index+=1
			samples.append({"time":t,"bones":bones})
			RenderingServer.force_draw()
			vp.get_texture().get_image().save_png("res://build/boss-audit/%s-base-%d.png" % [id,roundi(t*1000)])
		FileAccess.open("res://build/boss-audit/"+id+"-sampled-bones.json",FileAccess.WRITE).store_string(JSON.stringify(samples))
		print("BASE ",id)
		actor.free()
	quit()
