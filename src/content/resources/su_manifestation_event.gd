## 一次「素音」的动态凝现请求。
## 谱面只规定时机、数量和允许区域；精确坐标由当时真实生死波前的交点决定。
@tool
class_name SuManifestationEvent
extends Resource

@export_group("Identity")
## 全谱唯一的稳定 ID，供演出、日志和写谱器定位本次凝现。
@export var event_id: String = ""
## 关联的双侧调频组；该组必须同时包含一条生滑条和一条死滑条。
@export var group_id: String = ""

@export_group("Timing")
## 尝试凝现的绝对谱面 tick；应位于关联滑条结束后、所属调频段结束前。
@export var tick: int = 0

@export_group("Manifestation")
## 本次最多凝成的素音数量；候选交点不足时允许少于该数。
@export_range(1, 16, 1) var count: int = 1
## 设计画布上的归一化允许区域，左上和尺寸均以 0～1 表示。
@export var spawn_region_normalized: Rect2 = Rect2(0.25, 0.2, 0.5, 0.6)
## 美术变体键；只改变素音外观，不改变波前交点计算。
@export var visual_variant: StringName = &"default"
