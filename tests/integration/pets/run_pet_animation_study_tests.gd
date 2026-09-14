extends SceneTree
## 只检验审看素材和播放，不装配或改写正式随从技能。
const ACTOR := preload("res://src/presentation/pets/animated_pet_visual.gd")
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func pose(actor: Node) -> Array:
	var points := []
	for bone in actor.skeleton.get_skeleton().get_bones(): points.append(bone.get_global_transform())
	return points
func same(a: Array, b: Array, tolerance:=0.001) -> bool:
	for i in a.size():
		if a[i].origin.distance_to(b[i].origin)>tolerance or a[i].x.distance_to(b[i].x)>tolerance: return false
	return true

func fire_state(actor: Node) -> Array:
	var result := []
	for flame in actor.breath.flames:
		result.append([flame.visible,flame.transform,flame.material.get_shader_parameter("age")])
	return result

func same_fire(one: Array, two: Array) -> bool:
	# Spine 骨骼矩阵使用 float32；小于万分之一设计像素的累加差不构成姿态差异。
	for i in one.size():
		if one[i][0]!=two[i][0] or absf(one[i][2]-two[i][2])>0.0000001: return false
		if one[i][1].origin.distance_to(two[i][1].origin)>0.0001: return false
		if one[i][1].x.distance_to(two[i][1].x)>0.00001: return false
	return true

func light_state(actor: Node) -> Array:
	var result := []
	for piece in actor.trigger_lights._pieces:
		result.append([piece.node.visible,piece.node.transform,piece.surface.get_shader_parameter("age"),piece.surface.get_shader_parameter("amount")])
	return result

func check_lights(actor: Node) -> void:
	actor.clear_events()
	actor.trigger(.5)
	actor.sample(1.08)
	var frozen := light_state(actor)
	check(actor.trigger_lights._pieces.all(func(p): return p.node.visible),"释放段胸波或三眼可见")
	actor.sample(1.08)
	check(frozen==light_state(actor),"新光效暂停冻结")
	actor.sample(1.16)
	actor.sample(1.08)
	check(frozen==light_state(actor),"新光效定位恢复位置与强度")
	actor.die(1.08)
	actor.sample(1.08)
	check(actor.trigger_lights._pieces.all(func(p): return not p.node.visible),"死亡立即取消光效")
	actor.sample(1.07)
	check(actor.trigger_lights._pieces.all(func(p): return p.node.visible),"回拖到死亡前恢复光效")
	actor.clear_events()
	check(actor.trigger_lights._pieces.all(func(p): return not p.node.visible),"重置清除新光效")

func check_breath(actor: Node) -> void:
	check(actor.breath.flames.size()==3,"苹果蛇三嘴各有独立火焰")
	actor.clear_events()
	check(actor.breath.flames.all(func(f): return not f.visible),"常态不喷火")
	actor.trigger(.5)
	actor.sample(.74)
	check(actor.breath.flames[0].visible and not actor.breath.flames[1].visible and not actor.breath.flames[2].visible,"中间头先喷火")
	actor.sample(.83)
	check(actor.breath.flames[1].visible and not actor.breath.flames[2].visible,"右头第二口火")
	actor.sample(.91)
	check(actor.breath.flames.all(func(f): return f.visible),"三口火短暂错开交叠")
	var frozen := fire_state(actor)
	actor.sample(.91)
	check(frozen==fire_state(actor),"喷火暂停保持位置与年龄")
	actor.sample(1.0)
	actor.sample(.91)
	check(same_fire(frozen,fire_state(actor)),"喷火回拖恢复相同形状与位置")
	var origin: Vector2=actor.breath.flames[0].global_position
	actor.rotation=PI
	actor.scale=Vector2.ONE*1.5
	actor.sample(.91)
	check(actor.breath.flames[0].global_position.distance_to(-origin*1.5)<.001,"喷火随所属世界旋转和缩放")
	actor.rotation=0;actor.scale=Vector2.ONE
	actor.die(.91)
	actor.sample(.91)
	check(actor.breath.flames.all(func(f): return not f.visible),"死亡打断喷火")
	actor.sample(.90)
	check(actor.breath.flames.all(func(f): return f.visible),"回拖到死亡前恢复喷火")
	actor.clear_events()
	check(actor.breath.flames.all(func(f): return not f.visible),"重置清除全部火焰")
	actor.sample_clip("trigger",.60)
	check(actor.breath.flames.all(func(f): return f.visible),"延长后0.60秒三口火仍在喷吐")
	actor.sample_clip("trigger",1.08)
	check(not actor.breath.flames[0].visible and not actor.breath.flames[1].visible and actor.breath.flames[2].visible,"收招时依次熄灭，最后一口持续至1.13秒")
	actor.sample_clip("trigger",1.15)
	check(actor.breath.flames.all(func(f): return not f.visible),"技能收招前火焰已熄灭")
	actor.sample_clip("trigger",.45)
	check(actor.breath.flames.all(func(f): return f.visible),"离线图集与审看共用喷火")
	actor.clear_events()

