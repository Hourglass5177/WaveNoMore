extends Control
## 导入预览使用实际纹理比例；格线只用于检查精灵表，不写入资源。
var texture: Texture2D
var regions: Array[Rect2] = []
var original_size := false
func _ready() -> void:clip_contents=true;custom_minimum_size=Vector2(280,220)
func _draw() -> void:
	for y in range(0,int(size.y),20):
		for x in range(0,int(size.x),20):draw_rect(Rect2(x,y,20,20),Color("35404c") if (x/20+y/20)%2 else Color("252c36"))
	if texture==null:return
	var extent:=texture.get_size()
	var ratio:=1.0 if original_size else minf(size.x/extent.x,size.y/extent.y)
	var origin:=(size-extent*ratio)*0.5
	draw_texture_rect(texture,Rect2(origin,extent*ratio),false)
	for region in regions:draw_rect(Rect2(origin+region.position*ratio,region.size*ratio),Color("8cf0df"),false,1.5)
