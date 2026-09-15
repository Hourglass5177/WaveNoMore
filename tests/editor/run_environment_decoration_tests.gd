extends SceneTree
## 用教程关真实随机装饰检查换景，覆盖宿主隐藏、恢复和外部对象保留。
var failures:=0
func _initialize() -> void:run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:failures+=1;printerr("FAIL: "+label)
func settle() -> void:
	for frame in 5:await process_frame
func run() -> void:
	var view:=SubViewport.new();view.size=Vector2i(1920,1080);view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var controller:=ParallaxController.new();view.add_child(controller)
	check(controller.configure(load("res://content/stages/tutorial2/background.tres")).is_empty(),"装入带祭品随机装饰的原环境")
	await settle()
	check(not controller._horizontal_views.is_empty(),"测试覆盖真实随机装饰宿主")
	var hosts: Array=controller._horizontal_views.map(func(record):return record.view)
	var actor:=Node2D.new();view.add_child(actor);controller.register_object(actor,0)
	var registered:=controller._objects.keys()
	# 单独隐藏的素材不能在恢复基础场景后被强制显示。
	var ordinary_index:=-1
	for index in controller._configured_objects.size():
		if is_instance_valid(controller._configured_objects[index]):ordinary_index=index;break
	if ordinary_index>=0:controller.set_configured_visible(ordinary_index,false)
	var sequence:=StageEnvironmentSequence.new()
	sequence.build(load("res://tests/fixtures/environment/b.tres"),[],Callable(),"normal",Vector3i(0,10000000,0))
	controller.set_environment(sequence);controller.sample_environment(0);await settle()
	check(hosts.all(func(host):return not host.is_visible_in_tree()),"替换初始环境后旧祭品宿主全部隐藏")
	controller.set_camera_position(Vector2(4000,0));controller.set_song_time(8);await settle()
	check(hosts.all(func(host):return not host.is_visible_in_tree()),"滚动和后续生成装饰不会重新露出旧场景")
	check(controller._objects.keys()==registered and actor.is_inside_tree(),"环境替换保留角色和音符注册")
	if DisplayServer.get_name()!="headless":
		controller.sample_environment(0,Vector2.ZERO);await RenderingServer.frame_post_draw
		var folder:=ProjectSettings.globalize_path("res://../Levels/output/environment-decoration")
		DirAccess.make_dir_recursive_absolute(folder);view.get_texture().get_image().save_png(folder.path_join("replaced.png"))
	controller.set_environment(null);await settle()
	check(hosts.all(func(host):return host.is_visible_in_tree()),"恢复沿用原环境时恢复祭品宿主")
	if ordinary_index>=0:check(not controller.get_configured_object(ordinary_index).visible,"恢复环境保留素材自身的隐藏设置")
	controller.set_environment(sequence);controller.sample_environment(5000000);controller.clear_environment();await settle()
	check(hosts.all(func(host):return host.is_visible_in_tree()),"清除换景安排也恢复基础环境")
	view.queue_free();await settle();print("ENVIRONMENT DECORATION failures=",failures);quit(failures)