## 独立参考实例只向前推进 Spine，不调用 sample() 的事件重建。
func incremental_pose(id: String, death_time: float) -> Array:
	var reference = ACTOR.new()
	root.add_child(reference)
	reference.setup(id)
	var state = reference.skeleton.get_animation_state()
	var boundaries := [{"time":.5,"kind":"trigger"}]
	if death_time>=0: boundaries.append({"time":death_time,"kind":"death"})
	var clock := 0.0
	var target := death_time+.07 if death_time>=0 else .9
	for event: Dictionary in boundaries:
		while clock<float(event.time)-0.000001:
			var next := minf(clock+1.0/120.0,event.time)
			reference.skeleton.update_skeleton(next-clock)
			clock=next
		state.set_animation(event.kind,false,0).set_mix_duration(.12 if event.kind=="death" else .08)
		reference.skeleton.update_skeleton(0)
	while clock<target-0.000001:
		var next := minf(clock+1.0/120.0,target)
		reference.skeleton.update_skeleton(next-clock)
		clock=next
	reference.skeleton.update_skeleton(0)
	var result:=pose(reference)
	reference.free()
	return result
func _run() -> void:
	for id: String in ["bat","snake","sheep"]:
		var actor = ACTOR.new()
		root.add_child(actor)
		actor.setup(id)
		actor.sample_clip("idle",0)
		var rest:=pose(actor)
		actor.sample_clip("idle",float(actor.config.idle))
		check(same(rest,pose(actor)),id+" 常态首尾姿态一致")
		actor.sample_clip("idle",float(actor.config.idle)*.23)
		check(not same(rest,pose(actor)),id+" 常态有实际骨骼运动")
		actor.clear_events()
		check(actor.trigger(.5),id+" 接受技能")
		check(not actor.trigger(.55) and actor.events.size()==1,id+" 密集技能不重启或排队")
		actor.sample(.54)
		var frozen:=pose(actor)
		for i in 20: actor.sample(.54)
		check(same(frozen,pose(actor)),id+" 暂停不积累骨骼偏移")
		actor.sample(.9)
		var direct:=pose(actor)
		for i in 90: actor.sample(i/100.0)
		actor.sample(.9)
		check(same(direct,pose(actor)),id+" 定位与连续播放混合相同")
		check(same(direct,incremental_pose(id,-1)),id+" 定位与120Hz原生逐步推进相同")
		actor.sample(2)
		var returned:=pose(actor)
		actor.sample_clip("idle",2)
		check(same(returned,pose(actor)),id+" 技能后接回原呼吸相位")
		for death_time: float in [.25,.54,.85]:
			actor.clear_events()
			actor.trigger(.5)
			actor.sample(death_time)
			var before:=pose(actor)
			actor.die(death_time)
			actor.sample(death_time)
			check(same(before,pose(actor)),id+" 死亡起点保持当前姿态")
			if death_time>=.5:
				actor.sample(death_time+.07)
				var reference := incremental_pose(id,death_time)
				check(same(pose(actor),reference),id+" 嵌套死亡混合与原生推进相同")
			check(not actor.trigger(death_time+.03),id+" 死亡后禁止技能")
			actor.sample(death_time+1.4)
			check(actor.ashes.visible and not actor.skeleton.visible,id+" 1.4秒切换灰烬")
			actor.sample(death_time+2.05)
			check(not actor.ashes.visible and not actor.skeleton.visible,id+" 灰烬结束完全隐藏")
		actor.clear_events()
		check(same(rest,pose(actor)) and not actor.ashes.visible and actor.skeleton.visible,id+" 重置清除姿态及灰烬")
		var frames: SpriteFrames=load(ACTOR.FOLDER+id+"/frames.tres")
		check(frames.has_animation("idle") and frames.has_animation("trigger") and frames.has_animation("death"),id+" 三条帧动画可加载")
		check(frames.get_animation_speed("idle")==30 and frames.get_animation_loop("idle") and not frames.get_animation_loop("death"),id+" 图集30fps与循环属性正确")
		var death_frames:=frames.get_frame_count("death")
		check(is_equal_approx(frames.get_frame_duration("death",death_frames-2),.5),id+" 死亡2.05秒边界保留半帧时长")
		check(frames.get_frame_count("trigger")==roundi(float(actor.config.trigger)*30),id+" 技能图集时长与骨骼一致")
		if id=="snake": check_breath(actor)
		else: check_lights(actor)
		actor.free()
	var review = load("res://scenes/tools/pet_animation/review.tscn").instantiate()
	root.add_child(review)
	await process_frame
	review.playing=false
	review.clock=.8
	for actor in review.actors: actor.trigger(.8)
	review._sample()
	review.timeline.value=.84
	check(is_equal_approx(review.clock,.84) and not review.playing,"审看时间条可定位并暂停")
	review.reset()
	check(review.actors.all(func(a): return a.events.is_empty()),"审看重置清空两界六个实例")
	review._layout_actors()
	for i in 3:
		check((review.actors[i].position+review.actors[i+3].position).distance_to(review.stage.size)<.001,"审看两界中心对称")
	review.queue_free()
	await process_frame
	print("Pet animation studies: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
