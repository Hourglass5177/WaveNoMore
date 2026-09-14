class_name LevelAssetLibrary
extends RefCounted
## 素材包提供实例模板；普通文件在工程目录里解码，避免依赖编辑器导入缓存。
var directory := ""
var entries := {}
var cache := {}
var issues: Array[Dictionary] = []
static var mounted := {}

func configure(root: String, packs: Array) -> void:
	directory = root; entries.clear(); cache.clear(); issues.clear()
	for pack_data: Dictionary in packs:
		var path := root.path_join(str(pack_data.path))
		if not mounted.has(path):
			if not ProjectSettings.load_resource_pack(path, false):
				issues.append({"message": "无法加载素材包：" + str(pack_data.path), "severity": "error", "pack_path":str(pack_data.path)}); continue
			mounted[path] = true
		var manifest := load(str(pack_data.manifest)) as VisualAssetManifest
		if manifest == null:
			issues.append({"message": "找不到素材清单：" + str(pack_data.manifest), "severity": "error", "pack_path":str(pack_data.path)}); continue
		for entry: VisualAssetEntry in manifest.entries:
			entries[entry.asset_id] = entry

func resolve(asset: String) -> Resource:
	if asset.is_empty(): return null
	if cache.has(asset): return cache[asset]
	var result: Resource
	if entries.has(asset): result = entries[asset].background if entries[asset].background != null else entries[asset].runtime_scene
	else:
		var path := asset if asset.begins_with("res://") else directory.path_join(asset)
		if not FileAccess.file_exists(path) and not ResourceLoader.exists(path): return null
		if asset.ends_with(LevelAnimationAsset.SUFFIX): result=LevelAnimationAsset.load_frames(path)
		elif path.get_extension().to_lower() in ["tres","res"]:result=load(path)
		elif asset.begins_with("res://"): result = load(path)
		else:
			match path.get_extension().to_lower():
				"png", "jpg", "jpeg", "webp", "svg":
					var picture := Image.load_from_file(path)
					if picture != null: result = ImageTexture.create_from_image(picture)
				"wav", "ogg", "mp3": result = ChartJsonCodec.load_audio(path)
				"ttf", "otf":
					var font := FontFile.new()
					if font.load_dynamic_font(path) == OK: result = font
	cache[asset] = result
	return result

func instantiate(asset: String) -> Node:
	var resource := resolve(asset)
	if resource is PackedScene: return resource.instantiate()
	return null

func animation_names(asset: String) -> PackedStringArray:
	var resource := resolve(asset)
	if resource is SpriteFrames: return resource.get_animation_names()
	return PackedStringArray()

func default_animation(asset: String) -> String:
	var names := animation_names(asset)
	if asset.ends_with(LevelAnimationAsset.SUFFIX):
		var preferred:=str(LevelProjectIO.read_json(directory.path_join(asset)).get("default_animation",""))
		if preferred in names:return preferred
	if names.has("default"): return "default"
	return names[0] if not names.is_empty() else ""

## 内置环境只借用 StageDefinition 的背景，不切换主题、歌曲或玩法。
func background(asset: String) -> StageBackgroundDefinition:
	if asset.begins_with("stage:"):
		return ChartSceneLibrary.shared().resolve({"scene_id": asset.trim_prefix("stage:")}).get("background") as StageBackgroundDefinition
	return resolve(asset) as StageBackgroundDefinition

func backgrounds() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for stage in ChartSceneLibrary.shared().all_stages():
		if stage.background == null and stage.background_resource_path.is_empty(): continue
		result.append({"id": "stage:" + stage.stage_id, "name": stage.display_name, "thumbnail": stage.cover})
	for asset: String in entries:
		var entry: VisualAssetEntry = entries[asset]
		if entry.background != null: result.append({"id": asset, "name": entry.display_name if not entry.display_name.is_empty() else asset, "thumbnail": entry.thumbnail})
	return result

func anchor(asset: String, anchor_name: String) -> Vector2:
	if not entries.has(asset): return Vector2.ZERO
	return LevelFormat.vec(entries[asset].anchors.get(anchor_name, Vector2.ZERO))

func actions(asset: String) -> PackedStringArray:
	return entries[asset].state_names if entries.has(asset) else animation_names(asset)

func release_time(asset: String, action: String) -> float:
	if not entries.has(asset): return 0.0
	return float(entries[asset].action_markers.get(action, {}).get("release_sec", 0.0))

func list_files(folder := "assets") -> PackedStringArray:
	var result := PackedStringArray()
	if not DirAccess.dir_exists_absolute(directory.path_join(folder)): return result
	for file in DirAccess.get_files_at(directory.path_join(folder)): result.append(folder.path_join(file))
	for child in DirAccess.get_directories_at(directory.path_join(folder)):
		var nested:=folder.path_join(child)
		if FileAccess.file_exists(directory.path_join(nested).path_join("asset"+LevelAnimationAsset.SUFFIX)):result.append(nested.path_join("asset"+LevelAnimationAsset.SUFFIX))
		else:result.append_array(list_files(nested))
	return result

