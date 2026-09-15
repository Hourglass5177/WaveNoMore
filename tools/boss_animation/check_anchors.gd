extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	for id: String in ["bat","snake","goat_eye"]:
		var actor=load("res://tools/boss_animation/boss_visual.gd").new();root.add_child(actor);actor.setup(id)
		await process_frame
		actor.sample(0.)
		for item in actor.lights+actor.mouths+actor.eyes:
			print(id," wanted ",item.reference," actual ",actor._point(item)+Vector2(500,450))
		actor.free()
	quit()
