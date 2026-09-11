extends SceneTree

## 验证移出原槽位后仍能按阵营触发真实 Spine 动画。
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var presentation := GrayboxStagePresentation.new()
	var scene := load("res://scenes/presentation/actors/lingjun_actor.tscn") as PackedScene
	var slot := Node2D.new()
	root.add_child(slot)
	var life := presentation._instance_if_present(scene, slot)
	var death := presentation._instance_if_present(scene, slot)
	presentation._life_actor = life
	presentation._death_actor = death
	life.reparent(root)
	death.reparent(root)
	presentation._update_actor_attacks(true, false)
	assert(life.get_animation_state().get_track(0) != null)
	assert(death.get_animation_state().get_num_tracks() == 0)
	presentation._update_actor_attacks(true, true)
	assert(death.get_animation_state().get_track(0) != null)
	await process_frame
	await process_frame
	assert(life.get_animation_state().get_track(0).get_track_time() > 0.0)
	var elapsed: float = life.get_animation_state().get_track(0).get_track_time()
	presentation._update_actor_attacks(true, true)
	assert(life.get_animation_state().get_track(0).get_track_time() == elapsed)
	assert(life.get_animation_state().get_track(0).get_loop())
	presentation._update_actor_attacks(false, true)
	var track = life.get_animation_state().get_track(0)
	assert(not track.get_loop())
	assert(death.get_animation_state().get_track(0) != null)
	var duration: float = track.get_animation().get_duration()
	track.set_track_time(duration * 0.5)
	presentation._update_actor_attacks(true, true)
	assert(track.get_loop() and track.get_track_time() == duration * 0.5)
	track.set_track_time(duration * 3.5)
	presentation._update_actor_attacks(false, false)
	assert(is_equal_approx(track.get_track_time(), duration * 0.5))
	assert(not track.get_loop())
	assert(not death.get_animation_state().get_track(0).get_loop())
	track.set_track_time(duration + 0.1)
	presentation._update_actor_attacks(true, false)
	assert(life.get_animation_state().get_track(0).get_track_time() == 0.0)
	presentation.free()
	life.free()
	death.free()
	slot.free()
	print("Lingjun attack: release finishes cycle, repress resumes, completed attack restarts passed")
	quit()
