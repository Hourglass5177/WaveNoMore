## 拍号变化点。tick 表示新拍号开始生效的位置，分母只接受常见的二次幂音符时值。
@tool
class_name MeterEvent
extends Resource

## 拍号生效的绝对谱面 tick；数值越大，变化点越靠后。
@export var tick: int = 0
## 每小节包含的拍数，范围 1～32；数值越大，一小节容纳的拍越多。
@export_range(1, 32, 1) var numerator: int = 4
## 每一拍采用几分音符，必须是 1～32 的二次幂；数值越大，单拍时值越短。
@export_enum("1", "2", "4", "8", "16", "32") var denominator: int = 4
