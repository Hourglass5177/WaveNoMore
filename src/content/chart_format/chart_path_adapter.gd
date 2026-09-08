class_name ChartPathAdapter
extends RefCounted
## 集中的过渡适配：角度编排 -> 当前频率滑条。只生成临时资源，不修改判定规则。
const BASE_ANGLE := -0.5123894603107377 # atan2(-540, 960)，固定设计画布的右上射线。

static func angle_limits(side: int, rules: GameplayRuleSet) -> Vector2:
	# 生钟使用角色连线的右上半圆，死钟使用左下半圆；返回连续角区间以跨越 ±180°。
	var divider := (rules.death_wave_origin - rules.life_wave_origin).angle()
	var boundary := rad_to_deg(wrapf(divider - BASE_ANGLE, -PI, PI))
	return Vector2(boundary - 180.0, boundary) if side == 0 else Vector2(boundary, boundary + 180.0)

static func unwrap_angle(value: float, side: int, rules: GameplayRuleSet) -> float:
	var limits := angle_limits(side, rules)
	var center := (limits.x + limits.y) * 0.5
	return center + wrapf(value - center, -180.0, 180.0)

static func clamp_angle(value: float, side: int, rules: GameplayRuleSet) -> float:
	var limits := angle_limits(side, rules)
	return clampf(unwrap_angle(value, side, rules), limits.x, limits.y)

static func angle_allowed(value: float, side: int, rules: GameplayRuleSet) -> bool:
	if not is_finite(value): return false
	var limits := angle_limits(side, rules)
	var angle := unwrap_angle(value, side, rules)
	return angle >= limits.x - 0.000001 and angle <= limits.y + 0.000001

static func frequency_values(path: TuningPathEvent, rules: GameplayRuleSet) -> Dictionary:
	if path.points.size() < 2: return {"error": "Tuning 至少需要两个节点"}
	var distance := TuningArcGeometry.equivalent_center_distance_px(rules.wave_canvas_size.x)
	var scale := (rules.tuning_max_frequency_hz - rules.tuning_min_frequency_hz) * rules.tuning_pixels_per_hz
	var maximum := TuningArcGeometry.equivalent_sweep_from_chord_rad(scale, distance)
	var cumulative: Array[float] = [0.0]
	for point in path.points:
		if not is_finite(point.angle_deg): return {"error": "节点角度必须为有限数值", "node": point.event_id}
		if not angle_allowed(point.angle_deg, path.affinity, rules): return {"error": "Tuning 节点越过生死分界", "node": point.event_id}
	var low := 0.0; var high := 0.0
	for i in range(1, path.points.size()):
		var a := path.points[i - 1]; var b := path.points[i]
		if b.offset_ticks <= a.offset_ticks: return {"error": "Tuning 节点时间必须严格递增", "node": b.event_id}
		var delta := deg_to_rad(wrapf(b.angle_deg - a.angle_deg, -180, 180))
		if absf(delta) < TuningArcGeometry.DEFAULT_MIN_SWEEP_RAD - 0.000001 or absf(delta) > maximum + 0.000001:
			return {"error": "当前规则要求每段角跨度为 28°～%.2f°" % rad_to_deg(maximum), "node": b.event_id}
		var difference := 2.0 * distance * tan(absf(delta) * 0.5) / scale
		var value := cumulative[-1] + difference * signf(delta) * (1.0 if path.affinity == 0 else -1.0)
		cumulative.append(value); low = minf(low, value); high = maxf(high, value)
	if high - low > 1.000001: return {"error": "这条 Tuning 的累计调频超出当前频率范围，请增加折返或减小跨度"}
	var base := inverse_lerp(rules.tuning_min_frequency_hz, rules.tuning_max_frequency_hz, rules.tuning_base_frequency_hz)
	var shift := clampf(base, -low, 1.0 - high)
	for i in cumulative.size(): cumulative[i] = clampf(cumulative[i] + shift, 0.0, 1.0)
	return {"values": cumulative}

