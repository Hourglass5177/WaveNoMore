extends CanvasLayer
## 血条位于玩法顶部；长死亡白场在文字与血条下面。
var rows := {}
func display(battle: BossBattleEngine, at: int, flash: float) -> void:
	$WorldFlash/Flash.color.a = clampf(flash,0,1)
	for id in rows.keys():
		if not battle.states.has(id): rows[id].box.queue_free();rows.erase(id)
	for id: String in battle.states:
		var state: Dictionary = battle.states[id]
		if not rows.has(id):
			var box := VBoxContainer.new(); $Rows.add_child(box)
			var label := Label.new(); box.add_child(label)
			var bar := ProgressBar.new(); bar.custom_minimum_size.y=12;bar.show_percentage=false;box.add_child(bar)
			rows[id]={"box":box,"label":label,"bar":bar}
		var status := "尚未配置战斗" if state.maximum==0 else ("破防" if state.hp==0 else ("二阶段" if state.phase_us>=0 else "战斗中"))
		if state.finish_us>=0: status="已击败" if state.hp==0 else "未击败 · 撤退"
		rows[id].label.text = "%s · %s" % [state.name,status]
		rows[id].bar.max_value=maxi(1,state.maximum);rows[id].bar.value=state.hp
		rows[id].box.visible=state.finish_us<0 or at<int(state.finish_us)+int(state.config.death_duration_us)
