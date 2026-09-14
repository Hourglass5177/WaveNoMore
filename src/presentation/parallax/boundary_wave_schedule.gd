class_name BoundaryWaveSchedule
extends RefCounted
## 由谱面绝对拍位直接列举可见浪。拍号段决定出生点，既有浪按出生段长度收尾。
var motion: BoundaryMotion

func _init(driver: BoundaryMotion) -> void:
	motion = driver

func sample(seconds: float) -> Dictionary:
	var quarter := seconds * 2.0
	if motion.tempo_map != null:
		quarter = motion.tempo_map.us_to_tick(roundi(seconds * 1000000.0)) / motion.tempo_map.ppq
	var segments: Array[Dictionary] = [{"start":0.0,"step":1.0,"count":4}]
	for meter in motion.meters:
		var start := float(meter.tick) / motion.tempo_map.ppq
		var segment := {"start":start,"step":4.0 / meter.denominator,"count":meter.numerator}
		if is_zero_approx(start): segments[0] = segment
		else: segments.append(segment)
	var large: Array[Dictionary] = []
	var small: Array[Dictionary] = []
	for i in segments.size():
		var part := segments[i]
		var end := float(segments[i+1].start) if i+1 < segments.size() else INF
		var length: float = part.step * part.count
		var interval: float = length * motion.style.bar_interval
		var near := floori((quarter - part.start) / interval)
		for n in range(near-2, near+3):
			var crash: float = part.start + n * interval
			if (i > 0 and crash < part.start) or crash >= end: continue
			var phase := (quarter - crash + 1.5 * length) / (2.0 * length)
			if phase >= 0.0 and phase < 1.0:
				large.append({"id":"%d:%d" % [i,n],"phase":phase,"crash":crash,"length":length})
		var beat := floori((quarter - part.start) / part.step)
		for n in range(beat-2,beat+1):
			var birth: float = part.start + n * part.step
			if (i > 0 and birth < part.start) or birth >= end: continue
			var age: float = (quarter - birth) / part.step
			if age >= 0.0 and age < 3.0:
				small.append({"id":"%d:%d" % [i,n],"phase":age/3.0,"region":posmod(n,3),"birth":birth})
	large.sort_custom(func(a,b): return a.crash < b.crash)
	small.sort_custom(func(a,b): return a.birth > b.birth)
	# 换拍号时优先保留正在拍落的前浪和最近的接替浪，数量不会短时膨胀。
	if large.size() > 2: large.resize(2)
	if small.size() > 3: small.resize(3)
	return {"quarter":quarter,"large":large,"small":small}
