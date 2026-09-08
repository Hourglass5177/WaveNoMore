## 普通 Tap/Hold 音符的制谱数据；这里只描述「是什么、何时发生」，不保存运行时判定状态。
@tool
class_name NoteEvent
extends Resource

@export_group("Identity")
## 全谱唯一的稳定 ID；编辑器、Replay 和运行时都靠它定位此音符，不能随意重用。
@export var event_id: String = ""
## 同组音符构成双押等逻辑组合；空字符串表示不分组。
@export var group_id: String = ""
## 共用一次扣血资格的组 ID；相同值的多个 MISS 只伤害一次，空值会由编译器回退到事件 ID。
@export var damage_group_id: String = ""
## 来源标记；当前仅供写谱器编排，正式计分与表现暂不读取。
@export var boss: bool = false

@export_group("Timing")
## 音符头的绝对谱面 tick；数值越大，出现时间越晚。
@export var tick: int = 0
## 从音符头到尾的 tick 数；Tap 必须为 0，Hold 数值越大持续越久。
@export var duration_ticks: int = 0

@export_group("Semantics")
## 音符类型：Tap 只判头，Hold 判头部与持续过程，到达尾点后自动完成。
@export_enum("Tap", "Hold") var kind: int = GameplayTypes.NoteKind.TAP
## 所属阵营：Zhu 使用生钟输入，Xuan 使用死钟输入。
@export_enum("Zhu", "Xuan") var affinity: int = GameplayTypes.Affinity.ZHU
## 已弃用：仅为旧谱资源保留序列化兼容，运行时不再读取，Hold 尾点也不要求松键。
@export var tail_requires_release: bool = false

@export_group("Presentation")
## 美术变体键；仅改变外观，不得改变判定含义。
@export var visual_variant: StringName = &"default"
