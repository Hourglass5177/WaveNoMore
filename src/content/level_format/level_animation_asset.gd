class_name LevelAnimationAsset
extends RefCounted
## 普通关卡动画使用相对图片描述；同一张精灵表只解码与携带一次。
const SUFFIX := ".animation.json"
const IMAGE_EXTENSIONS := ["png","jpg","jpeg","webp","svg"]

static func read_texture(path: String) -> Texture2D:
	var picture:=Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(picture) if picture!=null else null

static func load_frames(path: String) -> SpriteFrames:
	var data:=LevelProjectIO.read_json(path)
	if data.get("format","")!="minghe-animation":return null
	var result:=SpriteFrames.new();result.remove_animation("default")
	var textures:={}
	for animation: Dictionary in data.get("animations",[]):
		var name:=str(animation.name);result.add_animation(name)
		result.set_animation_speed(name,float(animation.fps));result.set_animation_loop(name,bool(animation.loop))
		for frame: Dictionary in animation.frames:
			var image_path:=path.get_base_dir().path_join(str(frame.image))
			if not textures.has(image_path):textures[image_path]=read_texture(image_path)
			var texture: Texture2D=textures[image_path]
			if texture==null:return null
			if frame.has("region"):
				var atlas:=AtlasTexture.new();atlas.atlas=texture;atlas.region=rect(frame.region);atlas.margin=rect(frame.get("margin",[0,0,0,0]));texture=atlas
			result.add_frame(name,texture,float(frame.get("duration",1.0)))
	return result

static func rect(value: Array) -> Rect2:
	return Rect2(float(value[0]),float(value[1]),float(value[2]),float(value[3]))

static func dependencies(path: String) -> PackedStringArray:
	var result:=PackedStringArray()
	for animation: Dictionary in LevelProjectIO.read_json(path).get("animations",[]):
		for frame: Dictionary in animation.frames:
			var dependency:=path.get_base_dir().path_join(str(frame.image)).simplify_path()
			if dependency not in result:result.append(dependency)
	return result

static func duration(frames: SpriteFrames, action: String) -> float:
	if frames==null or not frames.has_animation(action):return 0.0
	var total:=0.0
	for index in frames.get_frame_count(action):total+=frames.get_frame_duration(action,index)
	return total/maxf(0.001,frames.get_animation_speed(action))

## 在来源工程的坐标中解析依赖；临时资源缓存只在同步读取期间使用，随后还原。
## 这样二进制 .res 和文本 .tres 都不会误借当前 Game 中同名的图片。
static func source_dependencies(path: String, replacements: Dictionary={}) -> Array:
	var absolute:=ProjectSettings.globalize_path(path).simplify_path()
	var source_root:=absolute.get_base_dir()
	while not FileAccess.file_exists(source_root.path_join("project.godot")) and source_root.get_base_dir()!=source_root:source_root=source_root.get_base_dir()
	if not FileAccess.file_exists(source_root.path_join("project.godot")):source_root=absolute.get_base_dir()
	var dependencies:=[];var seen:={}
	_gather_sources(absolute,source_root,replacements,seen,dependencies)
	return dependencies

