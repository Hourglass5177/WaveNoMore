## 关卡背景配置，空数组表示不添加视差素材。只保存美术数据。
@tool
class_name StageBackgroundDefinition
extends Resource

## 按数组顺序注册，同深度后面的条目覆盖前面的条目。
@export var entries: Array[StageBackgroundEntry] = []
