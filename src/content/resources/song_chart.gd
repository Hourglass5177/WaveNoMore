## 正式谱面根资源。tick 是谱面使用的整数时间刻度；PPQ 表示一个四分音符被切成多少 tick。
## 运行时再把这些刻度统一编译为微秒时间轴。
@tool
class_name SongChart
extends Resource

## 当前可直接读取的谱面结构版本；旧版共同游标调频无法可靠迁移，会被明确拒绝。
const CURRENT_SCHEMA_VERSION: int = 2
## 默认每四分音符 480 tick；PPQ 越大，可表达的节奏位置越精细。
const DEFAULT_PPQ: int = 480

@export_group("Identity")
## 当前资源的格式版本；只随字段结构迁移递增。
@export var schema_version: int = CURRENT_SCHEMA_VERSION
## 谱面稳定 ID；存档、Replay 与工具靠它识别本谱。
@export var chart_id: String = ""
## 难度稳定 ID，例如 normal；用于区分同歌不同谱，不是显示名。
@export var difficulty_id: String = "normal"

@export_group("Timing")
## 每四分音符包含的 tick 数，范围 24～3840；越大制谱分辨率越高。
@export_range(24, 3840, 1) var ppq: int = DEFAULT_PPQ
## 对全谱事件统一施加的 tick 偏移；正值整体推迟，负值整体提前。
@export var chart_offset_ticks: int = 0
## 作者声明的谱面尾点绝对 tick；越大，关卡最短持续时间越长。
@export var end_tick: int = 0
## BPM 变化表；tick 0 必须能取得速度，运行时由此把 tick 换算为微秒。
@export var tempo_events: Array[TempoEvent] = []
## 拍号变化表；主要服务网格与小节显示，不改变 tick 到微秒的速度换算。
@export var meter_events: Array[MeterEvent] = []

@export_group("Gameplay Tracks")
## Tap/Hold 音符轨；事件时间均使用本谱 PPQ 的绝对 tick。
@export var note_events: Array[NoteEvent] = []
## 调频开放区域轨；区域只决定何时允许改变频率，本身不计分。
@export var tuning_fields: Array[TuningFieldRegion] = []
## 生、死两钟各自的粗滑条轨；同 group_id 的双侧滑条合并为一次判定。
@export var tuning_sliders: Array[TuningSliderEvent] = []
## 素音动态凝现轨；只声明时机和候选区域，不保存固定坐标，也不计分。
@export var su_manifestations: Array[SuManifestationEvent] = []
## 双钟高速交替敲击区域轨。
@export var rapid_regions: Array[RapidRegion] = []

@export_group("Authoring")
## 仅供写谱与教学定位的段落标记；不计入理论判定单位。
@export var sections: Array[SectionMarker] = []
