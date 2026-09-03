## StageShow 中的一条演出指令。cue_id 表示动作，target_slot 表示作用位置，parameters 携带可扩展参数。
@tool
class_name ShowCue
extends Resource

## 全演出轨唯一的稳定 ID，便于编辑器定位和迁移。
@export var event_id: String = ""
## 指令开始的绝对谱面 tick；数值越大，触发越晚。
@export var tick: int = 0
## 指令持续 tick 数；0 表示瞬时指令，数值越大持续越久。
@export var duration_ticks: int = 0
## 指令所属演出轨，决定由角色、世界、镜头、特效、音频或教学适配器接收。
@export_enum("Actor", "World", "Camera", "VFX", "Audio", "Tutorial") var track: int = 0
## 具体动作键，例如播放哪个动作；由对应演出适配器解释。
@export var cue_id: StringName = &""
## 作用对象槽位；同一 cue 可用不同槽位指向不同角色或场景节点。
@export var target_slot: StringName = &""
## 动作的扩展参数；键和值由 cue_id 的执行方约定，不可参与玩法判定。
@export var parameters: Dictionary = {}
