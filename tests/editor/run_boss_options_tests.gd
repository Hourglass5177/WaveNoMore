extends SceneTree
var failures:=0
func _initialize() -> void:run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1;printerr(label)
func settle() -> void:
	for frame in 5:await process_frame
func run() -> void:
	var output:=ProjectSettings.globalize_path("res://../Levels/output/boss-options")
	var opened:=LevelProjectIO.open_project("res://examples/level-studio/渡口演出/level.json")
	LevelProjectIO.copy_dependencies(LevelProjectIO.dependencies(opened.level,opened.directory),opened.directory,output)
	LevelProjectIO.save(opened.level,output)
	var workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate();workspace.offer_recovery_on_start=false;root.add_child(workspace);await settle()
	workspace._open_path(output.path_join("level.json"));await settle()
	var binding: Dictionary=workspace.document.entries("bindings")[0]
	workspace.select_objects(PackedStringArray([binding.object_id]));workspace.open_boss_binding(binding.id);await settle()
	var panel=workspace.boss_panel
	var cursor: int=workspace.document.cursor
	panel._object_setting("visual","goat");await settle()
	check(workspace.document.cursor==cursor+1,"选择完整表现一次撤销")
	check(workspace.surface.player.objects[binding.object_id].get_node("Content").has_method("sample_show"),"替换为正式完整表现")
	panel._object_setting("health_ratio",0.65);await settle()
	workspace.document.undo();await settle();check(not workspace.document.find("objects",binding.object_id).boss.has("health_ratio"),"撤销恢复继承比例")
	panel._change("flight_speed",500.0);await settle()
	check(workspace.surface.emissions.size()>0,"新路径已编译")
	for path: Dictionary in workspace.surface.emissions.values():check(path.has("arc_profile"),"旧绑定默认使用新路径")
	root.get_texture().get_image().save_png(output.path_join("options-1280.png"))
	panel._content.get_parent().ensure_control_visible(panel._form.get_child(0).get_node("Battle"));await settle()
	root.get_texture().get_image().save_png(output.path_join("battle-controls.png"))
	root.size=Vector2i(1024,720);await settle();root.get_texture().get_image().save_png(output.path_join("options-1024.png"))
	var saved:=LevelProjectIO.save(workspace.document.data,output)
	check(saved.is_empty(),"保存配置")
	var loaded:=LevelProjectIO.open_project(output.path_join("level.json"))
	check(LevelFormat.find(loaded.level.show.objects,binding.object_id).boss.visual=="goat","重新打开保留完整表现选择")
	check(LevelFormat.find(loaded.level.show.bindings,binding.id).flight_speed==500.0,"重新打开保留路径覆盖")
	workspace.queue_free();await settle();print("BOSS OPTIONS failures=",failures);quit(failures)
