## 关卡背景配置，空数组表示不添加视差素材。只保存美术数据。
@tool
class_name StageBackgroundDefinition
extends Resource

## 每个有符号深度对应一个顶层；顶层只包含子层，素材只属于子层。
@export var layers: Array[StageBackgroundLayer] = []
