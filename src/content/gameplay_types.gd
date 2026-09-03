## 全工程共用的玩法枚举和名称转换。集中定义可防止谱面、判定、输入与表现层各自发明不同编号。
class_name GameplayTypes
extends RefCounted

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

## 设备无关的语义输入；鼠标、键盘和手柄都先转换成这些事件。
enum SemanticInputKind {
	LIFE_PRESSED,
	LIFE_RELEASED,
	DEATH_PRESSED,
	DEATH_RELEASED,
	## 手柄两根摇杆各自给出的移动速率；数值是方向/力度，不是频率绝对位置。
	TUNING_RATE_CHANGED,
	## 触屏或鼠标拖动产生的相对位移；两路分量必须分别钳制，不能按二维长度归一化。
	TUNING_DISPLACED,
	FOCUS_CANCELLED,
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
