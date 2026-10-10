extends Node2D

## 端到端自测：矿洞地图程序化生成。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_mine_gen.tscn
##
## 这里最重要的一条不是"生成出来的图长得对"，而是
## **生成出来的平台玩家真的跳得上去** —— 我原来手写的地图就没做到，
## 平台摆在第 2/4/6 行，而跳跃高度只有 2 格，一个都够不着。
## 那个 bug 藏了十几轮，因为测试只验过"能站在地面上"。

var _fail: int = 0
var _level: MineLevel
var _player: MinePlayer

func _check(label: String, ok: bool) -> void:
	if ok:
		print("PASS  ", label)
	else:
		_fail += 1
		print("FAIL  ", label)

func _step(frames: int) -> void:
	for i in range(frames):
		await get_tree().physics_frame

func _release_all() -> void:
	for a in ["left", "right", "jump"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)

func _ready() -> void:
	MineRun.scene_switch_enabled = false
	MineRun.active = false
	MineRun.entry_slot = 1
	MineRun.depth = 1

	print("--- 可复现性 ---")
	var a1 := MineGen.generate(1001)
	var a2 := MineGen.generate(1001)
	var b1 := MineGen.generate(1002)
	print("  INFO 种子 1001 的第一行平台：", a1[9])
	print("  INFO 种子 1002 的第一行平台：", b1[9])
	_check("同一个种子生成两次完全一样", a1 == a2)
	_check("★ 不同种子生成出来的图不一样", a1 != b1)

	_check("种子由 槽号+层数 决定", MineGen.seed_for(1, 1) != MineGen.seed_for(2, 1))
	_check("同一层同槽号种子稳定", MineGen.seed_for(2, 3) == MineGen.seed_for(2, 3))
	_check("同槽号换层种子不同", MineGen.seed_for(1, 1) != MineGen.seed_for(1, 2))

	print("--- 结构合法性 ---")
	var m := MineGen.generate(4242)
	_check("行数对", m.size() == MineGen.H)
	var widths_ok := true
	for r in m:
		if r.length() != MineGen.W:
			widths_ok = false
	_check("每行宽度一致", widths_ok)

	var ground_ok := true
	for y in range(MineGen.GROUND_ROW, MineGen.H):
		if m[y] != "#".repeat(MineGen.W):
			ground_ok = false
	_check("地面三层是完整实心的（不会掉出去）", ground_ok)

	var spawn_found := false
	for y in range(m.size()):
		if "S" in m[y]:
			spawn_found = true
	_check("有出生点", spawn_found)

	var platform_count := 0
	for r in m:
		platform_count += r.count("=")
	print("  INFO 这张图有 ", platform_count, " 格平台")
	_check("有平台（不是一张空地）", platform_count > 20)

	# 换个种子也应该是合法的
	var bad := 0
	for s in range(1, 40):
		var g := MineGen.generate(s)
		if g.size() != MineGen.H:
			bad += 1
			continue
		for r in g:
			if r.length() != MineGen.W:
				bad += 1
				break
	print("  INFO 抽查 39 个种子，结构有问题的：", bad)
	_check("随便哪个种子生成出来都合法", bad == 0)

	print("--- 关卡用的是生成的图 ---")
	_level = (load("res://Scenes/Mine/mine_level.tscn") as PackedScene).instantiate()
	add_child(_level)
	await _step(2)
	var used := _level.active_map()
	await _step(2)
	_player = _level.get_node("MinePlayer")
	print("  INFO 关卡实际用的第一行平台：", used[9])
	_check("没传自定义地图时用生成的", used == MineGen.generate(MineRun.level_seed()))
	# 自定义地图优先级最高（测试和调试都靠它）
	var custom := PackedStringArray()
	for y in range(MineGen.H):
		custom.append("#".repeat(MineGen.W) if y >= MineGen.GROUND_ROW else " ".repeat(MineGen.W))
	_level.map = custom
	_check("传了自定义地图就优先用它", _level.active_map() == custom)
	_level.map = PackedStringArray()
	await _step(2)

	print("--- ★ 平台够不够得着（真的跳一次）---")
	# 先量出玩家实际能跳多高
	var gap_px: float = float(MineGen.GROUND_ROW - MineGen.PLATFORM_ROWS[0]) * 18.0
	print("  INFO 地面顶面到最下面一层平台的距离 = ", gap_px, " px")
	# 找一根头顶没平台的柱子，免得跳起来撞到东西
	var m2 := _level.active_map()
	var col: int = -1
	for x in range(4, MineGen.W - 4):
		if m2[9][x] == " " and m2[7][x] == " " and m2[5][x] == " ":
			col = x
			break
	_check("找得到一根头顶空的柱子", col >= 0)
	if col >= 0:
		_release_all()
		_player.global_position = Vector2(float(col) * 18.0 + 9.0, 198)
		_player.velocity = Vector2.ZERO
		await _step(10)
		var y0: float = _player.global_position.y
		Input.action_press("jump")
		var min_y: float = y0
		for i in range(40):
			await get_tree().physics_frame
			min_y = minf(min_y, _player.global_position.y)
		Input.action_release("jump")
		await _step(4)
		var rise: float = y0 - min_y
		print("  INFO 实测跳跃高度 = ", snappedf(rise, 0.1), " px（需要 ", gap_px, " px）")
		_check("★ 跳跃高度够得着最下面一层平台", rise >= gap_px)

		# 相邻两层平台之间的间距也要跳得上去
		var step_gap: float = 0.0
		for i in range(1, MineGen.PLATFORM_ROWS.size()):
			var d: float = float(MineGen.PLATFORM_ROWS[i - 1] - MineGen.PLATFORM_ROWS[i]) * 18.0
			step_gap = maxf(step_gap, d)
		print("  INFO 平台层之间最大间距 = ", step_gap, " px")
		_check("★ 层与层之间也跳得上去", rise >= step_gap)

	_release_all()
	print("RESULT fail=", _fail)
	get_tree().quit()
