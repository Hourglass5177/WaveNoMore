extends SceneTree
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate();workspace.offer_recovery_on_start=false;root.add_child(workspace)
	for frame in 5:await process_frame
	var directory:=ProjectSettings.globalize_path("res://../Levels/output/pack-repeat-test")
	DirAccess.make_dir_recursive_absolute(directory)
	# 相同内容不同路径足以复现版本误判；短文件避免测试无关的大包复制。
	var file:=FileAccess.open(directory.path_join("current.pck"),FileAccess.WRITE);file.store_string("same-package");file.close()
	file=FileAccess.open(directory.path_join("source.pck"),FileAccess.WRITE);file.store_string("same-package");file.close()
	LevelProjectIO.write_json(directory.path_join("test.assetpack.json"),{"format":"minghe-assets","pack":"source.pck","manifest":"res://test-pack.tres"})
	workspace.document.directory=directory
	workspace.document.data.packs=[{"path":"current.pck","manifest":"res://test-pack.tres"}]
	var cursor: int=workspace.document.cursor
	workspace._pending_packs=workspace.document.data.packs.duplicate(true)
	workspace._import_pack_path(directory.path_join("test.assetpack.json"))
	var ok: bool=workspace._pending_packs.is_empty() and workspace.document.cursor==cursor and str(workspace.document.data.packs[0].path)=="current.pck"
	workspace._pending_packs=workspace.document.data.packs.duplicate(true);workspace._apply_pending_packs()
	ok=ok and workspace._pending_packs.is_empty()
	for child in workspace.get_children():
		if child is ConfirmationDialog and child.title=="应用新素材包":ok=false
	print("PACK REPEAT IMPORT ","PASS" if ok else "FAIL")
	workspace.queue_free();await process_frame;quit(0 if ok else 1)
