extends SceneTree
## 用实际 shader 像素检查近圆帽面、各方向贴边与暂停；产出姿态表供美术复核。
const OUT := "res://builds/guidance-review"
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var viewport := SubViewport.new(); viewport.size = Vector2i(180,180)
	viewport.transparent_bg = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var cap := MeshInstance2D.new(); cap.position = Vector2(90,90); viewport.add_child(cap)
	var quad := QuadMesh.new(); quad.size = Vector2(120,120); cap.mesh = quad
	var material := ShaderMaterial.new(); material.shader = preload("res://shaders/fields/tuning_stick_cap.gdshader"); cap.material = material
	var style: TimingCueStyle = load("res://content/presentation/timing_cue_style.tres")
	material.set_shader_parameter("bone_color", style.note_style.white_color)
	var grid := SubViewport.new(); grid.size = Vector2i(900,360); grid.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(grid)
	var background := ColorRect.new(); background.size = grid.size; background.color = Color("252431"); grid.add_child(background)
	var directions := [Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN, Vector2(-1,1).normalized(), Vector2(1,-1).normalized()]
	for side in 2:
		material.set_shader_parameter("body_color", style.note_style.base(side)); material.set_shader_parameter("light_color", style.note_style.rim(side))
		for index in directions.size():
			var direction: Vector2 = directions[index]; material.set_shader_parameter("recommendation", direction)
			await process_frame; RenderingServer.force_draw(false)
			var frame := viewport.get_texture().get_image()
			var total := Vector2.ZERO; var count := 0; var extent := Rect2i(); var outer := -100.0
			for y in 180:
				for x in 180:
					if frame.get_pixel(x,y).a < 0.78: continue
					var pixel := Vector2i(x,y)
					extent = Rect2i(pixel,Vector2i.ONE) if count==0 else extent.expand(pixel)
					total += Vector2(pixel); count += 1
					outer = maxf(outer, (Vector2(pixel)+Vector2.ONE*0.5-cap.position).dot(direction))
			check(count > 1500, "近圆帽面像素面积 %d/%d" % [side,index])
			if direction == Vector2.ZERO:
				# 高 alpha 阈值排除了抗锯齿边缘，实体直径比约 50 px 外沿略小。
				check(abs(extent.size.x-extent.size.y)<=1 and extent.size.x>=47 and extent.size.x<=52, "回中为直径约50的正圆：%s" % extent.size)
			else:
				check(absf(outer-52.0)<1.6, "满推外沿抵住半径52的源泉外框")
				var offset := total / count + Vector2.ONE*0.5-cap.position
				check(offset.normalized().dot(direction)>0.998 and offset.length()>27.0, "平移方向与物理摇杆一致，无竖直压缩或固定偏置")
			var sprite := Sprite2D.new(); sprite.texture = ImageTexture.create_from_image(frame)
			sprite.position = Vector2(90+index*180,90+side*180); grid.add_child(sprite)
			var label := Label.new(); label.text = ["回中","右推","下推","左下推","右上推"][index]
			label.add_theme_font_override("font",MingheUiStyle.ui_font()); label.position = Vector2(index*180+64,side*180+152); grid.add_child(label)
			await process_frame; RenderingServer.force_draw(false)
			check(frame.get_data()==viewport.get_texture().get_image().get_data(), "暂停姿态像素不随时间变化")
	await process_frame; RenderingServer.force_draw(false)
	grid.get_texture().get_image().save_png(OUT+"/stick-poses.png")
	viewport.free(); grid.free()
	print("STICK CAP: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)
