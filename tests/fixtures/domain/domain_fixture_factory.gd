class_name DomainFixtureFactory
extends RefCounted

## 玩法逻辑层测试共用的谱面工厂。
## 测试从这里取得最小合法数据，避免每个用例各写一套、彼此含义不一致。


## 返回默认规则的新实例，保证各测试修改规则时不会互相污染。
static func rules() -> GameplayRuleSet:
	return GameplayRuleSet.new()


## 建立带 120 BPM、4/4 拍和稳定身份的最小合法谱面，其余工厂都以它为底。
static func base_chart(chart_id: String = "fixture", end_tick: int = 4800) -> SongChart:
	var chart := SongChart.new()
	chart.chart_id = chart_id
	chart.difficulty_id = "test"
	chart.ppq = SongChart.DEFAULT_PPQ
	chart.end_tick = end_tick
	var tempo := TempoEvent.new()
	tempo.tick = 0
	tempo.bpm = 120.0
	chart.tempo_events = [tempo]
	var meter := MeterEvent.new()
	meter.tick = 0
	meter.numerator = 4
	meter.denominator = 4
	chart.meter_events = [meter]
	return chart


## 同时包含 Tap、双押、Hold、双侧调频、素音凝现和疾振，供编译与完整流程测试复用。
static func all_mechanics_chart() -> SongChart:
	# 事件彼此错开，方便单个用例只观察目标机制，不受别的输入所有者干扰。
	var chart := base_chart("all_mechanics", 4800)
	chart.note_events.append(_note("tap_zhu", 480, GameplayTypes.Affinity.ZHU))
	var chord_life := _note("chord_life", 960, GameplayTypes.Affinity.ZHU)
	chord_life.group_id = "chord_01"
	chord_life.damage_group_id = "chord_01"
	var chord_death := _note("chord_death", 960, GameplayTypes.Affinity.XUAN)
	chord_death.group_id = "chord_01"
	chord_death.damage_group_id = "chord_01"
	chart.note_events.append(chord_life)
	chart.note_events.append(chord_death)
	var hold := _note("hold_death", 1440, GameplayTypes.Affinity.XUAN)
	hold.kind = GameplayTypes.NoteKind.HOLD
	hold.duration_ticks = 480
	chart.note_events.append(hold)

	var field := TuningFieldRegion.new()
	field.event_id = "tuning_field_01"
	field.tick = 2400
	field.duration_ticks = 960
	chart.tuning_fields.append(field)
	var life_slider := _tuning_slider("tuning_01_life", field.event_id, "tuning_01", 2400, GameplayTypes.Affinity.ZHU)
	life_slider.traversal_ticks = 480
	life_slider.traversal_count = 2
	life_slider.start_value = 0.5
	life_slider.end_value = 0.75
	var death_slider := _tuning_slider("tuning_01_death", field.event_id, "tuning_01", 2400, GameplayTypes.Affinity.XUAN)
	death_slider.traversal_ticks = 480
	death_slider.traversal_count = 2
	death_slider.start_value = 0.5
	death_slider.end_value = 0.25
	chart.tuning_sliders = [life_slider, death_slider]
	var su := SuManifestationEvent.new()
	su.event_id = "su_01"
	su.group_id = "tuning_01"
	su.tick = 3360
	su.count = 1
	su.spawn_region_normalized = Rect2(0.35, 0.25, 0.3, 0.5)
	chart.su_manifestations.append(su)

	var rapid := RapidRegion.new()
	rapid.event_id = "rapid_01"
	rapid.damage_group_id = "rapid_01"
	rapid.tick = 3840
	rapid.duration_ticks = 480
	rapid.required_strikes = 8
	rapid.debounce_ms = 35
	rapid.must_alternate = true
	chart.rapid_regions.append(rapid)

	var section := SectionMarker.new()
	section.event_id = "section_intro"
	section.tick = 0
	section.label = "Test"
	chart.sections.append(section)
	return chart


## 以下工厂每次只放一种机制，方便边界测试排除其他输入所有者的影响。
static func one_tap_chart(affinity: int = GameplayTypes.Affinity.ZHU) -> SongChart:
	var chart := base_chart("one_tap", 960)
	chart.note_events.append(_note("tap_only", 480, affinity))
	return chart


static func chord_only_chart() -> SongChart:
	var chart := base_chart("chord_only", 960)
	var first := _note("chord_life", 480, GameplayTypes.Affinity.ZHU)
	var second := _note("chord_death", 480, GameplayTypes.Affinity.XUAN)
	first.group_id = "damage_once"
	second.group_id = "damage_once"
	first.damage_group_id = "damage_once"
	second.damage_group_id = "damage_once"
	chart.note_events = [first, second]
	return chart


static func hold_only_chart() -> SongChart:
	var chart := base_chart("hold_only", 1440)
	var hold := _note("hold_only", 480, GameplayTypes.Affinity.ZHU)
	hold.kind = GameplayTypes.NoteKind.HOLD
	hold.duration_ticks = 480
	chart.note_events = [hold]
	return chart


static func tuning_only_chart() -> SongChart:
	var source := all_mechanics_chart()
	source.chart_id = "tuning_only"
	source.note_events.clear()
	source.rapid_regions.clear()
	var field: TuningFieldRegion = source.tuning_fields[0]
	field.tick = 480
	field.duration_ticks = 480
	for slider: TuningSliderEvent in source.tuning_sliders:
		slider.tick = 480
		slider.traversal_ticks = 240
		slider.traversal_count = 2
	var manifestation: SuManifestationEvent = source.su_manifestations[0]
	manifestation.tick = 960
	source.end_tick = 1440
	return source


static func rapid_only_chart() -> SongChart:
	var source := all_mechanics_chart()
	source.chart_id = "rapid_only"
	source.note_events.clear()
	source.tuning_fields.clear()
	source.tuning_sliders.clear()
	source.su_manifestations.clear()
	var region: RapidRegion = source.rapid_regions[0]
	region.tick = 480
	region.duration_ticks = 480
	region.required_strikes = 2
	region.debounce_ms = 100
	source.end_tick = 1440
	return source


static func _note(event_id: String, tick: int, affinity: int) -> NoteEvent:
	var note := NoteEvent.new()
	note.event_id = event_id
	note.tick = tick
	note.kind = GameplayTypes.NoteKind.TAP
	note.affinity = affinity
	note.duration_ticks = 0
	return note


static func _tuning_slider(event_id: String, field_id: String, group_id: String, tick: int, affinity: int) -> TuningSliderEvent:
	var slider := TuningSliderEvent.new()
	slider.event_id = event_id
	slider.field_id = field_id
	slider.group_id = group_id
	slider.tick = tick
	slider.affinity = affinity
	return slider
