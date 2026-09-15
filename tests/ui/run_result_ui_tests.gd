extends SceneTree
## 正式场景、真实奖励保存与渲染检查；由 UI review 提供独立 user://。
var page_scene: PackedScene
var checks := 0
var failures: Array[String] = []
var signals_seen: Array[String] = []

func _init() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func stage_for(id: String) -> StageDefinition:
	var stage: StageDefinition = root.get_node("ContentCatalog").get_stage(id).duplicate(false)
	stage.reward = load(stage.reward_resource_path).duplicate(false)
	return stage

func add_page(stage: StageDefinition, result: Dictionary) -> Control:
	var page := page_scene.instantiate()
	root.add_child(page)
	page.present(stage, result)
	page.next_stage_requested.connect(func(id): signals_seen.append("next:"+id))
	page.retry_requested.connect(func(id): signals_seen.append("retry:"+id))
	page.stage_select_requested.connect(func(): signals_seen.append("exit"))
	return page

func capture(name: String) -> void:
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://builds/result-review/"+name+".png")

func joy(button: int) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventJoypadButton.new()
	event.button_index = button
	Input.parse_input_event(event)
	await process_frame

func run() -> void:
	page_scene = load("res://scenes/screens/result_screen.tscn")
	root.size = Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute("res://builds/result-review")
	var save = root.get_node("SaveService")
	var original: Dictionary = save.data.duplicate(true)
	save.data.pets = {}
	var report := PlanningParameters.read(PlanningParameters.WORKBOOK_PATH)
	check(report.errors.is_empty(), "策划表全部字段可解析：" + str(report.errors))
	var override_reward := RewardDefinition.new()
	PlanningParameters.apply_values(override_reward, "reward:tutorial2", {"values":{"reward:tutorial2/next_stage_id":"s08","reward:tutorial2/fc_grants_base_pet":false}})
	check(override_reward.next_stage_id == "s08" and not override_reward.fc_grants_base_pet, "策划奖励参数应用到资源")
	var bat := stage_for("tutorial2")
	var snake := stage_for("s07")
	var goat := stage_for("s08")
	check(bat.reward.next_stage_id == "s07" and snake.reward.next_stage_id == "s08" and goat.reward.next_stage_id.is_empty(), "真实关卡串联且末关无下一关")
	for stage in [bat, snake, goat]:
		check(stage.reward.fc_grants_base_pet and stage.reward.ap_grants_advanced_pet, "三关收服、进阶规则启用")
	check(bat.reward.pet.display_name == "女土蝠", "随从复用 BOSS 名称")
	var result := {"cleared":true, "score":165467, "soul_fire":87, "grade_counts":{"PERFECT":80,"GOOD":10,"PASS":5,"MISS":5}}
	var page = add_page(bat, result)
	await capture("ordinary")
	check(page.get_node("%HitRate").text == "95.00%" and page.get_node("%PerfectRate").text == "80.00%", "非 Miss 命中率与 Perfect 臻率")
	check(page.get_node("%Reward").text == "女土蝠未收服", "未取得真实奖励不展示已收服")
	check(page.get_node("%Next").has_focus(), "成功时默认焦点为下一关")
	check(not page._mark.visible, "普通成绩无完成标记")
	check(page.get_node("%Perfect").text == "臻  80" and page.get_node("%Good").text == "良  10" and page.get_node("%Pass").text == "过  5" and page.get_node("%Miss").text == "失  5", "正式判定文案统一")
	await joy(JOY_BUTTON_DPAD_RIGHT)
	check(page._retry.has_focus(), "手柄右移到重玩")
	await joy(JOY_BUTTON_DPAD_RIGHT)
	check(page._select.has_focus(), "手柄右移到退出")
	await joy(JOY_BUTTON_DPAD_RIGHT)
	check(page.get_node("%Next").has_focus(), "手柄焦点循环")
	# 本轮成绩先入存档，结算只是读取；重读验证最高状态不会被普通成绩覆盖。
	result.full_combo = true
	result.grade_counts = {"PERFECT":80,"GOOD":20}
	save.record_stage_result(bat, result)
	page.present(bat, result)
	await capture("fc")
	check(page.get_node("%Reward").text == "女土蝠已收服", "玄同授予基础随从")
	result.all_perfect = true
	result.grade_counts = {"PERFECT":100}
	save.record_stage_result(bat, result)
	page.present(bat, result)
	await capture("ap")
	check(page.get_node("%Reward").text == "女土蝠已进阶", "至臻授予进阶随从")
	check(page._mark._glow_material.get_shader_parameter("glow_color") == Color("b985ff"), "至臻紫色外晕")
	check(page._mark._body_material.get_shader_parameter("light_color") == Color("f2e5cb"), "字内保持暖白金粉")
	var count_before := page.get_child_count()
	for i in 12: page.present(bat, result)
	check(page.get_child_count() == count_before, "重复展示不增加节点")
	save.record_stage_result(bat, {"cleared":true,"score":1})
	save.load_or_create()
	check(save.pet_state("nu_tu_fu").get("advanced",false), "保存重开、重复普通通关保留进阶")
	result = {"cleared":false,"grade_counts":{0:2,3:1},"expected_judgment_count":300,"score":1234}
	page.present(bat, result)
	await capture("failed")
	check(page.get_node("%HitRate").text == "66.67%", "失败只按已结算部分计算，兼容枚举键")
	check(not page.get_node("%Next").visible and page._select.has_focus(), "失败隐藏下一关并聚焦退出")
	page.present(goat, {"cleared":true,"score":123456789,"grade_counts":{}})
	await capture("last-zero")
	check(page._summary.text == "123456789" and page.get_node("%HitRate").text == "—", "高分不截断，零分母不显示虚假百分比")
	check(not page.get_node("%Next").visible, "末关没有下一关")
	page.present(bat, {"cleared":true,"full_combo":true,"score":165467,"grade_counts":{"PERFECT":80,"GOOD":20},"pet_name":"女土蝠","bonus_score":3200})
	# 真正创建各档渲染目标，不用窗口尺寸代替实际像素尺寸。
	for resolution in [Vector2i(1280,720),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160),Vector2i(1920,1200)]:
		var view := SubViewport.new()
		view.size = resolution
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(view)
		var sized_page := page_scene.instantiate()
		view.add_child(sized_page)
		sized_page.present(bat, {"cleared":true,"full_combo":true,"all_perfect":true,"score":165467,"soul_fire":100,"grade_counts":{"PERFECT":100},"pet_name":"女土蝠","bonus_score":3200})
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		var image := view.get_texture().get_image()
		image.save_png("res://builds/result-review/size-%dx%d.png" % [resolution.x,resolution.y])
		check(image.get_size() == resolution, "实际渲染尺寸 %s" % resolution)
		var design: Control = sized_page.get_node("Design")
		check(is_equal_approx(design.scale.x,design.scale.y), "等比缩放 %s" % resolution)
		check(design.position.x >= -0.1 and design.position.y >= -0.1, "构图不溢出 %s" % resolution)
		view.queue_free()
		await process_frame
	root.size = Vector2i(1280,720)
	page.configure_external(true)
	page.show_notice("谱面已加入本地目录")
	await capture("trial")
	check(not page.get_node("%Next").visible and not page.get_node("%Reward").visible, "试玩不展示正式串关或奖励")
	check(page._select.text == "结束试玩" and page.get_node("%AddLocal").visible, "临时试玩入口保留")
	page.get_node("%AddLocal").pressed.emit()
	check(page.get_node("%AddLocal").disabled, "加入目录过程中不重复开启弹窗")
	page.restore_external_focus()
	check(not page.get_node("%AddLocal").disabled and page.get_node("%AddLocal").has_focus(), "导入弹窗关闭后可再次操作，恢复原焦点")
	page.configure_external(false)
	check(page._select.text == "返回本地谱面" and not page.get_node("%AddLocal").visible, "本地谱面返回入口")
	page.queue_free()
	await process_frame
	# 验证淡出与重复操作只派发一次；A 真正触发按钮信号。
	page = add_page(bat, {"cleared":true})
	await create_timer(0.3).timeout
	await joy(JOY_BUTTON_A)
	page._leave(&"next")
	await create_timer(0.2).timeout
	check(signals_seen == ["next:s07"], "确认、重复输入只跳转一次下一关")
	page.queue_free()
	await process_frame
	page = add_page(goat, {})
	await create_timer(0.3).timeout
	await joy(JOY_BUTTON_B)
	await create_timer(0.2).timeout
	check(signals_seen.back() == "exit", "手柄返回沿用退出意图")
	page.queue_free()
	await process_frame
	# 用实际透明画布的像素边界验证分数，而不只验证容器坐标。
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800,160)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var score = load("res://src/app/ui/score_label.gd").new()
	score.size = Vector2(800,160)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.add_theme_font_override("font",load("res://assets/fonts/huiwen.otf"))
	score.add_theme_font_size_override("font_size",60)
	viewport.add_child(score)
	for text_score in [0,111111,165467,9999999]:
		score.set_score(text_score)
		await process_frame
		await RenderingServer.frame_post_draw
		var bounds := viewport.get_texture().get_image().get_used_rect()
		check(absf(bounds.get_center().x-400.0) <= 2.0, "实际分数字形居中 %d：%s" % [text_score,bounds])
	viewport.queue_free()
	save.data = original
	save.save_now()
	print("Result UI: %d checks, %d failures" % [checks,failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
