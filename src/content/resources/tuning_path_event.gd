class_name TuningPathEvent
extends Resource
## 新版编排数据。旧频率滑条只由当前规则适配器临时生成，不与本对象双向同步。
@export var event_id: String = ""
@export var affinity: int = GameplayTypes.Affinity.ZHU
@export var tick: int = 0
@export var hold_id: String = ""
@export var support_hold_id: String = ""
@export var points: Array[TuningPathPoint] = []
var duration_ticks: int:
	get: return points[-1].offset_ticks if not points.is_empty() else 0
	set(value):
		if not points.is_empty(): points[-1].offset_ticks = value
