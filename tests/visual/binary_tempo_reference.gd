extends TempoMap
## 原二分反算，供精度回归逐值对照。
func us_to_tick(time_us: int) -> float:
	# 用二分搜索取得相邻整数 tick，再在区间内插值；整个反算不依赖帧 delta。
	var target_us: int = time_us
	var low: int = -1
	var high: int = 1
	while tick_to_us(low) > target_us:
		high = low
		low *= 2
	while tick_to_us(high) < target_us:
		low = high
		high *= 2
	for _iteration in range(64):
		if high - low <= 1:
			break
		var middle: int = low + (high - low) / 2
		if tick_to_us(middle) <= target_us:
			low = middle
		else:
			high = middle
	var low_us: int = tick_to_us(low)
	var high_us: int = tick_to_us(high)
	if high_us == low_us:
		return float(low)
	return float(low) + float(target_us - low_us) / float(high_us - low_us)
