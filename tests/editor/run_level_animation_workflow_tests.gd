extends SceneTree
var failures:=0
func _initialize() -> void:run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok:failures+=1;printerr("FAIL: "+label)
func run() -> void:
	var output:=ProjectSettings.globalize_path("res://").path_join("../Levels/output/reliability/animation").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	for index in [1,2,10]:
		var file:=FileAccess.open(output.path_join("frame%d.svg"%index),FileAccess.WRITE)
		file.store_string('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32"><rect width="32" height="32" fill="red"/></svg>');file.close()
	var dialog=load("res://scenes/tools/level_studio/animation_import.tscn").instantiate();dialog.directory=output;root.add_child(dialog)
	await dialog.load_images(PackedStringArray([output.path_join("frame10.svg"),output.path_join("frame2.svg"),output.path_join("frame1.svg"),output.path_join("missing.png")]))
	check(dialog.frames.get_frame_count("default")==3 and dialog.get_node("%Missing").get_child_count()==1,"导入列出跳过文件且保留可用帧")
	var list: ItemList=dialog.get_node("%Frames");list.select(0,false);list.select(2,false)
	dialog._name_action(true)
	var prompt: ConfirmationDialog=dialog.get_children().filter(func(node):return node is ConfirmationDialog)[0]
	var edit: LineEdit=prompt.get_children().filter(func(node):return node is LineEdit)[0];edit.text="两帧动作";prompt.confirmed.emit();await process_frame
	check(dialog.frames.has_animation("两帧动作") and dialog.frames.get_frame_count("两帧动作")==2,"所选帧创建独立动作")
	dialog._name_action(false);prompt=dialog.get_children().filter(func(node):return node is ConfirmationDialog)[0]
	edit=prompt.get_children().filter(func(node):return node is LineEdit)[0];edit.text="相纹";prompt.confirmed.emit();await process_frame
	check(dialog.frames.has_animation("相纹") and not dialog.frames.has_animation("两帧动作"),"重命名保留动作帧")
	await dialog.load_images(PackedStringArray([output.path_join("frame2.svg")]),true)
	check(dialog.frames.get_frame_count("相纹")==3 and dialog.frames.get_frame_count("default")==3,"追加不覆盖其他动作")
	dialog._select_frame(1);check(dialog._readout.text.contains("第 2 / 3 帧"),"逐帧读数对应素材帧")
	var imported:=[""];dialog.imported.connect(func(path):imported[0]=path);await dialog._write();await process_frame
	var restored:=LevelAnimationAsset.load_frames(output.path_join(imported[0]))
	check(restored!=null and restored.get_frame_count("相纹")==3 and restored.get_animation_names().size()==2,"多动作导入和重新装配完整")
	print("LEVEL ANIMATION WORKFLOW failures=",failures);quit(failures)
