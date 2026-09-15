extends Node2D
## 正式游戏与素材审看共用的表现播放器，只消费显式时钟与动作请求。
const ROOT := "res://assets/bosses/animation_studies/"
const RING := preload("res://shaders/bosses/ring.gdshader")
const FLAME := preload("res://shaders/bosses/flame.gdshader")
const AURA := preload("res://shaders/bosses/aura.gdshader")
const FRAGMENTS := preload("res://shaders/bosses/fragments.gdshader")
const GOAT_FRACTURE := preload("res://src/presentation/actors/boss_goat_fracture.gd")
@export var glow_strength := 1.0
@export var effect_scale := 1.0
@export var fragment_multiplier := 1.0
var config: Dictionary
var skeleton: SpineSprite
var effects := Node2D.new()
var fragments: MeshInstance2D
var events: Array[Dictionary] = []
var clock := 0.0
var mode := "idle"
var phase_start := 0.0
var phase_end := INF
var loop_start := INF
var death_time := INF
var hurt_end := INF
var stop_pending := false
var cursor := 0
var dirty := true
var next_ring := INF
var ring_serial := 0
var ring_stage := 0
var flame_tail: Array[float] = []
var lights: Array[Dictionary] = []
var mouths: Array[Dictionary] = []
var eyes: Array[Dictionary] = []
var rings: Array[Dictionary] = []
var source_textures: Array[Texture2D] = []
var body_material: ShaderMaterial
var form := ""
var initial_form := ""
var goat_fracture: Node2D
var white_flash := 0.0
var side_eye_glow := 0.0

func setup(id: String) -> void:
	initial_form=id;form=id
	config=JSON.parse_string(FileAccess.get_file_as_string(ROOT+id+"/animation.json"))
	skeleton=SpineSprite.new()
	# 审看工具直接读取派生源，避免后台编辑器导入尚未完成时采到上一次的动作。
	for name in DirAccess.get_files_at(ROOT+id):
		if name=="skeleton.png" or name.begins_with("eye_core_") and name.ends_with(".png") or name in config.get("texture_pages",[]):
			var path:=ROOT+id+"/"+name
			var texture:=_source_texture(path);texture.take_over_path(path);source_textures.append(texture)
	var data:=SpineSkeletonDataResource.new()
	var atlas:=SpineAtlasResource.new();atlas.load_from_atlas_file(ROOT+id+"/boss.atlas")
	var file:=SpineSkeletonFileResource.new();file.load_from_file(ROOT+id+"/boss.spine-json")
	data.atlas_res=atlas;data.skeleton_file_res=file;skeleton.skeleton_data_res=data
	body_material=ShaderMaterial.new();body_material.shader=preload("res://shaders/bosses/body.gdshader")
	if id=="bat":body_material.set_shader_parameter("tint",Color(1.,.45,.5))
	skeleton.normal_material=body_material
	skeleton.scale=Vector2.ONE*float(config.unit)
	skeleton.position=-Vector2(config.center[0],config.center[1])*float(config.unit)
	add_child(skeleton)
	skeleton.set_update_mode(SpineConstant.UpdateMode_Manual)
	if id.begins_with("goat"):_set_form(id)
	add_child(effects)
	for definition: Dictionary in config.get("lights",[]):
		var item:=_bound(definition);item.node=_quad(Vector2(95,95),AURA);lights.append(item)
	for definition: Dictionary in config.get("mouths",[]):
		var item:=_bound(definition);item.node=_quad(Vector2(600,320),FLAME)
		item.node.mesh.center_offset=Vector3(260,0,0)
		item.aura=_quad(Vector2(125,125),AURA)
		item.node.material.set_shader_parameter("phase",float(mouths.size())*1.73)
		mouths.append(item)
	for definition: Dictionary in config.get("eyes",[]):
		var item:=_bound(definition);item.node=_quad(Vector2(100,80),AURA);eyes.append(item)
	for i in 16:
		var node:=_quad(Vector2(800,800),RING)
		rings.append({"node":node,"time":-INF,"duration":.75})
	var path:=ROOT+id+"/death_pose.png"
	if FileAccess.file_exists(path) and not id.begins_with("goat"):
		fragments=_quad(Vector2(1024,1024),FRAGMENTS)
		fragments.texture=_source_texture(path)
		var count:=int((36 if id.begins_with("goat") else 72)*fragment_multiplier)
		fragments.mesh=NoteFragmentHost._template(Vector2(1024,1024),maxi(count,8),int(100*fragment_multiplier)).duplicate()
		fragments.mesh.custom_aabb=AABB(Vector3(-1100,-1100,-1),Vector3(2200,2200,2))
		fragments.material.set_shader_parameter("kind_id",2 if id.begins_with("goat") else (1 if id=="snake" else 0))
		fragments.material.set_shader_parameter("duration",float(config.death)-float(config["break"]))
	if id.begins_with("goat"):
		goat_fracture=GOAT_FRACTURE.new();effects.add_child(goat_fracture);goat_fracture.setup(self)
	sample(0.)

