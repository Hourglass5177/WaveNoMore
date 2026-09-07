extends SceneTree
## 双路总线录音绕过模型，测量音乐与提示起音；不包含扬声器/蓝牙的物理延迟。
var directory := "res://builds/timing-probe"
var pulse_seconds := [0.25, 0.75, 1.25, 1.75, 2.25]
var duration := 2.6
var sample_kind := "pulse"

class ProbeAudio extends StudioAudio:
	var starts := 0
	func _start_streams() -> void:
		starts += 1
		print("CUE START count=", starts, " position=", position, " source_playing=", _player.playing, " skips=", cues.skipped_buffers)
		super._start_streams()
	# 测量复用播放实现，但退出不回写用户试听设置。
	func _exit_tree() -> void:
		cues.stop(); _player.stop()
		AudioServer.remove_bus(_cue_bus); AudioServer.remove_bus(_bus)

func _init() -> void: _run.call_deferred()

func pulse_value(index: int, count: int) -> int:
	# 约 3ms 的带限短脉冲；起音指标另外记录阈值，避免把最大峰值当作敲击时刻。
	return roundi(18000.0 * sin(TAU * 3.0 * index / count) * (1.0 - float(index) / count))

func make_stream(source_rate: int, whole_song: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.mix_rate = source_rate; stream.format = AudioStreamWAV.FORMAT_16_BITS
	var pulse_frames := roundi(source_rate * 0.003)
	var bell: AudioStreamWAV
	if sample_kind == "life": bell = GrayboxClickTrackFactory.create_transient(470, 0.085, 0.25, 0.30)
	elif sample_kind == "death": bell = GrayboxClickTrackFactory.create_transient(315, 0.095, 0.27, 0.55)
	if bell != null: pulse_frames = bell.data.size() / 2
	var frames := roundi(source_rate * duration) if whole_song else pulse_frames
	var bytes := PackedByteArray(); bytes.resize(frames * 2)
	var starts: Array = pulse_seconds if whole_song else [0.0]
	for seconds: float in starts:
		var start := roundi(seconds * source_rate)
		for i in pulse_frames:
			bytes.encode_s16((start + i) * 2, pulse_value(i, pulse_frames) if bell == null else bell.data.decode_s16(i * 2))
	stream.data = bytes
	return stream

func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var args := OS.get_cmdline_user_args()
	var smoke := "--cue-smoke" in args
	var long_run := "--cue-long" in args
	var ui_stall := "--cue-ui-stall" in args
	if "--cue-life" in args: sample_kind = "life"
	if "--cue-death" in args: sample_kind = "death"
	var bells := sample_kind != "pulse"
	var category := "ui-stall" if ui_stall else ("long" if long_run else (sample_kind if bells else ("smoke" if smoke else "pulse")))
	directory = directory.path_join(category)
	if long_run:
		pulse_seconds = [0.25, 60.25, 120.25, 180.25, 240.25, 300.25]
		duration = 300.7
	if ui_stall:
		pulse_seconds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75]
		duration = 3.1
	DirAccess.make_dir_recursive_absolute(directory)
	# 下游总线不会被音乐 PitchShift 重建替换，能完整记录实际重启和欠载。
	var music_capture := AudioServer.bus_count
	AudioServer.add_bus(); AudioServer.set_bus_name(music_capture, &"ProbeMusic")
	var cue_capture := AudioServer.bus_count
	AudioServer.add_bus(); AudioServer.set_bus_name(cue_capture, &"ProbeCues")
	var audio := ProbeAudio.new(); root.add_child(audio)
	audio.device_compensation_ms = 0
	AudioServer.set_bus_send(audio._bus, &"ProbeMusic")
	AudioServer.set_bus_send(audio._cue_bus, &"ProbeCues")
	var music_record := AudioEffectRecord.new(); music_record.format = AudioStreamWAV.FORMAT_16_BITS
	var cue_record := AudioEffectRecord.new(); cue_record.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(music_capture, music_record)
	AudioServer.add_bus_effect(cue_capture, cue_record)
	var master_volume := AudioServer.get_bus_volume_db(0)
	AudioServer.set_bus_volume_db(0, -80)
	var results: Array = []
	var manifest := {"engine": Engine.get_version_info().string, "audio_driver": AudioServer.get_driver_name(), "output_device": AudioServer.output_device, "output_rate": AudioServer.get_mix_rate(), "output_latency_sec": audio.cached_output_latency, "scope": "StudioMusic/StudioCues 经独立下游总线同时录音；Master 静音。源采样率覆盖不等于输出采样率覆盖，不包含物理输出延迟。", "category": category, "expected_pulse_seconds": pulse_seconds, "runs": results}
	manifest["producer"] = "dedicated_thread"
	manifest["ui_stalls_ms"] = [150, 1500] if ui_stall else []
	for source_rate in ([22050] if bells else ([48000] if smoke or long_run or ui_stall else [44100, 48000])):
		audio.set_stream(make_stream(source_rate, true))
		audio.cues.set_sample(&"probe", make_stream(source_rate, false))
		var events: Array[Dictionary] = []
		for seconds: float in pulse_seconds: events.append({"seconds": seconds, "sample": &"probe"})
		audio.cues.set_events(events)
		for fps in ([30] if long_run or ui_stall else ([60] if smoke or bells else [30, 60, 144])):
			Engine.max_fps = fps
			for rate in ([1.0] if smoke or long_run or ui_stall else [0.5, 0.75, 1.0, 1.25, 1.5]):
				audio.seek(0); audio.set_rate(rate)
				var skipped := audio.cues.skipped_buffers
				var rendered := audio.cues.rendered_events
				var starts_before := audio.starts
				var start := Time.get_ticks_usec()
				audio.set_playing(true)
				print("CUE INITIAL capacity=", audio.cues.mixer._capacity, " first=", roundi(0.1 * AudioServer.get_mix_rate()), " available=", audio.cues.mixer._playback.get_frames_available())
				# 总线第一次混音会建立通道效果实例；等待它完成，再启用 Record。
				# 否则新实例会覆盖刚启用的录音状态，造成一条总线空录音。
				await process_frame
				await process_frame
				# 首个脉冲前仍有 250ms 的源空白，两帧等待不会跳过事件。
				# 两条 Record 的起止与同一混音块对齐，录音样本零点一致。
				AudioServer.lock()
				music_record.set_recording_active(true); cue_record.set_recording_active(true)
				AudioServer.unlock()
				var frames: Array[float] = []
				var previous := Time.get_ticks_usec()
				var minute := 0
				var stall_stage := 0
				while float(Time.get_ticks_usec() - start) / 1000000.0 < duration / rate + 0.3:
					await process_frame
					var now := Time.get_ticks_usec()
					frames.append((now - previous) / 1000.0); previous = now
					if audio.cues.mixer._playback != null and frames.size() < 8: print("CUE FILL delta=", frames[-1], " capacity=", audio.cues.mixer._capacity, " available=", audio.cues.mixer._playback.get_frames_available(), " skips=", audio.cues.mixer._playback.get_skips())
					var elapsed := float(now - start) / 1000000
					# 只阻塞 UI 线程；原生音乐与 producer 应继续输出，多个脉冲落在阻塞期间。
					if ui_stall and stall_stage == 0 and elapsed >= 0.4:
						stall_stage = 1; print("CUE UI STALL 150ms"); OS.delay_msec(150)
					elif ui_stall and stall_stage == 1 and elapsed >= 0.8:
						stall_stage = 2; print("CUE UI STALL 1500ms"); OS.delay_msec(1500)
					if long_run and floori(float(now - start) / 60000000) > minute:
						minute += 1
						print("CUE LONG MINUTE ", minute, " skips=", audio.cues.skipped_buffers - skipped, " starts=", audio.starts - starts_before)
				audio.set_playing(false)
				AudioServer.lock()
				music_record.set_recording_active(false); cue_record.set_recording_active(false)
				AudioServer.unlock()
				var name := "source_%d_fps_%d_rate_%.2f" % [source_rate, fps, rate]
				print("CUE SYNC TRACE ", name, " skips=", audio.cues.skipped_buffers - skipped, " rendered=", audio.cues.rendered_events - rendered, " music_effects=", AudioServer.get_bus_effect_count(audio._bus), " driver=", AudioServer.get_driver_name())
				var music_wav := music_record.get_recording()
				var cue_wav := cue_record.get_recording()
				if music_wav == null or cue_wav == null:
					push_error("测量未获得有效双路录音：" + name); quit(1); return
				music_wav.save_to_wav(directory.path_join(name + "_music.wav"))
				cue_wav.save_to_wav(directory.path_join(name + "_cues.wav"))
				frames.sort()
				results.append({"id": name, "kind": sample_kind, "source_rate": source_rate, "requested_fps": fps, "rate": rate, "frame_p50_ms": frames[frames.size() / 2], "frame_p95_ms": frames[floori(frames.size() * 0.95)], "frame_max_ms": frames[-1], "processing_latency_sec": audio.processing_latency, "skipped_buffers": audio.cues.skipped_buffers - skipped, "rendered_events": audio.cues.rendered_events - rendered, "stream_starts": audio.starts - starts_before})
				var file := FileAccess.open(directory.path_join("cue-sync.json"), FileAccess.WRITE)
				file.store_string(JSON.stringify(manifest, "\t")); file.close()
				print("CUE SYNC RECORDED ", name)
	AudioServer.set_bus_volume_db(0, master_volume)
	audio.queue_free(); await process_frame
	AudioServer.remove_bus(cue_capture); AudioServer.remove_bus(music_capture)
	print("CUE SYNC COMPLETE ", results.size())
	quit()
