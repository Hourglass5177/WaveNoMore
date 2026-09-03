## BPM 变化点；从 tick 开始，后续 tick 按新的每分钟拍数换算为时间。
@tool
class_name TempoEvent
extends Resource

## 速度变化生效的绝对谱面 tick；数值越大，变化点越靠后。
@export var tick: int = 0
## 每分钟四分音符拍数，范围 1～400 BPM；数值越大，后续节拍越快、同样 tick 间隔越短。
@export_range(1.0, 400.0, 0.01) var bpm: float = 120.0
