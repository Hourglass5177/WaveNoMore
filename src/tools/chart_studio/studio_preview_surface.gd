extends TextureRect
## 游戏坐标仍为 1920×1080；渲染纹理独立于 UI 的逻辑尺寸，避免先低分辨率渲染再放大。
@onready var viewport: SubViewport = $Viewport

func _ready() -> void:
	texture = viewport.get_texture()
	resized.connect(update_resolution)
	get_window().size_changed.connect(update_resolution)
	update_resolution.call_deferred()

func update_resolution() -> void:
	var physical_width := minf(size.x, size.y * 16.0 / 9.0) * get_window().content_scale_factor
	var width := clampi(ceili(physical_width / 16.0) * 16, 320, 2560)
	var resolution := Vector2i(width, width * 9 / 16)
	viewport.size_2d_override = Vector2i(1920,1080)
	viewport.size_2d_override_stretch = true
	if viewport.size != resolution: viewport.size = resolution