static func import_resource(path: String, replacements: Dictionary={}, preloaded: Dictionary={}) -> Dictionary:
	var absolute:=ProjectSettings.globalize_path(path).simplify_path()
	var dependencies:=source_dependencies(path,replacements)
	var missing:=dependencies.filter(func(item):return not FileAccess.file_exists(item.path))
	if not missing.is_empty():return {"error":"请补齐来源资源的图片依赖。","missing":missing}
	var borrowed:=[]
	for dependency: Dictionary in dependencies:
		var previous: Resource=load(dependency.ref) if ResourceLoader.has_cached(dependency.ref) else null
		var resource: Resource=preloaded.get(dependency.path)
		if resource==null:resource=read_texture(dependency.path) if dependency.path.get_extension().to_lower() in IMAGE_EXTENSIONS else ResourceLoader.load(dependency.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if resource==null:
			_restore_borrowed(borrowed)
			return {"error":"无法读取来源依赖："+str(dependency.path),"missing":[dependency]}
		borrowed.append({"ref":dependency.ref,"previous":previous,"resource":resource})
		resource.take_over_path(dependency.ref)
	var frames:=ResourceLoader.load(absolute,"",ResourceLoader.CACHE_MODE_IGNORE) as SpriteFrames
	_restore_borrowed(borrowed)
	return {"error":"资源不是有效的 SpriteFrames。" if frames==null else "","frames":frames,"missing":[]}

static func _restore_borrowed(borrowed: Array) -> void:
	for index in range(borrowed.size()-1,-1,-1):
		var item: Dictionary=borrowed[index]
		item.resource.resource_path=""
		if item.previous!=null:item.previous.take_over_path(item.ref)

static func _gather_sources(path: String, source_root: String, replacements: Dictionary, seen: Dictionary, result: Array) -> void:
	for dependency in ResourceLoader.get_dependencies(path):
		var parts:=dependency.split("::");var ref:=str(parts[-1])
		if ref in seen:continue
		seen[ref]=true
		var actual:=str(replacements.get(ref,source_root.path_join(ref.trim_prefix("res://")) if ref.begins_with("res://") else path.get_base_dir().path_join(ref)))
		if FileAccess.file_exists(actual) and actual.get_extension().to_lower() in ["tres","res"]:_gather_sources(actual,source_root,replacements,seen,result)
		result.append({"ref":ref,"path":actual})

## 写入新的资源目录，不覆盖旧版本，文档撤销后仍能恢复原资源。
static func write(frames: SpriteFrames, directory: String, label: String, progress: Callable=Callable(), canceled: Callable=Callable(), default_action: String="") -> Dictionary:
	var relative:="assets/animations/"+LevelFormat.id("animation")
	var folder:=directory.path_join(relative)
	DirAccess.make_dir_recursive_absolute(folder)
	var data:={"format":"minghe-animation","name":label,"default_animation":default_action,"animations":[]}
	var exported:={};var written:=PackedStringArray()
	var total:=0
	for name in frames.get_animation_names():total+=frames.get_frame_count(name)
	var count:=0
	var error:=""
	for name in frames.get_animation_names():
		var animation:={"name":str(name),"fps":frames.get_animation_speed(name),"loop":frames.get_animation_loop(name),"frames":[]}
		for index in frames.get_frame_count(name):
			if canceled.is_valid() and canceled.call():error="已取消导入";break
			var texture:=frames.get_frame_texture(name,index)
			var frame:={"duration":frames.get_frame_duration(name,index)}
			if texture is AtlasTexture and not texture.atlas is AtlasTexture:
				frame.region=[texture.region.position.x,texture.region.position.y,texture.region.size.x,texture.region.size.y]
				frame.margin=[texture.margin.position.x,texture.margin.position.y,texture.margin.size.x,texture.margin.size.y]
				texture=texture.atlas
			if texture==null:error="动画包含空帧，请移除或补齐。";break
			var key:=texture.get_instance_id()
			if not exported.has(key):
				var file:="image_%04d.png"%exported.size()
				var image:=texture.get_image()
				if image==null:error="无法读取动画图片";break
				if image.is_compressed():image.decompress()
				if image.save_png(folder.path_join(file))!=OK:error="无法写入动画图片";break
				exported[key]=file;written.append(folder.path_join(file))
			frame.image=exported[key];animation.frames.append(frame);count+=1
			if progress.is_valid():progress.call(count,total)
			await Engine.get_main_loop().process_frame
		data.animations.append(animation)
		if not error.is_empty():break
	var path:=folder.path_join("asset"+SUFFIX)
	if error.is_empty():error=LevelProjectIO.write_json(path,data)
	if not error.is_empty():
		for file in written:DirAccess.remove_absolute(file)
		DirAccess.remove_absolute(folder)
		return {"error":error}
	return {"error":"","path":relative.path_join("asset"+SUFFIX)}
