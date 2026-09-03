## 单关结算奖励配置，负责串联下一关以及 FC/AP 对随从普通、进阶形态的授予规则。
@tool
class_name RewardDefinition
extends Resource

## 奖励配置的稳定 ID，供存档记录是否已发放。
@export var reward_id: String = ""
## 通关后解锁的下一关 stage_id；空值表示不串联下一关。
@export var next_stage_id: String = ""
## 本关可获得的随从；为空表示本关没有随从奖励。
@export var pet: PetDefinition
## 开启时，Full Combo 授予随从普通形态。
@export var fc_grants_base_pet: bool = true
## 开启时，All Perfect 授予随从进阶形态。
@export var ap_grants_advanced_pet: bool = true
