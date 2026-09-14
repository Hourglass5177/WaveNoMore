extends MeshInstance2D

## 正式贴图使用预制距离场；颜色和宽度来自唯一的全局设计资源。
const SHADER = preload("res://shaders/notes/note_aura.gdshader")
static var _masks: Dictionary[String, Texture2D] = {}
var _surface := ShaderMaterial.new()
var _quad := QuadMesh.new()
var _source: Texture2D
var _rect := Rect2()
var _width: float = 36.0
var _available := false
var _rim_color := Color.WHITE
var _applied_rim := Color.TRANSPARENT

func _init() -> void:
	_surface.shader = SHADER
	material = _surface
	mesh = _quad
	show_behind_parent = true

func configure(style: NoteEffectStyle, side: int) -> void:
	_rim_color = style.rim(side)
	_applied_rim = _rim_color
	_width = style.halo_width_px
	_surface.set_shader_parameter(&"halo_color", style.halo(side))
	_surface.set_shader_parameter(&"rim_color", style.rim(side))
	_surface.set_shader_parameter(&"strength", style.halo_strength)
	_surface.set_shader_parameter(&"radius_px", style.halo_width_px)
	_surface.set_shader_parameter(&"rim_px", style.rim_width_px)
	_rect = Rect2()

func set_condition_light(amount: float, white: Color) -> void:
	## 只让贴图近轮廓转白，外晕仍保持阵营色；不改变遮罩或网格。
	var color := _rim_color.lerp(white, amount)
	if color == _applied_rim: return
	_applied_rim = color
	_surface.set_shader_parameter(&"rim_color", color)

func shape(source: Texture2D, rect: Rect2) -> void:
	if source == _source and rect == _rect:
		visible = _available
		return
	_source = source
	_rect = rect
	var path := source.resource_path.get_basename() + "_glow.png"
	if not _masks.has(path):
		_masks[path] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_available = _masks[path] != null
	visible = _available
	if not visible: return
	_surface.set_shader_parameter(&"glow_mask", _masks[path])
	var mask_rect := rect.grow(64.0)
	_surface.set_shader_parameter(&"mask_rect", Vector4(mask_rect.position.x, mask_rect.position.y, mask_rect.size.x, mask_rect.size.y))
	var bounds := rect.grow(_width + 2.0)
	_quad.size = bounds.size
	_quad.center_offset = Vector3(bounds.get_center().x, bounds.get_center().y, 0.0)
