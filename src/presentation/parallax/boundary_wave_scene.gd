@tool
class_name BoundaryWaveScene
extends Node2D
## 两股常驻厚浪中心对称放置，水纹共用绝对路程，小浪沿原节拍编排。
const ART := "res://assets/image/background/boundary_waves/"
const DESIGN_SCALE := 0.7616555803103707
const CENTER := Vector2(1325,720)
const CLIP := preload("res://shaders/materials/boundary_wave_clip.gdshader")
const WATER_FLOW := preload("res://shaders/materials/boundary_water_flow.gdshader")
var driver: BoundaryMotion
var schedule: BoundaryWaveSchedule
var originals: Sprite2D
var animated: Node2D
var big: Array[Dictionary] = []
var little: Array[AnimatedSprite2D] = []
var last_state: Dictionary = {}
var band: Sprite2D
var flow_material: ShaderMaterial

func _ready() -> void:
	originals = Sprite2D.new(); originals.centered=false
	originals.texture=load("res://assets/image/background/edge.png"); add_child(originals)
	animated=Node2D.new(); add_child(animated)
	band=Sprite2D.new(); band.centered=false; band.texture=load("res://assets/image/background/boundary_vortex/water_band_split.png"); animated.add_child(band)
	flow_material=ShaderMaterial.new(); flow_material.shader=WATER_FLOW
	flow_material.set_shader_parameter("flow_control",load(ART+"flow_control.png"))
	flow_material.set_shader_parameter("flow_streaks",load(ART+"flow_streaks.png"))
	band.material=flow_material
	for side in 2:
		var world := Node2D.new(); world.position=CENTER; world.rotation=side*PI
		world.scale=Vector2.ONE/DESIGN_SCALE; animated.add_child(world)
		var arm := BoundaryVortexArm.new()
		world.add_child(arm)
		arm.material_instance.set_shader_parameter("world_sign",1.0 if side==0 else -1.0)
		big.append({"sprite":arm,"material":arm.material_instance})
		for index in 3:
			var sprite := AnimatedSprite2D.new(); sprite.sprite_frames=load(ART+"small_frames.tres")
			sprite.animation=&"wave"; sprite.centered=false; sprite.offset=-Vector2(280,232)
			var material := ShaderMaterial.new(); material.shader=CLIP
			sprite.material=material; world.add_child(sprite); sprite.stop(); little.append(sprite)
	if driver == null: configure_boundary_scene(BoundaryMotion.new())
	sample_background(0.0)

func configure_boundary_scene(motion: BoundaryMotion) -> void:
	driver=motion; schedule=BoundaryWaveSchedule.new(driver)

func background_bounds() -> Rect2:
	return Rect2(0,0,2650,1440)

func sample_background(seconds: float) -> void:
	if originals == null: return
	originals.visible=not driver.style.enabled; animated.visible=driver.style.enabled
	if not animated.visible: return
	# 有界相位避免长歌曲损失浮点精度，也使完整周期逐像素可复现。
	flow_material.set_shader_parameter("flow_seconds",fposmod(seconds,2.0))
	for field in [&"flow_enabled",&"flow_speed_px_sec",&"flow_strength",&"streak_strength"]:
		flow_material.set_shader_parameter(field,driver.style.get(field))
	last_state=schedule.sample(seconds)
	var travel:=driver.vortex_distance_at(seconds)
	for side in 2:
		big[side].sprite.sample(travel,driver.style)
		for index in 3:
			var sprite := little[side*3+index]
			sprite.visible=index < last_state.small.size()
			if not sprite.visible: continue
			var state: Dictionary=last_state.small[index]
			var phase: float=state.phase
			sprite.position=Vector2(-750+state.region*230+140*phase,-8)
			# 浪根仍嵌在原画厚水带内，浪顶略上提；死界由父节点中心对称。
			sprite.scale=Vector2(.43,.30)
			sprite.modulate.a=smoothstep(0.0,.12,phase)*(1.0-smoothstep(.75,1.0,phase))
			_sample_material(sprite.material,phase)

func _sample_material(material: ShaderMaterial, phase: float) -> void:
	material.set_shader_parameter("wave_frame",phase*127.0)
