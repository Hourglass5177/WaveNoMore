@tool
class_name BoundaryMotionStyle
extends Resource
## 分层浪头的表现编排，不进入判定或 Replay 规则摘要。1920×1080 设计像素。
@export var enabled: bool = true
@export_range(1,4,1) var bar_interval: int = 1
@export_range(100.0,190.0,1.0) var wave_height_px: float = 165.0
@export_range(100.0,240.0,1.0) var advance_px: float = 190.0
@export_range(70.0,110.0,1.0) var curl_travel_px: float = 90.0
@export_range(0.0,1.0,0.05) var foam_strength: float = 0.9
@export var flow_enabled: bool = true
@export_range(0.0,100.0,1.0) var flow_speed_px_sec: float = 60.0
@export_range(0.0,1.0,0.05) var flow_strength: float = 0.80
@export_range(0.0,0.4,0.01) var streak_strength: float = 0.24
