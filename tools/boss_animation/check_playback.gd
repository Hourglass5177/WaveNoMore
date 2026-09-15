extends SceneTree
## 对比连续推进与定位，检查叠加轨道、喷口跟随与羊头光照范围。
const VISUAL=preload("res://tools/boss_animation/boss_visual.gd")
var failures: Array[String]=[]
func _initialize() -> void:_run.call_deferred()
func check(value: bool,label: String) -> void:
	if not value:
		failures.append(label)
		if failures.size()<12:push_error(label)
func pose(actor) -> Array:
	var values=[]
	for bone in actor.skeleton.get_skeleton().get_bones():values.append(bone.get_global_transform())
	return values
func _run() -> void:
	var planning:=PlanningParameters.read(PlanningParameters.WORKBOOK_PATH)
	check(planning.errors.is_empty(),"planning workbook read")
	for key in ["glow_strength","effect_scale","fragment_multiplier"]:check(planning.values.has("boss/"+key),"planning "+key)
	for id: String in ["bat","snake","goat","goat_eye"]:
		var a=VISUAL.new();root.add_child(a);a.setup(id)
		var b=VISUAL.new();root.add_child(b);b.setup(id)
		await process_frame
		check(a.request("start",.2),id+" start")
		check(not a.request("start",.3),id+" duplicate attack")
		check(a.request("hurt",1.),id+" hurt")
		check(not a.request("hurt",1.1),id+" duplicate hurt")
		check(a.request("end",1.5),id+" end")
		var stop:float=.2+float(a.config.start)+ceil((1.5-.2-float(a.config.start))/float(a.config.loop))*float(a.config.loop)
		a.sample(stop-.001);check(a.mode=="attack_loop",id+" finish loop")
		a.sample(stop+.001);check(a.mode=="attack_end",id+" end transition")
		a.request("death",stop+.15)
		check(not a.request("start",stop+.2),id+" death priority")
		b.events.assign(a.events);b.dirty=true;a.dirty=true
		for frame in 420:
			var time:=frame/60.;a.sample(time)
			if frame%19!=0:continue
			b.dirty=true;b.sample(time)
			var pa:=pose(a);var pb:=pose(b)
			for i in pa.size():
				var difference:float=max(pa[i].origin.distance_to(pb[i].origin),pa[i].x.distance_to(pb[i].x),pa[i].y.distance_to(pb[i].y))
				check(difference<.01,id+" seek bone "+str(i)+" at "+str(time)+" error "+str(difference))
			for i in a.mouths.size():
				check(a.mouths[i].node.position.distance_to(b.mouths[i].node.position)<.01,id+" seek mouth")
				check(absf(a.mouths[i].node.rotation-b.mouths[i].node.rotation)<.0001,id+" seek flame direction")
				check(is_equal_approx(a.mouths[i].node.material.get_shader_parameter("amount"),b.mouths[i].node.material.get_shader_parameter("amount")),id+" seek flame age")
				if a.mouths[i].node.visible:check(a.mouths[i].node.position.distance_to(a._point(a.mouths[i]))<.001,id+" flame origin at "+str(time))
			for i in a.rings.size():
				check(a.rings[i].node.visible==b.rings[i].node.visible,id+" seek wave visibility")
				if a.rings[i].node.visible:check(a.rings[i].node.position.distance_to(b.rings[i].node.position)<.01,id+" detached wave origin")
			if id.begins_with("goat"):check(a.body_material.get_shader_parameter("light")==0.,id+" no body glow")
			var before:=pose(a);a.sample(time);check(before==pose(a),id+" pause")
		a.reset();check(a.mode=="idle" and (a.fragments==null or not a.fragments.visible),id+" reset")
		for trigger:float in [0.,.3,1.2,3.]:
			a.reset();b.reset()
			if trigger>0.:
				a.request("start",.1);b.request("start",.1)
			check(a.request("hurt",trigger),id+" phase hurt")
			a.sample(trigger+float(a.config.hurt)+.05);b.sample(a.clock)
			var pa:=pose(a);var pb:=pose(b)
			for i in pa.size():check(pa[i].origin.distance_to(pb[i].origin)<.01,id+" additive recovery")
			check(a.request("death",a.clock),id+" phase death")
			a.sample(a.clock+float(a.config.death)+.01)
			if id=="goat":check(a.mode=="idle" and a.form=="goat_eye" and a.skeleton.visible,id+" phase restored")
			else:check(not a.skeleton.visible and (a.fragments==null or not a.fragments.visible),id+" fully hidden")
		a.free();b.free();print("CHECK ",id)
	print("BOSS playback failures: ",failures.size());quit(0 if failures.is_empty() else 1)

