extends Control
## 独立 UI 火框；尺寸/火势高度变化时重建环带，运行中按显式时间更新材质。
const SHADER=preload("res://shaders/ui/flame_frame.gdshader")
const EMBERS=preload("res://shaders/ui/flame_embers.gdshader")
const ROOT="res://assets/ui/flame_frame/"
@export_enum("红焰","蓝焰") var palette:int=0
@export var flame_height:float=48.:
	set(value):
		flame_height=value
		if is_node_ready():rebuild()
@export var speed:float=90.
@export var glow_strength:float=1.
@export var random_seed:int=0
var surface:MeshInstance2D
var embers:MeshInstance2D
var elapsed:=0.
var rebuilds:=0
var automatic:=true
var _palette_cache:=-1

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	process_mode=Node.PROCESS_MODE_ALWAYS
	surface=MeshInstance2D.new();add_child(surface)
	var mat:=ShaderMaterial.new();mat.shader=SHADER
	mat.set_shader_parameter("noise_map",load(ROOT+"noise.png"));mat.set_shader_parameter("fuel_map",load(ROOT+"fuel.png"))
	surface.material=mat
	embers=MeshInstance2D.new();add_child(embers)
	var ember_mat:=ShaderMaterial.new();ember_mat.shader=EMBERS;embers.material=ember_mat
	resized.connect(rebuild);rebuild();sample(0.)

func rebuild() -> void:
	if surface==null:return
	var pad:=flame_height*2.4
	var border:=flame_height*1.4
	var xs:=[-pad,border,size.x-border,size.x+pad]
	# 底火更旺，给向框内上窜的火尖留足柔和消退的空间。
	var bottom_band:=minf(flame_height*2.4,size.y*.4+2.)
	var ys:=[-pad,border,size.y-bottom_band,size.y+pad]
	var v:=PackedVector2Array();var indices:=PackedInt32Array()
	# 九宫格去掉中央空白，角区只绘制一次；外扩网格保留完整火尖与柔晕。
	for y in 3:
		for x in 3:
			if x==1&&y==1:continue
			var start:=v.size()
			v.append_array(PackedVector2Array([Vector2(xs[x],ys[y]),Vector2(xs[x+1],ys[y]),Vector2(xs[x+1],ys[y+1]),Vector2(xs[x],ys[y+1])]))
			indices.append_array(PackedInt32Array([start,start+1,start+2,start,start+2,start+3]))
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=v;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);surface.mesh=mesh;rebuilds+=1
	surface.material.set_shader_parameter("frame_size",size)
	var ev:=PackedVector2Array();var uv:=PackedVector2Array()
	for i in 8:
		var edge:=i/2;var along:=.26 if i%2==0 else .74
		var p:Vector2=[Vector2(size.x*along,0),Vector2(size.x,size.y*along),Vector2(size.x*along,size.y),Vector2(0,size.y*along)][edge]
		for corner:Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,-1),Vector2(1,1),Vector2(-1,1)]:
			ev.append(p+corner*Vector2(4,8));uv.append((corner+Vector2.ONE)*.5)
	var ea:=[];ea.resize(Mesh.ARRAY_MAX);ea[Mesh.ARRAY_VERTEX]=ev;ea[Mesh.ARRAY_TEX_UV]=uv
	var em:=ArrayMesh.new();em.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,ea);embers.mesh=em

func sample(seconds:float) -> void:
	elapsed=seconds
	if surface==null:return
	var mat:ShaderMaterial=surface.material
	mat.set_shader_parameter("age",seconds);mat.set_shader_parameter("flame_height",flame_height)
	mat.set_shader_parameter("speed",speed);mat.set_shader_parameter("glow_strength",glow_strength)
	mat.set_shader_parameter("random_seed",float(random_seed))
	for name in ["age","flame_height","speed","glow_strength","random_seed"]:embers.material.set_shader_parameter(name,mat.get_shader_parameter(name))
	if palette!=_palette_cache:
		_palette_cache=palette
		mat.set_shader_parameter("color_ramp",load(ROOT+("red" if palette==0 else "blue")+"_ramp.png"))
		embers.material.set_shader_parameter("color_ramp",mat.get_shader_parameter("color_ramp"))

func apply_planning(report:Dictionary) -> void:
	for key:String in ["flame_height","speed","glow_strength"]:
		var id:="ui_flame/"+key
		if report.get("values",{}).has(id):set(key,report.values[id])

func _process(delta:float) -> void:
	if automatic && is_visible_in_tree() && modulate.a>0.:sample(elapsed+delta)
