## 歌曲音频及其时间基准。谱面 tick 0 对应音频中的 first_beat_offset_sec，而非文件开头。
@tool
class_name SongDefinition
extends Resource

@export_group("Identity")
## 歌曲稳定 ID；存档、关卡与音频校验靠它建立引用。
@export var song_id: String = ""
## 面向玩家显示的歌曲标题，不参与时间计算。
@export var title: String = ""
## 面向玩家显示的作者/艺术家名称，不参与时间计算。
@export var artist: String = ""

@export_group("Audio")
## 正式播放的音频资源；为空时 Graybox 可使用备用时长运行。
@export var audio_stream: AudioStream
## 音频文件开头到谱面 tick 0 的秒数，范围 -30～30；数值越大，首拍在音频中越晚。
@export_range(-30.0, 30.0, 0.001) var first_beat_offset_sec: float = 0.0
## 无法读取音频长度时采用的秒数，范围 0～3600；数值越大，关卡备用尾点越晚。
@export_range(0.0, 3600.0, 0.01) var fallback_duration_sec: float = 30.0
## 菜单试听从音频开头算起的秒数，范围 0～3600；数值越大，试听片段越靠后。
@export_range(0.0, 3600.0, 0.01) var preview_start_sec: float = 0.0
## 菜单试听持续秒数，范围 1～60；数值越大，试听越长。
@export_range(1.0, 60.0, 0.1) var preview_duration_sec: float = 15.0
