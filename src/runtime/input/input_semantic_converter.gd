class_name InputSemanticConverter
extends RefCounted

## 无状态的物理输入转换层。只读取传入事件并返回语义字典，不访问缓冲区。

enum GameplayEvent {
	LIFE_A_PRESSED,
	LIFE_A_RELEASED,
	LIFE_B_PRESSED,
	LIFE_B_RELEASED,
	DEATH_A_PRESSED,
	DEATH_A_RELEASED,
	DEATH_B_PRESSED,
	DEATH_B_RELEASED,
	TUNING_DISPLACED,
	LIFE_TUNING_DISPLACED,
	DEATH_TUNING_DISPLACED,
	INPUT_CANCELLED,
	ENUM_MAX,
}

enum StickSide { LEFT, RIGHT }

static func to_tuning_control(event: PhysicalInputEvent) -> Dictionary:
	## 设计画布方向的无量纲速度控制；0.2 死区外线性重映射，不保存设备状态。
	if event == null or event.kind not in [
		GameplayTypes.PhysicalInputKind.GAMEPAD_LEFT_STICK_MOVED,
		GameplayTypes.PhysicalInputKind.GAMEPAD_RIGHT_STICK_MOVED
	]:
		return {"exists": false, "timestamp_us": -1}
	var raw_vector: Vector2 = event.axis_value
	var side: int = StickSide.LEFT if event.kind == GameplayTypes.PhysicalInputKind.GAMEPAD_LEFT_STICK_MOVED else StickSide.RIGHT
	var control_vector := Vector2.ZERO
	var radius: float = raw_vector.length()
	if radius > 0.2:
		control_vector = raw_vector / radius * clampf((radius - 0.2) / 0.8, 0.0, 1.0)
	return {
		"exists": true,
		"timestamp_us": event.timestamp_us,
		"stick_side": side,
		"raw_vector": raw_vector,
		"control_vector": control_vector,
	}

static func to_gameplay(event: PhysicalInputEvent) -> Dictionary:
	if event == null:
		return {"exists": false, "event": null}
	var kind := -1
	match event.kind:
		GameplayTypes.PhysicalInputKind.KEY_J_PRESSED, GameplayTypes.PhysicalInputKind.MOUSE_RIGHT_PRESSED, GameplayTypes.PhysicalInputKind.GAMEPAD_R1_PRESSED:
			kind = GameplayEvent.LIFE_A_PRESSED
		GameplayTypes.PhysicalInputKind.KEY_J_RELEASED, GameplayTypes.PhysicalInputKind.MOUSE_RIGHT_RELEASED, GameplayTypes.PhysicalInputKind.GAMEPAD_R1_RELEASED:
			kind = GameplayEvent.LIFE_A_RELEASED
		GameplayTypes.PhysicalInputKind.KEY_RIGHT_PRESSED, GameplayTypes.PhysicalInputKind.GAMEPAD_R3_PRESSED:
			kind = GameplayEvent.LIFE_B_PRESSED
		GameplayTypes.PhysicalInputKind.KEY_RIGHT_RELEASED, GameplayTypes.PhysicalInputKind.GAMEPAD_R3_RELEASED:
			kind = GameplayEvent.LIFE_B_RELEASED
		GameplayTypes.PhysicalInputKind.KEY_F_PRESSED, GameplayTypes.PhysicalInputKind.MOUSE_LEFT_PRESSED, GameplayTypes.PhysicalInputKind.GAMEPAD_L1_PRESSED:
			kind = GameplayEvent.DEATH_A_PRESSED
		GameplayTypes.PhysicalInputKind.KEY_F_RELEASED, GameplayTypes.PhysicalInputKind.MOUSE_LEFT_RELEASED, GameplayTypes.PhysicalInputKind.GAMEPAD_L1_RELEASED:
			kind = GameplayEvent.DEATH_A_RELEASED
		GameplayTypes.PhysicalInputKind.KEY_LEFT_PRESSED, GameplayTypes.PhysicalInputKind.GAMEPAD_L3_PRESSED:
			kind = GameplayEvent.DEATH_B_PRESSED
		GameplayTypes.PhysicalInputKind.KEY_LEFT_RELEASED, GameplayTypes.PhysicalInputKind.GAMEPAD_L3_RELEASED:
			kind = GameplayEvent.DEATH_B_RELEASED
		GameplayTypes.PhysicalInputKind.GAMEPAD_RIGHT_STICK_MOVED:
			kind = GameplayEvent.LIFE_TUNING_DISPLACED
		GameplayTypes.PhysicalInputKind.GAMEPAD_LEFT_STICK_MOVED:
			kind = GameplayEvent.DEATH_TUNING_DISPLACED
		GameplayTypes.PhysicalInputKind.MOUSE_MOVED, GameplayTypes.PhysicalInputKind.TOUCH_MOVED:
			kind = GameplayEvent.TUNING_DISPLACED
		GameplayTypes.PhysicalInputKind.FOCUS_CANCELLED, GameplayTypes.PhysicalInputKind.DEVICE_DISCONNECTED:
			kind = GameplayEvent.INPUT_CANCELLED
	if kind < 0:
		return {"exists": false, "event": null}
	return {"exists": true, "event": {"kind": kind, "source_event": event}}

static func to_ui(event: PhysicalInputEvent) -> Dictionary:
	if event == null:
		return {"exists": false, "event": null}
	var kind := -1
	match event.kind:
		GameplayTypes.PhysicalInputKind.KEY_F_PRESSED, GameplayTypes.PhysicalInputKind.KEY_J_PRESSED, GameplayTypes.PhysicalInputKind.MOUSE_LEFT_PRESSED, GameplayTypes.PhysicalInputKind.MOUSE_RIGHT_PRESSED, GameplayTypes.PhysicalInputKind.GAMEPAD_A_PRESSED:
			kind = 0
		GameplayTypes.PhysicalInputKind.GAMEPAD_B_PRESSED, GameplayTypes.PhysicalInputKind.FOCUS_CANCELLED:
			kind = 1
		GameplayTypes.PhysicalInputKind.GAMEPAD_START_PRESSED:
			kind = 2
	if kind < 0:
		return {"exists": false, "event": null}
	return {"exists": true, "event": {"kind": kind, "source_event": event}}

static func to_editor(event: PhysicalInputEvent) -> Dictionary:
	return to_gameplay(event)
