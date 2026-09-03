## 随从的身份、数值和两阶段美术资源配置。随从效果作用在结算侧，不改写原始节奏判定。
@tool
class_name PetDefinition
extends Resource

enum EffectKind {
	BONUS_SCORE,
	NONE,
}

## 随从效果类型；Bonus Score 只加结算奖励，None 表示纯收藏。
@export_enum("Bonus Score", "None") var effect_kind: int = EffectKind.NONE
## 随从稳定 ID；存档和奖励配置靠它识别，发布后不应随意改名。
@export var pet_id: String = ""
## 面向玩家显示的随从名称。
@export var display_name: String = ""
## 面向玩家显示的多行说明，可描述文化出处和效果。
@export_multiline var description: String = ""
## 普通形态的效果数值，范围 0～10；含义由 effect_kind 决定，越大加成越强。
@export_range(0.0, 10.0, 0.01) var base_effect_value: float = 0.0
## 进阶形态的效果数值，范围 0～10；越大加成越强，通常不低于普通形态。
@export_range(0.0, 10.0, 0.01) var advanced_effect_value: float = 0.0
## 普通形态在菜单与奖励弹窗使用的图标。
@export var base_icon: Texture2D
## 进阶形态在菜单与奖励弹窗使用的图标。
@export var advanced_icon: Texture2D
## 普通形态的关卡内可实例化场景。
@export var base_scene: PackedScene
## 进阶形态的关卡内可实例化场景。
@export var advanced_scene: PackedScene
