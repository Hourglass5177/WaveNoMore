extends SceneTree
## 实际声音服务和标题入口；只改内存状态，不保存玩家设置。
var checks := 0
var failures := 0
var audio_service
var cues: Array[StringName] = []

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	audio_service = root.get_node("MenuAudioService")
	audio_service.ui_sound_played.connect(func(cue: StringName): cues.append(cue))
	check(not audio_service._ambient.playing, "开屏前不预播环境音")
	check(audio_service._ambient.stream.loop, "Ambient1 循环")
	check(is_equal_approx(audio_service._ambient.stream.get_length(), 34.5), "加载指定 Ambient1")
	check(audio_service._ambient.bus == &"Music", "环境音使用现有音乐音量")
	for voice in audio_service._ui_players.values():
		check(voice.bus == &"UI" and voice.max_polyphony == 2, "短音效使用 UI 总线与固定复音上限")
		_check_variations(voice.stream)
	var title = load("res://scenes/screens/title_screen.tscn").instantiate()
	title.show_boot_splash = true
	root.add_child(title)
	check(not audio_service._ambient.playing, "工作室开屏期间保持静音")
	for child in title.get_children():
		if child.scene_file_path == "res://scenes/screens/boot_splash.tscn":
			child.finished.emit()
	check(audio_service._ambient.playing and title.phase == title.Phase.ENTERING,
		"主界面开始显现即播放环境音，早于点击提示")
	await create_timer(title.arrival_duration_sec + title.prompt_delay_sec + title.prompt_fade_sec + 0.1).timeout
	var waiting_position: float = audio_service._ambient.get_playback_position()
	check(waiting_position > 0.0 and cues.is_empty(), "等待点击时环境音持续，尚未播放按钮入场声")
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	title._input(event)
	check(audio_service._ambient.get_playback_position() >= waiting_position and cues.has(&"open"), "点击只播放入场声，环境音不重播")
	await create_timer(0.75).timeout
	check(audio_service._ambient.volume_linear > 0.99, "环境音完成淡入")
	var position: float = audio_service._ambient.get_playback_position()
	audio_service.unlock_menu()
	audio_service._on_route(&"stage_select", {})
	await create_timer(0.08).timeout
	check(audio_service._ambient.get_playback_position() >= position, "重复唤醒与菜单切页不重播")
	check(cues.count(&"open") == 1, "入场声只触发一次")

	var button := Button.new()
	button.name = "Back"
	button.size = Vector2(80,40)
	root.add_child(button)
	audio_service.bind_control(button)
	var connections := button.pressed.get_connections().size()
	audio_service.bind_control(button)
	check(button.pressed.get_connections().size() == connections, "重复装配不叠加声音连接")
	cues.clear()
	button.grab_focus()
	check(cues.is_empty(), "程序恢复焦点不发声")
	button.disabled = true
	button.mouse_entered.emit()
	check(cues.is_empty(), "禁用按钮不发悬停音")
	button.disabled = false
	audio_service._last_cue_usec.clear()
	button.pressed.emit()
	check(cues == [&"cancel"], "返回按钮使用低音反馈")
	button.set_meta("ui_sound", &"none")
	button.pressed.emit()
	check(cues == [&"cancel"], "自定义换页按钮可以关闭默认确认")
	cues.clear()
	audio_service._last_cue_usec.clear()
	for i in 100: audio_service.play_ui(&"adjust")
	# 上一个返回仍在同一帧，细小反馈要让开；下一帧最多触发一次。
	await process_frame
	for i in 100: audio_service.play_ui(&"adjust")
	check(cues.size() <= 1, "连续调整限速，不堆积声音")
	check(audio_service._ui_players.size() == 5, "播放过程复用五个固定播放器")

	var song := SongDefinition.new()
	song.audio_stream = load("res://assets/audio/menu/crafted/confirm.wav")
	song.preview_start_sec = 0.0
	song.preview_duration_sec = 0.5
	audio_service.play_preview(song)
	check(audio_service._ambient.stream_paused and audio_service._player.playing, "试听与环境音互斥")
	await create_timer(0.7).timeout
	check(not audio_service._player.playing and not audio_service._ambient.stream_paused, "试听结束恢复菜单环境")
	audio_service.set_calibrating(true)
	cues.clear()
	audio_service.play_ui(&"confirm")
	check(cues.is_empty() and audio_service._ambient.stream_paused, "校准期间只保留参考音")
	check(audio_service._ui_players.values().all(func(voice): return not voice.playing), "校准清除先前按钮尾音")
	audio_service.set_calibrating(false)
	check(not audio_service._ambient.stream_paused, "校准退出恢复环境")
	audio_service._on_route(&"loading", {})
	await create_timer(0.35).timeout
	check(audio_service._ambient.volume_linear == 0.0 and audio_service._ambient.stream_paused, "加载时完成淡出")
	audio_service._on_route(&"stage_select", {})
	await create_timer(0.1).timeout
	audio_service._on_route(&"stage", {})
	check(audio_service._ambient.volume_linear == 0.0 and audio_service._ambient.stream_paused, "快速进关也不会带入环境音")
	audio_service._on_route(&"result", {})
	check(not audio_service._ambient.stream_paused, "结算回到菜单环境")

	if DisplayServer.get_name() != "headless": await _capture_ui()
	title.queue_free()
	button.queue_free()
	audio_service._on_route(&"stage", {})
	audio_service.set_calibrating(true)
	await create_timer(0.10).timeout
	print("MENU AUDIO: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check_variations(stream: AudioStream) -> void:
	var pool := stream as AudioStreamRandomizer
	check(pool != null and pool.streams_count == 3, "每种按钮装配三种布料录音")
	if pool == null or pool.streams_count != 3: return
	var references: Array[PackedVector2Array] = []
	for i in 3:
		var playback := pool.get_stream(i).instantiate_playback()
		playback.start()
		references.append(playback.mix_audio(1.0, 1024))
		playback.stop()
	check(not references[0].is_empty() and references[0] != references[1]
		and references[1] != references[2] and references[0] != references[2], "三种实际音频内容不同")
	# 直接混出随机播放器的 PCM，对照源录音，验证不是只在资源上写了随机模式。
	var last := -1
	var valid := true
	for i in 32:
		# AudioStreamPlayer 每次 play 建立新 playback，随机器在该阶段选取录音。
		var playback := pool.instantiate_playback()
		playback.start()
		var picked := references.find(playback.mix_audio(1.0, 1024))
		valid = valid and picked >= 0 and picked != last
		last = picked
		playback.stop()
	check(valid, "随机播放使用原录音且连续不重复")


func _capture_ui() -> void:
	# 从实际音频总线采样，确认不仅仅设置了 playing 标志。
	var bus := AudioServer.get_bus_index(&"UI")
	var slot := AudioServer.get_bus_effect_count(bus)
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2.0
	AudioServer.add_bus_effect(bus, capture)
	audio_service._last_cue_usec.clear()
	audio_service.play_ui(&"confirm")
	await create_timer(0.75).timeout
	var frames := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	var pcm := PackedByteArray()
	pcm.resize(frames.size()*4)
	for i in frames.size():
		peak = maxf(peak, maxf(absf(frames[i].x), absf(frames[i].y)))
		pcm.encode_s16(i*4, roundi(clampf(frames[i].x,-1,1)*32767))
		pcm.encode_s16(i*4+2, roundi(clampf(frames[i].y,-1,1)*32767))
	check(peak > 0.01 and peak < 0.99, "实际 UI 总线有声音且未削波")
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = roundi(AudioServer.get_mix_rate())
	wav.data = pcm
	DirAccess.make_dir_recursive_absolute("res://builds/audio-review")
	wav.save_to_wav("res://builds/audio-review/runtime-confirm.wav")
	AudioServer.remove_bus_effect(bus, slot)
