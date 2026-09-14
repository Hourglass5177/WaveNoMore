@tool
class_name BoundaryMotionStyle
extends Resource
## 仅驱动原画形变，不进入判定或 Replay 规则摘要。幅度为 1920×1080 设计像素。
@export var enabled: bool = true
@export_range(3.0,12.0,0.1) var period_sec: float = 6.0
@export_range(0.0,6.0,0.1) var stream_amplitude_px: float = 3.0
@export_range(0.0,16.0,0.5) var curl_amplitude_px: float = 12.0
@export var beat_enabled: bool = true
@export_range(0.0,2.0,0.1) var beat_amplitude_px: float = 1.2
