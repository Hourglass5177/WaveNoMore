extends Node2D
## 裂纹、骨片、光束采用同一份切分数据；所有运动由死亡年龄直接求值。
const SHADER=preload("res://shaders/bosses/goat_fracture.gdshader")
const RAY=preload("res://shaders/bosses/goat_ray.gdshader")
var pieces: MeshInstance2D
var rays: Array[Dictionary]=[]
var root_light: MeshInstance2D
var motes: MeshInstance2D

func setup(host: Node2D) -> void:
	var folder: String=host.ROOT+"goat_eye/"
	if not FileAccess.file_exists(folder+"fracture.json"):return
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"fracture.json"))
	var vertices:=PackedVector2Array();var uvs:=PackedVector2Array();var colors:=PackedColorArray();var indices:=PackedInt32Array()
	for piece: Dictionary in data.pieces:
		var start:=vertices.size();var center:=Vector2(piece.center[0],piece.center[1])
		for point in piece.points:
			var p:=Vector2(point[0],point[1]);vertices.append(p-Vector2.ONE*512.);uvs.append(p/1024.)
			colors.append(Color(center.x/1024.,center.y/1024.,piece.seed,1.))
		for i in range(1,piece.points.size()-1):indices.append_array(PackedInt32Array([start,start+i,start+i+1]))
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.custom_aabb=AABB(Vector3(-1800,-1800,-1),Vector3(3600,3600,2))
	pieces=MeshInstance2D.new();pieces.mesh=mesh;pieces.texture=host._source_texture(folder+"death_pose.png")
	var material:=ShaderMaterial.new();material.shader=SHADER;material.set_shader_parameter("cracks_texture",host._source_texture(folder+"cracks.png"));pieces.material=material
	add_child(pieces)
	material.set_shader_parameter("eyes_texture",host._source_texture(folder+"death_eye_map.png"))
	for i in data.rays.size():
		var item: Dictionary=data.rays[i].duplicate(true)
		var node:=MeshInstance2D.new();var quad:=QuadMesh.new();quad.size=Vector2(1100,500);quad.center_offset=Vector3(550,0,0);node.mesh=quad
		var mat:=ShaderMaterial.new();mat.shader=RAY;mat.set_shader_parameter("phase",i*1.83);node.material=mat
		# 光束位于骨片后方，裂口边缘负责遮住发射根部。
		add_child(node);move_child(node,0);item.node=node;rays.append(item)
	root_light=host._quad(Vector2(1200,1200),host.AURA);root_light.reparent(self);move_child(root_light,0)
	motes=host._quad(Vector2(1024,1024),host.FRAGMENTS);motes.reparent(self)
	# 白场退去后只留下细小余烬，不再重新露出整块头骨。
	var template:=NoteFragmentHost._template(Vector2(1024,1024),8,maxi(1,int(90*host.fragment_multiplier))).surface_get_arrays(0)
	var mote_vertices:=PackedVector2Array();var mote_uvs:=PackedVector2Array();var mote_colors:=PackedColorArray()
	for i in template[Mesh.ARRAY_COLOR].size():
		if template[Mesh.ARRAY_COLOR][i].a<.75:continue
		var point=template[Mesh.ARRAY_VERTEX][i]
		mote_vertices.append(Vector2(point.x,point.y));mote_uvs.append(template[Mesh.ARRAY_TEX_UV][i]);mote_colors.append(template[Mesh.ARRAY_COLOR][i])
	var mote_arrays:=[];mote_arrays.resize(Mesh.ARRAY_MAX);mote_arrays[Mesh.ARRAY_VERTEX]=mote_vertices;mote_arrays[Mesh.ARRAY_TEX_UV]=mote_uvs;mote_arrays[Mesh.ARRAY_COLOR]=mote_colors
	var mote_mesh:=ArrayMesh.new();mote_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,mote_arrays);motes.mesh=mote_mesh
	motes.texture=pieces.texture;motes.material.set_shader_parameter("duration",1.85);motes.material.set_shader_parameter("kind_id",2)
	hide()

func motion(center: Vector2, seed: float, age: float, spread: float) -> Transform2D:
	var direction: Vector2=(center-Vector2(0,-72)).normalized()
	var split:=smoothstep(3.8,4.8,age);var burst:=smoothstep(4.8,5.4,age)
	var angle:=sin(seed*37.)*(split*.30+burst*.65)
	var result:=Transform2D(angle,center+direction*(12.*smoothstep(2.1,3.8,age)+58.*split+300.*burst)*spread)
	result.origin-=result.basis_xform(center)
	return result

func sample(age: float, strength: float, spread: float) -> void:
	visible=age>=.7 and age<7.
	if pieces==null:return
	pieces.material.set_shader_parameter("age",age);pieces.material.set_shader_parameter("strength",strength);pieces.material.set_shader_parameter("spread",spread)
	for i in rays.size():
		var item: Dictionary=rays[i];var node: MeshInstance2D=item.node
		var center:=Vector2(item.center[0],item.center[1])-Vector2.ONE*512.
		var point:=Vector2(item.point[0],item.point[1])-Vector2.ONE*512.
		var transform:=motion(center,item.seed,age,spread)
		node.position=transform*point;node.rotation=(point-Vector2(0,-107)).angle()+transform.get_rotation()
		var amount:=smoothstep(2.1+i*.13,2.5+i*.13,age)*(1.-smoothstep(5.1,5.5,age))*strength
		node.visible=amount>0.
		node.material.set_shader_parameter("age",age);node.material.set_shader_parameter("amount",amount)
		node.material.set_shader_parameter("reach",lerpf(160.,650.,smoothstep(2.1,4.8,age))*spread+300.*smoothstep(4.8,5.15,age))
		node.material.set_shader_parameter("width",lerpf(18.,75.,smoothstep(2.1,5.,age))*spread)
	root_light.position=Vector2(0,-100);root_light.scale=Vector2.ONE*lerpf(.08,1.6,smoothstep(3.8,5.15,age))*spread
	root_light.visible=age>3.8 and age<6.
	root_light.material.set_shader_parameter("amount",smoothstep(3.8,5.15,age)*(1.-smoothstep(5.65,6.,age))*strength)
	motes.visible=age>=5.15 and age<7.
	motes.material.set_shader_parameter("age",maxf(0.,age-5.15));motes.material.set_shader_parameter("spread",350.*spread);motes.material.set_shader_parameter("strength",strength*.6)

static func flash(age: float, strength: float) -> float:
	return clampf(smoothstep(4.80,5.15,age)*(1.-smoothstep(5.65,6.65,age))*strength,0.,1.)
