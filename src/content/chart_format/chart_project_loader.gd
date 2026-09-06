class_name ChartProjectLoader
extends RefCounted
const THEMES := {
	"default": "res://content/stages/s02/stage_visual_theme.tres",
	"s01_free_carrier_theme": "res://content/stages/s01/stage_visual_theme.tres",
	"s02_tap_lab_theme": "res://content/stages/s02/stage_visual_theme.tres",
	"s03_hold_lab_theme": "res://content/stages/s03/stage_visual_theme.tres",
	"s04_rotary_tuning_theme": "res://content/stages/s04/stage_visual_theme.tres",
	"s05_combined_lab_theme": "res://content/stages/s05/stage_visual_theme.tres",
}
## 游戏和工具共用的接入点：JSON 项目直接装配正式领域资源，不另造导出音符。
static func make_stage(song: SongDefinition, chart: SongChart) -> StageDefinition:
	var stage := StageDefinition.new()
	stage.stage_id = chart.chart_id
	stage.display_name = song.title
	stage.song = song.duplicate(true)
	stage.chart = chart.duplicate(true)
	var raw: Dictionary = chart.get_meta("json_source", {})
	stage.song.first_beat_offset_sec = float(raw.get("timing", {}).get("first_beat_offset_ms", 0)) / 1000.0
	stage.stage_show = StageShow.new()
	var theme_id := str(raw.get("presentation", {}).get("theme_id", "default"))
	stage.visual_theme = load(THEMES.get(theme_id, THEMES.default)).duplicate(true)
	var palette: Dictionary = raw.get("presentation", {}).get("palette_overrides", {})
	for key in ["life", "death", "su", "ink", "paper"]:
		if palette.has(key): stage.visual_theme.set(key + "_color", Color(str(palette[key])))
	stage.reward = RewardDefinition.new()
	stage.rule_set = load("res://content/rules/default_gameplay_rules.tres")
	return stage

static func load_stage(song_path: String, difficulty_id: String = "") -> Dictionary:
	if song_path.get_extension().to_lower() == "zip":
		var pack := ZIPReader.new()
		if pack.open(song_path) != OK: return {"stage": null, "errors": ["无法打开谱面包"]}
		var result := _read_stage(func(relative: String) -> PackedByteArray: return pack.read_file(relative), difficulty_id)
		pack.close()
		return result
	return _read_stage(func(relative: String) -> PackedByteArray: return FileAccess.get_file_as_bytes(song_path.get_base_dir().path_join(relative)), difficulty_id)

static func _read_stage(read: Callable, difficulty_id: String) -> Dictionary:
	var song_bytes: PackedByteArray = read.call("song.json")
	var raw: Variant = JSON.parse_string(song_bytes.get_string_from_utf8())
	if not raw is Dictionary: return {"stage": null, "errors": ["无法解析歌曲 JSON"]}
	var decoded := ChartJsonCodec.decode_song(raw)
	if decoded.song == null: return {"stage": null, "errors": decoded.errors}
	for entry: Dictionary in raw.get("charts", []):
		if not difficulty_id.is_empty() and entry.get("difficulty_id") != difficulty_id: continue
		var chart_bytes: PackedByteArray = read.call(str(entry.path))
		var chart_raw: Variant = JSON.parse_string(chart_bytes.get_string_from_utf8())
		if not chart_raw is Dictionary: return {"stage": null, "errors": ["无法解析难度 JSON"]}
		var chart := ChartJsonCodec.decode_chart(chart_raw)
		if chart.chart == null or not chart.errors.is_empty(): return {"stage": null, "errors": chart.errors}
		var theme_id := str(chart_raw.get("presentation", {}).get("theme_id", "default"))
		if not THEMES.has(theme_id): return {"stage": null, "errors": ["未知主题：" + theme_id]}
		var audio_path := str(raw.get("audio", ""))
		decoded.song.audio_stream = ChartJsonCodec.audio_from_bytes(read.call(audio_path), audio_path.get_extension())
		if decoded.song.audio_stream == null: return {"stage": null, "errors": ["音频缺失或无法解码"]}
		var stage := make_stage(decoded.song, chart.chart)
		var report := ChartValidator.validate(stage.chart, stage.rule_set)
		return {"stage": null if report.has_errors() else stage, "errors": report.issues}
	return {"stage": null, "errors": ["找不到指定难度"]}
