extends SceneTree
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var save=load("res://src/services/save/save_service.gd").new()
	var fresh=save.default_data()
	assert(fresh.pets.is_empty())
	var legacy={"pets":{"nu_tu_fu":{"owned":true,"advanced":true},"yi_huo_she":{"owned":true,"advanced":true},"gui_jin_yang":{"owned":true,"advanced":true}},"equipped_pet_id":"yi_huo_she","stage_results":{"tutorial2":{"cleared":true,"full_combo":true},"level3":{"cleared":true,"all_perfect":true}}}
	var result=save._migrate_and_normalize(legacy)
	assert(result.pets.nu_tu_fu.owned and not result.pets.nu_tu_fu.advanced)
	assert(not result.pets.yi_huo_she.owned)
	assert(result.pets.gui_jin_yang.advanced)
	assert(result.equipped_pet_id.is_empty())
	result.stage_results={}
	assert(save._migrate_and_normalize(result).pets.gui_jin_yang.advanced)
	print("PASS 新存档全锁；清除测试授予；保留正式玄同/至臻；无效装备卸下；迁移不重复")
	save.free();quit()
