class_name SemanticInputSample
extends RefCounted

## 与设备无关的玩法输入样本。它只记录语义、判定时间和稳定序号，
## 因而键鼠、手柄和 Replay 可以走同一条判定路径。

## Q15 正上限；双钟调频量会量化到有符号 16 位整数，保证 Replay 跨帧率、跨平台一致。
const Q15_MAX: int = 32767

## 输入发生在判定时间轴上的整数微秒时间戳。
var timestamp_us: int = 0
## 输入稳定顺序号；两个事件落在同一微秒时用它决定处理先后。
var sequence: int = 0
## 输入语义类型，例如生/死按下、松开或一次相对调频位移。
var kind: int = GameplayTypes.SemanticInputKind.LIFE_A_PRESSED
## 双钟调频输入。X 永远代表生钟，Y 永远代表死钟，两个分量各自处于 -1～1。
## 数值表示本次输入造成的归一化频率轴位移；非调频样本保持 Vector2.ZERO。
## 两路必须独立，禁止把它当二维方向向量归一化。
var tune_vector: Vector2 = Vector2.ZERO


static func create(p_timestamp_us: int, p_sequence: int, p_kind: int, p_tune_vector: Vector2 = Vector2.ZERO) -> SemanticInputSample:
	var sample := SemanticInputSample.new()
	sample.timestamp_us = p_timestamp_us
	sample.sequence = p_sequence
	sample.kind = p_kind
	# 生、死两路分别钳制和量化。不能使用 limit_length()：两根摇杆同时推满时，
	# (1, 1) 必须原样保留，不能被单位圆归一化成约 (0.707, 0.707)。
	sample.tune_vector = Vector2(
		_quantize_component(p_tune_vector.x),
		_quantize_component(p_tune_vector.y)
	)
	return sample


static func _quantize_component(value: float) -> float:
	return float(roundi(clampf(value, -1.0, 1.0) * Q15_MAX)) / float(Q15_MAX)


static func sort_samples(a: SemanticInputSample, b: SemanticInputSample) -> bool:
	if a.timestamp_us != b.timestamp_us:
		return a.timestamp_us < b.timestamp_us
	return a.sequence < b.sequence


func is_press() -> bool:
	return kind in [
		GameplayTypes.SemanticInputKind.LIFE_A_PRESSED,
		GameplayTypes.SemanticInputKind.LIFE_B_PRESSED,
		GameplayTypes.SemanticInputKind.DEATH_A_PRESSED,
		GameplayTypes.SemanticInputKind.DEATH_B_PRESSED,
	]


func is_release() -> bool:
	return kind in [
		GameplayTypes.SemanticInputKind.LIFE_A_RELEASED,
		GameplayTypes.SemanticInputKind.LIFE_B_RELEASED,
		GameplayTypes.SemanticInputKind.DEATH_A_RELEASED,
		GameplayTypes.SemanticInputKind.DEATH_B_RELEASED,
	]


func is_tuning() -> bool:
	return kind == GameplayTypes.SemanticInputKind.TUNING_DISPLACED


func affinity() -> int:
	if kind in [
		GameplayTypes.SemanticInputKind.LIFE_A_PRESSED,
		GameplayTypes.SemanticInputKind.LIFE_A_RELEASED,
		GameplayTypes.SemanticInputKind.LIFE_B_PRESSED,
		GameplayTypes.SemanticInputKind.LIFE_B_RELEASED,
	]:
		return GameplayTypes.Affinity.ZHU
	if kind in [
		GameplayTypes.SemanticInputKind.DEATH_A_PRESSED,
		GameplayTypes.SemanticInputKind.DEATH_A_RELEASED,
		GameplayTypes.SemanticInputKind.DEATH_B_PRESSED,
		GameplayTypes.SemanticInputKind.DEATH_B_RELEASED,
	]:
		return GameplayTypes.Affinity.XUAN
	return GameplayTypes.Affinity.SU


## 返回本次敲钟所属的 A/B 通道；非敲钟事件返回 NONE。
func input_channel() -> int:
	if kind in [
		GameplayTypes.SemanticInputKind.LIFE_A_PRESSED,
		GameplayTypes.SemanticInputKind.LIFE_A_RELEASED,
		GameplayTypes.SemanticInputKind.DEATH_A_PRESSED,
		GameplayTypes.SemanticInputKind.DEATH_A_RELEASED,
	]:
		return GameplayTypes.BellInputChannel.A
	if kind in [
		GameplayTypes.SemanticInputKind.LIFE_B_PRESSED,
		GameplayTypes.SemanticInputKind.LIFE_B_RELEASED,
		GameplayTypes.SemanticInputKind.DEATH_B_PRESSED,
		GameplayTypes.SemanticInputKind.DEATH_B_RELEASED,
	]:
		return GameplayTypes.BellInputChannel.B
	return GameplayTypes.BellInputChannel.NONE


## 返回按下事件唯一匹配的释放事件；非按下事件返回 -1。
func matching_release_kind() -> int:
	match kind:
		GameplayTypes.SemanticInputKind.LIFE_A_PRESSED:
			return GameplayTypes.SemanticInputKind.LIFE_A_RELEASED
		GameplayTypes.SemanticInputKind.LIFE_B_PRESSED:
			return GameplayTypes.SemanticInputKind.LIFE_B_RELEASED
		GameplayTypes.SemanticInputKind.DEATH_A_PRESSED:
			return GameplayTypes.SemanticInputKind.DEATH_A_RELEASED
		GameplayTypes.SemanticInputKind.DEATH_B_PRESSED:
			return GameplayTypes.SemanticInputKind.DEATH_B_RELEASED
	return -1


func to_dictionary() -> Dictionary:
	return {
		"timestamp_us": timestamp_us,
		"sequence": sequence,
		"kind": kind,
		"life_q15": roundi(clampf(tune_vector.x, -1.0, 1.0) * Q15_MAX),
		"death_q15": roundi(clampf(tune_vector.y, -1.0, 1.0) * Q15_MAX),
	}


static func from_dictionary(data: Dictionary) -> SemanticInputSample:
	var vector := Vector2(
		float(int(data.get("life_q15", 0))) / float(Q15_MAX),
		float(int(data.get("death_q15", 0))) / float(Q15_MAX)
	)
	return create(
		int(data.get("timestamp_us", 0)),
		int(data.get("sequence", 0)),
		int(data.get("kind", GameplayTypes.SemanticInputKind.LIFE_A_PRESSED)),
		vector
	)
