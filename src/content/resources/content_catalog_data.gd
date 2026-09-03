## 游戏内容总目录的字段约定。运行时先读这份轻量目录，再按 StageDefinition 的路径加载具体关卡。
@tool
class_name ContentCatalogData
extends Resource

## 内容目录格式版本；数值只随数据结构迁移递增，不代表游戏版本。
@export var catalog_version: int = 1
## 已登记关卡列表；顺序可由 StageDefinition.order_index 再排序。
@export var stages: Array[StageDefinition] = []
## 已登记随从列表；菜单和存档只应引用这里存在的稳定 pet_id。
@export var pets: Array[PetDefinition] = []
## 关卡未单独指定规则时使用的共享默认规则；为空会导致关卡依赖不完整。
@export var default_rule_set: GameplayRuleSet
