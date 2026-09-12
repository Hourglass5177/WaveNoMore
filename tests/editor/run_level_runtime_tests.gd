extends SceneTree
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: " + message)

func _run() -> void:
	var level := LevelFormat.new_level()
	var object_data := LevelFormat.object("text")
	object_data.fields.text = "演出定位测试"
	level.show.objects.append(object_data)
	var track := LevelFormat.track(object_data.id, "position")
	track.keys = [LevelFormat.key(0, [100.0, 200.0]), LevelFormat.key(2000000, [500.0, 600.0])]
	level.show.tracks.append(track)
	var player := LevelShowPlayer.new(); root.add_child(player)
	player.configure(level.show, "", [], "normal")
	player.advance("song", 1000000, false)
	var forward: Transform2D = player.objects[object_data.id].transform
	player.advance("song", 1800000, false); player.seek("song", 1000000)
	check(player.objects[object_data.id].transform.is_equal_approx(forward), "回拖与正向播放属性一致")
	check(forward.origin.is_equal_approx(Vector2(300, 400)), "对象按绝对时间定位")
	var text_node: RichTextLabel = player.objects[object_data.id].get_node("Content")
	check(text_node.text == "演出定位测试", "HUD 文字由文档驱动")
	var camera := LevelFormat.object("camera"); camera.fields.position = [1160, 540]
	level.show.objects.append(camera)
	player.configure(level.show, "", [], "normal")
	player.seek("song", 1000000)
	check(player.objects[object_data.id].position.is_equal_approx(Vector2(300, 400)), "HUD 不跟随世界镜头移动")
	var folder := "user://level-runtime-test/" + LevelFormat.id("case")
	check(LevelProjectIO.save(level, folder).is_empty(), "允许保存未完成工程")
	var opened := LevelProjectIO.open_project(folder.path_join("level.json"))
	check(opened.error.is_empty() and opened.level.show.objects.size() == 2, "元信息与演出分文件往返读取")
	check(not LevelProjectIO.export_zip(level, folder, folder.path_join("incomplete.zip")).is_empty(), "交付缺失歌曲时提供具体错误")
	var song := {"audio": "test.wav", "charts": [{"path": "chart.json"}]}
	StudioProjectIO.write_json(folder.path_join("song/song.json"), song)
	StudioProjectIO.write_json(folder.path_join("song/chart.json"), {"test": true})
	var wav := FileAccess.open(folder.path_join("song/test.wav"), FileAccess.WRITE); wav.store_buffer(PackedByteArray([1, 2, 3])); wav.close()
	check(LevelProjectIO.export_zip(level, folder, folder.path_join("complete.zip")).is_empty(), "关卡包包含声明依赖")
	var zip := ZIPReader.new(); zip.open(folder.path_join("complete.zip"))
	check(zip.file_exists("song/test.wav") and not zip.file_exists("workspace.json"), "发布包包含音乐且排除工作区")
	zip.close()
	var unpacked := folder.path_join("unpacked")
	check(LevelProjectIO.unpack(folder.path_join("complete.zip"), unpacked).is_empty(), "关卡包可解压")
	check(LevelProjectIO.open_project(unpacked.path_join("level.json")).level == opened.level, "解压后文档一致")
	# 动作结束后恢复基础值，任意定位不依赖曾经经过片段尾部。
	var actor := Node2D.new(); var animator := AnimationPlayer.new(); actor.add_child(animator); root.add_child(actor)
	var library := AnimationLibrary.new(); var animation := Animation.new(); animation.length = 2.0
	var index := animation.add_track(Animation.TYPE_VALUE); animation.track_set_path(index, NodePath(".:position"))
	animation.track_insert_key(index, 0.0, Vector2.ZERO); animation.track_insert_key(index, 2.0, Vector2(200, 100))
	library.add_animation("move", animation); animator.add_animation_library("", library)
	var driver := LevelAnimationDriver.new(); driver.configure(actor)
	var clip := LevelFormat.clip(0); clip.action = "move"; clip.local_us = 1000000; clip.weight = 1.0
	driver.sample([clip], 1000000)
	check(actor.position.is_equal_approx(Vector2(100, 50)), "AnimationPlayer 按目标时间采样")
	driver.sample([], 3000000)
	check(actor.position.is_equal_approx(Vector2.ZERO), "动作结束恢复基础属性")
	actor.queue_free(); player.queue_free()
	await process_frame
	print("LEVEL RUNTIME TESTS: %d (%d checks)" % [failures, checks]); quit(1 if failures else 0)
