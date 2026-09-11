## 一条由生钟或死钟独立完成的调频滑条。
## 玩家在 traversal_ticks 内走完一程；traversal_count 大于 1 时在两端往返。
@tool
class_name TuningSliderEvent
extends Resource

@export_group("Identity")
## 全谱唯一的稳定 ID；定位的是这一侧滑条，而不是整组判定。
@export var event_id: String = ""
## 所属 TuningFieldRegion 的 event_id；滑条必须完整落在该调频段内。
@export var field_id: String = ""
## 生、死滑条共用此 ID 时合并为一次判定；单侧滑条可留空。
@export var group_id: String = ""

@export_group("Semantics")
## 使用哪口钟：Zhu 为生钟，Xuan 为死钟；素音不能作为滑条阵营。
@export_enum("Zhu", "Xuan") var affinity: int = GameplayTypes.Affinity.ZHU

@export_group("Timing")
## 第一程起点的绝对谱面 tick。
@export var tick: int = 0
## 完成一程所需的 tick；总时长等于它乘以 traversal_count。
@export var traversal_ticks: int = 480
## 总共经过几程；1 为单程，2 为一次往返，之后每程继续折返。
@export_range(1, 32, 1) var traversal_count: int = 1

@export_group("Frequency Axis")
## 第一程起点在统一频率轴上的归一化位置，范围 0～1。
@export_range(0.0, 1.0, 0.001) var start_value: float = 0.0
## 第一程终点在统一频率轴上的归一化位置，范围 0～1；偶数程最终会回到 start_value。
@export_range(0.0, 1.0, 0.001) var end_value: float = 1.0

@export_group("Presentation")
## 0 使用频率跨度推导的原半径，正数覆盖绘制半径；不参与调频与判定。
@export var visual_radius_px: float = 0.0
## 将默认圆弧绕自身中心旋转的角度。0°保持原来的近横向上/下弧；
## 正值按屏幕坐标顺时针旋转，可用来制作斜向或近纵向滑条。
@export_range(-180.0, 180.0, 1.0) var arc_rotation_deg: float = 0.0
## 相对于本阵营默认安全锚点的画面偏移，单位为设计像素。
## 它只用于给连续滑条编排构图，不参与频率、判定或 Replay。
@export var visual_offset_px: Vector2 = Vector2.ZERO
