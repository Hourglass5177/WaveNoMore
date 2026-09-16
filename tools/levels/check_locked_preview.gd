extends SceneTree
func _initialize() -> void:run.call_deferred()
func run() -> void:
	root.get_node("SaveService").data=root.get_node("SaveService").default_data()
	var pet=load("res://scenes/ui/modals/pet_select_modal.tscn").instantiate();root.add_child(pet)
	for i in 3:
		pet._index=i;pet._show_pet();pet.play_skill();pet._process(1.0)
		assert(pet._clock==0.0 and pet.get_node("%Preview").disabled)
	var card=load("res://scenes/ui/modals/level_card.tscn").instantiate();root.add_child(card)
	card.set_locked(true);card.set_selection_weight(1.0)
	assert(not card.get_node("Flame").visible)
	assert(card.get_node("MonsterIcon").material.get_shader_parameter("locked"))
	card.queue_free();pet.queue_free();await process_frame
	print("LOCKED PREVIEW PASS");quit()
