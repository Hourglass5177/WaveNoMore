extends SceneTree
## 关卡制作的基础语义：定位求值、难度隔离、编辑历史与对象引用。
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(message)

func _run() -> void:
	var doc := LevelDocument.new()
	var first := doc.add_object("sprite")
	var second := doc.add_object("actor")
	var third := doc.add_object("text")
	doc.set_key(first, "position", "song", 0, [0.0, 0.0])
	doc.set_key(first, "position", "song", 1000000, [100.0, 200.0])
	var middle := LevelShowSampler.object_state(doc.data.show, doc.find("objects", first), "song", 500000, "normal")
	check(LevelFormat.vec(middle.position).is_equal_approx(Vector2(50, 100)), "绝对时间插值位置")
	doc.set_key(first, "opacity", "song", 0, 0.25, "hard")
	check(is_equal_approx(float(LevelShowSampler.object_state(doc.data.show, doc.find("objects", first), "song", 0, "normal").opacity), 1.0), "专属轨不污染其他难度")
	check(is_equal_approx(float(LevelShowSampler.object_state(doc.data.show, doc.find("objects", first), "song", 0, "hard").opacity), 0.25), "专属轨在目标难度生效")
	doc.mark_saved()
	doc.delete_objects(PackedStringArray([second]))
	check(doc.dirty and doc.find("objects", second).is_empty(), "删除后待保存")
	doc.undo()
	check(not doc.dirty and doc.entries("objects")[1].id == second and doc.entries("objects")[2].id == third, "撤销删除恢复层级顺序和保存状态")
	doc.copy_objects(PackedStringArray([first])); var pasted := doc.paste_objects()
	check(pasted.size() == 1 and pasted[0] != first, "复制分配新对象标识")
	check(doc.entries("tracks").filter(func(t): return t.object_id == pasted[0]).size() == 2, "复制携带动画轨道")
	doc.undo(); check(doc.find("objects", pasted[0]).is_empty(), "一次撤销移除整组复制")
	var keys := [LevelFormat.key(0, 0.0), LevelFormat.key(1000000, 1.0)]
	keys[0].interpolation = "hold"
	check(is_zero_approx(float(LevelShowSampler.sample_keys(keys, 999999, 0))), "保持插值边界")
	check(is_equal_approx(float(LevelShowSampler.sample_keys(keys, 1000000, 0)), 1.0), "关键帧端点准确")
	keys[0].interpolation = "bezier"
	check(absf(float(LevelShowSampler.sample_keys(keys, 500000, 0)) - 0.5) < 0.0001, "贝塞尔时间轴反解")
	var round_trip: Dictionary = JSON.parse_string(JSON.stringify(doc.data))
	check(LevelFormat.issues(round_trip).is_empty(), "交换文档往返无类型资源残留")
	var group:=doc.add_object("group")
	var child:=doc.find("objects",first).duplicate(true);child.parent_id=group
	doc.replace("放入组","objects",[doc.find("objects",first)],[child])
	doc.copy_objects(PackedStringArray([first]));var copied_child:=doc.paste_objects()
	check(doc.find("objects",copied_child[0]).parent_id==group,"单独复制子对象保留原父组与局部坐标")
	print("LEVEL DOCUMENT TESTS: %d (%d checks)" % [failures, checks])
	quit(failures)
