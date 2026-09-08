class_name StudioPreviewInputs
extends RefCounted
## 只驱动谱面中真实存在的按键。Tuning 追加位移，绝不自行按下/松开 Hold。
static func build(compiled: CompiledChart, rules: GameplayRuleSet) -> Array[SemanticInputSample]:
	var events: Array[Dictionary] = []
	for note in compiled.notes:
		var life: bool = int(note.affinity) == 0
		var release: int = int(note.end_us) if note.unit_kind == &"hold" else int(note.start_us) + 1000
		if note.unit_kind == &"hold":
			for slider in compiled.tuning_sliders:
				if int(slider.end_us) == release: release += 1; break
		events.append({"time": int(note.start_us), "priority": 0, "kind": GameplayTypes.SemanticInputKind.LIFE_A_PRESSED if life else GameplayTypes.SemanticInputKind.DEATH_A_PRESSED})
		events.append({"time": release, "priority": 4, "kind": GameplayTypes.SemanticInputKind.LIFE_A_RELEASED if life else GameplayTypes.SemanticInputKind.DEATH_A_RELEASED})
	var base := inverse_lerp(rules.tuning_min_frequency_hz, rules.tuning_max_frequency_hz, rules.tuning_base_frequency_hz)
	for field in compiled.tuning_fields:
		events.append({"time": int(field.start_us), "priority": 2, "reset": true})
	for slider in compiled.tuning_sliders:
		var side := int(slider.affinity)
		events.append({"time": int(slider.start_us), "priority": 3, "init": true, "side": side, "value": float(slider.start_value)})
		var tick := int(slider.tick)
		while tick < int(slider.end_tick):
			events.append({"time": compiled.tempo_map.tick_to_us(tick) + (1 if tick == int(slider.tick) else 0), "priority": 1, "side": side, "value": ReplayRunner._slider_guide_value(slider, tick)})
			tick += maxi(1, rules.tuning_sample_interval_ticks)
		events.append({"time": int(slider.end_us), "priority": 1, "side": side, "value": ReplayRunner._slider_guide_value(slider, int(slider.end_tick))})
	events.sort_custom(func(a, b): return a.time < b.time if a.time != b.time else (a.priority < b.priority if a.priority != b.priority else int(a.get("side", a.get("kind", 0))) < int(b.get("side", b.get("kind", 0)))))
	var values := Vector2(base, base)
	var result: Array[SemanticInputSample] = []
	for event in events:
		if event.has("reset"): values = Vector2(base, base); continue
		if event.has("init"): values[int(event.side)] = float(event.value); continue
		if event.has("kind"):
			result.append(SemanticInputSample.create(int(event.time), result.size(), int(event.kind))); continue
		var side := int(event.side)
		var delta := Vector2.ZERO; delta[side] = float(event.value) - values[side]
		var sample := SemanticInputSample.create(int(event.time), result.size(), GameplayTypes.SemanticInputKind.TUNING_DISPLACED, delta)
		values[side] += sample.tune_vector[side]; result.append(sample)
	return result
