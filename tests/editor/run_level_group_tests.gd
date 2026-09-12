extends SceneTree
var failures:=0
var checks:=0
func _initialize() -> void:_run.call_deferred()
func check(value:bool,label:String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+label)

func _run() -> void:
	var document:=LevelDocument.new()
	var group:=LevelFormat.object("group");group.layer="hud";group.fields.position=[300,400];group.fields.rotation=15;group.fields.scale=[2,1];group.fields.opacity=0.5
	var child:=LevelFormat.object("text");child.parent_id=group.id;child.fields.position=[50,20];child.fields.rotation=25
	var move:=LevelFormat.track(group.id,"position");move.difficulties=["hard"];move.keys=[LevelFormat.key(0,[300,400]),LevelFormat.key(1000000,[600,500])]
	var visibility:=LevelFormat.track(group.id,"visibility","song","visibility");visibility.clips=[LevelFormat.clip(0,"",2000000)];visibility.clips[0].fade_in_us=1000000
	var level:=LevelFormat.new_level();level.show.objects=[group,child];level.show.tracks=[move,visibility];document.reset(level)
	document.copy_objects(PackedStringArray([group.id]));var clones:=document.paste_objects()
	check(clones.size()==2,"复制分组包含子对象")
	check(document.find("objects",clones[1]).parent_id==clones[0],"复制重绑父子关系")
	document.undo()
	var source:Dictionary=document.data.show.duplicate(true)
	var changes:=LevelGroupBake.changes(source,PackedStringArray([group.id]),PackedStringArray(["normal","hard"]))
	document.commit("解组",changes)
	check(document.entries("objects").size()==1 and document.find("objects",child.id).layer=="hud","解组保留 HUD 坐标层")
	for difficulty in ["normal","hard"]:
		var expected:=LevelShowSampler.object_transform(source,child.id,"song",500000,difficulty)
		var actual:=LevelShowSampler.object_transform(document.data.show,child.id,"song",500000,difficulty)
		check(expected.is_equal_approx(actual),"解组保留 "+difficulty+" 非等比旋转组合")
		var appearance:=LevelShowSampler.local_appearance(document.data.show,document.find("objects",child.id),"song",500000,difficulty)
		check(absf(appearance.color.a-0.25)<0.01,"解组保留 "+difficulty+" 分组淡入和透明度")
	document.undo();check(document.data.show==source,"一次撤销恢复所有难度和分组")
	var timeline:=LevelTimeline.new();timeline.tempo=TempoMap.new();timeline.tempo.configure(480,0,[TempoEvent.new()],350000)
	check(timeline.snap(350100)==350000,"拍线吸附使用音乐首拍偏移")
	timeline.free()
	print("LEVEL GROUP TESTS: %d (%d checks)"%[failures,checks]);quit(1 if failures else 0)