func validate_level(level: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = issues.duplicate(true)
	var environments: Array = level.show.get("scene_cues", []).duplicate()
	if not str(level.get("initial_background", "")).is_empty(): environments.append({"asset": level.initial_background, "id": ""})
	for cue: Dictionary in environments:
		if background(str(cue.asset)) == null:
			result.append({"message": "环境场景资源缺失：" + str(cue.asset), "scene_cue_id": str(cue.id), "time_us": cue.get("time_us", 0), "severity": "error"})
	var references := []
	# 补齐模板、关键帧和动画内部图片；所有定位信息沿用资源引用枚举。
	for reference: Dictionary in LevelProjectIO.references(level):
		var asset: String=reference.asset
		if not asset.begins_with("assets/"):continue
		if not FileAccess.file_exists(directory.path_join(asset)):
			var issue:=reference.duplicate();issue.message="素材缺失："+asset;issue.severity="error";result.append(issue)
		elif asset.ends_with(LevelAnimationAsset.SUFFIX):
			for dependency in LevelAnimationAsset.dependencies(directory.path_join(asset)):
				if not FileAccess.file_exists(dependency):
					var issue:=reference.duplicate();issue.dependency=dependency;issue.message="动画图片缺失："+dependency.get_file();issue.severity="error";result.append(issue)
	if not str(level.get("cover", "")).is_empty(): references.append({"asset":level.cover,"kind":"image"})
	for object_data: Dictionary in level.show.get("objects", []):
		if not str(object_data.asset).is_empty(): references.append({"asset":object_data.asset,"object_id":object_data.id,"kind":object_data.type})
		var font := str(object_data.fields.get("font", ""))
		if not font.is_empty(): references.append({"asset":font,"object_id":object_data.id,"kind":"font"})
	for track: Dictionary in level.show.get("tracks", []):
		for clip: Dictionary in track.clips:
			if track.type in ["audio", "effect"] and not str(clip.asset).is_empty(): references.append({"asset":clip.asset,"track_id":track.id,"time_us":clip.start_us,"kind":track.type})
	for binding: Dictionary in level.show.get("bindings", []):
		for field: String in ["sound","effect","hit_effect","miss_effect"]:
			if not str(binding.get(field, "")).is_empty(): references.append({"asset":binding[field],"binding_id":binding.id,"kind":"audio" if field=="sound" else "effect"})
	for track: Dictionary in level.show.get("tracks",[]):
		if track.type!="action":continue
		var object_data:=LevelFormat.find(level.show.objects,str(track.object_id))
		if object_data.is_empty() or str(object_data.asset).is_empty():continue
		var names:=actions(str(object_data.asset))
		if names.is_empty():continue
		for clip: Dictionary in track.clips:
			if str(clip.action) not in names:result.append({"message":"动作缺失："+str(clip.action)+"；请选择此素材中的动作。","object_id":object_data.id,"track_id":track.id,"item_id":clip.id,"time_us":clip.start_us,"severity":"error"})
	for reference: Dictionary in references:
		if result.any(func(issue):return issue.get("asset","")==reference.asset and issue.get("object_id","")==reference.get("object_id","") and issue.get("track_id","")==reference.get("track_id","")):continue
		var resource := resolve(str(reference.asset))
		var valid := resource != null
		match str(reference.kind):
			"actor", "environment": valid = resource is PackedScene
			"image", "sprite": valid = resource is Texture2D or resource is SpriteFrames
			"animated_sprite": valid = resource is SpriteFrames
			"audio": valid = resource is AudioStream
			"font": valid = resource is Font
			"effect": valid = resource is PackedScene or resource is Texture2D
		if not valid:
			var problem := reference.duplicate()
			for located: Dictionary in LevelProjectIO.references(level):
				if located.asset==reference.asset and located.get("object_id","")==reference.get("object_id","") and located.get("track_id","")==reference.get("track_id",""):problem.merge(located);break
			problem.message = "素材缺失或类型不符：" + str(reference.asset); problem.severity="error"; result.append(problem)
	return result

## 分类不触发图片、字体或声音解码。
func kind(asset: String) -> String:
	if entries.has(asset):
		return "background" if entries[asset].background!=null else "scene"
	if asset.ends_with(LevelAnimationAsset.SUFFIX):return "animation"
	var extension:=asset.get_extension().to_lower()
	if extension in LevelAnimationAsset.IMAGE_EXTENSIONS:return "image"
	if extension in ["wav","ogg","mp3"]:return "audio"
	if extension in ["ttf","otf"]:return "font"
	if extension in ["tres","res"] and resolve(asset) is SpriteFrames:return "animation"
	return "unknown"
