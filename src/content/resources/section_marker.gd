## 谱师使用的段落标记。它帮助定位教学和歌曲结构，本身不是可判定音符。
@tool
class_name SectionMarker
extends Resource

## 全谱唯一的段落标记 ID，供编辑器和演出工具稳定引用。
@export var event_id: String = ""
## 段落起点的绝对谱面 tick；数值越大，段落越靠后。
@export var tick: int = 0
## 谱师可读的段落名称，只用于编辑和显示。
@export var label: String = ""
## 可选的教学内容键；空值表示进入此段时不触发教学。
@export var tutorial_key: StringName = &""
