extends SceneTree
## 小体积的动画制作示例；帧图只用于说明编排与遮挡，不代表正式美术。
const ROOT := "res://examples/level-studio/动画与遮挡"
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var level:=LevelFormat.new_level();level.level_id="animation_workflow_example";level.title="动画与遮挡 · 制作流程";level.scene_id="s08";level.intro_us=2000000;level.outro_us=2000000
	level.description="三种来源的可携带动画、局部时间、曲前曲后、父组遮挡和空引用恢复。"
	var frames:=SpriteFrames.new();frames.set_animation_speed("default",12)
	var sheet:=Image.create(384,96,false,Image.FORMAT_RGBA8);sheet.fill(Color.TRANSPARENT)
	for index in 4:
		var image:=Image.create(96,96,false,Image.FORMAT_RGBA8);image.fill(Color.TRANSPARENT)
		for y in 96:
			for x in 96:
				var distance:=Vector2(x-48,y-48).length()
				if distance<20+index*6 and distance>12+index*6:image.set_pixel(x,y,Color("d6bf82"))
		frames.add_frame("default",ImageTexture.create_from_image(image));sheet.blit_rect(image,Rect2i(0,0,96,96),Vector2i(index*96,0))
	var sequence: Dictionary=await LevelAnimationAsset.write(frames,ROOT,"连续图片 · 扩散环")
	var atlas_frames:=SpriteFrames.new();atlas_frames.set_animation_speed("default",12);var texture:=ImageTexture.create_from_image(sheet)
	for index in 4:
		var atlas:=AtlasTexture.new();atlas.atlas=texture;atlas.region=Rect2(index*96,0,96,96);atlas_frames.add_frame("default",atlas)
	var atlas_asset: Dictionary=await LevelAnimationAsset.write(atlas_frames,ROOT,"精灵表 · 扩散环")
	frames.rename_animation("default","pulse");frames.set_frame("pulse",3,frames.get_frame_texture("pulse",3),2.0)
	var native: Dictionary=await LevelAnimationAsset.write(frames,ROOT,"SpriteFrames · 不等帧时长")
	var assets: Array=[sequence.path,atlas_asset.path,native.path]
	var group:=LevelFormat.object("group");group.id="effects_group";group.name="扩散环组（背景前）";group.fields.position=[0,0];group.occlusion_inherit=false;group.occlusion_depth=1;group.occlusion_order="front";level.show.objects.append(group)
	for index in 3:
		var object_data:=LevelFormat.object("animated_sprite",assets[index]);object_data.id="animation_%d"%index;object_data.name=["连续帧","精灵表","SpriteFrames"][index];object_data.parent_id=group.id;object_data.fields.position=[550+index*400,600];object_data.fields.scale=[2.4,2.4];object_data.animation="pulse" if index==2 else "default";level.show.objects.append(object_data)
		var action:=LevelFormat.track(object_data.id,"action","song","action");var clip:=LevelFormat.clip(index*500000,"",18000000);clip.action=object_data.animation;clip.loop=true;clip.offset_us=index*100000;clip.rate=[1.0,0.75,1.5][index];clip.name=object_data.name+" · 可裁剪／拆分";action.clips=[clip];level.show.tracks.append(action)
		var position:=LevelFormat.track(object_data.id,"position");position.keys=[LevelFormat.key(2000000,object_data.fields.position),LevelFormat.key(7000000,[550+index*400,420]),LevelFormat.key(14000000,object_data.fields.position)];position.keys[0].interpolation="bezier";level.show.tracks.append(position)
	var title:=LevelFormat.object("text");title.id="instructions";title.name="操作提示";title.fields.position=[960,210];title.fields.size=[1400,200];title.fields.text="三种动画来源 · 从当前游标开始编排\n关闭自动关键帧拖动：整体调整当前区段动画";title.fields.font_size=36;level.show.objects.append(title)
	var empty:=LevelFormat.object("animated_sprite");empty.id="empty_rebind";empty.name="空引用对象 · 选中后重新绑定";empty.fields.position=[960,850];level.show.objects.append(empty)
	var error:=LevelProjectIO.import_song("res://examples/level-studio/渡口演出/song/song.json",ROOT)
	if error.is_empty():error=LevelProjectIO.save(level,ROOT)
	print("ANIMATION EXAMPLE: ","OK" if error.is_empty() else error);quit(0 if error.is_empty() else 1)
