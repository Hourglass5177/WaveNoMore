class_name BoundaryMotion
extends RefCounted
## 正式背景和环境片段共用绝对歌曲时钟；片段局部时间不会重置浪卷。
const SHADER := preload("res://shaders/materials/boundary_motion.gdshader")
const DEFAULT_STYLE := preload("res://content/presentation/boundary_motion_style.tres")
var style: BoundaryMotionStyle = DEFAULT_STYLE.duplicate()
var tempo_map: TempoMap
var meters: Array[MeterEvent] = []
## 环境演出的 song 段使用音频位置，普通表现时钟已经扣掉此偏移。
var audio_offset_sec := 0.0

static func accepts(material: Material) -> bool:
	return material is ShaderMaterial and material.shader==SHADER

func apply(material: ShaderMaterial, scale: float) -> void:
	material.set_shader_parameter("motion_enabled",style.enabled)
	# 旧材质仅保留给对照样片；退休参数不再读取策划当前值。
	var legacy := {"period_sec":6.0,"stream_amplitude_px":3.0,"curl_amplitude_px":12.0,"beat_enabled":true,"beat_amplitude_px":1.2}
	for key in legacy: material.set_shader_parameter(key,legacy[key])
	material.set_shader_parameter("design_scale",scale)

func beat_at(seconds: float) -> float:
	if tempo_map==null: return seconds*2.0
	var tick:=tempo_map.us_to_tick(roundi(seconds*1000000.0))
	# 与写谱器节拍器一致：拍号分母确定每拍 tick，换拍号从该事件重新起拍。
	var meter_tick:=0
	var denominator:=4
	for meter in meters:
		if meter.tick>tick: break
		meter_tick=meter.tick; denominator=meter.denominator
	return (tick-meter_tick)/(tempo_map.ppq*4.0/denominator)

static func sample(material: ShaderMaterial, seconds: float, beat: float) -> void:
	material.set_shader_parameter("boundary_time",seconds)
	material.set_shader_parameter("boundary_beat",beat)

func continuous_beat_at(seconds: float) -> float:
	if tempo_map==null: return seconds*2.0
	var tick:=tempo_map.us_to_tick(roundi(seconds*1000000.0))
	var previous_tick:=0.0
	var denominator:=4
	var total:=0.0
	# 换拍号只改变此后的拍长；累计拍位不归零，水纹不能倒退或跳动。
	for meter in meters:
		if meter.tick>tick: break
		total+=(meter.tick-previous_tick)*denominator/(tempo_map.ppq*4.0)
		previous_tick=meter.tick
		denominator=meter.denominator
	return total+(tick-previous_tick)*denominator/(tempo_map.ppq*4.0)

func vortex_distance_at(seconds: float) -> float:
	var beat:=continuous_beat_at(seconds)
	var x:=clampf(fposmod(beat,1.0)/.4,0.0,1.0)
	# 拍点柔和加速后回到恒速；位移和速度在拍边界都连续。
	var pulse:=floorf(beat)+x-sin(TAU*x)/TAU
	return seconds*style.vortex_flow_speed_px_sec+pulse*style.vortex_beat_push_px
