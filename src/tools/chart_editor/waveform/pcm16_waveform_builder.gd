## 制谱 WAV 波形解析器。把 PCM16 音频压成多级 min/max 峰值缓存，避免时间线逐样本绘制。
@tool
class_name MinghePcm16WaveformBuilder
extends RefCounted

## 最细一级每 256 帧汇总一次最小/最大振幅；后续层级每四块继续合并。
const BASE_BLOCK_FRAMES := 256
## 生成的 `.tres` 缓存放在 user://，不污染项目资源目录。
const CACHE_DIRECTORY := "user://minghe_chart_editor/waveform_cache"


static func load_or_build(path: String) -> Dictionary:
	# 源文件大小、修改时间和 SHA-256 全部一致时才复用旧缓存。
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"cache": null, "error": "WAV 文件不存在：%s" % path}
	var cache_path := _cache_path_for(path)
	if ResourceLoader.exists(cache_path):
		var existing := ResourceLoader.load(cache_path, "", ResourceLoader.CACHE_MODE_IGNORE) as MingheWaveformCache
		if existing != null and existing.is_current(path):
			return {"cache": existing, "error": ""}
	var built := _build(path)
	if built.cache != null:
		_ensure_cache_directory()
		var error := ResourceSaver.save(built.cache, cache_path)
		if error != OK:
			built.error = "%s（缓存保存失败：%s）" % [built.error, error_string(error)]
	return built


static func _build(path: String) -> Dictionary:
	# 只接受未压缩的 16-bit PCM WAV；正式游戏音频格式与制谱波形源可以不同。
	# 第一阶段解析 RIFF 容器，找到 fmt 格式说明和 data 采样区。
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"cache": null, "error": "无法打开 WAV：%s" % path}
	file.big_endian = false
	if _read_fourcc(file) != "RIFF":
		return {"cache": null, "error": "不是 RIFF WAV：%s" % path}
	file.get_32()
	if _read_fourcc(file) != "WAVE":
		return {"cache": null, "error": "不是 WAVE 文件：%s" % path}

	var audio_format := 0
	var channels := 0
	var sample_rate := 0
	var bits_per_sample := 0
	var data_offset := -1
	var data_size := 0
	while file.get_position() + 8 <= file.get_length():
		var chunk_id := _read_fourcc(file)
		var chunk_size := int(file.get_32())
		var chunk_start := file.get_position()
		if chunk_id == "fmt ":
			audio_format = int(file.get_16())
			channels = int(file.get_16())
			sample_rate = int(file.get_32())
			file.get_32()
			file.get_16()
			bits_per_sample = int(file.get_16())
		elif chunk_id == "data":
			data_offset = file.get_position()
			data_size = chunk_size
		file.seek(chunk_start + chunk_size + (chunk_size & 1))

	if audio_format != 1 or bits_per_sample != 16:
		return {"cache": null, "error": "仅支持 16-bit PCM WAV（format=1），当前 format=%d bits=%d" % [audio_format, bits_per_sample]}
	if channels < 1 or channels > 8 or sample_rate <= 0 or data_offset < 0:
		return {"cache": null, "error": "WAV fmt/data 块无效"}
	# 第二阶段把多声道样本压成每个 256 帧块的一对最小/最大值。
	var frame_size := channels * 2
	var frame_count := data_size / frame_size
	file.seek(data_offset)
	var pcm := file.get_buffer(frame_count * frame_size)
	var level_zero := PackedVector2Array()
	var block_min := 1.0
	var block_max := -1.0
	var frames_in_block := 0
	for frame_index in frame_count:
		var frame_min := 1.0
		var frame_max := -1.0
		var frame_base := frame_index * frame_size
		for channel_index in channels:
			var byte_index := frame_base + channel_index * 2
			var raw := int(pcm[byte_index]) | (int(pcm[byte_index + 1]) << 8)
			if raw >= 32768:
				raw -= 65536
			var sample := clampf(float(raw) / 32768.0, -1.0, 1.0)
			frame_min = minf(frame_min, sample)
			frame_max = maxf(frame_max, sample)
		block_min = minf(block_min, frame_min)
		block_max = maxf(block_max, frame_max)
		frames_in_block += 1
		if frames_in_block == BASE_BLOCK_FRAMES:
			level_zero.append(Vector2(block_min, block_max))
			block_min = 1.0
			block_max = -1.0
			frames_in_block = 0
	if frames_in_block > 0:
		level_zero.append(Vector2(block_min, block_max))

	var cache := MingheWaveformCache.new()
	cache.source_path = path
	cache.source_size = file.get_length()
	cache.source_modified_time = int(FileAccess.get_modified_time(path))
	cache.source_sha256 = FileAccess.get_sha256(path)
	cache.sample_rate = sample_rate
	cache.channels = channels
	cache.frame_count = frame_count
	cache.block_sizes = PackedInt32Array([BASE_BLOCK_FRAMES])
	cache.levels = [level_zero]
	# 第三阶段建立更粗的层级，缩小时无需重新扫描底层全部采样块。
	var current := level_zero
	# 每四个块合并一级，缩小时选择粗层级，避免一列像素遍历大量峰值。
	var block_size := BASE_BLOCK_FRAMES
	while current.size() > 1024:
		var next_level := PackedVector2Array()
		for index in range(0, current.size(), 4):
			var low := 1.0
			var high := -1.0
			for sub_index in range(index, mini(index + 4, current.size())):
				low = minf(low, current[sub_index].x)
				high = maxf(high, current[sub_index].y)
			next_level.append(Vector2(low, high))
		block_size *= 4
		cache.block_sizes.append(block_size)
		cache.levels.append(next_level)
		current = next_level
	return {"cache": cache, "error": ""}


static func _read_fourcc(file: FileAccess) -> String:
	return file.get_buffer(4).get_string_from_ascii()


static func _cache_path_for(path: String) -> String:
	return "%s/%s.tres" % [CACHE_DIRECTORY, path.sha256_text()]


static func _ensure_cache_directory() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIRECTORY))
