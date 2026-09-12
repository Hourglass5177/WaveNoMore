extends SceneTree
## 中央圈参数映射、缓动、暂停及材质实例隔离；图形模式还检查实际 shader 编译。
var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)

func run() -> void:
	# 延迟加载，确保 --script 入口先完成项目 Autoload 初始化。
	var gate = load("res://src/presentation/vfx/twin_gate_cue_visual.gd").new()
	root.add_child(gate)
	check(gate._edge_distances == Vector2.ONE, "默认 1/1")
	gate.set_bell_held(true, false)
	check(gate._edge_targets == Vector2(1, 0.7), "生钟控制右侧")
	check(gate._move_targets == Vector2.ZERO, "当前配置不移动圆圈")
	gate._advance_circle(0.05)
	var middle: float = gate._edge_distances.y
	check(middle > 0.7 and middle < 0.95, "快速非线性过渡")
	check(gate._edge_distances.x == 1.0, "左侧保持默认")
	gate.set_bell_held(true, false)
	check(gate._edge_distances.y == middle, "重复快照不重置")
	gate._advance_circle(0.0)
	check(gate._edge_distances.y == middle, "暂停不推进")
	gate.set_bell_held(false, false)
	check(gate._move_targets == Vector2.ZERO, "松开恢复位移目标")
	check(gate._edge_distances.y == middle, "松开瞬间连续")
	gate._advance_circle(0.02)
	check(gate._edge_distances.y > middle and gate._edge_distances.y < 1.0, "平滑返回")
	gate._advance_circle(1.0)
	check(gate._edge_distances == Vector2.ONE, "回到精确默认值")
	for state in [Vector2i(0, 1), Vector2i(1, 1)]:
		gate.set_bell_held(state.x == 1, state.y == 1)
		gate._advance_circle(1.0)
		check(gate._edge_distances.is_equal_approx(Vector2(1.0 - state.y * 0.3, 1.0 - state.x * 0.3)), "双侧独立映射")
		check(gate._circle_material.get_shader_parameter("left_edge_distance") == gate._edge_distances.x, "材质左参数")
		check(gate._circle_material.get_shader_parameter("right_edge_distance") == gate._edge_distances.y, "材质右参数")
		check(gate._circle_material.get_shader_parameter("live_move") == gate._circle_moves.x and gate._circle_material.get_shader_parameter("death_move") == gate._circle_moves.y, "材质位移参数")
	var second = load("res://src/presentation/vfx/twin_gate_cue_visual.gd").new()
	root.add_child(second)
	check(second._circle_material != gate._circle_material, "每实例独立材质")
	check(second._edge_distances == Vector2.ONE, "另一实例不受影响")
	gate.clear()
	check(gate._edge_distances == Vector2.ONE and gate._edge_targets == Vector2.ONE and gate._circle_moves == Vector2.ZERO and gate._move_targets == Vector2.ZERO, "清理恢复默认")
	check(gate._center_circle.position == Vector2(960, 540), "中心不变")
	check(is_equal_approx(gate._center_circle.scale.x * gate.CENTER_CIRCLE_DISPLAY_REFERENCE_PX, gate.gate_radius * 2), "圆圈本体显示大小不变")
	check(gate.CENTER_CIRCLE.get_size() == Vector2(528, 528), "四方向扩展 100 像素")
	if DisplayServer.get_name() != "headless":
		second.visible = false
		gate._center_circle.reparent(root)
		gate._center_circle.position = Vector2(320, 180)
		await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://builds/center-circle")
		root.get_texture().get_image().save_png("res://builds/center-circle/default.png")
		gate.set_bell_held(true, false)
		gate._advance_circle(1.0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/center-circle/life.png")
	print("CENTER CIRCLE: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
