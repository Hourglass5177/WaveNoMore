extends SceneTree
## 双阶段事件、皮肤、骨骼、裂光与白场都必须可由绝对时间恢复。
const VISUAL=preload("res://tools/boss_animation/boss_visual.gd")
var failures: Array[String]=[]
func _initialize() -> void:_run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		if failures.size()<15:push_error(message)
func _run() -> void:
	var a=VISUAL.new();root.add_child(a);a.setup("goat")
	var b=VISUAL.new();root.add_child(b);b.setup("goat")
	for at: float in [0.,.35,1.2,3.0]:
		a.reset()
		if at>0.:
			a.request("start",.1);a.request("hurt",at-.01)
		check(a.request("phase_break",at),"接受转阶段 "+str(at))
		check(not a.request("phase_break",at+.01),"忽略重复转阶段")
		check(not a.request("hurt",at+.1) and not a.request("start",at+.2),"转阶段接管操作")
		a.sample(at+2.)
		check(is_equal_approx(a.side_eye_glow,1.),"觉醒两侧眼睛变白")
		check(a.skeleton.get_animation_state().get_track(2).get_track_time()==0.,"额眼保留虹膜")
		a.sample(at+3.)
		check(a.mode=="idle" and a.form=="goat_eye" and a.skeleton.visible,"真眼阶段恢复常态")
		check(a.side_eye_glow==0.,"常态侧眼光退尽")
		check(a.request("start",at+3.1) and a.request("hurt",at+3.2),"第二阶段可攻击受击")
		check(a.request("death",at+3.3),"第二阶段死亡")
		for age: float in [0.,.3,.7,1.5,2.09,2.11,3.8,4.8]:
			a.sample(at+3.3+age)
			check(is_equal_approx(a.skeleton.get_animation_state().get_track(2).get_track_time(),1.),"死亡三眼持续白光 "+str(age))
			check(is_equal_approx(a.side_eye_glow,1.),"死亡侧眼白光不熄灭")
			if age>=2.1:
				for item in a.eyes:check(not item.node.visible,"裂解后不残留固定眼晕")
		a.sample(at+10.3)
		check(not a.skeleton.visible and not a.goat_fracture.visible and a.white_flash==0.,"最终完全消失")
	a.reset()
	a.events.assign([{"kind":"start","time":.1},{"kind":"hurt","time":.35},{"kind":"phase_break","time":.4},{"kind":"start","time":3.7},{"kind":"end","time":4.6},{"kind":"death","time":6.7}]);a.dirty=true
	b.events.assign(a.events);b.dirty=true
	for frame in 841:
		var time:=frame/60.;a.sample(time)
		if frame%13!=0:continue
		b.dirty=true;b.sample(time)
		check(a.form==b.form and a.mode==b.mode,"定位形态 "+str(time))
		check(is_equal_approx(a.white_flash,b.white_flash),"定位白光 "+str(time))
		var aa=a.skeleton.get_skeleton().get_bones();var bb=b.skeleton.get_skeleton().get_bones()
		for i in aa.size():
			var x: Transform2D=aa[i].get_global_transform();var y: Transform2D=bb[i].get_global_transform()
			check(x.origin.distance_to(y.origin)<.01 and x.x.distance_to(y.x)<.01,"定位骨骼 %d %.3f" % [i,time])
		for i in a.goat_fracture.rays.size():
			var x: MeshInstance2D=a.goat_fracture.rays[i].node;var y: MeshInstance2D=b.goat_fracture.rays[i].node
			check(x.position.distance_to(y.position)<.001 and is_equal_approx(x.rotation,y.rotation),"定位光束")
		var flash: float=a.white_flash;var before: Transform2D=aa[0].get_global_transform();a.sample(time)
		check(flash==a.white_flash and before==aa[0].get_global_transform(),"暂停冻结")
	for age: float in [5.15,5.4,5.649]:
		a.sample(6.7+age);check(is_equal_approx(a.white_flash,1.),"白场保持 "+str(age))
	a.sample(6.7+6.65);check(a.white_flash==0.,"白场退尽")
	a.reset();check(a.form=="goat" and a.mode=="idle" and a.white_flash==0.,"重置恢复图案眼")
	check(not a.goat_fracture.visible,"重置无裂光残留")
	check(a.body_material.get_shader_parameter("light")==0.,"无全身提亮")
	a.free();b.free()
	print("GOAT phases failures: ",failures.size());quit(0 if failures.is_empty() else 1)
