extends SceneTree
## 原生 Compatibility 验证；使用隔离用户目录，截图及数据只写 builds。
var checks := 0
var failures := 0
var canvas: SubViewport
var captures := "res://builds/ui-review"
var costs: Array[float] = []
func _init() -> void:
	call_deferred("_run")
func check(value: bool, detail: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(detail)
func frames(count: int = 4) -> void:
	for i in count: await process_frame
func shot(name: String, delay: float = 0.22) -> void:
	await create_timer(delay).timeout
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	canvas.get_texture().get_image().save_png(captures+"/"+name+".png")
func mount(path: String) -> Control:
	var ui: Control = load(path).instantiate()
	canvas.add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return ui
func _run() -> void:
	print("UI REVIEW USER DIR: ",OS.get_user_data_dir())
	if not OS.get_user_data_dir().contains("UIReview"):
		push_error("UI 测试需要隔离用户目录，参阅 docs/ui-art-integration.md")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(captures))
	var save = root.get_node("SaveService")
	save.data = save.default_data()
	var settings = root.get_node("SettingsService")
	canvas = SubViewport.new()
	canvas.size = Vector2i(1920,1080)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var backdrop := TextureRect.new()
	backdrop.texture = load("res://assets/image/background/background-fire-deathbk.png")
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.size = Vector2(1920,1080)
	canvas.add_child(backdrop)
	var ui = mount("res://scenes/ui/modals/settings_modal.tscn")
	await frames()
	check(ui._pages[0].visible and not ui._pages[1].visible,"默认声音分类")
	var font: Font = ui.get_theme_default_font()
	for character in "0123456789声音画面校准继续重玩退出基础进阶分辨率毫秒%":
		check(font.has_char(character.unicode_at(0)),"字体字符："+character)
	check(ui.get_node("%Resolution").item_count==5,"现有五档分辨率")
	var old_music: float = settings.music_volume_db
	ui.get_node("%Music").value = -11.5
	ui.select_tab(1)
	check(is_equal_approx(settings.music_volume_db,old_music),"编辑草稿不修改服务")
	ui.select_tab(0)
	check(is_equal_approx(ui.get_node("%Music").value,-11.5),"切分类保留草稿")
	await shot("settings-sound")
	var sound_button: Button = ui.get_node("%Sound")
	var original_position := sound_button.position
	sound_button.grab_focus()
	await create_timer(0.2).timeout
	check(sound_button.get_node("Interaction").amount > 0.99,"手柄焦点展开细光")
	sound_button.button_down.emit()
	await create_timer(0.1).timeout
	check(is_equal_approx(sound_button.scale.x,0.98) and sound_button.position==original_position,"按钮轻压保持布局位置")
	await shot("interaction-button-down",0.01)
	sound_button.button_up.emit()
	await sound_button._motion.finished
	check(sound_button.scale.is_equal_approx(Vector2.ONE),"释放后尺寸归位")
	var music: HSlider = ui.get_node("%Music")
	music.grab_focus()
	await create_timer(0.2).timeout
	check(sound_button.get_node("Interaction").amount < 0.01 and music.get_node("Interaction").amount > 0.99,"焦点离开按钮后细光消退，滑块局部亮起")
	music.value = -12.0
	await shot("interaction-slider",0.05)
	check(music.get_node("Interaction").pulse > 0.0 and is_equal_approx(music.value,-12.0),"滑块反馈不干扰设定值")
	music.value = -11.5
	await create_timer(0.35).timeout
	check(is_zero_approx(music.get_node("Interaction").pulse),"连续操作后短亮结束")
	check(music.get_child_count()==1,"滑块反馈复用一个组件")
	ui.select_tab(1)
	await shot("settings-display")
	ui.select_tab(2)
	await shot("settings-calibration")
	var calibration = ui.get_node("%CalibrationPage")
	var accumulated: bool = Input.use_accumulated_input
	calibration._start_test()
	check(calibration._running,"校准可开始")
	ui.select_tab(0)
	check(not calibration._running and Input.use_accumulated_input==accumulated,"离开校准停止测量且恢复输入")
	calibration._input_offset.value = 23
	await frames()
	var before_offset: int = settings.input_offset_ms
	ui._close()
	check(settings.input_offset_ms==before_offset and is_equal_approx(settings.music_volume_db,old_music),"取消不写设置")
	ui._save_and_close()
	check(is_equal_approx(settings.music_volume_db,-11.5) and settings.input_offset_ms==23,"保存统一提交校准及普通设置")
	settings.load_settings()
	check(is_equal_approx(settings.music_volume_db,-11.5) and settings.input_offset_ms==23,"设置重读一致")
	for size: Vector2i in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160),Vector2i(1800,1200)]:
		canvas.size = size
		await frames()
		var design: Control = ui.get_node("Design")
		check(is_equal_approx(design.scale.x,design.scale.y),"等比布局 %s"%size)
		check(Rect2(Vector2.ZERO,Vector2(size)).encloses(Rect2(design.position,Vector2(1920,1080)*design.scale)),"画布留边 %s"%size)
		await shot("settings-%dx%d"%[size.x,size.y])
	ui.queue_free()
	await frames()
	canvas.size = Vector2i(1920,1080)
	var pause = load("res://scenes/ui/hud/pause_overlay.tscn").instantiate()
	canvas.add_child(pause)
	pause._on_state_changed(0,GameplayTypes.StageState.PAUSED,&"test")
	check(pause.get_node("%Retry").position.x < pause.get_node("%Continue").position.x and pause.get_node("%Continue").position.x < pause.get_node("%Exit").position.x,"重玩、继续、退出的左右顺序")
	await shot("pause")
	pause._on_resume_countdown_changed(1.2)
	check(pause.get_node("%OpenEye").visible and not pause.get_node("%ClosedEye").visible,"恢复睁眼")
	check(pause._title.text=="2","沿用会话倒计时向上取整")
	await shot("pause-countdown")
	check(is_zero_approx(pause._root.get_node("Design/Panel").modulate.a) and is_zero_approx(pause._root.get_node("Dim").modulate.a),"倒计时仅留眼睛，面板与遮罩退场")
	pause.configure_external(true)
	check(pause.get_node("%AddLocal").visible and not pause.get_node("%ExitArt").visible,"试玩附加操作与动态退出文案")
	pause.configure_external(false)
	check(not pause.get_node("%AddLocal").visible,"本地谱面不重复显示导入按钮")
	pause.queue_free()
	await frames()
	# 真实会话验证恢复和重试，不以手工切换 UI 状态代替玩法流程。
	var stage = load("res://scenes/stage/stage_root.tscn").instantiate()
	canvas.add_child(stage)
	var definition := StageDefinition.new()
	definition.stage_id = "ui_pause_test"
	definition.song = SongDefinition.new()
	definition.song.song_id = "ui_pause_test"
	definition.song.audio_stream = CalibrationTapSession.create_reference()
	definition.chart = DomainFixtureFactory.base_chart("ui_pause_test",48000)
	definition.rule_set = DomainFixtureFactory.rules()
	check(stage.load_stage(definition),"真实 StageRoot 加载")
	stage.stage_session.pause_on_focus_loss = false
	await frames()
	check(stage.stage_session.request_pause(&"ui_review"),"真实会话暂停")
	stage.pause_overlay._on_continue_pressed()
	var remaining: float = stage.stage_session._resume_countdown_remaining
	stage.pause_overlay._on_continue_pressed()
	check(stage.stage_session._resume_countdown_remaining==remaining,"重复继续不重启倒计时")
	await create_timer(remaining+0.15).timeout
	check(not stage.pause_overlay._root.visible,"倒计时完成收起暂停")
	stage.stage_session.request_pause(&"ui_review")
	stage.pause_overlay._on_retry_pressed()
	await create_timer(0.22).timeout
	check(stage.stage_session.state==GameplayTypes.StageState.PAUSED,"重玩过渡期间原会话保持暂停")
	check(stage.pause_overlay.get_node("%OpenEye").visible and is_zero_approx(stage.pause_overlay._root.get_node("Design/Panel").modulate.a),"重玩先退面板再睁眼")
	await shot("pause-retry-countdown")
	await create_timer(stage.stage_session.resume_countdown_sec+0.18).timeout
	check(not stage.pause_overlay._root.visible,"真实重试收起暂停")
	stage.stage_session.request_pause(&"ui_review")
	stage.pause_overlay._on_exit_pressed()
	await create_timer(0.2).timeout
	check(stage.stage_session.state!=GameplayTypes.StageState.PAUSED,"真实退出结束暂停")
	stage.queue_free()
	await frames()

	ui = mount("res://scenes/ui/modals/pet_select_modal.tscn")
	await frames()
	var catalog = root.get_node("ContentCatalog")
	for i in 3:
		ui._index = i
		ui._show_pet()
		var entry = ui.entries[i]
		var pet = catalog.get_pet(entry.pet_id)
		check(ui.get_node("%Base").text=="？？？" and ui.get_node("%Advanced").text=="？？？","未解锁技能隐藏："+entry.pet_id)
		check(ui.get_node("%Status").text=="未获得","获得状态不含解锁条件")
		check(ui.get_node("%Equip").disabled,"未获得不能装备："+entry.pet_id)
		await shot("pet-%s-idle"%entry.pet_id)
		check(ui.get_node("%Base").horizontal_alignment==HORIZONTAL_ALIGNMENT_CENTER,"问号在右侧内容区居中")
		check(ui.get_node("%GroundGlow").material.get_shader_parameter("glow_color")==entry.shadow_color,"投影对应原画主色")
		check(ui.get_node("%GroundGlow").get_index()<ui.get_node("%Actor").get_index(),"投影位于随从底层")
		ui.play_skill()
		ui.play_skill()
		check(ui._actor.events.size()==1,"重复点击不重启技能："+entry.pet_id)
		await create_timer(0.3).timeout
		await shot("pet-%s-trigger"%entry.pet_id)
		await create_timer(1.2).timeout
		check(ui._actor.skeleton.get_animation_state().get_track(0).get_animation().get_name()=="idle","技能后返回静息")
	ui._grant(false)
	var pet = catalog.get_pet(ui.entries[ui._index].pet_id)
	check(ui.get_node("%Base").text==pet.base_description and ui.get_node("%Advanced").text=="？？？","基础解锁保留原文，进阶仍隐藏")
	check(ui.get_node("%Status").text=="已获得","已获得状态简洁显示")
	ui._grant(true)
	check(ui.get_node("%Advanced").text==pet.advanced_description,"进阶解锁保留原文")
	check(save.equipped_pet_id()==ui.entries[ui._index].pet_id,"装备生效")
	ui._equip()
	check(save.equipped_pet_id().is_empty(),"卸下生效")
	for i in 12:
		ui.step(1)
		await frames(1)
	check(ui.get_node("%Actor").get_child_count()==1,"反复切换只保留一个动画实例")
	await create_timer(0.3).timeout
	check(is_equal_approx(ui.get_node("%Actor").position.x,960.0) and is_equal_approx(ui.get_node("%Actor").modulate.a,1.0),"快速切换后动效归位")
	ui.set_process(false)
	for i in 120:
		var started := Time.get_ticks_usec()
		ui._process(1.0/60.0)
		costs.append(float(Time.get_ticks_usec()-started)/1000.0)
		await process_frame
	costs.sort()
	var total := 0.0
	for value in costs: total+=value
	var metrics := {"mean_preview_cpu_ms":total/costs.size(),"p95_preview_cpu_ms":costs[int(costs.size()*.95)],"max_preview_cpu_ms":costs.back(),"checks":checks,"failures":failures}
	FileAccess.open(captures+"/metrics.json",FileAccess.WRITE).store_string(JSON.stringify(metrics,"  "))
	ui.queue_free()
	await frames()
	canvas.queue_free()
	await frames()
	print("ART UI TESTS: ", checks, " checks, ", failures, " failures; ",metrics)
	quit(0 if failures==0 else 1)
