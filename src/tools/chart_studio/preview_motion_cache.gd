extends RefCounted
## 身体恢复样本不含节点、不落盘；修改边界后的样本统一失效。
const LIMIT_BYTES := 64 * 1024 * 1024
const INTERVAL_US := 500000
var entries := {}
var bytes := 0
var hits := 0
var _stamp := 0

func clear() -> void:
	entries.clear(); bytes = 0; hits = 0

func put(id: String, at: int, state: Dictionary) -> void:
	var key := "%s/%d" % [id, at]
	if entries.has(key): return
	var size := var_to_bytes(state).size()
	_stamp += 1
	entries[key] = {"id": id, "at": at, "state": state, "bytes": size, "stamp": _stamp}
	bytes += size
	while bytes > LIMIT_BYTES and not entries.is_empty():
		var oldest: String = entries.keys()[0]
		for candidate: String in entries:
			if entries[candidate].stamp < entries[oldest].stamp: oldest = candidate
		bytes -= int(entries[oldest].bytes); entries.erase(oldest)

func before(id: String, at: int) -> Dictionary:
	var found := {}
	for value: Dictionary in entries.values():
		if value.id == id and value.at <= at and (found.is_empty() or value.at > found.at): found = value
	if found.is_empty(): return {}
	_stamp += 1; found.stamp = _stamp; hits += 1
	return {"at": found.at, "state": found.state.duplicate(true)}

func invalidate_from(at: int) -> void:
	for key: String in entries.keys():
		if entries[key].at >= at:
			bytes -= int(entries[key].bytes); entries.erase(key)