static func validate(chart: SongChart, rules: GameplayRuleSet) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var by_id := {}
	for event in ChartEditEvents.all(chart):
		if event.event_id.is_empty() or by_id.has(event.event_id): _issue(issues, event, "对象 ID 为空或重复")
		by_id[event.event_id] = event
	var previous := {}
	var paths := chart.tuning_paths.duplicate()
	paths.sort_custom(func(a, b): return a.tick < b.tick)
	for path in paths:
		if path.affinity not in [0, 1]: _issue(issues, path, "Tuning 必须属于生钟或死钟")
		if path.tick < 0 or path.tick + path.duration_ticks > chart.end_tick: _issue(issues, path, "Tuning 超出谱面起止范围")
		if path.points.is_empty() or path.points[0].offset_ticks != 0: _issue(issues, path, "Tuning 首节点偏移必须为零")
		var ids := {}
		for point in path.points:
			if point.event_id.is_empty() or ids.has(point.event_id): _issue(issues, path, "Tuning 节点 ID 为空或重复", point.event_id)
			ids[point.event_id] = true
		var values := frequency_values(path, rules)
		if values.has("error"): _issue(issues, path, values.error, values.get("node", ""))
		var own = by_id.get(path.hold_id); var support = by_id.get(path.support_hold_id)
		for pair in [[own, path.affinity], [support, 1 - path.affinity]]:
			var note = pair[0]
			if not note is NoteEvent or note.kind != GameplayTypes.NoteKind.HOLD or note.affinity != pair[1]:
				_issue(issues, path, "Tuning 关联的生／死 Hold 缺失或类型不符")
			elif note.tick > path.tick or note.tick + note.duration_ticks < path.tick + path.duration_ticks:
				_issue(issues, path, "Tuning 必须完整位于关联的双 Hold 重合窗口")
		if previous.has(path.affinity) and previous[path.affinity].tick + previous[path.affinity].duration_ticks > path.tick: _issue(issues, path, "同侧 Tuning 不能重叠")
		previous[path.affinity] = path
	for ghost in chart.ghost_events:
		if ghost.tick < 0 or ghost.tick > chart.end_tick: _issue(issues, ghost, "Ghost 超出谱面起止范围")
		if ghost.tuning_ids.size() > 2 or (ghost.tuning_ids.size() == 2 and ghost.tuning_ids[0] == ghost.tuning_ids[1]): _issue(issues, ghost, "Ghost 只能关联每侧各一条 Tuning")
		if ghost.count < 1 or ghost.count > 16: _issue(issues, ghost, "Ghost 数量必须为 1～16")
		var coverage := ChartEditEvents.tuning_at(chart, ghost.tick)
		if ghost.tuning_ids.is_empty() or coverage.is_empty(): _issue(issues, ghost, "Ghost 必须位于 Tuning 窗口并关联 Tuning")
		for id in ghost.tuning_ids:
			if not coverage.has(id): _issue(issues, ghost, "关联 Tuning 已不覆盖此 Ghost；可按当前位置重新关联")
		for id in coverage:
			if not ghost.tuning_ids.has(id): _issue(issues, ghost, "Ghost 需要关联此刻双方的 Tuning")
	return issues

static func _issue(issues: Array[Dictionary], event, message: String, node := "") -> void:
	var tick: int = event.tick
	if event is TuningPathEvent and not node.is_empty():
		for i in event.points.size():
			if event.points[i].event_id == node:
				tick += event.points[i].offset_ticks; message = "节点 %d：%s" % [i + 1, message]; break
	issues.append({"severity": "error", "code": &"authoring.constraint", "message": message, "event_id": event.event_id, "node_id": node, "tick": tick, "track": "tuning_paths" if event is TuningPathEvent else "ghost_events"})

static func project(chart: SongChart, rules: GameplayRuleSet) -> SongChart:
	var result := chart.duplicate(true) as SongChart
	if chart.tuning_paths.is_empty() and chart.ghost_events.is_empty(): return result
	result.tuning_paths.clear(); result.ghost_events.clear()
	# 同一双 Hold 窗口共享 field；相接或相交的窗口合并，节点不会重置基频。
	var intervals: Array[Vector2i] = []
	for path in chart.tuning_paths:
		var own = ChartEditEvents.find(chart, path.hold_id); var other = ChartEditEvents.find(chart, path.support_hold_id)
		intervals.append(Vector2i(maxi(own.tick, other.tick), mini(own.tick + own.duration_ticks, other.tick + other.duration_ticks)))
	intervals.sort_custom(func(a, b): return a.x < b.x)
	var merged: Array[Vector2i] = []
	for interval in intervals:
		if not merged.is_empty() and interval.x <= merged[-1].y: merged[-1].y = maxi(merged[-1].y, interval.y)
		else: merged.append(interval)
	for i in merged.size():
		var field := TuningFieldRegion.new(); field.event_id = "preview_field_%d" % i
		field.tick = merged[i].x; field.duration_ticks = merged[i].y - merged[i].x; result.tuning_fields.append(field)
	for path in chart.tuning_paths:
		var values: Array = frequency_values(path, rules).values
		for i in range(1, path.points.size()):
			var a := path.points[i - 1]; var b := path.points[i]
			var slider := TuningSliderEvent.new()
			slider.event_id = path.event_id + ":" + a.event_id
			slider.affinity = path.affinity; slider.tick = path.tick + a.offset_ticks
			slider.traversal_ticks = b.offset_ticks - a.offset_ticks; slider.traversal_count = 1
			slider.start_value = values[i - 1]; slider.end_value = values[i]
			var delta := wrapf(b.angle_deg - a.angle_deg, -180, 180)
			slider.arc_rotation_deg = wrapf(rad_to_deg(BASE_ANGLE) + a.angle_deg + delta * 0.5 - (-90.0 if path.affinity == 0 else 90.0), -180, 180)
			for field in result.tuning_fields:
				if field.tick <= slider.tick and field.tick + field.duration_ticks >= slider.tick + slider.traversal_ticks: slider.field_id = field.event_id; break
			result.tuning_sliders.append(slider)
	for batch in chart.ghost_events:
		var ghost := SuManifestationEvent.new()
		ghost.event_id = batch.event_id; ghost.tick = batch.tick; ghost.count = batch.count
		# 新编排没有中央生成区限制，使用整个设计画布；旧谱显式区域仍由旧资源保存。
		ghost.spawn_region_normalized = Rect2(0, 0, 1, 1)
		# 旧引擎仅预览显现，不能用旧 group_id 冒充条内共同成绩。
		result.su_manifestations.append(ghost)
	return result
