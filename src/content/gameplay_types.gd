## 全工程共用的玩法枚举和名称转换。集中定义可防止谱面、判定、输入与表现层各自发明不同编号。
class_name GameplayTypes
extends RefCounted

## 物理输入设备类别；只描述事件来源，不表达任何玩法语义。
enum PhysicalDeviceType {
	KEYBOARD,
	MOUSE,
	GAMEPAD,
	TOUCHSCREEN,
	SYSTEM,
	ENUM_MAX,
}

## 具体物理输入事件。按键按下/释放分别枚举，避免查询一个按键时误消费其他按键。
enum PhysicalInputKind {
	KEY_F_PRESSED,
	KEY_F_RELEASED,
	KEY_J_PRESSED,
	KEY_J_RELEASED,
	KEY_LEFT_PRESSED,
	KEY_LEFT_RELEASED,
	KEY_RIGHT_PRESSED,
	KEY_RIGHT_RELEASED,
	MOUSE_LEFT_PRESSED,
	MOUSE_LEFT_RELEASED,
	MOUSE_RIGHT_PRESSED,
	MOUSE_RIGHT_RELEASED,
	GAMEPAD_L1_PRESSED,
	GAMEPAD_L1_RELEASED,
	GAMEPAD_R1_PRESSED,
	GAMEPAD_R1_RELEASED,
	GAMEPAD_L3_PRESSED,
	GAMEPAD_L3_RELEASED,
	GAMEPAD_R3_PRESSED,
	GAMEPAD_R3_RELEASED,
	GAMEPAD_START_PRESSED,
	GAMEPAD_START_RELEASED,
	GAMEPAD_A_PRESSED,
	GAMEPAD_A_RELEASED,
	GAMEPAD_B_PRESSED,
	GAMEPAD_B_RELEASED,
	MOUSE_MOVED,
	GAMEPAD_LEFT_STICK_MOVED,
	GAMEPAD_RIGHT_STICK_MOVED,
	TOUCH_PRESSED,
	TOUCH_RELEASED,
	TOUCH_MOVED,
	FOCUS_CANCELLED,
	DEVICE_CONNECTED,
	DEVICE_DISCONNECTED,
	ENUM_MAX,
}

## 音符/输入阵营：朱对应生钟，玄对应死钟，素对应双钟调频产生的中性目标。
enum Affinity {
	ZHU,
	XUAN,
	SU,
}

## 普通音符形态：Tap 只需敲击，Hold 还需持续按住。
enum NoteKind {
	TAP,
	HOLD,
}

## 判定由优到劣的固定序值；数值越大越差，MISS 为失败档。
enum JudgmentGrade {
	PERFECT,
	GOOD,
	PASS,
	MISS,
}

## 同一口钟的两套设备无关操作通道。NONE 只用于尚未记录持续来源的状态。
enum BellInputChannel {
	NONE,
	A,
	B,
}

## 设备无关的语义输入；A/B 保留同功能不同按键的释放归属。
enum SemanticInputKind {
	LIFE_A_PRESSED = 0,
	LIFE_A_RELEASED = 1,
	LIFE_B_PRESSED = 2,
	LIFE_B_RELEASED = 3,
	DEATH_A_PRESSED = 4,
	DEATH_A_RELEASED = 5,
	DEATH_B_PRESSED = 6,
	DEATH_B_RELEASED = 7,
	## 摇杆旋转、触屏或鼠标拖动产生的相对调频位移。X=生钟，Y=死钟。
	TUNING_DISPLACED = 8,
	FOCUS_CANCELLED = 9,
	ENUM_MAX = 10,
}

## 一次输入最终归属的机制；优先级由模拟层规定为疾振、调频、普通音符。
enum InputOwner {
	NONE,
	NOTE,
	TUNING,
	RAPID,
}

## 关卡会话状态值；状态只能经 StageSession 的合法迁移边转换。
enum StageState {
	LOADING,
	READY,
	PREROLL,
	PLAYING,
	PAUSED,
	FINISHING,
	FAILING,
	RESULT,
}

## 与 JudgmentGrade 序值一一对应的稳定文本名，用于日志和 Replay 摘要。
const GRADE_NAMES: PackedStringArray = ["PERFECT", "GOOD", "PASS", "MISS"]
## 与 Affinity 序值一一对应的稳定文本名。
const AFFINITY_NAMES: PackedStringArray = ["ZHU", "XUAN", "SU"]


static func grade_name(grade: int) -> String:
	if grade < 0 or grade >= GRADE_NAMES.size():
		return "UNKNOWN"
	return GRADE_NAMES[grade]


static func affinity_name(affinity: int) -> String:
	if affinity < 0 or affinity >= AFFINITY_NAMES.size():
		return "UNKNOWN"
	return AFFINITY_NAMES[affinity]
