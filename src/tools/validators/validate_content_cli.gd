## 无界面内容门禁入口：普通模式允许灰盒，传入 --strict-art 时按正式交付标准拒绝占位美术。
extends SceneTree

## 内容包关系校验器；命令行检查与编辑器、测试共用同一套规则。
const ContentPackageValidatorScript := preload("res://src/tools/validators/content_package_validator.gd")
## 美术清单校验器；负责场景节点、状态和占位资产发布门槛。
const ArtManifestValidatorScript := preload("res://src/tools/validators/art_manifest_validator.gd")


## 除 Catalog 已登记关卡外也扫描 stages 目录，避免漏登记内容完全逃过校验。
func _init() -> void:
	var strict_art := "--strict-art" in OS.get_cmdline_user_args()
	var catalog := load("res://content/catalogs/mvp_catalog.tres") as ContentCatalogData
	if catalog != null:
		var registered_stage_ids: Dictionary = {}
		for registered_stage: StageDefinition in catalog.stages:
			if registered_stage == null:
				continue
			registered_stage.resolve_dependencies_sync(ResourceLoader.CACHE_MODE_IGNORE)
			registered_stage_ids[registered_stage.stage_id] = true
		for folder: String in DirAccess.get_directories_at("res://content/stages"):
			var stage_path := "res://content/stages".path_join(folder).path_join("stage_definition.tres")
			if not ResourceLoader.exists(stage_path):
				continue
			var stage := ResourceLoader.load(stage_path, "Resource", ResourceLoader.CACHE_MODE_IGNORE) as StageDefinition
			if stage != null and not registered_stage_ids.has(stage.stage_id):
				stage.resolve_dependencies_sync(ResourceLoader.CACHE_MODE_IGNORE)
				catalog.stages.append(stage)
				registered_stage_ids[stage.stage_id] = true
	var issues: Array[Dictionary] = ContentPackageValidatorScript.validate_catalog(catalog)
	var manifest := load("res://content/visual/graybox_manifest.tres") as VisualAssetManifest
	issues.append_array(ArtManifestValidatorScript.validate(manifest, not strict_art))
	var errors := 0
	var warnings := 0
	for issue: Dictionary in issues:
		var line := "[%s] %s: %s" % [str(issue.get("severity", "info")).to_upper(), issue.get("location", ""), issue.get("message", "")]
		if issue.get("severity") == "error":
			errors += 1
			printerr(line)
		else:
			warnings += 1
			print(line)
	print("CONTENT VALIDATION: %d errors, %d warnings." % [errors, warnings])
	quit(0 if errors == 0 else 1)
