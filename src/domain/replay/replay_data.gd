class_name ReplayData
extends RefCounted

## 确定性 Replay 的数据包。保存语义输入及谱面、规则、歌曲和装备哈希，
## 不保存具体键码，因此同一记录可由不同设备映射复现。

## v2 把一条共享调频向量拆成固定的生/死双路速率或位移。
## v1 无法可靠判断旧向量属于哪口钟，因此加载入口会明确拒绝，不能猜测迁移。
const CURRENT_SCHEMA_VERSION: int = 2

## 此 Replay 采用的数据结构版本；必须等于 CURRENT_SCHEMA_VERSION 才能直接执行。
var schema_version: int = CURRENT_SCHEMA_VERSION
## 本次录制的稳定 ID；可由存档层用于区分多次成绩。
var replay_id: String = ""
## 录制时的 CompiledChart.content_hash；不一致说明谱面玩法内容已变化。
var chart_hash: String = ""
## 录制时 GameplayRuleSet 的规范哈希；判定窗等规则变化后应拒绝验证。
var rules_hash: String = ""
## 录制时歌曲首拍与变速时间基准的哈希；防止同谱事件整体错位。
var song_timing_hash: String = ""
## 录制时应用的输入延迟校准，单位微秒；重放时必须保持同一语义。
var captured_input_offset_us: int = 0
## 录制时装备组合的稳定哈希；用于追溯结算奖励，不应影响原始判定。
var loadout_hash: String = ""
## 录制所用游戏构建 ID；用于诊断跨版本差异。
var build_id: String = ""
## 设备无关的语义输入序列；执行前会按 timestamp_us、sequence 重新稳定排序。
var inputs: Array[SemanticInputSample] = []
## 可选的预期结果哈希；空值只运行不验证，非空时必须与实际 digest 相同。
var expected_result_digest: String = ""


static func compute_song_timing_hash(song_id: String, first_beat_offset_sec: float, chart_hash: String) -> String:
	## Runtime Replay 用这一身份确认“歌曲、首拍和谱面时间轴”仍是录制时的组合。
	return ("%s|%.9f|%s" % [song_id, first_beat_offset_sec, chart_hash]).sha256_text()


func sorted_inputs() -> Array[SemanticInputSample]:
	var result: Array[SemanticInputSample] = inputs.duplicate()
	result.sort_custom(SemanticInputSample.sort_samples)
	return result


func to_dictionary() -> Dictionary:
	var serialized_inputs: Array[Dictionary] = []
	for sample in sorted_inputs():
		serialized_inputs.append(sample.to_dictionary())
	return {
		"schema_version": schema_version,
		"replay_id": replay_id,
		"chart_hash": chart_hash,
		"rules_hash": rules_hash,
		"song_timing_hash": song_timing_hash,
		"captured_input_offset_us": captured_input_offset_us,
		"loadout_hash": loadout_hash,
		"build_id": build_id,
		"inputs": serialized_inputs,
		"expected_result_digest": expected_result_digest,
	}


static func from_dictionary(data: Dictionary) -> ReplayData:
	var replay := ReplayData.new()
	replay.schema_version = int(data.get("schema_version", 0))
	replay.replay_id = String(data.get("replay_id", ""))
	replay.chart_hash = String(data.get("chart_hash", ""))
	replay.rules_hash = String(data.get("rules_hash", ""))
	replay.song_timing_hash = String(data.get("song_timing_hash", ""))
	replay.captured_input_offset_us = int(data.get("captured_input_offset_us", 0))
	replay.loadout_hash = String(data.get("loadout_hash", ""))
	replay.build_id = String(data.get("build_id", ""))
	replay.expected_result_digest = String(data.get("expected_result_digest", ""))
	for sample_data in data.get("inputs", []):
		replay.inputs.append(SemanticInputSample.from_dictionary(sample_data))
	return replay


func canonical_input_hash() -> String:
	var lines := PackedStringArray([
		"ReplayInput:v%d" % schema_version,
		chart_hash,
		rules_hash,
		song_timing_hash,
		str(captured_input_offset_us),
		loadout_hash,
	])
	for sample in sorted_inputs():
		var data: Dictionary = sample.to_dictionary()
		lines.append("%d|%d|%d|%d|%d" % [
			data["timestamp_us"],
			data["sequence"],
			data["kind"],
			data["life_q15"],
			data["death_q15"],
		])
	return "\n".join(lines).sha256_text()
