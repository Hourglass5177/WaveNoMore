extends SceneTree
const Reference = preload('res://tests/visual/binary_tempo_reference.gd')
func _initialize():
	var rng := RandomNumberGenerator.new(); rng.seed = 1729
	var checks := 0
	for variant in 20:
		var events: Array[TempoEvent] = []
		for i in 12:
			var event := TempoEvent.new(); event.tick = (i-3)*rng.randi_range(60,480); event.bpm = rng.randf_range(30.0,500.0); events.append(event)
		var current := TempoMap.new(); var original := Reference.new()
		var offset := rng.randi_range(-1200,1200); var start := rng.randi_range(-9000000,9000000)
		current.configure(480,offset,events,start); original.configure(480,offset,events,start)
		for i in 150:
			var at := rng.randi_range(-10000000,300000000)
			if i < events.size()*3: at = original.tick_to_us(events[i/3].tick - offset) + i%3-1
			if current.us_to_tick(at) != original.us_to_tick(at):
				push_error('反算差异 %s %s %s' % [at,current.us_to_tick(at),original.us_to_tick(at)]); quit(1); return
			checks += 1
	print('TEMPO INVERSE: ',checks,' exact comparisons passed'); quit()
