@tool
class_name BoundaryVortexArm
extends MeshInstance2D
## 厚浪两边独立编排；纹样沿弧长前进，轮廓不随时间整股伸缩。
const VORTEX_MATERIAL := preload("res://shaders/materials/boundary_vortex.gdshader")
const WATER := preload("res://assets/image/background/boundary_waves/water_band.png")
const CREST := preload("res://assets/image/background/boundary_vortex/crest_flow.png")
const STEPS := 144
const ROWS := 12
static var water_bounds: ImageTexture
var material_instance: ShaderMaterial
var distance_px := 0.0
var path_length := 0.0
var _shape := Vector2.ZERO

func _ready() -> void:
	material_instance=ShaderMaterial.new()
	material_instance.shader=VORTEX_MATERIAL
	material_instance.set_shader_parameter("root_water",WATER)
	material_instance.set_shader_parameter("crest_texture",CREST)
	material_instance.set_shader_parameter("water_bounds",_get_water_bounds())
	material=material_instance

static func _get_water_bounds() -> ImageTexture:
	if water_bounds != null: return water_bounds
	# 只读取一次原水带各列的上下缘，形成保持原笔触顺序的采样表。
	var source:=WATER.get_image()
	var lookup:=Image.create(512,1,false,Image.FORMAT_RGF)
	for column in 512:
		var x:=roundi(lerpf(96.0,2500.0,column/511.0))
		var top:=620
		var bottom:=800
		for y in range(620,810):
			if source.get_pixel(x,y).a>.8:
				top=y
				break
		for y in range(809,619,-1):
			if source.get_pixel(x,y).a>.8:
				bottom=y
				break
		lookup.set_pixel(column,0,Color((top+2.0)/1440.0,(bottom-2.0)/1440.0,0,1))
	water_bounds=ImageTexture.create_from_image(lookup)
	return water_bounds

## 返回内外缘。入口下缘只平顺上升，增厚发生在上方。
static func edges(u: float, inner_radius: float, width: float) -> PackedVector2Array:
	var inside: Vector2
	var outside: Vector2
	if u < .32:
		var t:=u/.32
		inside=Vector2(-330,24).bezier_interpolate(Vector2(-240,24),Vector2(-146,24),Vector2(-116,-40),t)
		outside=Vector2(-330,-26).bezier_interpolate(Vector2(-220,-26),Vector2(-185,-120),Vector2(-132,-170),t)
	elif u < .54:
		var t:=(u-.32)/.22
		inside=Vector2(-116,-40).bezier_interpolate(Vector2(-97,-70),Vector2(-62,-88),Vector2(-20,-88),t)
		outside=Vector2(-132,-170).bezier_interpolate(Vector2(-100,-200),Vector2(-60,-212),Vector2(-26,-208),t)
	else:
		var t:=(u-.54)/.46
		inside=Vector2(-20,-88).bezier_interpolate(Vector2(40,-88),Vector2(105,-25),Vector2(86,23),t)
		outside=Vector2(-26,-208).bezier_interpolate(Vector2(105,-192),Vector2(182,-85),Vector2(86,23),t)
	# 内径只移动中央弧面；宽度向外增加，不能把浪根下缘挤出鼓包。
	var shift:=inside.normalized()*(inner_radius-88.0)*smoothstep(0.0,.45,u)
	outside=inside+(outside-inside)*lerpf(1.0,width/112.0,smoothstep(0.0,.28,u))
	return PackedVector2Array([inside+shift,outside+shift])

func _build_mesh(inner_radius: float, width: float) -> void:
	var vertices:=PackedVector3Array()
	var uv:=PackedVector2Array()
	var colors:=PackedColorArray()
	var indices:=PackedInt32Array()
	var previous:=Vector2(-330,-1)
	path_length=0.0
	for i in STEPS+1:
		var u:=i/float(STEPS)
		var pair:=edges(u,inner_radius,width)
		var center:=(pair[0]+pair[1])*.5
		path_length+=center.distance_to(previous)
		previous=center
		for row in ROWS+1:
			# 上部预留翻出的浪唇，实际外缘由带透明缺口的原画附件定义。
			var v:=row/float(ROWS)*1.4
			var point:=pair[0].lerp(pair[1],v)
			vertices.append(Vector3(point.x,point.y,0))
			uv.append(Vector2(path_length,v))
			colors.append(Color(u,pair[0].distance_to(pair[1])/256.0,1,1))
		if i==STEPS: continue
		for row in ROWS:
			var a:=i*(ROWS+1)+row
			indices.append_array(PackedInt32Array([a,a+1,a+ROWS+1,a+1,a+ROWS+2,a+ROWS+1]))
	var arrays:=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_TEX_UV]=uv
	arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_INDEX]=indices
	var surface:=ArrayMesh.new()
	surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh=surface

func sample(travel: float, configuration: BoundaryMotionStyle) -> void:
	distance_px=travel
	var shape:=Vector2(configuration.vortex_inner_radius_px,configuration.vortex_width_px)
	if shape!=_shape:
		_shape=shape
		_build_mesh(shape.x,shape.y)
	# 有界相位避免长曲及远距离定位丢失亚像素精度。
	material_instance.set_shader_parameter("ink_phase",fposmod(travel,640.0)/640.0)
	material_instance.set_shader_parameter("foam_phase",fposmod(travel*1.12,235.0)/235.0)
	material_instance.set_shader_parameter("crest_phase",fposmod(travel*1.06,900.0)/900.0)
	material_instance.set_shader_parameter("foam_strength",configuration.vortex_foam_strength)
