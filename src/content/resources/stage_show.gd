## 与 SongChart 平行的演出时间轴。演出可以跟随同一 tick 前进，但不得参与或改写玩法判定。
@tool
class_name StageShow
extends Resource

## 演出资源格式版本；仅在字段结构迁移时递增。
@export var schema_version: int = 1
## 演出时间轴的稳定 ID，供关卡组合和工具识别。
@export var show_id: String = ""
## 按谱面 tick 调度的演出指令列表；只驱动表现，不参与判定。
@export var cues: Array[ShowCue] = []
## 关卡工具的绝对时间演出；旧 Cue 与它显式并存，不自动复制场景演出。
@export var level_data: Dictionary = {}
## 外部关卡装载时注入；内置关卡保存 res:// 素材目录及包引用。
@export var asset_directory: String = ""
@export var asset_packs: Array = []
var difficulty_id: String = ""
