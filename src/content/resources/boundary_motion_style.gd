@tool
class_name BoundaryMotionStyle
extends Resource
## 分层浪头的表现编排，不进入判定或 Replay 规则摘要。1920×1080 设计像素。
@export var enabled: bool = true
@export_range(80.0,110.0,1.0) var vortex_inner_radius_px: float = 88.0
@export_range(80.0,150.0,1.0) var vortex_width_px: float = 112.0
@export_range(0.0,1.0,0.05) var vortex_foam_strength: float = 0.65
@export_range(0.0,180.0,1.0) var vortex_flow_speed_px_sec: float = 96.0
@export_range(0.0,3.0,0.05) var vortex_beat_push_px: float = 1.25
@export var flow_enabled: bool = true
@export_range(0.0,100.0,1.0) var flow_speed_px_sec: float = 60.0
@export_range(0.0,1.0,0.05) var flow_strength: float = 0.80
@export_range(0.0,0.4,0.01) var streak_strength: float = 0.24
