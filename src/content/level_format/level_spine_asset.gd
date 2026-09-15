class_name LevelSpineAsset
extends RefCounted
## 原始 Spine 数据、图集和图片随关卡保存；运行时复用现有手动骨骼采样。
const SUFFIX := ".skeleton.json"

static func pages(atlas_path: String) -> PackedStringArray:
	var result:=PackedStringArray();var next_page:=true
	for line in FileAccess.get_file_as_string(atlas_path).split("\n"):
		var value:=line.strip_edges()
		if value.is_empty():next_page=true;continue
		if next_page:result.append(value);next_page=false
	return result

static func read_data(skeleton_path: String, atlas_path: String) -> Dictionary:
	var result:={"error":"","data":null,"textures":[],"actions":[]}
	if not FileAccess.file_exists(skeleton_path) or not FileAccess.file_exists(atlas_path):
		result.error="请选择骨骼文件及对应的 .atlas 图集。";return result
	if skeleton_path.get_extension().to_lower() in ["json","spine-json"]:
		var version:=str(LevelProjectIO.read_json(skeleton_path).get("skeleton",{}).get("spine",""))
		if not version.begins_with("4.3"):
			result.error="此骨骼版本为 %s；请从 Spine 导出 4.3 数据。工程的旧 BOSS 转换脚本只适用于特定素材，不直接套用到任意骨骼。"%version;return result
	# 原始图片显式注册并持有，外部工程和导出程序不依赖 Godot 导入缓存。
	for page in pages(atlas_path):
		var path:=atlas_path.get_base_dir().path_join(page)
		var texture:=LevelAnimationAsset.read_texture(path)
		if texture==null:result.error="缺少图集图片："+path;return result
		texture.take_over_path(path);result.textures.append(texture)
	var atlas:=SpineAtlasResource.new();atlas.load_from_atlas_file(atlas_path)
	var file:=SpineSkeletonFileResource.new()
	if skeleton_path.get_extension().to_lower()=="json":
		# 原生扩展只把 .spine-json 识别成文本；候选预览临时规范后缀，不改作者源文件。
		var temporary:="user://level_studio/spine_import/"+LevelFormat.id("source")+".spine-json"
		DirAccess.make_dir_recursive_absolute(temporary.get_base_dir())
		var copied:=DirAccess.copy_absolute(skeleton_path,temporary)
		if copied!=OK:result.error="无法准备骨骼预览文件。";return result
		file.load_from_file(temporary);DirAccess.remove_absolute(temporary)
	else:file.load_from_file(skeleton_path)
	var data:=SpineSkeletonDataResource.new();data.atlas_res=atlas;data.skeleton_file_res=file
	if not data.is_skeleton_data_loaded():result.error="骨骼无法加载。请使用与工程 Spine 4.3 运行库匹配的导出文件，并检查图集。";return result
	for animation in data.get_animations():result.actions.append({"name":str(animation.get_name()),"duration":animation.get_duration()})
	if result.actions.is_empty():result.error="骨骼没有可用动作。";return result
	result.data=data;return result

static func scene(data: Dictionary, settings: Dictionary) -> PackedScene:
	var root:=Node2D.new();var sprite:=SpineSprite.new();root.add_child(sprite);sprite.owner=root
	sprite.skeleton_data_res=data.data;sprite.scale=Vector2.ONE*float(settings.get("scale",1.0))
	# Spine 制作坐标 Y 向上，以导出范围中心作为关卡对象原点。
	sprite.position=Vector2(-(data.data.get_x()+data.data.get_width()/2.0),data.data.get_y()+data.data.get_height()/2.0)*sprite.scale
	sprite.set_meta("level_default_animation",settings.get("default_animation",data.actions[0].name))
	root.set_meta("spine_textures",data.textures)
	var packed:=PackedScene.new();packed.pack(root);root.free();return packed

static func load_scene(path: String) -> PackedScene:
	var settings:=LevelProjectIO.read_json(path);var folder:=path.get_base_dir()
	var loaded:=read_data(folder.path_join(str(settings.get("skeleton",""))),folder.path_join(str(settings.get("atlas",""))))
	return scene(loaded,settings) if loaded.error.is_empty() else null

static func dependencies(path: String) -> PackedStringArray:
	var data:=LevelProjectIO.read_json(path);var folder:=path.get_base_dir();var result:=PackedStringArray()
	for relative in [data.get("skeleton",""),data.get("atlas","")]+data.get("pages",[]):
		if not str(relative).is_empty():result.append(folder.path_join(str(relative)))
	return result

static func write(skeleton_path: String, atlas_path: String, directory: String, settings: Dictionary) -> Dictionary:
	var loaded:=read_data(skeleton_path,atlas_path)
	if not loaded.error.is_empty():return {"error":loaded.error,"path":""}
	var relative:="assets/"+LevelFormat.id("spine");var folder:=directory.path_join(relative)
	DirAccess.make_dir_recursive_absolute(folder)
	var skeleton_name:="skeleton.skel" if skeleton_path.get_extension().to_lower()=="skel" else "skeleton.spine-json"
	var files:={skeleton_name:skeleton_path,atlas_path.get_file():atlas_path}
	var images:=pages(atlas_path)
	for page in images:files[page]=atlas_path.get_base_dir().path_join(page)
	for name: String in files:
		var target:=folder.path_join(name);DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if DirAccess.copy_absolute(files[name],target)!=OK:return {"error":"复制骨骼依赖失败："+name,"path":""}
	var description:=settings.duplicate(true)
	description.merge({"format":"minghe-spine","skeleton":skeleton_name,"atlas":atlas_path.get_file(),"pages":Array(images),"actions":loaded.actions})
	var path:=relative.path_join("asset"+SUFFIX)
	var error:=LevelProjectIO.write_json(directory.path_join(path),description)
	return {"error":error,"path":path}
