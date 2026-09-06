class_name PhysicalInputEvent
extends RefCounted

const _GAMEPLAY_TYPES: Script = preload("res://src/content/gameplay_types.gd")

## 输入缓冲中的底层事件。它保留设备和具体按键信息，不表达 Gameplay/UI 语义。
var timestamp_us: int = 0
var sequence: int = 0
var kind: int = _GAMEPLAY_TYPES.PhysicalInputKind.KEY_F_PRESSED
var device_type: int = _GAMEPLAY_TYPES.PhysicalDeviceType.SYSTEM
var device_id: int = -1
var code: int = 0
var axis_value: Vector2 = Vector2.ZERO
var position: Vector2 = Vector2.ZERO
var relative: Vector2 = Vector2.ZERO
var touch_id: int = -1
var cancel_reason: int = 0


static func create(
		p_timestamp_us: int,
		p_sequence: int,
		p_kind: int,
		p_device_type: int,
		p_device_id: int = -1,
		p_code: int = 0,
		p_axis_value: Vector2 = Vector2.ZERO,
		p_position: Vector2 = Vector2.ZERO,
		p_relative: Vector2 = Vector2.ZERO,
		p_touch_id: int = -1,
		p_cancel_reason: int = 0
) -> PhysicalInputEvent:
	var event := PhysicalInputEvent.new()
	event.timestamp_us = p_timestamp_us
	event.sequence = p_sequence
	event.kind = p_kind
	event.device_type = p_device_type
	event.device_id = p_device_id
	event.code = p_code
	event.axis_value = p_axis_value
	event.position = p_position
	event.relative = p_relative
	event.touch_id = p_touch_id
	event.cancel_reason = p_cancel_reason
	return event


static func sort_events(a: PhysicalInputEvent, b: PhysicalInputEvent) -> bool:
	if a.timestamp_us != b.timestamp_us:
		return a.timestamp_us < b.timestamp_us
	return a.sequence < b.sequence
