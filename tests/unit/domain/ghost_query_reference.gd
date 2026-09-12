extends RefCounted
## 优化前全量求交与排序，用于结果逐点对照；不进入游戏导出。

static func query(engine: CarrierWaveEngine,
		time_us: int,
		normalized_region: Rect2,
		count: int,
		minimum_spacing_px: float = 120.0,
		selection_seed: int = 0,
		freeze_when_complete: bool = false
) -> Array[Vector2]:
	## 素音只受谱面显式区域约束，包含四条边界；HUD 和波源不构成隐藏禁区。
	if count <= 0: return []
	var life_fronts: Array[Dictionary] = []
	var death_fronts: Array[Dictionary] = []
	for front: Dictionary in visible_wavefronts(engine, time_us):
		if int(front["affinity"]) == GameplayTypes.Affinity.ZHU:
			life_fronts.append(front)
		elif int(front["affinity"]) == GameplayTypes.Affinity.XUAN:
			death_fronts.append(front)

	var allowed := Rect2(
		Vector2(normalized_region.position.x * engine._canvas_size.x, normalized_region.position.y * engine._canvas_size.y),
		Vector2(normalized_region.size.x * engine._canvas_size.x, normalized_region.size.y * engine._canvas_size.y)
	)
	var center: Vector2 = allowed.get_center()
	var candidates: Array[Dictionary] = []
	for life: Dictionary in life_fronts:
		for death: Dictionary in death_fronts:
			for point: Vector2 in engine._circle_intersections(
				life["origin"], float(life["radius_px"]),
				death["origin"], float(death["radius_px"])
			):
				# Rect2.has_point 不包含右边和下边，因此显式比较闭区间。
				# 不钳制坐标：屏幕外或谱面区域外的真实交点仍然拒绝。
				if (
					point.x < allowed.position.x or point.x > allowed.end.x
					or point.y < allowed.position.y or point.y > allowed.end.y
				):
					continue
				candidates.append({
					"point": point,
					"distance_to_center": point.distance_squared_to(center),
					"life_id": str(life["wave_id"]),
					"death_id": str(death["wave_id"]),
					"available_us": maxi(int(life["launch_us"]), int(death["launch_us"])),
				})
	candidates.sort_custom(engine._sort_intersection_candidates)

	# 按载波发射批次建立互不重叠的候选池，不能找到 count 个就立即停止遍历。
	# 预读取最早足量的完整发射批次：即使一帧跨过多次发波，冻结池仍然相同。
	var pool: Array[Vector2] = []
	var batch_us := CarrierWaveEngine.NEVER_TIME_US
	for candidate: Dictionary in candidates:
		var available_us: int = candidate["available_us"]
		if freeze_when_complete and pool.size() >= count and available_us != batch_us: break
		batch_us = available_us
		var point: Vector2 = candidate["point"]
		var spaced: bool = true
		for existing: Vector2 in pool:
			if point.distance_squared_to(existing) < minimum_spacing_px * minimum_spacing_px:
				spaced = false
				break
		if not spaced:
			continue
		pool.append(point)
	# 每个事件使用独立种子，不消耗全局 RNG；定位和 Replay 不会受其他随机效果影响。
	var rng := RandomNumberGenerator.new()
	rng.seed = selection_seed
	var selected: Array[Vector2] = []
	for index in mini(count, pool.size()):
		var picked := rng.randi_range(index, pool.size() - 1)
		var point := pool[picked]
		pool[picked] = pool[index]
		pool[index] = point
		selected.append(point)
	return selected


static func visible_wavefronts(engine: CarrierWaveEngine, time_us: int) -> Array[Dictionary]:
	# 保留原始全历史扫描，连同时间范围检索一起对照。
	var result: Array[Dictionary] = []
	for emission: Dictionary in engine._history:
		var age_us: int = time_us - int(emission["launch_us"])
		if age_us < 0: continue
		var radius: float = float(age_us) / CarrierWaveEngine.USEC_PER_SEC * float(emission["speed_px_sec"])
		if radius > engine._canvas_size.length() * 1.15: continue
		var front: Dictionary = emission.duplicate(true)
		front["radius_px"] = radius
		result.append(front)
	return result
