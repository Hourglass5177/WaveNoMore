@tool
extends Control
## 选关与结算共用：原字图独立绘制，柔光只覆盖留边后的局部区域。
const MARKS = preload("res://src/app/ui/clear_mark.gd")
@export var fc_color := Color("dfcaa1")
@export var ap_color := Color("b985ff")
## 近轮廓与字内提亮分开，紫色外晕不会覆盖原图金粉。
@export var ap_edge_color := Color("ead8ff")
@export var ap_body_color := Color("f2e5cb")
@export var fc_radius_px := 8.0
@export var ap_radius_px := 11.0
@export var fc_strength := Vector2(0.26,0.34)
@export var ap_strength := Vector2(0.45,0.60)
@export var fc_lift := 0.08
@export var ap_lift := 0.12
@export var period_sec := 4.8
@export var texture: Texture2D:
	set(value):
		texture = value
		elapsed = 0.0
		if is_node_ready(): _refresh()
var elapsed := 0.0
var _halo: ColorRect
var _body: TextureRect
var _glow_material: ShaderMaterial
var _body_material: ShaderMaterial
var _strength := Vector2.ZERO
var _lift := 0.0
var _weight := 1.0
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow_material = ShaderMaterial.new()
	_glow_material.shader = preload("res://shaders/ui/clear_mark_glow.gdshader")
	_body_material = ShaderMaterial.new()
	_body_material.shader = preload("res://shaders/ui/clear_mark_body.gdshader")
	_halo = ColorRect.new()
	_halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_halo.material = _glow_material
	add_child(_halo)
	_body = TextureRect.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_body.material = _body_material
	add_child(_body)
	resized.connect(_refresh)
	visibility_changed.connect(_sync_processing)
	_refresh()
func set_result(result: Dictionary) -> void:
	texture = MARKS.texture_for(result)
func set_emphasis(weight: float) -> void:
	_weight = clampf(weight,0.0,1.0)
	modulate.a = _weight
	_sync_processing()
func _sync_processing() -> void:
	set_process(texture != null and is_visible_in_tree() and _weight > 0.0 and not Engine.is_editor_hint())
func _refresh() -> void:
	_body.texture = texture
	_body.visible = texture != null
	_halo.visible = texture != null
	_sync_processing()
	if texture == null: return
	var atlas := texture as AtlasTexture
	var ap := texture == MARKS.AP
	var tint := ap_color if ap else fc_color
	var radius := ap_radius_px if ap else fc_radius_px
	_strength = ap_strength if ap else fc_strength
	_lift = ap_lift if ap else fc_lift
	# 按有效字图比例居中；光晕留边不改变容器占位。
	var drawn := texture.get_size() * minf(size.x / texture.get_width(), size.y / texture.get_height())
	_body.position = (size-drawn)*0.5
	_body.size = drawn
	var padding := radius + 2.0
	_halo.position = _body.position-Vector2.ONE*padding
	_halo.size = drawn+Vector2.ONE*padding*2.0
	_glow_material.set_shader_parameter("source_texture",atlas.atlas)
	var source_size := atlas.atlas.get_size()
	_glow_material.set_shader_parameter("source_region",Vector4(atlas.region.position.x/source_size.x,atlas.region.position.y/source_size.y,atlas.region.size.x/source_size.x,atlas.region.size.y/source_size.y))
	_glow_material.set_shader_parameter("drawn_size",drawn.max(Vector2.ONE))
	_glow_material.set_shader_parameter("padding_px",padding)
	_glow_material.set_shader_parameter("radius_px",radius)
	_glow_material.set_shader_parameter("glow_color",tint)
	_glow_material.set_shader_parameter("edge_color",ap_edge_color if ap else fc_color)
	_glow_material.set_shader_parameter("halo_softness",0.5 if ap else 1.0)
	_body_material.set_shader_parameter("light_color",ap_body_color if ap else fc_color)
	_sample()
func _process(delta: float) -> void:
	elapsed = fposmod(elapsed+delta,maxf(period_sec,0.1))
	_sample()
func _sample() -> void:
	var breath := 0.5-0.5*cos(TAU*elapsed/maxf(period_sec,0.1))
	_glow_material.set_shader_parameter("strength",lerpf(_strength.x,_strength.y,breath))
	_body_material.set_shader_parameter("lift",_lift*lerpf(0.9,1.1,breath))
