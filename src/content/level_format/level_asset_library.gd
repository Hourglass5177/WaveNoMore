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
				issues.append({"message": "无法加载素材包：" + str(pack_data.path), "severity": "error"}); continue
			mounted[path] = true
		var manifest := load(str(pack_data.manifest)) as VisualAssetManifest
		if manifest == null:
			issues.append({"message": "找不到素材清单：" + str(pack_data.manifest), "severity": "error"}); continue
		for entry: VisualAssetEntry in manifest.entries:
			entries[entry.asset_id] = entry

func resolve(asset: String) -> Resource:
	if asset.is_empty(): return null
	if cache.has(asset): return cache[asset]
	var result: Resource
	if entries.has(asset): result = entries[asset].runtime_scene
	else:
		var path := asset if asset.begins_with("res://") else directory.path_join(asset)
		if not FileAccess.file_exists(path) and not ResourceLoader.exists(path): return null
		if asset.begins_with("res://"): result = load(path)
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

func anchor(asset: String, anchor_name: String) -> Vector2:
	if not entries.has(asset): return Vector2.ZERO
	return LevelFormat.vec(entries[asset].anchors.get(anchor_name, Vector2.ZERO))

func actions(asset: String) -> PackedStringArray:
	return entries[asset].state_names if entries.has(asset) else PackedStringArray()

func release_time(asset: String, action: String) -> float:
	if not entries.has(asset): return 0.0
	return float(entries[asset].action_markers.get(action, {}).get("release_sec", 0.0))

func list_files(folder := "assets") -> PackedStringArray:
	var result := PackedStringArray()
	for file in DirAccess.get_files_at(directory.path_join(folder)): result.append(folder.path_join(file))
	for child in DirAccess.get_directories_at(directory.path_join(folder)): result.append_array(list_files(folder.path_join(child)))
	return result

func validate_level(level: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = issues.duplicate(true)
	var references := []
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
	for reference: Dictionary in references:
		var resource := resolve(str(reference.asset))
		var valid := resource != null
		match str(reference.kind):
			"actor", "environment": valid = resource is PackedScene
			"image", "sprite": valid = resource is Texture2D
			"audio": valid = resource is AudioStream
			"font": valid = resource is Font
			"effect": valid = resource is PackedScene or resource is Texture2D
		if not valid:
			var problem := reference.duplicate(); problem.message = "素材缺失或类型不符：" + str(reference.asset); problem.severity="error"; result.append(problem)
	return result
