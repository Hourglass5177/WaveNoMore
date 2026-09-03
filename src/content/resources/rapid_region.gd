## 双钟疾振区域：在一段时间内统计有效敲击次数，并可要求生、死两钟交替。
@tool
class_name RapidRegion
extends Resource

@export_group("Identity")
## 全谱唯一的稳定 ID，供编译、判定与 Replay 对齐本段疾振。
@export var event_id: String = ""
## 本区域 MISS 的扣血组；同组只扣一次，空值回退到事件 ID。
@export var damage_group_id: String = ""

@export_group("Timing")
## 疾振开始的绝对谱面 tick；数值越大，区域越靠后。
@export var tick: int = 0
## 疾振持续 tick 数；数值越大，可敲击时段越长。
@export var duration_ticks: int = 480

@export_group("Rapid")
## 达标所需的有效敲击次数，范围 2～128；数值越大，要求越密集或持续更久。
@export_range(2, 128, 1) var required_strikes: int = 8
## 两次计数之间的最短间隔，单位毫秒、范围 0～250；数值越大，越能滤除按键抖动，也越限制最高连击速度。
@export_range(0, 250, 1) var debounce_ms: int = 35
## 开启时必须生钟、死钟交替敲击；连续敲同一侧不会增加次数。
@export var must_alternate: bool = true

@export_group("Presentation")
## 美术变体键；只换表现，不改变疾振判定。
@export var visual_variant: StringName = &"default"