func _set_form(value: String) -> void:
	form=value
	skeleton.get_skeleton().set_skin_by_name(value)
	skeleton.get_skeleton().set_slots_to_setup_pose()
	skeleton.update_skeleton(0.)

func _source_texture(path: String) -> ImageTexture:
	var image:=Image.new();image.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	return ImageTexture.create_from_image(image)

func _quad(size: Vector2, shader: Shader) -> MeshInstance2D:
	var item:=MeshInstance2D.new();var mesh:=QuadMesh.new();mesh.size=size;item.mesh=mesh
	var material:=ShaderMaterial.new();material.shader=shader;item.material=material
	effects.add_child(item);item.hide();return item

func _bound(definition: Dictionary) -> Dictionary:
	var item:=definition.duplicate(true);item.binds=[]
	for bind: Dictionary in definition.bindings:
		# Spine 导出局部 Y 向上；Godot 骨骼 Transform2D 的局部坐标已经转为 Y 向下。
		item.binds.append({"bone":skeleton.get_skeleton().find_bone(bind.bone),"point":Vector2(bind.point[0],-bind.point[1]),"weight":float(bind.weight),"direction":Vector2(bind.get("direction",[1,0])[0],bind.get("direction",[1,0])[1])})
	return item

func _point(item: Dictionary) -> Vector2:
	var result:=Vector2.ZERO
	for bind: Dictionary in item.binds:result+=to_local(bind.bone.get_global_transform()*bind.point)*bind.weight
	return result

func _direction(item: Dictionary) -> Vector2:
	var result:=Vector2.ZERO
	for bind: Dictionary in item.binds:
		var transform: Transform2D=global_transform.affine_inverse()*bind.bone.get_global_transform()
		result+=(transform.x*bind.direction.x+transform.y*bind.direction.y)*bind.weight
	return result.normalized()

func reset() -> void:
	events.clear();dirty=true;sample(0.)

func request(action: String, at: float) -> bool:
	sample(at)
	if mode in ["death","phase_break"]:return false
	if action=="phase_break" and form!="goat":return false
	if action=="death" and form=="goat":action="phase_break"
	if action=="start" and mode!="idle":return false
	if action=="end" and mode not in ["attack_start","attack_loop"]:return false
	if action=="hurt" and is_finite(hurt_end) and at<hurt_end:return false
	while not events.is_empty() and float(events.back().time)>at:events.pop_back()
	if action in ["death","phase_break"]:
		while not events.is_empty() and is_equal_approx(float(events.back().time),at):events.pop_back()
	events.append({"kind":action,"time":at});dirty=true;sample(at);return true

func _set_clip(name: String, at: float, duration: float=INF, mix: float=.08) -> void:
	mode=name;phase_start=at;phase_end=at+duration
	var entry=skeleton.get_animation_state().set_animation(str(config.idle) if name=="idle" else name,name in ["idle","attack_loop"],0)
	entry.set_mix_duration(mix)
	if name=="idle":entry.set_track_time(fposmod(at,4.))
	skeleton.update_skeleton(0.)

