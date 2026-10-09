extends Node2D

## 端到端自测：矿洞与农场的连通（阶段 E）。
## 用法: godot --headless --path . --fixed-fps 60 res://Tests/test_mine_run.tscn
##
## ⚠️ 测试里必须关掉 MineRun.scene_switch_enabled ——
##    否则 finish() 会真的切场景，一切后面就没法继续跑断言了。

var _fail: int = 0
var _level: MineLevel
var _player: MinePlayer
var _enemy: MineEnemy

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
	for a in ["left", "right", "jump", "use_item", "switch_weapon"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)

func _ready() -> void:
	MineRun.scene_switch_enabled = false
	MineRun.active = false
	MineRun.gold = 0
	MineRun.kills = 0

	print("--- 这一趟的状态 ---")
	_check("初始不在洞里", not MineRun.active)
	MineRun.start_run()
	_check("进洞后 active", MineRun.active)
	_check("火把充满", is_equal_approx(MineRun.torch_left, MineRun.TORCH_TIME))
	_check("收获清零", MineRun.gold == 0 and MineRun.kills == 0)

	MineRun.add_gold(5)
	MineRun.add_gold(3)
	MineRun.add_kill()
	print("  INFO 捡了 5+3 金、1 只怪 → gold=", MineRun.gold, " kills=", MineRun.kills)
	_check("金币累加", MineRun.gold == 8)
	_check("击杀累加", MineRun.kills == 1)
	MineRun.add_gold(-5)
	_check("负数被忽略", MineRun.gold == 8)

	print("--- 出洞结算 ---")
	var success_signal := false
	var killed_signal := false
	# 信号用方法接，不用 lambda（lambda 按值捕获局部变量，改了外面看不到）
	MineRun.run_finished.connect(_on_run_finished)
	MineRun.finish(true)
	_check("出洞后 active 关掉", not MineRun.active)
	_check("发了 run_finished 信号", _finished_count == 1)
	_check("结果已暂存", MineRun.has_result())
	var r := MineRun.consume_result()
	print("  INFO 结算：success=", r.get("success"), " gold=", r.get("gold"), " kills=", r.get("kills"))
	_check("结算内容正确", bool(r.get("success")) and int(r.get("gold")) == 8 and int(r.get("kills")) == 1)
	_check("结算只能取一次", not MineRun.has_result())
	_check("再取是空的", MineRun.consume_result().is_empty())
	_check("重复 finish 不会重复结算", _call_finish_again() == false)

	print("--- 矿洞场景 ---")
	MineRun.start_run()
	_level = (load("res://Scenes/Mine/mine_level.tscn") as PackedScene).instantiate()
	add_child(_level)
	await _step(2)
	_level.build()
	await _step(4)
	_player = _level.get_node("MinePlayer")
	_enemy = _level.get_node("EnemyA")

	var torch0: float = MineRun.torch_left
	await _step(30)
	print("  INFO 火把 ", snappedf(torch0, 0.1), " → ", snappedf(MineRun.torch_left, 0.1))
	_check("火把会随时间减少", MineRun.torch_left < torch0)
	_check("火把比例在 0~1 之间", _level.torch_ratio() > 0.0 and _level.torch_ratio() <= 1.0)

	var hud := _level.get_node("MineHud") as MineHud
	var torch_label := _level.get_node("MineHud/TorchLabel") as Label
	print("  INFO ", torch_label.text)
	_check("HUD 显示火把剩余秒数", "火把" in torch_label.text and "秒" in torch_label.text)
	_check("HUD 显示这趟收获", "收获" in torch_label.text)
	_check("HUD 有 4 格技能栏", hud.skill_labels().size() == 4)

	print("--- 打怪掉钱 ---")
	var before_gold: int = MineRun.gold
	var before_kills: int = MineRun.kills
	_enemy.take_damage(99, _player.global_position)
	await _step(3)
	print("  INFO 打死一只后：金币 ", before_gold, " → ", MineRun.gold, "，击杀 ", before_kills, " → ", MineRun.kills)
	_check("击杀计数 +1", MineRun.kills == before_kills + 1)
	var coins := get_tree().get_nodes_in_group("mine_pickup")
	_check("地上掉了一份金币", coins.size() == 1)
	if coins.size() == 1:
		var coin := coins[0] as MinePickup
		# ⚠️ 先记下金额 —— 捡走后这个对象就被释放了，之后不能再读
		var coin_value: int = coin.amount
		print("  INFO 这份金币值 ", coin_value)
		_check("掉的钱和怪的强度挂钩", coin_value > 0)
		_player.global_position = coin.global_position
		await _step(6)
		print("  INFO 捡完金币 = ", MineRun.gold)
		_check("碰到就自动捡走", MineRun.gold == before_gold + coin_value)
		_check("捡完金币从场上消失", get_tree().get_nodes_in_group("mine_pickup").is_empty())

	print("--- 火把烧完 = 自动回农场（收获保留） ---")
	MineRun.start_run()
	MineRun.add_gold(20)
	MineRun.torch_left = 0.05
	await _step(10)
	_check("火把烧完会自动结算", not MineRun.active)
	var r2 := MineRun.consume_result()
	print("  INFO 结算：success=", r2.get("success"), " gold=", r2.get("gold"))
	_check("烧完是成功（收获保留）", bool(r2.get("success")))
	_check("收获原样带回", int(r2.get("gold")) == 20)

	print("--- 在洞里倒下 = 丢掉这趟收获 ---")
	MineRun.start_run()
	MineRun.add_gold(50)
	_player.hp = 1
	_player.take_damage(5, Vector2(0, 0))
	await _step(3)
	_check("倒下会结束这趟", not MineRun.active)
	var r3 := MineRun.consume_result()
	print("  INFO 结算：success=", r3.get("success"), " gold=", r3.get("gold"))
	_check("倒下是失败", not bool(r3.get("success")))
	_check("失败时不带回金币（结算里 gold 仅供参考）", int(r3.get("gold")) == 50)

	print("--- 农场那边的矿洞口 ---")
	var farm := (load("res://Scenes/base_level.tscn") as PackedScene).instantiate()
	add_child(farm)
	var save := farm.get_node("SaveSystem") as SaveSystem
	save.auto_load = false
	save.auto_save_on_dawn = false
	await _step(2)
	var ent := farm.get_node_or_null("level/Static/MineEntrance") as MineEntrance
	_check("农场里摆了矿洞口", ent != null)
	if ent != null:
		var p := farm.get_node("level/Player") as Player
		var land := farm.get_node("Land") as FarmLand
		print("  INFO 玩家出生点 ", p.global_position, "，洞口 ", ent.global_position)
		_check("玩家出生时不在洞口范围内", not ent.is_player_inside())
		_check("不在洞口时按 F 不会进洞", ent.enter_mine() == false)
		_check("也不会误启动一趟", not MineRun.active)

		# ⚠️ 洞口**不能压在农田上** —— 否则站那格按 F 会被洞口分支抢走，种不了地。
		#    （踩过一次：test_farm 的玉米种不下去，报的错跟矿洞毫无关系。）
		var radius: float = 30.0
		var clash: int = 0
		var nearest: float = INF
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for c in land.get_used_cells():
			if not land.is_farmland(c):
				continue
			var w: Vector2 = land.to_global(land.map_to_local(c))
			lo = Vector2(minf(lo.x, w.x), minf(lo.y, w.y))
			hi = Vector2(maxf(hi.x, w.x), maxf(hi.y, w.y))
			var d: float = w.distance_to(ent.global_position)
			nearest = minf(nearest, d)
			if d < radius:
				clash += 1
		print("  INFO 农田范围 x ", lo.x, "~", hi.x, "  y ", lo.y, "~", hi.y)
		print("  INFO 离洞口最近的农田 ", snappedf(nearest, 0.1), " px（要求 > ", radius, "）")
		_check("洞口没有压在任何农田上", clash == 0)

	MineRun.active = false
	MineRun.scene_switch_enabled = true
	_release_all()
	print("RESULT fail=", _fail)
	get_tree().quit()

var _finished_count: int = 0

func _on_run_finished(_success: bool, _gold: int, _kills: int) -> void:
	_finished_count += 1

func _call_finish_again() -> bool:
	var was_active: bool = MineRun.active
	MineRun.finish(true)
	return MineRun.active != was_active
