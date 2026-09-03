## 一段允许玩家改变双钟频率的时间区域。
## 它只开放调频操作，不直接计分；真正的跟随目标由 TuningSliderEvent 描述。
@tool
class_name TuningFieldRegion
extends Resource

@export_group("Identity")
## 全谱唯一的稳定 ID；调频滑条通过 field_id 指回本区域。
@export var event_id: String = ""

@export_group("Timing")
## 区域起点的绝对谱面 tick；进入该时刻后，摇杆或拖动才会改变频率。
@export var tick: int = 0
## 区域持续 tick 数；离开区域后，新发出的载波恢复统一基准频率。
@export var duration_ticks: int = 480