func _restart() -> void:
	clock=0.;cursor=0;death_time=INF;hurt_end=INF;loop_start=INF;next_ring=INF;stop_pending=false;ring_serial=0;ring_stage=0;flame_tail.clear()
	for ring in rings:ring.time=-INF
	skeleton.get_animation_state().clear_tracks();skeleton.get_skeleton().set_to_setup_pose()
	if initial_form.begins_with("goat"):_set_form(initial_form)
	skeleton.get_skeleton().set_time(0.)
	_set_clip("idle",0.,INF,0.)
	dirty=false

func _event(event: Dictionary) -> void:
	var at: float=event.time
	match str(event.kind):
		"start":
			stop_pending=false;loop_start=at+float(config.start);_set_clip("attack_start",at,float(config.start))
		"end":
			stop_pending=true
			if mode=="attack_loop":phase_end=loop_start+maxf(1.,ceil((at-loop_start)/float(config.loop)-.000001))*float(config.loop)
		"hurt":
			if is_finite(hurt_end) and at<hurt_end:return
			hurt_end=at+float(config.hurt)
			var entry=skeleton.get_animation_state().set_animation("hurt",false,1)
			entry.set_additive(true);entry.set_mix_duration(0.)
		"phase_break":_start_phase_break(at)
		"death":
			if form=="goat":
				_start_phase_break(at);return
			flame_tail.clear()
			for item in mouths:
				var amount:=smoothstep(float(item.delay),float(item.delay)+.16,at-loop_start) if mode=="attack_loop" else (1.-smoothstep(float(item.delay)*.5,.55,at-phase_start) if mode=="attack_end" else 0.)
				flame_tail.append(amount)
			death_time=at;hurt_end=INF;next_ring=at+float(config.burst)
			if form.begins_with("goat"):next_ring=INF
			skeleton.get_animation_state().clear_track(1)
			_set_clip("death",at,INF,.10)

func _start_phase_break(at: float) -> void:
	hurt_end=INF;next_ring=INF;stop_pending=false
	skeleton.get_animation_state().clear_track(1)
	_set_form("goat_eye")
	_set_clip("phase_break",at,3.,.10)

func _transition(at: float) -> void:
	match mode:
		"attack_start":
			_set_clip("attack_loop",at,float(config.loop) if stop_pending else INF,0.)
			if str(config.id)=="bat":next_ring=at;ring_stage=0
		"attack_loop":
			next_ring=INF;_set_clip("attack_end",at,float(config.end),0.)
		"attack_end":_set_clip("idle",at,INF,.15)
		"phase_break":_set_clip("idle",at,INF,.15)

func _step(delta: float) -> void:
	# 只在混合期间细步推进，维持 Spine 的旋转混合方向；稳定段可直接跨到事件时间。
	var remaining:=delta
	while remaining>0. and skeleton.get_animation_state().get_track(0).get_mixing_from()!=null:
		var step:=minf(remaining,1./120.);skeleton.update_skeleton(step);remaining-=step
	if remaining>0.:skeleton.update_skeleton(remaining)

func _emit_ring(at: float, item: Dictionary, radius: float, delay: float=0., burst: bool=false) -> void:
	var ring:=rings[ring_serial%rings.size()];ring_serial+=1
	ring.time=at+delay;ring.duration=.95 if burst else .75
	ring.node.position=_point(item)
	ring.node.material.set_shader_parameter("radius",radius)
	ring.node.material.set_shader_parameter("duration",ring.duration)
	ring.node.material.set_shader_parameter("burst",1. if burst else 0.)

func sample(target: float) -> void:
	if skeleton==null:return
	# Spine 会跳过不可见实例的骨架更新；采样完成后再决定是否由碎片替代主体。
	skeleton.show()
	if dirty or target<clock:_restart()
	while true:
		var event_time:=float(events[cursor].time) if cursor<events.size() else INF
		var boundary:=minf(minf(event_time,phase_end),minf(next_ring,hurt_end))
		if boundary>target:break
		_step(maxf(0.,boundary-clock));clock=boundary
		if event_time==boundary:
			_event(events[cursor]);cursor+=1
		if phase_end==boundary:_transition(boundary)
		if hurt_end==boundary:
			skeleton.get_animation_state().clear_track(1);hurt_end=INF
		if next_ring==boundary:
			if mode=="death":
				var origin: Dictionary=lights[0] if not lights.is_empty() else (eyes[0] if not eyes.is_empty() else mouths[0])
				_emit_ring(boundary,origin,330.,0.,true);next_ring=INF
			else:
				# 副波在真正离开翼纹的时刻取位置，不能提前缓存上一拍的翼部姿势。
				if ring_stage==0:
					_emit_ring(boundary,lights[0],float(lights[0].radius));next_ring+=.1;ring_stage=1
				else:
					for i in range(1,lights.size()):_emit_ring(boundary,lights[i],float(lights[i].radius))
					next_ring+=.5;ring_stage=0
	_step(maxf(0.,target-clock));clock=target
	_sample_effects()

