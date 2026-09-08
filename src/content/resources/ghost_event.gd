class_name GhostEvent
extends Resource
## 一批同刻结算的 Ghost；数量为编排数量，当前旧预览可能显示更少目标。
@export var event_id: String = ""
@export var tick: int = 0
@export var count: int = 1
@export var tuning_ids: PackedStringArray = []
@export var boss: bool = false
var duration_ticks: int = 0
var affinity: int = GameplayTypes.Affinity.SU
