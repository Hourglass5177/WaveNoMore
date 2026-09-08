class_name DamageRecord
extends RefCounted
## 实际受击事实，与得分等级分开。时间来自领域时间线，画面只消费结果。
var source_id: String = ""
var group_id: String = ""
var timestamp_us: int = 0
var base_damage: int = 0
var actual_damage: int = 0

static func create(source: String, group: String, time_us: int, amount: int) -> DamageRecord:
	var record := DamageRecord.new()
	record.source_id = source
	record.group_id = group if not group.is_empty() else source
	record.timestamp_us = time_us
	record.base_damage = amount
	return record

func to_dictionary() -> Dictionary:
	return {"source_id": source_id, "group_id": group_id, "timestamp_us": timestamp_us,
		"base_damage": base_damage, "actual_damage": actual_damage}
