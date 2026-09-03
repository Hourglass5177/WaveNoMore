## 同一段波形由细到粗保存多级峰值：放大时用细层，缩小时用粗层；
## 同时记录源文件指纹，用来判断磁盘缓存是否仍然有效。
@tool
class_name MingheWaveformCache
extends Resource

## 生成缓存时使用的 WAV 绝对或 `user://` 路径。
@export var source_path: String = ""
## 生成缓存时 WAV 的文件字节数，是快速失效检查的第一层。
@export var source_size: int = 0
## 生成缓存时 WAV 的文件修改时间戳。
@export var source_modified_time: int = 0
## WAV 全文件 SHA-256；大小和时间都相同后仍用它做最终确认。
@export var source_sha256: String = ""
## 原 WAV 每秒采样帧数，单位 Hz。
@export var sample_rate: int = 0
## 原 WAV 声道数；构建缓存时各声道合并成同一最小/最大包络。
@export var channels: int = 0
## 原 WAV 总采样帧数，与 sample_rate 相除得到音频秒数。
@export var frame_count: int = 0
## 每个层级的一项峰值覆盖多少源音频帧，与 levels 使用相同下标。
@export var block_sizes: PackedInt32Array = PackedInt32Array()
## levels 中每个 Vector2 表示一个采样块，x/y 分别是该块的最小、最大振幅。
@export var levels: Array = []


func duration_seconds() -> float:
	return float(frame_count) / float(sample_rate) if sample_rate > 0 else 0.0


func is_current(path: String) -> bool:
	if source_path != path or not FileAccess.file_exists(path):
		return false
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null or source_size != source.get_length():
		return false
	if source_modified_time != int(FileAccess.get_modified_time(path)):
		return false
	return source_sha256 == FileAccess.get_sha256(path)


func choose_level(source_frames_per_pixel: float) -> int:
	# 选择最接近当前缩放密度的层级，既保留波峰，也限制每帧绘制量。
	if block_sizes.is_empty():
		return -1
	var best := 0
	for index in block_sizes.size():
		if float(block_sizes[index]) <= source_frames_per_pixel * 2.0:
			best = index
		else:
			break
	return best
