extends SceneTree
var failures:=0
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var args:=OS.get_cmdline_user_args()
	var output:=ProjectSettings.globalize_path("res://").path_join("../Levels/output/reliability/pack-restart").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	var workspace=load("res://scenes/tools/level_studio/studio.tscn").instantiate();workspace.offer_recovery_on_start=false;workspace.recovery_path=output.path_join("recovery.json");root.add_child(workspace)
	for i in 12:await process_frame
	if "--restart-child" in args:
		var version: String=workspace.assets().entries.get("restart_fixture",VisualAssetEntry.new()).display_name
		var cursor: int=workspace.document.cursor;workspace.document.undo()
		var deferred_restart: bool=workspace.document.cursor==cursor
		LevelProjectIO.write_json(output.path_join("result.json"),{"version":version,"dirty":workspace.document.dirty,"history":cursor,"undo_requires_restart":deferred_restart})
		workspace.queue_free();await process_frame;quit();return
	var packs:=[]
	for version: String in ["A","B"]:
		var manifest:=VisualAssetManifest.new();manifest.manifest_id="restart_fixture"
		var entry:=VisualAssetEntry.new();entry.asset_id="restart_fixture";entry.display_name=version;manifest.entries.append(entry)
		var source:=output.path_join("manifest_"+version+".tres");ResourceSaver.save(manifest,source)
		var relative:="packs/version_"+version+".pck";DirAccess.make_dir_recursive_absolute(output.path_join("packs"))
		var packer:=PCKPacker.new();packer.pck_start(output.path_join(relative));packer.add_file("res://level_restart_fixture/manifest.tres",source);packer.flush()
		packs.append({"path":relative,"manifest":"res://level_restart_fixture/manifest.tres","name":version})
	var level:=LevelFormat.new_level();level.packs=[packs[0]];workspace.document.reset(level,output)
	for i in 6:await process_frame
	if workspace.assets().entries.restart_fixture.display_name!="A":failures+=1
	var candidate: LevelDocument=workspace._history_document();candidate.fields("更新素材包",{"packs":[packs[1]]})
	var session:={"level":candidate.data,"directory":output,"history":candidate.history,"cursor":candidate.cursor,"saved_cursor":candidate.saved_cursor,"workspace":workspace._workspace_snapshot(),"selection":workspace._selection_snapshot(),"clipboard":{},"timeline_clipboard":[]}
	var session_path:=output.path_join("session.json");LevelProjectIO.write_json(session_path,session)
	var result_path:=output.path_join("result.json")
	if FileAccess.file_exists(result_path):DirAccess.remove_absolute(result_path)
	var pid:=OS.create_process(OS.get_executable_path(),PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/editor/run_level_pack_restart_tests.gd","--log-file",output.path_join("child.log"),"--","--level-editor","--restart-child","--resume-level-session",session_path]),false)
	var start:=Time.get_ticks_msec()
	while pid>0 and OS.is_process_running(pid) and Time.get_ticks_msec()-start<15000:await create_timer(0.1).timeout
	var result:=LevelProjectIO.read_json(result_path)
	if result.get("version")!="B" or not result.get("dirty",false) or not result.get("undo_requires_restart",false):failures+=1;printerr("FAIL: restart result ",result)
	if pid>0 and OS.is_process_running(pid):OS.kill(pid)
	print("LEVEL PACK RESTART failures=",failures," result=",JSON.stringify(result));workspace.queue_free();await process_frame;quit(failures)
