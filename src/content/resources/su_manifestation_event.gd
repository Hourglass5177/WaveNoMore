## 一次「素音」的动态凝现请求。
## 谱面只规定时机、数量和允许区域；预读期间预测真实载波在目标时刻的交点。
@tool
class_name SuManifestationEvent
extends Resource

@export_group("Identity")
## 全谱唯一的稳定 ID，供演出、日志和写谱器定位本次凝现。
@export var event_id: String = ""
## 可选双侧调频组；空字符串表示独立素音，不读取任何调频组成绩。
@export var group_id: String = ""

@export_group("Timing")
## 原地命中的绝对谱面 tick；有调频组时应位于该组结束后、所属调频段结束前。
@export var tick: int = 0

@export_group("Manifestation")
## 本次要求凝成的素音数量；预读等待足量交点，到时不足会报告实际数量。
@export_range(1, 16, 1) var count: int = 1
## 设计画布上的归一化允许区域，左上和尺寸均以 0～1 表示。
@export var spawn_region_normalized: Rect2 = Rect2(0.25, 0.2, 0.5, 0.6)
## 美术变体键；只改变素音外观，不改变波前交点计算。
@export var visual_variant: StringName = &"default"
## 目标 Note 的独立外观变体；为空时沿用 visual_variant。
@export var target_visual_variant: StringName = &""
## 目标命中后保留的秒数，仅影响表现层。
@export_range(0.05, 3.0, 0.01) var target_hold_duration_sec: float = 0.78