func _sample_effects() -> void:
	var glow:=0.;var attack_age:=clock-loop_start;var death_age:=clock-death_time
	if mode=="attack_start":glow=smoothstep(float(config.start)*.25,float(config.start),clock-phase_start)
	elif mode=="attack_loop":glow=.93+.07*cos((clock-loop_start)/float(config.loop)*TAU)
	elif mode=="attack_end":glow=1.-smoothstep(0.,float(config.end),clock-phase_start)
	elif mode=="death":glow=smoothstep(.6,float(config.burst),death_age)*(1.-smoothstep(float(config.burst)+.12,float(config["break"])+.25,death_age))
	# 死亡从第一帧持续点亮三眼；裂解后亮层由同一分块网格接替。
	if form.begins_with("goat") and mode=="death":glow=1.
	var reveal_age:=clock-phase_start
	side_eye_glow=smoothstep(1.05,1.70,reveal_age)*(1.-smoothstep(2.65,3.,reveal_age))*glow_strength if mode=="phase_break" else 0.
	if form.begins_with("goat") and mode=="death":side_eye_glow=glow_strength
	# 羊头只点亮眼部附件，手部、飘带与角骨保持原画亮度。
	body_material.set_shader_parameter("light",0. if str(config.id).begins_with("goat") else glow*glow_strength*(1. if mode=="death" else .12))
	for item in lights+eyes:
		item.node.position=_point(item);item.node.visible=glow>0.;item.node.scale=Vector2.ONE*effect_scale
		item.node.material.set_shader_parameter("amount",glow*glow_strength)
		if not eyes.is_empty():item.node.material.set_shader_parameter("tint",Color(1.,.97,.88) if mode=="death" else Color(1.,.78,.35))
	if not eyes.is_empty():
		for i in [1,2]:
			var item: Dictionary=eyes[i]
			item.node.material.set_shader_parameter("tint",Color(1.,.97,.88) if mode in ["phase_break","death"] else Color(1.,.78,.35))
			if mode=="phase_break":
				item.node.visible=side_eye_glow>0.;item.node.material.set_shader_parameter("amount",side_eye_glow*1.35)
	if mode=="death" and goat_fracture==null and death_age>=float(config["break"]) and not (lights+eyes).is_empty():
		var last: Dictionary=(lights+eyes)[0]
		last.node.visible=death_age<float(config.death)
		last.node.scale=Vector2.ONE*.4
		last.node.material.set_shader_parameter("amount",.6*(1.-smoothstep(float(config.death)-.5,float(config.death),death_age))*glow_strength)
	if not eyes.is_empty():
		var state=skeleton.get_animation_state()
		var eye=state.get_track(2) if state.get_num_tracks()>2 else null
		var eye_clip:="white_eye_light" if goat_fracture!=null and mode=="death" else "eye_light"
		if eye==null or eye.get_animation().get_name()!=eye_clip:
			eye=state.set_animation(eye_clip,false,2);eye.set_mix_duration(0.);eye.set_time_scale(0.)
		eye.set_track_time(clampf(glow*glow_strength,0.,1.));skeleton.update_skeleton(0.)
	for index in mouths.size():
		var item: Dictionary=mouths[index]
		var amount:=0.
		if mode=="attack_loop":amount=smoothstep(float(item.delay),float(item.delay)+.16,attack_age)
		elif mode=="attack_end":amount=1.-smoothstep(float(item.delay)*.5,.55,clock-phase_start)
		elif mode=="death":
			amount=smoothstep(1.20,1.32,death_age)*(1.-smoothstep(1.5,1.85,death_age))
			if index<flame_tail.size():amount=maxf(amount,flame_tail[index]*(1.-smoothstep(0.,.15,death_age)))
		item.node.position=_point(item);item.node.rotation=_direction(item).angle()
		item.node.scale=Vector2.ONE*effect_scale;item.node.visible=amount>0.
		item.node.material.set_shader_parameter("age",clock-loop_start if mode!="death" or death_age<.15 and not flame_tail.is_empty() else death_age)
		item.node.material.set_shader_parameter("amount",amount)
		item.node.material.set_shader_parameter("strength",glow_strength)
		item.node.material.set_shader_parameter("reach",float(item.length)*(1.2 if mode=="death" else 1.))
		item.node.material.set_shader_parameter("width",float(item.width)*(1.35 if mode=="death" else 1.))
		item.aura.position=item.node.position;item.aura.visible=amount>0.;item.aura.material.set_shader_parameter("amount",amount*glow_strength)
	for ring in rings:
		var age: float=clock-ring.time
		ring.node.visible=age>=0. and age<ring.duration
		ring.node.scale=Vector2.ONE*effect_scale
		ring.node.material.set_shader_parameter("age",age)
		var fade:=1.-smoothstep(0.,.15,death_age) if ring.time<death_time else 1.
		ring.node.material.set_shader_parameter("strength",glow_strength*fade)
	skeleton.visible=death_age<float(config["break"]) or fragments==null
	if fragments!=null:
		fragments.visible=death_age>=float(config["break"]) and death_age<float(config.death)
		fragments.material.set_shader_parameter("age",maxf(0.,death_age-float(config["break"])))
		fragments.material.set_shader_parameter("spread",180.*effect_scale)
		fragments.material.set_shader_parameter("strength",glow_strength)
	if death_age>=float(config.death):skeleton.hide()
	white_flash=0.
	if goat_fracture!=null:
		# 骨片分离后不再留下固定在旧骨骼位置的眼晕。
		if mode=="death" and death_age>=2.1:
			for item in eyes:item.node.hide()
		goat_fracture.sample(death_age,glow_strength,effect_scale)
		skeleton.visible=death_age<2.1
		white_flash=GOAT_FRACTURE.flash(death_age,glow_strength)
		# 独立透明度轨道防止混合起点短暂露出尚未揭开的真眼。
		var state=skeleton.get_animation_state()
		var seal=state.get_track(4) if state.get_num_tracks()>4 else null
		if seal==null:
			seal=state.set_animation("seal_reveal",false,4);seal.set_mix_duration(0.);seal.set_time_scale(0.)
		seal.set_track_time(clock-phase_start if mode=="phase_break" else 3.)
		var side=state.get_track(5) if state.get_num_tracks()>5 else null
		if side==null:
			side=state.set_animation("side_eye_light",false,5);side.set_mix_duration(0.);side.set_time_scale(0.)
		side.set_track_time(clampf(side_eye_glow,0.,1.))
		skeleton.update_skeleton(0.)

## 单条素材采样供生成器烘焙，无事件混合，不用于交互播放。
func sample_clip(clip: String, time: float) -> void:
	skeleton.get_animation_state().clear_tracks();skeleton.get_skeleton().set_to_setup_pose()
	if form.begins_with("goat"):_set_form("goat_eye" if clip in ["death","phase_break"] else initial_form)
	skeleton.get_animation_state().set_animation(clip,clip=="attack_loop",0).set_track_time(time)
	body_material.set_shader_parameter("light",0.)
	if clip=="death":
		var light:=smoothstep(.6,float(config.burst),time)*(1.-smoothstep(float(config.burst)+.12,float(config["break"])+.25,time))
		if not str(config.id).begins_with("goat"):body_material.set_shader_parameter("light",light)
		if not eyes.is_empty():skeleton.get_animation_state().set_animation("eye_light",false,2).set_track_time(0. if form.begins_with("goat") else light)
	skeleton.update_skeleton(0.)
	effects.hide();skeleton.show();dirty=true
