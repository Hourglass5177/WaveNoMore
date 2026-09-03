class_name StrayInputRecord
extends RefCounted

## 没有被任何玩法机制消费的按下事件。是否断 Combo 或扣血由规则决定；
## 松键不产生乱按记录。

## 乱按在全局输入序列中的稳定编号，用于 Replay 保持确定顺序。
var sequence: int = 0
## 乱按发生在判定时间轴上的时刻，单位为整数微秒。
var timestamp_us: int = 0
## 乱按来自生钟、死钟还是素输入，使用 GameplayTypes.Affinity 枚举。
var affinity: int = GameplayTypes.Affinity.SU
## 这次乱按是否中断 Combo；取值在记录创建时从 GameplayRuleSet 固化。
var breaks_combo: bool = true
## 这次乱按是否扣除魂火；取值同样由规则表决定。
var damages: bool = false


static func create(sample: SemanticInputSample, rules: GameplayRuleSet) -> StrayInputRecord:
	var record := StrayInputRecord.new()
	record.sequence = sample.sequence
	record.timestamp_us = sample.timestamp_us
	record.affinity = sample.affinity()
	record.breaks_combo = rules.stray_input_breaks_combo
	record.damages = rules.stray_input_damages
	return record


func to_dictionary() -> Dictionary:
	return {
		"sequence": sequence,
		"timestamp_us": timestamp_us,
		"affinity": affinity,
		"breaks_combo": breaks_combo,
		"damages": damages,
	}


func canonical_line() -> String:
	return "%d|%d|%d|%d|%d" % [sequence, timestamp_us, affinity, int(breaks_combo), int(damages)]
