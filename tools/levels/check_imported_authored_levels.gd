extends SceneTree
## 检查游戏目录实际引用的两关，避免只验证编辑器源文件。
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var catalog=load("res://content/catalogs/mvp_catalog.tres")
	for index in 2:
		var stage: StageDefinition=catalog.stages[index]
		stage.resolve_dependencies_sync()
		var show=stage.stage_show
		var object: Dictionary=show.level_data.objects[0]
		print(stage.display_name," ID=",stage.stage_id," BOSS=",object.boss.visual," scale=",object.fields.scale," bindings=",show.level_data.bindings[0].note_ids.size()," packs=",show.asset_packs.size()," cues=",show.level_data.get("scene_cues",[]).size())
		assert(stage.display_name==["钟","火"][index])
		assert(show.level_data.bindings[0].note_ids.size()==[16,36][index])
		if index==0:assert(is_equal_approx(float(object.fields.scale[0]),1.7))
		var library:=LevelAssetLibrary.new()
		library.configure(show.asset_directory,show.asset_packs)
		assert(library.issues.is_empty())
		if index==1:assert(library.background(str(stage.get_meta("level").initial_background))!=null)
	print("内置关卡检查通过")
	quit()
