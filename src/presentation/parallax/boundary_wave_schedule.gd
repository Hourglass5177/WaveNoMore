class_name BoundaryWaveSchedule
extends RefCounted
## 小浪仍按拍出生，直接恢复最近三道；中央常驻水臂由连续路程驱动。
var motion: BoundaryMotion
var _segments: Array[Dictionary] = []
var _meter_key: Array = []

func _init(driver: BoundaryMotion) -> void:
	motion=driver

func sample(seconds: float) -> Dictionary:
	var quarter:=seconds*2.0
	if motion.tempo_map!=null:
		quarter=motion.tempo_map.us_to_tick(roundi(seconds*1000000.0))/motion.tempo_map.ppq
	var meter_key: Array=[motion.tempo_map.ppq if motion.tempo_map!=null else 480]
	for meter in motion.meters:meter_key.append(Vector3(meter.tick,meter.numerator,meter.denominator))
	if meter_key!=_meter_key:
		_meter_key=meter_key
		_segments=[{"start":0.0,"step":1.0}]
		for meter in motion.meters:
			var part:={"start":float(meter.tick)/motion.tempo_map.ppq,"step":4.0/meter.denominator}
			if is_zero_approx(part.start):_segments[0]=part
			else:_segments.append(part)
	var small: Array[Dictionary]=[]
	for i in _segments.size():
		var part:=_segments[i]
		var end:=float(_segments[i+1].start) if i+1<_segments.size() else INF
		var beat:=floori((quarter-part.start)/part.step)
		for n in range(beat-2,beat+1):
			var birth:float=part.start+n*part.step
			if (i>0 and birth<part.start) or birth>=end:continue
			var age:float=(quarter-birth)/part.step
			if age>=0.0 and age<3.0:
				small.append({"id":"%d:%d"%[i,n],"phase":age/3.0,"region":posmod(n,3),"birth":birth})
	small.sort_custom(func(a,b):return a.birth>b.birth)
	if small.size()>3:small.resize(3)
	return {"quarter":quarter,"small":small}
