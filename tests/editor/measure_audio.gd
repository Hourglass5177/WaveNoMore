extends SceneTree
## 录制音乐总线处理后的持续音，留给频率与延迟分析；不以比例计算冒充实测。
func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 44100
	var bytes := PackedByteArray()
	bytes.resize(44100 * 3 * 2)
	for i in 44100 * 3:
		var value := int(10000 * sin(TAU * 440 * i / 44100.0)) if i > 11025 else 0
		bytes.encode_s16(i * 2, value)
	sound.data = bytes
	var audio = load("res://src/tools/chart_studio/studio_audio.gd").new()
	root.add_child(audio)
	var bus := AudioServer.get_bus_index("StudioMusic")
	var record := AudioEffectRecord.new()
	AudioServer.add_bus_effect(bus, record)
	# 录音在音乐总线内完成，降低实际扬声器音量不改变测量样本。
	AudioServer.set_bus_volume_db(0, -60)
	DirAccess.make_dir_recursive_absolute("user://chart_studio/audio_measure")
	for rate in [0.5, 0.75, 1.0, 1.25, 1.5]:
		audio.set_stream(sound)
		audio.set_rate(rate)
		record.set_recording_active(true)
		audio.set_playing(true)
		await create_timer(3.0 / rate + 0.3).timeout
		record.set_recording_active(false)
		var path := "user://chart_studio/audio_measure/rate_%.2f.wav" % rate
		record.get_recording().save_to_wav(path)
		print("AUDIO RECORD ", ProjectSettings.globalize_path(path))
	audio.queue_free()
	await process_frame
	quit()
