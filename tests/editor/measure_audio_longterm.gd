extends SceneTree
## 五分钟真实音频驱动录音：同时记录 Transport 时间，检查累计漂移而非只测短音频。
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS; stream.mix_rate = 44100
	var bytes := PackedByteArray(); bytes.resize(44100 * 300 * 2)
	for second in range(5, 300, 10):
		for i in 64: bytes.encode_s16((second * 44100 + i) * 2, 10000 if i < 32 else -10000)
	stream.data = bytes
	var audio = load("res://src/tools/chart_studio/studio_audio.gd").new(); root.add_child(audio)
	audio.set_stream(stream)
	var recorder := AudioEffectRecord.new()
	AudioServer.add_bus_effect(AudioServer.get_bus_index("StudioMusic"), recorder)
	AudioServer.set_bus_volume_db(0, -60)
	recorder.set_recording_active(true)
	var start := Time.get_ticks_usec()
	audio.set_playing(true)
	var trace: Array = []
	while Time.get_ticks_usec() - start < 300500000:
		await create_timer(1.0).timeout
		trace.append({"wall": (Time.get_ticks_usec() - start) / 1000000.0, "transport": audio.position})
		if trace.size() % 60 == 0: print("LONG AUDIO ", trace.size(), " seconds")
	recorder.set_recording_active(false)
	var directory := "user://chart_studio/audio_measure"
	DirAccess.make_dir_recursive_absolute(directory)
	recorder.get_recording().save_to_wav(directory.path_join("longterm.wav"))
	StudioProjectIO.write_json(directory.path_join("longterm.json"), {"rate": 1.0, "output_latency_sec": AudioServer.get_output_latency(), "device_compensation_ms": audio.device_compensation_ms, "trace": trace})
	audio.queue_free(); await process_frame
	print("LONG AUDIO COMPLETE")
	quit()
