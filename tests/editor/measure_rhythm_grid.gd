extends SceneTree
## 固定五分钟网格与一万音符，仅测新候选计算和生成查询。
func _init() -> void:
	var doc := StudioDocument.new(); doc.new_project(); doc.chart().end_tick = 288000
	for i in 10000:
		var note := NoteEvent.new(); note.event_id = "measure_%d" % i; note.tick = roundi(i * 28.8); note.affinity = i % 2
		doc.chart().note_events.append(note)
	var started := Time.get_ticks_usec()
	var draft := StudioRhythmTools.generate(doc, Vector2(0, 300), true, 2, [])
	var result := {"generation_ms": (Time.get_ticks_usec() - started) / 1000.0, "generated": draft.notes.size(), "duplicates": draft.duplicates}
	var raw := {"beats": [], "downbeats": [], "range": [0, 300]}
	for i in 600:
		raw.beats.append(i * 0.5)
		if i % 4 == 0: raw.downbeats.append(i * 0.5)
	started = Time.get_ticks_usec()
	for i in 100: StudioRhythmTools.diagnose(raw, 120 + i * 0.001, 0, 4)
	result.candidate_diagnose_mean_ms = (Time.get_ticks_usec() - started) / 100000.0
	StudioProjectIO.write_json("res://builds/rhythm-probe/grid-measurement.json", result)
	print(JSON.stringify(result)); quit()
