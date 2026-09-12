class_name LevelFormat
extends RefCounted
## 关卡交换文档只保存制作数据；控件、缓存和玩家成绩不进入这里。
const VERSION := 1
const SECTIONS := ["intro", "song", "outro"]
const PROPERTIES := {"position": "位置", "rotation": "旋转", "scale": "大小", "opacity": "透明度", "color": "颜色", "visible": "显示", "text": "文字", "visible_ratio": "打字进度", "volume_db": "音量", "zoom": "镜头缩放", "shake": "震动"}

static func id(prefix: String) -> String:
	return prefix + "_" + Crypto.new().generate_random_bytes(8).hex_encode()

static func new_level() -> Dictionary:
	var stages := ChartSceneLibrary.shared().all_stages()
	return {"format": "minghe-level", "format_version": VERSION, "level_id": id("level"), "title": "未命名关卡", "author": "", "description": "", "cover": "", "order_index": 0, "scene_id": stages.back().stage_id if not stages.is_empty() else "s08", "song_path": "song/song.json", "intro_us": 0, "outro_us": 0, "rule_path": "res://content/rules/default_gameplay_rules.tres", "next_stage_id": "", "pet_id": "", "fc_grants_base_pet": true, "ap_grants_advanced_pet": true, "packs": [], "show": {"format": "minghe-show", "format_version": VERSION, "objects": [], "tracks": [], "bindings": [], "sequences": []}}

static func object(kind: String, asset := "") -> Dictionary:
	var names := {"sprite": "精灵", "image": "HUD 图片", "text": "HUD 文字", "actor": "BOSS", "group": "对象组", "environment": "环境", "camera": "镜头", "audio": "声音"}
	return {"id": id("object"), "name": names.get(kind, kind), "type": kind, "asset": asset, "parent_id": "", "layer": "hud" if kind in ["text", "image"] else "world", "depth": 0.0, "locked": false, "hidden": false, "fields": {"position": [960.0, 540.0], "rotation": 0.0, "scale": [1.0, 1.0], "opacity": 1.0, "color": "ffffffff", "visible": true, "size": [560.0, 100.0], "text": "在此输入文字", "font_size": 36, "alignment": 1, "font": "", "visible_ratio": 1.0, "volume_db": 0.0, "zoom": 1.0, "shake": 0.0}}

static func track(object_id: String, property: String, section := "song", kind := "property") -> Dictionary:
	return {"id": id("track"), "object_id": object_id, "property": property, "type": kind, "section": section, "difficulties": [], "muted": false, "locked": false, "keys": [], "clips": []}

static func key(time_us: int, value) -> Dictionary:
	return {"id": id("key"), "time_us": time_us, "value": value, "interpolation": "linear", "out_handle": [0.333333, 0.333333], "in_handle": [0.666667, 0.666667]}

static func clip(time_us: int, asset := "", duration_us := 1000000) -> Dictionary:
	return {"id": id("clip"), "name": "片段", "start_us": time_us, "duration_us": duration_us, "asset": asset, "action": "", "offset_us": 0, "rate": 1.0, "loop": false, "fade_in_us": 0, "fade_out_us": 0, "gain_db": 0.0, "hold_last": false}

static func visible_in(track_data: Dictionary, difficulty: String) -> bool:
	return not track_data.get("muted", false) and (track_data.get("difficulties", []).is_empty() or difficulty in track_data.difficulties)

static func find(entries: Array, entry_id: String) -> Dictionary:
	for entry: Dictionary in entries:
		if entry.get("id", "") == entry_id: return entry
	return {}

static func vec(value, fallback := Vector2.ZERO) -> Vector2:
	if value is Vector2: return value
	if value is Array and value.size() >= 2: return Vector2(float(value[0]), float(value[1]))
	return fallback

static func issues(level: Dictionary, charts: Array = []) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if level.get("format", "") != "minghe-level" or int(level.get("format_version", 0)) != VERSION:
		result.append({"message": "无法读取此关卡格式", "severity": "error"}); return result
	var show: Dictionary = level.get("show", {})
	var objects: Array = show.get("objects", [])
	var ids := {}
	for object_data: Dictionary in objects:
		var object_id := str(object_data.get("id", ""))
		if object_id.is_empty() or ids.has(object_id): result.append({"message": "对象标识为空或重复", "object_id": object_id, "severity": "error"})
		ids[object_id] = true
		# 父子环会让变换无法求值，直接定位到产生环的对象。
		var parents := {object_id: true}
		var parent := str(object_data.get("parent_id", ""))
		while not parent.is_empty():
			if parents.has(parent): result.append({"message": "对象分组形成循环", "object_id": object_id, "severity": "error"}); break
			parents[parent] = true
			var found := find(objects, parent)
			if found.is_empty(): result.append({"message": "找不到父对象", "object_id": object_id, "severity": "error"}); break
			parent = str(found.get("parent_id", ""))
	for track_data: Dictionary in show.get("tracks", []):
		if not ids.has(track_data.get("object_id", "")): result.append({"message": "轨道关联的对象已删除", "track_id": track_data.get("id", ""), "severity": "error"})
		for clip_data: Dictionary in track_data.get("clips", []):
			if int(clip_data.get("duration_us", 0)) <= 0 or float(clip_data.get("rate", 1.0)) <= 0:
				result.append({"message": "片段长度和播放速率须大于零", "track_id": track_data.id, "time_us": clip_data.get("start_us", 0), "severity": "error"})
	for binding: Dictionary in show.get("bindings", []):
		if not ids.has(binding.get("object_id", "")): result.append({"message": "攻击绑定的 BOSS 已删除", "binding_id": binding.get("id", ""), "severity": "error"})
		for chart: SongChart in charts:
			if chart.difficulty_id != binding.get("difficulty", ""): continue
			var note_ids := {}
			for note in ChartEditEvents.all(chart):
				if (note is NoteEvent or note is GhostEvent) and note.boss:note_ids[note.event_id] = true
			for note_id in binding.get("note_ids", []):
				if not note_ids.has(note_id): result.append({"message": "攻击音符已删除或取消 BOSS 标记：" + str(note_id), "binding_id": binding.get("id", ""), "severity": "error"})
	return result
