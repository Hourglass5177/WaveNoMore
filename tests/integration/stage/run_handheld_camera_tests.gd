extends SceneTree
## 验证随机镜头的绝对时间恢复、平滑性、位移强度和种子控制。
var failures := 0

func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		print("FAIL ", label)

func _initialize() -> void:
	var driver := ParallaxHandheldDriver.new()
	check(driver.offset_at(0) == Vector2.ZERO and driver.offset_at(-1) == Vector2.ZERO, "开场原点")
	var saved := driver.offset_at(12.75)
	driver.offset_at(300)
	check(driver.offset_at(12.75) == saved, "跳转和重复采样不改变轨迹")
	var other := ParallaxHandheldDriver.new()
	check(other.offset_at(12.75) == saved, "游戏和预览一致")
	other.noise_seed += 1
	check(other.offset_at(12.75).distance_to(saved) > 1, "不同种子改变轨迹")
	var peak := Vector2.ZERO
	var max_step := 0.0
	var previous := Vector2.ZERO
	var repeated_error := 0.0
	for frame in 3600:
		var time := float(frame) / 60.0
		var sample := driver.offset_at(time)
		peak = peak.max(sample.abs())
		max_step = maxf(max_step, sample.distance_to(previous))
		repeated_error += sample.distance_to(driver.offset_at(time + driver.base_period_sec))
		check(sample.is_finite(), "有效位移")
		previous = sample
	check(peak.x > 25 and peak.y > 18, "足够明显的二维位移")
	check(max_step < 2.5, "保留大位移但限制每帧变化，避免急促晃动")
	check(repeated_error / 3600 > 10, "基准周期不重复")
	print("HANDHELD: peak=%s max_step=%.2f failures=%d" % [peak, max_step, failures])
	quit(1 if failures else 0)
