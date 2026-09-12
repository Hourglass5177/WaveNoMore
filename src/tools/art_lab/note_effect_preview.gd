extends Node2D

## ArtLab 只编排演示状态；实际材质、光效和裂解复用游戏音符。
const THEME = preload("res://content/stages/s08/stage_visual_theme.tres")
var _entry: VisualAssetEntry
var _notes: Array[GrayboxNoteVisual] = []
var _state: StringName = &"prepare"
var _grade: int = GameplayTypes.JudgmentGrade.PERFECT
var _elapsed := 0.0
var _last_pulse := -1.0

func _ready() -> void:
	if _entry != null: _build()

func configure_from_manifest(entry: VisualAssetEntry) -> void:
	_entry = entry
	for name: String in entry.anchors:
		(get_node(NodePath(name)) as Node2D).position = entry.anchors[name]
	if is_inside_tree(): _build()

func _build() -> void:
	var is_hold := _entry.asset_id == "note_hold"
	for side: int in range(2 if is_hold else 1):
		var note: GrayboxNoteVisual
		if is_hold:
			var hold := GrayboxHoldVisual.new()
			hold.head_texture = THEME.zhu_hold_head_texture
			hold.body_texture = load("res://assets/image/note/hold_body.png")
			note = hold
		else:
			note = GrayboxNoteVisual.new()
			note.tap_texture = THEME.zhu_tap_texture
			note.tap_material = THEME.zhu_tap_material.duplicate(false)
		add_child(note)
		_notes.append(note)
	_reset()

func _reset() -> void:
	_elapsed = 0.0
	_last_pulse = -1.0
	for index: int in _notes.size():
		var note := _notes[index]
		var is_hold := note is GrayboxHoldVisual
		note.reset_for_pool()
		note.prepare({"event_id": "art_note%d" % index, "affinity": index if is_hold else (1 if _entry.asset_id == "note_xuan" else 0), "unit_kind": &"hold" if is_hold else &"tap", "start_us": 0, "end_us": 1000000, "double_tap": true})
		note.position = Vector2(110, -66 + index * 132) if is_hold else Vector2.ZERO
		note.set_approach_progress(1.0)
		if not is_hold: note.rotation = 0.0 if note.affinity == GameplayTypes.Affinity.ZHU else PI
		if is_hold:
			note.body_length = 210.0
			note.set_body_target(210.0); note.advance_body(0.0)

func art_lab_set_state(state: StringName, _payload: Dictionary = {}) -> bool:
	if state not in [&"prepare", &"approach", &"hold", &"release", &"perfect", &"good", &"pass", &"miss"]: return false
	_state = state
	_reset()
	return true

func art_lab_set_judgment(grade: int) -> bool:
	_grade = grade
	return art_lab_set_state(StringName(GameplayTypes.grade_name(grade).to_lower()))

func art_lab_set_progress(pulse: float) -> void:
	var delta := fposmod(pulse - _last_pulse, 1.0) if _last_pulse >= 0.0 else 0.0
	if _elapsed + delta >= 1.0: _reset()
	_last_pulse = pulse
	_elapsed += delta
	for note: GrayboxNoteVisual in _notes:
		note.set_preview_time(_elapsed)
		if note is GrayboxHoldVisual:
			note.set_tuning_glow(_state == &"hold", _elapsed)
			if _state == &"hold":
				note.emit_consumption(note.hold_progress, _elapsed * 0.7, _elapsed)
				note.set_hold_progress(_elapsed * 0.7)
				note.set_body_target(note.body_length * (1.0 - note.hold_progress))
			note.advance_body(delta)
		else:
			note.set_note_glow_time(_elapsed, 1.0 - _elapsed if _state == &"approach" else 2.0)
		if _state == &"miss": note.play_miss()
		if _state in [&"perfect", &"good", &"pass", &"release"] and _elapsed >= 0.10:
			note.play_timing_confirmed(GameplayTypes.JudgmentGrade.GOOD if _state == &"good" else GameplayTypes.JudgmentGrade.PERFECT)
			if _elapsed >= 0.22:
				if note is GrayboxHoldVisual: note.play_hold_finished(_elapsed)
				else: note.play_wave_contact({"contact_us": roundi(_elapsed * 1000000.0), "position": note.global_position})
