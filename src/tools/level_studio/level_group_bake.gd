class_name LevelGroupBake
extends RefCounted
## 解组时仅烘焙被移除父组的影响；保留上级分组和所有难度的最终姿态。
const FIELDS := ["position", "rotation", "scale", "skew", "color", "visible", "opacity"]

static func changes(source: Dictionary, ids: PackedStringArray, difficulties: PackedStringArray) -> Array:
	var show := source.duplicate(true)
	for id in ids:
		var group := LevelFormat.find(show.objects, id)
		if group.get("type", "") != "group": continue
		var old := show.duplicate(true)
		var children: Array = old.objects.filter(func(object_data): return object_data.get("parent_id", "") == id)
		for object_data: Dictionary in children:
			var child := LevelFormat.find(show.objects, object_data.id)
			child.parent_id = group.parent_id; child.layer = group.layer; child.hidden = false
			child.fields.opacity = 1.0
			show.tracks = show.tracks.filter(func(track): return track.object_id != child.id or (track.type != "visibility" and track.property not in FIELDS))
			for section: String in LevelFormat.SECTIONS:
				var times := {0:true}; var first := 0; var last := 0
				for track: Dictionary in old.tracks:
					if track.object_id not in [id, child.id] or track.section != section: continue
					for key: Dictionary in track.keys: times[int(key.time_us)] = true
					for clip: Dictionary in track.clips:
						times[int(clip.start_us)] = true; times[int(clip.start_us)+int(clip.duration_us)] = true
				for time: int in times: first = mini(first, time); last = maxi(last, time)
				var sample_us := first
				while sample_us < last: times[sample_us] = true; sample_us += 16667
				var ordered: Array = times.keys(); ordered.sort()
				for difficulty: String in difficulties:
					var tracks := {}
					for property: String in FIELDS:
						if property == "opacity": continue
						var track := LevelFormat.track(child.id, property, section)
						track.difficulties = [difficulty] if difficulties.size() > 1 else []
						tracks[property] = track; show.tracks.append(track)
					for time: int in ordered:
						var pose := LevelShowSampler.object_transform(old, child.id, section, time, difficulty)
						var parent_pose := Transform2D.IDENTITY
						if not str(child.parent_id).is_empty(): parent_pose = LevelShowSampler.object_transform(old, child.parent_id, section, time, difficulty)
						elif child.layer == "death": parent_pose = Transform2D(PI, Vector2(1920,1080))
						pose = parent_pose.affine_inverse() * pose
						var group_look := LevelShowSampler.local_appearance(old, group, section, time, difficulty)
						var child_look := LevelShowSampler.local_appearance(old, object_data, section, time, difficulty)
						var values := {"position":[pose.origin.x,pose.origin.y],"rotation":rad_to_deg(pose.get_rotation()),"scale":[pose.get_scale().x,pose.get_scale().y],"skew":rad_to_deg(pose.get_skew()),"color":(group_look.color * child_look.color).to_html(),"visible":group_look.visible and child_look.visible}
						for property: String in tracks: tracks[property].keys.append(LevelFormat.key(time, values[property]))
		show.objects = show.objects.filter(func(object_data): return object_data.id != id)
		show.tracks = show.tracks.filter(func(track): return track.object_id != id)
	var result := []
	for kind: String in ["objects", "tracks"]:
		var before := []; var after := []
		for entry: Dictionary in source[kind]:
			if entry != LevelFormat.find(show[kind], entry.id): before.append(entry)
		for entry: Dictionary in show[kind]:
			if entry != LevelFormat.find(source[kind], entry.id): after.append(entry)
		if not before.is_empty() or not after.is_empty(): result.append({"kind":kind,"before":before,"after":after})
	return result
